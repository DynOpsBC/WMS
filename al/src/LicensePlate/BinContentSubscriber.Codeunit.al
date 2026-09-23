codeunit 72039 "DOPSWHS Bin Content Subscriber"
{
    Access = Public;

    procedure CalculateNestedLPQuantity(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]): Decimal
    var
        LP: Record "DOPSWHS LP Header";
        Total: Decimal;
    begin
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetRange(Status, LP.Status::Built);
        LP.SetRange("Parent LP No.", '');
        if LP.FindSet() then
            repeat
                Total += SumLeafItemLines(LP."No.", ItemNo);
            until LP.Next() = 0;
        exit(Total);
    end;

    /// <summary>
    /// Returns the active LP numbers and the quantity of the current Bin Content item that is
    /// represented by LP metadata. BC stock remains in Bin Content; these values explain which
    /// part of that stock belongs to which LP.
    /// </summary>
    procedure GetActiveLPItemInfo(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10]; var LpNos: Text[250]; var LPQuantity: Decimal)
    begin
        GetActiveLPItemInfoInternal(LocationCode, BinCode, ItemNo, VariantCode, UomCode, '', '', false, LpNos, LPQuantity);
    end;

    // Warehouse entries carry exact tracking values. Blank means untracked,
    // not every lot/serial in the bin. Bin Contents keeps its aggregate view.
    procedure GetActiveLPTrackingInfo(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; var LpNos: Text[250]; var LPQuantity: Decimal)
    begin
        GetActiveLPItemInfoInternal(LocationCode, BinCode, ItemNo, VariantCode, UomCode, LotNo, SerialNo, true, LpNos, LPQuantity);
    end;

    local procedure GetActiveLPItemInfoInternal(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; MatchTracking: Boolean; var LpNos: Text[250]; var LPQuantity: Decimal)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Separator: Text;
    begin
        Clear(LpNos);
        Clear(LPQuantity);
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LP."No.");
                FilterActiveLPItemLines(LPLine, ItemNo, VariantCode, UomCode, LotNo, SerialNo, MatchTracking);
                if LPLine.FindSet() then begin
                    Separator := '';
                    if LpNos <> '' then
                        Separator := ', ';
                    LpNos := CopyStr(LpNos + Separator + LP."No.", 1, MaxStrLen(LpNos));
                    repeat
                        LPQuantity += LPLine.Quantity;
                    until LPLine.Next() = 0;
                end;
            until LP.Next() = 0;
    end;

    // Shared by the summary and its drill-down so quantities and LP lists
    // use the same scope. Preserve the caller's LP/header selection.
    procedure FilterActiveLPItemLines(var LPLine: Record "DOPSWHS LP Line"; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; MatchTracking: Boolean)
    begin
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetRange("Unit of Measure");
        if UomCode <> '' then
            LPLine.SetRange("Unit of Measure", UomCode);
        LPLine.SetFilter(Quantity, '>0');
        LPLine.SetRange("Lot No.");
        LPLine.SetRange("Serial No.");
        if MatchTracking then begin
            LPLine.SetRange("Lot No.", LotNo);
            LPLine.SetRange("Serial No.", SerialNo);
        end;
    end;

    procedure GetLPContentSummary(LPNo: Code[20]): Text[250]
    var
        LPLine: Record "DOPSWHS LP Line";
        Summary: Text[250];
        LineText: Text;
        Separator: Text;
    begin
        LPLine.SetRange("LP No.", LPNo);
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                LineText := LPLine."Item No." + ' x ' + Format(LPLine.Quantity);
                if LPLine."Lot No." <> '' then
                    LineText += ' (Lot ' + LPLine."Lot No." + ')';
                Separator := '';
                if Summary <> '' then
                    Separator := '; ';
                Summary := CopyStr(Summary + Separator + LineText, 1, MaxStrLen(Summary));
            until (LPLine.Next() = 0) or (StrLen(Summary) = MaxStrLen(Summary));
        exit(Summary);
    end;

    local procedure SumLeafItemLines(LPNo: Code[20]; ItemNo: Code[20]): Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
        Total: Decimal;
    begin
        LPLine.SetRange("LP No.", LPNo);
        if LPLine.FindSet() then
            repeat
                if LPLine."Child LP No." <> '' then
                    Total += SumLeafItemLines(LPLine."Child LP No.", ItemNo)
                else
                    if (ItemNo = '') or (LPLine."Item No." = ItemNo) then
                        Total += LPLine.Quantity;
            until LPLine.Next() = 0;
        exit(Total);
    end;
}
