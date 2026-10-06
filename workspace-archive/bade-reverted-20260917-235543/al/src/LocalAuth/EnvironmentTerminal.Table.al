table 72326 "DOPSWHS Environment Terminal"
{
    Caption = 'WMS Terminal';
    DataClassification = CustomerContent;
    DataPerCompany = false;
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
    trigger OnRename()
    begin
        Error('Terminal kodu değiştirilemez. Yeni terminal oluşturup kullanıcıları taşıyın.');
    end;

    trigger OnDelete()
    var
        LocalUser: Record "DOPSWHS Local User";
        Company: Record Company;
    begin
        if Company.FindSet() then
            repeat
                LocalUser.ChangeCompany(Company.Name);
                LocalUser.SetRange("Terminal Code", Code);
                if not LocalUser.IsEmpty() then
                    Error('%1 şirketinde terminale bağlı kullanıcılar var. Önce kullanıcıları başka bir terminale taşıyın.', Company.Name);
            until Company.Next() = 0;
    end;
}
