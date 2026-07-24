table 72031 "DOPSWHS Maintenance Plan"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-04: koruyucu bakım planı — DOPSWHS Maintenance Scheduler süresi gelenler
    // için otomatik Work Order açar (SM-05).
    Caption = 'Maintenance Plan';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Maintenance Plans";
    DrillDownPageId = "DOPSWHS Maintenance Plans";

    fields
    {
        field(1; "No."; Code[20])
        {
            Caption = 'No.';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(10; "Asset No."; Code[20])
        {
            Caption = 'Asset No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Service Asset";
        }
        field(20; "Maintenance Type"; Enum "DOPSWHS Maintenance Type")
        {
            Caption = 'Maintenance Type';
            DataClassification = CustomerContent;
        }
        field(30; "Interval (Days)"; Integer)
        {
            Caption = 'Interval (Days)';
            DataClassification = CustomerContent;
            MinValue = 1;
        }
        field(40; "Next Due Date"; Date)
        {
            Caption = 'Next Due Date';
            DataClassification = CustomerContent;
        }
        field(50; "Last Completed Date"; Date)
        {
            Caption = 'Last Completed Date';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(60; "Enabled"; Boolean)
        {
            Caption = 'Enabled';
            InitValue = true;
            DataClassification = CustomerContent;
        }
        field(70; "Checklist Text"; Text[2048])
        {
            Caption = 'Checklist Text';
            DataClassification = CustomerContent;
            ToolTip = 'Satır satır kontrol listesi; ayrı bir alt tablo şimdilik gerekli görülmedi (SM-04 kapsamı).';
        }
    }

    keys
    {
        key(PK; "No.")
        {
            Clustered = true;
        }
        key(DueDate; "Next Due Date", Enabled)
        {
        }
    }
}
