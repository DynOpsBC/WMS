table 50110 "WMS Container"
{
    Caption = 'WMS Container';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; NotBlank = true; }
        field(2; "Shipment No."; Code[20]) { Caption = 'Shipment No.'; }
        field(3; "Container Type Code"; Code[20]) { Caption = 'Container Type Code'; }
        field(4; "Packing Location"; Code[20]) { Caption = 'Packing Location'; }
        field(5; Status; Enum "WMS Container Status") { Caption = 'Status'; }
        field(6; "Gross Weight"; Decimal) { Caption = 'Gross Weight'; }
        field(7; "Tare Weight"; Decimal) { Caption = 'Tare Weight'; }
        field(8; Length; Decimal) { Caption = 'Length'; }
        field(9; Width; Decimal) { Caption = 'Width'; }
        field(10; Height; Decimal) { Caption = 'Height'; }
        field(11; "Created At"; DateTime) { Caption = 'Created At'; Editable = false; }
        field(12; "Created By"; Code[50]) { Caption = 'Created By'; TableRelation = "WMS Worker"."User ID"; }
        field(13; "Closed At"; DateTime) { Caption = 'Closed At'; Editable = false; }
        field(14; "Closed By"; Code[50]) { Caption = 'Closed By'; TableRelation = "WMS Worker"."User ID"; }
        field(15; "Tracking Number"; Code[50]) { Caption = 'Tracking Number'; }
    }
    keys { key(PK; "No.") { Clustered = true; } key(Shipment; "Shipment No.") { } }
}
