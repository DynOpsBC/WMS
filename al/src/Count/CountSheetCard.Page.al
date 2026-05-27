page 72075 "DOPSWHS Count Sheet Card"
{
    Caption = 'Count Sheet';
    PageType = Card;
    SourceTable = "DOPSWHS Count Sheet Header";
    ApplicationArea = All;
    UsageCategory = Documents;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field(Mode; Rec.Mode) { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
            }
            part(Counters; "DOPSWHS Count Counter Part")
            {
                ApplicationArea = All;
                SubPageLink = "Sheet No." = field("No.");
            }
            part(Lines; "DOPSWHS Count Sheet Line Part")
            {
                ApplicationArea = All;
                SubPageLink = "Sheet No." = field("No.");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Post)
            {
                Caption = 'Post';
                ApplicationArea = All;
                Image = Post;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                begin
                    CountMgmt.PostSheet(Rec."No.");
                    CurrPage.Update(false);
                end;
            }
            action(PrintVarianceReport)
            {
                Caption = 'Print Variance Report';
                ApplicationArea = All;
                Image = PrintReport;
                trigger OnAction()
                var
                    CountLine: Record "DOPSWHS Count Sheet Line";
                begin
                    CountLine.SetRange("Sheet No.", Rec."No.");
                    Report.RunModal(Report::"DOPSWHS Count Variance", true, false, CountLine);
                end;
            }
        }
    }
}
