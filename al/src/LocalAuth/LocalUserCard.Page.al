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
                field("Terminal Admin"; Rec."Terminal Admin") { ApplicationArea = All; }
                field("Terminal Code"; Rec."Terminal Code") { ApplicationArea = All; }
                field("Display Name"; Rec."Display Name") { Caption = 'Ad Soyad'; ApplicationArea = All; }
                field("Disabled"; Rec.Disabled) { Caption = 'Devre Dışı'; ApplicationArea = All; }
            }
            group(Security)
            {
                Caption = 'PIN';
                field(PasswordTemp; PasswordTemp)
                {
                    ApplicationArea = All;
                    Caption = 'Yeni 4 Haneli PIN';
                    ExtendedDatatype = Masked;
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

                field("Default Location Code"; Rec."Default Location Code") { ApplicationArea = All; }
                field("Default Bin Code"; Rec."Default Bin Code") { ApplicationArea = All; }
                field("Locale"; Rec.Locale) { ApplicationArea = All; ToolTip = 'tr / en / de'; }
                field("Hide Test Tools"; Rec."Hide Test Tools") { ApplicationArea = All; }
                field("Hide Admin Tools"; Rec."Hide Admin Tools") { ApplicationArea = All; }
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
    var
        ShowAdvanced: Boolean;
        AuthMgt: Codeunit "DOPSWHS Local Auth Mgmt";
        PasswordTemp: Text;
}
