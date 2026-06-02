page 72228 "DOPSWHS PutAway Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'putAwayLine';
    EntitySetName = 'putAwayLines';
    SourceTable = "Warehouse Activity Line";
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
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; Editable = false; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(qtyToHandle; Rec."Qty. to Handle") { Caption = 'qtyToHandle'; }
                field(lpNo; Rec."LP No.") { Caption = 'lpNo'; }
                field(targetLpNo; Rec."Target LP No.") { Caption = 'targetLpNo'; Editable = false; }
            }
        }
    }
    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::PutAwayLine);
        RecRef.SetTable(Rec);
    end;

}
