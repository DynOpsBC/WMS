tableextension 72406 "DOPSWHS Whse Shipment Line" extends "Warehouse Shipment Line"
{
    fields
    {
        field(72406; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        field(72407; "SSCC"; Code[18])
        {
            Caption = 'SSCC';
            DataClassification = CustomerContent;
        }
    }
}
