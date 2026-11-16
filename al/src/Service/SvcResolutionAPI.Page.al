page 72115 "DOPSWHS Svc Resolution API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceResolutionCode';
    EntitySetName = 'serviceResolutionCodes';
    SourceTable = "Resolution Code";
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
