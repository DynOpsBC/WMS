codeunit 72051 "DOPSWHS Print Dispatcher"
{
    Access = Public;

    procedure PrintLPLabel(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
    var
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        LabelReport: Report "DOPSWHS LP Label";
        PrintNode: Codeunit "DOPSWHS PrintNode Client";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        OutStream: OutStream;
        Zpl: Text;
        ResolvedPrinter: Code[20];
    begin
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');
        Setup.Get('');
        Zpl := LabelReport.BuildZpl(LP);

        if Setup."Print Channel" in [Setup."Print Channel"::SelfHosted, Setup."Print Channel"::AzureDirect] then begin
            GuardLicense().GuardFeature(Enum::"DOPSWHS License Feature"::PrintBridge);
            ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::LpLabel, Copies);
            if ResolvedPrinter = '' then
                Error('No WMS bridge printer is mapped for LP label printing. Configure Device Printer Mapping or pass a Printer Code.');
            SelfHosted.Enqueue(LP."No.", ResolvedPrinter, Enum::"DOPSWHS Print Format"::ZPL, Zpl, Copies);
            exit;
        end;
        if Setup."Print Channel" = Setup."Print Channel"::BCNative then begin
            if not GuiAllowed() then
                Error('Business Central Native cannot deliver a terminal ZPL label. Configure Azure Direct, Self-Hosted or PrintNode.');
        end else
            if Setup."Print Channel" <> Setup."Print Channel"::PrintNode then
                Error('Print channel %1 is not supported for LP labels.', Setup."Print Channel");
        if Copies <= 0 then
            Copies := 1;

        Queue.Init();
        Queue."Source Doc" := LP."No.";
        Queue."Report ID" := Report::"DOPSWHS LP Label";
        Queue."Printer ID" := PrinterId;
        Queue.Channel := Setup."Print Channel";
        Queue."Format" := Enum::"DOPSWHS Print Format"::ZPL;
        Queue.Copies := Copies;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.ZPL.CreateOutStream(OutStream);
        OutStream.WriteText(Zpl);
        Queue.Insert(true);
        if Setup."Print Channel" = Setup."Print Channel"::PrintNode then
            PrintNode.SendPrintJob(Queue, Copies)
        else begin
            Report.Run(Report::"DOPSWHS LP Label", false, false, LP);
            Queue.Status := Queue.Status::Sent;
            Queue.Sent := CurrentDateTime();
            Queue.Modify(true);
        end;
    end;

    procedure PrintItemLabel(var Item: Record Item; PrinterId: Code[50]; Copies: Integer)
    begin
        EnqueueZpl(Item."No.", BuildItemZpl(Item), PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Item, 'Item');
    end;

    procedure PrintBinLabel(var Bin: Record Bin; PrinterId: Code[50]; Copies: Integer)
    begin
        EnqueueZpl(Bin."Code", BuildBinZpl(Bin), PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Bin, 'Bin');
    end;

    /// <summary>
    /// Renders the exact value scanned by a terminal as a one-page PDF and
    /// sends it to the explicitly selected document printer. This deliberately
    /// does not parse GS1/LP/item prefixes: the test output must prove which raw
    /// value reached Business Central from the scanner.
    /// </summary>
    procedure PrintBarcodeTest(PrinterId: Code[50]; BarcodeValue: Text; Copies: Integer): Integer
    var
        BarcodeReport: Report "DOPSWHS Barcode Print Test";
        TempBlob: Codeunit "Temp Blob";
        AzureBridge: Codeunit "DOPSWHS Azure Print Bridge";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        PdfInStream: InStream;
        PdfOutStream: OutStream;
        CleanValue: Text;
        Position: Integer;
        CharacterNumber: Integer;
        JobId: Integer;
    begin
        CleanValue := BarcodeValue.Trim();
        if CleanValue = '' then
            Error('Scan a barcode before starting the print test.');
        if StrLen(CleanValue) > 48 then
            Error('The scanned barcode cannot exceed 48 characters in the printable Code 128 test.');
        for Position := 1 to StrLen(CleanValue) do begin
            CharacterNumber := CleanValue[Position];
            if (CharacterNumber < 32) or (CharacterNumber = 127) then
                Error('The scanned barcode contains an unsupported control character.');
            if CharacterNumber > 126 then
                Error('The printable Code 128 test supports standard ASCII characters only.');
        end;
        if Copies <= 0 then
            Copies := 1;
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');

        EnsureDocumentPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::Receipt);
        BarcodeReport.SetBarcodeValue(CleanValue);
        TempBlob.CreateOutStream(PdfOutStream);
        if not BarcodeReport.SaveAs('', ReportFormat::Pdf, PdfOutStream) then
            Error('The scanned barcode test PDF could not be rendered.');
        if not TempBlob.HasValue() then
            Error('The scanned barcode test produced an empty PDF.');
        Setup.Get('');
        TempBlob.CreateInStream(PdfInStream);
        if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then
            JobId := SelfHosted.EnqueueStreamForImmediateDispatch(
                'BARCODE-TEST',
                Report::"DOPSWHS Barcode Print Test",
                CopyStr(PrinterId, 1, 20),
                Enum::"DOPSWHS Print Format"::PDF,
                PdfInStream,
                Copies,
                '')
        else
            JobId := EnqueuePdf('BARCODE-TEST', Report::"DOPSWHS Barcode Print Test", PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Receipt, PdfInStream);

        // This is an explicit terminal test action. Commit its durable audit row
        // and dispatch it in the same request so the operator does not have to
        // wait for the one-minute recovery worker or press Validate Azure Print.
        // The recurring worker remains the retry/recovery path for failures.
        if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then begin
            Commit();
            AzureBridge.DispatchJob(JobId);
            Commit();
            Queue.Get(JobId);
            if Queue.Status in [Queue.Status::Queued, Queue.Status::Failed] then
                Error('The barcode print job was saved but Azure dispatch failed: %1', Queue."Last Error");
        end;
        exit(JobId);
    end;

    // Item/Bin etiketleri için LP-label ile aynı kanal mantığı; içerik satır-içi
    // ZPL (ayrı Report objesine gerek yok). PrintNode ZPL blob'unu kullanır.
    local procedure EnqueueZpl(SourceDoc: Code[50]; Zpl: Text; PrinterId: Code[50]; Copies: Integer; Usage: Enum "DOPSWHS IWX Report Usage"; LabelName: Text)
    var
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        PrintNode: Codeunit "DOPSWHS PrintNode Client";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        OutStream: OutStream;
        ResolvedPrinter: Code[20];
    begin
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');
        Setup.Get('');

        if Setup."Print Channel" in [Setup."Print Channel"::SelfHosted, Setup."Print Channel"::AzureDirect] then begin
            GuardLicense().GuardFeature(Enum::"DOPSWHS License Feature"::PrintBridge);
            ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Usage, Copies);
            if ResolvedPrinter = '' then
                Error('No WMS bridge printer is mapped for %1 label printing. Configure Device Printer Mapping or pass a Printer Code.', LabelName);
            SelfHosted.Enqueue(SourceDoc, ResolvedPrinter, Enum::"DOPSWHS Print Format"::ZPL, Zpl, Copies);
            exit;
        end;
        if Setup."Print Channel" <> Setup."Print Channel"::PrintNode then
            Error('Inline %1 ZPL labels require Azure Direct, Self-Hosted or PrintNode; Business Central Native has no physical ZPL route.', LabelName);
        if Copies <= 0 then
            Copies := 1;

        Queue.Init();
        Queue."Source Doc" := SourceDoc;
        Queue."Printer ID" := PrinterId;
        Queue.Channel := Setup."Print Channel";
        Queue."Format" := Enum::"DOPSWHS Print Format"::ZPL;
        Queue.Copies := Copies;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.ZPL.CreateOutStream(OutStream);
        OutStream.WriteText(Zpl);
        Queue.Insert(true);
        PrintNode.SendPrintJob(Queue, Copies);
    end;

    local procedure BuildItemZpl(var Item: Record Item): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        exit(
            '^XA^CI28^PW812^LL406' +
            '^FO40,30^A0N,40,40^FH_^FD' + ZplEncoder.EncodeFieldData(Item."No.") + '^FS' +
            '^FO40,80^A0N,28,28^FH_^FD' + ZplEncoder.EncodeFieldData(CopyStr(Item.Description, 1, 42)) + '^FS' +
            '^FO40,130^BY2^BCN,110,Y,N,N^FH_^FD' + ZplEncoder.EncodeFieldData(Item."No.") + '^FS' +
            '^XZ');
    end;

    local procedure BuildBinZpl(var Bin: Record Bin): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        exit(
            '^XA^CI28^PW812^LL406' +
            '^FO40,30^A0N,40,40^FH_^FD' + ZplEncoder.EncodeFieldData(Bin."Location Code" + ' / ' + Bin.Code) + '^FS' +
            '^FO40,90^BY2^BCN,120,Y,N,N^FH_^FD' + ZplEncoder.EncodeFieldData(Bin.Code) + '^FS' +
            '^XZ');
    end;

    /// <summary>
    /// Renders a filtered Business Central report as PDF and routes it through
    /// the same provider queue used by terminal labels. The RecordRef is
    /// mandatory so a report can never accidentally print every record.
    /// </summary>
    procedure PrintReport(SourceDoc: Code[50]; ReportId: Integer; PrinterId: Code[50]; Copies: Integer; Usage: Enum "DOPSWHS IWX Report Usage"; SourceRecord: RecordRef): Integer
    var
        TempBlob: Codeunit "Temp Blob";
        PdfInStream: InStream;
        PdfOutStream: OutStream;
    begin
        if ReportId = 0 then
            Error('A report must be configured for print usage %1.', Usage);
        if SourceRecord.Number() = 0 then
            Error('A source record is required to render report %1.', ReportId);
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');

        EnsureDocumentPrinter(PrinterId, Usage);

        TempBlob.CreateOutStream(PdfOutStream);
        if not Report.SaveAs(ReportId, '', ReportFormat::Pdf, PdfOutStream, SourceRecord) then
            Error('Report %1 could not be rendered as PDF.', ReportId);
        if not TempBlob.HasValue() then
            Error('Report %1 produced an empty PDF.', ReportId);
        TempBlob.CreateInStream(PdfInStream);
        exit(EnqueuePdf(SourceDoc, ReportId, PrinterId, Copies, Usage, PdfInStream));
    end;

    procedure EnsureDocumentPrinter(PrinterId: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage")
    var
        Setup: Record "DOPSWHS Setup";
        Printer: Record "DOPSWHS Printer";
        AzureBridge: Codeunit "DOPSWHS Azure Print Bridge";
        ResolvedPrinter: Code[20];
        EffectiveCopies: Integer;
    begin
        if not Setup.Get('') then
            Error('Advanced WMS Setup must be configured before document printing.');
        case Setup."Print Channel" of
            Setup."Print Channel"::SelfHosted,
            Setup."Print Channel"::AzureDirect:
                begin
                    GuardLicense().GuardFeature(Enum::"DOPSWHS License Feature"::PrintBridge);
                    ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Usage, EffectiveCopies);
                    if ResolvedPrinter = '' then
                        Error('No WMS bridge printer is mapped for %1. Select a document printer or configure Device Printer Mapping.', Usage);
                    Printer.Get(ResolvedPrinter);
                    if Printer."Format" <> Printer."Format"::PDF then
                        Error('Printer %1 is configured for %2. %3 document printing requires a PDF printer.', ResolvedPrinter, Printer."Format", Usage);
                    if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then
                        AzureBridge.ValidateAzurePrinter(Printer);
                end;
            Setup."Print Channel"::PrintNode:
                if PrinterId = '' then
                    Error('A PrintNode printer ID is required for %1 document printing.', Usage);
            else
                Error('Terminal document printing requires Azure Direct, Self-Hosted or PrintNode. BC Native cannot route an API-session PDF to a physical printer.');
        end;
    end;

    procedure IsDocumentPrinterConfigured(PrinterId: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage"): Boolean
    var
        Setup: Record "DOPSWHS Setup";
        Printer: Record "DOPSWHS Printer";
        AzureBridge: Codeunit "DOPSWHS Azure Print Bridge";
        ResolvedPrinter: Code[20];
    begin
        if not Setup.Get('') then
            exit(false);
        case Setup."Print Channel" of
            Setup."Print Channel"::SelfHosted,
            Setup."Print Channel"::AzureDirect:
                begin
                    ResolvedPrinter := ResolveConfiguredSelfHostedPrinter(PrinterId, Usage);
                    if ResolvedPrinter = '' then
                        exit(false);
                    if not Printer.Get(ResolvedPrinter) then
                        exit(false);
                    if Printer."Format" <> Printer."Format"::PDF then
                        exit(false);
                    if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then begin
                        if not AzureBridge.TryValidateAzurePrinter(Printer) then begin
                            ClearLastError();
                            exit(false);
                        end;
                    end;
                    exit(true);
                end;
            Setup."Print Channel"::PrintNode:
                exit(PrinterId <> '');
            else
                exit(false);
        end;
    end;

    [Obsolete('Use PrintReport with a filtered RecordRef and explicit usage/printer.', '1.13')]
    procedure QueueReport(SourceDoc: Code[50]; ReportId: Integer)
    begin
        Error('QueueReport can no longer create an unfiltered, empty print job. Use PrintReport with a filtered RecordRef.');
    end;

    local procedure EnqueuePdf(SourceDoc: Code[50]; ReportId: Integer; PrinterId: Code[50]; Copies: Integer; Usage: Enum "DOPSWHS IWX Report Usage"; PdfStream: InStream): Integer
    var
        Setup: Record "DOPSWHS Setup";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        ResolvedPrinter: Code[20];
    begin
        Setup.Get('');
        case Setup."Print Channel" of
            Setup."Print Channel"::SelfHosted,
            Setup."Print Channel"::AzureDirect:
                begin
                    GuardLicense().GuardFeature(Enum::"DOPSWHS License Feature"::PrintBridge);
                    ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Usage, Copies);
                    if ResolvedPrinter = '' then
                        Error('No WMS bridge printer is mapped for %1. Configure Device Printer Mapping or pass a Printer Code.', Usage);
                    exit(SelfHosted.EnqueueStream(SourceDoc, ReportId, ResolvedPrinter, Enum::"DOPSWHS Print Format"::PDF, PdfStream, Copies, ''));
                end;
            Setup."Print Channel"::PrintNode:
                begin
                    if Copies <= 0 then
                        Copies := 1;
                    exit(EnqueuePrintNodePdf(SourceDoc, ReportId, PrinterId, Copies, PdfStream));
                end;
            else
                Error('Terminal document printing requires Azure Direct, Self-Hosted or PrintNode. BC Native cannot route an API-session PDF to a physical printer.');
        end;
    end;

    local procedure EnqueuePrintNodePdf(SourceDoc: Code[50]; ReportId: Integer; PrinterId: Code[50]; Copies: Integer; PdfStream: InStream): Integer
    var
        Queue: Record "DOPSWHS Print Job Queue";
        PrintNode: Codeunit "DOPSWHS PrintNode Client";
        TempBlob: Codeunit "Temp Blob";
        BufferInStream: InStream;
        BufferOutStream: OutStream;
        QueueOutStream: OutStream;
    begin
        if PrinterId = '' then
            Error('A PrintNode printer ID is required for document printing.');
        TempBlob.CreateOutStream(BufferOutStream);
        CopyStream(BufferOutStream, PdfStream);
        if not TempBlob.HasValue() then
            Error('The PDF print payload is empty.');

        Queue.Init();
        Queue."Source Doc" := SourceDoc;
        Queue."Report ID" := ReportId;
        Queue."Printer ID" := PrinterId;
        Queue.Channel := Queue.Channel::PrintNode;
        Queue."Format" := Enum::"DOPSWHS Print Format"::PDF;
        Queue.Copies := Copies;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue."Payload Size" := TempBlob.Length();
        TempBlob.CreateInStream(BufferInStream);
        Queue.ZPL.CreateOutStream(QueueOutStream);
        CopyStream(QueueOutStream, BufferInStream);
        Queue.Insert(true);
        PrintNode.SendPrintJob(Queue, Copies);
        exit(Queue."Job ID");
    end;

    local procedure GuardLicense(): Codeunit "DOPSWHS License Mgmt"
    var
        License: Codeunit "DOPSWHS License Mgmt";
    begin
        exit(License);
    end;

    local procedure ResolveSelfHostedPrinter(Candidate: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage"; var Copies: Integer): Code[20]
    var
        Printer: Record "DOPSWHS Printer";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        ResolvedCode: Code[20];
        RequestedCopies: Integer;
    begin
        if Candidate <> '' then begin
            if StrLen(Candidate) > MaxStrLen(Printer."Code") then
                Error('Printer code %1 exceeds the supported length.', Candidate);
            if not Printer.Get(CopyStr(Candidate, 1, MaxStrLen(Printer."Code"))) then
                Error('Printer %1 is not registered.', Candidate);
            if not Printer.Active then
                Error('Printer %1 is inactive.', Candidate);
            if Copies <= 0 then
                Copies := Printer."Default Copies";
            if Copies <= 0 then
                Copies := 1;
            if Copies > 10 then
                Error('A print job cannot exceed 10 copies.');
            exit(Printer."Code");
        end;
        RequestedCopies := Copies;
        if not SelfHosted.ResolvePrinterAndCopies(CopyStr(UserId(), 1, 50), Usage, RequestedCopies, ResolvedCode, Copies) then
            exit('');
        exit(ResolvedCode);
    end;

    local procedure ResolveConfiguredSelfHostedPrinter(Candidate: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage"): Code[20]
    var
        Printer: Record "DOPSWHS Printer";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        ResolvedCode: Code[20];
    begin
        if Candidate <> '' then begin
            if StrLen(Candidate) > MaxStrLen(Printer."Code") then
                exit('');
            ResolvedCode := CopyStr(Candidate, 1, MaxStrLen(Printer."Code"));
        end else
            ResolvedCode := SelfHosted.ResolvePrinter(CopyStr(UserId(), 1, 50), Usage);
        if (ResolvedCode = '') or (not Printer.Get(ResolvedCode)) or (not Printer.Active) then
            exit('');
        exit(ResolvedCode);
    end;
}
