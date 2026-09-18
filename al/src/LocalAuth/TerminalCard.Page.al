page 72321 "DOPSWHS Terminal Card"
{
    PageType = Card;
    SourceTable = "DOPSWHS WMS Terminal";
    Caption = 'Terminal';
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Terminal';
                field(Code; Rec.Code) { ApplicationArea = All; }
                field(Disabled; Rec.Disabled) { ApplicationArea = All; }
                field("Label Printer Code"; Rec."Label Printer Code") { ApplicationArea = All; }
                field("Document Printer Code"; Rec."Document Printer Code") { ApplicationArea = All; }
            }
            part(Users; "DOPSWHS Terminal User Part")
            {
                ApplicationArea = All;
                SubPageLink = "Terminal Code" = field(Code);
            }
            part(Managers; "DOPSWHS Terminal User Part")
            {
                Caption = 'Yöneticiler (Tüm Terminaller)';
                ApplicationArea = All;
                SubPageLink = "Terminal Admin" = const(true);
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(CreateUser)
            {
                Caption = 'Kullanıcı Oluştur';
                ApplicationArea = All;
                Image = New;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = CanManageUsers;
                trigger OnAction()
                var
                    Dialog: Page "DOPSWHS Create PIN User";
                begin
                    Rec.TestField(Code);
                    Rec.TestField(Disabled, false);
                    CurrPage.SaveRecord();
                    Dialog.SetTerminal(Rec.Code);
                    if Dialog.RunModal() = Action::OK then
                        Dialog.CreateUser();
                    CurrPage.Update(false);
                    CurrPage.Users.Page.Update(false);
                end;
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
