page 72207 "DOPSWHS Project API"
{
    // Terminal: proje seçimi (Ad-Hoc Hareket). Tamamen bloke projeler listelenmez.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'wmsProject';
    EntitySetName = 'wmsProjects';
    SourceTable = Job;
    SourceTableView = where(Blocked = filter(<> All));
    ODataKeyFields = "No.";
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(billToName; Rec."Bill-to Name") { Caption = 'billToName'; }
            }
        }
    }
}
