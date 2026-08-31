table 72449 "DOPSWHS Subcontract EDesp Out"
{
    Caption = 'Fason E-İrsaliye Kuyruğu';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; }
        field(2; "Transfer Order No."; Code[20]) { }
        field(3; "Posted Transfer Shipment No."; Code[20]) { }
        field(4; "Reference No."; Code[50]) { }
        field(5; "Prod. Order No."; Code[20]) { }
        field(6; "Purchase Order No."; Code[20]) { }
        field(7; "Operation No."; Code[10]) { }
        field(8; "Subcontractor No."; Code[20]) { }
        field(9; Status; Code[20]) { }
        field(10; "Provider Document No."; Code[50]) { }
        field(11; "Last Error"; Text[250]) { }
        field(12; "Attempt Count"; Integer) { }
        field(13; "Created At"; DateTime) { }
        field(14; "Last Attempt At"; DateTime) { }
        field(15; "Submitted At"; DateTime) { }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Shipment; "Posted Transfer Shipment No.") { Unique = true; }
        key(Reference; "Reference No.", Status) { }
    }
}
