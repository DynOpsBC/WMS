page 72114 "DOPSWHS Svc Fault Codes API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceFaultCode';
    EntitySetName = 'serviceFaultCodes';
    SourceTable = "Fault Code";
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
                field(faultAreaCode; Rec."Fault Area Code") { Caption = 'faultAreaCode'; }
                field(symptomCode; Rec."Symptom Code") { Caption = 'symptomCode'; }
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec."Description") { Caption = 'description'; }
            }
        }
    }
}
