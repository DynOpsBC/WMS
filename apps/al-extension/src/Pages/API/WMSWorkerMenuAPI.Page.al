page 50029012 "WMS Worker Menu API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsWorkerMenu';
    EntitySetName = 'wmsWorkerMenus';
    SourceTable = "WMS Worker Menu";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(code; Rec.Code) { }
                field(description; Rec.Description) { }
                field(isRoot; Rec."Is Root") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
            part(menuItems; "WMS Menu Item API")
            {
                EntityName = 'menuItem';
                EntitySetName = 'menuItems';
                SubPageLink = "Menu Code" = field(Code);
            }
        }
    }
}
