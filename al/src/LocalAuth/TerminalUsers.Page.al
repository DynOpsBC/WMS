page 72324 "DOPSWHS Terminal Users"
{
    PageType = List;
    SourceTable = "DOPSWHS Local User";
    Caption = 'WMS Kullanıcıları';
    ApplicationArea = All;
    UsageCategory = Lists;
    AdditionalSearchTerms = 'WMS kullanıcıları,yöneticiler';
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
                field("Terminal Admin"; Rec."Terminal Admin") { ApplicationArea = All; Editable = false; }
                field("Terminal Code"; Rec."Terminal Code") { ApplicationArea = All; Editable = CanManageUsers; }
                field(Disabled; Rec.Disabled) { Caption = 'Devre Dışı'; ApplicationArea = All; Editable = CanManageUsers; }
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
