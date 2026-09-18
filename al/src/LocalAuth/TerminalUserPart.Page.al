page 72322 "DOPSWHS Terminal User Part"
{
    PageType = ListPart;
    SourceTable = "DOPSWHS Local User";
    Caption = 'Kullanıcılar';
    InsertAllowed = false;
    DeleteAllowed = false;
    CardPageId = "DOPSWHS Local User Card";
    layout
    {
        area(Content)
        {
            repeater(Users)
            {
                field("Display Name"; Rec."Display Name") { Caption = 'Ad Soyad'; ApplicationArea = All; Editable = CanManageUsers; }
                field(Disabled; Rec.Disabled) { Caption = 'Devre Dışı'; ApplicationArea = All; Editable = CanManageUsers; }
                field("Last Login DateTime"; Rec."Last Login DateTime") { Caption = 'Son Giriş'; ApplicationArea = All; Editable = false; }
            }
        }
    }
    trigger OnOpenPage()
    var
        AuthMgt: Codeunit "DOPSWHS Local Auth Mgmt";
    begin
        CanManageUsers := AuthMgt.CanManageLocalUsers();
    end;

    var
        CanManageUsers: Boolean;
}
