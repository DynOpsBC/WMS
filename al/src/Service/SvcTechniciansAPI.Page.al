page 72117 "DOPSWHS Svc Technicians API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceTechnician';
    EntitySetName = 'serviceTechnicians';
    SourceTable = "DOPSWHS Service Technician";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where(Active = const(true));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(userName; Rec."User Name") { Caption = 'userName'; }
                field(resourceNo; Rec."Resource No.") { Caption = 'resourceNo'; }
                field(resourceName; Rec."Resource Name") { Caption = 'resourceName'; }
                field(vanLocationCode; Rec."Van Location Code") { Caption = 'vanLocationCode'; }
                field(dispatcher; Rec."Dispatcher") { Caption = 'dispatcher'; }
            }
        }
    }
}
