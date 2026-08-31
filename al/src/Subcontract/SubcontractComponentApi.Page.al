page 72442 "DOPSWHS Subcontract Comp API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'subcontractComponent';
    EntitySetName = 'subcontractComponents';
    SourceTable = "Prod. Order Component";
    SourceTableView = where(Status = const(Released));
    ODataKeyFields = Status, "Prod. Order No.", "Prod. Order Line No.", "Line No.";
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(status; Rec.Status) { }
                field(prodOrderNo; Rec."Prod. Order No.") { }
                field(prodOrderLineNo; Rec."Prod. Order Line No.") { }
                field(componentLineNo; Rec."Line No.") { }
                field(routingLinkCode; Rec."Routing Link Code") { }
                field(itemNo; Rec."Item No.") { }
                field(description; Rec.Description) { }
                field(requiredQuantity; Rec."Expected Quantity") { }
                field(consumptionRemainingQuantity; Rec."Remaining Quantity") { }
                field(dispatchedQuantity; DispatchedQuantity) { }
                field(remainingDispatchQuantity; RemainingDispatchQuantity) { }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { }
                field(locationCode; Rec."Location Code") { }
                field(binCode; Rec."Bin Code") { }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        DispatchedQuantity := Mgmt.GetDispatchedQuantity(Rec);
        RemainingDispatchQuantity := Mgmt.GetRemainingDispatchQuantity(Rec);
    end;

    var
        DispatchedQuantity: Decimal;
        RemainingDispatchQuantity: Decimal;
}
