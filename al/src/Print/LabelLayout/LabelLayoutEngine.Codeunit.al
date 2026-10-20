// Kitoko (20 Eki 2026): etiket tasarım tablolarından ZPL üretir. Ölçüler mm,
// ZPL'e dpi'ye göre nokta olarak çevrilir. Yazı ölçme/sarma/QR boyutu
// Label Canvas'taki yardımcılarla yapılır; ^CI28 (UTF-8) Türkçe karakterler için.
codeunit 72466 "DOPSWHS Label Layout Engine"
{
    Access = Public;
    Permissions = tabledata "DOPSWHS Label Layout" = RIMD,
                  tabledata "DOPSWHS Label Layout Line" = RIMD,
                  tabledata "DOPSWHS Setup" = R;

    var
        Canvas: Codeunit "DOPSWHS Label Canvas";

    /// <summary>mm to printer dots (203 dpi = 8 dots per mm); a Dpi of 0 means 203.</summary>
    procedure MmToDots(Mm: Decimal; Dpi: Integer): Integer
    begin
        if Dpi <= 0 then
            Dpi := 203;
        if Mm <= 0 then
            exit(0);
        // 203 dpi is 8 dots/mm, 300 dpi 12, 600 dpi 24 (Label Canvas uses the same 8 dots/mm).
        exit(Round(Mm * Round(Dpi / 25.4, 1), 1));
    end;

    /// <summary>The active layout of this kind (ITEM/BIN/ZONE preferred); false = use the built-in design.</summary>
    procedure FindActiveLayout(Kind: Enum "DOPSWHS Label Kind"; var LayoutCode: Code[20]): Boolean
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        if not Layout.ReadPermission() then
            exit(false);
        Layout.SetRange("Label Kind", Kind);
        Layout.SetRange(Active, true);
        if not Layout.FindFirst() then
            exit(false);
        LayoutCode := Layout."Code";
        exit(true);
    end;

    /// <summary>Effective label size of a layout (0 = Setup size, else 80x40 mm).</summary>
    procedure LayoutSize(LayoutCode: Code[20]; var WidthMm: Decimal; var HeightMm: Decimal; var Dpi: Integer)
    var
        Layout: Record "DOPSWHS Label Layout";
        Setup: Record "DOPSWHS Setup";
    begin
        Layout.Get(LayoutCode);
        WidthMm := Layout."Width (mm)";
        HeightMm := Layout."Height (mm)";
        Dpi := Layout.Dpi;
        if Dpi <= 0 then
            Dpi := 203;
        if (WidthMm <= 0) or (HeightMm <= 0) then
            if Setup.Get() then begin
                if WidthMm <= 0 then
                    WidthMm := Setup."Label Width (mm)";
                if HeightMm <= 0 then
                    HeightMm := Setup."Label Height (mm)";
            end;
        if WidthMm <= 0 then
            WidthMm := 80;
        if HeightMm <= 0 then
            HeightMm := 40;
    end;

    /// <summary>ZPL (^XA..^XZ) of the layout filled with Values; Copies above 1 adds ^PQ.</summary>
    procedure BuildZpl(LayoutCode: Code[20]; Values: Dictionary of [Text, Text]; Copies: Integer): Text
    begin
        exit(BuildZplWithYOffset(LayoutCode, Values, Copies, 0));
    end;

    /// <summary>ZPL for a layout with every element shifted down by YOffsetMm.</summary>
    procedure BuildZplWithYOffset(LayoutCode: Code[20]; Values: Dictionary of [Text, Text]; Copies: Integer; YOffsetMm: Decimal): Text
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
        WidthDots: Integer;
        HeightDots: Integer;
        Zpl: Text;
    begin
        LayoutSize(LayoutCode, WidthMm, HeightMm, Dpi);
        WidthDots := MmToDots(WidthMm, Dpi);
        HeightDots := MmToDots(HeightMm, Dpi);
        Canvas.InitSize(WidthMm, HeightMm);
        Zpl := '^XA^CI28^PW' + Format(WidthDots) + '^LL' + Format(HeightDots) + '^LH0,0';
        LayoutLine.SetRange("Layout Code", LayoutCode);
        LayoutLine.SetRange(Enabled, true);
        if LayoutLine.FindSet() then
            repeat
                Zpl += BuildElement(LayoutLine, Values, Dpi, WidthDots, YOffsetMm);
            until LayoutLine.Next() = 0;
        if Copies > 1 then
            Zpl += '^PQ' + Format(Copies);
        exit(Zpl + '^XZ');
    end;

    /// <summary>ZPL of the layout with made-up sample values.</summary>
    procedure BuildSampleZpl(LayoutCode: Code[20]): Text
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
        Values: Dictionary of [Text, Text];
    begin
        Layout.Get(LayoutCode);
        LayoutFields.SampleValues(Layout."Label Kind", Values);
        exit(BuildZpl(LayoutCode, Values, 1));
    end;

    local procedure BuildElement(var LayoutLine: Record "DOPSWHS Label Layout Line"; var Values: Dictionary of [Text, Text]; Dpi: Integer; LabelWidthDots: Integer; YOffsetMm: Decimal): Text
    var
        Value: Text;
        X: Integer;
        Y: Integer;
        W: Integer;
        H: Integer;
        Thickness: Integer;
        Side: Integer;
    begin
        X := MmToDots(LayoutLine."X (mm)", Dpi);
        Y := MmToDots(LayoutLine."Y (mm)" + YOffsetMm, Dpi);
        W := MmToDots(LayoutLine."Width (mm)", Dpi);
        H := MmToDots(LayoutLine."Height (mm)", Dpi);
        case LayoutLine."Element Type" of
            LayoutLine."Element Type"::Text, LayoutLine."Element Type"::Field:
                exit(BuildText(LayoutLine, ResolveValue(LayoutLine, Values), X, Y, W, Dpi, LabelWidthDots));
            LayoutLine."Element Type"::Barcode128:
                begin
                    Value := ResolveValue(LayoutLine, Values);
                    if Value = '' then
                        exit('');
                    if W = 0 then
                        W := LabelWidthDots - X - 16;
                    if H = 0 then
                        H := MmToDots(10, Dpi);
                    exit(Canvas.Code128(X, Y, H, Value, W, LayoutLine."Show Text"));
                end;
            LayoutLine."Element Type"::QRCode:
                begin
                    Value := ResolveValue(LayoutLine, Values);
                    if Value = '' then
                        exit('');
                    Side := W;
                    if Side = 0 then
                        Side := H;
                    if Side = 0 then
                        Side := MmToDots(20, Dpi);
                    exit(Canvas.Qr(X, Y, Canvas.QrMagnification(Value, Side), Value));
                end;
            LayoutLine."Element Type"::Line, LayoutLine."Element Type"::Box:
                begin
                    if W = 0 then
                        W := 1;
                    if H = 0 then
                        H := 1;
                    Thickness := MmToDots(LayoutLine."Thickness (mm)", Dpi);
                    if (Thickness = 0) or (LayoutLine."Element Type" = LayoutLine."Element Type"::Line) then begin
                        Thickness := W;
                        if H < Thickness then
                            Thickness := H;
                    end;
                    exit('^FO' + Format(X) + ',' + Format(Y) + '^GB' + Format(W) + ',' + Format(H) + ',' + Format(Thickness) + '^FS');
                end;
        end;
        exit('');
    end;

    local procedure BuildText(var LayoutLine: Record "DOPSWHS Label Layout Line"; Value: Text; X: Integer; Y: Integer; W: Integer; Dpi: Integer; LabelWidthDots: Integer): Text
    var
        Lines: List of [Text];
        TextLine: Text;
        Zpl: Text;
        FontHeight: Integer;
        FontWidth: Integer;
        MinHeight: Integer;
        FitSize: Integer;
        Index: Integer;
    begin
        if Value = '' then
            exit('');
        if W = 0 then
            W := LabelWidthDots - X;
        if W < 8 then
            W := 8;
        FontHeight := MmToDots(LayoutLine."Font Height (mm)", Dpi);
        if FontHeight = 0 then
            FontHeight := MmToDots(2.75, Dpi);
        FontWidth := MmToDots(LayoutLine."Font Width (mm)", Dpi);
        if FontWidth = 0 then
            FontWidth := FontHeight;
        if LayoutLine."Fit to Width" then begin
            MinHeight := MmToDots(LayoutLine."Min Font Height (mm)", Dpi);
            if (MinHeight = 0) or (MinHeight > FontHeight) then
                MinHeight := FontHeight div 2;
            FitSize := Canvas.FitFontMeasured(Value, W, FontHeight, MinHeight);
            // Even the smallest size too wide: condense the glyphs instead of overprinting.
            FontWidth := Canvas.FitFontMeasured(Value, W, FitSize, 10);
            FontHeight := FitSize;
        end;
        if LayoutLine."Max Lines" > 1 then begin
            Canvas.WrapText(Value, Canvas.MaxChars(W, FontHeight), LayoutLine."Max Lines", Lines);
            foreach TextLine in Lines do begin
                Zpl += TextLineZpl(LayoutLine, X, Y + Index * (FontHeight + 6), FontHeight, FontWidth, W, TextLine);
                Index += 1;
            end;
            exit(Zpl);
        end;
        exit(TextLineZpl(LayoutLine, X, Y, FontHeight, FontWidth, W, Value));
    end;

    local procedure TextLineZpl(var LayoutLine: Record "DOPSWHS Label Layout Line"; X: Integer; Y: Integer; FontHeight: Integer; FontWidth: Integer; W: Integer; Value: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
        Align: Text;
    begin
        case LayoutLine.Alignment of
            LayoutLine.Alignment::Center:
                Align := 'C';
            LayoutLine.Alignment::Right:
                Align := 'R';
            else
                Align := 'L';
        end;
        Zpl := '^FO' + Format(X) + ',' + Format(Y) + '^A0N,' + Format(FontHeight) + ',' + Format(FontWidth);
        if LayoutLine.Inverted then
            Zpl += '^FR';
        exit(Zpl + '^FH_^FB' + Format(W) + ',1,0,' + Align + '^FD' + ZplEncoder.EncodeFieldData(Value) + '^FS');
    end;

    /// <summary>Source field value (or the static text when no field is set) with prefix/suffix; empty stays empty.</summary>
    local procedure ResolveValue(var LayoutLine: Record "DOPSWHS Label Layout Line"; var Values: Dictionary of [Text, Text]): Text
    var
        Raw: Text;
    begin
        if LayoutLine."Source Field" <> '' then begin
            if Values.ContainsKey(LayoutLine."Source Field") then
                Raw := Values.Get(LayoutLine."Source Field");
        end else
            Raw := LayoutLine."Static Text";
        if Raw = '' then
            exit('');
        exit(LayoutLine.Prefix + Raw + LayoutLine.Suffix);
    end;

    // ------------------------------------------------------------------
    // Default layouts (reproduce the built-in 80x40 mm designs)
    // ------------------------------------------------------------------

    /// <summary>Creates ITEM/BIN/ZONE when missing. They start inactive so printing does not change until the user activates one.</summary>
    procedure SeedDefaults()
    var
        Layout: Record "DOPSWHS Label Layout";
        Kind: Enum "DOPSWHS Label Kind";
        KindOrdinal: Integer;
    begin
        foreach KindOrdinal in Kind.Ordinals() do begin
            Kind := Enum::"DOPSWHS Label Kind".FromInteger(KindOrdinal);
            if not Layout.Get(DefaultCode(Kind)) then begin
                CreateLayout(Kind);
                FillDefaultLines(DefaultCode(Kind), Kind);
            end;
        end;
        EnsureItemV2Layout();
    end;

    /// <summary>Creates the QR-only item label option when it is missing.</summary>
    procedure EnsureItemV2Layout()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        LineNo: Integer;
    begin
        if Layout.Get('ETIKETV2') then
            exit;
        Layout.Init();
        Layout.Code := 'ETIKETV2';
        Layout.Description := 'Ürün etiketi V2 - QR + madde no';
        Layout."Label Kind" := Enum::"DOPSWHS Label Kind"::Item;
        Layout."Width (mm)" := 80;
        Layout."Height (mm)" := 40;
        Layout.Dpi := 203;
        Layout.Active := false;
        Layout.Insert(true);
        FillItemV2Lines(LayoutLine, Layout.Code, LineNo);
    end;

    /// <summary>Replaces all lines of the layout with the default design of its kind (80x40 mm, 203 dpi).</summary>
    procedure ResetToDefault(LayoutCode: Code[20])
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        Layout.Get(LayoutCode);
        LayoutLine.SetRange("Layout Code", LayoutCode);
        LayoutLine.DeleteAll();
        Layout."Width (mm)" := 80;
        Layout."Height (mm)" := 40;
        Layout.Dpi := 203;
        Layout.Modify();
        FillDefaultLines(LayoutCode, Layout."Label Kind");
    end;

    procedure DefaultCode(Kind: Enum "DOPSWHS Label Kind"): Code[20]
    begin
        case Kind of
            Kind::Item:
                exit('ITEM');
            Kind::Bin:
                exit('BIN');
        end;
        exit('ZONE');
    end;

    local procedure CreateLayout(Kind: Enum "DOPSWHS Label Kind")
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.Init();
        Layout."Code" := DefaultCode(Kind);
        Layout."Label Kind" := Kind;
        Layout."Width (mm)" := 80;
        Layout."Height (mm)" := 40;
        Layout.Dpi := 203;
        case Kind of
            Kind::Item:
                Layout.Description := 'Ürün etiketi (varsayılan)';
            Kind::Bin:
                Layout.Description := 'Raf etiketi (varsayılan)';
            Kind::Zone:
                Layout.Description := 'Alan etiketi (varsayılan)';
        end;
        Layout.Insert();
    end;

    local procedure FillDefaultLines(LayoutCode: Code[20]; Kind: Enum "DOPSWHS Label Kind")
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
        LineNo: Integer;
        Title: Text[100];
        RightField: Text[30];
        CodeField: Text[30];
    begin
        if LayoutCode = 'ETIKETV2' then begin
            FillItemV2Lines(LayoutLine, LayoutCode, LineNo);
            exit;
        end;
        // Siyah başlık şeridi (5,5 mm): sol başlık, sağ firma/depo adı, ikisi beyaz.
        case Kind of
            Kind::Item:
                begin
                    Title := 'ÜRÜN ETİKETİ';
                    RightField := 'Company';
                    CodeField := 'ItemNo';
                end;
            Kind::Bin:
                begin
                    Title := 'RAF ETİKETİ';
                    RightField := 'LocationCode';
                    CodeField := 'BinCode';
                end;
            Kind::Zone:
                begin
                    Title := 'ALAN ETİKETİ';
                    RightField := 'LocationCode';
                    CodeField := 'ZoneCode';
                end;
        end;
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Box, 0, 0, 80, 5.5);
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Text, 2, 1, 76, 0);
        LayoutLine."Static Text" := Title;
        LayoutLine."Font Height (mm)" := 3.5;
        LayoutLine.Inverted := true;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 1.5, 76, 0);
        LayoutLine."Source Field" := RightField;
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Inverted := true;
        LayoutLine.Insert();
        // Sağda QR (21 mm), solda 53 mm'lik metin sütunu.
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 57, 6.5, 21, 21);
        LayoutLine."Source Field" := CodeField;
        LayoutLine.Insert();

        case Kind of
            Kind::Item:
                FillItemLines(LayoutLine, LayoutCode, LineNo);
            Kind::Bin:
                FillBinLines(LayoutLine, LayoutCode, LineNo);
            Kind::Zone:
                FillZoneLines(LayoutLine, LayoutCode, LineNo);
        end;
    end;

    local procedure FillItemLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 6.5, 53, 0);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine."Font Height (mm)" := 4;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.25;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 11.5, 53, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine."Max Lines" := 2;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 18.5, 18, 0);
        LayoutLine."Source Field" := 'UoM';
        LayoutLine.Prefix := 'BİRİM: ';
        LayoutLine."Font Height (mm)" := 2.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 20, 18.5, 35, 0);
        LayoutLine."Source Field" := 'Gtin';
        LayoutLine.Prefix := 'GTIN: ';
        LayoutLine."Font Height (mm)" := 2.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 1.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Barcode128, 2, 21.75, 53, 11.1);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine."Show Text" := true;
        LayoutLine.Insert();
    end;

    local procedure FillItemV2Lines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        // QR'ı önceki konumundan 10 mm sola al; madde numarasını altına ortala.
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 50, 6.5, 15, 15);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 42, 26.5, 31, 0);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine."Font Height (mm)" := 2.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 1.5;
        LayoutLine.Alignment := LayoutLine.Alignment::Center;
        LayoutLine.Insert();
    end;

    local procedure FillBinLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 6.5, 51, 0);
        LayoutLine."Source Field" := 'BinCode';
        LayoutLine."Font Height (mm)" := 13.9;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 4.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 21.25, 51, 0);
        LayoutLine."Source Field" := 'ZoneCode';
        LayoutLine."Font Height (mm)" := 4.4;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.75;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 26.4, 53, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Barcode128, 2, 30.1, 53, 7.9);
        LayoutLine."Source Field" := 'BinCode';
        LayoutLine.Insert();
    end;

    local procedure FillZoneLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 6.5, 51, 0);
        LayoutLine."Source Field" := 'ZoneCode';
        LayoutLine."Font Height (mm)" := 13.9;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 4.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 21.25, 53, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Barcode128, 2, 25, 53, 11.1);
        LayoutLine."Source Field" := 'ZoneCode';
        LayoutLine.Insert();
    end;

    local procedure NewLine(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer; ElementType: Enum "DOPSWHS Label Element Type"; X: Decimal; Y: Decimal; W: Decimal; H: Decimal)
    begin
        LineNo += 10000;
        Clear(LayoutLine);
        LayoutLine.Init();
        LayoutLine."Layout Code" := LayoutCode;
        LayoutLine."Line No." := LineNo;
        LayoutLine."Element Type" := ElementType;
        LayoutLine."X (mm)" := X;
        LayoutLine."Y (mm)" := Y;
        LayoutLine."Width (mm)" := W;
        LayoutLine."Height (mm)" := H;
        LayoutLine.Enabled := true;
    end;
}
