table 72321 "DOPSWHS WMS Terminal"
{
    Caption = 'WMS Terminal';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Terminal List";
    DrillDownPageId = "DOPSWHS Terminal List";

    fields
    {
        field(1; Code; Code[20]) { Caption = 'Terminal Adı'; NotBlank = true; }
        field(2; Disabled; Boolean) { Caption = 'Devre Dışı'; }
        field(3; "Label Printer Code"; Code[20])
        {
            Caption = 'Etiket Yazıcısı';
            TableRelation = "DOPSWHS Printer".Code where(Active = const(true), Format = const(ZPL));
        }
        field(4; "Document Printer Code"; Code[20])
        {
            Caption = 'Belge Yazıcısı';
            TableRelation = "DOPSWHS Printer".Code where(Active = const(true), Format = const(PDF));
        }
    }

    keys { key(PK; Code) { Clustered = true; } }
}
