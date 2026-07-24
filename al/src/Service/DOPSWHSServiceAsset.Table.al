table 72028 "DOPSWHS Service Asset"
{
    // NOT: Bu obje bu ortamda derlenmedi (BC sembol paketi/sandbox erişimi yok).
    // Merge öncesi VS Code + AL derleyicisiyle veya bir BC sandbox'ta doğrulanmalı.
    //
    // SM-01: Servis Yönetimi modülünün çekirdek varlık kaydı. Muhasebesel Fixed Asset
    // ile isteğe bağlı bağlantı (CIT-042'nin "ikili varlık modeli") — aynı ekipmanı
    // hem FA hem operasyonel varlık olarak temsil edebilmek için.
    Caption = 'Service Asset';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Service Assets";
    DrillDownPageId = "DOPSWHS Service Assets";

    fields
    {
        field(1; "No."; Code[20])
        {
            Caption = 'No.';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(10; "Description"; Text[100])
        {
            Caption = 'Description';
            DataClassification = CustomerContent;
        }
        field(20; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location;
        }
        field(21; "Bin Code"; Code[20])
        {
            Caption = 'Bin Code';
            DataClassification = CustomerContent;
        }
        field(30; "Fixed Asset No."; Code[20])
        {
            Caption = 'Fixed Asset No.';
            DataClassification = CustomerContent;
            TableRelation = "Fixed Asset";
            ToolTip = 'Opsiyonel: muhasebesel sabit kıymet kaydına bağlantı (ikili varlık modeli).';
        }
        field(40; "Serial No."; Code[50])
        {
            Caption = 'Serial No.';
            DataClassification = CustomerContent;
        }
        field(50; "Warranty Expiry"; Date)
        {
            Caption = 'Warranty Expiry';
            DataClassification = CustomerContent;
        }
        field(60; "Open Work Order Count"; Integer)
        {
            Caption = 'Open Work Order Count';
            FieldClass = FlowField;
            CalcFormula = count("DOPSWHS Work Order" where("Asset No." = field("No."), Status = filter(Open | Assigned | "In Progress" | "Waiting Parts")));
            Editable = false;
        }
        field(70; "Blocked"; Boolean)
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
    }
}
