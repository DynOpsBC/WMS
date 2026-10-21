/// <summary>Shows the LP of each put-away line (read-only) next to its bin.</summary>
pageextension 72329 "DOPSWHS Whse PutAway Line LP" extends "Whse. Put-away Subform"
{
    layout
    {
        addafter("Bin Code")
        {
            field("DOPSWHS LP No."; Rec."LP No.")
            {
                ApplicationArea = All;
                Caption = 'LP No.';
                Editable = false;
                ToolTip = 'Bu Al/Koy satırının taşıdığı LP. "LP''ye göre böl" işlemi veya mal kabul kaydı doldurur; burada değiştirilemez.';
            }
        }
    }
}
