table 50029016 "WMS Shipping Rate"
{
    Caption = 'WMS Shipping Rate';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Rate ID"; Guid) { Caption = 'Rate ID'; }
        field(2; "Shipment No."; Code[20]) { Caption = 'Shipment No.'; }
        field(3; "Carrier Code"; Code[20]) { Caption = 'Carrier Code'; TableRelation = "WMS Carrier".Code; }
        field(4; "Service Code"; Code[20]) { Caption = 'Service Code'; }
        field(5; "Service Name"; Text[100]) { Caption = 'Service Name'; }
        field(6; Amount; Decimal) { Caption = 'Amount'; }
        field(7; Currency; Code[10]) { Caption = 'Currency'; }
        field(8; "Estimated Days"; Integer) { Caption = 'Estimated Days'; }
        field(9; "Quoted At"; DateTime) { Caption = 'Quoted At'; }
        field(10; Selected; Boolean) { Caption = 'Selected'; }
    }
    keys { key(PK; "Rate ID") { Clustered = true; } key(Shipment; "Shipment No.") { } }
}
