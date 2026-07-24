page 72006 "DOPSWHS Maintenance Plans"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Maintenance Plans';
    PageType = List;
    SourceTable = "DOPSWHS Maintenance Plan";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "DOPSWHS Maintenance Plan Card";

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Asset No."; Rec."Asset No.") { ApplicationArea = All; }
                field("Maintenance Type"; Rec."Maintenance Type") { ApplicationArea = All; }
                field("Interval (Days)"; Rec."Interval (Days)") { ApplicationArea = All; }
                field("Next Due Date"; Rec."Next Due Date")
                {
                    ApplicationArea = All;
                    StyleExpr = DueDateStyleExpr;
                }
                field("Last Completed Date"; Rec."Last Completed Date") { ApplicationArea = All; }
                field(Enabled; Rec.Enabled) { ApplicationArea = All; }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if (Rec."Next Due Date" <> 0D) and (Rec."Next Due Date" <= Today) and Rec.Enabled then
            DueDateStyleExpr := 'Unfavorable'
        else
            DueDateStyleExpr := 'Standard';
    end;

    var
        DueDateStyleExpr: Text;
}
