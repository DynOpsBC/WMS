table 72025 "DOPSWHS Migration Map WI"
{
    Caption = 'DOPSWHS Migration Map WI';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
            DataClassification = CustomerContent;
        }
    }

    keys { key(PK; "Primary Key") { Clustered = true; } }
}
