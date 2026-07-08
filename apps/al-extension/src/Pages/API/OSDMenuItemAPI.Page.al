page 50029013 "OSD Menu Item API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsMenuItem';
    EntitySetName = 'wmsMenuItems';
    SourceTable = "OSD Menu Item";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(menuCode; Rec."Menu Code") { }
                field(lineNumber; Rec."Line No.") { }
                field(description; Rec.Description) { }
                field(itemType; Rec."Item Type") { }
                field(childMenuCode; Rec."Child Menu Code") { }
                field(flowId; Rec."Flow ID") { }
                field(icon; Rec.Icon) { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
