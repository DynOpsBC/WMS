/// <summary>
/// Flattened pallet → carton → box → item rows for the packing list report.
/// Level 1 = root container, 2 = nested container, 3 = item line.
/// </summary>
table 72316 "DOPSWHS Packing List Buffer"
{
    Caption = 'Packing List Buffer';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; DataClassification = SystemMetadata; }
        field(2; Level; Integer) { Caption = 'Level'; DataClassification = SystemMetadata; }
        field(3; "Root LP No."; Code[20]) { Caption = 'Root LP No.'; DataClassification = SystemMetadata; }
        field(4; "Root SSCC"; Code[18]) { Caption = 'Root SSCC'; DataClassification = SystemMetadata; }
        field(5; "Root Kind"; Text[30]) { Caption = 'Root Kind'; DataClassification = SystemMetadata; }
        field(6; "Root Net Weight kg"; Decimal) { Caption = 'Root Net Weight kg'; DataClassification = SystemMetadata; }
        field(7; "Root Gross Weight kg"; Decimal) { Caption = 'Root Gross Weight kg'; DataClassification = SystemMetadata; }
        field(8; "Root Container Count"; Integer) { Caption = 'Root Container Count'; DataClassification = SystemMetadata; }
        field(10; "Child LP No."; Code[20]) { Caption = 'Child LP No.'; DataClassification = SystemMetadata; }
        field(11; "Child SSCC"; Code[18]) { Caption = 'Child SSCC'; DataClassification = SystemMetadata; }
        field(12; "Child Kind"; Text[30]) { Caption = 'Child Kind'; DataClassification = SystemMetadata; }
        field(13; "Child Net Weight kg"; Decimal) { Caption = 'Child Net Weight kg'; DataClassification = SystemMetadata; }
        field(14; "Child Gross Weight kg"; Decimal) { Caption = 'Child Gross Weight kg'; DataClassification = SystemMetadata; }
        field(15; "Child Depth"; Integer) { Caption = 'Child Depth'; DataClassification = SystemMetadata; }
        field(20; "Item No."; Code[20]) { Caption = 'Item No.'; DataClassification = SystemMetadata; }
        field(21; Description; Text[100]) { Caption = 'Description'; DataClassification = SystemMetadata; }
        field(22; "Variant Code"; Code[10]) { Caption = 'Variant Code'; DataClassification = SystemMetadata; }
        field(23; "Lot No."; Code[50]) { Caption = 'Lot No.'; DataClassification = SystemMetadata; }
        field(24; "Serial No."; Code[50]) { Caption = 'Serial No.'; DataClassification = SystemMetadata; }
        field(25; Quantity; Decimal) { Caption = 'Quantity'; DataClassification = SystemMetadata; }
        field(26; "Unit of Measure"; Code[10]) { Caption = 'Unit of Measure'; DataClassification = SystemMetadata; }
        field(27; "Expiration Date"; Date) { Caption = 'Expiration Date'; DataClassification = SystemMetadata; }
        field(28; "Line Weight kg"; Decimal) { Caption = 'Line Weight kg'; DataClassification = SystemMetadata; }
        field(29; "Container LP No."; Code[20]) { Caption = 'Container LP No.'; DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
