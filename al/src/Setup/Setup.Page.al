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
