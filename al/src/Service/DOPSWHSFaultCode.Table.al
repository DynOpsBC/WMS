table 72035 "DOPSWHS Fault Code"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-08: problem-neden-çözüm sınıflandırması için master.
    Caption = 'Fault Code';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Fault Codes";
    DrillDownPageId = "DOPSWHS Fault Codes";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Code';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(10; "Description"; Text[100])
        {
            Caption = 'Description';
            DataClassification = CustomerContent;
        }
        field(20; "Default Severity"; Enum "DOPSWHS Fault Severity")
        {
            Caption = 'Default Severity';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Code")
        {
            Clustered = true;
        }
    }
}
