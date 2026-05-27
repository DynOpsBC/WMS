page 72220 "DOPSWHS Movement API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'movement';
    EntitySetName = 'movements';
    SourceTable = "Warehouse Activity Header";
    SourceTableView = where(Type = const(Movement));
    DelayedInsert = true;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(assignedUserId; Rec."Assigned User ID") { Caption = 'assignedUserId'; }
                // TODO Sprint H+ post-deploy: bind to activity status if exposed by the target BC app.
                field(status; StatusText) { Caption = 'status'; }
                field(type; Rec.Type) { Caption = 'type'; }
            }
        }
    }

    [ServiceEnabled]
    procedure adHoc(fromBin: Code[20]; toBin: Code[20]; itemNo: Code[20]; lpNo: Code[20]; qty: Decimal; userId: Code[50])
    var
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
    begin
        MovementMgmt.AdHocMove(fromBin, toBin, itemNo, lpNo, qty, userId);
    end;

    [ServiceEnabled]
    procedure register()
    var
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
    begin
        MovementMgmt.RegisterDirected(Rec);
    end;

    var
        StatusText: Text[30];
}
