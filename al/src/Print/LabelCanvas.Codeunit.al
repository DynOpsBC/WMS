/// <summary>
/// EMU/DKÇ (16 Eyl 2026): every ZPL label (item, bin, LP designs, pallet item)
/// is laid out on a canvas whose size comes from DOPSWHS Setup "Label Width
/// (mm)" / "Label Height (mm)". The first roll at DKÇ turned out to be 80x40 mm
/// while the designs assumed 4x2" (101.6x50.8 mm): the right third and the
/// bottom of every label were cut off. Fonts, band, QR and barcode heights are
/// derived from the canvas so the same designs stay readable from 80x40 up to
/// 100x100 mm without touching the builders. 203 dpi = 8 dots per mm.
/// </summary>
codeunit 72321 "DOPSWHS Label Canvas"
{
    Access = Public;
    Permissions = tabledata "DOPSWHS Setup" = R;

    var
        Width: Integer;
        Height: Integer;
        MarginDots: Integer;
        BandDots: Integer;
        TitleSize: Integer;
        NormalSize: Integer;
        SmallSize: Integer;
        BigSize: Integer;
        ItemNoSize: Integer;
        QtySize: Integer;
        PitchDots: Integer;
        ContentLines: Integer;
        DefaultWidthMm: Decimal;
        DefaultHeightMm: Decimal;

    /// <summary>Reads the label size from Setup (default 80x40 mm) and derives the metrics.</summary>
    procedure Init()
    var
        Setup: Record "DOPSWHS Setup";
        WidthMm: Decimal;
        HeightMm: Decimal;
    begin
        DefaultWidthMm := 80;
        DefaultHeightMm := 40;
        if Setup.Get() then begin
            WidthMm := Setup."Label Width (mm)";
            HeightMm := Setup."Label Height (mm)";
        end;
        InitSize(WidthMm, HeightMm);
    end;

    /// <summary>Canvas for an explicit size; 0 or an unusable value falls back to 80x40 mm.</summary>
    procedure InitSize(WidthMm: Decimal; HeightMm: Decimal)
    begin
        if DefaultWidthMm = 0 then begin
            DefaultWidthMm := 80;
            DefaultHeightMm := 40;
        end;
        if (WidthMm < 25) or (WidthMm > 300) then
            WidthMm := DefaultWidthMm;
        if (HeightMm < 20) or (HeightMm > 400) then
            HeightMm := DefaultHeightMm;
        Width := Round(WidthMm * 8, 1);
        Height := Round(HeightMm * 8, 1);
        MarginDots := Width div 40;
        if MarginDots < 12 then
            MarginDots := 12;
        BandDots := Clamp(Height * 14 div 100, 36, 54);
        TitleSize := BandDots * 64 div 100;
        NormalSize := Clamp(Height div 14, 20, 28);
        SmallSize := NormalSize - 4;
        BigSize := Clamp(Height * 18 div 100, 44, 76);
        // DKÇ (17 Eyl 2026): "ürün no çok büyük, uzunsa sığmıyor". The item
        // number no longer uses BigSize (57 dots on 80x40); 32 dots on 80x40.
        ItemNoSize := Clamp(Height * 10 div 100, 28, 44);
        QtySize := Clamp(Height div 9, 30, 44);
        PitchDots := NormalSize + 6;
        if Height < 380 then
            ContentLines := 2
        else
            ContentLines := 3;
    end;

    local procedure EnsureInit()
    begin
        if Width = 0 then
            Init();
    end;

    // ------------------------------------------------------------------
    // Metrics
    // ------------------------------------------------------------------

    procedure LabelWidth(): Integer
    begin
        EnsureInit();
        exit(Width);
    end;

    procedure LabelHeight(): Integer
    begin
        EnsureInit();
        exit(Height);
    end;

    procedure Margin(): Integer
    begin
        EnsureInit();
        exit(MarginDots);
    end;

    procedure BandHeight(): Integer
    begin
        EnsureInit();
        exit(BandDots);
    end;

    procedure NormalFont(): Integer
    begin
        EnsureInit();
        exit(NormalSize);
    end;

    procedure SmallFont(): Integer
    begin
        EnsureInit();
        exit(SmallSize);
    end;

    procedure BigFont(): Integer
    begin
        EnsureInit();
        exit(BigSize);
    end;

    /// <summary>Preferred item number size on the item label (smaller than BigFont).</summary>
    procedure ItemNoFont(): Integer
    begin
        EnsureInit();
        exit(ItemNoSize);
    end;

    procedure QtyFont(): Integer
    begin
        EnsureInit();
        exit(QtySize);
    end;

    /// <summary>Vertical distance between two normal text lines.</summary>
    procedure Pitch(): Integer
    begin
        EnsureInit();
        exit(PitchDots);
    end;

    /// <summary>Content (inner layer) lines an LP design may list before "+N satır daha".</summary>
    procedure MaxContentLines(): Integer
    begin
        EnsureInit();
        exit(ContentLines);
    end;

    /// <summary>Bottom edge available to the text column (above the margin).</summary>
    procedure Bottom(): Integer
    begin
        EnsureInit();
        exit(Height - MarginDots);
    end;

    /// <summary>Characters of the given font that fit BoxWidth (font 0 averages 0.55 x size per glyph).</summary>
    procedure MaxChars(BoxWidth: Integer; Font: Integer): Integer
    begin
        if Font <= 0 then
            exit(0);
        exit(BoxWidth * 100 div (Font * 55));
    end;

    /// <summary>Largest font size between Minimum and Preferred at which Value fits MaxWidth.</summary>
    procedure FitFont(Value: Text; MaxWidth: Integer; Preferred: Integer; Minimum: Integer): Integer
    begin
        if StrLen(Value) = 0 then
            exit(Preferred);
        exit(Clamp(MaxWidth * 100 div (StrLen(Value) * 55), Minimum, Preferred));
    end;

    /// <summary>
    /// Printed width in dots of Value in Zebra font 0 at the given font width.
    /// Glyph advances were measured on Labelary (8 dpmm, ^A0N,100,100) on
    /// 17 Eyl 2026: digits 48, most capitals 50-61, I 28, M 76, W 82, '-' 91
    /// per 100. The flat 0.55 estimate (FitFont) under-sizes capitals such as
    /// K, M, W and made long item numbers overprint the end of the line.
    /// </summary>
    procedure MeasuredWidth(Value: Text; FontWidth: Integer): Integer
    begin
        exit(GlyphUnits(Value) * FontWidth div 100);
    end;

    /// <summary>Largest font size between Minimum and Preferred at which Value measurably fits MaxWidth.</summary>
    procedure FitFontMeasured(Value: Text; MaxWidth: Integer; Preferred: Integer; Minimum: Integer): Integer
    var
        Units: Integer;
    begin
        Units := GlyphUnits(Value);
        if Units <= 0 then
            exit(Preferred);
        exit(Clamp(MaxWidth * 100 div Units, Minimum, Preferred));
    end;

    local procedure GlyphUnits(Value: Text): Integer
    var
        Index: Integer;
        Units: Integer;
    begin
        for Index := 1 to StrLen(Value) do
            Units += GlyphUnit(CopyStr(Value, Index, 1));
        exit(Units);
    end;

    local procedure GlyphUnit(Ch: Text): Integer
    begin
        case true of
            StrPos('Iİijlıft', Ch) > 0:
                exit(28);
            StrPos(' .,/:;()!|''', Ch) > 0:
                exit(30);
            StrPos('Jacksvxyzrçş?', Ch) > 0:
                exit(46);
            StrPos('0123456789eoö*#"', Ch) > 0:
                exit(48);
            StrPos('EFLTZbdghnpquğü_', Ch) > 0:
                exit(50);
            StrPos('ABCKPSVXYÇŞ', Ch) > 0:
                exit(56);
            StrPos('DGOQRĞÖ', Ch) > 0:
                exit(59);
            StrPos('HNUÜ&', Ch) > 0:
                exit(61);
            StrPos('Mmw', Ch) > 0:
                exit(76);
            StrPos('W', Ch) > 0:
                exit(82);
            StrPos('-+%=@~', Ch) > 0:
                exit(91);
        end;
        exit(60);
    end;

    /// <summary>Word-wraps Value into at most MaxLines lines of MaxChars; the remainder is dropped.</summary>
    procedure WrapText(Value: Text; MaxChars: Integer; MaxLines: Integer; var Lines: List of [Text])
    var
        Cut: Integer;
    begin
        Clear(Lines);
        if MaxChars <= 0 then
            exit;
        Value := DelChr(Value, '<>', ' ');
        while StrPos(Value, '  ') > 0 do
            Value := Value.Replace('  ', ' ');
        while (Value <> '') and (Lines.Count() < MaxLines) do
            if StrLen(Value) <= MaxChars then begin
                Lines.Add(Value);
                Value := '';
            end else begin
                Cut := MaxChars + 1;
                while (Cut > 1) and (Value[Cut] <> ' ') do
                    Cut -= 1;
                if Cut <= MaxChars div 2 then
                    Cut := MaxChars + 1;
                Lines.Add(DelChr(CopyStr(Value, 1, Cut - 1), '>', ' '));
                Value := DelChr(CopyStr(Value, Cut), '<', ' ');
            end;
    end;

    /// <summary>Byte-mode QR module count for the data length (version 1..6, error correction L).</summary>
    procedure QrModules(Data: Text): Integer
    begin
        case true of
            StrLen(Data) <= 17:
                exit(21);
            StrLen(Data) <= 32:
                exit(25);
            StrLen(Data) <= 53:
                exit(29);
            StrLen(Data) <= 78:
                exit(33);
            StrLen(Data) <= 106:
                exit(37);
        end;
        exit(41);
    end;

    /// <summary>Largest ^BQ magnification (2..8) whose symbol stays within MaxSide dots.</summary>
    procedure QrMagnification(Data: Text; MaxSide: Integer): Integer
    begin
        exit(Clamp(MaxSide div QrModules(Data), 2, 8));
    end;

    // ------------------------------------------------------------------
    // ZPL primitives
    // ------------------------------------------------------------------

    procedure Start(): Text
    begin
        EnsureInit();
        // ^CI28 = UTF-8 so Turkish characters print correctly.
        exit('^XA^CI28^PW' + Format(Width) + '^LL' + Format(Height) + '^LH0,0');
    end;

    procedure Finish(): Text
    begin
        exit('^XZ');
    end;

    /// <summary>Black band across the top: white title on the left, optional white text right-aligned.</summary>
    procedure Band(Title: Text; RightText: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
        RightFont: Integer;
        RightWidth: Integer;
    begin
        EnsureInit();
        Zpl := '^FO0,0^GB' + Format(Width) + ',' + Format(BandDots) + ',' + Format(BandDots) + '^FS' +
            '^FO' + Format(MarginDots) + ',' + Format((BandDots - TitleSize) div 2) +
            '^A0N,' + Format(TitleSize) + ',' + Format(TitleSize) + '^FR^FH_^FD' + ZplEncoder.EncodeFieldData(Title) + '^FS';
        if RightText <> '' then begin
            RightWidth := Width - 3 * MarginDots - TextWidth(Title, TitleSize);
            RightFont := FitFont(RightText, RightWidth, TitleSize - 6, 16);
            if TextWidth(RightText, RightFont) > RightWidth then
                RightText := CopyStr(RightText, 1, MaxChars(RightWidth, RightFont));
            Zpl += '^FO' + Format(MarginDots) + ',' + Format((BandDots - RightFont) div 2 + 1) +
                '^A0N,' + Format(RightFont) + ',' + Format(RightFont) + '^FR^FH_^FB' + Format(Width - 2 * MarginDots) + ',1,0,R^FD' +
                ZplEncoder.EncodeFieldData(RightText) + '^FS';
        end;
        exit(Zpl);
    end;

    /// <summary>One line of text in font 0; nothing is emitted for an empty value.</summary>
    procedure Write(X: Integer; Y: Integer; Font: Integer; BoxWidth: Integer; Value: Text): Text
    begin
        exit(WriteSized(X, Y, Font, Font, BoxWidth, Value));
    end;

    procedure WriteSized(X: Integer; Y: Integer; FontHeight: Integer; FontWidth: Integer; BoxWidth: Integer; Value: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        if Value = '' then
            exit('');
        exit('^FO' + Format(X) + ',' + Format(Y) + '^A0N,' + Format(FontHeight) + ',' + Format(FontWidth) +
            '^FH_^FB' + Format(BoxWidth) + ',1,0,L^FD' + ZplEncoder.EncodeFieldData(Value) + '^FS');
    end;

    /// <summary>
    /// Code128 whose module width keeps the bars inside MaxWidth (automatic
    /// subset selection, so digit-only data such as an SSCC packs two digits
    /// per symbol). With Human the value is printed under the bars.
    /// </summary>
    procedure Code128(X: Integer; Y: Integer; BarHeight: Integer; Data: Text; MaxWidth: Integer; Human: Boolean): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
        Modules: Integer;
    begin
        EnsureInit();
        if IsDigits(Data) then
            Modules := 11 * ((StrLen(Data) + 1) div 2 + 1) + 35
        else
            Modules := 11 * StrLen(Data) + 35;
        Zpl := '^FO' + Format(X) + ',' + Format(Y) + '^BY' + Format(Clamp(MaxWidth div Modules, 1, 4)) +
            '^BCN,' + Format(BarHeight) + ',N,N,N,A^FH_^FD' + ZplEncoder.EncodeFieldData(Data) + '^FS';
        if Human then
            Zpl += Write(X, Y + BarHeight + 4, SmallSize, MaxWidth, Data);
        exit(Zpl);
    end;

    procedure Qr(X: Integer; Y: Integer; Magnification: Integer; Data: Text): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
    begin
        exit('^FO' + Format(X) + ',' + Format(Y) + '^BQN,2,' + Format(Magnification) + '^FH_^FDLA,' + ZplEncoder.EncodeFieldData(Data) + '^FS');
    end;

    /// <summary>
    /// Common frame of every design: ^XA header, title band, QR on the right
    /// (largest magnification that fits 30% of the width / the free height)
    /// with a caption under it. Returns the ZPL and the geometry of the text
    /// column: LeftX, ColumnWidth and the first free TopY under the band.
    /// </summary>
    procedure Frame(Title: Text; RightText: Text; QrData: Text; QrCaption: Text; var LeftX: Integer; var ColumnWidth: Integer; var TopY: Integer): Text
    var
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
        QrMax: Integer;
        Magnification: Integer;
        Side: Integer;
        QrX: Integer;
        QrY: Integer;
        CaptionY: Integer;
    begin
        EnsureInit();
        // Zebra (and Labelary) draw the QR symbol about 10 dots below the ^FO origin.
        QrMax := Width * 30 div 100;
        if QrCaption = '' then begin
            if Height - BandDots - 8 - QrOffset() - MarginDots < QrMax then
                QrMax := Height - BandDots - 8 - QrOffset() - MarginDots;
        end else
            if Height - BandDots - 8 - QrOffset() - 6 - SmallSize - MarginDots < QrMax then
                QrMax := Height - BandDots - 8 - QrOffset() - 6 - SmallSize - MarginDots;
        Magnification := QrMagnification(QrData, QrMax);
        Side := QrModules(QrData) * Magnification;
        QrX := Width - MarginDots - Side;
        QrY := BandDots + 8;
        Zpl := Start() + Band(Title, RightText) + Qr(QrX, QrY, Magnification, QrData);
        CaptionY := QrY + QrOffset() + Side + 6;
        if (QrCaption <> '') and (CaptionY + SmallSize <= Height - MarginDots) then
            Zpl += '^FO' + Format(QrX - 20) + ',' + Format(CaptionY) + '^A0N,' + Format(SmallSize) + ',' + Format(SmallSize) +
                '^FH_^FB' + Format(Side + 40) + ',1,0,C^FD' + ZplEncoder.EncodeFieldData(QrCaption) + '^FS';
        LeftX := MarginDots;
        ColumnWidth := Width - 3 * MarginDots - Side;
        TopY := BandDots + 8;
        exit(Zpl);
    end;

    /// <summary>Small line on the bottom margin of the text column (never under the QR).</summary>
    procedure FooterLine(LeftX: Integer; ColumnWidth: Integer; Value: Text): Text
    begin
        EnsureInit();
        exit(Write(LeftX, Height - MarginDots - SmallSize, SmallSize, ColumnWidth + MarginDots, Value));
    end;

    /// <summary>
    /// Bar height for a barcode starting at Top that ends above the footer
    /// line; the human-readable value (when shown) is reserved as well.
    /// </summary>
    procedure BarHeightAboveFooter(Top: Integer; Human: Boolean): Integer
    var
        Available: Integer;
    begin
        EnsureInit();
        Available := Height - MarginDots - SmallSize - 6 - Top;
        if Human then
            Available -= SmallSize + 4;
        if Available < 30 then
            exit(30);
        exit(Available);
    end;

    /// <summary>Bar height for a barcode starting at Top that ends on the bottom margin.</summary>
    procedure BarHeightToBottom(Top: Integer; Human: Boolean): Integer
    var
        Available: Integer;
    begin
        EnsureInit();
        Available := Height - MarginDots - Top;
        if Human then
            Available -= SmallSize + 4;
        if Available < 30 then
            exit(30);
        exit(Available);
    end;

    local procedure QrOffset(): Integer
    begin
        exit(10);
    end;

    local procedure TextWidth(Value: Text; Font: Integer): Integer
    begin
        exit(StrLen(Value) * Font * 55 div 100);
    end;

    local procedure IsDigits(Value: Text): Boolean
    begin
        if Value = '' then
            exit(false);
        exit(DelChr(Value, '=', '0123456789') = '');
    end;

    local procedure Clamp(Value: Integer; Minimum: Integer; Maximum: Integer): Integer
    begin
        if Value < Minimum then
            exit(Minimum);
        if Value > Maximum then
            exit(Maximum);
        exit(Value);
    end;
}
