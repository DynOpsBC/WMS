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
        AzureBridge: Codeunit "DOPSWHS Azure Print Bridge";
        TempBlob: Codeunit "Temp Blob";
        ZplInStream: InStream;
        OutStream: OutStream;
        Zpl: Text;
        ResolvedPrinter: Code[20];
        JobId: Integer;
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
            if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then begin
                TempBlob.CreateOutStream(OutStream, TextEncoding::UTF8);
                OutStream.WriteText(Zpl);
                TempBlob.CreateInStream(ZplInStream);
                JobId := SelfHosted.EnqueueStreamForImmediateDispatch(
                    LP."No.",
                    Report::"DOPSWHS LP Label",
                    ResolvedPrinter,
                    Enum::"DOPSWHS Print Format"::ZPL,
                    ZplInStream,
                    Copies,
                    '');
                // The LP button is an explicit operator action: persist the job,
                // dispatch it now, and leave the recurring worker as recovery.
                Commit();
                AzureBridge.DispatchJob(JobId);
                Commit();
                Queue.Get(JobId);
                if Queue.Status in [Queue.Status::Queued, Queue.Status::Failed] then
                    Error('The LP label job was saved but Azure dispatch failed: %1', Queue."Last Error");
            end else
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
    var
        Printer: Record "DOPSWHS Printer";
    begin
        if Printer.Get(PrinterId) then
            if Printer."Format" = Printer."Format"::PDF then begin
                PrintBarcodeDocument(PrinterId, Item."No.", Copies, Item."No.", 'URUN ETIKETI', Item.Description + ' | ' + Item."Base Unit of Measure");
                exit;
            end;
        EnqueueZpl(Item."No.", BuildItemZpl(Item), PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Item, 'Item');
    end;

    /// <summary>
    /// Prints the material-identification label(s) (MTE) of one LP. The printer
    /// decides the format: a ZPL label printer (the field's 4 x 2 inch stock)
    /// gets one ZPL MTE per item group, exactly as before 1.14.1.37; a PDF
    /// document printer gets the approved 10 x 8 cm RDLC report through the
    /// Windows driver route. A missing document printer therefore never blocks
    /// the label printer that the terminals already use.
    /// </summary>
    procedure PrintPalletItemLabels(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
    begin
        PrintPalletItemLabelsWithOptions(LP, PrinterId, Copies, '');
    end;

    /// <summary>
    /// OptionsJson (terminal "MTE Yazdır" ekranı): inspectorEmployeeNo,
    /// supplierLotNo, qcEmployeeNo, qcApprovalDate (yyyy-MM-dd), documentNo,
    /// revisionNo, revisionDate (yyyy-MM-dd). Used only by the customer report
    /// route; the ZPL label has no room for them.
    /// </summary>
    procedure PrintPalletItemLabelsWithOptions(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer; OptionsJson: Text)
    var
        TargetPrinter: Code[50];
    begin
        TargetPrinter := ResolvePalletItemLabelPrinter(PrinterId);
        if PrinterIsPdf(TargetPrinter) then
            PrintPalletItemReport(LP, TargetPrinter, Copies, OptionsJson)
        else
            PrintPalletItemZplLabels(LP, TargetPrinter, Copies, OptionsJson);
    end;

    /// <summary>
    /// Explicit printer wins. Without one, the device's label mapping is tried
    /// first, then its document mapping. Empty lets the ZPL route raise its
    /// own "no label printer mapped" error, which the terminal explains.
    /// </summary>
    local procedure ResolvePalletItemLabelPrinter(PrinterId: Code[50]): Code[50]
    var
        Setup: Record "DOPSWHS Setup";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        ResolvedCode: Code[20];
        EffectiveCopies: Integer;
    begin
        if PrinterId <> '' then
            exit(PrinterId);
        if not Setup.Get('') then
            exit('');
        if not (Setup."Print Channel" in [Setup."Print Channel"::SelfHosted, Setup."Print Channel"::AzureDirect]) then
            exit('');
        if SelfHosted.ResolvePrinterAndCopies(CopyStr(UserId(), 1, 50), Enum::"DOPSWHS IWX Report Usage"::LpLabel, 0, ResolvedCode, EffectiveCopies) then
            exit(ResolvedCode);
        if SelfHosted.ResolvePrinterAndCopies(CopyStr(UserId(), 1, 50), Enum::"DOPSWHS IWX Report Usage"::Receipt, 0, ResolvedCode, EffectiveCopies) then
            exit(ResolvedCode);
        exit('');
    end;

    local procedure PrinterIsPdf(PrinterId: Code[50]): Boolean
    var
        Printer: Record "DOPSWHS Printer";
    begin
        if (PrinterId = '') or (StrLen(PrinterId) > MaxStrLen(Printer.Code)) then
            exit(false);
        if not Printer.Get(CopyStr(PrinterId, 1, MaxStrLen(Printer.Code))) then
            exit(false);
        exit(Printer."Format" = Printer."Format"::PDF);
    end;

    /// <summary>
    /// The approved 10 x 8 cm MTE RDLC (one page per LP) as a PDF document.
    /// </summary>
    local procedure PrintPalletItemReport(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer; OptionsJson: Text)
    var
        ReportLP: Record "DOPSWHS LP Header";
        SourceRecord: RecordRef;
        CustomerReportId: Integer;
    begin
        // BADE: the customer's own MTE report (Setup "MTE Report ID", e.g.
        // BadeProduction 60150) runs on the pallet's source item ledger
        // entries with the operator's extra fields. Its BC-selected layout is
        // what the customer already prints from the client.
        if ResolveCustomerMteReport(CustomerReportId) then begin
            if not CollectLpSourceEntries(LP, SourceRecord) then
                Error(MteNoSourceEntryErr, LP."No.");
            PrintReportWithParameters(
                LP."No.",
                CustomerReportId,
                BuildMteParameters(CustomerReportId, LP, OptionsJson),
                PrinterId,
                Copies,
                Enum::"DOPSWHS IWX Report Usage"::Receipt,
                SourceRecord);
            exit;
        end;
        ReportLP := LP;
        ReportLP.SetRecFilter();
        SourceRecord.GetTable(ReportLP);
        PrintReport(
            LP."No.",
            Report::"DOPSWHS MTE LP Report",
            PrinterId,
            Copies,
            Enum::"DOPSWHS IWX Report Usage"::Receipt,
            SourceRecord);
    end;

    local procedure ResolveCustomerMteReport(var ReportId: Integer): Boolean
    var
        Setup: Record "DOPSWHS Setup";
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        Clear(ReportId);
        if not Setup.Get('') then
            exit(false);
        if Setup."MTE Report ID" = 0 then
            exit(false);
        if not AllObjWithCaption.Get(AllObjWithCaption."Object Type"::Report, Setup."MTE Report ID") then
            exit(false);
        ReportId := Setup."MTE Report ID";
        exit(true);
    end;

    /// <summary>
    /// The item ledger entries the pallet was received on: the LP lines' source
    /// entries, else the entries stamped with this LP number.
    /// </summary>
    local procedure CollectLpSourceEntries(var LP: Record "DOPSWHS LP Header"; var SourceRecord: RecordRef): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        EntryNos: List of [Integer];
        EntryNo: Integer;
        FilterText: Text;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Source Item Ledger Entry No.", '<>0');
        if LPLine.FindSet() then
            repeat
                if not EntryNos.Contains(LPLine."Source Item Ledger Entry No.") then
                    EntryNos.Add(LPLine."Source Item Ledger Entry No.");
            until LPLine.Next() = 0;
        if EntryNos.Count() = 0 then begin
            ItemLedgerEntry.SetRange("DOPSWHS LP No.", LP."No.");
            if ItemLedgerEntry.FindSet() then
                repeat
                    EntryNos.Add(ItemLedgerEntry."Entry No.");
                until ItemLedgerEntry.Next() = 0;
        end;
        if EntryNos.Count() = 0 then
            exit(false);
        foreach EntryNo in EntryNos do begin
            if FilterText <> '' then
                FilterText += '|';
            FilterText += Format(EntryNo);
        end;
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetFilter("Entry No.", FilterText);
        SourceRecord.GetTable(ItemLedgerEntry);
        exit(true);
    end;

    /// <summary>
    /// Request-page values for the customer report as BC's ReportParameters
    /// XML. Control names follow BadeProduction report 60150; dates use the XML
    /// (yyyy-MM-dd) format the request page stores.
    /// </summary>
    local procedure BuildMteParameters(ReportId: Integer; var LP: Record "DOPSWHS LP Header"; OptionsJson: Text): Text
    var
        Options: JsonObject;
        Xml: Text;
    begin
        if (OptionsJson <> '') and not Options.ReadFrom(OptionsJson) then
            Error(MteOptionsInvalidErr);
        Xml := '<?xml version="1.0" standalone="yes"?>' +
            '<ReportParameters id="' + Format(ReportId) + '"><Options>' +
            XmlField('LpNoFilterReq', LP."No.") +
            XmlField('InspectorEmployeeNo', JsonText(Options, 'inspectorEmployeeNo')) +
            XmlField('TedarikciLotu', JsonText(Options, 'supplierLotNo')) +
            XmlField('QualityControlEmployeeNo', JsonText(Options, 'qcEmployeeNo')) +
            XmlField('QualityControlApprovalDate', JsonDateText(Options, 'qcApprovalDate')) +
            XmlField('DokumanNoReq', JsonText(Options, 'documentNo')) +
            XmlField('RevizyonNo', JsonText(Options, 'revisionNo')) +
            XmlField('RevizyonTarihi', JsonDateText(Options, 'revisionDate')) +
            '</Options><DataItems></DataItems></ReportParameters>';
        exit(Xml);
    end;

    local procedure XmlField(Name: Text; Value: Text): Text
    begin
        if Value = '' then
            exit('');
        exit('<Field name="' + Name + '">' + XmlEscape(Value) + '</Field>');
    end;

    local procedure XmlEscape(Value: Text): Text
    begin
        Value := Value.Replace('&', '&amp;');
        Value := Value.Replace('<', '&lt;');
        Value := Value.Replace('>', '&gt;');
        Value := Value.Replace('"', '&quot;');
        exit(Value);
    end;

    local procedure JsonText(var Options: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Options.Get(KeyName, Token) then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText().Trim());
    end;

    /// <summary>Accepts yyyy-MM-dd or dd.MM.yyyy from the terminal; emits the XML date.</summary>
    local procedure JsonDateText(var Options: JsonObject; KeyName: Text): Text
    var
        Value: Text;
        DateValue: Date;
    begin
        Value := JsonText(Options, KeyName);
        if Value = '' then
            exit('');
        if Evaluate(DateValue, Value, 9) then
            exit(Format(DateValue, 0, 9));
        if Evaluate(DateValue, Value) then
            exit(Format(DateValue, 0, 9));
        Error(MteDateInvalidErr, Value);
    end;

    /// <summary>
    /// One ZPL material-identification label for every item group on the LP.
    /// This is the label the BADE terminals print on their ZPL label printer.
    /// </summary>
    local procedure PrintPalletItemZplLabels(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer; OptionsJson: Text)
    var
        LPLine: Record "DOPSWHS LP Line";
        LabelLine: Record "DOPSWHS LP Line";
        PrintedGroups: Dictionary of [Text, Boolean];
        GroupKey: Text;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then
            repeat
                GroupKey := PalletItemGroupKey(LPLine);
                if not PrintedGroups.ContainsKey(GroupKey) then begin
                    PrintedGroups.Add(GroupKey, true);
                    LabelLine := LPLine;
                    LabelLine.Quantity := PalletItemGroupQuantity(LPLine);
                    EnqueueZpl(
                        LP."No.",
                        BuildPalletItemZplWithOptions(LP, LabelLine, OptionsJson),
                        PrinterId,
                        Copies,
                        Enum::"DOPSWHS IWX Report Usage"::LpLabel,
                        'LP material identification');
                end;
            until LPLine.Next() = 0;
    end;

    local procedure PalletItemGroupKey(LPLine: Record "DOPSWHS LP Line"): Text
    begin
        exit(
            LPLine."Item No." + '|' + LPLine."Variant Code" + '|' + LPLine."Unit of Measure" + '|' +
            LPLine."Lot No." + '|' + LPLine."Serial No." + '|' + Format(LPLine."Source Document Type") + '|' +
            LPLine."Source Document No." + '|' + Format(LPLine."Source Document Line No."));
    end;

    local procedure PalletItemGroupQuantity(LPLine: Record "DOPSWHS LP Line"): Decimal
    var
        GroupLine: Record "DOPSWHS LP Line";
        GroupQuantity: Decimal;
    begin
        GroupLine.SetRange("LP No.", LPLine."LP No.");
        GroupLine.SetRange("Item No.", LPLine."Item No.");
        GroupLine.SetRange("Variant Code", LPLine."Variant Code");
        GroupLine.SetRange("Unit of Measure", LPLine."Unit of Measure");
        GroupLine.SetRange("Lot No.", LPLine."Lot No.");
        GroupLine.SetRange("Serial No.", LPLine."Serial No.");
        GroupLine.SetRange("Source Document Type", LPLine."Source Document Type");
        GroupLine.SetRange("Source Document No.", LPLine."Source Document No.");
        GroupLine.SetRange("Source Document Line No.", LPLine."Source Document Line No.");
        if GroupLine.FindSet() then
            repeat
                GroupQuantity += GroupLine.Quantity;
            until GroupLine.Next() = 0;
        exit(GroupQuantity);
    end;

    /// <summary>
    /// BADE MTE as ZPL: the customer's report layout on the 10 x 8 cm Zebra
    /// stock (codeunit "DOPSWHS MTE Zpl Builder"). Kept for callers and tests.
    /// </summary>
    procedure BuildPalletItemZpl(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"): Text
    begin
        exit(BuildPalletItemZplWithOptions(LP, LPLine, ''));
    end;

    procedure BuildPalletItemZplWithOptions(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"; OptionsJson: Text): Text
    var
        Builder: Codeunit "DOPSWHS MTE Zpl Builder";
    begin
        exit(Builder.Build(LP, LPLine, OptionsJson));
    end;

    procedure PrintBinLabel(var Bin: Record Bin; PrinterId: Code[50]; Copies: Integer)
    var
        Printer: Record "DOPSWHS Printer";
    begin
        if Printer.Get(PrinterId) then
            if Printer."Format" = Printer."Format"::PDF then begin
                PrintBarcodeDocument(PrinterId, Bin."Code", Copies, Bin."Code", 'RAF ETIKETI', Bin."Location Code" + ' | ' + Bin.Description);
                exit;
            end;
        EnqueueZpl(Bin."Code", BuildBinZpl(Bin), PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Bin, 'Bin');
    end;

    /// <summary>
    /// Renders the exact value scanned by a terminal as a one-page PDF and
    /// sends it to the explicitly selected document printer. This deliberately
    /// does not parse GS1/LP/item prefixes: the test output must prove which raw
    /// value reached Business Central from the scanner.
    /// </summary>
    procedure PrintBarcodeTest(PrinterId: Code[50]; BarcodeValue: Text; Copies: Integer): Integer
    begin
        exit(PrintBarcodeDocument(PrinterId, BarcodeValue, Copies, 'BARCODE-TEST', 'OKUTULAN BARKOD', 'BCWMS terminal baskı testi'));
    end;

    local procedure PrintBarcodeDocument(PrinterId: Code[50]; BarcodeValue: Text; Copies: Integer; SourceDoc: Code[50]; Heading: Text; Description: Text): Integer
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
        BarcodeReport.SetLabelContent(Heading, Description);
        TempBlob.CreateOutStream(PdfOutStream);
        if not BarcodeReport.SaveAs('', ReportFormat::Pdf, PdfOutStream) then
            Error('The scanned barcode test PDF could not be rendered: %1', LastRenderError());
        if not TempBlob.HasValue() then
            Error('The scanned barcode test produced an empty PDF.');
        Setup.Get('');
        TempBlob.CreateInStream(PdfInStream);
        if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then
            JobId := SelfHosted.EnqueueStreamForImmediateDispatch(
                SourceDoc,
                Report::"DOPSWHS Barcode Print Test",
                CopyStr(PrinterId, 1, 20),
                Enum::"DOPSWHS Print Format"::PDF,
                PdfInStream,
                Copies,
                '')
        else
            JobId := EnqueuePdf(SourceDoc, Report::"DOPSWHS Barcode Print Test", PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Receipt, PdfInStream);

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

    /// <summary>
    /// Creates an A4 PDF containing the LP number as a QR code and immediately
    /// dispatches it to the selected PDF/document printer.
    /// </summary>
    procedure PrintLPDocument(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer): Integer
    var
        LpQrReport: Report "DOPSWHS LP QR Document";
        TempBlob: Codeunit "Temp Blob";
        AzureBridge: Codeunit "DOPSWHS Azure Print Bridge";
        SelfHosted: Codeunit "DOPSWHS Self-Host Print Client";
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        PdfInStream: InStream;
        PdfOutStream: OutStream;
        ResolvedPrinter: Code[20];
        JobId: Integer;
    begin
        if Copies <= 0 then
            Copies := 1;
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');

        ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::Receipt, Copies);
        if ResolvedPrinter = '' then
            Error('No PDF document printer is selected for LP QR printing.');
        EnsureDocumentPrinter(ResolvedPrinter, Enum::"DOPSWHS IWX Report Usage"::Receipt);

        LP.SetRecFilter();
        LpQrReport.SetTableView(LP);
        TempBlob.CreateOutStream(PdfOutStream);
        // BADE 16 Eyl 2026: the boolean SaveAs swallows the report's own error
        // (permission, layout, data); the terminal only saw a REF code. Surface it.
        if not LpQrReport.SaveAs('', ReportFormat::Pdf, PdfOutStream) then
            Error(LpQrRenderFailedErr, LP."No.", LastRenderError());
        if not TempBlob.HasValue() then
            Error('The LP QR report produced an empty PDF.');

        Setup.Get('');
        TempBlob.CreateInStream(PdfInStream);
        if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then
            JobId := SelfHosted.EnqueueStreamForImmediateDispatch(
                LP."No.",
                Report::"DOPSWHS LP QR Document",
                ResolvedPrinter,
                Enum::"DOPSWHS Print Format"::PDF,
                PdfInStream,
                Copies,
                '')
        else
            JobId := EnqueuePdf(LP."No.", Report::"DOPSWHS LP QR Document", ResolvedPrinter, Copies, Enum::"DOPSWHS IWX Report Usage"::Receipt, PdfInStream);

        if Setup."Print Channel" = Setup."Print Channel"::AzureDirect then begin
            Commit();
            AzureBridge.DispatchJob(JobId);
            Commit();
            Queue.Get(JobId);
            if Queue.Status in [Queue.Status::Queued, Queue.Status::Failed] then
                Error('The LP QR print job was saved but Azure dispatch failed: %1', Queue."Last Error");
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

    /// <summary>
    /// 4x2" (812x406 dots, 203 dpi) item label: header band, large item number,
    /// two-line description, base unit, Code128 + QR. Both barcodes carry the bare
    /// item number, which the terminal resolves as an item by default.
    /// </summary>
    local procedure BuildItemZpl(var Item: Record Item): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        NoFont: Integer;
    begin
        NoFont := FitFontSize(Item."No.", 560, 72);
        exit(
            '^XA^CI28^PW812^LL406' +
            '^FO0,0^GB812,52,52^FS' +
            '^FO24,10^A0N,32,32^FR^FH_^FDÜRÜN ETİKETİ^FS' +
            '^FO470,12^A0N,26,26^FR^FH_^FB318,1,0,R^FD' + ZplEncoder.EncodeFieldData(CopyStr(CompanyProperty.DisplayName(), 1, 22)) + '^FS' +
            '^FO24,66^A0N,' + Format(NoFont) + ',' + Format(NoFont) + '^FH_^FD' + ZplEncoder.EncodeFieldData(Item."No.") + '^FS' +
            '^FO24,148^A0N,30,30^FH_^FD' + ZplEncoder.EncodeFieldData(DescriptionLine(Item.Description, 1, 33)) + '^FS' +
            '^FO24,184^A0N,30,30^FH_^FD' + ZplEncoder.EncodeFieldData(DescriptionLine(Item.Description, 2, 33)) + '^FS' +
            '^FO24,222^A0N,24,24^FH_^FDBİRİM: ' + ZplEncoder.EncodeFieldData(Item."Base Unit of Measure") +
                ItemGtinText(Item) + '^FS' +
            '^FO24,258^BY' + Format(BarcodeModuleWidth(Item."No.")) + '^BCN,100,Y,N,N^FH_^FD' + ZplEncoder.EncodeFieldData(Item."No.") + '^FS' +
            '^FO604,66^BQN,2,7^FH_^FDLA,' + ZplEncoder.EncodeFieldData(Item."No.") + '^FS' +
            '^FO604,320^A0N,22,22^FH_^FDQR = ÜRÜN NO^FS' +
            '^XZ');
    end;

    local procedure ItemGtinText(var Item: Record Item): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        if Item.GTIN = '' then
            exit('');
        exit('   GTIN: ' + ZplEncoder.EncodeFieldData(Item.GTIN));
    end;

    /// <summary>
    /// 4x2" bin label meant to be read from the aisle: the bin code fills the
    /// left column at the largest size that fits, followed by zone / bin type /
    /// description, Code128 + QR. Barcodes carry the bare bin code.
    /// </summary>
    local procedure BuildBinZpl(var Bin: Record Bin): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        InfoText: Text;
        CodeFont: Integer;
    begin
        CodeFont := FitFontSize(Bin.Code, 560, 110);
        if Bin."Zone Code" <> '' then
            InfoText := 'BÖLGE: ' + Bin."Zone Code";
        if Bin."Bin Type Code" <> '' then
            InfoText := AppendLabelPart(InfoText, 'TİP: ' + Bin."Bin Type Code");
        if Bin.Description <> '' then
            InfoText := AppendLabelPart(InfoText, Bin.Description);
        exit(
            '^XA^CI28^PW812^LL406' +
            '^FO0,0^GB812,52,52^FS' +
            '^FO24,10^A0N,32,32^FR^FH_^FDRAF ETİKETİ^FS' +
            '^FO470,12^A0N,26,26^FR^FH_^FB318,1,0,R^FD' + ZplEncoder.EncodeFieldData(Bin."Location Code") + '^FS' +
            '^FO24,' + Format(62 + (110 - CodeFont) div 2) + '^A0N,' + Format(CodeFont + 10) + ',' + Format(CodeFont) + '^FH_^FD' + ZplEncoder.EncodeFieldData(Bin.Code) + '^FS' +
            '^FO24,190^A0N,26,26^FH_^FB560,1,0,L^FD' + ZplEncoder.EncodeFieldData(CopyStr(InfoText, 1, 44)) + '^FS' +
            '^FO24,236^BY' + Format(BarcodeModuleWidth(Bin.Code)) + '^BCN,110,Y,N,N^FH_^FD' + ZplEncoder.EncodeFieldData(Bin.Code) + '^FS' +
            '^FO604,180^BQN,2,7^FH_^FDLA,' + ZplEncoder.EncodeFieldData(Bin.Code) + '^FS' +
            '^XZ');
    end;

    local procedure AppendLabelPart(Existing: Text; Part: Text): Text
    begin
        if Existing = '' then
            exit(Part);
        exit(Existing + '   ' + Part);
    end;

    /// <summary>
    /// Code128 module width so the bar pattern stays inside the 560-dot left
    /// column: ~ (11 x chars + 35) x module dots.
    /// </summary>
    local procedure BarcodeModuleWidth(Data: Text): Integer
    begin
        if StrLen(Data) <= 10 then
            exit(3);
        if StrLen(Data) <= 22 then
            exit(2);
        exit(1);
    end;

    /// <summary>
    /// Word-wraps Description into two lines of at most MaxChars and returns the
    /// requested line. ^FB would overprint a third line onto the second, so the
    /// split is done here and the remainder is cut.
    /// </summary>
    local procedure DescriptionLine(Description: Text; LineNo: Integer; MaxChars: Integer): Text
    var
        FirstLine: Text;
        Rest: Text;
        BreakAt: Integer;
    begin
        Description := DelChr(Description, '<>', ' ');
        if StrLen(Description) <= MaxChars then begin
            if LineNo = 1 then
                exit(Description);
            exit('');
        end;
        BreakAt := MaxChars + 1;
        while (BreakAt > 1) and (Description[BreakAt] <> ' ') do
            BreakAt -= 1;
        if BreakAt <= MaxChars div 2 then
            BreakAt := MaxChars + 1;
        FirstLine := DelChr(CopyStr(Description, 1, BreakAt - 1), '>', ' ');
        Rest := DelChr(CopyStr(Description, BreakAt), '<', ' ');
        if LineNo = 1 then
            exit(FirstLine);
        exit(CopyStr(Rest, 1, MaxChars));
    end;

    /// <summary>
    /// Largest Zebra font 0 size (dots) at which Value still fits MaxWidth.
    /// Font 0 glyphs average ~0.55 x the point size in width.
    /// </summary>
    local procedure FitFontSize(Value: Text; MaxWidth: Integer; Preferred: Integer): Integer
    var
        Size: Integer;
    begin
        if StrLen(Value) = 0 then
            exit(Preferred);
        Size := MaxWidth div StrLen(Value) * 100 div 55;
        if Size > Preferred then
            Size := Preferred;
        if Size < 24 then
            Size := 24;
        exit(Size);
    end;

    /// <summary>
    /// Renders a filtered Business Central report as PDF and routes it through
    /// the same provider queue used by terminal labels. The RecordRef is
    /// mandatory so a report can never accidentally print every record.
    /// </summary>
    procedure PrintReport(SourceDoc: Code[50]; ReportId: Integer; PrinterId: Code[50]; Copies: Integer; Usage: Enum "DOPSWHS IWX Report Usage"; SourceRecord: RecordRef): Integer
    begin
        exit(PrintReportWithParameters(SourceDoc, ReportId, '', PrinterId, Copies, Usage, SourceRecord));
    end;

    procedure PrintReportWithParameters(SourceDoc: Code[50]; ReportId: Integer; Parameters: Text; PrinterId: Code[50]; Copies: Integer; Usage: Enum "DOPSWHS IWX Report Usage"; SourceRecord: RecordRef): Integer
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
        // BADE 16 Eyl 2026 (LP000025 MTE): the boolean SaveAs swallows the
        // report's own error (missing Execute permission on the customer report,
        // report Error(), layout/data failure) and the terminal only showed a
        // REF code. Carry the real message so the operator/admin can act.
        if not Report.SaveAs(ReportId, Parameters, ReportFormat::Pdf, PdfOutStream, SourceRecord) then
            Error(ReportRenderFailedErr, ReportId, ReportCaption(ReportId), LastRenderError());
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

    /// <summary>The message behind a failed Report.SaveAs (BC clears it on success).</summary>
    local procedure LastRenderError(): Text
    var
        LastError: Text;
    begin
        LastError := GetLastErrorText();
        ClearLastError();
        if LastError = '' then
            exit(RenderErrorUnknownTxt);
        exit(LastError);
    end;

    local procedure ReportCaption(ReportId: Integer): Text
    var
        AllObjWithCaption: Record AllObjWithCaption;
    begin
        if AllObjWithCaption.Get(AllObjWithCaption."Object Type"::Report, ReportId) then
            exit(AllObjWithCaption."Object Caption");
        exit('');
    end;

    var
        MteNoSourceEntryErr: Label '%1 paletinin kaynak madde defteri girişi yok; müşteri MTE raporu için palet önce mal kabulle kaydedilmiş olmalı.', Comment = '%1 LP no';
        MteOptionsInvalidErr: Label 'MTE ek alanları okunamadı (geçersiz JSON).';
        MteDateInvalidErr: Label 'MTE tarih alanı geçersiz: %1 (gg.aa.yyyy veya yyyy-aa-gg girin).', Comment = '%1 value';
        ReportRenderFailedErr: Label '%1 %2 raporu PDF olarak oluşturulamadı. BC hatası: %3', Comment = '%1 report id, %2 report caption, %3 BC error text';
        LpQrRenderFailedErr: Label '%1 LP QR belgesi oluşturulamadı. BC hatası: %2', Comment = '%1 LP no, %2 BC error text';
        RenderErrorUnknownTxt: Label 'ayrıntı alınamadı', Comment = 'shown when GetLastErrorText is empty';
}
