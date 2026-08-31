tableextension 72448 "DOPSWHS Subcontract Trans Shpt" extends "Transfer Shipment Header"
{
    fields
    {
        field(72440; "DOPSWHS Fason Reference No."; Code[50])
        {
            Caption = 'Fason Reference No.';
            DataClassification = CustomerContent;
        }
        field(72441; "DOPSWHS Fason Prod. Order No."; Code[20])
        {
            Caption = 'Fason Prod. Order No.';
            DataClassification = CustomerContent;
        }
        field(72442; "DOPSWHS Fason Purch. Order No."; Code[20])
        {
            Caption = 'Fason Purchase Order No.';
            DataClassification = CustomerContent;
        }
        field(72443; "DOPSWHS Fason Operation No."; Code[10])
        {
            Caption = 'Fason Operation No.';
            DataClassification = CustomerContent;
        }
        field(72444; "DOPSWHS E-Despatch Status"; Code[20])
        {
            Caption = 'E-Despatch Status';
            DataClassification = CustomerContent;
        }
        field(72445; "DOPSWHS E-Despatch Document No."; Code[50])
        {
            Caption = 'E-Despatch Document No.';
            DataClassification = CustomerContent;
        }
    }
}
