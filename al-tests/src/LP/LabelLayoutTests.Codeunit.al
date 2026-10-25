/// <summary>
/// Kitoko (20 Eki 2026): veriyle yönetilen etiket tasarımı (Label Layout):
/// motor, mm-nokta çevirisi, tohum tasarımlar, aktif/pasif ve fallback.
/// </summary>
codeunit 72160 "DOPSWHS Label Layout Tests"
{
    Subtype = Test;

    [Test]
    procedure MmConvertsToDotsByDpi()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
    begin
        Assert.AreEqual(160, Engine.MmToDots(20, 203), '20 mm at 203 dpi is 160 dots.');
        Assert.AreEqual(160, Engine.MmToDots(20, 0), 'Dpi 0 means 203.');
        Assert.AreEqual(240, Engine.MmToDots(20, 300), '20 mm at 300 dpi is 12 dots/mm.');
        Assert.AreEqual(0, Engine.MmToDots(0, 203), 'Zero stays zero.');
    end;

    [Test]
    procedure SeedCreatesItemBinZone()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Assert.IsTrue(Layout.Get('ITEM'), 'ITEM seeded');
        Assert.IsTrue(Layout.Get('BIN'), 'BIN seeded');
        Assert.IsTrue(Layout.Get('ZONE'), 'ZONE seeded');
        Assert.IsFalse(Layout.Active, 'Seeded layouts stay inactive.');
        Assert.AreEqual(Layout."Label Kind"::Zone, Layout."Label Kind", 'ZONE is a zone layout.');
        LayoutLine.SetRange("Layout Code", 'ITEM');
        Assert.IsTrue(LayoutLine.Count() >= 8, 'ITEM has its default elements.');
        // Kitoko (21 Eki 2026): ITEM, BIN, ZONE, LP + ETIKETV2.
        Assert.IsTrue(Layout.Get('LP'), 'LP seeded');
        Assert.IsTrue(Layout.Get('ETIKETV2'), 'ETIKETV2 seeded');
        Engine.SeedDefaults();
        Assert.AreEqual(5, Layout.Count(), 'Seeding twice creates nothing new.');
    end;

    [Test]
    procedure EngineWritesSampleValuesAsFieldData()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Zpl := Engine.BuildSampleZpl('ITEM');
        Assert.IsTrue(StrPos(Zpl, '^XA^CI28^PW640^LL320') = 1, 'Header carries UTF-8 and the 80x40 mm size.');
        Assert.IsTrue(StrPos(Zpl, '^FDSK-10025^FS') > 0, 'Item no text.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,SK-10025^FS') > 0, 'QR carries the item no.');
        Assert.IsTrue(StrPos(Zpl, '^BCN,') > 0, 'Code128 present.');
        Assert.IsTrue(StrPos(Zpl, '^FDBİRİM: ADET^FS') > 0, 'Prefix is applied.');
        Assert.IsTrue(StrPos(Zpl, '^FDGTIN: 8690000012345^FS') > 0, 'GTIN with prefix.');
        Assert.IsTrue(StrPos(Zpl, '^FR') > 0, 'Inverted title.');
        Assert.IsTrue(StrPos(Zpl, '^GB640,44,44^FS') > 0, 'Filled 5.5 mm band.');
        Assert.IsTrue(CopyStr(Zpl, StrLen(Zpl) - 2) = '^XZ', 'Ends with ^XZ.');
    end;

    [Test]
    procedure EmptyValuesAndDisabledLinesPrintNothing()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
        Values: Dictionary of [Text, Text];
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Values.Add('ItemNo', 'A1');
        Values.Add('UoM', '');
        Zpl := Engine.BuildZpl('ITEM', Values, 3);
        Assert.AreEqual(0, StrPos(Zpl, 'BİRİM'), 'Empty value drops its prefix too.');
        Assert.IsTrue(StrPos(Zpl, '^PQ3^XZ') > 0, 'Copies become ^PQ.');
        LayoutLine.SetRange("Layout Code", 'ITEM');
        LayoutLine.SetRange("Element Type", LayoutLine."Element Type"::QRCode);
        LayoutLine.FindFirst();
        LayoutLine.Enabled := false;
        LayoutLine.Modify();
        Zpl := Engine.BuildZpl('ITEM', Values, 1);
        Assert.AreEqual(0, StrPos(Zpl, '^BQN'), 'Disabled QR is not printed.');
        Layout.Get('ITEM');
    end;

    [Test]
    procedure ActiveLayoutIsUsedByBuildItemZpl()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Item: Record Item;
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        SeedItem('LAY-ITEM-1', 'ETIKET TASARIM ÜRÜNÜ');
        Item.Get('LAY-ITEM-1');

        // Inactive: built-in design (header has no ^LH before ^PW order difference: Canvas prints ^PW then ^LL too, so use the band text).
        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^FDÜRÜN ETİKETİ^FS') > 0, 'Built-in design while no layout is active.');

        Layout.Get('ITEM');
        LayoutLine.SetRange("Layout Code", 'ITEM');
        LayoutLine.SetRange("Static Text", 'ÜRÜN ETİKETİ');
        LayoutLine.FindFirst();
        LayoutLine."Static Text" := 'TASARIM TEST';
        LayoutLine.Modify();
        Layout.Validate(Active, true);
        Layout.Modify();

        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^FDTASARIM TEST^FS') > 0, 'Active layout text is printed.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,LAY-ITEM-1^FS') > 0, 'Real item no reaches the QR.');
        Assert.AreEqual(0, StrPos(Zpl, 'ÜRÜN ETİKETİ'), 'Built-in design is not used.');

        Layout.Validate(Active, false);
        Layout.Modify();
        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^FDÜRÜN ETİKETİ^FS') > 0, 'Inactive layout falls back to the built-in design.');
    end;

    [Test]
    procedure OnlyOneLayoutPerKindStaysActive()
    var
        First: Record "DOPSWHS Label Layout";
        Second: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
        LayoutCode: Code[20];
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Assert.IsFalse(Engine.FindActiveLayout(Enum::"DOPSWHS Label Kind"::Bin, LayoutCode), 'Nothing active yet.');
        First.Get('BIN');
        First.Validate(Active, true);
        First.Modify();
        Second.Init();
        Second."Code" := 'BIN2';
        Second."Label Kind" := Second."Label Kind"::Bin;
        Second.Insert();
        Second.Validate(Active, true);
        Second.Modify();
        First.Get('BIN');
        Assert.IsFalse(First.Active, 'Activating another bin layout deactivates the first.');
        Assert.IsTrue(Engine.FindActiveLayout(Enum::"DOPSWHS Label Kind"::Bin, LayoutCode), 'Active bin layout found.');
        Assert.AreEqual('BIN2', LayoutCode, 'The newly activated one.');
    end;

    [Test]
    procedure PreviewUrlUsesInchesAndResolution()
    var
        Preview: Codeunit "DOPSWHS Label Layout Preview";
        Assert: Codeunit "Library Assert";
    begin
        Assert.AreEqual('https://api.labelary.com/v1/printers/8dpmm/labels/3.1552x1.5788/0/', Preview.PreviewUrl(80, 40, 203), '80x40 mm at 203 dpi = exactly 640 x 320 dots on Labelary');
        Assert.IsTrue(StrPos(Preview.PreviewUrl(80, 40, 300), '12dpmm') > 0, '300 dpi is 12 dpmm.');
    end;

    local procedure ClearLayouts()
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.DeleteAll(true);
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
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert();
    end;
}
