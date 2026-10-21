/// <summary>
/// Kitoko (21 Eki 2026): sürükle-bırak etiket tasarımcısının BC tarafı:
/// DesignJson gidiş-dönüş, döndürme, EAN-13 / GS1-128, ^GFA resim, LP türü.
/// </summary>
codeunit 72161 "DOPSWHS Label Designer Tests"
{
    Subtype = Test;

    [Test]
    procedure DesignJsonRoundTripKeepsSeededLayout()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Json: Text;
        ZplBefore: Text;
        LinesBefore: Integer;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        ZplBefore := Engine.BuildSampleZpl('ITEM');
        LayoutLine.SetRange("Layout Code", 'ITEM');
        LinesBefore := LayoutLine.Count();

        Json := DesignerMgt.DesignToJson('ITEM');
        DesignerMgt.SaveFromJson('ITEM', Json);

        Assert.AreEqual(LinesBefore, LayoutLine.Count(), 'Every element is written back.');
        Assert.AreEqual(ZplBefore, Engine.BuildSampleZpl('ITEM'), 'DesignToJson -> SaveFromJson prints the same label.');
        LayoutLine.FindFirst();
        Assert.AreEqual(10000, LayoutLine."Line No.", 'Lines are renumbered in array order.');
        Assert.AreEqual('e10000', LayoutLine."Element Id", 'Designer id of a seeded line is kept.');
        Assert.AreEqual(Json, DesignerMgt.DesignToJson('ITEM'), 'A second round trip returns the same JSON.');
    end;

    [Test]
    procedure DesignJsonRoundTripKeepsDesignerProperties()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        LabelImage: Record "DOPSWHS Label Image";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Root: JsonObject;
        Token: JsonToken;
        Elements: JsonArray;
        Element: JsonToken;
        Images: JsonArray;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());

        LayoutLine.SetRange("Layout Code", 'DSG');
        Assert.AreEqual(4, LayoutLine.Count(), 'Four elements saved.');
        LayoutLine.Get('DSG', 10000);
        Assert.AreEqual('t1', LayoutLine."Element Id", 'Designer id stored.');
        Assert.AreEqual(90, LayoutLine.Rotation, 'Rotation stored.');
        Assert.IsTrue(LayoutLine.Bold, 'Bold stored.');
        Assert.AreEqual('DÖNEN', LayoutLine."Static Text", 'Static text stored.');
        LayoutLine.Get('DSG', 20000);
        Assert.AreEqual(LayoutLine.Symbology::EAN13, LayoutLine.Symbology, 'EAN-13 stored.');
        Assert.AreEqual('Gtin', LayoutLine."Source Field", 'Barcode field stored.');
        LayoutLine.Get('DSG', 30000);
        Assert.AreEqual(LayoutLine."Element Type"::Image, LayoutLine."Element Type", 'Image element stored.');
        Assert.AreEqual('LOGO1', LayoutLine."Image Id", 'Image id stored.');
        Assert.AreEqual(GfaTxt, LayoutLine.GetImageGf(), '^GFA data stored in the blob.');
        Assert.IsTrue(LabelImage.Get('LOGO1'), 'Uploaded image is upserted.');
        Assert.AreEqual('data:image/png;base64,iVBORw0KGgo=', LabelImage.GetDataUrl(), 'Image data URL kept.');

        Root.ReadFrom(DesignerMgt.DesignToJson('DSG'));
        Root.Get('kind', Token);
        Assert.AreEqual('Item', Token.AsValue().AsText(), 'Kind text.');
        Root.Get('elements', Token);
        Elements := Token.AsArray();
        Assert.AreEqual(4, Elements.Count(), 'Elements returned.');
        Elements.Get(0, Element);
        Assert.AreEqual(90, JsonInt(Element, 'rotation'), 'Rotation returned.');
        Assert.IsTrue(JsonBool(Element, 'bold'), 'Bold returned.');
        Assert.AreEqual('text', JsonText(Element, 'type'), 'Type returned.');
        Elements.Get(1, Element);
        Assert.AreEqual('barcode', JsonText(Element, 'type'), 'Barcode type returned.');
        Assert.AreEqual('ean13', JsonText(Element, 'symbology'), 'Symbology returned.');
        Elements.Get(2, Element);
        Assert.AreEqual(GfaTxt, JsonText(Element, 'imageGf'), '^GFA returned.');
        Root.Get('images', Token);
        Images := Token.AsArray();
        Assert.AreEqual(1, Images.Count(), 'Referenced image returned.');
        Images.Get(0, Token);
        Assert.AreEqual('LOGO1', JsonText(Token, 'id'), 'Image id returned.');
        Root.Get('fields', Token);
        Assert.IsTrue(Token.AsArray().Count() >= 8, 'Item fields listed for the designer.');
    end;

    [Test]
    procedure RotationUsesZplOrientation()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        Zpl := Engine.BuildSampleZpl('DSG');
        Assert.IsTrue(StrPos(Zpl, '^FO16,16^A0R,32,38^FH_^FB400,1,0,L^FDDÖNEN^FS') > 0, '90 degrees is ^A0R; bold is 20% wider.');
        Assert.IsTrue(StrPos(Zpl, '^GB40,160,40^FS') > 0, 'A box turned by 90 degrees swaps width and height.');
        Assert.AreEqual('N', Engine.OrientationCode(0), '0 = N');
        Assert.AreEqual('R', Engine.OrientationCode(90), '90 = R');
        Assert.AreEqual('I', Engine.OrientationCode(180), '180 = I');
        Assert.AreEqual('B', Engine.OrientationCode(270), '270 = B');

        Zpl := DesignerMgt.SampleZpl('DSG', StrSubstNo(OneElementJsonTxt, '"type":"barcode","xMm":2,"yMm":2,"wMm":30,"hMm":10,"rotation":270,"field":"ItemNo"'));
        Assert.IsTrue(StrPos(Zpl, '^BCB,80,N,N,N,A^FH_^FDSK-10025^FS') > 0, 'Rotated Code128 is ^BCB.');
        Zpl := DesignerMgt.SampleZpl('DSG', StrSubstNo(OneElementJsonTxt, '"type":"field","xMm":2,"yMm":2,"wMm":30,"rotation":180,"field":"ItemNo","fontMm":4'));
        Assert.IsTrue(StrPos(Zpl, '^A0I,32,32') > 0, '180 degrees is ^A0I.');
        Zpl := DesignerMgt.SampleZpl('DSG', StrSubstNo(OneElementJsonTxt, '"type":"qr","xMm":2,"yMm":2,"wMm":20,"rotation":90,"field":"ItemNo"'));
        Assert.IsTrue(StrPos(Zpl, '^BQN,2,') > 0, 'QR is never rotated.');
    end;

    [Test]
    procedure Ean13AndGs1128Barcodes()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        Zpl := Engine.BuildSampleZpl('DSG');
        Assert.IsTrue(StrPos(Zpl, '^BEN,80,Y,N^FH_^FD869000001234^FS') > 0, 'EAN-13 is ^BE with the first 12 digits (printer adds the check digit).');

        Zpl := DesignerMgt.SampleZpl('DSG', StrSubstNo(OneElementJsonTxt, '"type":"barcode","xMm":2,"yMm":2,"wMm":60,"hMm":10,"symbology":"ean13","field":"ItemNo"'));
        Assert.AreEqual(0, StrPos(Zpl, '^BE'), 'Non-numeric data is not printed as EAN-13.');
        Assert.IsTrue(StrPos(Zpl, '^BCN,80,N,N,N,A^FH_^FDSK-10025^FS') > 0, 'It falls back to Code128.');

        Zpl := DesignerMgt.SampleZpl('DSG', StrSubstNo(OneElementJsonTxt, '"type":"barcode","xMm":2,"yMm":2,"wMm":70,"hMm":10,"symbology":"gs1-128","showText":true,"text":"(01)08690000012345(10)LOT1"'));
        Assert.IsTrue(StrPos(Zpl, '^BCN,80,Y,N,N,D^FH_^FD(01)08690000012345(10)LOT1^FS') > 0, 'GS1-128 uses ^BC mode D (FNC1 + AIs).');
    end;

    [Test]
    procedure ImageGfaIsPassedThroughAndValidated()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        Zpl := Engine.BuildSampleZpl('DSG');
        Assert.IsTrue(StrPos(Zpl, '^FO480,16' + GfaTxt + '^FS') > 0, 'Image is ^FO x,y + stored ^GFA.');

        Assert.IsTrue(Engine.IsSafeGraphic(GfaTxt), 'Plain ^GFA is accepted.');
        Assert.IsFalse(Engine.IsSafeGraphic('^GFA,8,8,1,FF^XZ^XA^FDX^FS'), 'A second command is rejected.');
        Assert.IsFalse(Engine.IsSafeGraphic('^FO0,0^GB10,10,10^FS'), 'Only ^GFA is accepted.');
        asserterror DesignerMgt.SaveFromJson('DSG', StrSubstNo(OneElementJsonTxt, '"type":"image","xMm":2,"yMm":2,"wMm":10,"hMm":10,"imageGf":"^GFA,8,8,1,FF~JA"'));
        Assert.ExpectedError('^GFA');
    end;

    [Test]
    procedure LpKindFieldKeysAndValues()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
        Assert: Codeunit "Library Assert";
        Values: Dictionary of [Text, Text];
    begin
        Assert.AreEqual('LPNo,SSCC,BarcodeData,ItemNo,Description,LotNo,ExpirationDate,Quantity,TotalQuantity,UoM,LocationCode,BinCode,ItemCount,LineCount,ExtraLines,Company,Today',
            LayoutFields.KeyList(Enum::"DOPSWHS Label Kind"::LP), 'LP keys follow the designer contract.');

        CreateLp(LP);
        LayoutFields.LpValues(LP, Values);
        Assert.AreEqual(LpNoTxt, Values.Get('LPNo'), 'LP no.');
        Assert.AreEqual('386900000000099999', Values.Get('SSCC'), 'SSCC');
        Assert.AreEqual('LPDES-ITEM-A', Values.Get('ItemNo'), 'First line item.');
        Assert.AreEqual('TASARIM ÜRÜN A', Values.Get('Description'), 'Item description.');
        Assert.AreEqual('L1', Values.Get('LotNo'), 'First line lot.');
        Assert.AreEqual('31.12.2027', Values.Get('ExpirationDate'), 'Expiration date dd.mm.yyyy.');
        Assert.AreEqual(Format(5), Values.Get('Quantity'), 'First line quantity.');
        Assert.AreEqual('ADET', Values.Get('UoM'), 'First line unit.');
        Assert.AreEqual('ANA', Values.Get('LocationCode'), 'Location');
        Assert.AreEqual('K-01', Values.Get('BinCode'), 'Bin');
        Assert.AreEqual('2', Values.Get('ItemCount'), 'Distinct items, not lines.');
        Assert.IsTrue(Values.ContainsKey('Company') and Values.ContainsKey('Today'), 'Common keys.');
        // Kitoko (21 Eki 2026): same data as the built-in LP label.
        Assert.AreEqual('386900000000099999', Values.Get('BarcodeData'), 'Barcode carries the SSCC when the LP has one.');
        Assert.AreEqual(Format(10), Values.Get('TotalQuantity'), 'Total of all item lines (one unit).');
        Assert.AreEqual('3', Values.Get('LineCount'), 'Item lines.');
        Assert.AreEqual('+2 DİĞER SATIR', Values.Get('ExtraLines'), 'Extra lines as on the built-in label.');

        LP.SSCC := '';
        LP.Modify();
        LayoutFields.LpValues(LP, Values);
        Assert.AreEqual(LpNoTxt, Values.Get('BarcodeData'), 'Without SSCC the barcode carries the LP no.');

        LPLine.Get(LpNoTxt, 20000);
        LPLine."Unit of Measure" := 'KOLİ';
        LPLine.Modify();
        LayoutFields.LpValues(LP, Values);
        Assert.AreEqual('', Values.Get('TotalQuantity'), 'Mixed units are not added up.');
    end;

    [Test]
    procedure MissingElementsIsRejectedAndDeletesNothing()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        LayoutLine.SetRange("Layout Code", 'DSG');

        asserterror DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"Item"}');
        Assert.ExpectedError('"elements"');
        Assert.AreEqual(4, LayoutLine.Count(), 'A missing elements array deletes nothing.');

        asserterror DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"Item","elements":{"id":"x"}}');
        Assert.ExpectedError('"elements"');
        Assert.AreEqual(4, LayoutLine.Count(), 'A non-array elements value deletes nothing.');

        DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"Item","elements":[]}');
        Assert.AreEqual(0, LayoutLine.Count(), 'An explicit empty array is an empty design.');
    end;

    [Test]
    procedure StaleDesignerDoesNotOverrideActive()
    var
        Layout: Record "DOPSWHS Label Layout";
        Other: Record "DOPSWHS Label Layout";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Root: JsonObject;
        StaleJson: Text;
        Json: Text;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        CreateLayout('DSG2', Enum::"DOPSWHS Label Kind"::Item);
        Layout.Get('DSG');
        Layout.Validate(Active, true);
        Layout.Modify();
        StaleJson := DesignerMgt.DesignToJson('DSG');

        // Meanwhile another item layout is activated elsewhere (DSG becomes inactive).
        Other.Get('DSG2');
        Other.Validate(Active, true);
        Other.Modify();

        DesignerMgt.SaveFromJson('DSG', StaleJson);
        Layout.Get('DSG');
        Other.Get('DSG2');
        Assert.IsFalse(Layout.Active, 'An active flag the user did not change is not written back.');
        Assert.IsTrue(Other.Active, 'The activation made meanwhile stays.');

        // The user switches it on in the designer: active <> activeAtLoad.
        Root.ReadFrom(DesignerMgt.DesignToJson('DSG'));
        Root.Replace('active', true);
        Root.WriteTo(Json);
        DesignerMgt.SaveFromJson('DSG', Json);
        Layout.Get('DSG');
        Other.Get('DSG2');
        Assert.IsTrue(Layout.Active, 'A switch made in the designer is saved.');
        Assert.IsFalse(Other.Active, 'One active layout per kind.');

        DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"Item","active":false,"elements":[]}');
        Layout.Get('DSG');
        Assert.IsTrue(Layout.Active, 'Without activeAtLoad the active flag is left alone.');
    end;

    [Test]
    procedure EmptyKindIsRejected()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::LP);
        DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"LP","elements":[{"id":"t1","type":"text","text":"A"}]}');

        asserterror DesignerMgt.SaveFromJson('DSG', '{"version":1,"code":"DSG","kind":"","elements":[]}');
        Assert.ExpectedError('etiket türü');
        Layout.Get('DSG');
        Assert.AreEqual(Layout."Label Kind"::LP, Layout."Label Kind", 'An empty kind does not turn the layout into an item layout.');
        LayoutLine.SetRange("Layout Code", 'DSG');
        Assert.AreEqual(1, LayoutLine.Count(), 'Nothing is deleted.');
    end;

    [Test]
    procedure SetupSizeZeroIsKeptAndUnchangedImageIsNotRewritten()
    var
        Layout: Record "DOPSWHS Label Layout";
        LabelImage: Record "DOPSWHS Label Image";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Root: JsonObject;
        Json: Text;
        Stamp: DateTime;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        Layout.Get('DSG');
        Layout."Width (mm)" := 0;
        Layout."Height (mm)" := 0;
        Layout.Modify();

        Json := DesignerMgt.DesignToJson('DSG');
        DesignerMgt.SaveFromJson('DSG', Json);
        Layout.Get('DSG');
        Assert.AreEqual(0, Layout."Width (mm)", 'Width 0 (Setup size) survives a save of the resolved size.');
        Assert.AreEqual(0, Layout."Height (mm)", 'Height 0 (Setup size) survives a save of the resolved size.');

        Root.ReadFrom(Json);
        Root.Replace('widthMm', 100);
        Root.WriteTo(Json);
        DesignerMgt.SaveFromJson('DSG', Json);
        Layout.Get('DSG');
        Assert.AreEqual(100, Layout."Width (mm)", 'A size changed in the designer is stored.');
        Assert.AreEqual(0, Layout."Height (mm)", 'The unchanged height stays 0.');

        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        Stamp := CreateDateTime(DMY2Date(1, 1, 2020), 0T);
        LabelImage.Get('LOGO1');
        LabelImage."Last Modified" := Stamp;
        LabelImage.Modify(false);
        DesignerMgt.SaveFromJson('DSG', SampleDesignJson());
        LabelImage.Get('LOGO1');
        Assert.AreEqual(Stamp, LabelImage."Last Modified", 'The same picture is not written again.');

        Json := SampleDesignJson();
        DesignerMgt.SaveFromJson('DSG', Json.Replace('iVBORw0KGgo=', 'iVBORw0KGgoAAAA'));
        LabelImage.Get('LOGO1');
        Assert.AreNotEqual(Stamp, LabelImage."Last Modified", 'A changed picture is written.');
        Assert.AreEqual('data:image/png;base64,iVBORw0KGgoAAAA', LabelImage.GetDataUrl(), 'New picture stored.');
    end;

    [Test]
    procedure ActiveLpLayoutIsUsedAndInactiveFallsBack()
    var
        LP: Record "DOPSWHS LP Header";
        Layout: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
        BuiltIn: Text;
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Assert.IsTrue(Layout.Get('LP'), 'Default LP layout seeded.');
        Assert.IsFalse(Layout.Active, 'Seeded LP layout stays inactive.');
        Assert.AreEqual(Layout."Label Kind"::LP, Layout."Label Kind", 'LP kind.');
        CreateLp(LP);

        BuiltIn := LabelReport.BuildZpl(LP);
        Assert.IsTrue(StrPos(BuiltIn, '^XA^CI28^PW812^LL406^FO0,0^GB812,52,52^FS') = 1, 'Inactive layout: the built-in LP label is unchanged.');
        Assert.IsTrue(StrPos(BuiltIn, '^FH_^FD386900000000099999^FS') > 0, 'Built-in label: barcode carries the SSCC.');

        Layout.Validate(Active, true);
        Layout.Modify();
        Zpl := LabelReport.BuildZpl(LP);
        Assert.IsTrue(StrPos(Zpl, '^XA^CI28^PW813^LL406^LH0,0') = 1, 'Active layout: 101.6 x 50.8 mm from the engine.');
        Assert.IsTrue(StrPos(Zpl, '^FDPALET / LP ETİKETİ^FS') > 0, 'Title from the layout.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,' + LpNoTxt + '^FS') > 0, 'QR carries the LP no.');
        Assert.IsTrue(StrPos(Zpl, '^FDLOT: L1^FS') > 0, 'Lot with prefix.');
        Assert.IsTrue(StrPos(Zpl, '^FDÜRÜN ÇEŞİDİ: 2^FS') > 0, 'Distinct item count.');
        // Kitoko (21 Eki 2026): same data as the built-in label.
        Assert.IsTrue(StrPos(Zpl, ',N,N,N,A^FH_^FD386900000000099999^FS') > 0, 'Active layout: barcode carries the SSCC, like the built-in label.');
        Assert.AreEqual(0, StrPos(Zpl, 'A^FH_^FD' + LpNoTxt + '^FS'), 'The LP no. is not the barcode while an SSCC exists.');
        Assert.IsTrue(StrPos(Zpl, '^FDMİKTAR: 10^FS') > 0, 'Total quantity of the lines.');
        Assert.IsTrue(StrPos(Zpl, '^FD+2 DİĞER SATIR^FS') > 0, 'Extra lines as on the built-in label.');

        LP.SSCC := '';
        LP.Modify();
        Zpl := LabelReport.BuildZpl(LP);
        Assert.IsTrue(StrPos(Zpl, ',N,N,N,A^FH_^FD' + LpNoTxt + '^FS') > 0, 'Without SSCC the barcode carries the LP no.');
        LP.SSCC := '386900000000099999';
        LP.Modify();

        Layout.Validate(Active, false);
        Layout.Modify();
        Assert.AreEqual(BuiltIn, LabelReport.BuildZpl(LP), 'Deactivated: back to the built-in LP label.');
    end;

    [Test]
    procedure EnsureLpLayoutAddsOnlyMissingLpLayout()
    var
        Layout: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Engine.EnsureLpLayout();
        Assert.IsTrue(Layout.Get('LP'), 'LP layout created for installs seeded before the LP kind.');
        Assert.AreEqual(101.6, Layout."Width (mm)", '4x2 inch width.');
        Assert.AreEqual(50.8, Layout."Height (mm)", '4x2 inch height.');
        Engine.EnsureLpLayout();
        Layout.SetRange("Label Kind", Layout."Label Kind"::LP);
        Assert.AreEqual(1, Layout.Count(), 'Calling it again creates nothing.');
    end;

    [Test]
    procedure UntouchedFirstLpDefaultsAreUpgradedEditedAreKept()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Engine.EnsureLpLayout();
        LayoutLine.SetRange("Layout Code", 'LP');
        Assert.AreEqual(17, LayoutLine.Count(), 'Current default LP lines.');

        MakeFirstLpDefaults();
        Assert.AreEqual(16, LayoutLine.Count(), 'First (1.14.3.13) default LP lines.');
        Engine.EnsureLpLayout();
        Assert.AreEqual(17, LayoutLine.Count(), 'Untouched first defaults become the current defaults.');
        LayoutLine.SetRange("Source Field", 'BarcodeData');
        Assert.IsFalse(LayoutLine.IsEmpty(), 'Barcode = BarcodeData.');
        LayoutLine.SetRange("Source Field", 'TotalQuantity');
        Assert.IsFalse(LayoutLine.IsEmpty(), 'Quantity = TotalQuantity.');
        LayoutLine.SetRange("Source Field", 'ExtraLines');
        Assert.IsFalse(LayoutLine.IsEmpty(), '"+N DİĞER SATIR" element added.');
        LayoutLine.SetRange("Source Field");

        MakeFirstLpDefaults();
        LayoutLine.Get('LP', 20000);
        LayoutLine."Static Text" := 'PALET';
        LayoutLine.Modify();
        Engine.EnsureLpLayout();
        LayoutLine.SetRange("Layout Code", 'LP');
        Assert.AreEqual(16, LayoutLine.Count(), 'An edited layout is not replaced.');
        LayoutLine.Get('LP', 130000);
        Assert.AreEqual('LPNo', LayoutLine."Source Field", 'User layout kept as it is.');
        Assert.IsTrue(Layout.Get('LP'), 'Layout kept.');
    end;

    [Test]
    procedure ItemV2EnlargementDoesNotUndoLaterSizes()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        LayoutLine.Get('ETIKETV2', 10000);
        LayoutLine."Width (mm)" := 15;
        LayoutLine."Height (mm)" := 15;
        LayoutLine."X (mm)" := 50;
        LayoutLine.Modify();
        Engine.EnsureItemV2Layout();
        LayoutLine.Get('ETIKETV2', 10000);
        Assert.AreEqual(15, LayoutLine."Width (mm)", 'A size chosen after the one-time enlargement is kept.');
        Assert.AreEqual(50, LayoutLine."X (mm)", 'Position kept.');
    end;

    [Test]
    procedure Gs1128GeneratesFnc1AndKeepsUserDataEscaped()
    var
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('DSG', Enum::"DOPSWHS Label Kind"::Item);
        Zpl := DesignerMgt.SampleZpl('DSG', Gs1Json('(10)LOT1(17)271231'));
        Assert.IsTrue(StrPos(Zpl, ',N,N,D^FH_^FD(10)LOT1>8(17)271231^FS') > 0, 'FNC1 (raw >8) after a variable-length AI.');
        Zpl := DesignerMgt.SampleZpl('DSG', Gs1Json('(01)08690000012345(17)271231(10)LOT1'));
        Assert.IsTrue(StrPos(Zpl, ',N,N,D^FH_^FD(01)08690000012345(17)271231(10)LOT1^FS') > 0, 'No FNC1 after predefined-length AIs.');
        Zpl := DesignerMgt.SampleZpl('DSG', Gs1Json('(10)LOT1>8(17)271231'));
        Assert.IsTrue(StrPos(Zpl, '^FD(10)LOT1>8(17)271231^FS') > 0, 'A typed >8 is regenerated once.');
        Zpl := DesignerMgt.SampleZpl('DSG', Gs1Json('(10)L_1^X(21)S1(17)271231'));
        Assert.IsTrue(StrPos(Zpl, '^FD(10)L_5F1_5EX>8(21)S1>8(17)271231^FS') > 0, 'User data stays ^FH-escaped.');
        Zpl := DesignerMgt.SampleZpl('DSG', Gs1Json('(10)A>B'));
        Assert.AreEqual(0, StrPos(Zpl, ',N,N,D^'), 'A ">" in the data is not sent in GS1 mode.');
        Assert.IsTrue(StrPos(Zpl, ',N,N,A^FH_^FD(10)A_3EB^FS') > 0, 'It prints as plain Code128.');
    end;

    local procedure Gs1Json(Data: Text): Text
    begin
        exit(StrSubstNo(OneElementJsonTxt, '"type":"barcode","xMm":2,"yMm":2,"wMm":76,"hMm":10,"symbology":"gs1-128","showText":true,"text":"' + Data + '"'));
    end;

    /// <summary>Turns the current default LP lines back into the first (1.14.3.13) defaults.</summary>
    local procedure MakeFirstLpDefaults()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        LineNo: Integer;
    begin
        Engine.ResetToDefault('LP');
        LayoutLine.Get('LP', 100000);
        LayoutLine.TestField("Source Field", 'ExtraLines');
        LayoutLine.Delete();
        for LineNo := 11 to 17 do begin
            LayoutLine.Get('LP', LineNo * 10000);
            LayoutLine.Rename('LP', (LineNo - 1) * 10000);
        end;
        LayoutLine.Get('LP', 90000);
        LayoutLine."Width (mm)" := 40;
        LayoutLine.Modify();
        LayoutLine.Get('LP', 100000);
        LayoutLine.TestField("Source Field", 'ExpirationDate');
        LayoutLine."X (mm)" := 44;
        LayoutLine."Width (mm)" := 29;
        LayoutLine."Fit to Width" := false;
        LayoutLine."Min Font Height (mm)" := 0;
        LayoutLine.Modify();
        LayoutLine.Get('LP', 110000);
        LayoutLine."Source Field" := 'Quantity';
        LayoutLine.Modify();
        LayoutLine.Get('LP', 130000);
        LayoutLine.TestField("Source Field", 'BarcodeData');
        LayoutLine."Source Field" := 'LPNo';
        LayoutLine.Modify();
    end;

    local procedure SampleDesignJson(): Text
    begin
        exit(
            '{"version":1,"code":"DSG","description":"Tasarımcı testi","kind":"Item","widthMm":80,"heightMm":40,"dpi":203,"active":false,' +
            '"elements":[' +
            '{"id":"t1","lineNo":0,"type":"text","xMm":2,"yMm":2,"wMm":50,"hMm":6,"rotation":90,"fontMm":4,"bold":true,"align":"left","text":"DÖNEN","enabled":true},' +
            '{"id":"b1","lineNo":0,"type":"barcode","xMm":2,"yMm":20,"wMm":50,"hMm":10,"rotation":0,"symbology":"ean13","field":"Gtin","showText":true,"enabled":true},' +
            '{"id":"i1","lineNo":0,"type":"image","xMm":60,"yMm":2,"wMm":10,"hMm":10,"imageId":"logo1","imageGf":"' + GfaTxt + '","enabled":true},' +
            '{"id":"x1","lineNo":0,"type":"box","xMm":60,"yMm":15,"wMm":20,"hMm":5,"rotation":90,"thicknessMm":0,"enabled":true}' +
            '],' +
            '"fields":[],' +
            '"images":[{"id":"LOGO1","name":"Logo","dataUrl":"data:image/png;base64,iVBORw0KGgo="}]}');
    end;

    local procedure CreateLayout(LayoutCode: Code[20]; Kind: Enum "DOPSWHS Label Kind")
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.Init();
        Layout."Code" := LayoutCode;
        Layout."Label Kind" := Kind;
        Layout."Width (mm)" := 80;
        Layout."Height (mm)" := 40;
        Layout.Dpi := 203;
        Layout.Insert();
    end;

    local procedure CreateLp(var LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        SeedItem('LPDES-ITEM-A', 'TASARIM ÜRÜN A');
        SeedItem('LPDES-ITEM-B', 'TASARIM ÜRÜN B');
        LPLine.SetRange("LP No.", LpNoTxt);
        LPLine.DeleteAll();
        if LP.Get(LpNoTxt) then
            LP.Delete();
        LP.Init();
        LP."No." := LpNoTxt;
        LP.SSCC := '386900000000099999';
        LP."Location Code" := 'ANA';
        LP."Bin Code" := 'K-01';
        LP.Insert();
        AddLpLine(10000, 'LPDES-ITEM-A', 5, 'L1', DMY2Date(31, 12, 2027));
        AddLpLine(20000, 'LPDES-ITEM-B', 3, 'L2', 0D);
        AddLpLine(30000, 'LPDES-ITEM-A', 2, 'L3', 0D);
    end;

    local procedure AddLpLine(LineNo: Integer; ItemNo: Code[20]; Qty: Decimal; LotNo: Code[50]; ExpirationDate: Date)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.Init();
        LPLine."LP No." := LpNoTxt;
        LPLine."Line No." := LineNo;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := 'ADET';
        LPLine.Quantity := Qty;
        LPLine."Lot No." := LotNo;
        LPLine."Expiration Date" := ExpirationDate;
        LPLine.Insert();
    end;

    local procedure SeedItem(ItemNo: Code[20]; Description: Text[100])
    var
        Item: Record Item;
    begin
        if Item.Get(ItemNo) then
            exit;
        Item.Init();
        Item."No." := ItemNo;
        Item.Description := Description;
        Item."Base Unit of Measure" := 'ADET';
        Item.Insert();
    end;

    [Test]
    procedure NewLayoutGetsNextFreeCodeAndStaysInactive()
    var
        Layout: Record "DOPSWHS Label Layout";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Assert.AreEqual('URUN-01', DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::Item), 'First item design code.');
        Assert.AreEqual('URUN-02', DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::Item), 'Next free item design code.');
        Assert.AreEqual('RAF-01', DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::Bin), 'Bin design code.');
        Assert.AreEqual('LP-01', DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::LP), 'LP design code.');

        Layout.Get('URUN-01');
        Assert.IsFalse(Layout.Active, 'A new design never replaces the printed label by itself.');
        Assert.AreEqual(0, Layout."Width (mm)", 'Item design starts with the Setup label size.');
        Layout.Get('LP-01');
        Assert.AreEqual(Enum::"DOPSWHS Label Kind"::LP, Layout."Label Kind", 'Kind is kept.');
        Assert.AreEqual(101.6, Layout."Width (mm)", 'LP design starts at 4 inch width.');
    end;

    [Test]
    procedure CopyLayoutCopiesLinesAsInactive()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        NewCode: Code[20];
        SourceLines: Integer;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Layout.Get('ITEM');
        Layout.Validate(Active, true);
        Layout.Modify(true);
        LayoutLine.SetRange("Layout Code", 'ITEM');
        SourceLines := LayoutLine.Count();

        NewCode := DesignerMgt.CopyLayout('ITEM');

        Assert.AreEqual('URUN-01', NewCode, 'Copy gets the next free code of its kind.');
        LayoutLine.SetRange("Layout Code", NewCode);
        Assert.AreEqual(SourceLines, LayoutLine.Count(), 'Every line is copied.');
        Layout.Get(NewCode);
        Assert.IsFalse(Layout.Active, 'The copy is inactive.');
        Layout.Get('ITEM');
        Assert.IsTrue(Layout.Active, 'The source stays active.');
        Assert.AreEqual(Engine.BuildSampleZpl('ITEM'), Engine.BuildSampleZpl(NewCode), 'The copy prints the same label.');
    end;

    [Test]
    procedure DeleteIfEmptyKeepsSavedDesigns()
    var
        Layout: Record "DOPSWHS Label Layout";
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        Assert: Codeunit "Library Assert";
        EmptyCode: Code[20];
        SavedCode: Code[20];
        Json: Text;
    begin
        ClearLayouts();
        EmptyCode := DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::Item);
        SavedCode := DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind"::Item);
        Json := StrSubstNo(OneElementJsonTxt, '"type":"text","xMm":2,"yMm":2,"wMm":30,"hMm":5,"fontMm":3,"text":"A"');
        Json := Json.Replace('"code":"DSG"', '"code":"' + SavedCode + '"');
        DesignerMgt.SaveFromJson(SavedCode, Json);

        DesignerMgt.DeleteIfEmpty(EmptyCode);
        DesignerMgt.DeleteIfEmpty(SavedCode);

        Assert.IsFalse(Layout.Get(EmptyCode), 'An unsaved new design is removed on close.');
        Assert.IsTrue(Layout.Get(SavedCode), 'A saved design is kept.');
    end;

    local procedure ClearLayouts()
    var
        Layout: Record "DOPSWHS Label Layout";
        LabelImage: Record "DOPSWHS Label Image";
    begin
        Layout.DeleteAll(true);
        LabelImage.DeleteAll();
    end;

    local procedure JsonText(Element: JsonToken; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        Element.AsObject().Get(KeyName, Token);
        exit(Token.AsValue().AsText());
    end;

    local procedure JsonInt(Element: JsonToken; KeyName: Text): Integer
    var
        Token: JsonToken;
    begin
        Element.AsObject().Get(KeyName, Token);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure JsonBool(Element: JsonToken; KeyName: Text): Boolean
    var
        Token: JsonToken;
    begin
        Element.AsObject().Get(KeyName, Token);
        exit(Token.AsValue().AsBoolean());
    end;

    var
        GfaTxt: Label '^GFA,8,8,1,FF00FF00FF00FF00', Locked = true;
        LpNoTxt: Label 'LPDES-001', Locked = true;
        OneElementJsonTxt: Label '{"version":1,"code":"DSG","kind":"Item","widthMm":80,"heightMm":40,"dpi":203,"elements":[{"id":"z1",%1}]}', Locked = true;
}
