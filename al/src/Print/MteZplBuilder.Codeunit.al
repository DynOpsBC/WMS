/// <summary>
/// BADE (16–17 Eyl 2026): the terminal's ZPL "Madde Tanımlama Etiketi" drawn as
/// the customer's report layout (BadeProduction report 60150): boxed table
/// with the same rows, KABUL / RED / KARANTİNA cells, QR (LP number), and the
/// operator's extra fields (Giriş Yapan, tedarikçi lotu, kalite kontrol onayı,
/// doküman / revizyon). Data is resolved the way the report resolves it
/// (parent category, INCI name, receipt vendor, warehouse class, posted
/// receipt number) without a compile dependency on the customer extension.
///
/// Orientation (17 Eyl 2026, "MTE yatay çıkmalı"): the stock is 100 x 150 mm
/// (4 x 6 inch) fed portrait through a 4-inch Zebra, but the label must read
/// LANDSCAPE (15 cm wide, 10 cm tall). The layout is therefore designed on a
/// 1218 x 812 landscape canvas and every primitive rotates it 90° clockwise
/// onto the 812 x 1218 portrait stock (^A0R text): canvas (x, y, w, h) ->
/// stock (812 - y - h, x, h, w). The operator turns the label a quarter turn
/// counter-clockwise to read it.
/// </summary>
codeunit 72320 "DOPSWHS MTE Zpl Builder"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = R,
        tabledata "DOPSWHS LP Line" = R,
        tabledata Item = R,
        tabledata "Item Category" = R,
        tabledata "Item Vendor" = R,
        tabledata Vendor = R,
        tabledata "Purch. Rcpt. Header" = R,
        tabledata "Item Ledger Entry" = R,
        tabledata "Lot No. Information" = R,
        tabledata "Warehouse Class" = R,
        tabledata "Posted Whse. Receipt Line" = R,
        tabledata Employee = R,
        tabledata "Company Information" = R;

    var
        // Physical stock: 100 x 150 mm at 203 dpi (4 x 6 inch), fed portrait.
        LabelWidth: Integer;
        LabelHeight: Integer;
        // Design canvas: the same label seen landscape (150 x 100 mm).
        CanvasWidth: Integer;
        CanvasHeight: Integer;
        Unknown: Label 'U.Y', Locked = true;

    procedure Build(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"; OptionsJson: Text): Text
    var
        Item: Record Item;
        ItemLedgerEntry: Record "Item Ledger Entry";
        Options: JsonObject;
        HaveEntry: Boolean;
        Zpl: Text;
        ItemNo: Text;
        CategoryText: Text;
        ItemName: Text;
        InciName: Text;
        VendorName: Text;
        SupplierLot: Text;
        ProductionDate: Text;
        LotNo: Text;
        ExpirationDate: Text;
        QtyText: Text;
        StorageText: Text;
        ReceiptDate: Text;
        ReceiptNo: Text;
        InspectorText: Text;
        QcName: Text;
        QcDate: Text;
        DocumentNo: Text;
        RevisionNo: Text;
        RevisionDate: Text;
        QrData: Text;
        CompanyText: Text;
    begin
        LabelWidth := 812;
        LabelHeight := 1218;
        CanvasWidth := 1218;
        CanvasHeight := 812;
        if (OptionsJson <> '') and not Options.ReadFrom(OptionsJson) then
            Clear(Options);

        if LPLine."Source Item Ledger Entry No." <> 0 then
            HaveEntry := ItemLedgerEntry.Get(LPLine."Source Item Ledger Entry No.");
        if Item.Get(LPLine."Item No.") then;

        ItemNo := LPLine."Item No.";
        CategoryText := ResolveCategory(Item);
        VendorName := ResolveVendorName(Item, ItemLedgerEntry, HaveEntry);
        ItemName := ResolveItemName(Item, LPLine, ItemLedgerEntry, HaveEntry);
        InciName := ResolveInciName(Item);
        SupplierLot := JsonText(Options, 'supplierLotNo');
        if SupplierLot = '' then
            SupplierLot := ResolveSupplierLot(LPLine);
        ProductionDate := ResolveProductionDate(LPLine, ItemLedgerEntry, HaveEntry);
        LotNo := LPLine."Lot No.";
        if (LPLine."Expiration Date" <> 0D) then
            ExpirationDate := DateText(LPLine."Expiration Date")
        else
            if HaveEntry then
                ExpirationDate := DateText(ItemLedgerEntry."Expiration Date");
        QtyText := FormatQuantity(LPLine.Quantity) + ' ' + LPLine."Unit of Measure";
        StorageText := ResolveStorageCondition(Item);
        if HaveEntry then
            ReceiptDate := DateText(ItemLedgerEntry."Posting Date")
        else
            if LP."Built DateTime" <> 0DT then
                ReceiptDate := DateText(DT2Date(LP."Built DateTime"));
        ReceiptNo := ResolveReceiptNo(LPLine, ItemLedgerEntry, HaveEntry);
        InspectorText := EmployeeName(JsonText(Options, 'inspectorEmployeeNo'));
        if InspectorText = '' then
            InspectorText := LP."Built By User";
        QcName := EmployeeName(JsonText(Options, 'qcEmployeeNo'));
        QcDate := JsonDateText(Options, 'qcApprovalDate');
        DocumentNo := JsonText(Options, 'documentNo');
        RevisionNo := JsonText(Options, 'revisionNo');
        RevisionDate := JsonDateText(Options, 'revisionDate');
        CompanyText := CompanyShortName();

        // QR: the pallet when it exists, otherwise lot, otherwise item —
        // the terminal treats an LP-prefixed scan as a pallet.
        QrData := LP."No.";
        if QrData = '' then
            QrData := LPLine."Lot No.";
        if QrData = '' then
            QrData := LPLine."Item No.";

        // ------------------------------------------------------------------
        // ------------------------------------------------------------------
        // BADE (17 Eyl 2026, Merve): outer frame around the whole label, a
        // 3 mm margin so nothing prints edge to edge ("sıfıra sıfır"), and the
        // LP number under the QR. Landscape canvas 1218 x 812; see summary.
        // Frame 24..1194 x 24..788; header 24..78; table 78..756; footer to 788.
        // Columns A 272 | B 296 | C 306 | D 296.
        // ------------------------------------------------------------------
        Zpl := '^XA^CI28^PW' + Format(LabelWidth) + '^LL' + Format(LabelHeight) +
            Box(24, 24, 1170, 764, 3) +
            Text(38, 34, 34, 30, 250, 0, CompanyText) +
            Text(24, 32, 40, 36, 1170, 1, 'MADDE TANIMLAMA ETİKETİ') +
            Line(24, 78, 1170, 3);

        // Upper rows, same order as report 60150.
        Zpl += Row4(78, 43, 'MADDE KODU', ItemNo, 'MADDE KATEGORİSİ', UY(CategoryText)) +
            Row2(121, 43, 'MADDE ADI', UY(ItemName)) +
            Row2(164, 43, 'INCI ADI', UY(InciName)) +
            Row2(207, 43, 'TEDARİKÇİ ADI', UY(VendorName)) +
            Row2(250, 43, 'TEDARİKÇİ LOTU', UY(SupplierLot)) +
            Row4(293, 43, 'ÜRETİM TARİHİ', UY(ProductionDate), 'LOT NO', UY(LotNo)) +
            Row4(336, 43, 'SON KULLANMA TARİHİ', UY(ExpirationDate), 'MİKTAR/BİRİM', QtyText);

        // Lower block (Y 379..756): left rows A 272 | B 296, decision column
        // 216, QR column 386 — the report narrows the decision column here.
        Zpl += RowLeft(379, 42, 'DEPOLAMA KOŞULU', UY(StorageText)) +
            RowLeft(421, 43, 'DEPO GİRİŞ TARİHİ', UY(ReceiptDate)) +
            RowLeft(464, 42, 'DEPO GİRİŞ NO.', UY(ReceiptNo)) +
            RowLeft(506, 49, 'GİRİŞ YAPAN', UY(InspectorText)) +
            Cell(24, 555, 568, 35, 24, 22, 1, 'KALİTE KONTROL ONAYI') +
            RowLeft(590, 42, 'KONTROL EDEN', UY(QcName)) +
            RowLeft(632, 42, 'TARİH', UY(QcDate)) +
            RowLeft(674, 82, 'İMZA', '');

        // Decision cells span the row groups; QR with the LP number under it
        // (Merve, 17 Eyl: "qr altında lp nosu").
        Zpl += Cell(592, 379, 216, 85, 30, 28, 1, 'KABUL') +
            Cell(592, 464, 216, 132, 30, 28, 1, 'RED') +
            Cell(592, 596, 216, 160, 28, 26, 1, 'KARANTİNA') +
            Box(808, 379, 386, 377, 2) +
            Qr(896, 433, 10, QrData) +
            Text(808, 661, 40, 36, 386, 1, QrData);

        // Footer (Y 756..788)
        Zpl += Cell(24, 756, 568, 32, 22, 20, 0, 'DOKÜMAN NO. / REVİZYON NO. / REVİZYON TARİHİ') +
            Cell(592, 756, 602, 32, 22, 20, 1, UY(DocumentNo) + ' / ' + UY(RevisionNo) + ' / ' + UY(RevisionDate)) +
            '^XZ';
        exit(Zpl);
    end;

    // ------------------------------------------------------------------
    // Data resolution (mirrors BadeProduction report 60150)
    // ------------------------------------------------------------------

    local procedure ResolveCategory(Item: Record Item): Text
    var
        ItemCategory: Record "Item Category";
    begin
        if Item."Item Category Code" = '' then
            exit('');
        if not ItemCategory.Get(Item."Item Category Code") then
            exit(Item."Item Category Code");
        // The report prints the parent category ("SEKONDER AMBALAJ"), not the leaf.
        if ItemCategory."Parent Category" <> '' then
            exit(ItemCategory."Parent Category");
        exit(ItemCategory.Code);
    end;

    local procedure ResolveVendorName(Item: Record Item; ItemLedgerEntry: Record "Item Ledger Entry"; HaveEntry: Boolean): Text
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        Vendor: Record Vendor;
    begin
        if HaveEntry and (ItemLedgerEntry."Document Type" = ItemLedgerEntry."Document Type"::"Purchase Receipt") then
            if PurchRcptHeader.Get(ItemLedgerEntry."Document No.") then
                exit(PurchRcptHeader."Buy-from Vendor Name");
        if (Item."Vendor No." <> '') and Vendor.Get(Item."Vendor No.") then
            exit(Vendor.Name);
        exit('');
    end;

    /// <summary>Customer field "Vendor Item Name" on Item Vendor (BadeProduction), read by name; else the item description.</summary>
    local procedure ResolveItemName(Item: Record Item; LPLine: Record "DOPSWHS LP Line"; ItemLedgerEntry: Record "Item Ledger Entry"; HaveEntry: Boolean): Text
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ItemVendor: Record "Item Vendor";
        FieldRec: Record Field;
        ItemVendorRef: RecordRef;
        VendorItemName: Text;
    begin
        if HaveEntry and (ItemLedgerEntry."Document Type" = ItemLedgerEntry."Document Type"::"Purchase Receipt") then
            if PurchRcptHeader.Get(ItemLedgerEntry."Document No.") and (PurchRcptHeader."Buy-from Vendor No." <> '') then
                if ItemVendor.Get(PurchRcptHeader."Buy-from Vendor No.", LPLine."Item No.", LPLine."Variant Code") then begin
                    FieldRec.SetRange(TableNo, Database::"Item Vendor");
                    FieldRec.SetRange(FieldName, 'Vendor Item Name');
                    if FieldRec.FindFirst() then begin
                        ItemVendorRef.GetTable(ItemVendor);
                        if ItemVendorRef.FieldExist(FieldRec."No.") then
                            VendorItemName := Format(ItemVendorRef.Field(FieldRec."No.").Value);
                    end;
                    if VendorItemName.Trim() <> '' then
                        exit(VendorItemName);
                end;
        exit(Item.Description);
    end;

    /// <summary>Customer field "INCI Name" on Item (BadeProduction); read by name, no dependency.</summary>
    local procedure ResolveInciName(Item: Record Item): Text
    var
        FieldRec: Record Field;
        ItemRef: RecordRef;
    begin
        if Item."No." = '' then
            exit('');
        FieldRec.SetRange(TableNo, Database::Item);
        FieldRec.SetRange(FieldName, 'INCI Name');
        if not FieldRec.FindFirst() then
            exit('');
        ItemRef.GetTable(Item);
        if not ItemRef.FieldExist(FieldRec."No.") then
            exit('');
        exit(Format(ItemRef.Field(FieldRec."No.").Value));
    end;

    local procedure ResolveSupplierLot(LPLine: Record "DOPSWHS LP Line"): Text
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        if (LPLine."Lot No." = '') or (LPLine."Item No." = '') then
            exit('');
        if not LotNoInformation.Get(LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.") then
            exit('');
        if LotNoInformation.Description <> '' then
            exit(LotNoInformation.Description);
        exit(LotNoInformation."DOPSWHS Supplier Lot No.");
    end;

    local procedure ResolveProductionDate(LPLine: Record "DOPSWHS LP Line"; ItemLedgerEntry: Record "Item Ledger Entry"; HaveEntry: Boolean): Text
    var
        OutputEntry: Record "Item Ledger Entry";
    begin
        if HaveEntry and (ItemLedgerEntry."Entry Type" = ItemLedgerEntry."Entry Type"::Output) then
            exit(DateText(ItemLedgerEntry."Posting Date"));
        if LPLine."Lot No." = '' then
            exit('');
        // BADE 16 Eyl 2026 (LP000025/26 "MTE Yazdır" REF hatası): SetAscending
        // on a field outside the current sort key throws "Cannot call
        // SetAscending on field Posting Date because it is not part of the
        // current sorting" and killed every ZPL MTE. Sort by posting date
        // explicitly (ascending is the default) and take the first entry.
        OutputEntry.SetCurrentKey("Item No.", "Posting Date");
        OutputEntry.SetRange("Item No.", LPLine."Item No.");
        OutputEntry.SetRange("Variant Code", LPLine."Variant Code");
        OutputEntry.SetRange("Lot No.", LPLine."Lot No.");
        OutputEntry.SetRange("Entry Type", OutputEntry."Entry Type"::Output);
        if OutputEntry.FindFirst() then
            exit(DateText(OutputEntry."Posting Date"));
        exit('');
    end;

    local procedure ResolveStorageCondition(Item: Record Item): Text
    var
        WarehouseClass: Record "Warehouse Class";
    begin
        if Item."Warehouse Class Code" = '' then
            exit('');
        if WarehouseClass.Get(Item."Warehouse Class Code") then
            exit(WarehouseClass.Description);
        exit(Item."Warehouse Class Code");
    end;

    local procedure ResolveReceiptNo(LPLine: Record "DOPSWHS LP Line"; ItemLedgerEntry: Record "Item Ledger Entry"; HaveEntry: Boolean): Text
    var
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
    begin
        if HaveEntry and (ItemLedgerEntry."Lot No." <> '') then begin
            PostedWhseReceiptLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
            PostedWhseReceiptLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
            PostedWhseReceiptLine.SetRange("Posting Date", ItemLedgerEntry."Posting Date");
            if PostedWhseReceiptLine.FindFirst() then
                exit(PostedWhseReceiptLine."No.");
        end;
        if HaveEntry then
            exit(ItemLedgerEntry."Document No.");
        exit(LPLine."Source Document No.");
    end;

    local procedure EmployeeName(EmployeeNo: Text): Text
    var
        Employee: Record Employee;
        NameText: Text;
    begin
        if EmployeeNo = '' then
            exit('');
        if not Employee.Get(CopyStr(EmployeeNo, 1, MaxStrLen(Employee."No."))) then
            exit(EmployeeNo);
        NameText := (Employee."First Name" + ' ' + Employee."Last Name").Trim();
        if NameText = '' then
            NameText := Employee."Search Name";
        exit(NameText);
    end;

    local procedure CompanyShortName(): Text
    var
        CompanyInformation: Record "Company Information";
        Words: List of [Text];
    begin
        if not CompanyInformation.Get() then
            exit('');
        Words := CompanyInformation.Name.Split(' ');
        if Words.Count() >= 2 then
            exit(Words.Get(1) + ' ' + Words.Get(2));
        exit(CompanyInformation.Name);
    end;

    // ------------------------------------------------------------------
    // JSON / formatting helpers
    // ------------------------------------------------------------------

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

    local procedure JsonDateText(var Options: JsonObject; KeyName: Text): Text
    var
        Value: Text;
        DateValue: Date;
    begin
        Value := JsonText(Options, KeyName);
        if Value = '' then
            exit('');
        if Evaluate(DateValue, Value, 9) then
            exit(DateText(DateValue));
        if Evaluate(DateValue, Value) then
            exit(DateText(DateValue));
        exit(Value);
    end;

    local procedure DateText(Value: Date): Text
    begin
        if Value = 0D then
            exit('');
        exit(Format(Value, 0, '<Day,2>.<Month,2>.<Year4>'));
    end;

    /// <summary>Turkish number format like the report: 15.000 / 1.030,5.</summary>
    local procedure FormatQuantity(Value: Decimal): Text
    var
        Whole: Text;
        Fraction: Text;
        Grouped: Text;
        Position: Integer;
        Raw: Text;
    begin
        Raw := Format(Round(Value, 0.00001), 0, '<Precision,0:5><Sign><Integer><Decimals>');
        Position := StrPos(Raw, '.');
        if Position > 0 then begin
            Whole := CopyStr(Raw, 1, Position - 1);
            Fraction := CopyStr(Raw, Position + 1);
        end else
            Whole := Raw;
        Grouped := '';
        while StrLen(Whole) > 3 do begin
            Grouped := '.' + CopyStr(Whole, StrLen(Whole) - 2, 3) + Grouped;
            Whole := CopyStr(Whole, 1, StrLen(Whole) - 3);
        end;
        Grouped := Whole + Grouped;
        if Fraction <> '' then
            exit(Grouped + ',' + Fraction);
        exit(Grouped);
    end;

    local procedure UY(Value: Text): Text
    begin
        if Value.Trim() = '' then
            exit(Unknown);
        exit(Value);
    end;

    // ------------------------------------------------------------------
    // ZPL primitives — all take LANDSCAPE canvas coordinates (1218 x 812) and
    // rotate them 90° clockwise onto the portrait stock (812 x 1218):
    // canvas (x, y, w, h) -> stock (LabelWidth - y - h, x, h, w), text ^A0R.
    // ------------------------------------------------------------------

    local procedure Row4(Y: Integer; Height: Integer; LabelA: Text; ValueB: Text; LabelC: Text; ValueD: Text): Text
    begin
        exit(
            Cell(24, Y, 272, Height, 26, 24, 1, LabelA) +
            Cell(296, Y, 296, Height, 26, 22, 1, ValueB) +
            Cell(592, Y, 306, Height, 26, 24, 1, LabelC) +
            Cell(898, Y, 296, Height, 26, 22, 1, ValueD));
    end;

    local procedure Row2(Y: Integer; Height: Integer; LabelA: Text; Value: Text): Text
    begin
        exit(
            Cell(24, Y, 272, Height, 26, 24, 1, LabelA) +
            Cell(296, Y, 898, Height, 26, 22, 1, Value));
    end;

    local procedure RowLeft(Y: Integer; Height: Integer; LabelA: Text; Value: Text): Text
    begin
        exit(
            Cell(24, Y, 272, Height, 24, 22, 1, LabelA) +
            Cell(296, Y, 296, Height, 24, 20, 1, Value));
    end;

    /// <summary>Boxed cell with one line of text, vertically centred; Align 1 = centred (the report centres every cell).</summary>
    local procedure Cell(X: Integer; Y: Integer; Width: Integer; Height: Integer; FontHeight: Integer; FontWidth: Integer; Align: Integer; Value: Text): Text
    var
        TextY: Integer;
    begin
        TextY := Y + (Height - FontHeight) div 2;
        exit(Box(X, Y, Width, Height, 2) + Text(X + 6, TextY, FontHeight, FontWidth, Width - 12, Align, Value));
    end;

    /// <summary>
    /// One line of text. ^FB with a single line OVERPRINTS overflow on the same
    /// line (17 Eyl photo: "MADDE KATEGORİSİ", "SON KULLANMA TARİHİ" garbled,
    /// "KARANTİN-" hyphenated), so the font width is narrowed until the text
    /// fits the box (font 0 glyphs average ~0.55 x the width parameter).
    /// </summary>
    local procedure Text(X: Integer; Y: Integer; FontHeight: Integer; FontWidth: Integer; BoxWidth: Integer; Align: Integer; Value: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        AlignCode: Text;
    begin
        if Value = '' then
            exit('');
        AlignCode := 'L';
        if Align = 1 then
            AlignCode := 'C';
        FontWidth := FitFontWidth(Value, FontWidth, BoxWidth);
        exit(
            '^FO' + Format(LabelWidth - Y - FontHeight) + ',' + Format(X) + '^A0R,' + Format(FontHeight) + ',' + Format(FontWidth) +
            '^FH_^FB' + Format(BoxWidth) + ',1,0,' + AlignCode + '^FD' + ZplEncoder.EncodeFieldData(Value) + '^FS');
    end;

    /// <summary>Largest font width (dots, min 12) at which Value fits MaxWidth on one line.</summary>
    local procedure FitFontWidth(Value: Text; FontWidth: Integer; MaxWidth: Integer): Integer
    var
        Width: Integer;
    begin
        if StrLen(Value) = 0 then
            exit(FontWidth);
        if StrLen(Value) * FontWidth * 55 div 100 <= MaxWidth then
            exit(FontWidth);
        Width := MaxWidth * 100 div (55 * StrLen(Value));
        if Width < 12 then
            Width := 12;
        exit(Width);
    end;

    local procedure Box(X: Integer; Y: Integer; Width: Integer; Height: Integer; Thickness: Integer): Text
    begin
        exit('^FO' + Format(LabelWidth - Y - Height) + ',' + Format(X) + '^GB' + Format(Height) + ',' + Format(Width) + ',' + Format(Thickness) + '^FS');
    end;

    local procedure Line(X: Integer; Y: Integer; Width: Integer; Thickness: Integer): Text
    begin
        exit(Box(X, Y, Width, Thickness, Thickness));
    end;

    local procedure Qr(X: Integer; Y: Integer; Magnification: Integer; Data: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        // Symbol size = modules x magnification (version 1 = 21 modules = 147 dots at 7).
        exit('^FO' + Format(LabelWidth - Y - 21 * Magnification) + ',' + Format(X) + '^BQN,2,' + Format(Magnification) + '^FH_^FDLA,' + ZplEncoder.EncodeFieldData(Data) + '^FS');
    end;
}
