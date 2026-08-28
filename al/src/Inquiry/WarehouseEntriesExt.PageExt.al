pageextension 72314 "DOPSWHS Warehouse Entries" extends "Warehouse Entries"
{
    layout
    {
        addafter("Lot No.")
        {
            field("DOPSWHS LP No."; Rec."DOPSWHS LP No.")
            {
                ApplicationArea = All;
                Caption = 'LP No.';
                ToolTip = 'Bu ambar girişinin ilişkili olduğu taşıma kabı (LP) numarasını gösterir.';
                DrillDown = true;

                trigger OnDrillDown()
                var
                    LPHeader: Record "DOPSWHS LP Header";
                begin
                    if (Rec."DOPSWHS LP No." <> '') and LPHeader.Get(Rec."DOPSWHS LP No.") then
                        Page.Run(Page::"DOPSWHS LP Card", LPHeader);
                end;
            }
        }
    }
}
