page 72465 "DOPSWHS Invt. Movement API"
{
    // Inventory movements (locations without directed put-away and pick) for the handheld.
    //   POST inventoryMovements('{no}')/Microsoft.NAV.assignTo { userId }
    //   POST inventoryMovements('{no}')/Microsoft.NAV.confirmLine { lineNo, qtyToHandle, userId }
    //   POST inventoryMovements('{no}')/Microsoft.NAV.registerWithDespatch { userId, overridesJson, idempotencyKey }
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'inventoryMovement';
    EntitySetName = 'inventoryMovements';
    SourceTable = "Warehouse Activity Header";
    SourceTableView = where(Type = const("Invt. Movement"));
    ODataKeyFields = "No.";
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
                field(no; Rec."No.") { Caption = 'no'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(assignedUserId; Rec."Assigned User ID") { Caption = 'assignedUserId'; }
                field(sourceDocument; Rec."Source Document") { Caption = 'sourceDocument'; }
                field(sourceNo; Rec."Source No.") { Caption = 'sourceNo'; }
                field(destinationType; Rec."Destination Type") { Caption = 'destinationType'; }
                field(destinationNo; Rec."Destination No.") { Caption = 'destinationNo'; }
                field(postingDate; Rec."Posting Date") { Caption = 'postingDate'; }
                field(type; Rec.Type) { Caption = 'type'; }
            }
        }
    }

    [ServiceEnabled]
    procedure assignTo(userId: Code[50])
    var
        EDespMovementMgmt: Codeunit "DOPSWHS EDesp Movement Mgmt";
    begin
        EDespMovementMgmt.ClaimInvtMovement(Rec, userId);
    end;

    [ServiceEnabled]
    procedure confirmLine(lineNo: Integer; qtyToHandle: Decimal; userId: Code[50])
    var
        EDespMovementMgmt: Codeunit "DOPSWHS EDesp Movement Mgmt";
    begin
        EDespMovementMgmt.ConfirmInvtMovementLine(Rec."No.", lineNo, qtyToHandle, userId);
    end;

    [ServiceEnabled]
    procedure registerWithDespatch(userId: Code[50]; overridesJson: Text; idempotencyKey: Guid): Text
    var
        EDespMovementMgmt: Codeunit "DOPSWHS EDesp Movement Mgmt";
    begin
        exit(EDespMovementMgmt.RegisterWithDespatch(Rec.Type, Rec."No.", userId, overridesJson, idempotencyKey));
    end;
}
