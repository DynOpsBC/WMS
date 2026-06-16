page 50029002 "WMS License Plates"
{
    Caption = 'WMS License Plates';
    PageType = List;
    SourceTable = "WMS License Plate";
    UsageCategory = Lists;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Parent LP No."; Rec."Parent LP No.") { ApplicationArea = All; }
                field("Container Type Code"; Rec."Container Type Code") { ApplicationArea = All; }
                field(Closed; Rec.Closed) { ApplicationArea = All; }
            }
        }
    }
}
