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
            PrintOnlyIfDetail = true;

            column(CompanyLogo; CompanyInformation.Picture) { }
            column(LpNo; "No.") { }

            // BADE (9 Eki 2026): karma palette (LP001645'te 8 ürün) yalnız ilk
            // satır basılıyordu. Terminal ZPL'i gibi her ürün/lot/kaynak satırı
            // grubu için ayrı etiket; RDLC her veri satırını ayrı sayfa basar.
            dataitem(LabelLine; "DOPSWHS LP Line")
            {
                DataItemLink = "LP No." = field("No.");
                DataItemTableView = sorting("LP No.", "Line No.") where(Quantity = filter(> 0));

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
                column(DokumanNo; DocumentNo) { }
                column(RevizyonNo; RevisionNo) { }
                column(RevizyonTarihi; RevisionDate) { }

                trigger OnPreDataItem()
                begin
                    Clear(PrintedGroups);
                end;

                trigger OnAfterGetRecord()
                var
                    GroupKey: Text;
                begin
                    if "Item No." = '' then
                        CurrReport.Skip();
                    // Aynı ürün/lot/kaynak satırına ait bölünmüş satırlar tek etikette toplanır.
                    GroupKey := PalletItemGroupKey(LabelLine);
                    if PrintedGroups.ContainsKey(GroupKey) then
                        CurrReport.Skip();
                    PrintedGroups.Add(GroupKey, true);
                    LoadDynamicLabelData(LabelLine);
                end;
            }

            trigger OnPreDataItem()
            begin
                CompanyInformation.Get();
                CompanyInformation.CalcFields(Picture);
            end;

            trigger OnAfterGetRecord()
            var
                ContentLine: Record "DOPSWHS LP Line";
            begin
                // İçeriği olmayan LP boş etiket basmaz.
                ContentLine.SetRange("LP No.", "No.");
                ContentLine.SetFilter("Item No.", '<>%1', '');
                ContentLine.SetFilter(Quantity, '>0');
                if ContentLine.IsEmpty() then
                    CurrReport.Skip();
                QrCodeBase64 := LpQrCode("No.");
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

    local procedure LoadDynamicLabelData(LPLine: Record "DOPSWHS LP Line")
    var
        Item: Record Item;
        ItemCategory: Record "Item Category";
        MteBuilder: Codeunit "DOPSWHS MTE Zpl Builder";
        Values: Dictionary of [Text, Text];
        Options: JsonObject;
        OptionsJson: Text;
        LabelQuantity: Decimal;
    begin
        ClearLabelData();

        // BADE (8 Eki 2026): BC etiketi terminal etiketiyle aynı veriyi basmalı.
        // Kategori (üst kategori), INCI adı, tedarikçi madde adı, depolama koşulu
        // ve doküman bilgisi terminalin ZPL'iyle aynı çözümlemeden gelir.
        if InspectorNameOverride <> '' then
            Options.Add('operatorDisplayName', InspectorNameOverride);
        Options.WriteTo(OptionsJson);
        MteBuilder.GetLabelValues(LicensePlate, LPLine, OptionsJson, Values);

        ItemNo := LPLine."Item No.";
        LotNoValue := LPLine."Lot No.";
        CategoryDescription := UnknownIfBlank(Values.Get('Category'));
        ItemDescription := UnknownIfBlank(Values.Get('ItemName'));
        InciName := UnknownIfBlank(Values.Get('InciName'));
        VendorName := UnknownIfBlank(Values.Get('VendorName'));
        SupplierLotNo := UnknownIfBlank(Values.Get('SupplierLot'));
        ProductionDateText := UnknownIfBlank(Values.Get('ProductionDate'));
        ExpirationDateText := UnknownIfBlank(Values.Get('ExpirationDate'));
        StorageCondition := UnknownIfBlank(Values.Get('StorageCondition'));
        ReceiptDateText := UnknownIfBlank(Values.Get('ReceiptDate'));
        ReceiptNo := UnknownIfBlank(Values.Get('ReceiptNo'));
        CheckedBy := UnknownIfBlank(Values.Get('Inspector'));
        ApprovedBy := 'U.Y';
        QualityApprovalName := UnknownIfBlank(Values.Get('QcName'));
        QualityApprovalDate := UnknownIfBlank(Values.Get('QcDate'));
        DocumentNo := UnknownIfBlank(Values.Get('DocumentNo'));
        RevisionNo := UnknownIfBlank(Values.Get('RevisionNo'));
        RevisionDate := UnknownIfBlank(Values.Get('RevisionDate'));
        if Item.Get(ItemNo) then begin
            ItemCategoryCode := Item."Item Category Code";
            if ItemCategory.Get(ItemCategoryCode) then
                ParentCategoryCode := ItemCategory."Parent Category";
        end;

        LabelQuantity := PalletItemGroupQuantity(LPLine);
        QuantityUomText := StrSubstNo('%1 %2', LabelQuantity, LPLine."Unit of Measure");
    end;

    local procedure LpQrCode(LpNo: Code[20]): Text
    var
        BarcodeImageProvider: Interface "Barcode Image Provider 2D";
        BarcodeImage: Codeunit "Temp Blob";
        Base64Convert: Codeunit "Base64 Convert";
        ImageInStream: InStream;
    begin
        BarcodeImageProvider := Enum::"Barcode Image Provider 2D"::Dynamics2D;
        BarcodeImage := BarcodeImageProvider.EncodeImage(LpNo, Enum::"Barcode Symbology 2D"::"QR-Code");
        if not BarcodeImage.HasValue() then
            Error('%1 LP numarası için QR kod üretilemedi.', LpNo);
        BarcodeImage.CreateInStream(ImageInStream);
        exit(Base64Convert.ToBase64(ImageInStream));
    end;

    local procedure PalletItemGroupKey(LPLine: Record "DOPSWHS LP Line"): Text
    begin
        exit(
            LPLine."Item No." + '|' + LPLine."Variant Code" + '|' + LPLine."Unit of Measure" + '|' +
            LPLine."Lot No." + '|' + LPLine."Serial No." + '|' + Format(LPLine."Source Document Type") + '|' +
            LPLine."Source Document No." + '|' + Format(LPLine."Source Document Line No."));
    end;

    local procedure UnknownIfBlank(Value: Text): Text
    begin
        if Value.Trim() = '' then
            exit('U.Y');
        exit(Value);
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
        PrintedGroups: Dictionary of [Text, Boolean];
}
