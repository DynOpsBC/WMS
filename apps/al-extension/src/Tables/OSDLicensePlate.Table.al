table 50029003 "OSD License Plate"
{
    Caption = 'WMS License Plate';
    DataClassification = CustomerContent;
    LookupPageId = "OSD License Plates";
    DrillDownPageId = "OSD License Plates";

    fields
    {
        field(1; "No."; Code[20])
        {
            Caption = 'No.';
            NotBlank = true;
        }
        field(2; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            TableRelation = Location;
        }
        field(3; "Bin Code"; Code[20])
        {
            Caption = 'Bin Code';
            TableRelation = Bin.Code where("Location Code" = field("Location Code"));
        }
        field(4; Status; Enum "OSD License Plate Status")
        {
            Caption = 'Status';
        }
        field(5; "Parent LP No."; Code[20])
        {
            Caption = 'Parent LP No.';
            TableRelation = "OSD License Plate"."No.";
            ToolTip = 'For nested license plates (LP-on-LP). Empty for top-level pallets.';
        }
        field(6; "Container Type Code"; Code[20])
        {
            Caption = 'Container Type Code';
        }
        field(7; "Created At"; DateTime)
        {
            Caption = 'Created At';
            Editable = false;
        }
        field(8; "Created By"; Code[50])
        {
            Caption = 'Created By';
            TableRelation = "OSD Worker"."User ID";
        }
        field(9; Closed; Boolean)
        {
            Caption = 'Closed';
        }
    }

    keys
    {
        key(PK; "No.")
        {
            Clustered = true;
        }
        key(Location; "Location Code", "Bin Code") { }
    }
}
