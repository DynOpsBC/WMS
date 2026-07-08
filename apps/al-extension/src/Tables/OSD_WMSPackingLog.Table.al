table 50029017 "OSD Packing Log"
{
    Caption = 'WMS Packing Log';
    DataClassification = CustomerContent;
    Description = 'Worker-ID traceability for container packing events (WMA 2025 W1 parity).';

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; AutoIncrement = true; }
        field(2; "Container No."; Code[20]) { Caption = 'Container No.'; TableRelation = "OSD Container"."No."; }
        field(3; "Event Type"; Enum "OSD Packing Event") { Caption = 'Event Type'; }
        field(4; "Worker ID"; Code[50]) { Caption = 'Worker ID'; TableRelation = "OSD Worker"."User ID"; }
        field(5; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item; }
        field(6; Quantity; Decimal) { Caption = 'Quantity'; }
        field(7; "Recorded At"; DateTime) { Caption = 'Recorded At'; Editable = false; }
    }
    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Container; "Container No.") { }
    }
}

enum 50029009 "OSD Packing Event"
{
    Extensible = true;
    value(0; ContainerCreated) { Caption = 'Container Created'; }
    value(1; ItemAdded) { Caption = 'Item Added'; }
    value(2; ItemRemoved) { Caption = 'Item Removed'; }
    value(3; ContainerClosed) { Caption = 'Container Closed'; }
    value(4; LabelPrinted) { Caption = 'Label Printed'; }
}
