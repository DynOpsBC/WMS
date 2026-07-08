table 50029014 "OSD Count Variance"
{
    Caption = 'WMS Count Variance';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Plan No."; Code[20]) { Caption = 'Plan No.'; TableRelation = "OSD Cycle Count Plan"."Plan No."; }
        field(2; "Line No."; Integer) { Caption = 'Line No.'; }
        field(3; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item; }
        field(4; "Variant Code"; Code[10]) { Caption = 'Variant Code'; }
        field(5; "Location Code"; Code[10]) { Caption = 'Location Code'; TableRelation = Location; }
        field(6; "Bin Code"; Code[20]) { Caption = 'Bin Code'; }
        field(7; "System Quantity"; Decimal) { Caption = 'System Quantity'; }
        field(8; "Counted Quantity"; Decimal) { Caption = 'Counted Quantity'; }
        field(9; Variance; Decimal) { Caption = 'Variance'; }
        field(10; "Counted By"; Code[50]) { Caption = 'Counted By'; TableRelation = "OSD Worker"."User ID"; }
        field(11; "Counted At"; DateTime) { Caption = 'Counted At'; Editable = false; }
        field(12; "Approved By"; Code[50]) { Caption = 'Approved By'; TableRelation = "OSD Worker"."User ID"; }
        field(13; "Approved At"; DateTime) { Caption = 'Approved At'; Editable = false; }
        field(14; "Recount No."; Integer) { Caption = 'Recount No.'; }
    }
    keys { key(PK; "Plan No.", "Line No.") { Clustered = true; } }
}
