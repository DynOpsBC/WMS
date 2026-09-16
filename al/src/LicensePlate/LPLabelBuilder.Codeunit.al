/// <summary>
/// Template-driven ZPL label designs for license plates (EMU/DKÇ, 15 Eyl 2026).
/// One "Print label" per LP: the LP template decides the design (pallet /
/// carton / box / sack / standard), whether the inner layers (contents) are
/// listed and how many copies are printed. Every design is laid out on the
/// label canvas configured in Setup (codeunit "DOPSWHS Label Canvas", 80x40 mm
/// at DKÇ by default; 16 Eyl 2026) and carries a QR with the LP number (the
/// terminal reopens the exact record) and a Code128 with the SSCC once the LP
/// was stopped, otherwise with the LP number.
/// </summary>
codeunit 72302 "DOPSWHS LP Label Builder"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = R,
        tabledata "DOPSWHS LP Line" = R,
        tabledata "DOPSWHS LP Template" = R,
        tabledata Item = R;

    procedure BuildZpl(var LP: Record "DOPSWHS LP Header"): Text
    var
        Template: Record "DOPSWHS LP Template";
        Design: Enum "DOPSWHS LP Label Design";
    begin
        ResolveTemplate(LP, Template);
        Design := ResolveDesign(Template);
        case Design of
            Design::Pallet:
                exit(BuildPalletZpl(LP, Template));
            Design::Carton:
                exit(BuildCartonZpl(LP, Template));
            Design::Box:
                exit(BuildBoxZpl(LP, Template));
            Design::Sack:
                exit(BuildSackZpl(LP, Template));
            else
                exit(BuildStandardZpl(LP));
        end;
    end;

    /// <summary>True when the template routes the label to an RDLC report (PDF document printer).</summary>
    procedure UsesReportLayout(var LP: Record "DOPSWHS LP Header"; var ReportId: Integer): Boolean
    var
        Template: Record "DOPSWHS LP Template";
    begin
        Clear(ReportId);
        if not ResolveTemplate(LP, Template) then
            exit(false);
        if Template."Label Design" <> Template."Label Design"::Report then
            exit(false);
        ReportId := Template."Label Report ID";
        exit(ReportId <> 0);
    end;

    /// <summary>Copies configured on the LP template; at least one.</summary>
    procedure ResolveCopies(var LP: Record "DOPSWHS LP Header"): Integer
    var
        Template: Record "DOPSWHS LP Template";
    begin
        if ResolveTemplate(LP, Template) and (Template."Label Copies" > 0) then
            exit(Template."Label Copies");
        exit(1);
    end;

    procedure ResolveDesign(Template: Record "DOPSWHS LP Template"): Enum "DOPSWHS LP Label Design"
    begin
        if Template."Label Design" <> Template."Label Design"::ByContainerKind then
            exit(Template."Label Design");
        case Template."Container Kind" of
            Template."Container Kind"::Pallet:
                exit(Enum::"DOPSWHS LP Label Design"::Pallet);
            Template."Container Kind"::Carton:
                exit(Enum::"DOPSWHS LP Label Design"::Carton);
            Template."Container Kind"::Box:
                exit(Enum::"DOPSWHS LP Label Design"::Box);
            Template."Container Kind"::Sack:
                exit(Enum::"DOPSWHS LP Label Design"::Sack);
            else
                exit(Enum::"DOPSWHS LP Label Design"::Standard);
        end;
    end;

    /// <summary>Caption of the container kind for labels and packing lists ('' when unspecified).</summary>
    procedure ContainerKindCaption(LpNo: Code[20]): Text
    var
        LP: Record "DOPSWHS LP Header";
        Template: Record "DOPSWHS LP Template";
    begin
        if not LP.Get(LpNo) then
            exit('');
        if not ResolveTemplate(LP, Template) then
            exit('');
        if Template."Container Kind" = Template."Container Kind"::Unspecified then
            exit('');
        exit(Format(Template."Container Kind"));
    end;

    procedure ResolveTemplate(var LP: Record "DOPSWHS LP Header"; var Template: Record "DOPSWHS LP Template"): Boolean
    begin
        Clear(Template);
        if LP."LP Template Code" = '' then
            exit(false);
        exit(Template.Get(LP."LP Template Code"));
    end;

    // ------------------------------------------------------------------
    // Designs
    // ------------------------------------------------------------------

    /// <summary>Standard LP: number, first item, lot, quantity, Code128 (SSCC or LP), footer, QR.</summary>
    local procedure BuildStandardZpl(var LP: Record "DOPSWHS LP Header"): Text
    var
        Content: Record "DOPSWHS LP Line";
        Item: Record Item;
        Canvas: Codeunit "DOPSWHS Label Canvas";
        ItemText: Text;
        LotText: Text;
        QtyText: Text;
        Zpl: Text;
        LineCount: Integer;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
    begin
        Content.SetRange("LP No.", LP."No.");
        Content.SetFilter("Item No.", '<>%1', '');
        if Content.FindSet() then begin
            repeat
                LineCount += 1;
                if LineCount = 1 then begin
                    ItemText := Content."Item No.";
                    if Item.Get(Content."Item No.") then
                        ItemText += '  ' + Item.Description;
                    QtyText := StrSubstNo('MİKTAR: %1 %2', Content.Quantity, Content."Unit of Measure");
                    if Content."Lot No." <> '' then
                        LotText := 'LOT: ' + Content."Lot No.";
                end;
            until Content.Next() = 0;
            if LineCount > 1 then begin
                if LotText <> '' then
                    LotText += '   ';
                LotText += StrSubstNo('+%1 DİĞER SATIR', LineCount - 1);
            end;
        end else
            QtyText := 'BOŞ TAŞIYICI';

        Canvas.Init();
        Zpl := Canvas.Frame('PALET / LP ETİKETİ', PlaceText(LP), LP."No.", 'QR = LP NO', X, ColumnWidth, Y);
        NoFont := Canvas.FitFont(LP."No.", ColumnWidth, Canvas.BigFont(), 28);
        Zpl += Canvas.Write(X, Y, NoFont, ColumnWidth, LP."No.");
        Y += NoFont + 6;
        Zpl += TextLine(Canvas, X, Y, ColumnWidth, ItemText);
        Zpl += TextLine(Canvas, X, Y, ColumnWidth, LotText);
        Zpl += Canvas.Write(X, Y, Canvas.QtyFont(), ColumnWidth, CopyStr(QtyText, 1, Canvas.MaxChars(ColumnWidth, Canvas.QtyFont())));
        Y += Canvas.QtyFont() + 8;
        Zpl += Barcode(Canvas, LP, X, Y, ColumnWidth);
        Zpl += Canvas.FooterLine(X, ColumnWidth, FooterText(LP));
        exit(Zpl + Canvas.Finish());
    end;

    /// <summary>
    /// Pallet: big LP number, contents (inner layers) or a summary, totals,
    /// Code128 (SSCC once stopped, printed in clear under the bars) and QR.
    /// </summary>
    local procedure BuildPalletZpl(var LP: Record "DOPSWHS LP Header"; Template: Record "DOPSWHS LP Template"): Text
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Lines: List of [Text];
        Zpl: Text;
        TotalsText: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
    begin
        Canvas.Init();
        CollectContent(LP, Canvas.MaxContentLines(), Template."Label Includes Contents", Lines, TotalsText);
        Zpl := Canvas.Frame('PALET', PlaceText(LP), LP."No.", 'QR = LP NO', X, ColumnWidth, Y);
        NoFont := Canvas.FitFont(LP."No.", ColumnWidth, Canvas.BigFont() - 8, 28);
        Zpl += Canvas.Write(X, Y, NoFont, ColumnWidth, LP."No.");
        Y += NoFont + 6;
        Zpl += ContentLines(Canvas, X, Y, ColumnWidth, Lines);
        Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, CopyStr(TotalsText, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont())));
        Y += Canvas.Pitch();
        Zpl += Barcode(Canvas, LP, X, Y, ColumnWidth);
        Zpl += Canvas.FooterLine(X, ColumnWidth, FooterText(LP));
        exit(Zpl + Canvas.Finish());
    end;

    /// <summary>Carton: LP number, the pallet it sits on, contents/summary, Code128, QR.</summary>
    local procedure BuildCartonZpl(var LP: Record "DOPSWHS LP Header"; Template: Record "DOPSWHS LP Template"): Text
    begin
        exit(BuildInnerContainerZpl(LP, Template, 'KOLİ', 'PALET'));
    end;

    /// <summary>Box: like the carton but names the carton/pallet it belongs to.</summary>
    local procedure BuildBoxZpl(var LP: Record "DOPSWHS LP Header"; Template: Record "DOPSWHS LP Template"): Text
    begin
        exit(BuildInnerContainerZpl(LP, Template, 'KUTU', 'ÜST KAP'));
    end;

    local procedure BuildInnerContainerZpl(var LP: Record "DOPSWHS LP Header"; Template: Record "DOPSWHS LP Template"; Title: Text; ParentCaption: Text): Text
    var
        Canvas: Codeunit "DOPSWHS Label Canvas";
        Lines: List of [Text];
        Zpl: Text;
        ParentText: Text;
        TotalsText: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
    begin
        Canvas.Init();
        // Inner containers always show at least the first item: a box label
        // without its content is useless on the shelf.
        CollectContent(LP, Canvas.MaxContentLines(), true, Lines, TotalsText);
        if not Template."Label Includes Contents" then
            while Lines.Count() > 1 do
                Lines.RemoveAt(Lines.Count());
        if LP."Parent LP No." <> '' then
            ParentText := ParentCaption + ': ' + LP."Parent LP No." + ParentKindSuffix(LP."Parent LP No.")
        else
            ParentText := ParentCaption + ': —';

        Zpl := Canvas.Frame(Title, PlaceText(LP), LP."No.", 'QR = LP NO', X, ColumnWidth, Y);
        NoFont := Canvas.FitFont(LP."No.", ColumnWidth, Canvas.BigFont() - 8, 28);
        Zpl += Canvas.Write(X, Y, NoFont, ColumnWidth, LP."No.");
        Y += NoFont + 6;
        Zpl += Canvas.Write(X, Y, Canvas.NormalFont() - 2, ColumnWidth, CopyStr(ParentText, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont() - 2)));
        Y += Canvas.Pitch() - 4;
        Zpl += ContentLines(Canvas, X, Y, ColumnWidth, Lines);
        Zpl += Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, CopyStr(TotalsText, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont())));
        Y += Canvas.Pitch();
        Zpl += Barcode(Canvas, LP, X, Y, ColumnWidth);
        Zpl += Canvas.FooterLine(X, ColumnWidth, FooterText(LP));
        exit(Zpl + Canvas.Finish());
    end;

    /// <summary>Sack: one item, its lot / expiry and the net quantity in large type.</summary>
    local procedure BuildSackZpl(var LP: Record "DOPSWHS LP Header"; Template: Record "DOPSWHS LP Template"): Text
    var
        Content: Record "DOPSWHS LP Line";
        Item: Record Item;
        Canvas: Codeunit "DOPSWHS Label Canvas";
        ItemText: Text;
        LotText: Text;
        NetText: Text;
        Zpl: Text;
        X: Integer;
        ColumnWidth: Integer;
        Y: Integer;
        NoFont: Integer;
    begin
        Content.SetRange("LP No.", LP."No.");
        Content.SetFilter("Item No.", '<>%1', '');
        if Content.FindFirst() then begin
            ItemText := Content."Item No.";
            if Item.Get(Content."Item No.") then
                ItemText += '  ' + Item.Description;
            if Content."Lot No." <> '' then
                LotText := 'LOT: ' + Content."Lot No.";
            if Content."Expiration Date" <> 0D then
                LotText += '   SKT ' + Format(Content."Expiration Date", 0, '<Day,2>.<Month,2>.<Year4>');
            NetText := StrSubstNo('NET: %1 %2', Content.Quantity, Content."Unit of Measure");
            if Content.Count() > 1 then
                NetText += StrSubstNo('  (+%1 satır)', Content.Count() - 1);
        end else
            NetText := 'BOŞ ÇUVAL';

        Canvas.Init();
        Zpl := Canvas.Frame('ÇUVAL', PlaceText(LP), LP."No.", 'QR = LP NO', X, ColumnWidth, Y);
        NoFont := Canvas.FitFont(LP."No.", ColumnWidth, Canvas.BigFont() - 8, 28);
        Zpl += Canvas.Write(X, Y, NoFont, ColumnWidth, LP."No.");
        Y += NoFont + 6;
        Zpl += TextLine(Canvas, X, Y, ColumnWidth, ItemText);
        Zpl += TextLine(Canvas, X, Y, ColumnWidth, LotText);
        Zpl += Canvas.Write(X, Y, Canvas.QtyFont(), ColumnWidth, CopyStr(NetText, 1, Canvas.MaxChars(ColumnWidth, Canvas.QtyFont())));
        Y += Canvas.QtyFont() + 8;
        Zpl += Barcode(Canvas, LP, X, Y, ColumnWidth);
        Zpl += Canvas.FooterLine(X, ColumnWidth, FooterText(LP));
        exit(Zpl + Canvas.Finish());
    end;

    // ------------------------------------------------------------------
    // Layout helpers
    // ------------------------------------------------------------------

    /// <summary>Normal-font line truncated to the column; advances Y when something was written.</summary>
    local procedure TextLine(var Canvas: Codeunit "DOPSWHS Label Canvas"; X: Integer; var Y: Integer; ColumnWidth: Integer; Value: Text): Text
    var
        Zpl: Text;
    begin
        if Value = '' then
            exit('');
        Zpl := Canvas.Write(X, Y, Canvas.NormalFont(), ColumnWidth, CopyStr(Value, 1, Canvas.MaxChars(ColumnWidth, Canvas.NormalFont())));
        Y += Canvas.Pitch() - 2;
        exit(Zpl);
    end;

    /// <summary>Content lines in the small font; advances Y.</summary>
    local procedure ContentLines(var Canvas: Codeunit "DOPSWHS Label Canvas"; X: Integer; var Y: Integer; ColumnWidth: Integer; Lines: List of [Text]): Text
    var
        Zpl: Text;
        Line: Text;
    begin
        foreach Line in Lines do begin
            Zpl += Canvas.Write(X, Y, Canvas.SmallFont(), ColumnWidth, CopyStr(Line, 1, Canvas.MaxChars(ColumnWidth, Canvas.SmallFont())));
            Y += Canvas.SmallFont() + 4;
        end;
        exit(Zpl);
    end;

    /// <summary>
    /// Code128 from Y down to the footer: the SSCC once the LP was stopped
    /// (printed in clear under the bars, it appears nowhere else), otherwise
    /// the LP number without the clear text (it is already the headline).
    /// </summary>
    local procedure Barcode(var Canvas: Codeunit "DOPSWHS Label Canvas"; var LP: Record "DOPSWHS LP Header"; X: Integer; Y: Integer; ColumnWidth: Integer): Text
    var
        Human: Boolean;
    begin
        Human := LP.SSCC <> '';
        exit(Canvas.Code128(X, Y, Canvas.BarHeightAboveFooter(Y, Human), BarcodeData(LP), ColumnWidth, Human));
    end;

    // ------------------------------------------------------------------
    // Content
    // ------------------------------------------------------------------

    /// <summary>
    /// Up to MaxLines content lines: nested LPs first ("LP000045 KOLİ · 12 ADET"),
    /// then item lines ("AB.00175 · Lot A101296 · 6000 ADET"). When the label
    /// must not list contents, only the totals line is produced.
    /// </summary>
    local procedure CollectContent(var LP: Record "DOPSWHS LP Header"; MaxLines: Integer; IncludeContents: Boolean; var Lines: List of [Text]; var TotalsText: Text)
    var
        Content: Record "DOPSWHS LP Line";
        Child: Record "DOPSWHS LP Header";
        ItemCount: Integer;
        ChildCount: Integer;
        TotalQty: Decimal;
        Uom: Code[10];
        MixedUom: Boolean;
        Hidden: Integer;
        LineText: Text;
    begin
        Clear(Lines);
        Content.SetRange("LP No.", LP."No.");
        if Content.FindSet() then
            repeat
                if Content."Child LP No." <> '' then begin
                    ChildCount += 1;
                    if Child.Get(Content."Child LP No.") then begin
                        Child.CalcFields("Total Quantity");
                        LineText := Content."Child LP No." + ' ' + ContainerKindCaption(Child."No.") + ' · ' + Format(Child."Total Quantity");
                    end else
                        LineText := Content."Child LP No.";
                    if IncludeContents and (Lines.Count() < MaxLines) then
                        Lines.Add(LineText)
                    else
                        if IncludeContents then
                            Hidden += 1;
                end else
                    if Content."Item No." <> '' then begin
                        ItemCount += 1;
                        TotalQty += Content.Quantity;
                        if Uom = '' then
                            Uom := Content."Unit of Measure"
                        else
                            if Uom <> Content."Unit of Measure" then
                                MixedUom := true;
                        LineText := Content."Item No.";
                        if Content."Lot No." <> '' then
                            LineText += ' · Lot ' + Content."Lot No.";
                        if Content."Serial No." <> '' then
                            LineText += ' · SN ' + Content."Serial No.";
                        LineText += ' · ' + Format(Content.Quantity) + ' ' + Content."Unit of Measure";
                        if IncludeContents and (Lines.Count() < MaxLines) then
                            Lines.Add(LineText)
                        else
                            if IncludeContents then
                                Hidden += 1;
                    end;
            until Content.Next() = 0;
        if Hidden > 0 then
            Lines.Add(StrSubstNo('+%1 satır daha', Hidden));

        if (ItemCount = 0) and (ChildCount = 0) then
            TotalsText := 'BOŞ TAŞIYICI'
        else begin
            if ChildCount > 0 then
                TotalsText := StrSubstNo('%1 KAP', ChildCount);
            if ItemCount > 0 then begin
                if TotalsText <> '' then
                    TotalsText += ' · ';
                if MixedUom then
                    TotalsText += StrSubstNo('%1 ÜRÜN SATIRI', ItemCount)
                else
                    TotalsText += StrSubstNo('%1 ÜRÜN · %2 %3', ItemCount, TotalQty, Uom);
            end;
        end;
        if LP."Weight kg" <> 0 then
            TotalsText += StrSubstNo(' · %1 kg', LP."Weight kg");
    end;

    local procedure ParentKindSuffix(ParentLpNo: Code[20]): Text
    var
        Kind: Text;
    begin
        Kind := ContainerKindCaption(ParentLpNo);
        if Kind = '' then
            exit('');
        exit(' (' + Kind + ')');
    end;

    /// <summary>SSCC once the LP was stopped, otherwise the LP number.</summary>
    local procedure BarcodeData(var LP: Record "DOPSWHS LP Header"): Text
    begin
        if LP.SSCC <> '' then
            exit(LP.SSCC);
        exit(LP."No.");
    end;

    local procedure PlaceText(var LP: Record "DOPSWHS LP Header"): Text
    begin
        if LP."Bin Code" <> '' then
            exit(LP."Location Code" + ' / ' + LP."Bin Code");
        exit(LP."Location Code");
    end;

    local procedure FooterText(var LP: Record "DOPSWHS LP Header"): Text
    var
        Footer: Text;
    begin
        Footer := Format(LP."Built DateTime", 0, '<Day,2>.<Month,2>.<Year4> <Hours24>:<Minutes,2>');
        if LP."Weight kg" <> 0 then
            Footer += '   ' + Format(LP."Weight kg") + ' kg';
        if (LP."Length cm" <> 0) or (LP."Width cm" <> 0) or (LP."Height cm" <> 0) then
            Footer += '   ' + Format(LP."Length cm") + 'x' + Format(LP."Width cm") + 'x' + Format(LP."Height cm") + ' cm';
        if LP."Source Document No." <> '' then
            Footer += '   Belge: ' + LP."Source Document No."
        else
            if LP."Built By User" <> '' then
                Footer += '   Oluşturan: ' + LP."Built By User";
        exit(Footer);
    end;
}
