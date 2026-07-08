table 50029000 "OSD Worker"
{
    Caption = 'WMS Worker';
    DataClassification = CustomerContent;
    LookupPageId = "OSD Workers";
    DrillDownPageId = "OSD Workers";

    fields
    {
        field(1; "User ID"; Code[50])
        {
            Caption = 'User ID';
            NotBlank = true;
        }
        field(2; "User Name"; Text[100])
        {
            Caption = 'User Name';
        }
        field(3; "Default Location Code"; Code[10])
        {
            Caption = 'Default Location Code';
            TableRelation = Location;
        }
        field(4; "Menu Code"; Code[20])
        {
            Caption = 'Menu Code';
            TableRelation = "OSD Worker Menu".Code;
        }
        field(5; Inactive; Boolean)
        {
            Caption = 'Inactive';
        }
        field(6; "Allow Pick Location Override"; Boolean)
        {
            Caption = 'Allow Pick Location Override';
        }
        field(7; "Cycle Count Supervisor"; Boolean)
        {
            Caption = 'Cycle Count Supervisor';
        }
        field(8; "Entra ID Object ID"; Guid)
        {
            Caption = 'Entra ID Object ID';
            ToolTip = 'Microsoft Entra ID object ID for SSO-mapped workers.';
        }
        field(9; "Last Sign-In"; DateTime)
        {
            Caption = 'Last Sign-In';
            Editable = false;
        }
    }

    keys
    {
        key(PK; "User ID")
        {
            Clustered = true;
        }
    }
}
