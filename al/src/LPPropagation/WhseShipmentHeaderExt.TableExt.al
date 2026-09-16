tableextension 72420 "DOPSWHS Whse Shpt Hdr Ext" extends "Warehouse Shipment Header"
{
    fields
    {
        field(72420; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        // EMU/DKÇ (15 Eyl 2026): printed on the packing list header.
        field(72450; "DOPSWHS Container No."; Code[30])
        {
            Caption = 'Container No.';
            DataClassification = CustomerContent;
        }
        field(72451; "DOPSWHS Seal No."; Code[30])
        {
            Caption = 'Seal No.';
            DataClassification = CustomerContent;
        }
    }
}
