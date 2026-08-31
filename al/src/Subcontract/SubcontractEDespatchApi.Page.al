page 72451 "DOPSWHS Subcontract EDesp API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'subcontractEDespatch';
    EntitySetName = 'subcontractEDespatches';
    SourceTable = "DOPSWHS Subcontract EDesp Out";
    ODataKeyFields = "Entry No.";
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(entryNo; Rec."Entry No.") { }
                field(transferOrderNo; Rec."Transfer Order No.") { }
                field(postedTransferShipmentNo; Rec."Posted Transfer Shipment No.") { }
                field(referenceNo; Rec."Reference No.") { }
                field(prodOrderNo; Rec."Prod. Order No.") { }
                field(purchaseOrderNo; Rec."Purchase Order No.") { }
                field(operationNo; Rec."Operation No.") { }
                field(status; Rec.Status) { }
                field(providerDocumentNo; Rec."Provider Document No.") { }
                field(lastError; Rec."Last Error") { }
                field(attemptCount; Rec."Attempt Count") { }
                field(createdAt; Rec."Created At") { }
                field(lastAttemptAt; Rec."Last Attempt At") { }
                field(submittedAt; Rec."Submitted At") { }
            }
        }
    }

    [ServiceEnabled]
    procedure retry(): Text
    var
        Mgmt: Codeunit "DOPSWHS Subcontract EDesp Mgt";
        OutboxPermission: Record "DOPSWHS Subcontract EDesp Out";
        Result: JsonObject;
        ResultText: Text;
    begin
        if not OutboxPermission.WritePermission() then
            Error('E-İrsaliye kuyruğunu yeniden gönderme yetkiniz yok.');
        Mgmt.Submit(Rec."Entry No.");
        Rec.Get(Rec."Entry No.");
        Result.Add('status', Rec.Status);
        Result.Add('providerDocumentNo', Rec."Provider Document No.");
        Result.Add('lastError', Rec."Last Error");
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;
}
