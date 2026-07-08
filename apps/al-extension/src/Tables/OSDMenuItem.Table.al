table 50029002 "OSD Menu Item"
{
    Caption = 'WMS Menu Item';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Menu Code"; Code[20])
        {
            Caption = 'Menu Code';
            TableRelation = "OSD Worker Menu".Code;
            NotBlank = true;
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
        }
        field(3; Description; Text[100])
        {
            Caption = 'Description';
        }
        field(4; "Item Type"; Enum "OSD Menu Item Type")
        {
            Caption = 'Item Type';
        }
        field(5; "Child Menu Code"; Code[20])
        {
            Caption = 'Child Menu Code';
            TableRelation = "OSD Worker Menu".Code;
        }
        field(6; "Flow ID"; Code[50])
        {
            Caption = 'Flow ID';
            ToolTip = 'Identifies the scanner flow rendered on the mobile app (e.g. PURCH-RECEIVE, WHSE-PICK, CYCLE-COUNT).';
        }
        field(7; "Icon"; Text[50])
        {
            Caption = 'Icon';
        }
    }

    keys
    {
        key(PK; "Menu Code", "Line No.")
        {
            Clustered = true;
        }
    }
}
