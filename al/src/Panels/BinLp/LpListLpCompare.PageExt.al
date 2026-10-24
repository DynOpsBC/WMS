pageextension 72399 "DOPSWHS LP List LP Compare" extends "DOPSWHS LP List"
{
    actions
    {
        addlast(Processing)
        {
            action(DOPSWHSBinLpCompare)
            {
                ApplicationArea = All;
                Caption = 'Göz ve LP karşılaştırma';
                ToolTip = 'Seçili LP''nin gözündeki stoğu aktif LP miktarıyla karşılaştırır.';
                Image = CompareCOA;
                Promoted = true;
                PromotedCategory = Report;

                trigger OnAction()
                var
                    ComparePage: Page "DOPSWHS Bin LP Compare";
                begin
                    ComparePage.SetContext(Rec."Location Code", Rec."Bin Code", '');
                    ComparePage.Run();
                end;
            }
        }
    }
}
