page 72321 "DOPSWHS Terminal Card"
{
    PageType = Card;
    SourceTable = "DOPSWHS WMS Terminal";
    Caption = 'WMS Terminali';
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Terminal';
                field(Code; Rec.Code) { ApplicationArea = All; }
                field("Label Printer Code"; Rec."Label Printer Code") { ApplicationArea = All; }
                field("Document Printer Code"; Rec."Document Printer Code") { ApplicationArea = All; }
                field(Disabled; Rec.Disabled) { ApplicationArea = All; }
            }
        }
    }
}
