page 72220 "DOPSWHS Movement API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
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

    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::Movement);
        RecRef.SetTable(Rec);
    end;

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

    // Paylaşımlı BC lisansı: belge, oturumdaki WMS kullanıcısına atanır
    // (pick'teki reassign deseninin movement karşılığı).
    [ServiceEnabled]
    procedure assignTo(userId: Code[50])
    begin
        Rec.Validate("Assigned User ID", userId);
        Rec.Modify(true);
    end;

    var
        StatusText: Text[30];
}
