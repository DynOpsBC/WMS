page 72481 "DOPSWHS Count Sheet Line Part"
{
    Caption = 'Count Sheet Lines';
    PageType = ListPart;
    SourceTable = "DOPSWHS Count Sheet Line";
    ApplicationArea = All;
    AutoSplitKey = true;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
                field("System Qty"; Rec."System Qty") { ApplicationArea = All; }
                field("Counted Qty 1"; Rec."Counted Qty 1") { ApplicationArea = All; }
                field("Counted Qty 2"; Rec."Counted Qty 2") { ApplicationArea = All; }
                field("Counted Qty 3"; Rec."Counted Qty 3") { ApplicationArea = All; }
                field(Variance; Rec.Variance) { ApplicationArea = All; }
                field("Recount Required"; Rec."Recount Required") { ApplicationArea = All; }
            }
        }
    }
}
