codeunit 50111 "WMS Putaway Svc"
{
    Access = Public;

    procedure RegisterPutawayLine(ActivityNo: Code[20]; LineNo: Integer; ActualBin: Code[20]; QtyHandled: Decimal): Boolean
    var
        ActLine: Record "Warehouse Activity Line";
    begin
        if not ActLine.Get(ActLine."Activity Type"::"Put-away", ActivityNo, LineNo) then
            exit(false);
        ActLine.Validate("Qty. to Handle", QtyHandled);
        ActLine.Validate("Bin Code", ActualBin);
        ActLine.Modify(true);
        // TODO[BC-sandbox]: invoke codeunit 7307 "Whse.-Activity-Register" on the activity header.
        exit(true);
    end;

    procedure CreatePutawayFromReceipt(ReceiptNo: Code[20]): Boolean
    begin
        // TODO[BC-sandbox]: invoke codeunit 7320 "Create Put-away" with the posted receipt header.
        exit(true);
    end;
}
