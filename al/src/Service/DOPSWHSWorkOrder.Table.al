table 72040 "DOPSWHS Work Order"
{
    // NOT: Bu obje bu ortamda derlenmedi (BC sembol paketi/sandbox erişimi yok).
    // Merge öncesi VS Code + AL derleyicisiyle veya bir BC sandbox'ta doğrulanmalı.
    //
    // SM-06: Servis Yönetimi'nin çekirdeği. Hem planlı bakımdan (Maintenance
    // Scheduler) hem arıza bildiriminden (Breakdown Svc) açılır.
    Caption = 'Work Order';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Work Orders";
    DrillDownPageId = "DOPSWHS Work Orders";

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
        field(11; "Contract No."; Code[20])
        {
            Caption = 'Contract No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Service Contract";
        }
        field(20; "Maintenance Type"; Enum "DOPSWHS Maintenance Type")
        {
            Caption = 'Maintenance Type';
            DataClassification = CustomerContent;
        }
        field(21; "Fault Code"; Code[20])
        {
            Caption = 'Fault Code';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Fault Code";
        }
        field(22; "Priority"; Enum "DOPSWHS Fault Severity")
        {
            Caption = 'Priority';
            DataClassification = CustomerContent;
        }
        field(30; "Status"; Enum "DOPSWHS Work Order Status")
        {
            Caption = 'Status';
            DataClassification = CustomerContent;
        }
        field(40; "Assigned To"; Code[50])
        {
            Caption = 'Assigned To';
            DataClassification = EndUserIdentifiableInformation;
        }
        field(50; "Opened At"; DateTime)
        {
            Caption = 'Opened At';
            Editable = false;
            DataClassification = SystemMetadata;
        }
        field(51; "Target Response By"; DateTime)
        {
            Caption = 'Target Response By';
            Editable = false;
            DataClassification = SystemMetadata;
            ToolTip = 'SLA''den türetilen hedef müdahale zamanı (SM-03).';
        }
        field(52; "Responded At"; DateTime)
        {
            Caption = 'Responded At';
            DataClassification = SystemMetadata;
        }
        field(53; "Target Resolution By"; DateTime)
        {
            Caption = 'Target Resolution By';
            Editable = false;
            DataClassification = SystemMetadata;
        }
        field(54; "Closed At"; DateTime)
        {
            Caption = 'Closed At';
            Editable = false;
            DataClassification = SystemMetadata;
        }
        field(60; "SLA Breached"; Boolean)
        {
            Caption = 'SLA Breached';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(70; "Downtime Minutes"; Integer)
        {
            Caption = 'Downtime Minutes';
            DataClassification = CustomerContent;
            ToolTip = 'Bu iş emrine bağlı duruş süresi — iş merkezi kapasitesine yansıtılabilmesi için (ELM-051 ile ilişkili, ayrı bir üretim entegrasyonu gerekir).';
        }
        field(80; "Root Cause"; Text[250])
        {
            Caption = 'Root Cause';
            DataClassification = CustomerContent;
        }
        field(90; "Resolution Notes"; Text[250])
        {
            Caption = 'Resolution Notes';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "No.")
        {
            Clustered = true;
        }
        key(Asset; "Asset No.", Status)
        {
        }
        key(Status; Status)
        {
        }
    }

    trigger OnInsert()
    begin
        if "No." = '' then
            "No." := NextNo();
        if "Opened At" = 0DT then
            "Opened At" := CurrentDateTime();
    end;

    local procedure NextNo(): Code[20]
    var
        WorkOrder: Record "DOPSWHS Work Order";
        Base: Text;
        Candidate: Code[20];
        Suffix: Integer;
    begin
        Base := 'WO-' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>');
        Candidate := CopyStr(Base, 1, 20);
        while WorkOrder.Get(Candidate) do begin
            Suffix += 1;
            Candidate := CopyStr(Base + '-' + Format(Suffix), 1, 20);
        end;
        exit(Candidate);
    end;
}
