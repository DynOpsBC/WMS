codeunit 72188 "DOPSWHS Stock Pick Probe"
{
    EventSubscriberInstance = Manual;
    var
        ExpectedLot: Code[50];
        ExpectedQty: Decimal;
        Observed: Boolean;

    procedure Verify(var Pick: Codeunit "Create Pick"; Lot: Code[50]; Qty: Decimal)
    var
        FirstNo: Code[20];
        LastNo: Code[20];
    begin
        ExpectedLot := Lot;
        ExpectedQty := Qty;
        Observed := false;
        Pick.CreateWhseDocument(FirstNo, LastNo, true);
        if not Observed then
            Error('The standard pick engine produced no Take lines.');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeCreateWhseDocument', '', false, false)]
    local procedure Inspect(var TempWhseActivLine: Record "Warehouse Activity Line" temporary; WhseSource: Option; var IsHandled: Boolean; IsMovementWorksheet: Boolean; var FirstWhseDocNo: Code[20]; var LastWhseDocNo: Code[20]; CreatePickParameters: Record "Create Pick Parameters")
    var
        Lines: Record "Warehouse Activity Line" temporary;
        Total: Decimal;
        WarehouseEntry: Record "Warehouse Entry";
    begin
        Lines.Copy(TempWhseActivLine, true);
        Lines.Reset();
        Lines.SetRange("Action Type", Lines."Action Type"::Take);
        if Lines.FindSet() then repeat
            Observed := true;
            if (ExpectedLot <> '') and (Lines."Lot No." <> ExpectedLot) then
                Error('Expected Take lot %1, got %2 in bin %3.', ExpectedLot, Lines."Lot No.", Lines."Bin Code");
            if Lines."Bin Code" = '' then
                Error('The FIFO/FEFO pick has no physical source bin.');
            WarehouseEntry.SetRange("Location Code", Lines."Location Code");
            WarehouseEntry.SetRange("Bin Code", Lines."Bin Code");
            WarehouseEntry.SetRange("Item No.", Lines."Item No.");
            WarehouseEntry.SetRange("Lot No.", Lines."Lot No.");
            WarehouseEntry.CalcSums("Qty. (Base)");
            if WarehouseEntry."Qty. (Base)" < Lines."Qty. (Base)" then
                Error('The suggested source bin does not contain sufficient stock of the selected lot.');
            Total += Lines."Qty. (Base)";
        until Lines.Next() = 0;
        if Total <> ExpectedQty then
            Error('Expected %1 units in Take lines, got %2.', ExpectedQty, Total);
        IsHandled := true; // Inspect the real BC plan; never create a customer warehouse document.
    end;
}
