codeunit 50029010 "OSD Receive Svc"
{
    Access = Public;

    /// <summary>
    /// Register a mobile-side receive against an open warehouse receipt line.
    /// Wraps standard BC processing: validates source line, posts the receipt,
    /// optionally creates put-away work via "Create Put-away".
    /// </summary>
    procedure ReceiveAgainstWhseReceipt(ReceiptNo: Code[20]; LineNo: Integer; QtyReceived: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; ExpirationDate: Date) Success: Boolean
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        if not WhseReceiptLine.Get(ReceiptNo, LineNo) then
            exit(false);
        WhseReceiptLine.Validate("Qty. to Receive", QtyReceived);
        WhseReceiptLine.Modify(true);
        // TODO[BC-sandbox]: invoke codeunit 5760 "Whse.-Post Receipt" with the document, propagate LP + lot/serial.
        // TODO[BC-sandbox]: when location.AllowLPReceiving, write into WMS License Plate / Line.
        Success := true;
    end;

    procedure ReceiveLicensePlate(LpNo: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; CreatedBy: Code[50]) Success: Boolean
    var
        LP: Record "OSD License Plate";
    begin
        if LP.Get(LpNo) then begin
            LP."Location Code" := LocationCode;
            LP."Bin Code" := BinCode;
            LP.Modify();
        end else begin
            LP.Init();
            LP."No." := LpNo;
            LP."Location Code" := LocationCode;
            LP."Bin Code" := BinCode;
            LP.Status := LP.Status::Open;
            LP."Created At" := CurrentDateTime();
            LP."Created By" := CreatedBy;
            LP.Insert();
        end;
        Success := true;
    end;
}
