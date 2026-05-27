page 72078 "DOPSWHS LP Factbox Bin"
{
    PageType = ListPart;
    SourceTable = "DOPSWHS LP Header";
    SourceTableView = where(Status = const(Built));
    ApplicationArea = All;
    Caption = 'License Plates';

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("No."; Rec."No.") { ApplicationArea = All; Caption = 'LP No.'; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Caption = 'Bin Code'; }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; Caption = 'Template'; }
                field(Status; Rec.Status) { ApplicationArea = All; Caption = 'Status'; }
            }
        }
    }
}
