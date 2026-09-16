/// <summary>
/// BADE (16 Eyl 2026): the terminal's ZPL "Madde Tanımlama Etiketi" drawn as
/// the customer's report layout (BadeProduction report 60150) on the 10 x 8 cm
/// Zebra stock: boxed table with the same rows, KABUL / RED / KARANTİNA cells,
/// QR (LP number), and the operator's extra fields (Giriş Yapan, tedarikçi
/// lotu, kalite kontrol onayı, doküman / revizyon). Data is resolved the way
/// the report resolves it (parent category, INCI name, receipt vendor,
/// warehouse class, posted receipt number) without a compile dependency on
/// the customer extension.
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

    // 100 x 80 mm at 203 dpi.
    var
        LabelWidth: Integer;
        LabelHeight: Integer;
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
        LabelHeight := 640;
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
        // Frame and header
        // ------------------------------------------------------------------
        Zpl := '^XA^CI28^PW' + Format(LabelWidth) + '^LL' + Format(LabelHeight) +
            Box(6, 6, 800, 628, 3) +
            Text(16, 24, 26, 26, 240, 0, CompanyText) +
            Text(250, 20, 34, 30, 550, 1, 'MADDE TANIMLAMA ETİKETİ') +
            Line(6, 68, 800, 3);

        // ------------------------------------------------------------------
        // Rows (column A labels 200 wide, B values 220, C labels 170, D values 210)
        // ------------------------------------------------------------------
        Zpl += Row4(70, 'MADDE KODU', ItemNo, 'MADDE KATEGORİSİ', UY(CategoryText)) +
            Row2(104, 'MADDE ADI', UY(ItemName)) +
            Row2(138, 'INCI ADI', UY(InciName)) +
            Row2(172, 'TEDARİKÇİ ADI', UY(VendorName)) +
            Row2(206, 'TEDARİKÇİ LOTU', UY(SupplierLot)) +
            Row4(240, 'ÜRETİM TARİHİ', UY(ProductionDate), 'LOT NO', UY(LotNo)) +
            Row4(274, 'SON KULLANMA TARİHİ', UY(ExpirationDate), 'MİKTAR/BİRİM', QtyText) +
            // Left half rows 8..15 beside the decision/QR block.
            RowLeft(308, 34, 'DEPOLAMA KOŞULU', UY(StorageText)) +
            RowLeft(342, 34, 'DEPO GİRİŞ TARİHİ', UY(ReceiptDate)) +
            RowLeft(376, 34, 'DEPO GİRİŞ NO.', UY(ReceiptNo)) +
            RowLeft(410, 34, 'GİRİŞ YAPAN', UY(InspectorText)) +
            Cell(6, 444, 420, 34, 18, 18, 1, 'KALİTE KONTROL ONAYI') +
            RowLeft(478, 34, 'KONTROL EDEN', UY(QcName)) +
            RowLeft(512, 34, 'TARİH', UY(QcDate)) +
            RowLeft(546, 50, 'İMZA', '');

        // Decision boxes and QR (x 426..806, y 308..596).
        Zpl += Cell(426, 308, 130, 96, 22, 22, 1, 'KABUL') +
            Cell(426, 404, 130, 96, 22, 22, 1, 'RED') +
            Cell(426, 500, 130, 96, 20, 20, 1, 'KARANTİNA') +
            Box(556, 308, 250, 288, 2) +
            Qr(586, 322, 7, QrData) +
            Text(556, 560, 24, 24, 250, 1, QrData);

        // Footer
        Zpl += Cell(6, 596, 420, 38, 16, 16, 0, 'DOKÜMAN NO. / REVİZYON NO. / REVİZYON TARİHİ') +
            Cell(426, 596, 380, 38, 18, 18, 1, UY(DocumentNo) + ' / ' + UY(RevisionNo) + ' / ' + UY(RevisionDate)) +
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
    // ZPL primitives
    // ------------------------------------------------------------------

    local procedure Row4(Y: Integer; LabelA: Text; ValueB: Text; LabelC: Text; ValueD: Text): Text
    begin
        exit(
            Cell(6, Y, 200, 34, 18, 16, 0, LabelA) +
            Cell(206, Y, 220, 34, 20, 20, 0, ValueB) +
            Cell(426, Y, 170, 34, 18, 16, 0, LabelC) +
            Cell(596, Y, 210, 34, 20, 20, 0, ValueD));
    end;

    local procedure Row2(Y: Integer; LabelA: Text; Value: Text): Text
    begin
        exit(
            Cell(6, Y, 200, 34, 18, 16, 0, LabelA) +
            Cell(206, Y, 600, 34, 20, 20, 0, Value));
    end;

    local procedure RowLeft(Y: Integer; Height: Integer; LabelA: Text; Value: Text): Text
    begin
        exit(
            Cell(6, Y, 200, Height, 18, 16, 0, LabelA) +
            Cell(206, Y, 220, Height, 20, 20, 0, Value));
    end;

    /// <summary>Boxed cell with one line of text, vertically centred; Align 1 = centred.</summary>
    local procedure Cell(X: Integer; Y: Integer; Width: Integer; Height: Integer; FontHeight: Integer; FontWidth: Integer; Align: Integer; Value: Text): Text
    var
        TextY: Integer;
    begin
        TextY := Y + (Height - FontHeight) div 2;
        exit(Box(X, Y, Width, Height, 2) + Text(X + 6, TextY, FontHeight, FontWidth, Width - 12, Align, Value));
    end;

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
        exit(
            '^FO' + Format(X) + ',' + Format(Y) + '^A0N,' + Format(FontHeight) + ',' + Format(FontWidth) +
            '^FH_^FB' + Format(BoxWidth) + ',1,0,' + AlignCode + '^FD' + ZplEncoder.EncodeFieldData(Value) + '^FS');
    end;

    local procedure Box(X: Integer; Y: Integer; Width: Integer; Height: Integer; Thickness: Integer): Text
    begin
        exit('^FO' + Format(X) + ',' + Format(Y) + '^GB' + Format(Width) + ',' + Format(Height) + ',' + Format(Thickness) + '^FS');
    end;

    local procedure Line(X: Integer; Y: Integer; Width: Integer; Thickness: Integer): Text
    begin
        exit('^FO' + Format(X) + ',' + Format(Y) + '^GB' + Format(Width) + ',' + Format(Thickness) + ',' + Format(Thickness) + '^FS');
    end;

    local procedure Qr(X: Integer; Y: Integer; Magnification: Integer; Data: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        exit('^FO' + Format(X) + ',' + Format(Y) + '^BQN,2,' + Format(Magnification) + '^FH_^FDLA,' + ZplEncoder.EncodeFieldData(Data) + '^FS');
    end;
}
