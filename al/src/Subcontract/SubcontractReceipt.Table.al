table 72444 "DOPSWHS Subcontract Receipt"
{
    Caption = 'Fason Teslim Alma Hareketi';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; }
        field(2; "Idempotency Key"; Guid) { }
        field(10; "Purchase Order No."; Code[20]) { TableRelation = "Purchase Header"."No."; }
        field(11; "Purchase Line No."; Integer) { }
        field(12; "Prod. Order No."; Code[20]) { TableRelation = "Production Order"."No."; }
        field(13; "Prod. Order Line No."; Integer) { }
        field(14; "Routing Reference No."; Integer) { }
        field(15; "Routing No."; Code[20]) { }
        field(16; "Operation No."; Code[10]) { }
        field(17; "Work Center No."; Code[20]) { TableRelation = "Work Center"; }
        field(20; "Item No."; Code[20]) { TableRelation = Item; }
        field(21; Quantity; Decimal) { DecimalPlaces = 0 : 5; }
        field(22; "Unit of Measure Code"; Code[10]) { }
        field(23; "Location Code"; Code[10]) { TableRelation = Location; }
        field(24; "Bin Code"; Code[20]) { }
        field(25; "Vendor No."; Code[20]) { TableRelation = Vendor; }
        field(26; "Vendor Shipment No."; Code[35]) { }
        field(27; "Inbound Reference No."; Code[50]) { }
        field(30; "Posted Purchase Receipt No."; Code[20]) { }
        field(31; "Warehouse Receipt No."; Code[20]) { }
        field(32; "Operation Finished"; Boolean) { }
        field(33; Status; Code[20]) { }
        field(40; "Created By"; Code[50]) { }
        field(41; "Created At"; DateTime) { }
        field(42; "Posted At"; DateTime) { }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Idempotency; "Idempotency Key") { }
        key(PurchaseLine; "Purchase Order No.", "Purchase Line No.", Status) { }
        key(ProductionOperation; "Prod. Order No.", "Operation No.", Status) { }
    }
}
