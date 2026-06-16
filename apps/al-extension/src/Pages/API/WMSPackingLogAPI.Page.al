page 50029026 "WMS Packing Log API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsPackingLog';
    EntitySetName = 'wmsPackingLogs';
    SourceTable = "WMS Packing Log";
    DelayedInsert = false;
    Editable = false;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(entryNumber; Rec."Entry No.") { }
                field(containerNumber; Rec."Container No.") { }
                field(eventType; Rec."Event Type") { }
                field(workerId; Rec."Worker ID") { }
                field(itemNumber; Rec."Item No.") { }
                field(quantity; Rec.Quantity) { }
                field(recordedAt; Rec."Recorded At") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
