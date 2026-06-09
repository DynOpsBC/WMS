page 50115 "WMS Mobile Device API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsMobileDevice';
    EntitySetName = 'wmsMobileDevices';
    SourceTable = "WMS Mobile Device";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(deviceId; Rec."Device ID") { }
                field(deviceName; Rec."Device Name") { }
                field(manufacturer; Rec.Manufacturer) { }
                field(model; Rec.Model) { }
                field(osVersion; Rec."OS Version") { }
                field(appVersion; Rec."App Version") { }
                field(lastSeen; Rec."Last Seen") { }
                field(assignedUserId; Rec."Assigned User ID") { }
                field(defaultWarehouse; Rec."Default Warehouse") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
