page 50029015 "OSD Mobile Device API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsMobileDevice';
    EntitySetName = 'wmsMobileDevices';
    SourceTable = "OSD Mobile Device";
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
                field(status; Rec.Status) { }
                field(pairedAt; Rec."Paired At") { }
                field(pairedBy; Rec."Paired By") { }
                field(companyId; Rec."Company Id") { }
                field(revokedAt; Rec."Revoked At") { }
                field(revokedBy; Rec."Revoked By") { }
                field(revokeReason; Rec."Revoke Reason") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }

    [ServiceEnabled]
    procedure completePairing(deviceId: Code[50]; deviceName: Text[100]; manufacturer: Enum "OSD Device Manufacturer"; model: Text[50]; osVersion: Text[30]; appVersion: Text[30]; defaultWarehouse: Code[10]): Guid
    var
        Svc: Codeunit "OSD Pairing Svc";
    begin
        exit(Svc.CompletePairing(deviceId, deviceName, manufacturer, model, osVersion, appVersion, defaultWarehouse));
    end;

    [ServiceEnabled]
    procedure recordHeartbeat(deviceId: Code[50]; appVersion: Text[30])
    var
        Svc: Codeunit "OSD Pairing Svc";
    begin
        Svc.RecordHeartbeat(deviceId, appVersion);
    end;

    [ServiceEnabled]
    procedure revokeDevice(deviceId: Code[50]; reason: Text[100])
    var
        Svc: Codeunit "OSD Pairing Svc";
    begin
        Svc.RevokeDevice(deviceId, reason);
    end;
}
