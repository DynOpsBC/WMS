table 72029 "DOPSWHS Service Contract"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-02.
    Caption = 'Service Contract';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Service Contracts";
    DrillDownPageId = "DOPSWHS Service Contracts";

    fields
    {
        field(1; "No."; Code[20])
        {
            Caption = 'No.';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(10; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            DataClassification = CustomerContent;
            TableRelation = Customer;
        }
        field(20; "Covered Asset No."; Code[20])
        {
            Caption = 'Covered Asset No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Service Asset";
        }
        field(30; "Start Date"; Date)
        {
            Caption = 'Start Date';
            DataClassification = CustomerContent;
        }
        field(31; "End Date"; Date)
        {
            Caption = 'End Date';
            DataClassification = CustomerContent;
        }
        field(40; "Billing Type"; Option)
        {
            Caption = 'Billing Type';
            OptionMembers = "Fixed Fee",Time,"Per Visit";
            OptionCaption = 'Fixed Fee,Time,Per Visit';
            DataClassification = CustomerContent;
        }
        field(50; "SLA Code"; Code[20])
        {
            Caption = 'SLA Code';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Service SLA";
        }
        field(60; "Blocked"; Boolean)
        {
            Caption = 'Blocked';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "No.")
        {
            Clustered = true;
        }
        key(Asset; "Covered Asset No.")
        {
        }
    }
}
