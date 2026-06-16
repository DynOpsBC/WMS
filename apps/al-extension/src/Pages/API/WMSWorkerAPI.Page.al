page 50029010 "WMS Worker API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsWorker';
    EntitySetName = 'wmsWorkers';
    SourceTable = "WMS Worker";
    DelayedInsert = true;
    ODataKeyFields = SystemId;
    Caption = 'WMS Worker API';

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Caption = 'systemId'; Editable = false; }
                field(userId; Rec."User ID") { Caption = 'userId'; }
                field(userName; Rec."User Name") { Caption = 'userName'; }
                field(defaultLocationCode; Rec."Default Location Code") { Caption = 'defaultLocationCode'; }
                field(menuCode; Rec."Menu Code") { Caption = 'menuCode'; }
                field(inactive; Rec.Inactive) { Caption = 'inactive'; }
                field(allowPickLocationOverride; Rec."Allow Pick Location Override") { Caption = 'allowPickLocationOverride'; }
                field(cycleCountSupervisor; Rec."Cycle Count Supervisor") { Caption = 'cycleCountSupervisor'; }
                field(entraObjectId; Rec."Entra ID Object ID") { Caption = 'entraObjectId'; }
                field(lastSignIn; Rec."Last Sign-In") { Caption = 'lastSignIn'; }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Caption = 'lastModifiedDateTime'; Editable = false; }
            }
        }
    }
}
