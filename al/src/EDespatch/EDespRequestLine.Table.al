table 72454 "DOPSWHS EDesp Request Line"
{
    // Lines of an e-despatch request that has no Business Central source document, for example a batch of
    // handheld bin moves to a subcontractor bin.
    Caption = 'E-Despatch Request Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Request Entry No."; Integer)
        {
            Caption = 'Request Entry No.';
            TableRelation = "DOPSWHS EDesp Request"."Entry No.";
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
        }
        field(3; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item."No.";
        }
        field(4; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
        }
        field(5; Description; Text[100])
        {
            Caption = 'Description';
        }
        field(6; Quantity; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        field(7; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
        }
        field(8; "Lot No."; Code[50])
        {
            Caption = 'Lot No.';
        }
        field(9; "Serial No."; Code[50])
        {
            Caption = 'Serial No.';
        }
        field(10; "From Bin Code"; Code[20])
        {
            Caption = 'From Bin Code';
        }
        field(11; "To Bin Code"; Code[20])
        {
            Caption = 'To Bin Code';
        }
        field(12; "LP No."; Code[20])
        {
            Caption = 'LP No.';
        }
        field(13; Posted; Boolean)
        {
            Caption = 'Posted';
        }
    }

    keys
    {
        key(PK; "Request Entry No.", "Line No.")
        {
            Clustered = true;
        }
    }
}
