tableextension 72433 "DOPSWHS Whse. Journal Line Ext" extends "Warehouse Journal Line"
{
    fields
    {
        field(72434; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
    }
}
