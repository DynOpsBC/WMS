tableextension 72432 "DOPSWHS Item Journal Line Ext" extends "Item Journal Line"
{
    fields
    {
        field(72433; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
    }
}
