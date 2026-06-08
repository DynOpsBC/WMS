table 50104 "WMS License Plate Line"
{
    Caption = 'WMS License Plate Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            TableRelation = "WMS License Plate"."No.";
            NotBlank = true;
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
        }
        field(3; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item;
        }
        field(4; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
            TableRelation = "Item Variant".Code where("Item No." = field("Item No."));
        }
        field(5; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
            TableRelation = "Item Unit of Measure".Code where("Item No." = field("Item No."));
        }
        field(6; Quantity; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        field(7; "Lot No."; Code[50])
        {
            Caption = 'Lot No.';
        }
        field(8; "Serial No."; Code[50])
        {
            Caption = 'Serial No.';
        }
        field(9; "Expiration Date"; Date)
        {
            Caption = 'Expiration Date';
        }
    }

    keys
    {
        key(PK; "LP No.", "Line No.")
        {
            Clustered = true;
        }
        key(Item; "Item No.", "Variant Code") { }
    }
}
