/// <summary>
/// Kitoko (23 Eki 2026): "8x4 (80x40 mm) seçiyorum, çıkarırken tam sığmıyor".
/// The ZPL of a layout must be exactly the chosen size (^PW/^LL in printer dots,
/// 203 dpi = 8 dots/mm) and every printed field must stay inside it: field origins,
/// ^FB text boxes, ^A0 glyph heights, ^GB boxes, barcode bar heights and QR symbols
/// (drawn 10 dots below ^FO). Pure record setup, no posting.
/// </summary>
codeunit 72163 "DOPSWHS Label Size Fit Tests"
{
    Subtype = Test;

    [Test]
    procedure SeededEightyByFortyLayoutsFitAt203Dpi()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Codes: List of [Code[20]];
        LayoutCode: Code[20];
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Engine.EnsureLotLayout();
        Codes.Add('ITEM');
        Codes.Add('BIN');
        Codes.Add('ZONE');
        Codes.Add('ETIKETV2');
        Codes.Add('LOT');
        foreach LayoutCode in Codes do begin
            Zpl := Engine.BuildSampleZpl(LayoutCode);
            AssertHeader(Zpl, 640, 320, LayoutCode);
            AssertInside(Zpl, 640, 320, LayoutCode);
        end;
    end;

    [Test]
    procedure EightyByFortyDesignHasExactPrintSize()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('FIT80', 80, 40, 203);
        AddField('FIT80', 'ItemNo', 2, 2, 53, 4.5, true);
        AddQr('FIT80', 'ItemNo', 57, 2, 21);
        AddBarcode('FIT80', 'ItemNo', 2, 24, 53, 8, true);
        AddBox('FIT80', 0, 0, 80, 1, 0);
        AddBox('FIT80', 0, 39, 80, 1, 0);
        Zpl := Engine.BuildSampleZpl('FIT80');
        AssertHeader(Zpl, 640, 320, 'FIT80');
        AssertInside(Zpl, 640, 320, 'FIT80');
        Assert.IsTrue(StrPos(Zpl, '^FO0,312^GB640,8,8^FS') > 0, 'A 1 mm bar on the bottom edge ends exactly on dot 320.');
        Assert.IsTrue(StrPos(Zpl, '^FO456,16^BQN,2,') > 0, 'QR at 57/2 mm = 456/16 dots.');
    end;

    [Test]
    procedure OversizedDesignIsKeptInsideEightyByForty()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        // A 100x50 mm design whose label was switched to 80x40 without moving the elements.
        ClearLayouts();
        CreateLayout('BIG', 80, 40, 203);
        AddQr('BIG', 'ItemNo', 2, 2, 30);
        AddField('BIG', 'Description', 35, 2, 63, 9, true);
        AddField('BIG', 'ItemNo', 35, 37.5, 63, 5.5, false);
        AddBarcode('BIG', 'ItemNo', 35, 30, 63, 12, true);
        AddBox('BIG', 0, 0, 100, 6, 0);
        AddBox('BIG', 35, 43.5, 63, 0.4, 0);
        AddQr('BIG', 'ItemNo', 70, 20, 25);
        AddField('BIG', 'UoM', 85, 10, 10, 3, false);
        Zpl := Engine.BuildSampleZpl('BIG');
        AssertHeader(Zpl, 640, 320, 'BIG');
        AssertInside(Zpl, 640, 320, 'BIG');
        Assert.IsTrue(StrPos(Zpl, '^FO0,0^GB640,48,48^FS') > 0, 'The 100 mm band is cut to the 80 mm label.');
        Assert.AreEqual(0, StrPos(Zpl, 'ADET'), 'An element starting right of the label (x 85 mm) is not printed.');
    end;

    [Test]
    procedure HundredByFiftyLayoutFits()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('LPQR50', 100, 50, 203);
        // Same geometry as the gallery template "LP QR + Lot (100x50)".
        AddQr('LPQR50', 'ItemNo', 2, 2, 30);
        AddText('LPQR50', 'QR = LP NO', 2, 33, 30, 2.25);
        AddField('LPQR50', 'ItemNo', 35, 2, 63, 9, true);
        AddBox('LPQR50', 35, 12.5, 63, 0.4, 0);
        AddField('LPQR50', 'Description', 35, 19, 63, 2.75, false);
        AddField('LPQR50', 'UoM', 76, 36, 22, 5.5, true);
        AddBox('LPQR50', 35, 43.5, 63, 0.3, 0);
        AddField('LPQR50', 'Company', 35, 45.5, 40, 2.5, true);
        AddField('LPQR50', 'Today', 76, 45.5, 22, 2.5, false);
        Zpl := Engine.BuildSampleZpl('LPQR50');
        AssertHeader(Zpl, 800, 400, 'LPQR50');
        AssertInside(Zpl, 800, 400, 'LPQR50');
    end;

    [Test]
    procedure HundredByHundredLayoutFits()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('LP100', 100, 100, 203);
        AddBox('LP100', 0, 0, 100, 9, 0);
        AddText('LP100', 'PALET ETİKETİ', 3, 2, 60, 5);
        AddQr('LP100', 'ItemNo', 64, 12, 34);
        AddField('LP100', 'ItemNo', 3, 12, 58, 12, true);
        AddField('LP100', 'Description', 3, 30, 58, 4, true);
        AddBarcode('LP100', 'ItemNo', 3, 70, 94, 20, true);
        AddField('LP100', 'Today', 3, 96, 94, 3, false);
        Zpl := Engine.BuildSampleZpl('LP100');
        AssertHeader(Zpl, 800, 800, 'LP100');
        AssertInside(Zpl, 800, 800, 'LP100');
    end;

    [Test]
    procedure SeededLpLayoutFitsFourByTwoInches()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Zpl: Text;
    begin
        ClearLayouts();
        Engine.SeedDefaults();
        Zpl := Engine.BuildSampleZpl('LP');
        // 101.6 x 50.8 mm at 8 dots/mm.
        AssertHeader(Zpl, 813, 406, 'LP');
        AssertInside(Zpl, 813, 406, 'LP');
    end;

    [Test]
    procedure ThreeHundredDpiUsesTwelveDotsPerMm()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Zpl: Text;
    begin
        ClearLayouts();
        CreateLayout('FIT300', 80, 40, 300);
        AddField('FIT300', 'ItemNo', 2, 2, 76, 6, true);
        AddQr('FIT300', 'ItemNo', 55, 15, 23);
        AddBox('FIT300', 0, 38, 80, 2, 0);
        Zpl := Engine.BuildSampleZpl('FIT300');
        AssertHeader(Zpl, 960, 480, 'FIT300');
        AssertInside(Zpl, 960, 480, 'FIT300');
    end;

    [Test]
    procedure PrinterResolutionMustMatchLayout()
    var
        Printer: Record "DOPSWHS Printer";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
    begin
        if Printer.Get('ZD230-DPI') then
            Printer.Delete();
        Printer.Init();
        Printer."Code" := 'ZD230-DPI';
        Printer."Format" := Printer."Format"::ZPL;
        Printer.Insert();

        // Unknown resolution: nothing to compare.
        Dispatcher.CheckLayoutDpi('ZD230-DPI', 300);

        Printer.Validate("Resolution (dpi)", 203);
        Printer.Modify();
        Dispatcher.CheckLayoutDpi('ZD230-DPI', 203);
        Dispatcher.CheckLayoutDpi('ZD230-DPI', 0);
        asserterror Dispatcher.CheckLayoutDpi('ZD230-DPI', 300);
        Assert.ExpectedError('300 dpi');

        asserterror Printer.Validate("Resolution (dpi)", 250);
        Assert.ExpectedError('203, 300 veya 600');
        Printer.Delete();
    end;

    // ------------------------------------------------------------------
    // ZPL bounds checker
    // ------------------------------------------------------------------

    local procedure AssertHeader(Zpl: Text; WidthDots: Integer; HeightDots: Integer; Context: Text)
    var
        Assert: Codeunit "Library Assert";
    begin
        Assert.IsTrue(StrPos(Zpl, '^XA^CI28^PW' + Format(WidthDots) + '^LL' + Format(HeightDots) + '^LH0,0') = 1,
            StrSubstNo('%1: header must be ^PW%2^LL%3 (got %4).', Context, WidthDots, HeightDots, CopyStr(Zpl, 1, 40)));
    end;

    /// <summary>Every ^FO field of Zpl lies inside WidthDots x HeightDots (ink extents as Labelary draws them).</summary>
    local procedure AssertInside(Zpl: Text; WidthDots: Integer; HeightDots: Integer; Context: Text)
    var
        Assert: Codeunit "Library Assert";
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Fields: List of [Text];
        FieldZpl: Text;
        Orientation: Text;
        X: Integer;
        Y: Integer;
        W: Integer;
        H: Integer;
        Magnification: Integer;
        Side: Integer;
        Pos: Integer;
        Checked: Integer;
    begin
        Fields := Zpl.Split('^FS');
        foreach FieldZpl in Fields do begin
            Pos := StrPos(FieldZpl, '^FO');
            if Pos > 0 then begin
                Pos += 3;
                X := ReadInt(FieldZpl, Pos);
                Pos += 1;
                Y := ReadInt(FieldZpl, Pos);
                Checked += 1;
                Assert.IsTrue((X >= 0) and (X < WidthDots) and (Y >= 0) and (Y < HeightDots), StrSubstNo('%1: field origin %2,%3 outside %4x%5: %6', Context, X, Y, WidthDots, HeightDots, FieldZpl));

                Pos := StrPos(FieldZpl, '^GB');
                if Pos > 0 then begin
                    Pos += 3;
                    W := ReadInt(FieldZpl, Pos);
                    Pos += 1;
                    H := ReadInt(FieldZpl, Pos);
                    Assert.IsTrue((X + W <= WidthDots) and (Y + H <= HeightDots), StrSubstNo('%1: box runs off the label: %2', Context, FieldZpl));
                end;

                Pos := StrPos(FieldZpl, '^A0');
                if Pos > 0 then begin
                    Orientation := CopyStr(FieldZpl, Pos + 3, 1);
                    Pos += 5;
                    H := ReadInt(FieldZpl, Pos);
                    if Orientation in ['R', 'B'] then
                        Assert.IsTrue(X + H <= WidthDots, StrSubstNo('%1: turned text runs off the right edge: %2', Context, FieldZpl))
                    else
                        Assert.IsTrue(Y + H <= HeightDots, StrSubstNo('%1: text runs off the bottom: %2', Context, FieldZpl));
                    Pos := StrPos(FieldZpl, '^FB');
                    if Pos > 0 then begin
                        Pos += 3;
                        W := ReadInt(FieldZpl, Pos);
                        if Orientation in ['R', 'B'] then
                            Assert.IsTrue(Y + W <= HeightDots, StrSubstNo('%1: turned text box runs off the bottom: %2', Context, FieldZpl))
                        else
                            Assert.IsTrue(X + W <= WidthDots, StrSubstNo('%1: text box runs off the right edge: %2', Context, FieldZpl));
                    end;
                end;

                Pos := StrPos(FieldZpl, '^BQN,2,');
                if Pos > 0 then begin
                    Pos += 7;
                    Magnification := ReadInt(FieldZpl, Pos);
                    Side := Magnification * Canvas.QrModules(CopyStr(FieldZpl, StrPos(FieldZpl, '^FDLA,') + 6));
                    Assert.IsTrue((X + Side <= WidthDots) and (Y + 10 + Side <= HeightDots), StrSubstNo('%1: QR (%2 dots) runs off the label: %3', Context, Side, FieldZpl));
                end;

                Pos := StrPos(FieldZpl, '^BC');
                if Pos = 0 then
                    Pos := StrPos(FieldZpl, '^BE');
                if Pos > 0 then begin
                    Orientation := CopyStr(FieldZpl, Pos + 3, 1);
                    Pos += 5;
                    H := ReadInt(FieldZpl, Pos);
                    if Orientation in ['R', 'B'] then
                        Assert.IsTrue(X + H <= WidthDots, StrSubstNo('%1: turned barcode runs off the right edge: %2', Context, FieldZpl))
                    else
                        Assert.IsTrue(Y + H <= HeightDots, StrSubstNo('%1: barcode runs off the bottom: %2', Context, FieldZpl));
                end;
            end;
        end;
        Assert.IsTrue(Checked > 0, Context + ': no printed fields');
    end;

    local procedure ReadInt(Value: Text; var Pos: Integer): Integer
    var
        Digits: Text;
        Result: Integer;
    begin
        while (Pos <= StrLen(Value)) and (StrPos('0123456789', CopyStr(Value, Pos, 1)) > 0) do begin
            Digits += CopyStr(Value, Pos, 1);
            Pos += 1;
        end;
        if Digits = '' then
            exit(-1);
        Evaluate(Result, Digits);
        exit(Result);
    end;

    // ------------------------------------------------------------------
    // Layout builders
    // ------------------------------------------------------------------

    local procedure ClearLayouts()
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.DeleteAll(true);
    end;

    local procedure CreateLayout(LayoutCode: Code[20]; WidthMm: Decimal; HeightMm: Decimal; Dpi: Integer)
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.Init();
        Layout."Code" := LayoutCode;
        Layout."Label Kind" := Layout."Label Kind"::Item;
        Layout."Width (mm)" := WidthMm;
        Layout."Height (mm)" := HeightMm;
        Layout.Dpi := Dpi;
        Layout.Insert();
    end;

    local procedure NewLine(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; ElementType: Enum "DOPSWHS Label Element Type"; X: Decimal; Y: Decimal; W: Decimal; H: Decimal)
    var
        Last: Record "DOPSWHS Label Layout Line";
    begin
        Last.SetRange("Layout Code", LayoutCode);
        LayoutLine.Init();
        LayoutLine."Layout Code" := LayoutCode;
        LayoutLine."Line No." := 10000;
        if Last.FindLast() then
            LayoutLine."Line No." := Last."Line No." + 10000;
        LayoutLine."Element Type" := ElementType;
        LayoutLine."X (mm)" := X;
        LayoutLine."Y (mm)" := Y;
        LayoutLine."Width (mm)" := W;
        LayoutLine."Height (mm)" := H;
        LayoutLine.Enabled := true;
    end;

    local procedure AddField(LayoutCode: Code[20]; FieldKey: Text[30]; X: Decimal; Y: Decimal; W: Decimal; FontMm: Decimal; FitToWidth: Boolean)
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        NewLine(LayoutLine, LayoutCode, LayoutLine."Element Type"::Field, X, Y, W, 0);
        LayoutLine."Source Field" := FieldKey;
        LayoutLine."Font Height (mm)" := FontMm;
        LayoutLine."Fit to Width" := FitToWidth;
        LayoutLine.Insert();
    end;

    local procedure AddText(LayoutCode: Code[20]; Value: Text[100]; X: Decimal; Y: Decimal; W: Decimal; FontMm: Decimal)
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        NewLine(LayoutLine, LayoutCode, LayoutLine."Element Type"::Text, X, Y, W, 0);
        LayoutLine."Static Text" := Value;
        LayoutLine."Font Height (mm)" := FontMm;
        LayoutLine.Insert();
    end;

    local procedure AddQr(LayoutCode: Code[20]; FieldKey: Text[30]; X: Decimal; Y: Decimal; Side: Decimal)
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        NewLine(LayoutLine, LayoutCode, LayoutLine."Element Type"::QRCode, X, Y, Side, Side);
        LayoutLine."Source Field" := FieldKey;
        LayoutLine.Insert();
    end;

    local procedure AddBarcode(LayoutCode: Code[20]; FieldKey: Text[30]; X: Decimal; Y: Decimal; W: Decimal; H: Decimal; ShowText: Boolean)
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        NewLine(LayoutLine, LayoutCode, LayoutLine."Element Type"::Barcode128, X, Y, W, H);
        LayoutLine."Source Field" := FieldKey;
        LayoutLine."Show Text" := ShowText;
        LayoutLine.Insert();
    end;

    local procedure AddBox(LayoutCode: Code[20]; X: Decimal; Y: Decimal; W: Decimal; H: Decimal; ThicknessMm: Decimal)
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        NewLine(LayoutLine, LayoutCode, LayoutLine."Element Type"::Box, X, Y, W, H);
        LayoutLine."Thickness (mm)" := ThicknessMm;
        LayoutLine.Insert();
    end;
}
