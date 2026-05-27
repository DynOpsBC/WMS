pageextension 72301 "DOPSWHS Bin Card Ext" extends "Bin Contents"
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
