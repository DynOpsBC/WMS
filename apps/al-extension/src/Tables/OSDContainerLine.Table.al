table 50029011 "OSD Container Line"
{
    Caption = 'WMS Container Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Container No."; Code[20]) { Caption = 'Container No.'; TableRelation = "OSD Container"."No."; NotBlank = true; }
        field(2; "Line No."; Integer) { Caption = 'Line No.'; }
        field(3; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item; }
        field(4; "Variant Code"; Code[10]) { Caption = 'Variant Code'; }
        field(5; Quantity; Decimal) { Caption = 'Quantity'; }
        field(6; "Unit of Measure Code"; Code[10]) { Caption = 'Unit of Measure Code'; }
        field(7; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(8; "Serial No."; Code[50]) { Caption = 'Serial No.'; }
        field(9; "Packed By"; Code[50]) { Caption = 'Packed By'; TableRelation = "OSD Worker"."User ID"; }
        field(10; "Packed At"; DateTime) { Caption = 'Packed At'; Editable = false; }
    }
    keys { key(PK; "Container No.", "Line No.") { Clustered = true; } }
}
