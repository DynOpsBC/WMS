page 72122 "DOPSWHS Svc Service Items API"
{
    // Service item (customer equipment) picker for the terminal "Yeni Servis" form (read-only).
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceItem';
    EntitySetName = 'serviceItems';
    SourceTable = "Service Item";
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
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(customerNo; Rec."Customer No.") { Caption = 'customerNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(serviceItemGroupCode; Rec."Service Item Group Code") { Caption = 'serviceItemGroupCode'; }
            }
        }
    }
}
