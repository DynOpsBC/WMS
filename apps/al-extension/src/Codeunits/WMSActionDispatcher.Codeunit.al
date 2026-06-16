codeunit 50029024 "WMS Action Dispatcher"
{
    Access = Public;

    /// <summary>
    /// Routes an inbound action request to the matching service codeunit, then
    /// records the outcome on the request record. This is the single entry point
    /// that turns a mobile flow submission into a Business Central transaction.
    /// </summary>
    procedure Dispatch(var Request: Record "WMS Action Request")
    var
        ReceiveSvc: Codeunit "WMS Receive Svc";
        PutawaySvc: Codeunit "WMS Putaway Svc";
        PickSvc: Codeunit "WMS Pick Svc";
        PackSvc: Codeunit "WMS Pack Svc";
        MovementSvc: Codeunit "WMS Movement Svc";
        CountSvc: Codeunit "WMS Cycle Count Svc";
        ProdSvc: Codeunit "WMS Production Svc";
        P: JsonObject;
        Ok: Boolean;
    begin
        if not P.ReadFrom(Request.Payload) then begin
            Finish(Request, false, 'Invalid JSON payload', '');
            exit;
        end;

        case Request."Flow Id" of
            'PURCH-RECEIVE':
                Ok := ReceiveSvc.ReceiveAgainstWhseReceipt(
                    GetCode(P, 'receiptNo', 20), GetInt(P, 'lineNo'), GetDec(P, 'qty'),
                    GetCode(P, 'lpNo', 20), GetCode(P, 'lotNo', 50), GetCode(P, 'serialNo', 50), GetDate(P, 'expirationDate'));
            'LP-RECEIVE':
                Ok := ReceiveSvc.ReceiveLicensePlate(
                    GetCode(P, 'lpNo', 20), GetCode(P, 'locationCode', 10), GetCode(P, 'binCode', 20), Request."Worker Id");
            'PUTAWAY':
                Ok := PutawaySvc.RegisterPutawayLine(
                    GetCode(P, 'activityNo', 20), GetInt(P, 'lineNo'), GetCode(P, 'targetBin', 20), GetDec(P, 'qty'));
            'PICK':
                Ok := PickSvc.RegisterPick(
                    GetCode(P, 'shipmentNo', 20), GetInt(P, 'lineNo'), GetCode(P, 'sourceBin', 20), GetDec(P, 'qty'), GetCode(P, 'lpNo', 20));
            'PALLET-PICK':
                Ok := PickSvc.PalletPickByLP(GetCode(P, 'shipmentNo', 20), GetCode(P, 'lpNo', 20));
            'PACK':
                Ok := PackSvc.AddLine(
                    GetCode(P, 'containerNo', 20), GetCode(P, 'itemNo', 20), GetCode(P, 'variantCode', 10),
                    GetDec(P, 'qty'), GetCode(P, 'uom', 10), GetCode(P, 'lotNo', 50), GetCode(P, 'serialNo', 50), Request."Worker Id");
            'MOVEMENT':
                Ok := MovementSvc.RegisterMovement(
                    GetCode(P, 'itemNo', 20), GetCode(P, 'variantCode', 10), GetCode(P, 'locationCode', 10),
                    GetCode(P, 'fromBin', 20), GetCode(P, 'toBin', 20), GetDec(P, 'qty'), GetCode(P, 'lpNo', 20), Request."Worker Id");
            'TRANSFER':
                Ok := MovementSvc.RegisterTransfer(
                    GetCode(P, 'fromLocation', 10), GetCode(P, 'toLocation', 10), GetCode(P, 'itemNo', 20), GetDec(P, 'qty'));
            'CYCLE-COUNT':
                Ok := CountSvc.RecordCount(
                    GetCode(P, 'planNo', 20), GetCode(P, 'itemNo', 20), GetCode(P, 'locationCode', 10),
                    GetCode(P, 'binCode', 20), GetDec(P, 'countedQty'), Request."Worker Id");
            'RAF':
                Ok := ProdSvc.ReportAsFinished(
                    GetCode(P, 'productionOrderNo', 20), GetCode(P, 'itemNo', 20), GetDec(P, 'qty'),
                    GetCode(P, 'locationCode', 10), GetCode(P, 'toBin', 20), true, Request."Worker Id");
            'PRODUCTION-PICK':
                Ok := ProdSvc.ConsumeComponents(
                    GetCode(P, 'productionOrderNo', 20), GetCode(P, 'componentItemNo', 20), GetDec(P, 'qty'),
                    GetCode(P, 'fromBin', 20), Request."Worker Id");
            'APPROVE-VARIANCE':
                Ok := CountSvc.ApproveVariance(GetCode(P, 'planNo', 20), GetInt(P, 'lineNo'), Request."Worker Id");
            else begin
                Finish(Request, false, StrSubstNo('Unknown flow %1', Request."Flow Id"), '');
                exit;
            end;
        end;

        Finish(Request, Ok, '', Request."Result Document No.");
    end;

    local procedure Finish(var Request: Record "WMS Action Request"; Ok: Boolean; ErrMsg: Text; DocNo: Code[20])
    begin
        Request."Processed At" := CurrentDateTime();
        if Ok then begin
            Request.Status := Request.Status::Succeeded;
            Request."Result Document No." := DocNo;
            Request."Result Message" := 'OK';
        end else begin
            Request.Status := Request.Status::Failed;
            if ErrMsg = '' then
                ErrMsg := 'Service returned failure';
            Request."Result Message" := CopyStr(ErrMsg, 1, 250);
        end;
    end;

    // ---- JSON helpers ------------------------------------------------------

    local procedure GetText(P: JsonObject; Key: Text): Text
    var
        Tok: JsonToken;
    begin
        if P.Get(Key, Tok) then
            if Tok.IsValue() and (not Tok.AsValue().IsNull()) then
                exit(Tok.AsValue().AsText());
        exit('');
    end;

    local procedure GetCode(P: JsonObject; Key: Text; MaxLen: Integer): Code[50]
    begin
        exit(CopyStr(UpperCase(GetText(P, Key)), 1, MaxLen));
    end;

    local procedure GetDec(P: JsonObject; Key: Text): Decimal
    var
        Tok: JsonToken;
    begin
        if P.Get(Key, Tok) then
            if Tok.IsValue() and (not Tok.AsValue().IsNull()) then
                exit(Tok.AsValue().AsDecimal());
        exit(0);
    end;

    local procedure GetInt(P: JsonObject; Key: Text): Integer
    var
        Tok: JsonToken;
    begin
        if P.Get(Key, Tok) then
            if Tok.IsValue() and (not Tok.AsValue().IsNull()) then
                exit(Tok.AsValue().AsInteger());
        exit(0);
    end;

    local procedure GetDate(P: JsonObject; Key: Text): Date
    var
        Tok: JsonToken;
        D: Date;
    begin
        if P.Get(Key, Tok) then
            if Tok.IsValue() and (not Tok.AsValue().IsNull()) then
                if Evaluate(D, Tok.AsValue().AsText(), 9) then
                    exit(D);
        exit(0D);
    end;
}
