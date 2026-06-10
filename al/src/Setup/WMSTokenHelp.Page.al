page 72009 "DOPSWHS WMS Token Help"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    Caption = 'WMS Token Help — Web/Mobile uygulamaya bağlantı';
    SourceTable = Integer;
    SourceTableTemporary = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(Overview)
            {
                Caption = '1. Genel Bakış';
                label(OverviewMsg)
                {
                    ApplicationArea = All;
                    Caption = 'BCWMS web (tarayıcı) ve mobil (Android) operatör uygulamaları BC SaaS''e AAD bearer token ile bağlanır. Mobil uygulama Device Code Grant''ı otomatik kullanır; web uygulaması ve mobil "Gelişmiş: token yapıştır" yedek akışı, kendi iş istasyonunuzda ürettiğiniz bir token gerektirir.';
                }
            }
            group(Method1)
            {
                Caption = '2. Önerilen yol — Azure CLI (her platform)';
                label(Method1Step1)
                {
                    ApplicationArea = All;
                    Caption = 'Adım 1: Azure CLI''yi kur (https://aka.ms/azcli) ve "az login" ile BC tenant''ına giriş yap (Deniz@dynamicsops.com).';
                }
                field(Method1Cmd; Method1Cmd)
                {
                    ApplicationArea = All;
                    Caption = 'Adım 2: Aşağıdaki komutu Terminal/PowerShell''e yapıştır + çalıştır (1 saat geçerli token kopyalanır)';
                    Editable = false;
                    MultiLine = true;
                    ToolTip = 'Komut çıktısı standard output''a yazılır. macOS''ta "| pbcopy", Windows''ta "| Set-Clipboard" ekleyerek doğrudan kopyalayabilirsin.';
                }
                label(Method1Step3)
                {
                    ApplicationArea = All;
                    Caption = 'Adım 3: Token''ı Web App''in Login ekranındaki textarea''ya, veya Mobile App''in "Gelişmiş: token ile giriş" alanına yapıştır → Bağlan';
                }
            }
            group(Method2)
            {
                Caption = '3. Alternatif — PowerShell (Windows)';
                field(Method2Cmd; Method2Cmd)
                {
                    ApplicationArea = All;
                    Caption = 'Microsoft.Identity.Client veya MSAL.PS modülü gerekir';
                    Editable = false;
                    MultiLine = true;
                }
            }
            group(Method3)
            {
                Caption = '4. Alternatif — curl üzerinden device code (tarayıcısız)';
                field(Method3Cmd; Method3Cmd)
                {
                    ApplicationArea = All;
                    Caption = 'Bir cihazda interactive login yapıp başka cihazda kullanmak için';
                    Editable = false;
                    MultiLine = true;
                }
            }
            group(URLs)
            {
                Caption = '5. Bağlantı uçları';
                field(WebUrl; WebUrl)
                {
                    ApplicationArea = All;
                    Caption = 'Web App URL';
                    Editable = false;
                    ExtendedDatatype = URL;
                }
                field(MobileApk; MobileApk)
                {
                    ApplicationArea = All;
                    Caption = 'Mobile APK (releases)';
                    Editable = false;
                    ExtendedDatatype = URL;
                }
                field(BcEnvironment; BcEnvironment)
                {
                    ApplicationArea = All;
                    Caption = 'BC Environment / Company (giriş ekranına yaz)';
                    Editable = false;
                }
                field(Resource; Resource)
                {
                    ApplicationArea = All;
                    Caption = 'AAD resource (token alırken)';
                    Editable = false;
                }
            }
            group(Notes)
            {
                Caption = '6. Notlar';
                label(NoteExpiry)
                {
                    ApplicationArea = All;
                    Caption = '• Token ömrü ~1 saat. Süre dolunca aynı komutla yenisini al ve yapıştır. Web app sağ üstte 🔴 Bağlı değil gösterirse token expired demektir.';
                }
                label(NoteSecurity)
                {
                    ApplicationArea = All;
                    Caption = '• Token bir bearer secret''ıdır — paylaşma, screen-share ederken görünür yapma. Slack/Teams/email''e gönderme.';
                }
                label(NoteMobile)
                {
                    ApplicationArea = All;
                    Caption = '• Mobile app çoğu durumda Device Code Grant''ı (RFC 8628) kendi yapar; "Token yapıştır" sadece Wi-Fi olmayan kiosk cihazları için fallback''tür.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(OpenWebApp)
            {
                Caption = 'Web App''i tarayıcıda aç';
                ApplicationArea = All;
                Image = Web;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                trigger OnAction()
                begin
                    Hyperlink(WebUrl);
                end;
            }
            action(OpenAzCliDocs)
            {
                Caption = 'az CLI kurulum sayfası';
                ApplicationArea = All;
                Image = Link;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                begin
                    Hyperlink('https://learn.microsoft.com/cli/azure/install-azure-cli');
                end;
            }
            action(OpenMobileApk)
            {
                Caption = 'Mobile APK indir';
                ApplicationArea = All;
                Image = Download;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                begin
                    Hyperlink(MobileApk);
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        Method1Cmd :=
            'az account get-access-token \' + NL +
            '  --resource "https://api.businesscentral.dynamics.com" \' + NL +
            '  --query accessToken -o tsv | pbcopy   # macOS' + NL +
            '' + NL +
            'az account get-access-token `' + NL +
            '  --resource "https://api.businesscentral.dynamics.com" `' + NL +
            '  --query accessToken -o tsv | Set-Clipboard   # PowerShell/Windows';

        Method2Cmd :=
            'Connect-MgGraph -Scopes "user_impersonation"' + NL +
            '$token = Get-MsalToken -ClientId "04b07795-8ddb-461a-bbee-02f9e1bf7b46" `' + NL +
            '  -Authority "https://login.microsoftonline.com/7fa2357e-26f2-4174-8e16-a713981356b8" `' + NL +
            '  -Scopes "https://api.businesscentral.dynamics.com/.default"' + NL +
            '$token.AccessToken | Set-Clipboard';

        Method3Cmd :=
            '# Step 1: device code iste' + NL +
            'curl -s -X POST \' + NL +
            '  "https://login.microsoftonline.com/7fa2357e-26f2-4174-8e16-a713981356b8/oauth2/v2.0/devicecode" \' + NL +
            '  -d "client_id=04b07795-8ddb-461a-bbee-02f9e1bf7b46&scope=https://api.businesscentral.dynamics.com/.default offline_access"' + NL +
            '' + NL +
            '# Step 2: tarayıcıda https://microsoft.com/devicelogin → user_code gir' + NL +
            '# Step 3: token al' + NL +
            'curl -s -X POST \' + NL +
            '  "https://login.microsoftonline.com/7fa2357e-26f2-4174-8e16-a713981356b8/oauth2/v2.0/token" \' + NL +
            '  -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=04b07795-8ddb-461a-bbee-02f9e1bf7b46&device_code=<paste>"';

        WebUrl := 'http://127.0.0.1:5173/';
        MobileApk := 'https://github.com/celandeniz/BCWMSApp/releases';
        BcEnvironment := 'SandboxUS / CRONUS USA, Inc.';
        Resource := 'https://api.businesscentral.dynamics.com';
    end;

    var
        Method1Cmd: Text;
        Method2Cmd: Text;
        Method3Cmd: Text;
        WebUrl: Text[250];
        MobileApk: Text[250];
        BcEnvironment: Text[100];
        Resource: Text[100];
        NL: Label '\', Locked = true;
}
