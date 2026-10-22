// Kitoko (20 Eki 2026): etiket türü başına kullanılabilir alan anahtarları ve
// değerleri. Tasarım satırındaki "Alan" bu anahtarlardan birini seçer.
codeunit 72467 "DOPSWHS Label Layout Fields"
{
    Access = Public;

    /// <summary>Field keys a layout of this kind may reference.</summary>
    procedure KeysFor(Kind: Enum "DOPSWHS Label Kind"; var FieldKeys: List of [Text])
    begin
        Clear(FieldKeys);
        case Kind of
            Kind::Item:
                begin
                    FieldKeys.Add('ItemNo');
                    FieldKeys.Add('Description');
                    FieldKeys.Add('Description2');
                    FieldKeys.Add('UoM');
                    FieldKeys.Add('Gtin');
                    FieldKeys.Add('Barcode');
                    FieldKeys.Add('Category');
                    FieldKeys.Add('VariantCode');
                end;
            Kind::Bin:
                begin
                    FieldKeys.Add('BinCode');
                    FieldKeys.Add('LocationCode');
                    FieldKeys.Add('ZoneCode');
                    FieldKeys.Add('BinTypeCode');
                    FieldKeys.Add('Description');
                end;
            Kind::Zone:
                begin
                    FieldKeys.Add('ZoneCode');
                    FieldKeys.Add('LocationCode');
                    FieldKeys.Add('Description');
                end;
            // Kitoko (21 Eki 2026): LP / palet etiketi (docs/label-designer-contract.md).
            Kind::LP:
                begin
                    FieldKeys.Add('LPNo');
                    FieldKeys.Add('SSCC');
                    FieldKeys.Add('BarcodeData');
                    FieldKeys.Add('ItemNo');
                    FieldKeys.Add('Description');
                    FieldKeys.Add('LotNo');
                    FieldKeys.Add('ExpirationDate');
                    FieldKeys.Add('Quantity');
                    FieldKeys.Add('TotalQuantity');
                    FieldKeys.Add('UoM');
                    FieldKeys.Add('LocationCode');
                    FieldKeys.Add('BinCode');
                    FieldKeys.Add('ItemCount');
                    FieldKeys.Add('LineCount');
                    FieldKeys.Add('ExtraLines');
                    // Kitoko (22 Eki 2026): QR'lı LP etiketi ve karma palet içerik satırları.
                    FieldKeys.Add('Lots');
                    FieldKeys.Add('VariantCode');
                    FieldKeys.Add('PackageNo');
                    FieldKeys.Add('SourceDocument');
                    FieldKeys.Add('ContentsLine1');
                    FieldKeys.Add('ContentsLine2');
                    FieldKeys.Add('ContentsLine3');
                end;
            // Kitoko (22 Eki 2026): lot etiketi (bir LP'deki her ürün + lot için bir etiket).
            Kind::Lot:
                begin
                    FieldKeys.Add('ItemNo');
                    FieldKeys.Add('Description');
                    FieldKeys.Add('LotNo');
                    FieldKeys.Add('ExpirationDate');
                    FieldKeys.Add('Quantity');
                    FieldKeys.Add('UoM');
                    FieldKeys.Add('VariantCode');
                    FieldKeys.Add('SourceDocument');
                    FieldKeys.Add('VendorNo');
                    FieldKeys.Add('VendorName');
                    FieldKeys.Add('LPNo');
                end;
        end;
        FieldKeys.Add('Company');
        FieldKeys.Add('Today');
    end;

    /// <summary>Comma separated key list (StrMenu / error texts).</summary>
    procedure KeyList(Kind: Enum "DOPSWHS Label Kind"): Text
    var
        FieldKeys: List of [Text];
        FieldKey: Text;
        Result: Text;
    begin
        KeysFor(Kind, FieldKeys);
        foreach FieldKey in FieldKeys do begin
            if Result <> '' then
                Result += ',';
            Result += FieldKey;
        end;
        exit(Result);
    end;

    procedure IsValidKey(Kind: Enum "DOPSWHS Label Kind"; FieldKey: Text): Boolean
    var
        FieldKeys: List of [Text];
    begin
        KeysFor(Kind, FieldKeys);
        exit(FieldKeys.Contains(FieldKey));
    end;

    procedure ItemValues(var Item: Record Item; var Values: Dictionary of [Text, Text])
    begin
        Clear(Values);
        Values.Add('ItemNo', Item."No.");
        Values.Add('Description', Item.Description);
        Values.Add('Description2', Item."Description 2");
        Values.Add('UoM', Item."Base Unit of Measure");
        Values.Add('Gtin', Item.GTIN);
        Values.Add('Barcode', Item.GTIN);
        Values.Add('Category', Item."Item Category Code");
        Values.Add('VariantCode', '');
        AddCommon(Values);
    end;

    procedure BinValues(var Bin: Record Bin; var Values: Dictionary of [Text, Text])
    begin
        Clear(Values);
        Values.Add('BinCode', Bin.Code);
        Values.Add('LocationCode', Bin."Location Code");
        Values.Add('ZoneCode', Bin."Zone Code");
        Values.Add('BinTypeCode', Bin."Bin Type Code");
        Values.Add('Description', Bin.Description);
        AddCommon(Values);
    end;

    procedure ZoneValues(var Zone: Record Zone; var Values: Dictionary of [Text, Text])
    begin
        Clear(Values);
        Values.Add('ZoneCode', Zone.Code);
        Values.Add('LocationCode', Zone."Location Code");
        Values.Add('Description', Zone.Description);
        AddCommon(Values);
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): LP label values from the LP header and its first item
    /// line; ItemCount is the number of distinct items on the LP. Like the built-in
    /// LP label: BarcodeData = SSCC (else LP no.), ExtraLines = "+N DİĞER SATIR".
    /// TotalQuantity sums the item lines when they share one unit, else stays empty.
    /// Kitoko (22 Eki 2026): ExpirationDate = earliest date of the lines, Lots = the
    /// distinct lots ("L1, L2 +3"), ContentsLine1..3 = "ItemNo · Lot · Qty UoM" per
    /// line (more than three lines: two lines and "+N SATIR DAHA"), SourceDocument =
    /// the document the LP came from (line source, pending receipt or assignment).
    /// </summary>
    procedure LpValues(var LP: Record "DOPSWHS LP Header"; var Values: Dictionary of [Text, Text])
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        Items: List of [Code[20]];
        Lots: List of [Text];
        Contents: List of [Text];
        First: Boolean;
        ItemNo: Text;
        Description: Text;
        LotNo: Text;
        VariantCode: Text;
        PackageNo: Text;
        SourceDocument: Text;
        Quantity: Text;
        UoM: Text;
        BarcodeData: Text;
        ExtraLines: Text;
        ContentsLine: array[3] of Text;
        EarliestExpiration: Date;
        TotalQuantity: Decimal;
        LineCount: Integer;
        i: Integer;
        SameUoM: Boolean;
    begin
        Clear(Values);
        SameUoM := true;
        First := true;
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then
            repeat
                if First then begin
                    First := false;
                    ItemNo := LPLine."Item No.";
                    if Item.Get(LPLine."Item No.") then
                        Description := Item.Description;
                    LotNo := LPLine."Lot No.";
                    VariantCode := LPLine."Variant Code";
                    PackageNo := LPLine."Package No.";
                    Quantity := Format(LPLine.Quantity);
                    UoM := LPLine."Unit of Measure";
                end;
                if (SourceDocument = '') and (LPLine."Source Document No." <> '') then
                    SourceDocument := DocumentText(LPLine."Source Document Type", LPLine."Source Document No.");
                if LPLine."Expiration Date" <> 0D then
                    if (EarliestExpiration = 0D) or (LPLine."Expiration Date" < EarliestExpiration) then
                        EarliestExpiration := LPLine."Expiration Date";
                if (LPLine."Lot No." <> '') and not Lots.Contains(LPLine."Lot No.") then
                    Lots.Add(LPLine."Lot No.");
                if not Items.Contains(LPLine."Item No.") then
                    Items.Add(LPLine."Item No.");
                LineCount += 1;
                if LineCount <= 3 then
                    Contents.Add(ContentsText(LPLine));
                TotalQuantity += LPLine.Quantity;
                if LPLine."Unit of Measure" <> UoM then
                    SameUoM := false;
            until LPLine.Next() = 0;
        if SourceDocument = '' then
            if LP."Pending Receipt No." <> '' then
                SourceDocument := DocumentText(Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, LP."Pending Receipt No.")
            else
                if LP."Assigned Document No." <> '' then
                    SourceDocument := DocumentText(LP."Assigned Document Type", LP."Assigned Document No.");
        for i := 1 to Contents.Count() do
            ContentsLine[i] := Contents.Get(i);
        if LineCount > 3 then
            ContentsLine[3] := StrSubstNo('+%1 SATIR DAHA', LineCount - 2);
        BarcodeData := LP.SSCC;
        if BarcodeData = '' then
            BarcodeData := LP."No.";
        if LineCount > 1 then
            ExtraLines := StrSubstNo('+%1 DİĞER SATIR', LineCount - 1);
        Values.Add('LPNo', LP."No.");
        Values.Add('SSCC', LP.SSCC);
        Values.Add('BarcodeData', BarcodeData);
        Values.Add('ItemNo', ItemNo);
        Values.Add('Description', Description);
        Values.Add('LotNo', LotNo);
        if EarliestExpiration <> 0D then
            Values.Add('ExpirationDate', FormatDate(EarliestExpiration))
        else
            Values.Add('ExpirationDate', '');
        Values.Add('Quantity', Quantity);
        if (LineCount > 0) and SameUoM then
            Values.Add('TotalQuantity', Format(TotalQuantity))
        else
            Values.Add('TotalQuantity', '');
        Values.Add('UoM', UoM);
        Values.Add('LocationCode', LP."Location Code");
        Values.Add('BinCode', LP."Bin Code");
        Values.Add('ItemCount', Format(Items.Count()));
        Values.Add('LineCount', Format(LineCount));
        Values.Add('ExtraLines', ExtraLines);
        Values.Add('Lots', LotsText(Lots));
        Values.Add('VariantCode', VariantCode);
        Values.Add('PackageNo', PackageNo);
        Values.Add('SourceDocument', SourceDocument);
        Values.Add('ContentsLine1', ContentsLine[1]);
        Values.Add('ContentsLine2', ContentsLine[2]);
        Values.Add('ContentsLine3', ContentsLine[3]);
        AddCommon(Values);
    end;

    /// <summary>
    /// Kitoko (22 Eki 2026): lot label values of one item + lot of an LP. Vendor =
    /// the item card's vendor (cheap, no ledger lookup).
    /// </summary>
    procedure LotValues(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; ExpirationDate: Date; Quantity: Decimal; UoM: Code[10]; SourceDocument: Text; LPNo: Code[20]; var Values: Dictionary of [Text, Text])
    var
        Item: Record Item;
        Vendor: Record Vendor;
        Description: Text;
        VendorNo: Text;
        VendorName: Text;
    begin
        Clear(Values);
        if Item.Get(ItemNo) then begin
            Description := Item.Description;
            VendorNo := Item."Vendor No.";
            if Item."Vendor No." <> '' then
                if Vendor.Get(Item."Vendor No.") then
                    VendorName := Vendor.Name;
        end;
        Values.Add('ItemNo', ItemNo);
        Values.Add('Description', Description);
        Values.Add('LotNo', LotNo);
        if ExpirationDate <> 0D then
            Values.Add('ExpirationDate', FormatDate(ExpirationDate))
        else
            Values.Add('ExpirationDate', '');
        Values.Add('Quantity', Format(Quantity));
        Values.Add('UoM', UoM);
        Values.Add('VariantCode', VariantCode);
        Values.Add('SourceDocument', SourceDocument);
        Values.Add('VendorNo', VendorNo);
        Values.Add('VendorName', VendorName);
        Values.Add('LPNo', LPNo);
        AddCommon(Values);
    end;

    /// <summary>"L1, L2 +3": the first two distinct lots and how many more.</summary>
    local procedure LotsText(Lots: List of [Text]): Text
    var
        Result: Text;
        i: Integer;
    begin
        for i := 1 to Lots.Count() do
            if i <= 2 then begin
                if Result <> '' then
                    Result += ', ';
                Result += Lots.Get(i);
            end;
        if Lots.Count() > 2 then
            Result += StrSubstNo(' +%1', Lots.Count() - 2);
        exit(Result);
    end;

    /// <summary>"ItemNo · Lot · Qty UoM"; an empty lot is left out.</summary>
    local procedure ContentsText(var LPLine: Record "DOPSWHS LP Line"): Text
    var
        Result: Text;
    begin
        Result := LPLine."Item No.";
        if LPLine."Lot No." <> '' then
            Result += ' · ' + LPLine."Lot No.";
        Result += ' · ' + DelChr(Format(LPLine.Quantity) + ' ' + LPLine."Unit of Measure", '>', ' ');
        exit(Result);
    end;

    /// <summary>Short Turkish document text for the label, e.g. "KABUL RE000123".</summary>
    procedure DocumentText(DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]): Text
    begin
        if DocNo = '' then
            exit('');
        case DocType of
            DocType::WhseReceipt:
                exit('KABUL ' + DocNo);
            DocType::WhsePick:
                exit('TOPLAMA ' + DocNo);
            DocType::WhseShipment:
                exit('SEVK ' + DocNo);
            DocType::WhsePutaway:
                exit('YERLEŞTİRME ' + DocNo);
            DocType::WhseMovement:
                exit('HAREKET ' + DocNo);
            DocType::ProdConsumption,
            DocType::ProdOutput:
                exit('ÜRETİM ' + DocNo);
            DocType::Assembly:
                exit('MONTAJ ' + DocNo);
        end;
        exit(DocNo);
    end;

    /// <summary>Kitoko (21 Eki 2026): Turkish caption of a field key for the designer's field list.</summary>
    procedure FieldLabel(FieldKey: Text): Text
    begin
        case FieldKey of
            'ItemNo':
                exit('Ürün No');
            'Description':
                exit('Açıklama');
            'Description2':
                exit('Açıklama 2');
            'UoM':
                exit('Birim');
            'Gtin':
                exit('GTIN');
            'Barcode':
                exit('Barkod');
            'Category':
                exit('Kategori');
            'VariantCode':
                exit('Varyant');
            'BinCode':
                exit('Raf Kodu');
            'LocationCode':
                exit('Lokasyon');
            'ZoneCode':
                exit('Bölge Kodu');
            'BinTypeCode':
                exit('Raf Tipi');
            'LPNo':
                exit('LP No');
            'SSCC':
                exit('SSCC');
            'LotNo':
                exit('Lot No');
            'ExpirationDate':
                exit('Son Kullanma Tarihi');
            'Quantity':
                exit('Miktar');
            'ItemCount':
                exit('Ürün Çeşidi Sayısı');
            'BarcodeData':
                exit('Barkod Verisi (SSCC, yoksa LP No)');
            'TotalQuantity':
                exit('Toplam Miktar');
            'LineCount':
                exit('Satır Sayısı');
            'ExtraLines':
                exit('Diğer Satırlar (+N DİĞER SATIR)');
            'Lots':
                exit('Lotlar (L1, L2 +N)');
            'PackageNo':
                exit('Paket No');
            'VendorNo':
                exit('Satıcı No');
            'VendorName':
                exit('Satıcı Adı');
            'SourceDocument':
                exit('Kaynak Belge');
            'ContentsLine1':
                exit('İçerik Satırı 1 (Ürün · Lot · Miktar)');
            'ContentsLine2':
                exit('İçerik Satırı 2');
            'ContentsLine3':
                exit('İçerik Satırı 3 (fazlası +N SATIR DAHA)');
            'Company':
                exit('Şirket');
            'Today':
                exit('Bugünün Tarihi');
        end;
        exit(FieldKey);
    end;

    /// <summary>Made-up values only; preview and test print never carry real data.</summary>
    procedure SampleValues(Kind: Enum "DOPSWHS Label Kind"; var Values: Dictionary of [Text, Text])
    begin
        Clear(Values);
        case Kind of
            Kind::Item:
                begin
                    Values.Add('ItemNo', 'SK-10025');
                    Values.Add('Description', 'ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE');
                    Values.Add('Description2', 'İKİNCİ AÇIKLAMA');
                    Values.Add('UoM', 'ADET');
                    Values.Add('Gtin', '8690000012345');
                    Values.Add('Barcode', '8690000012345');
                    Values.Add('Category', 'KOZMETİK');
                    Values.Add('VariantCode', 'MAVİ');
                end;
            Kind::Bin:
                begin
                    Values.Add('BinCode', 'K.K03.11.UST');
                    Values.Add('LocationCode', 'ANA');
                    Values.Add('ZoneCode', 'K');
                    Values.Add('BinTypeCode', 'PICK');
                    Values.Add('Description', 'KOZMETİK ÜST RAF');
                end;
            Kind::Zone:
                begin
                    Values.Add('ZoneCode', 'K');
                    Values.Add('LocationCode', 'ANA');
                    Values.Add('Description', 'KOZMETİK ALANI');
                end;
            Kind::LP:
                begin
                    Values.Add('LPNo', 'LP000123');
                    Values.Add('SSCC', '386900000000012345');
                    Values.Add('BarcodeData', '386900000000012345');
                    Values.Add('ItemNo', 'SK-10025');
                    Values.Add('Description', 'ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE');
                    Values.Add('LotNo', 'LOT-2026-001');
                    Values.Add('ExpirationDate', '31.12.2027');
                    Values.Add('Quantity', '48');
                    Values.Add('TotalQuantity', '60');
                    Values.Add('UoM', 'KOLİ');
                    Values.Add('LocationCode', 'ANA');
                    Values.Add('BinCode', 'K.K03.11.UST');
                    Values.Add('ItemCount', '1');
                    Values.Add('LineCount', '2');
                    Values.Add('ExtraLines', '+1 DİĞER SATIR');
                    Values.Add('Lots', 'LOT-2026-001, LOT-2026-002');
                    Values.Add('VariantCode', 'MAVİ');
                    Values.Add('PackageNo', 'PK-0007');
                    Values.Add('SourceDocument', 'KABUL RE000123');
                    Values.Add('ContentsLine1', 'SK-10025 · LOT-2026-001 · 48 KOLİ');
                    Values.Add('ContentsLine2', 'SK-10031 · LOT-2026-002 · 12 KOLİ');
                    Values.Add('ContentsLine3', '');
                end;
            Kind::Lot:
                begin
                    Values.Add('ItemNo', 'SK-10025');
                    Values.Add('Description', 'ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE');
                    Values.Add('LotNo', 'LOT-2026-001');
                    Values.Add('ExpirationDate', '31.12.2027');
                    Values.Add('Quantity', '48');
                    Values.Add('UoM', 'KOLİ');
                    Values.Add('VariantCode', 'MAVİ');
                    Values.Add('SourceDocument', 'KABUL RE000123');
                    Values.Add('VendorNo', 'S-0042');
                    Values.Add('VendorName', 'ÖRNEK TEDARİKÇİ A.Ş.');
                    Values.Add('LPNo', 'LP000123');
                end;
        end;
        AddCommon(Values);
    end;

    local procedure FormatDate(Value: Date): Text
    begin
        exit(Format(Value, 0, '<Day,2>.<Month,2>.<Year4>'));
    end;

    local procedure AddCommon(var Values: Dictionary of [Text, Text])
    begin
        Values.Add('Company', CompanyProperty.DisplayName());
        Values.Add('Today', FormatDate(Today()));
    end;
}
