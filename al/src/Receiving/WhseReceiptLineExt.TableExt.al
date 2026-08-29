tableextension 72431 "DOPSWHS Whse Rcpt Line Ext" extends "Warehouse Receipt Line"
{
    fields
    {
        field(72431; "DOPSWHS Pending Lot No."; Code[50])
        {
            Caption = 'Pending Lot No.';
            DataClassification = CustomerContent;
        }
        field(72432; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
    }
}
