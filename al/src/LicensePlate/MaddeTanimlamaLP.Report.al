report 72375 "DOPSWHS MTE LP Report"
{
    Caption = 'Madde Tanımlama Etiketi - LP';
    UsageCategory = ReportsAndAnalysis;
    ApplicationArea = All;
    DefaultLayout = RDLC;
    RDLCLayout = './src/LicensePlate/MaddeTanimlamaLP.rdlc';

    dataset
    {
        dataitem(LicensePlate; "DOPSWHS LP Header")
        {
            RequestFilterFields = "No.";

            column(CompanyLogo; CompanyInformation.Picture) { }
            column(MaddeKodu; ItemNo) { }
            column(MaddeKategoriKodu; CategoryDescription) { }
            column(ItemCategoryCode; ItemCategoryCode) { }
            column(ItemCategoryParentCategory; ParentCategoryCode) { }
            column(MaddeAdi; ItemDescription) { }
            column(InciAdi; InciName) { }
            column(TedarikciAdi; VendorName) { }
            column(TedarikciLotu; SupplierLotNo) { }
            column(UretimTarihiTxt; ProductionDateText) { }
            column(LotNo; LotNoValue) { }
            column(SonKullanmaTarihiTxt; ExpirationDateText) { }
            column(MiktarBirimTxt; QuantityUomText) { }
            column(DepolamaKosulu; StorageCondition) { }
            column(DepoGirisTarihiTxt; ReceiptDateText) { }
            column(DepoGirisNo; ReceiptNo) { }
            column(KontrolEden; CheckedBy) { }
            column(Onaylayan; ApprovedBy) { }
            column(KaliteKontrolOnayiIsim; QualityApprovalName) { }
            column(KaliteKontrolOnayiTarih; QualityApprovalDate) { }
            column(QRCodeBase64; QrCodeBase64) { }
            column(LpNo; "No.") { }
            column(DokumanNo; DocumentNo) { }
            column(RevizyonNo; RevisionNo) { }
            column(RevizyonTarihi; RevisionDate) { }

            trigger OnPreDataItem()
            begin
                CompanyInformation.Get();
                CompanyInformation.CalcFields(Picture);
            end;

            trigger OnAfterGetRecord()
            begin
                if not LoadDynamicLabelData() then
                    CurrReport.Skip();
            end;
        }
    }

    requestpage
    {
        layout
        {
            area(Content)
            {
                field(InspectorName; InspectorNameOverride)
                {
                    ApplicationArea = All;
                    Caption = 'Giriş Yapan';
                }
            }
        }
    }

    local procedure LoadDynamicLabelData(): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemCategory: Record "Item Category";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LotInformation: Record "Lot No. Information";
        Vendor: Record Vendor;
        BarcodeImageProvider: Interface "Barcode Image Provider 2D";
        BarcodeImage: Codeunit "Temp Blob";
        Base64Convert: Codeunit "Base64 Convert";
        ImageInStream: InStream;
        LabelQuantity: Decimal;
    begin
        ClearLabelData();

        LPLine.SetRange("LP No.", LicensePlate."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindFirst() then
            exit(false);

        ItemNo := LPLine."Item No.";
        LotNoValue := LPLine."Lot No.";
        if Item.Get(ItemNo) then begin
            ItemDescription := Item.Description;
            InciName := Item."Search Description";
            ItemCategoryCode := Item."Item Category Code";
            if ItemCategory.Get(ItemCategoryCode) then begin
                CategoryDescription := ItemCategory.Description;
                ParentCategoryCode := ItemCategory."Parent Category";
            end;
            if CategoryDescription = '' then
                CategoryDescription := ItemCategoryCode;
            if (Item."Vendor No." <> '') and Vendor.Get(Item."Vendor No.") then
                VendorName := Vendor.Name;
        end;
        SetUnknownIfBlank(CategoryDescription);
        SetUnknownIfBlank(InciName);
        SetUnknownIfBlank(VendorName);

        if (ItemNo <> '') and (LotNoValue <> '') and
           LotInformation.Get(ItemNo, LPLine."Variant Code", LotNoValue)
        then begin
            SupplierLotNo := LotInformation.Description;
            if SupplierLotNo = '' then
                SupplierLotNo := LotInformation."DOPSWHS Supplier Lot No.";
        end;
        SetUnknownIfBlank(SupplierLotNo);

        ProductionDateText := 'U.Y';
        if LPLine."Expiration Date" = 0D then
            ExpirationDateText := 'U.Y'
        else
            ExpirationDateText := FormatDate(LPLine."Expiration Date");

        LabelQuantity := PalletItemGroupQuantity(LPLine);
        QuantityUomText := StrSubstNo('%1 %2', LabelQuantity, LPLine."Unit of Measure");
        StorageCondition := 'U.Y';

        if (LPLine."Source Item Ledger Entry No." <> 0) and
           ItemLedgerEntry.Get(LPLine."Source Item Ledger Entry No.")
        then begin
            ReceiptDateText := FormatDate(ItemLedgerEntry."Posting Date");
            ReceiptNo := ItemLedgerEntry."Document No.";
        end else begin
            ReceiptNo := LPLine."Source Document No.";
            if LicensePlate."Built DateTime" <> 0DT then
                ReceiptDateText := FormatDate(DT2Date(LicensePlate."Built DateTime"));
        end;
        SetUnknownIfBlank(ReceiptDateText);
        SetUnknownIfBlank(ReceiptNo);

        CheckedBy := InspectorNameOverride;
        if CheckedBy = '' then
            CheckedBy := LicensePlate."Built By User";
        SetUnknownIfBlank(CheckedBy);
        ApprovedBy := 'U.Y';
        QualityApprovalName := 'U.Y';
        QualityApprovalDate := 'U.Y';
        DocumentNo := 'U.Y';
        RevisionNo := 'U.Y';
        RevisionDate := 'U.Y';

        BarcodeImageProvider := Enum::"Barcode Image Provider 2D"::Dynamics2D;
        BarcodeImage := BarcodeImageProvider.EncodeImage(LicensePlate."No.", Enum::"Barcode Symbology 2D"::"QR-Code");
        if not BarcodeImage.HasValue() then
            Error('%1 LP numarası için QR kod üretilemedi.', LicensePlate."No.");
        BarcodeImage.CreateInStream(ImageInStream);
        QrCodeBase64 := Base64Convert.ToBase64(ImageInStream);
        exit(true);
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
        GroupLine.SetFilter(Quantity, '>0');
        if GroupLine.FindSet() then
            repeat
                GroupQuantity += GroupLine.Quantity;
            until GroupLine.Next() = 0;
        exit(GroupQuantity);
    end;

    local procedure FormatDate(Value: Date): Text
    begin
        exit(Format(Value, 0, '<Day,2>.<Month,2>.<Year4>'));
    end;

    local procedure SetUnknownIfBlank(var Value: Text)
    begin
        if Value = '' then
            Value := 'U.Y';
    end;

    local procedure ClearLabelData()
    begin
        Clear(ItemNo);
        Clear(ItemDescription);
        Clear(ItemCategoryCode);
        Clear(ParentCategoryCode);
        Clear(CategoryDescription);
        Clear(InciName);
        Clear(VendorName);
        Clear(SupplierLotNo);
        Clear(LotNoValue);
        Clear(ReceiptDateText);
        Clear(ReceiptNo);
        Clear(CheckedBy);
        Clear(QrCodeBase64);
    end;

    var
        CompanyInformation: Record "Company Information";
        ItemNo: Code[20];
        ItemDescription: Text;
        ItemCategoryCode: Code[20];
        ParentCategoryCode: Code[20];
        CategoryDescription: Text;
        InciName: Text;
        VendorName: Text;
        SupplierLotNo: Text;
        ProductionDateText: Text;
        LotNoValue: Code[50];
        ExpirationDateText: Text;
        QuantityUomText: Text;
        StorageCondition: Text;
        ReceiptDateText: Text;
        ReceiptNo: Text;
        CheckedBy: Text;
        InspectorNameOverride: Text;
        ApprovedBy: Text;
        QualityApprovalName: Text;
        QualityApprovalDate: Text;
        QrCodeBase64: Text;
        DocumentNo: Text;
        RevisionNo: Text;
        RevisionDate: Text;
}
