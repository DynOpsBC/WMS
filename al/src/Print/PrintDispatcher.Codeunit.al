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
        Builder: Codeunit "DOPSWHS LP Label Builder";
        ReportLP: Record "DOPSWHS LP Header";
        SourceRecord: RecordRef;
        TemplateReportId: Integer;
    begin
        // EMU/DKÇ (15 Eyl 2026): the LP template decides copies and design. A
        // template routed to an RDLC report prints as a PDF document; every
        // other design is ZPL built by the label builder.
        if Copies <= 0 then
            Copies := Builder.ResolveCopies(LP);
        if Copies > 10 then
            Error('A print job cannot exceed 10 copies.');
        if Builder.UsesReportLayout(LP, TemplateReportId) then begin
            ReportLP := LP;
            ReportLP.SetRecFilter();
            SourceRecord.GetTable(ReportLP);
            PrintReport(LP."No.", TemplateReportId, PrinterId, Copies, Enum::"DOPSWHS IWX Report Usage"::Receipt, SourceRecord);
            exit;
        end;
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
    var
        TargetPrinter: Code[50];
    begin
        TargetPrinter := ResolvePalletItemLabelPrinter(PrinterId);
        if PrinterIsPdf(TargetPrinter) then
            PrintPalletItemReport(LP, TargetPrinter, Copies)
        else
            PrintPalletItemZplLabels(LP, TargetPrinter, Copies);
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
    local procedure PrintPalletItemReport(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
    var
        ReportLP: Record "DOPSWHS LP Header";
        SourceRecord: RecordRef;
    begin
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

    /// <summary>
    /// One ZPL material-identification label for every item group on the LP.
    /// This is the label the BADE terminals print on their ZPL label printer.
    /// </summary>
    local procedure PrintPalletItemZplLabels(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
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
                        BuildPalletItemZpl(LP, LabelLine),
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
    /// Pallet item label, one per item group on the pallet: item, description,
    /// lot, received total and pallet quantity; QR and Code128 carry the LP No.
    /// Laid out on the configured label canvas (Setup label size).
    /// </summary>
    procedure BuildPalletItemZpl(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"): Text
    var
        Item: Record Item;
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Lines: List of [Text];
        DescriptionText: Text;
        TotalQuantity: Decimal;
        QrData: Text;
        TotalText: Text;
        PalletText: Text;
        LotText: Text;
        Zpl: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
        Bars: Integer;
    begin
        if Item.Get(LPLine."Item No.") then
            DescriptionText := Item.Description;
        TotalQuantity := LPLine."Source Document Quantity";
        if TotalQuantity = 0 then
            TotalQuantity := LPLine.Quantity;

        TotalText := StrSubstNo('TOPLAM MAL KABUL: %1 %2', TotalQuantity, LPLine."Unit of Measure");
        PalletText := StrSubstNo('PALET MİKTARI: %1 %2', LPLine.Quantity, LPLine."Unit of Measure");
        if LPLine."Lot No." <> '' then
            LotText := 'LOT: ' + LPLine."Lot No.";

        QrData := LP."No.";
        if QrData = '' then
            QrData := LPLine."Lot No.";
        if QrData = '' then
            QrData := LPLine."Item No.";

        Canvas.Init();
        Zpl := Canvas.Frame('MADDE TANIMLAMA ETİKETİ', LP."No.", QrData, 'QR = LP NO', X, ColumnWidth, Y);
        NoFont := Canvas.FitFont(LPLine."Item No.", ColumnWidth, Canvas.BigFont() - 8, 28);
        Zpl += Canvas.Write(X, Y, NoFont, ColumnWidth, LPLine."Item No.");
        Y += NoFont + 6;
        Canvas.WrapText(DescriptionText, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont()), 1, Lines);
        if Lines.Count() > 0 then begin
            Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, Lines.Get(1));
            Y += Canvas.Pitch() - 2;
        end;
        if LotText <> '' then begin
            Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, CopyStr(LotText, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont())));
            Y += Canvas.Pitch() - 2;
        end;
        Zpl += Canvas.Write(X, Y, Canvas.SmallFont(), ColumnWidth, CopyStr(TotalText, 1, Canvas.MaxChars(ColumnWidth, Canvas.SmallFont())));
        Y += Canvas.SmallFont() + 6;
        Zpl += Canvas.Write(X, Y, Canvas.QtyFont(), ColumnWidth, CopyStr(PalletText, 1, Canvas.MaxChars(ColumnWidth, Canvas.QtyFont())));
        Y += Canvas.QtyFont() + 8;
        if LP."No." <> '' then begin
            Bars := Canvas.LabelHeight() - Canvas.Margin() - Y;
            if Bars >= 30 then
                Zpl += Canvas.Code128(X, Y, Bars, LP."No.", ColumnWidth, false);
        end;
        exit(Zpl + Canvas.Finish());
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
            Error('The scanned barcode test PDF could not be rendered.');
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
        if not LpQrReport.SaveAs('', ReportFormat::Pdf, PdfOutStream) then
            Error('The LP QR PDF could not be rendered.');
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
    /// <summary>
    /// Item label: item no. at the largest size that fits the text column,
    /// description on up to two lines, unit and GTIN, Code128 + QR carrying the
    /// bare item no. Laid out on the configured label canvas (Setup label size,
    /// 80x40 mm at DKÇ) so nothing is cut off on the right or at the bottom.
    /// </summary>
    procedure BuildItemZpl(var Item: Record Item): Text
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Lines: List of [Text];
        Line: Text;
        UnitText: Text;
        Zpl: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
        NoWidth: Integer;
    begin
        Canvas.Init();
        // DKÇ (16 Eyl 2026): no caption under the item QR.
        Zpl := Canvas.Frame('ÜRÜN ETİKETİ', CompanyProperty.DisplayName(), Item."No.", '', X, ColumnWidth, Y);
        // DKÇ (17 Eyl 2026): "ürün no çok büyük, uzunsa sığmıyor". Smaller
        // preferred size, measured glyph widths; if even the small font is too
        // wide the glyphs are condensed so the number never overprints.
        NoFont := Canvas.FitFontMeasured(Item."No.", ColumnWidth, Canvas.ItemNoFont(), Canvas.SmallFont());
        NoWidth := Canvas.FitFontMeasured(Item."No.", ColumnWidth, NoFont, 10);
        Zpl += Canvas.WriteSized(X, Y, NoFont, NoWidth, ColumnWidth, Item."No.");
        Y += NoFont + 8;
        Canvas.WrapText(Item.Description, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont()), 2, Lines);
        foreach Line in Lines do begin
            Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, Line);
            Y += Canvas.Pitch();
        end;
        UnitText := 'BİRİM: ' + Item."Base Unit of Measure";
        if Item.GTIN <> '' then
            UnitText += '   GTIN: ' + Item.GTIN;
        Zpl += Canvas.Write(X, Y, Canvas.SmallFont(), ColumnWidth, CopyStr(UnitText, 1, Canvas.MaxChars(ColumnWidth, Canvas.SmallFont())));
        Y += Canvas.SmallFont() + 8;
        Zpl += Canvas.Code128(X, Y, Canvas.BarHeightToBottom(Y, true), Item."No.", ColumnWidth, true);
        exit(Zpl + Canvas.Finish());
    end;

    /// <summary>
    /// Bin label read from the aisle: the bin code at the largest size that
    /// fits the text column, zone / bin type / description, Code128 + QR
    /// carrying the bare bin code. Laid out on the configured label canvas.
    /// </summary>
    procedure BuildBinZpl(var Bin: Record Bin): Text
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        InfoText: Text;
        Zpl: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        CodeFont: Integer;
        CodeMax: Integer;
    begin
        if Bin."Zone Code" <> '' then
            InfoText := 'BÖLGE: ' + Bin."Zone Code";
        if Bin."Bin Type Code" <> '' then
            InfoText := AppendLabelPart(InfoText, 'TİP: ' + Bin."Bin Type Code");
        if Bin.Description <> '' then
            InfoText := AppendLabelPart(InfoText, Bin.Description);

        Canvas.Init();
        Zpl := Canvas.Frame('RAF ETİKETİ', Bin."Location Code", Bin.Code, 'QR = RAF KODU', X, ColumnWidth, Y);
        CodeMax := Canvas.LabelHeight() * 32 div 100;
        if CodeMax < 60 then
            CodeMax := 60;
        if CodeMax > 120 then
            CodeMax := 120;
        CodeFont := Canvas.FitFont(Bin.Code, ColumnWidth, CodeMax, 36);
        Zpl += Canvas.WriteSized(X, Y, CodeFont + CodeFont div 10, CodeFont, ColumnWidth, Bin.Code);
        Y += CodeFont + CodeFont div 10 + 6;
        if InfoText <> '' then begin
            Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, CopyStr(InfoText, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont())));
            Y += Canvas.Pitch();
        end;
        Y += 2;
        Zpl += Canvas.Code128(X, Y, Canvas.BarHeightToBottom(Y, true), Bin.Code, ColumnWidth, true);
        exit(Zpl + Canvas.Finish());
    end;

    local procedure AppendLabelPart(Existing: Text; Part: Text): Text
    begin
        if Existing = '' then
            exit(Part);
        exit(Existing + '   ' + Part);
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
