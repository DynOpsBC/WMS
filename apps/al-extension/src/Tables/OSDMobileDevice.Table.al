table 50029005 "OSD Mobile Device"
{
    Caption = 'WMS Mobile Device';
    DataClassification = CustomerContent;
    LookupPageId = "OSD Mobile Devices";
    DrillDownPageId = "OSD Mobile Devices";

    fields
    {
        field(1; "Device ID"; Code[50]) { Caption = 'Device ID'; NotBlank = true; }
        field(2; "Device Name"; Text[100]) { Caption = 'Device Name'; }
        field(3; Manufacturer; Enum "OSD Device Manufacturer") { Caption = 'Manufacturer'; }
        field(4; Model; Text[50]) { Caption = 'Model'; }
        field(5; "OS Version"; Text[30]) { Caption = 'OS Version'; }
        field(6; "App Version"; Text[30]) { Caption = 'App Version'; }
        field(7; "Last Seen"; DateTime) { Caption = 'Last Seen'; Editable = false; }
        field(8; "Assigned User ID"; Code[50]) { Caption = 'Assigned User ID'; TableRelation = "OSD Worker"."User ID"; }
        field(9; "Default Warehouse"; Code[10]) { Caption = 'Default Warehouse'; TableRelation = Location.Code; }
        field(10; Status; Enum "OSD Device Status")
        {
            Caption = 'Status';
            InitValue = Unpaired;
        }
        field(11; "Paired At"; DateTime) { Caption = 'Paired At'; Editable = false; }
        field(12; "Paired By"; Code[50])
        {
            Caption = 'Paired By';
            ToolTip = 'Entra ID user-principal-name of the admin who completed the device pairing.';
            Editable = false;
        }
        field(13; "Paired By Object Id"; Guid)
        {
            Caption = 'Paired By Object Id';
            Editable = false;
        }
        field(14; "Company Id"; Guid)
        {
            Caption = 'Company Id';
            Editable = false;
            ToolTip = 'BC company SystemId the device is bound to.';
        }
        field(15; "Revoked At"; DateTime) { Caption = 'Revoked At'; Editable = false; }
        field(16; "Revoked By"; Code[50]) { Caption = 'Revoked By'; Editable = false; }
        field(17; "Revoke Reason"; Text[100]) { Caption = 'Revoke Reason'; }
    }

    keys
    {
        key(PK; "Device ID") { Clustered = true; }
        key(Status; Status) { }
    }

    trigger OnInsert()
    begin
        if "Paired At" = 0DT then
            "Paired At" := CurrentDateTime();
    end;
}
