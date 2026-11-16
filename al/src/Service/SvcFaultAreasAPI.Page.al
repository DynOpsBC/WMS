page 72112 "DOPSWHS Svc Fault Areas API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceFaultArea';
    EntitySetName = 'serviceFaultAreas';
    SourceTable = "Fault Area";
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
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec."Description") { Caption = 'description'; }
            }
        }
    }
}
