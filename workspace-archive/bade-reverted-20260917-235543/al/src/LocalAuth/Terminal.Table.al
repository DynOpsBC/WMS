table 72321 "DOPSWHS WMS Terminal"
{
    Caption = 'WMS Terminal';
    DataClassification = CustomerContent;
    // Retained for non-destructive upgrade from company-specific terminals.
    DataPerCompany = true;
    ObsoleteState = Pending;
    ObsoleteReason = 'Terminals moved to DOPSWHS Environment Terminal.';
    ObsoleteTag = '1.14.1.55';
    LookupPageId = "DOPSWHS Local User List";
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
    trigger OnDelete()
    var
        LocalUser: Record "DOPSWHS Local User";
    begin
        LocalUser.SetRange("Terminal Code", Code);
        if not LocalUser.IsEmpty() then
            Error('Önce terminalin kullanıcılarını başka bir terminale taşıyın.');
    end;
}
