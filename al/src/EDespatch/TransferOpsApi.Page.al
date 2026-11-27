page 72464 "DOPSWHS Transfer Ops API"
{
    // Collection-less transfer and e-despatch operations of the handheld, bound to the Setup singleton:
    //   POST transferOps('')/Microsoft.NAV.createAndShip   { requestJson, userId, idempotencyKey }
    //   POST transferOps('')/Microsoft.NAV.resolveReceiver { fromLocationCode, fromBinCode, toLocationCode, toBinCode }
    //   POST transferOps('')/Microsoft.NAV.listReceivers   { receiverType, searchText, maxCount }
    //   POST transferOps('')/Microsoft.NAV.findByIdempotencyKey { idempotencyKey }
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'transferOp';
    EntitySetName = 'transferOps';
    SourceTable = "DOPSWHS Setup";
    ODataKeyFields = "Primary Key";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(primaryKey; Rec."Primary Key") { Caption = 'primaryKey'; }
                field(eDespatchEnabled; Rec."EDesp Integration Enabled") { Caption = 'eDespatchEnabled'; }
                field(eDespatchDefaultPrintFormat; Rec."EDesp Default Print Format") { Caption = 'eDespatchDefaultPrintFormat'; }
                field(eDespatchRequireVehicle; Rec."EDesp Require Vehicle Info") { Caption = 'eDespatchRequireVehicle'; }
                field(eDespatchPromptAfterRegister; Rec."EDesp Prompt After Register") { Caption = 'eDespatchPromptAfterRegister'; }
                field(transferUsesInTransit; Rec."Transfer Ship Use In-Transit") { Caption = 'transferUsesInTransit'; }
            }
        }
    }

    [ServiceEnabled]
    procedure createAndShip(requestJson: Text; userId: Code[50]; idempotencyKey: Guid): Text
    var
        TransferShipMgmt: Codeunit "DOPSWHS Transfer Ship Mgmt";
    begin
        exit(TransferShipMgmt.CreateAndShip(requestJson, userId, idempotencyKey));
    end;

    [ServiceEnabled]
    procedure resolveReceiver(fromLocationCode: Code[10]; fromBinCode: Code[20]; toLocationCode: Code[10]; toBinCode: Code[20]): Text
    var
        TransferShipMgmt: Codeunit "DOPSWHS Transfer Ship Mgmt";
    begin
        exit(TransferShipMgmt.ResolveReceiver(fromLocationCode, fromBinCode, toLocationCode, toBinCode));
    end;

    [ServiceEnabled]
    procedure listReceivers(receiverType: Text; searchText: Text; maxCount: Integer): Text
    var
        TransferShipMgmt: Codeunit "DOPSWHS Transfer Ship Mgmt";
    begin
        exit(TransferShipMgmt.ListReceivers(receiverType, searchText, maxCount));
    end;

    [ServiceEnabled]
    procedure findByIdempotencyKey(idempotencyKey: Guid): Text
    var
        Request: Record "DOPSWHS EDesp Request";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        if not RequestMgt.FindByIdempotencyKey(idempotencyKey, Request) then
            exit('{}');
        exit(RequestMgt.ToJsonText(Request));
    end;
}
