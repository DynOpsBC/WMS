pageextension 72301 "DOPSWHS Bin Card Ext" extends "Bin Card"
{
    layout
    {
        addlast(FactBoxes)
        {
            part(DOPSWHSLPFactboxBin; "DOPSWHS LP Factbox Bin")
            {
                ApplicationArea = All;
            }
        }
    }
}
