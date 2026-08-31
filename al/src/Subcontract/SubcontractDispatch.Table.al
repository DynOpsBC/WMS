table 72440 "DOPSWHS Subcontract Dispatch"
{
    Caption = 'Fason Sevk Hareketi';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; }
        field(2; "Idempotency Key"; Guid) { }
        field(10; "Prod. Order No."; Code[20]) { TableRelation = "Production Order"."No."; }
        field(11; "Prod. Order Line No."; Integer) { }
        field(12; "Component Line No."; Integer) { }
        field(13; "Routing Reference No."; Integer) { }
        field(14; "Routing No."; Code[20]) { }
        field(15; "Operation No."; Code[10]) { }
        field(20; "Item No."; Code[20]) { TableRelation = Item; }
        field(21; Quantity; Decimal) { DecimalPlaces = 0 : 5; }
        field(22; "Unit of Measure Code"; Code[10]) { }
        field(23; "LP No."; Code[20]) { TableRelation = "DOPSWHS LP Header"; }
        field(24; "Lot No."; Code[50]) { }
        field(25; "Serial No."; Code[50]) { }
        field(30; "Subcontractor No."; Code[20]) { TableRelation = Vendor; }
        field(31; "Work Center No."; Code[20]) { TableRelation = "Work Center"; }
        field(32; "From Location Code"; Code[10]) { TableRelation = Location; }
        field(33; "To Location Code"; Code[10]) { TableRelation = Location; }
        field(34; "From Bin Code"; Code[20]) { }
        field(35; "To Bin Code"; Code[20]) { }
        field(40; "Transfer Order No."; Code[20]) { }
        field(41; "Posted Transfer Shipment No."; Code[20]) { }
        field(42; Status; Code[10]) { }
        field(43; "Purchase Order No."; Code[20]) { }
        field(44; "Fason Reference No."; Code[50]) { }
        field(45; "E-Despatch Status"; Code[20]) { }
        field(46; "E-Despatch Document No."; Code[50]) { }
        field(50; "Created By"; Code[50]) { }
        field(51; "Created At"; DateTime) { }
        field(52; "Posted At"; DateTime) { }
        field(53; "LP Updated"; Boolean) { }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Idempotency; "Idempotency Key", "Entry No.") { }
        key(Component; "Prod. Order No.", "Prod. Order Line No.", "Component Line No.", Status) { }
        key(TransferOrder; "Transfer Order No.") { }
    }
}
