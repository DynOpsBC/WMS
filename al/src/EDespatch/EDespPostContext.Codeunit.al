codeunit 72459 "DOPSWHS EDesp Post Context"
{
    // Carries the handheld context (operator, idempotency key, e-despatch overrides) into the posting
    // transaction, and creates the e-despatch request in the same transaction as the posted document.
    // A retry with the same idempotency key therefore finds the request instead of posting twice.
    Access = Public;
    SingleInstance = true;
    Permissions =
        tabledata "DOPSWHS EDesp Request" = RIM,
        tabledata "Transfer Shipment Header" = RM;

    var
        ContextActive: Boolean;
        ContextIdempotencyKey: Guid;
        ContextOperatorUserId: Code[50];
        ContextOverridesJson: Text;
        ContextToBinCode: Code[20];
        ContextSetAt: DateTime;
        LastRequestEntryNo: Integer;

    procedure SetContext(IdempotencyKey: Guid; OperatorUserId: Code[50]; OverridesJson: Text; ToBinCode: Code[20])
    begin
        ContextActive := true;
        ContextSetAt := CurrentDateTime();
        ContextIdempotencyKey := IdempotencyKey;
        ContextOperatorUserId := OperatorUserId;
        ContextOverridesJson := OverridesJson;
        ContextToBinCode := ToBinCode;
        LastRequestEntryNo := 0;
    end;

    procedure ClearContext()
    begin
        ContextActive := false;
        Clear(ContextIdempotencyKey);
        ContextOperatorUserId := '';
        ContextOverridesJson := '';
        ContextToBinCode := '';
    end;

    /// <summary>
    /// The context belongs to one handheld call. A posting error skips ClearContext, so a context older than
    /// five minutes is ignored and a later Business Central posting in the same session never uses it.
    /// </summary>
    procedure IsContextActive(): Boolean
    begin
        if not ContextActive then
            exit(false);
        if CurrentDateTime() - ContextSetAt > 300000 then begin
            ClearContext();
            exit(false);
        end;
        exit(true);
    end;

    procedure GetLastRequestEntryNo(): Integer
    begin
        exit(LastRequestEntryNo);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Shipment", 'OnAfterTransferOrderPostShipment', '', false, false)]
    local procedure CreateRequestAfterTransferShipment(var TransferHeader: Record "Transfer Header"; CommitIsSuppressed: Boolean; PreviewMode: Boolean; var TransferShipmentHeader: Record "Transfer Shipment Header"; InvtPickPutaway: Boolean)
    begin
        if PreviewMode or (TransferShipmentHeader."No." = '') then
            exit;
        CreateRequest("DOPSWHS EDesp Source Type"::TransferShipment, TransferShipmentHeader."No.", TransferHeader, TransferShipmentHeader."Transfer-from Code", TransferShipmentHeader."Transfer-to Code");
        if TransferHeader."DOPSWHS Fason Reference No." <> '' then
            if LastRequestEntryNo <> 0 then begin
                // Persist the fason fields copied on insert and the first status for the subcontracting screens.
                TransferShipmentHeader."DOPSWHS E-Despatch Status" := 'PENDING';
                TransferShipmentHeader.Modify(true);
            end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Transfer", 'OnAfterTransferOrderPostTransfer', '', false, false)]
    local procedure CreateRequestAfterDirectTransfer(var TransferHeader: Record "Transfer Header"; var SuppressCommit: Boolean; var DirectTransHeader: Record "Direct Trans. Header"; InvtPickPutAway: Boolean)
    begin
        // PreviewMode is not taken here: older platform versions (BC 24) may not publish it on this event.
        // A posting preview is rolled back as a whole, so a request created during preview never persists,
        // and WMS API calls (the only callers that set the post context) never run in preview.
        if DirectTransHeader."No." = '' then
            exit;
        CreateRequest("DOPSWHS EDesp Source Type"::DirectTransfer, DirectTransHeader."No.", TransferHeader, DirectTransHeader."Transfer-from Code", DirectTransHeader."Transfer-to Code");
    end;

    local procedure CreateRequest(SourceType: Enum "DOPSWHS EDesp Source Type"; SourceNo: Code[20]; TransferHeader: Record "Transfer Header"; FromLocationCode: Code[10]; ToLocationCode: Code[10])
    var
        Request: Record "DOPSWHS EDesp Request";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        IsFason: Boolean;
    begin
        LastRequestEntryNo := 0;
        if not RequestMgt.IsEnabled() then
            exit;
        IsFason := TransferHeader."DOPSWHS Fason Reference No." <> '';
        // Transfers posted in Business Central itself are handled by the e-transformation app directly.
        if not (IsContextActive() or IsFason) then
            exit;

        RequestMgt.CreateForSource(SourceType, SourceNo, FromLocationCode, ToLocationCode, ContextOverridesJson, ContextOperatorUserId, ContextIdempotencyKey, Request);
        Request."Transfer Order No." := TransferHeader."No.";
        if ContextToBinCode <> '' then
            Request."To Bin Code" := ContextToBinCode;
        if IsFason then begin
            Request."Fason Reference No." := TransferHeader."DOPSWHS Fason Reference No.";
            Request."Fason Purchase Order No." := TransferHeader."DOPSWHS Fason Purch. Order No.";
            Request.Purpose := Request.Purpose::Subcontracting;
            Dispatch.SetRange("Transfer Order No.", TransferHeader."No.");
            if Dispatch.FindFirst() then
                if Request."Receiver Type" = Request."Receiver Type"::" " then begin
                    Request."Receiver Type" := Request."Receiver Type"::Vendor;
                    Request."Receiver No." := Dispatch."Subcontractor No.";
                    if Request."To Bin Code" = '' then
                        Request."To Bin Code" := Dispatch."To Bin Code";
                end;
        end;
        Request.Modify(true);
        LastRequestEntryNo := Request."Entry No.";

        // Fason dispatches come from the subcontracting screen; the draft is built in the background.
        if not IsContextActive() then
            RequestMgt.ScheduleDraft(Request);
    end;
}
