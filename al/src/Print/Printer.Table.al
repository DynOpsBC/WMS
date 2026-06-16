table 72287 "DOPSWHS Printer"
{
    Caption = 'DOPSWHS Printer';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Printer List";
    DrillDownPageId = "DOPSWHS Printer List";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Code';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(2; Description; Text[100])
        {
            Caption = 'Description';
            DataClassification = CustomerContent;
        }
        field(3; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location;
        }
        field(4; "Format"; Enum "DOPSWHS Print Format")
        {
            Caption = 'Format';
            DataClassification = CustomerContent;
        }
        field(5; "Printer Handle"; Text[100])
        {
            Caption = 'Printer Handle (OS Name)';
            DataClassification = CustomerContent;
            ToolTip = 'Operating-system printer name as seen by the local agent (e.g. ZDesigner-GK420t).';
        }
        field(6; Hostname; Text[100])
        {
            Caption = 'Hostname / IP';
            DataClassification = CustomerContent;
            ToolTip = 'Optional network host of the printer when direct socket 9100 is used.';
        }
        field(7; Port; Integer)
        {
            Caption = 'Port';
            DataClassification = CustomerContent;
            InitValue = 9100;
        }
        field(8; Active; Boolean)
        {
            Caption = 'Active';
            DataClassification = CustomerContent;
            InitValue = true;
        }
        field(9; "Default Copies"; Integer)
        {
            Caption = 'Default Copies';
            DataClassification = CustomerContent;
            InitValue = 1;
        }
        field(10; "Last Seen At"; DateTime)
        {
            Caption = 'Last Seen At';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(11; "Token Hash"; Text[128])
        {
            Caption = 'Token Hash';
            DataClassification = CustomerContent;
            Editable = false;
            ToolTip = 'SHA-256 hash of the agent token. The plain secret is shown only once at generation time.';
        }
        field(12; "Token Issued At"; DateTime)
        {
            Caption = 'Token Issued At';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(13; Comment; Text[250])
        {
            Caption = 'Comment';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Code") { Clustered = true; }
        key(Location; "Location Code") { }
    }

    fieldgroups
    {
        fieldgroup(DropDown; "Code", Description, "Format", "Location Code") { }
    }

    trigger OnDelete()
    var
        Map: Record "DOPSWHS Device Printer Map";
    begin
        Map.SetRange("Printer Code", "Code");
        Map.DeleteAll(true);
    end;
}
