page 72061 "DOPSWHS Setup"
{
    Caption = 'Advanced WMS Setup';
    PageType = Card;
    SourceTable = "DOPSWHS Setup";
    ApplicationArea = All;
    UsageCategory = Administration;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("LP No. Series"; Rec."LP No. Series")
                {
                    ApplicationArea = All;
                }
                field("SSCC No. Series"; Rec."SSCC No. Series")
                {
                    ApplicationArea = All;
                }
                field("GS1 Company Prefix"; Rec."GS1 Company Prefix")
                {
                    ApplicationArea = All;
                }
                field("Default Location Code"; Rec."Default Location Code")
                {
                    ApplicationArea = All;
                }
                field("Print Channel"; Rec."Print Channel")
                {
                    ApplicationArea = All;
                }
                field("PrintNode API Key Set"; Rec."PrintNode API Key Set")
                {
                    ApplicationArea = All;
                }
                field("Print Relay URL"; Rec."Print Relay URL")
                {
                    ApplicationArea = All;
                }
                field("Print Token TTL Hours"; Rec."Print Token TTL Hours")
                {
                    ApplicationArea = All;
                }
                field("Max LP Nesting Depth"; Rec."Max LP Nesting Depth")
                {
                    ApplicationArea = All;
                }
                field("Webhook Endpoint"; Rec."Webhook Endpoint")
                {
                    ApplicationArea = All;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            group(DemoData)
            {
                Caption = 'Demo Data';
                action(RunDemoSetup)
                {
                    Caption = 'Run Demo Setup';
                    ToolTip = 'Tüm konfigürasyon tablolarını best-practice değerlerle doldurur (No. Series, LP Templates, Device Configs, Barcode Rules, Short Pick Reasons, IWX Report Selection, Demo Devices).';
                    ApplicationArea = All;
                    Image = Setup;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                    RunObject = codeunit "DOPSWHS Demo Data Setup";
                }
                action(RunDemoTransactions)
                {
                    Caption = 'Create Demo Transactions';
                    ToolTip = '5 demo License Plate ve 1 aktif Count Sheet oluşturur. Demo Setup tamamlandıktan sonra kullanın.';
                    ApplicationArea = All;
                    Image = Inventory;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                    RunObject = codeunit "DOPSWHS Demo Transactions";
                }
                action(RunDemoE2ESuite)
                {
                    Caption = 'Run Demo E2E Suite (100 tx)';
                    ToolTip = 'Tüm 10 WMS fonksiyonu (LP/Receive/PutAway/Pick/Ship/Move/Count/Quality/Production/Assembly) için 10''ar transaction çalıştırır = 100 demo transaction. Mobil app''in API ile çağırdığı aynı codeunit''ları AL üzerinden uçtan-uca koşturur. Sonuçlar Demo E2E Results sayfasında.';
                    ApplicationArea = All;
                    Image = TestFile;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                    RunObject = codeunit "DOPSWHS Demo E2E Suite";
                }
                action(ShowDemoE2EResults)
                {
                    Caption = 'Show Demo E2E Results';
                    ToolTip = '100 demo transaction''ın sonuç sayfasını açar (Pass/Fail badge, durasyon, üretilen LP/dokuman).';
                    ApplicationArea = All;
                    Image = TestReport;
                    Promoted = true;
                    PromotedCategory = Process;
                    RunObject = page "DOPSWHS Demo E2E Results";
                }
            }
            group(PrinterBridge)
            {
                Caption = 'Printer Bridge';
                action(PrintersListAction)
                {
                    Caption = 'Printers';
                    ApplicationArea = All;
                    Image = Printer;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Register printers attached to local agents.';
                    RunObject = page "DOPSWHS Printer List";
                }
                action(DevicePrinterMapAction)
                {
                    Caption = 'Device Printer Mapping';
                    ApplicationArea = All;
                    Image = LinkAccount;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Map each device/user to a default printer per usage.';
                    RunObject = page "DOPSWHS Device Printer Map";
                }
            }
            group(TestScenarios)
            {
                Caption = 'Test Scenarios';
                action(GenerateAllScenarios)
                {
                    Caption = 'Generate All Test Scenarios';
                    ToolTip = 'Eldeki master data ve referansları kullanarak tüm alternatif test senaryolarını idempotent olarak yaratır (PO/SO/LP/Count). Tekrar çalıştırıldığında mevcut belgeler atlanır.';
                    ApplicationArea = All;
                    Image = CreateDocument;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                    trigger OnAction()
                    var
                        Gen: Codeunit "DOPSWHS Scenario Generator";
                        Result: Text;
                    begin
                        Result := Gen.GenerateAll();
                        Message(Result);
                    end;
                }
                action(CleanupScenarios)
                {
                    Caption = 'Cleanup Generated Scenarios';
                    ToolTip = 'gen.* prefix''ine sahip tüm generated PO/SO belgelerini siler (test reset). LP ve Count Sheet''ler için manuel temizlik gerekir.';
                    ApplicationArea = All;
                    Image = ClearLog;
                    Promoted = true;
                    PromotedCategory = Process;
                    trigger OnAction()
                    var
                        Gen: Codeunit "DOPSWHS Scenario Generator";
                        DeletedCount: Integer;
                    begin
                        DeletedCount := Gen.CleanupGenerated();
                        Message('Silinen belge: %1', DeletedCount);
                    end;
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get('') then begin
            Rec.Init();
            Rec.Insert(true);
        end;
    end;
}
