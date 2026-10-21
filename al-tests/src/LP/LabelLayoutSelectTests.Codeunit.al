/// <summary>
/// Kitoko (21 Eki 2026): terminalde seçilen etiket tasarımı (labelLayouts +
/// printLabelWithLayout). Dolu kod o tasarımla basar, tür uyuşmazsa hata verir;
/// boş kod bugünkü davranışı (aktif tasarım ya da sabit tasarım) aynen korur.
/// </summary>
codeunit 72162 "DOPSWHS Label Layout Sel Tests"
{
    Subtype = Test;

    var
        ItemNoTxt: Label 'SEL-ITEM-1', Locked = true;
        LpNoTxt: Label 'LPSEL-0001', Locked = true;

    [Test]
    procedure ExplicitItemLayoutIsUsedOverActiveLayout()
    var
        Item: Record Item;
        Layout: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        LayoutCode: Code[20];
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        CreateTextLayout('SECILEN', Enum::"DOPSWHS Label Kind"::Item, 'SECILEN TASARIM', 'ItemNo');
        Layout.Get('ITEM');
        Layout.Validate(Active, true);
        Layout.Modify();
        SeedItem(Item);

        Zpl := Dispatcher.BuildItemZplWithLayout(Item, 'SECILEN');
        Assert.IsTrue(StrPos(Zpl, '^FDSECILEN TASARIM^FS') > 0, 'The chosen layout is printed.');
        Assert.IsTrue(StrPos(Zpl, '^FD' + ItemNoTxt + '^FS') > 0, 'Real item values reach the chosen layout.');
        Assert.AreEqual(0, StrPos(Zpl, '^FDLA,' + ItemNoTxt + '^FS'), 'The active ITEM layout (with its QR) is not used.');

        Assert.IsTrue(Engine.ResolveLayout(Enum::"DOPSWHS Label Kind"::Item, 'SECILEN', LayoutCode), 'An explicit code resolves.');
        Assert.AreEqual('SECILEN', LayoutCode, 'Explicit code wins over the active layout.');
        Assert.IsTrue(Engine.ResolveLayout(Enum::"DOPSWHS Label Kind"::Item, '', LayoutCode), 'Blank resolves to the active layout.');
        Assert.AreEqual('ITEM', LayoutCode, 'Blank = active layout.');
    end;

    [Test]
    procedure ExplicitBinZoneAndLpLayoutsAreUsed()
    var
        Bin: Record Bin;
        Zone: Record Zone;
        LP: Record "DOPSWHS LP Header";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        CreateTextLayout('RAFSEC', Enum::"DOPSWHS Label Kind"::Bin, 'RAF SECIM', 'BinCode');
        CreateTextLayout('ALANSEC', Enum::"DOPSWHS Label Kind"::Zone, 'ALAN SECIM', 'ZoneCode');
        CreateTextLayout('LPSEC', Enum::"DOPSWHS Label Kind"::LP, 'LP SECIM', 'LPNo');
        SeedBin(Bin);
        SeedZone(Zone);
        SeedLp(LP);

        Assert.IsTrue(StrPos(Dispatcher.BuildBinZplWithLayout(Bin, 'RAFSEC'), '^FDRAF SECIM^FS') > 0, 'Chosen bin layout.');
        Assert.IsTrue(StrPos(Dispatcher.BuildBinZplWithLayout(Bin, 'RAFSEC'), '^FDSEL-R-01^FS') > 0, 'Bin code reaches the chosen layout.');
        Assert.IsTrue(StrPos(Dispatcher.BuildZoneZplWithLayout(Zone, 'ALANSEC'), '^FDALAN SECIM^FS') > 0, 'Chosen zone layout.');
        Assert.IsTrue(StrPos(LabelReport.BuildZplWithLayout(LP, 'LPSEC'), '^FDLP SECIM^FS') > 0, 'Chosen LP layout.');
        Assert.IsTrue(StrPos(LabelReport.BuildZplWithLayout(LP, 'LPSEC'), '^FD' + LpNoTxt + '^FS') > 0, 'LP no reaches the chosen layout.');
    end;

    [Test]
    procedure LayoutOfAnotherKindIsRefused()
    var
        Item: Record Item;
        Bin: Record Bin;
        Zone: Record Zone;
        LP: Record "DOPSWHS LP Header";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
        LayoutCode: Code[20];
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        SeedItem(Item);
        SeedBin(Bin);
        SeedZone(Zone);
        SeedLp(LP);

        asserterror Dispatcher.BuildBinZplWithLayout(Bin, 'ETIKETV2');
        Assert.ExpectedError('ETIKETV2 etiket tasarımının türü Ürün; Raf etiketi için kullanılamaz.');
        asserterror Dispatcher.BuildItemZplWithLayout(Item, 'BIN');
        Assert.ExpectedError('Ürün etiketi için kullanılamaz');
        asserterror Dispatcher.BuildZoneZplWithLayout(Zone, 'ITEM');
        Assert.ExpectedError('Alan etiketi için kullanılamaz');
        asserterror LabelReport.BuildZplWithLayout(LP, 'ITEM');
        Assert.ExpectedError('LP / Palet etiketi için kullanılamaz');
        asserterror Dispatcher.BuildItemZplWithLayout(Item, 'YOKTASARIM');
        Assert.ExpectedError('Etiket tasarımı YOKTASARIM bulunamadı.');
        asserterror Engine.ResolveLayout(Enum::"DOPSWHS Label Kind"::Bin, 'ITEM', LayoutCode);
        Assert.ExpectedError('Raf etiketi için kullanılamaz');
    end;

    [Test]
    procedure ChosenLayoutRefusesPdfPrinter()
    var
        Item: Record Item;
        Printer: Record "DOPSWHS Printer";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        SeedItem(Item);
        if Printer.Get('SELPDF') then
            Printer.Delete();
        Printer.Init();
        Printer."Code" := 'SELPDF';
        Printer."Format" := Printer."Format"::PDF;
        Printer.Insert();

        asserterror Dispatcher.PrintItemLabelWithLayout(Item, 'SELPDF', 1, 'ETIKETV2');
        Assert.ExpectedError('SELPDF bir PDF yazıcıdır');
        asserterror Dispatcher.PrintItemLabelWithLayout(Item, 'SELPDF', 1, 'BIN');
        Assert.ExpectedError('Ürün etiketi için kullanılamaz');
    end;

    [Test]
    procedure BlankLayoutKeepsCurrentBehaviour()
    var
        Item: Record Item;
        Bin: Record Bin;
        Zone: Record Zone;
        LP: Record "DOPSWHS LP Header";
        Layout: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
        LayoutCode: Code[20];
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        SeedItem(Item);
        SeedBin(Bin);
        SeedZone(Zone);
        SeedLp(LP);

        // Nothing active: the built-in designs, exactly as before.
        Assert.IsFalse(Engine.ResolveLayout(Enum::"DOPSWHS Label Kind"::Item, '', LayoutCode), 'Blank + nothing active = built-in design.');
        Zpl := Dispatcher.BuildItemZplWithLayout(Item, '');
        Assert.AreEqual(Dispatcher.BuildItemZpl(Item), Zpl, 'Blank item layout = BuildItemZpl.');
        Assert.IsTrue(StrPos(Zpl, '^FDÜRÜN ETİKETİ^FS') > 0, 'Built-in item design.');
        Assert.AreEqual(Dispatcher.BuildBinZpl(Bin), Dispatcher.BuildBinZplWithLayout(Bin, ''), 'Blank bin layout = BuildBinZpl.');
        Assert.AreEqual(Dispatcher.BuildZoneZpl(Zone), Dispatcher.BuildZoneZplWithLayout(Zone, ''), 'Blank zone layout = BuildZoneZpl.');
        Assert.AreEqual(LabelReport.BuildZpl(LP), LabelReport.BuildZplWithLayout(LP, ''), 'Blank LP layout = BuildZpl.');

        // An active layout: blank still follows BC's choice.
        Layout.Get('ETIKETV2');
        Layout.Validate(Active, true);
        Layout.Modify();
        Zpl := Dispatcher.BuildItemZplWithLayout(Item, '');
        Assert.AreEqual(Dispatcher.BuildItemZpl(Item), Zpl, 'Blank = the active layout, like BuildItemZpl.');
        Assert.AreEqual(0, StrPos(Zpl, 'ÜRÜN ETİKETİ'), 'Active layout replaces the built-in design.');
        Assert.AreEqual(Engine.BuildZpl('ETIKETV2', ItemValues(Item), 1), Zpl, 'Blank prints the active ETIKETV2.');
    end;

    local procedure ItemValues(var Item: Record Item) Values: Dictionary of [Text, Text]
    var
        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
    begin
        LayoutFields.ItemValues(Item, Values);
    end;

    local procedure CreateTextLayout(LayoutCode: Code[20]; Kind: Enum "DOPSWHS Label Kind"; StaticText: Text[100]; FieldKey: Text[30])
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        Layout.Init();
        Layout."Code" := LayoutCode;
        Layout.Description := StaticText;
        Layout."Label Kind" := Kind;
        Layout."Width (mm)" := 80;
        Layout."Height (mm)" := 40;
        Layout.Dpi := 203;
        Layout.Insert();
        LayoutLine.Init();
        LayoutLine."Layout Code" := LayoutCode;
        LayoutLine."Line No." := 10000;
        LayoutLine."Element Type" := LayoutLine."Element Type"::Text;
        LayoutLine."X (mm)" := 2;
        LayoutLine."Y (mm)" := 2;
        LayoutLine."Width (mm)" := 70;
        LayoutLine."Font Height (mm)" := 4;
        LayoutLine."Static Text" := StaticText;
        LayoutLine.Enabled := true;
        LayoutLine.Insert();
        LayoutLine.Init();
        LayoutLine."Layout Code" := LayoutCode;
        LayoutLine."Line No." := 20000;
        LayoutLine."Element Type" := LayoutLine."Element Type"::Field;
        LayoutLine."X (mm)" := 2;
        LayoutLine."Y (mm)" := 10;
        LayoutLine."Width (mm)" := 70;
        LayoutLine."Font Height (mm)" := 4;
        LayoutLine."Source Field" := FieldKey;
        LayoutLine.Enabled := true;
        LayoutLine.Insert();
    end;

    local procedure SeedItem(var Item: Record Item)
    begin
        if not Item.Get(ItemNoTxt) then begin
            Item.Init();
            Item."No." := ItemNoTxt;
            Item.Description := 'SECIM TEST URUNU';
            Item."Base Unit of Measure" := 'ADET';
            Item.Insert();
        end;
    end;

    local procedure SeedBin(var Bin: Record Bin)
    begin
        if not Bin.Get('SELLOC', 'SEL-R-01') then begin
            Bin.Init();
            Bin."Location Code" := 'SELLOC';
            Bin.Code := 'SEL-R-01';
            Bin."Zone Code" := 'SELZONE';
            Bin.Description := 'SECIM RAFI';
            Bin.Insert();
        end;
    end;

    local procedure SeedZone(var Zone: Record Zone)
    begin
        if not Zone.Get('SELLOC', 'SELZONE') then begin
            Zone.Init();
            Zone."Location Code" := 'SELLOC';
            Zone.Code := 'SELZONE';
            Zone.Description := 'SECIM ALANI';
            Zone.Insert();
        end;
    end;

    local procedure SeedLp(var LP: Record "DOPSWHS LP Header")
    begin
        if LP.Get(LpNoTxt) then
            exit;
        LP.Init();
        LP."No." := LpNoTxt;
        LP."Location Code" := 'SELLOC';
        LP."Bin Code" := 'SEL-R-01';
        LP.Insert();
    end;

    local procedure ClearLayouts()
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.DeleteAll(true);
    end;
}
