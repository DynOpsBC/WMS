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
        end;
        AddCommon(Values);
    end;

    local procedure AddCommon(var Values: Dictionary of [Text, Text])
    begin
        Values.Add('Company', CompanyProperty.DisplayName());
        Values.Add('Today', Format(Today(), 0, '<Day,2>.<Month,2>.<Year4>'));
    end;
}
