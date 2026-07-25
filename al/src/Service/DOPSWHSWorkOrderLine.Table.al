table 72034 "DOPSWHS Work Order Line"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-07: bakım iş emrine bağlanan yedek parça/sarf tüketimi (ELM-052).
    Caption = 'Work Order Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Work Order No."; Code[20])
        {
            Caption = 'Work Order No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Work Order"."No.";
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
            DataClassification = SystemMetadata;
        }
        field(10; "Type"; Option)
        {
            Caption = 'Type';
            OptionMembers = Labor,Part;
            OptionCaption = 'Labor,Part';
            DataClassification = CustomerContent;
        }
        field(20; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            DataClassification = CustomerContent;
            TableRelation = Item;
        }
        field(30; "Quantity"; Decimal)
        {
            Caption = 'Quantity';
            DataClassification = CustomerContent;
        }
        field(40; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location;
        }
        field(41; "Bin Code"; Code[20])
        {
            Caption = 'Bin Code';
            DataClassification = CustomerContent;
        }
        field(50; "Posted"; Boolean)
        {
            Caption = 'Posted';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(60; "Notes"; Text[100])
        {
            Caption = 'Notes';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Work Order No.", "Line No.")
        {
            Clustered = true;
        }
    }
}
