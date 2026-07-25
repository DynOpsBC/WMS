table 72038 "DOPSWHS Service SLA"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-03: SLA parametreleri (müdahale süresi, tekrar arıza limiti) sözleşmeye
    // bağlanır; DOPSWHS SLA Monitor bunları okuyup ihlali tespit eder.
    Caption = 'Service SLA';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Service SLAs";
    DrillDownPageId = "DOPSWHS Service SLAs";

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
        field(20; "Priority"; Enum "DOPSWHS Fault Severity")
        {
            Caption = 'Priority';
            DataClassification = CustomerContent;
        }
        field(30; "Response Time (Hours)"; Decimal)
        {
            Caption = 'Response Time (Hours)';
            DataClassification = CustomerContent;
            ToolTip = 'İş emri açıldıktan sonra saha müdahalesinin başlaması gereken azami süre.';
        }
        field(40; "Resolution Time (Hours)"; Decimal)
        {
            Caption = 'Resolution Time (Hours)';
            DataClassification = CustomerContent;
            ToolTip = 'İş emri açıldıktan sonra kapatılması gereken azami süre.';
        }
        field(50; "Repeat Fault Window (Days)"; Integer)
        {
            Caption = 'Repeat Fault Window (Days)';
            DataClassification = CustomerContent;
            ToolTip = 'Aynı varlıkta bu gün sayısı içinde tekrar arıza açılırsa "tekrar arıza" olarak sayılır.';
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
