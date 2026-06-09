page 50122 "WMS Count Plan API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsCycleCountPlan';
    EntitySetName = 'wmsCycleCountPlans';
    SourceTable = "WMS Cycle Count Plan";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(planNumber; Rec."Plan No.") { }
                field(description; Rec.Description) { }
                field(locationCode; Rec."Location Code") { }
                field(zoneFilter; Rec."Zone Filter") { }
                field(binFilter; Rec."Bin Filter") { }
                field(itemFilter; Rec."Item Filter") { }
                field(scheduledFor; Rec."Scheduled For") { }
                field(requiresSupervisor; Rec."Requires Supervisor") { }
                field(recountOnVariance; Rec."Recount On Variance") { }
                field(recountTimes; Rec."Recount Times") { }
                field(status; Rec.Status) { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
