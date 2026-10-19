page 72286 "DOPSWHS Local User Card"
{
    PageType = Card;
    SourceTable = "DOPSWHS Local User";
    Caption = 'WMS Kullanıcısı';
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Kullanıcı';
                field("Terminal Admin"; Rec."Terminal Admin") { ApplicationArea = All; Editable = CanManageUsers; }
                field("Terminal Code"; Rec."Terminal Code") { ApplicationArea = All; Editable = CanManageUsers; }
                field("Display Name"; Rec."Display Name") { Caption = 'Ad Soyad'; ApplicationArea = All; Editable = CanManageUsers; }
                field("Disabled"; Rec.Disabled) { Caption = 'Devre Dışı'; ApplicationArea = All; Editable = CanManageUsers; }
            }
            group(Security)
            {
                Caption = 'PIN';
                Visible = CanManageUsers;
                field(PasswordState; PasswordState)
                {
                    ApplicationArea = All;
                    Caption = 'Mevcut Şifre / PIN';
                    Editable = false;
                    ToolTip = 'Şifre ve PIN değerleri güvenlik için hash olarak saklanır; mevcut değer görüntülenemez.';
                }
                field(PasswordTemp; PasswordTemp)
                {
                    ApplicationArea = All;
                    Caption = 'Yeni 4 Haneli PIN';
                    ExtendedDatatype = Masked;
                    Editable = CanManageUsers;
                    ToolTip = '4 rakam girin. Mevcut PIN gösterilmez.';

                    trigger OnValidate()
                    begin
                        if PasswordTemp <> '' then
                        begin
                            AuthMgt.ValidatePin(PasswordTemp);
                            CurrPage.SaveRecord();
                            AuthMgt.UpdatePassword(Rec.Username, PasswordTemp);
                            Rec.Get(Rec.Username);
                            CurrPage.Update(false);
                            PasswordTemp := '';
                        end;
                    end;
                }
            }
            group(Defaults)
            {
                Caption = 'Diğer Ayarlar';
                Visible = ShowAdvanced;

                field("Default Location Code"; Rec."Default Location Code") { ApplicationArea = All; Editable = CanManageUsers; }
                field("Default Bin Code"; Rec."Default Bin Code") { ApplicationArea = All; Editable = CanManageUsers; }
                field("Locale"; Rec.Locale) { ApplicationArea = All; ToolTip = 'tr / en / de'; Editable = CanManageUsers; }
                field("Hide Test Tools"; Rec."Hide Test Tools") { ApplicationArea = All; Editable = CanManageUsers; }
                field("Hide Admin Tools"; Rec."Hide Admin Tools") { ApplicationArea = All; Editable = CanManageUsers; }
            }
            group(Telemetry)
            {
                Caption = 'Son Giriş';
                Visible = ShowAdvanced;

                field("Last Login DateTime"; Rec."Last Login DateTime") { Caption = 'Son Giriş'; ApplicationArea = All; Editable = false; }
                field("Failed Login Count"; Rec."Failed Login Count") { ApplicationArea = All; Editable = false; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; Editable = false; }
                field("Created By"; Rec."Created By") { ApplicationArea = All; Editable = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Advanced)
            {
                Caption = 'Diğer Ayarlar';
                ApplicationArea = All;
                Image = Setup;
                trigger OnAction()
                begin
                    ShowAdvanced := not ShowAdvanced;
                end;
            }
        }
    }
    trigger OnOpenPage()
    begin
        CanManageUsers := AuthMgt.CanManageLocalUsers();
    end;

    trigger OnAfterGetRecord()
    begin
        if (Rec."Password Hash" <> '') and (Rec."Password Salt" <> '') then
            PasswordState := 'Tanımlı (mevcut değer görüntülenemez)'
        else
            PasswordState := 'Tanımlı değil';
    end;

    var
        ShowAdvanced: Boolean;
        CanManageUsers: Boolean;
        AuthMgt: Codeunit "DOPSWHS Local Auth Mgmt";
        PasswordTemp: Text;
        PasswordState: Text[100];
}
