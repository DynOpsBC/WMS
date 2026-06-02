page 72091 "DOPSWHS PutAway API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'putAway';
    EntitySetName = 'putAways';
    SourceTable = "Warehouse Activity Header";
    SourceTableView = where(Type = const("Put-away"));
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
                part(lines; "DOPSWHS PutAway Line API")
                {
                    Caption = 'lines';
                    EntityName = 'putAwayLine';
                    EntitySetName = 'putAwayLines';
                    SubPageLink = "Activity Type" = field(Type), "No." = field("No.");
                }
            }
        }
    }

    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::PutAway);
        RecRef.SetTable(Rec);
    end;

    [ServiceEnabled]
    procedure suggestBin(itemNo: Code[20]; qty: Decimal; locationCode: Code[10]): Code[20]
    var
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
        Item: Record Item;
        EffectiveLocationCode: Code[10];
        BinCode: Code[20];
        Reason: Text;
    begin
        Item.Get(itemNo);
        EffectiveLocationCode := locationCode;
        if EffectiveLocationCode = '' then
            EffectiveLocationCode := Rec."Location Code";
        if not DirectedPutAway.SuggestBin(Item, qty, EffectiveLocationCode, BinCode, Reason) then
            Error(Reason);
        exit(BinCode);
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
