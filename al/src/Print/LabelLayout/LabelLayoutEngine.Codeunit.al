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
        EtiketV2SizeTagTxt: Label 'DOPSWHS-KITOKO-ETIKETV2-SIZE-20261021', Locked = true;
        LpQrSeedTagTxt: Label 'DOPSWHS-KITOKO-LPQR-SEED-20261022', Locked = true;
        LpQrCodeTok: Label 'LP-QR', Locked = true;

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

    /// <summary>
    /// Kitoko (21 Eki 2026): terminalde seçilen etiket tasarımı. Boş kod = bugünkü
    /// davranış (bu türün aktif tasarımı; yoksa false → koddaki sabit tasarım).
    /// Dolu kod: tasarım var olmalı ve türü Kind olmalı, yoksa hata.
    /// </summary>
    procedure ResolveLayout(Kind: Enum "DOPSWHS Label Kind"; RequestedCode: Code[20]; var LayoutCode: Code[20]): Boolean
    begin
        if RequestedCode = '' then
            exit(FindActiveLayout(Kind, LayoutCode));
        CheckLayoutKind(RequestedCode, Kind);
        LayoutCode := RequestedCode;
        exit(true);
    end;

    /// <summary>Kitoko (21 Eki 2026): errors when the layout is missing or belongs to another label kind.</summary>
    procedure CheckLayoutKind(LayoutCode: Code[20]; Kind: Enum "DOPSWHS Label Kind")
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        if not Layout.Get(LayoutCode) then
            Error('Etiket tasarımı %1 bulunamadı.', LayoutCode);
        if Layout."Label Kind" <> Kind then
            Error('%1 etiket tasarımının türü %2; %3 etiketi için kullanılamaz.', LayoutCode, Layout."Label Kind", Kind);
    end;

    /// <summary>Effective label size of a layout (0 = Setup size, else 80x40 mm).</summary>
    procedure LayoutSize(LayoutCode: Code[20]; var WidthMm: Decimal; var HeightMm: Decimal; var Dpi: Integer)
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.Get(LayoutCode);
        LayoutSizeOf(Layout, WidthMm, HeightMm, Dpi);
    end;

    /// <summary>Kitoko (21 Eki 2026): effective size of a layout record (also a temporary one built from designer JSON).</summary>
    procedure LayoutSizeOf(var Layout: Record "DOPSWHS Label Layout"; var WidthMm: Decimal; var HeightMm: Decimal; var Dpi: Integer)
    var
        Setup: Record "DOPSWHS Setup";
    begin
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
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        Layout.Get(LayoutCode);
        exit(BuildFromRecords(Layout, LayoutLine, Values, Copies, YOffsetMm));
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): ZPL of a layout held in (temporary) records, e.g. an
    /// unsaved designer JSON for preview / test print. Lines are filtered on the
    /// layout code and Enabled.
    /// </summary>
    procedure BuildZplFromRecords(var Layout: Record "DOPSWHS Label Layout"; var LayoutLine: Record "DOPSWHS Label Layout Line"; Values: Dictionary of [Text, Text]; Copies: Integer): Text
    begin
        exit(BuildFromRecords(Layout, LayoutLine, Values, Copies, 0));
    end;

    local procedure BuildFromRecords(var Layout: Record "DOPSWHS Label Layout"; var LayoutLine: Record "DOPSWHS Label Layout Line"; var Values: Dictionary of [Text, Text]; Copies: Integer; YOffsetMm: Decimal): Text
    var
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
        WidthDots: Integer;
        HeightDots: Integer;
        Zpl: Text;
    begin
        LayoutSizeOf(Layout, WidthMm, HeightMm, Dpi);
        WidthDots := MmToDots(WidthMm, Dpi);
        HeightDots := MmToDots(HeightMm, Dpi);
        Canvas.InitSize(WidthMm, HeightMm);
        Zpl := '^XA^CI28^PW' + Format(WidthDots) + '^LL' + Format(HeightDots) + '^LH0,0';
        LayoutLine.SetRange("Layout Code", Layout."Code");
        LayoutLine.SetRange(Enabled, true);
        if LayoutLine.FindSet() then
            repeat
                Zpl += BuildElement(LayoutLine, Values, Dpi, WidthDots, HeightDots, YOffsetMm);
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

    local procedure BuildElement(var LayoutLine: Record "DOPSWHS Label Layout Line"; var Values: Dictionary of [Text, Text]; Dpi: Integer; LabelWidthDots: Integer; LabelHeightDots: Integer; YOffsetMm: Decimal): Text
    var
        Value: Text;
        X: Integer;
        Y: Integer;
        W: Integer;
        H: Integer;
        Swap: Integer;
        Thickness: Integer;
        Side: Integer;
    begin
        X := MmToDots(LayoutLine."X (mm)", Dpi);
        Y := MmToDots(LayoutLine."Y (mm)" + YOffsetMm, Dpi);
        W := MmToDots(LayoutLine."Width (mm)", Dpi);
        H := MmToDots(LayoutLine."Height (mm)", Dpi);
        case LayoutLine."Element Type" of
            LayoutLine."Element Type"::Text, LayoutLine."Element Type"::Field:
                exit(BuildText(LayoutLine, ResolveValue(LayoutLine, Values), X, Y, W, Dpi, LabelWidthDots, LabelHeightDots));
            LayoutLine."Element Type"::Barcode128:
                begin
                    Value := ResolveValue(LayoutLine, Values);
                    if Value = '' then
                        exit('');
                    if W = 0 then
                        if IsSideways(LayoutLine.Rotation) then
                            W := LabelHeightDots - Y - 16
                        else
                            W := LabelWidthDots - X - 16;
                    if H = 0 then
                        H := MmToDots(10, Dpi);
                    // Kitoko (21 Eki 2026): unrotated Code128 keeps the original Label Canvas output.
                    if (LayoutLine.Rotation = 0) and (LayoutLine.Symbology = LayoutLine.Symbology::Code128) then
                        exit(Canvas.Code128(X, Y, H, Value, W, LayoutLine."Show Text"));
                    exit(BuildBarcode(LayoutLine, Value, X, Y, W, H));
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
                    // QR is never rotated (a QR scans in any orientation).
                    exit(Canvas.Qr(X, Y, Canvas.QrMagnification(Value, Side), Value));
                end;
            LayoutLine."Element Type"::Line, LayoutLine."Element Type"::Box:
                begin
                    if W = 0 then
                        W := 1;
                    if H = 0 then
                        H := 1;
                    // Kitoko (21 Eki 2026): a box turned by 90/270 occupies H x W on the label.
                    if IsSideways(LayoutLine.Rotation) then begin
                        Swap := W;
                        W := H;
                        H := Swap;
                    end;
                    Thickness := MmToDots(LayoutLine."Thickness (mm)", Dpi);
                    if (Thickness = 0) or (LayoutLine."Element Type" = LayoutLine."Element Type"::Line) then begin
                        Thickness := W;
                        if H < Thickness then
                            Thickness := H;
                    end;
                    exit('^FO' + Format(X) + ',' + Format(Y) + '^GB' + Format(W) + ',' + Format(H) + ',' + Format(Thickness) + '^FS');
                end;
            LayoutLine."Element Type"::Image:
                begin
                    // Kitoko (21 Eki 2026): the designer converts the picture to ^GFA for
                    // the element size and dpi (rotation included); BC places it as is.
                    Value := LayoutLine.GetImageGf();
                    if not IsSafeGraphic(Value) then
                        exit('');
                    exit('^FO' + Format(X) + ',' + Format(Y) + Value + '^FS');
                end;
        end;
        exit('');
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): rotated Code128, EAN-13 (^BE) and GS1-128 (^BC mode D,
    /// FNC1 + AIs in parentheses) with the printer's own interpretation line.
    /// Length (W) runs along the bars' reading direction, H is the bar height.
    /// </summary>
    local procedure BuildBarcode(var LayoutLine: Record "DOPSWHS Label Layout Line"; Value: Text; X: Integer; Y: Integer; W: Integer; H: Integer): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Orientation: Text[1];
        Human: Text[1];
        Command: Text;
        Data: Text;
        FieldData: Text;
        Modules: Integer;
        ModuleWidth: Integer;
        BarLength: Integer;
        FncCount: Integer;
    begin
        Orientation := OrientationCode(LayoutLine.Rotation);
        Human := 'N';
        if LayoutLine."Show Text" then
            Human := 'Y';
        Data := Value;
        case LayoutLine.Symbology of
            LayoutLine.Symbology::EAN13:
                begin
                    Data := DelChr(Value, '=', ' ');
                    if (DelChr(Data, '=', '0123456789') = '') and (StrLen(Data) in [12, 13]) then begin
                        // The printer adds the check digit itself: send the first 12 digits.
                        Data := CopyStr(Data, 1, 12);
                        Modules := 95;
                        Command := '^BE' + Orientation + ',' + Format(H) + ',' + Human + ',N';
                    end else begin
                        // Not EAN-13 data: print it as Code128 rather than an unreadable symbol.
                        Data := Value;
                        Modules := Code128Modules(Data);
                        Command := '^BC' + Orientation + ',' + Format(H) + ',' + Human + ',N,N,A';
                    end;
                end;
            LayoutLine.Symbology::GS1128:
                if Gs1FieldData(Value, FieldData, FncCount) then begin
                    // Mode D: starts with FNC1, strips "(" ")" and spaces from the bars and
                    // prints them in the human readable line; FNC1 separators are generated.
                    Modules := Code128Modules(DelChr(Value.Replace('>8', ''), '=', '() ')) + 11 * (FncCount + 1);
                    Command := '^BC' + Orientation + ',' + Format(H) + ',' + Human + ',N,N,D';
                end else begin
                    // A ">" cannot be encoded in mode D: print the data as plain Code128.
                    FieldData := '';
                    Modules := Code128Modules(Data);
                    Command := '^BC' + Orientation + ',' + Format(H) + ',' + Human + ',N,N,A';
                end;
            else begin
                Modules := Code128Modules(Data);
                Command := '^BC' + Orientation + ',' + Format(H) + ',' + Human + ',N,N,A';
            end;
        end;
        ModuleWidth := W * 85 div 100 div Modules;
        if ModuleWidth < 1 then
            ModuleWidth := 1;
        if ModuleWidth > 6 then
            ModuleWidth := 6;
        while (ModuleWidth > 1) and (Modules * ModuleWidth > W) do
            ModuleWidth -= 1;
        BarLength := Modules * ModuleWidth;
        if BarLength < W then
            if IsSideways(LayoutLine.Rotation) then
                Y += (W - BarLength) div 2
            else
                X += (W - BarLength) div 2;
        if FieldData = '' then
            FieldData := ZplEncoder.EncodeFieldData(Data);
        exit('^FO' + Format(X) + ',' + Format(Y) + '^BY' + Format(ModuleWidth) + Command + '^FH_^FD' + FieldData + '^FS');
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): ^FD data of a GS1-128 (^BC mode D) barcode. AIs are written
    /// in parentheses, e.g. (01)08690000012345(10)LOT1(17)271231. After an AI without a
    /// predefined length that is followed by another AI, the engine emits a raw ">8"
    /// (FNC1); user data is ^FH-escaped. The printer decodes ^FH before it reads Code 128
    /// invocation codes (labelary: "_3E8" also becomes FNC1, any other ">x" truncates
    /// the symbol in mode D), so user data may not contain ">" at all: false = print as
    /// plain Code128. A ">8" typed by the user (older contract) is dropped and regenerated.
    /// </summary>
    local procedure Gs1FieldData(Value: Text; var FieldData: Text; var FncCount: Integer): Boolean
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Rest: Text;
        Ai: Text;
        Data: Text;
        Close: Integer;
        Next: Integer;
    begin
        FieldData := '';
        FncCount := 0;
        Rest := Value.Replace('>8', '');
        if StrPos(Rest, '>') > 0 then
            exit(false);
        if CopyStr(Rest, 1, 1) <> '(' then begin
            FieldData := ZplEncoder.EncodeFieldData(Rest);
            exit(true);
        end;
        while Rest <> '' do begin
            Close := StrPos(Rest, ')');
            if Close = 0 then begin
                FieldData += ZplEncoder.EncodeFieldData(Rest);
                exit(true);
            end;
            Ai := CopyStr(Rest, 2, Close - 2);
            Rest := CopyStr(Rest, Close + 1);
            Next := StrPos(Rest, '(');
            if Next = 0 then begin
                Data := Rest;
                Rest := '';
            end else begin
                Data := CopyStr(Rest, 1, Next - 1);
                Rest := CopyStr(Rest, Next);
            end;
            FieldData += ZplEncoder.EncodeFieldData('(' + Ai + ')' + Data);
            if (Rest <> '') and not IsPredefinedLengthAi(Ai) then begin
                FieldData += '>8';
                FncCount += 1;
            end;
        end;
        exit(true);
    end;

    /// <summary>GS1 General Specifications: AIs starting with these two digits have a predefined length and need no FNC1 after them.</summary>
    local procedure IsPredefinedLengthAi(Ai: Text): Boolean
    begin
        exit(CopyStr(DelChr(Ai, '=', ' '), 1, 2) in
            ['00', '01', '02', '03', '04', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
             '31', '32', '33', '34', '35', '36', '41']);
    end;

    local procedure Code128Modules(Data: Text): Integer
    var
        Modules: Integer;
    begin
        if (Data <> '') and (DelChr(Data, '=', '0123456789') = '') then
            Modules := 11 * ((StrLen(Data) + 1) div 2 + 1) + 35
        else
            Modules := 11 * StrLen(Data) + 35;
        if Modules <= 0 then
            Modules := 35;
        exit(Modules);
    end;

    /// <summary>Kitoko (21 Eki 2026): ZPL field orientation for a clockwise rotation (N/R/I/B).</summary>
    procedure OrientationCode(Rotation: Integer): Text[1]
    begin
        case Rotation of
            90:
                exit('R');
            180:
                exit('I');
            270:
                exit('B');
        end;
        exit('N');
    end;

    local procedure IsSideways(Rotation: Integer): Boolean
    begin
        exit(Rotation in [90, 270]);
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): only a single ^GFA command may come from the designer;
    /// any other ^ or ~ would let stored data inject printer commands.
    /// </summary>
    procedure IsSafeGraphic(Value: Text): Boolean
    var
        Parts: List of [Text];
        Rest: Text;
        Header: Text;
        Index: Integer;
    begin
        if StrLen(Value) < 12 then
            exit(false);
        if CopyStr(Value, 1, 5) <> '^GFA,' then
            exit(false);
        Rest := CopyStr(Value, 6);
        if (StrPos(Rest, '^') > 0) or (StrPos(Rest, '~') > 0) then
            exit(false);
        // ^GFA,<total bytes>,<total bytes>,<bytes per row>,<data>: three numbers first.
        Header := CopyStr(Rest, 1, 40);
        Parts := Header.Split(',');
        if Parts.Count() < 4 then
            exit(false);
        for Index := 1 to 3 do
            if (Parts.Get(Index) = '') or (DelChr(Parts.Get(Index), '=', '0123456789') <> '') then
                exit(false);
        exit(true);
    end;

    local procedure BuildText(var LayoutLine: Record "DOPSWHS Label Layout Line"; Value: Text; X: Integer; Y: Integer; W: Integer; Dpi: Integer; LabelWidthDots: Integer; LabelHeightDots: Integer): Text
    var
        Lines: List of [Text];
        TextLine: Text;
        Zpl: Text;
        FontHeight: Integer;
        FontWidth: Integer;
        MinHeight: Integer;
        FitSize: Integer;
        FitWidth: Integer;
        Index: Integer;
        Pitch: Integer;
        LineX: Integer;
        LineY: Integer;
    begin
        if Value = '' then
            exit('');
        if W = 0 then
            if IsSideways(LayoutLine.Rotation) then
                W := LabelHeightDots - Y
            else
                W := LabelWidthDots - X;
        if W < 8 then
            W := 8;
        FontHeight := MmToDots(LayoutLine."Font Height (mm)", Dpi);
        if FontHeight = 0 then
            FontHeight := MmToDots(2.75, Dpi);
        FontWidth := MmToDots(LayoutLine."Font Width (mm)", Dpi);
        if FontWidth = 0 then
            FontWidth := FontHeight;
        // Kitoko (21 Eki 2026): ^A0 has no bold; bold glyphs are printed 20% wider,
        // so fitting measures against 1/1.2 of the width.
        FitWidth := W;
        if LayoutLine.Bold then
            FitWidth := W * 10 div 12;
        if LayoutLine."Fit to Width" then begin
            MinHeight := MmToDots(LayoutLine."Min Font Height (mm)", Dpi);
            if (MinHeight = 0) or (MinHeight > FontHeight) then
                MinHeight := FontHeight div 2;
            FitSize := Canvas.FitFontMeasured(Value, FitWidth, FontHeight, MinHeight);
            // Even the smallest size too wide: condense the glyphs instead of overprinting.
            FontWidth := Canvas.FitFontMeasured(Value, FitWidth, FitSize, 10);
            FontHeight := FitSize;
        end;
        if LayoutLine.Bold then
            FontWidth := Round(FontWidth * 1.2, 1);
        if LayoutLine."Max Lines" > 1 then begin
            Canvas.WrapText(Value, Canvas.MaxChars(FitWidth, FontHeight), LayoutLine."Max Lines", Lines);
            Pitch := FontHeight + 6;
            foreach TextLine in Lines do begin
                // Lines stack in the text's own "down" direction: right for 90, up for 180, left for 270.
                LineX := X;
                LineY := Y;
                case LayoutLine.Rotation of
                    90:
                        LineX := X + (Lines.Count() - 1 - Index) * Pitch;
                    180:
                        LineY := Y + (Lines.Count() - 1 - Index) * Pitch;
                    270:
                        LineX := X + Index * Pitch;
                    else
                        LineY := Y + Index * Pitch;
                end;
                Zpl += TextLineZpl(LayoutLine, LineX, LineY, FontHeight, FontWidth, W, TextLine);
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
        Zpl := '^FO' + Format(X) + ',' + Format(Y) + '^A0' + OrientationCode(LayoutLine.Rotation) + ',' + Format(FontHeight) + ',' + Format(FontWidth);
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
        EnsureLpQrLayout();
    end;

    /// <summary>
    /// Kitoko (22 Eki 2026): seeds the passive "LP-QR" layout (web gallery template
    /// "LP QR + Lot (100×50)": big QR = LP no., LP no., item, lot, SKT, quantity,
    /// bin, company, date) once per company. It is never activated here, and a
    /// deleted LP-QR is not created again (upgrade tag).
    /// </summary>
    procedure EnsureLpQrLayout()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        UpgradeTag: Codeunit "Upgrade Tag";
        LineNo: Integer;
    begin
        if UpgradeTag.HasUpgradeTag(LpQrSeedTagTxt) then
            exit;
        if not Layout.Get(LpQrCodeTok) then begin
            Layout.Init();
            Layout."Code" := LpQrCodeTok;
            Layout.Description := 'LP QR + Lot (100x50)';
            Layout."Label Kind" := Layout."Label Kind"::LP;
            Layout."Width (mm)" := 100;
            Layout."Height (mm)" := 50;
            Layout.Dpi := 203;
            Layout.Active := false;
            Layout.Insert(true);
            FillLpQrLines(LayoutLine, Layout."Code", LineNo);
        end;
        UpgradeTag.SetUpgradeTag(LpQrSeedTagTxt);
    end;

    /// <summary>
    /// The LP-QR lines; same sizes as LP_QR_LOT_ELEMENTS in
    /// web/src/labelDesigner/templates.ts (change both together).
    /// </summary>
    local procedure FillLpQrLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 2, 2, 30, 30);
        LayoutLine."Source Field" := 'LPNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Text, 2, 33, 30, 0);
        LayoutLine."Static Text" := 'QR = LP NO';
        LayoutLine."Font Height (mm)" := 2.25;
        LayoutLine.Alignment := LayoutLine.Alignment::Center;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'LocationCode', 2, 37, 30, 2.75, 2, 'DEPO: ', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'SourceDocument', 2, 41.5, 30, 2.25, 1.5, '', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'SSCC', 2, 46, 30, 2, 1.25, 'SSCC ', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'LPNo', 35, 2, 63, 9, 5, '', true);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Line, 35, 12.5, 63, 0.4);
        LayoutLine."Thickness (mm)" := 0.4;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'ItemNo', 35, 14, 63, 4, 2.5, '', true);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 35, 19, 63, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine."Max Lines" := 2;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'Lots', 35, 25.5, 63, 4, 2.5, 'LOT: ', true);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'ExpirationDate', 35, 31, 30, 3.25, 2.25, 'SKT: ', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'BinCode', 66, 31, 32, 3.25, 2.25, 'GÖZ: ', false);
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Modify();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'TotalQuantity', 35, 36, 40, 5.5, 3, 'MİKTAR: ', true);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'UoM', 76, 36, 22, 5.5, 3, '', false);
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Modify();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Line, 35, 43.5, 63, 0.3);
        LayoutLine."Thickness (mm)" := 0.3;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'Company', 35, 45.5, 40, 2.5, 1.75, '', false);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 76, 45.5, 22, 0);
        LayoutLine."Source Field" := 'Today';
        LayoutLine."Font Height (mm)" := 2.5;
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Insert();
    end;

    /// <summary>
    /// Kitoko (22 Eki 2026): creates the passive default lot layout "LOT" when no
    /// lot layout exists yet (installs seeded before the Lot kind existed).
    /// </summary>
    procedure EnsureLotLayout()
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.SetRange("Label Kind", Layout."Label Kind"::Lot);
        if not Layout.IsEmpty() then
            exit;
        if Layout.Get(DefaultCode(Enum::"DOPSWHS Label Kind"::Lot)) then
            exit;
        CreateLayout(Enum::"DOPSWHS Label Kind"::Lot);
        FillDefaultLines(DefaultCode(Enum::"DOPSWHS Label Kind"::Lot), Enum::"DOPSWHS Label Kind"::Lot);
    end;

    /// <summary>
    /// Default lot label, 80x40 mm: QR = item no. (every item scan keeps working),
    /// Code128 = lot no., item no., description, big lot no., SKT, quantity + unit,
    /// date. Same sizes as the web template "Lot etiketi (80×40)"
    /// (web/src/labelDesigner/templates.ts LOT_ELEMENTS; change both together).
    /// </summary>
    local procedure FillLotLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer)
    begin
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'ItemNo', 2, 2, 53, 4.5, 2.5, '', true);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 2, 7.5, 53, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 2.5;
        LayoutLine."Max Lines" := 2;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Text, 2, 13.75, 20, 0);
        LayoutLine."Static Text" := 'LOT';
        LayoutLine."Font Height (mm)" := 2.25;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'LotNo', 2, 16.5, 53, 6, 3, '', true);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Barcode128, 2, 23.5, 53, 8);
        LayoutLine."Source Field" := 'LotNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 57, 2, 21, 21);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'SourceDocument', 57, 24.5, 21, 2.25, 1.5, '', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'LPNo', 57, 28.5, 21, 2.25, 1.5, '', false);
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Line, 2, 33, 76, 0.3);
        LayoutLine."Thickness (mm)" := 0.3;
        LayoutLine.Insert();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'ExpirationDate', 2, 34.75, 27, 3, 2, 'SKT: ', true);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'Quantity', 30, 34.75, 16, 3, 2, '', true);
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Modify();
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'UoM', 47, 34.75, 12, 3, 1.75, '', false);
        AddLpQrField(LayoutLine, LayoutCode, LineNo, 'Today', 60, 35, 18, 2.5, 1.75, '', false);
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Modify();
    end;

    /// <summary>A "Genişliğe sığdır" field line of the LP-QR layout.</summary>
    local procedure AddLpQrField(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer; FieldKey: Text[30]; X: Decimal; Y: Decimal; W: Decimal; FontMm: Decimal; MinFontMm: Decimal; FieldPrefix: Text[30]; IsBold: Boolean)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, X, Y, W, 0);
        LayoutLine."Source Field" := FieldKey;
        LayoutLine.Prefix := FieldPrefix;
        LayoutLine."Font Height (mm)" := FontMm;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := MinFontMm;
        LayoutLine.Bold := IsBold;
        LayoutLine.Insert();
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): creates the passive default LP layout when no LP layout
    /// exists yet (installs seeded before the LP kind existed).
    /// </summary>
    procedure EnsureLpLayout()
    var
        Layout: Record "DOPSWHS Label Layout";
        Existing: Record "DOPSWHS Label Layout";
    begin
        Layout.SetRange("Label Kind", Layout."Label Kind"::LP);
        if not Layout.IsEmpty() then begin
            UpgradeLpDefaultLines(DefaultCode(Enum::"DOPSWHS Label Kind"::LP));
            exit;
        end;
        if Existing.Get(DefaultCode(Enum::"DOPSWHS Label Kind"::LP)) then
            exit;
        CreateLayout(Enum::"DOPSWHS Label Kind"::LP);
        FillDefaultLines(DefaultCode(Enum::"DOPSWHS Label Kind"::LP), Enum::"DOPSWHS Label Kind"::LP);
    end;

    /// <summary>
    /// Kitoko (21 Eki 2026): the first default LP lines (barcode = LP no., first-line
    /// quantity) become the current defaults (SSCC barcode, total quantity, "+N DİĞER
    /// SATIR") only while every line is still exactly as generated; edited layouts are kept.
    /// </summary>
    local procedure UpgradeLpDefaultLines(LayoutCode: Code[20])
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        TempOldLine: Record "DOPSWHS Label Layout Line" temporary;
        LineNo: Integer;
    begin
        if not Layout.Get(LayoutCode) then
            exit;
        if Layout."Label Kind" <> Layout."Label Kind"::LP then
            exit;
        FillLpLines(TempOldLine, LayoutCode, LineNo, 1);
        LayoutLine.SetRange("Layout Code", LayoutCode);
        if LayoutLine.Count() <> TempOldLine.Count() then
            exit;
        if LayoutLine.FindSet() then
            repeat
                if not TempOldLine.Get(LayoutLine."Layout Code", LayoutLine."Line No.") then
                    exit;
                if not SameGeneratedLine(LayoutLine, TempOldLine) then
                    exit;
            until LayoutLine.Next() = 0;
        LayoutLine.DeleteAll();
        LineNo := 0;
        FillLpLines(LayoutLine, LayoutCode, LineNo, LpDefaultVersion());
    end;

    /// <summary>Every printed property equal (the designer's Element Id is ignored).</summary>
    local procedure SameGeneratedLine(var Line: Record "DOPSWHS Label Layout Line"; var Generated: Record "DOPSWHS Label Layout Line"): Boolean
    begin
        exit(
            (Line."Element Type" = Generated."Element Type") and
            (Line."X (mm)" = Generated."X (mm)") and (Line."Y (mm)" = Generated."Y (mm)") and
            (Line."Width (mm)" = Generated."Width (mm)") and (Line."Height (mm)" = Generated."Height (mm)") and
            (Line."Font Height (mm)" = Generated."Font Height (mm)") and (Line."Font Width (mm)" = Generated."Font Width (mm)") and
            (Line."Min Font Height (mm)" = Generated."Min Font Height (mm)") and (Line.Alignment = Generated.Alignment) and
            (Line."Source Field" = Generated."Source Field") and (Line."Static Text" = Generated."Static Text") and
            (Line.Prefix = Generated.Prefix) and (Line.Suffix = Generated.Suffix) and
            (Line."Max Lines" = Generated."Max Lines") and (Line."Fit to Width" = Generated."Fit to Width") and
            (Line.Inverted = Generated.Inverted) and (Line."Show Text" = Generated."Show Text") and
            (Line."Thickness (mm)" = Generated."Thickness (mm)") and (Line.Enabled = Generated.Enabled) and
            (Line.Rotation = Generated.Rotation) and (Line.Bold = Generated.Bold) and
            (Line.Symbology = Generated.Symbology) and (Line."Image Id" = Generated."Image Id"));
    end;

    local procedure LpDefaultVersion(): Integer
    begin
        exit(2);
    end;

    /// <summary>Creates the QR-only item label option when it is missing.</summary>
    procedure EnsureItemV2Layout()
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        UpgradeTag: Codeunit "Upgrade Tag";
        LineNo: Integer;
    begin
        if Layout.Get('ETIKETV2') then begin
            // Kitoko (21 Eki 2026): the enlargement runs once per company (upgrade tag),
            // so a size chosen later in the designer or on the lines page is never undone.
            if UpgradeTag.HasUpgradeTag(EtiketV2SizeTagTxt) then
                exit;
            // Apply the requested ~30% enlargement once, while preserving any
            // later manual edits to these dimensions.
            if LayoutLine.Get('ETIKETV2', 10000) and
               (LayoutLine."Element Id" = '') and
               (LayoutLine."Element Type" = LayoutLine."Element Type"::QRCode) and
               (LayoutLine."Width (mm)" in [15, 19.5]) and
               (LayoutLine."Height (mm)" in [15, 19.5])
            then begin
                LayoutLine."Width (mm)" := 24;
                LayoutLine."Height (mm)" := 24;
                LayoutLine."X (mm)" := 45.5;
                LayoutLine.Modify(true);
            end;
            if LayoutLine.Get('ETIKETV2', 20000) and
               (LayoutLine."Element Id" = '') and
               (LayoutLine."Element Type" = LayoutLine."Element Type"::Field) and
               (LayoutLine."Source Field" = 'ItemNo') and
               (LayoutLine."Font Height (mm)" in [2.25, 2.925])
            then begin
                LayoutLine."Font Height (mm)" := 3.8;
                LayoutLine."Y (mm)" := 31.5;
                LayoutLine.Modify(true);
            end;
            UpgradeTag.SetUpgradeTag(EtiketV2SizeTagTxt);
            exit;
        end;
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
        // New lines already have the enlarged sizes.
        if not UpgradeTag.HasUpgradeTag(EtiketV2SizeTagTxt) then
            UpgradeTag.SetUpgradeTag(EtiketV2SizeTagTxt);
    end;

    /// <summary>Replaces all lines of the layout with the default design of its kind (80x40 mm; LP 4x2", 203 dpi).</summary>
    procedure ResetToDefault(LayoutCode: Code[20])
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        Layout.Get(LayoutCode);
        LayoutLine.SetRange("Layout Code", LayoutCode);
        LayoutLine.DeleteAll();
        Layout."Width (mm)" := DefaultWidthMm(Layout."Label Kind");
        Layout."Height (mm)" := DefaultHeightMm(Layout."Label Kind");
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
            Kind::LP:
                exit('LP');
            Kind::Lot:
                exit('LOT');
        end;
        exit('ZONE');
    end;

    /// <summary>Kitoko (21 Eki 2026): the built-in LP label is 4x2" (101.6 x 50.8 mm), the others 80x40 mm.</summary>
    procedure DefaultWidthMm(Kind: Enum "DOPSWHS Label Kind"): Decimal
    begin
        if Kind = Kind::LP then
            exit(101.6);
        exit(80);
    end;

    procedure DefaultHeightMm(Kind: Enum "DOPSWHS Label Kind"): Decimal
    begin
        if Kind = Kind::LP then
            exit(50.8);
        exit(40);
    end;

    local procedure CreateLayout(Kind: Enum "DOPSWHS Label Kind")
    var
        Layout: Record "DOPSWHS Label Layout";
    begin
        Layout.Init();
        Layout."Code" := DefaultCode(Kind);
        Layout."Label Kind" := Kind;
        Layout."Width (mm)" := DefaultWidthMm(Kind);
        Layout."Height (mm)" := DefaultHeightMm(Kind);
        Layout.Dpi := 203;
        case Kind of
            Kind::Item:
                Layout.Description := 'Ürün etiketi (varsayılan)';
            Kind::Bin:
                Layout.Description := 'Raf etiketi (varsayılan)';
            Kind::Zone:
                Layout.Description := 'Alan etiketi (varsayılan)';
            Kind::LP:
                Layout.Description := 'LP / palet etiketi (varsayılan)';
            Kind::Lot:
                Layout.Description := 'Lot etiketi (varsayılan)';
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
        if Kind = Kind::LP then begin
            FillLpLines(LayoutLine, LayoutCode, LineNo, LpDefaultVersion());
            exit;
        end;
        if Kind = Kind::Lot then begin
            FillLotLines(LayoutLine, LayoutCode, LineNo);
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
        // Larger QR with the item number centered directly below it.
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 45.5, 6.5, 24, 24);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 42, 31.5, 31, 0);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine."Font Height (mm)" := 3.8;
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

    /// <summary>
    /// Kitoko (21 Eki 2026): the LP Label report's 4x2" design in mm (8 dots/mm):
    /// black band with title and location / bin, large LP no., item, lot, quantity,
    /// Code128 + QR. Version 2 (current) matches the built-in label's data: the
    /// barcode is BarcodeData (SSCC, else LP no.), the quantity is TotalQuantity and
    /// "+N DİĞER SATIR" follows the lot. Version 1 = the first 1.14.3.13 lines, kept
    /// only to recognise untouched layouts (UpgradeLpDefaultLines).
    /// </summary>
    local procedure FillLpLines(var LayoutLine: Record "DOPSWHS Label Layout Line"; LayoutCode: Code[20]; var LineNo: Integer; Version: Integer)
    begin
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Box, 0, 0, 101.6, 6.5);
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Text, 3, 1.25, 55, 0);
        LayoutLine."Static Text" := 'PALET / LP ETİKETİ';
        LayoutLine."Font Height (mm)" := 4;
        LayoutLine.Inverted := true;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 58.75, 1.5, 20, 0);
        LayoutLine."Source Field" := 'LocationCode';
        LayoutLine."Font Height (mm)" := 3.25;
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
        LayoutLine.Inverted := true;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 79, 1.5, 19.75, 0);
        LayoutLine."Source Field" := 'BinCode';
        LayoutLine.Prefix := ' / ';
        LayoutLine."Font Height (mm)" := 3.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.25;
        LayoutLine.Inverted := true;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 7.75, 70, 0);
        LayoutLine."Source Field" := 'LPNo';
        LayoutLine."Font Height (mm)" := 10;
        LayoutLine."Font Width (mm)" := 9.5;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 7;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::QRCode, 75.5, 7.75, 24, 24);
        LayoutLine."Source Field" := 'LPNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 18.75, 22, 0);
        LayoutLine."Source Field" := 'ItemNo';
        LayoutLine."Font Height (mm)" := 3.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.25;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 26, 18.75, 47, 0);
        LayoutLine."Source Field" := 'Description';
        LayoutLine."Font Height (mm)" := 3.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.25;
        LayoutLine.Insert();
        if Version >= 2 then
            NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 23.25, 30, 0)
        else
            NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 23.25, 40, 0);
        LayoutLine."Source Field" := 'LotNo';
        LayoutLine.Prefix := 'LOT: ';
        LayoutLine."Font Height (mm)" := 3.25;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 2.25;
        LayoutLine.Insert();
        if Version >= 2 then begin
            // "+N DİĞER SATIR" next to the lot, as on the built-in LP label.
            NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 34, 23.25, 19, 0);
            LayoutLine."Source Field" := 'ExtraLines';
            LayoutLine."Font Height (mm)" := 3.25;
            LayoutLine."Fit to Width" := true;
            LayoutLine."Min Font Height (mm)" := 2.25;
            LayoutLine.Insert();
            NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 54, 23.25, 19, 0);
        end else
            NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 44, 23.25, 29, 0);
        LayoutLine."Source Field" := 'ExpirationDate';
        LayoutLine.Prefix := 'SKT: ';
        LayoutLine."Font Height (mm)" := 3.25;
        if Version >= 2 then begin
            LayoutLine."Fit to Width" := true;
            LayoutLine."Min Font Height (mm)" := 2.25;
        end;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 27.75, 46, 0);
        if Version >= 2 then
            LayoutLine."Source Field" := 'TotalQuantity'
        else
            LayoutLine."Source Field" := 'Quantity';
        LayoutLine.Prefix := 'MİKTAR: ';
        LayoutLine."Font Height (mm)" := 5.5;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 3.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 50, 27.75, 23, 0);
        LayoutLine."Source Field" := 'UoM';
        LayoutLine."Font Height (mm)" := 5.5;
        LayoutLine."Fit to Width" := true;
        LayoutLine."Min Font Height (mm)" := 3.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Barcode128, 3, 34.25, 70, 10.5);
        if Version >= 2 then
            LayoutLine."Source Field" := 'BarcodeData'
        else
            LayoutLine."Source Field" := 'LPNo';
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Text, 75.5, 40, 24, 0);
        LayoutLine."Static Text" := 'QR = LP NO';
        LayoutLine."Font Height (mm)" := 2.75;
        LayoutLine.Alignment := LayoutLine.Alignment::Center;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 3, 46.25, 40, 0);
        LayoutLine."Source Field" := 'Today';
        LayoutLine."Font Height (mm)" := 2.5;
        LayoutLine.Insert();
        NewLine(LayoutLine, LayoutCode, LineNo, LayoutLine."Element Type"::Field, 44, 46.25, 29, 0);
        LayoutLine."Source Field" := 'ItemCount';
        LayoutLine.Prefix := 'ÜRÜN ÇEŞİDİ: ';
        LayoutLine."Font Height (mm)" := 2.5;
        LayoutLine.Alignment := LayoutLine.Alignment::Right;
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
        // Reset + Init (not Clear) so the defaults can also be generated into a temporary record.
        LayoutLine.Reset();
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
