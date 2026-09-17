/// <summary>
/// EMU/DKÇ (16 Eyl 2026): labels follow the label size in Setup. Pure record
/// setup, no posting.
/// </summary>
codeunit 72499 "DOPSWHS Label Canvas Tests"
{
    Subtype = Test;

    [Test]
    procedure DefaultCanvasIs80x40Mm()
    var
        Setup: Record "DOPSWHS Setup";
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Assert: Codeunit "Library Assert";
    begin
        SetLabelSize(Setup, 0, 0);
        Canvas.Init();
        Assert.AreEqual(640, Canvas.LabelWidth(), '80 mm x 8 dots');
        Assert.AreEqual(320, Canvas.LabelHeight(), '40 mm x 8 dots');
        Assert.IsTrue(StrPos(Canvas.Start(), '^PW640^LL320') > 0, 'ZPL header carries the canvas size.');
        Assert.AreEqual(2, Canvas.MaxContentLines(), 'A 40 mm label lists two content lines.');
    end;

    [Test]
    procedure SetupSizeDrivesTheCanvas()
    var
        Setup: Record "DOPSWHS Setup";
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Assert: Codeunit "Library Assert";
    begin
        SetLabelSize(Setup, 100, 50);
        Canvas.Init();
        Assert.AreEqual(800, Canvas.LabelWidth(), '100 mm');
        Assert.AreEqual(400, Canvas.LabelHeight(), '50 mm');
        Assert.AreEqual(54, Canvas.BandHeight(), 'Band grows with the label but stays capped.');
        Assert.AreEqual(28, Canvas.NormalFont(), 'Normal font is capped at 28 dots.');
        Assert.AreEqual(3, Canvas.MaxContentLines(), 'A 50 mm label lists three content lines.');
        SetLabelSize(Setup, 0, 0);
    end;

    [Test]
    procedure UnusableSizesFallBackToTheDefault()
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Assert: Codeunit "Library Assert";
    begin
        Canvas.InitSize(5, 1000);
        Assert.AreEqual(640, Canvas.LabelWidth(), 'Width under 25 mm is ignored.');
        Assert.AreEqual(320, Canvas.LabelHeight(), 'Height over 400 mm is ignored.');
    end;

    [Test]
    procedure WrapBreaksAtWordsAndDropsTheRest()
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Assert: Codeunit "Library Assert";
        Lines: List of [Text];
    begin
        Canvas.WrapText('M193 FMJ KIVIRMA İÇ BASKI ZIMBASI BURCU', 35, 2, Lines);
        Assert.AreEqual(2, Lines.Count(), 'Two lines.');
        Assert.AreEqual('M193 FMJ KIVIRMA İÇ BASKI ZIMBASI', Lines.Get(1), 'First line ends at a word boundary.');
        Assert.AreEqual('BURCU', Lines.Get(2), 'Second line carries the remainder.');
        Canvas.WrapText('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJ', 10, 2, Lines);
        Assert.AreEqual(2, Lines.Count(), 'A word longer than the line is cut hard.');
        Assert.AreEqual('ABCDEFGHIJ', Lines.Get(1), 'Hard cut at MaxChars.');
        Canvas.WrapText('', 10, 2, Lines);
        Assert.AreEqual(0, Lines.Count(), 'Empty text gives no lines.');
    end;

    [Test]
    procedure QrMagnificationFitsTheAvailableSide()
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Assert: Codeunit "Library Assert";
    begin
        Assert.AreEqual(8, Canvas.QrMagnification('1', 218), 'Short data: 21 modules, magnification capped at 8.');
        Assert.AreEqual(4, Canvas.QrMagnification('003860012345678903', 100), '18 digits: 25 modules x 4 = 100.');
        Assert.AreEqual(2, Canvas.QrMagnification('LP000045', 10), 'Never below 2.');
    end;

    [Test]
    procedure EveryLpDesignStaysInsideTheCanvas()
    var
        Setup: Record "DOPSWHS Setup";
        LP: Record "DOPSWHS LP Header";
        Builder: Codeunit "DOPSWHS LP Label Builder";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
        TemplateCode: Code[20];
    begin
        SetLabelSize(Setup, 0, 0);
        SeedTemplate('CNV-PAL', Enum::"DOPSWHS LP Container Kind"::Pallet, true);
        SeedTemplate('CNV-KOLI', Enum::"DOPSWHS LP Container Kind"::Carton, true);
        SeedTemplate('CNV-KUTU', Enum::"DOPSWHS LP Container Kind"::Box, false);
        SeedTemplate('CNV-CUVAL', Enum::"DOPSWHS LP Container Kind"::Sack, false);
        SeedTemplate('CNV-STD', Enum::"DOPSWHS LP Container Kind"::Tote, false);
        SeedLp(LP, 'CNV-LP-1', 'CNV-PAL');
        SeedLine(LP, 10000, 'CNV-ITEM-1', 'LOT-A', 6000);
        SeedLine(LP, 20000, 'CNV-ITEM-2', 'LOT-B', 200);
        SeedLine(LP, 30000, 'CNV-ITEM-3', '', 12);
        LP.SSCC := '003860012345678903';
        LP."Weight kg" := 412;
        LP.Modify();
        foreach TemplateCode in 'CNV-PAL,CNV-KOLI,CNV-KUTU,CNV-CUVAL,CNV-STD'.Split(',') do begin
            LP."LP Template Code" := TemplateCode;
            LP.Modify();
            Zpl := Builder.BuildZpl(LP);
            Assert.IsTrue(StrPos(Zpl, '^PW640^LL320') > 0, TemplateCode + ': canvas header.');
            Assert.IsTrue(StrPos(Zpl, '^FDLA,CNV-LP-1^FS') > 0, TemplateCode + ': QR carries the LP number.');
            Assert.IsTrue(StrPos(Zpl, '003860012345678903') > 0, TemplateCode + ': Code128 carries the SSCC.');
            AssertInsideCanvas(Zpl, 640, 320, TemplateCode);
        end;
    end;

    [Test]
    procedure ItemAndBinLabelsFollowTheCanvas()
    var
        Setup: Record "DOPSWHS Setup";
        Item: Record Item;
        Bin: Record Bin;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        SetLabelSize(Setup, 100, 50);
        SeedItem('CNV-ITEM-L', 'PARFÜMLÜ NEMLENDİRİCİ EL VE VÜCUT LOSYONU 500 ML SHEA BUTTER FORMÜL');
        Item.Get('CNV-ITEM-L');
        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^PW800^LL400') > 0, 'Item label uses the Setup size.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,CNV-ITEM-L^FS') > 0, 'Item QR carries the item no.');
        Assert.IsTrue(StrPos(Zpl, 'PARFÜMLÜ NEMLENDİRİCİ') > 0, 'Description is printed.');
        AssertInsideCanvas(Zpl, 800, 400, 'item');

        SetLabelSize(Setup, 0, 0);
        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^PW640^LL320') > 0, 'Blank size = 80x40 mm.');
        AssertInsideCanvas(Zpl, 640, 320, 'item 80x40');

        if not Bin.Get('CNV-LOC', 'K.K03.11.UST') then begin
            Bin.Init();
            Bin."Location Code" := 'CNV-LOC';
            Bin.Code := 'K.K03.11.UST';
            Bin."Zone Code" := 'K';
            Bin.Insert();
        end;
        Zpl := Dispatcher.BuildBinZpl(Bin);
        Assert.IsTrue(StrPos(Zpl, '^FDLA,K.K03.11.UST^FS') > 0, 'Bin QR carries the bin code.');
        Assert.IsTrue(StrPos(Zpl, 'BÖLGE: K') > 0, 'Zone is printed.');
        AssertInsideCanvas(Zpl, 640, 320, 'bin');
    end;

    [Test]
    procedure MeasuredWidthsKeepLongItemNumbersInsideTheColumn()
    var
        Setup: Record "DOPSWHS Setup";
        Item: Record Item;
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
        LongNo: Code[20];
    begin
        // DKÇ 17 Eyl 2026: "ürün no çok büyük, uzunsa sığmıyor".
        Canvas.InitSize(80, 40);
        Assert.AreEqual(1268, Canvas.MeasuredWidth('MKW-WM2026-KRM-00154', 100), 'Measured units of a wide 20-char item no.');
        Assert.AreEqual(480, Canvas.MeasuredWidth('0123456789', 100), 'Digits are 48 units.');
        Assert.AreEqual(32, Canvas.ItemNoFont(), 'Item no preferred size on 80x40 mm.');
        Assert.AreEqual(32, Canvas.FitFontMeasured('1', 417, Canvas.ItemNoFont(), Canvas.SmallFont()), 'Short item no stays at the preferred size.');
        Assert.AreEqual(Canvas.SmallFont(), Canvas.FitFontMeasured('WWWWWWWWWWWWWWWWWWWW', 200, Canvas.ItemNoFont(), Canvas.SmallFont()), 'Never below the minimum.');

        SetLabelSize(Setup, 0, 0);
        LongNo := 'MKW-WM2026-KRM-00154';
        SeedItem(LongNo, 'M193 FMJ KIVIRMA İÇ BASKI ZIMBASI BURCU');
        Item.Get(LongNo);
        Zpl := Dispatcher.BuildItemZpl(Item);
        Assert.IsTrue(StrPos(Zpl, '^A0N,32,') > 0, 'Long item no is printed at 32 dots high.');
        Assert.IsTrue(StrPos(Zpl, '^A0N,57,57') = 0, 'The old 57-dot item no size is gone.');
        AssertInsideCanvas(Zpl, 640, 320, 'long item no');
    end;

    /// <summary>Every ^FO origin must lie inside the label; a design that grew past the canvas is caught here.</summary>
    local procedure AssertInsideCanvas(Zpl: Text; Width: Integer; Height: Integer; Context: Text)
    var
        Assert: Codeunit "Library Assert";
        Pos: Integer;
        Comma: Integer;
        Caret: Integer;
        X: Integer;
        Y: Integer;
        Fields: Integer;
    begin
        Pos := StrPos(Zpl, '^FO');
        while Pos > 0 do begin
            Zpl := CopyStr(Zpl, Pos + 3);
            Comma := StrPos(Zpl, ',');
            Caret := StrPos(Zpl, '^');
            Evaluate(X, CopyStr(Zpl, 1, Comma - 1));
            Evaluate(Y, CopyStr(Zpl, Comma + 1, Caret - Comma - 1));
            Assert.IsTrue((X >= 0) and (X < Width), StrSubstNo('%1: field origin x=%2 outside the %3-dot width.', Context, X, Width));
            Assert.IsTrue((Y >= 0) and (Y < Height), StrSubstNo('%1: field origin y=%2 outside the %3-dot height.', Context, Y, Height));
            Fields += 1;
            Pos := StrPos(Zpl, '^FO');
        end;
        Assert.IsTrue(Fields >= 5, Context + ': the design has fields.');
    end;

    local procedure SetLabelSize(var Setup: Record "DOPSWHS Setup"; WidthMm: Decimal; HeightMm: Decimal)
    begin
        if not Setup.Get() then begin
            Setup.Init();
            Setup.Insert();
        end;
        Setup."Label Width (mm)" := WidthMm;
        Setup."Label Height (mm)" := HeightMm;
        Setup.Modify();
    end;

    local procedure SeedTemplate(Code: Code[20]; Kind: Enum "DOPSWHS LP Container Kind"; IncludeContents: Boolean)
    var
        Template: Record "DOPSWHS LP Template";
    begin
        if Template.Get(Code) then
            Template.Delete();
        Template.Init();
        Template.Code := Code;
        Template.Description := Code;
        Template."Container Kind" := Kind;
        Template."Label Design" := Template."Label Design"::ByContainerKind;
        Template."Label Includes Contents" := IncludeContents;
        Template."Label Copies" := 1;
        Template."Allow Mixed Items" := true;
        Template."Allow Mixed Lots" := true;
        Template.Insert();
    end;

    local procedure SeedLp(var LP: Record "DOPSWHS LP Header"; No: Code[20]; TemplateCode: Code[20])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if LP.Get(No) then begin
            LPLine.SetRange("LP No.", No);
            LPLine.DeleteAll();
            LP.Delete();
        end;
        LP.Init();
        LP."No." := No;
        LP."LP Template Code" := TemplateCode;
        LP."Location Code" := 'CNV-LOC';
        LP."Bin Code" := 'A.A01.11';
        LP.Status := LP.Status::Open;
        LP.Insert();
    end;

    local procedure SeedLine(var LP: Record "DOPSWHS LP Header"; LineNo: Integer; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        SeedItem(ItemNo, 'Test item ' + ItemNo);
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine."Line No." := LineNo;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Qty;
        LPLine."Lot No." := LotNo;
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
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert();
    end;
}
