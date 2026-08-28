tableextension 72431 "DOPSWHS Whse Rcpt Line Ext" extends "Warehouse Receipt Line"
{
    fields
    {
        field(72431; "DOPSWHS Pending Lot No."; Code[50])
        {
            Caption = 'Pending Lot No.';
            DataClassification = CustomerContent;
        }
    }
}
