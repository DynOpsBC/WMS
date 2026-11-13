pageextension 72004 "DOPSWHS Lot No. Card Quality" extends "Lot No. Information Card"
{
    // KIT-010 (Kitoko, Kas 2026): shows why a lot is blocked.
    layout
    {
        addafter(Blocked)
        {
            field("DOPSWHS Quality Hold"; Rec."DOPSWHS Quality Hold")
            {
                ApplicationArea = ItemTracking;
            }
            field("DOPSWHS Quality Order No."; Rec."DOPSWHS Quality Order No.")
            {
                ApplicationArea = ItemTracking;
            }
        }
    }

    actions
    {
        addlast(Navigation)
        {
            action("DOPSWHS Quality Orders")
            {
                ApplicationArea = ItemTracking;
                Caption = 'Quality Orders';
                Image = TaskQualityMeasure;
                ToolTip = 'Show the quality orders of this lot.';

                trigger OnAction()
                var
                    QualityOrder: Record "DOPSWHS Quality Order";
                begin
                    QualityOrder.SetRange("Item No.", Rec."Item No.");
                    QualityOrder.SetRange("Variant Code", Rec."Variant Code");
                    QualityOrder.SetRange("Lot No.", Rec."Lot No.");
                    Page.Run(Page::"DOPSWHS Quality Orders", QualityOrder);
                end;
            }
        }
    }
}
