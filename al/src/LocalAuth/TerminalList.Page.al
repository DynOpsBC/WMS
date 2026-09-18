page 72320 "DOPSWHS Terminal List"
{
    PageType = List;
    SourceTable = "DOPSWHS WMS Terminal";
    Caption = 'WMS Terminalleri';
    ApplicationArea = All;
    UsageCategory = Lists;
    AdditionalSearchTerms = 'el terminali,terminal,yazıcı';
    CardPageId = "DOPSWHS Terminal Card";

    layout
    {
        area(Content)
        {
            repeater(Terminals)
            {
                field(Code; Rec.Code) { ApplicationArea = All; }
                field("Label Printer Code"; Rec."Label Printer Code") { ApplicationArea = All; }
                field("Document Printer Code"; Rec."Document Printer Code") { ApplicationArea = All; }
                field(Disabled; Rec.Disabled) { ApplicationArea = All; }
            }
        }
    }
}
