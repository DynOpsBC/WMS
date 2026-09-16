tableextension 72421 "DOPSWHS Posted Whse Shpt Hdr" extends "Posted Whse. Shipment Header"
{
    fields
    {
        field(72421; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        // EMU/DKÇ (15 Eyl 2026): carried from the warehouse shipment on posting.
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
