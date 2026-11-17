page 72121 "DOPSWHS Svc Customers API"
{
    // Customer picker for the terminal "Yeni Servis" form (read-only).
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceCustomer';
    EntitySetName = 'serviceCustomers';
    SourceTable = Customer;
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
                field(name; Rec.Name) { Caption = 'name'; }
                field(city; Rec.City) { Caption = 'city'; }
                field(phoneNo; Rec."Phone No.") { Caption = 'phoneNo'; }
                field(blocked; Rec.Blocked) { Caption = 'blocked'; }
            }
        }
    }
}
