codeunit 50029012 "OSD Pick Svc"
{
    Access = Public;

    /// <summary>
    /// Register a pick line registered from the mobile device.
    /// </summary>
    procedure RegisterPick(ActivityNo: Code[20]; LineNo: Integer; ActualBin: Code[20]; QtyPicked: Decimal; LpNo: Code[20]): Boolean
    var
        Line: Record "Warehouse Activity Line";
    begin
        if not Line.Get(Line."Activity Type"::Pick, ActivityNo, LineNo) then
            exit(false);
        Line.Validate("Qty. to Handle", QtyPicked);
        if ActualBin <> '' then
            Line.Validate("Bin Code", ActualBin);
        Line.Modify(true);
        // TODO[BC-sandbox]: codeunit 7307 "Whse.-Activity-Register".
        // TODO[BC-sandbox]: if LpNo provided, decrement LP line qty in WMS License Plate Line.
        exit(true);
    end;

    /// <summary>
    /// Pallet-level pick by single LP scan (Insight Works parity).
    /// Bulk-register every line on the LP against the matching pick.
    /// </summary>
    procedure PalletPickByLP(ShipmentNo: Code[20]; LpNo: Code[20]): Boolean
    var
        LpLine: Record "OSD License Plate Line";
        Activity: Record "Warehouse Activity Line";
    begin
        LpLine.SetRange("LP No.", LpNo);
        if not LpLine.FindSet() then exit(false);
        repeat
            Activity.SetRange("Activity Type", Activity."Activity Type"::Pick);
            Activity.SetRange("Whse. Document No.", ShipmentNo);
            Activity.SetRange("Item No.", LpLine."Item No.");
            Activity.SetRange("Variant Code", LpLine."Variant Code");
            if Activity.FindFirst() then begin
                Activity.Validate("Qty. to Handle", LpLine.Quantity);
                Activity.Modify(true);
            end;
        until LpLine.Next() = 0;
        // TODO[BC-sandbox]: codeunit 7307 "Whse.-Activity-Register".
        exit(true);
    end;
}
