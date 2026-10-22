table 72035 "DOPSWHS First Count Line"
{
    Caption = 'First Count Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Count No."; Code[20])
        {
            Caption = 'Count No.';
            TableRelation = "DOPSWHS First Count Header";
        }
        field(2; "Line No."; Integer) { Caption = 'Line No.'; }
        field(3; "Scan Id"; Guid) { Caption = 'Scan Id'; }
        field(4; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item;
        }
        field(5; "Variant Code"; Code[10]) { Caption = 'Variant Code'; }
        field(6; "Bin Code"; Code[20]) { Caption = 'Bin Code'; }
        field(7; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(8; "Unit of Measure Code"; Code[10]) { Caption = 'Unit of Measure Code'; }
        field(9; Quantity; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        field(10; "Qty. per Unit of Measure"; Decimal)
        {
            Caption = 'Qty. per Unit of Measure';
            DecimalPlaces = 0 : 5;
        }
        field(11; "Quantity (Base)"; Decimal)
        {
            Caption = 'Quantity (Base)';
            DecimalPlaces = 0 : 5;
        }
        field(12; Description; Text[100]) { Caption = 'Description'; }
        field(13; "User ID"; Code[50]) { Caption = 'User ID'; }
        field(14; "Created DateTime"; DateTime) { Caption = 'Created DateTime'; }
    }

    keys
    {
        key(PK; "Count No.", "Line No.") { Clustered = true; }
        key(ScanId; "Scan Id") { }
        key(Group; "Count No.", "Bin Code", "Item No.", "Variant Code", "Lot No.") { SumIndexFields = "Quantity (Base)"; }
    }
}
