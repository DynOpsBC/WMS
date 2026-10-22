pageextension 72398 "DOPSWHS Bin Cont LP Compare" extends "Bin Contents"
{
    actions
    {
        addlast(Processing)
        {
            action(DOPSWHSBinLpCompare)
            {
                ApplicationArea = All;
                Caption = 'Göz ve LP karşılaştırma';
                ToolTip = 'Seçili gözün BC stoğunu gözdeki aktif LP miktarıyla madde/lot bazında karşılaştırır; farkların olası nedenini gösterir.';
                Image = CompareCOA;

                trigger OnAction()
                var
                    ComparePage: Page "DOPSWHS Bin LP Compare";
                    LocationCode: Code[10];
                begin
                    LocationCode := Rec."Location Code";
                    if LocationCode = '' then
                        LocationCode := CopyStr(Rec.GetFilter("Location Code"), 1, MaxStrLen(LocationCode));
                    ComparePage.SetContext(LocationCode, Rec."Bin Code", '');
                    ComparePage.Run();
                end;
            }
        }
    }
}
