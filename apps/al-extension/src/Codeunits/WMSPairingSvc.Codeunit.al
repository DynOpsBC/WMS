codeunit 50125 "WMS Pairing Svc"
{
    Access = Public;

    /// <summary>
    /// Complete the device-pairing handshake. Called by the mobile app right after
    /// the admin finishes the Entra ID Device Code Flow.
    ///
    /// The mobile app supplies the device's locally-generated UUID, a human-readable
    /// name, manufacturer/model, and the default warehouse. BC binds the device to
    /// the current company + the calling user.
    /// </summary>
    procedure CompletePairing(
        DeviceId: Code[50];
        DeviceName: Text[100];
        Manufacturer: Enum "WMS Device Manufacturer";
        Model: Text[50];
        OsVersion: Text[30];
        AppVersion: Text[30];
        DefaultWarehouse: Code[10]) DeviceSystemId: Guid
    var
        Device: Record "WMS Mobile Device";
        Company: Record Company;
    begin
        if DeviceId = '' then
            Error('Device id is required to complete pairing.');

        if Device.Get(DeviceId) then begin
            if Device.Status = Device.Status::Revoked then
                Error('Device %1 has been revoked. Issue a new device id before re-pairing.', DeviceId);
        end else begin
            Device.Init();
            Device."Device ID" := DeviceId;
            Device.Insert();
        end;

        Device."Device Name" := DeviceName;
        Device.Manufacturer := Manufacturer;
        Device.Model := Model;
        Device."OS Version" := OsVersion;
        Device."App Version" := AppVersion;
        Device."Default Warehouse" := DefaultWarehouse;
        Device.Status := Device.Status::Active;
        Device."Paired At" := CurrentDateTime();
        Device."Paired By" := CopyStr(UserId(), 1, 50);
        if Company.Get(CompanyName()) then
            Device."Company Id" := Company.SystemId;
        Device."Last Seen" := CurrentDateTime();
        Device.Modify();

        DeviceSystemId := Device.SystemId;
    end;

    /// <summary>Heartbeat called periodically by the mobile app to record last-seen.</summary>
    procedure RecordHeartbeat(DeviceId: Code[50]; AppVersion: Text[30])
    var
        Device: Record "WMS Mobile Device";
    begin
        if not Device.Get(DeviceId) then exit;
        if Device.Status <> Device.Status::Active then exit;
        Device."Last Seen" := CurrentDateTime();
        if AppVersion <> '' then
            Device."App Version" := AppVersion;
        Device.Modify();
    end;

    /// <summary>Admin action: revoke a paired device. The mobile app will see this on next sync and force re-pairing.</summary>
    procedure RevokeDevice(DeviceId: Code[50]; Reason: Text[100])
    var
        Device: Record "WMS Mobile Device";
    begin
        if not Device.Get(DeviceId) then
            Error('Device %1 not found.', DeviceId);
        Device.Status := Device.Status::Revoked;
        Device."Revoked At" := CurrentDateTime();
        Device."Revoked By" := CopyStr(UserId(), 1, 50);
        Device."Revoke Reason" := Reason;
        Device.Modify();
    end;

    /// <summary>Lookup a device and verify it's still active. Called by the action dispatcher.</summary>
    procedure IsActive(DeviceId: Code[50]): Boolean
    var
        Device: Record "WMS Mobile Device";
    begin
        if not Device.Get(DeviceId) then exit(false);
        exit(Device.Status = Device.Status::Active);
    end;
}
