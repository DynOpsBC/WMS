page 72200 "DOPSWHS Prepared Label Row API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'preparedItemLabelRow';
    EntitySetName = 'preparedItemLabelRows';
    SourceTable = "DOPSWHS Prepared Label Row";
    SourceTableView = sorting("List Code", "Line No.");
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    layout
    {
        area(Content)
        {
            repeater(Rows)
            {
                field(id; Rec.SystemId) { }
                field(listCode; Rec."List Code") { }
                field(lineNo; Rec."Line No.") { }
                field(itemNo; Rec."Item No.") { }
                field(description; Rec.Description) { }
                field(binCode; Rec."Bin Code") { }
                field(sourceDate; Rec."Source Date") { }
            }
        }
    }
}
