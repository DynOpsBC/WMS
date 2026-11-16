page 72116 "DOPSWHS Svc Work Types API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceWorkType';
    EntitySetName = 'serviceWorkTypes';
    SourceTable = "Work Type";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec."Description") { Caption = 'description'; }
            }
        }
    }
}
