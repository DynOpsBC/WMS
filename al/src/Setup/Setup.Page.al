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

    trigger OnOpenPage()
    begin
        if not Rec.Get('') then begin
            Rec.Init();
            Rec.Insert(true);
        end;
    end;
}
