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
                field("Display Name"; Rec."Display Name") { Caption = 'Ad Soyad'; ApplicationArea = All; }
                field(Disabled; Rec.Disabled) { Caption = 'Devre Dışı'; ApplicationArea = All; }
                field("Last Login DateTime"; Rec."Last Login DateTime") { Caption = 'Son Giriş'; ApplicationArea = All; Editable = false; }
            }
        }
    }
}
