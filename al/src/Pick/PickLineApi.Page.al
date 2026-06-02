page 72229 "DOPSWHS Pick Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'pickLine';
    EntitySetName = 'pickLines';
    SourceTable = "Warehouse Activity Line";
    SourceTableView = where("Activity Type" = const(Pick));
    DelayedInsert = true;
    ODataKeyFields = "Activity Type", "No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(activityType; Rec."Activity Type") { Caption = 'activityType'; Editable = false; }
                field(no; Rec."No.") { Caption = 'no'; Editable = false; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; Editable = false; }
                field(actionType; Rec."Action Type") { Caption = 'actionType'; Editable = false; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; Editable = false; }
                field(description; Rec.Description) { Caption = 'description'; Editable = false; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; Editable = false; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; Editable = false; }
                field(qtyToHandle; Rec."Qty. to Handle") { Caption = 'qtyToHandle'; }
                field(qtyHandled; Rec."Qty. Handled") { Caption = 'qtyHandled'; Editable = false; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(licensePlateNo; Rec."LP No.") { Caption = 'licensePlateNo'; }
            }
        }
    }
    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::PickLine);
        RecRef.SetTable(Rec);
    end;

}
