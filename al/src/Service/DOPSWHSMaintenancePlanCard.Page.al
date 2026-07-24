page 72007 "DOPSWHS Maintenance Plan Card"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Maintenance Plan Card';
    PageType = Card;
    SourceTable = "DOPSWHS Maintenance Plan";
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Asset No."; Rec."Asset No.") { ApplicationArea = All; }
                field("Maintenance Type"; Rec."Maintenance Type") { ApplicationArea = All; }
                field("Interval (Days)"; Rec."Interval (Days)") { ApplicationArea = All; }
                field("Next Due Date"; Rec."Next Due Date") { ApplicationArea = All; }
                field("Last Completed Date"; Rec."Last Completed Date") { ApplicationArea = All; Editable = false; }
                field(Enabled; Rec.Enabled) { ApplicationArea = All; }
                field("Checklist Text"; Rec."Checklist Text") { ApplicationArea = All; MultiLine = true; }
            }
        }
    }
}
