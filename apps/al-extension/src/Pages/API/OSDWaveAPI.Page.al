page 50029021 "OSD Wave API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsWave';
    EntitySetName = 'wmsWaves';
    SourceTable = "OSD Wave";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(waveNumber; Rec."Wave No.") { }
                field(locationCode; Rec."Location Code") { }
                field(plannedRelease; Rec."Planned Release") { }
                field(releasedAt; Rec."Released At") { }
                field(status; Rec.Status) { }
                field(pickGroupMethod; Rec."Pick Group Method") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
