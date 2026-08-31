tableextension 72447 "DOPSWHS Subcontract Trans Hdr" extends "Transfer Header"
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
    }
}
