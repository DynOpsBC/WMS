page 72285 "DOPSWHS Local User List"
{
    PageType = List;
    SourceTable = "DOPSWHS WMS Terminal";
    Caption = 'WMS Terminaller ve Kullanıcılar';
    AdditionalSearchTerms = 'Local WMS Users,terminal,kullanıcı';
    ApplicationArea = All;
    UsageCategory = Lists;
    CardPageId = "DOPSWHS Terminal Card";
    layout
    {
        area(Content)
        {
            repeater(Terminals)
            {
                field(Code; Rec.Code) { ApplicationArea = All; }
                field("Label Printer Code"; Rec."Label Printer Code") { ApplicationArea = All; }
                field("Document Printer Code"; Rec."Document Printer Code") { ApplicationArea = All; }
                field(Disabled; Rec.Disabled) { ApplicationArea = All; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(CreateManager)
            {
                Caption = 'Yönetici Oluştur';
                ApplicationArea = All;
                Image = New;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                var
                    UserDialog: Page "DOPSWHS Create PIN User";
                begin
                    UserDialog.SetManager();
                    if UserDialog.RunModal() = Action::OK then begin
                        UserDialog.CreateUser();
                        ShowManagers();
                    end;
                end;
            }
            action(Managers)
            {
                Caption = 'Yöneticiler';
                ApplicationArea = All;
                Image = Users;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                begin
                    ShowManagers();
                end;
            }
            action(ExistingUsers)
            {
                Caption = 'Tüm Kullanıcılar';
                Promoted = true;
                PromotedCategory = Process;
                ApplicationArea = All;
                Image = Users;
                RunObject = page "DOPSWHS Terminal Users";
                ToolTip = 'Mevcut kullanıcıları bir terminale atayın; kullanıcı kodları ve geçmiş işlemleri korunur.';
            }
        }
    }
    local procedure ShowManagers()
    var
        LocalUser: Record "DOPSWHS Local User";
    begin
        LocalUser.SetRange("Terminal Admin", true);
        Page.Run(Page::"DOPSWHS Terminal Users", LocalUser);
    end;
}
