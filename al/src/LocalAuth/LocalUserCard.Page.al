page 72286 "DOPSWHS Local User Card"
{
    PageType = Card;
    SourceTable = "DOPSWHS Local User";
    Caption = 'Local WMS User';
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field("Username"; Rec.Username) { ApplicationArea = All; }
                field("Display Name"; Rec."Display Name") { ApplicationArea = All; }
                field("Disabled"; Rec.Disabled) { ApplicationArea = All; }
            }
            group(Defaults)
            {
                Caption = 'Mobil Varsayılanları';
                field("Default Location Code"; Rec."Default Location Code") { ApplicationArea = All; }
                field("Default Bin Code"; Rec."Default Bin Code") { ApplicationArea = All; }
                field("Locale"; Rec.Locale) { ApplicationArea = All; ToolTip = 'tr / en / de'; }
                field("Hide Test Tools"; Rec."Hide Test Tools") { ApplicationArea = All; }
                field("Hide Admin Tools"; Rec."Hide Admin Tools") { ApplicationArea = All; }
            }
            group(Telemetry)
            {
                Caption = 'Telemetri';
                field("Last Login DateTime"; Rec."Last Login DateTime") { ApplicationArea = All; Editable = false; }
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
            action(SetPassword)
            {
                Caption = 'Şifre Belirle / Sıfırla';
                Image = EncryptionKeys;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Bu kullanıcı için yeni şifre belirler. Mobil app bu şifreyle "WMS Hesabı" girişini yapar.';

                trigger OnAction()
                var
                    AuthMgt: Codeunit "DOPSWHS Local Auth Mgmt";
                    NewPwd: Text;
                begin
                    if Rec.Username = '' then
                        Error('Önce kullanıcı kaydını oluşturun ve username belirleyin.');
                    NewPwd := '';
                    if not Dialog.Confirm('Bu kullanıcının şifresini "wms1234" olarak ayarla?', true) then
                        exit;
                    AuthMgt.Register(Rec.Username, Rec."Display Name", 'wms1234', Rec."Default Location Code", Rec."Default Bin Code");
                    Message('Şifre belirlendi. Operatöre "wms1234" değerini güvenli kanaldan bildirin.');
                end;
            }
        }
    }
}
