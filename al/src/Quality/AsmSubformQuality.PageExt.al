pageextension 72003 "DOPSWHS Asm. Subform Quality" extends "Assembly Order Subform"
{
    // INV-010 (Kitoko, Kas 2026): a defect found on the assembly line is
    // recorded against the component line and its lot/serial; the failed
    // quality order then carries the scrap / return decision.
    actions
    {
        addlast(Processing)
        {
            action("DOPSWHS Report Defect")
            {
                ApplicationArea = All;
                Caption = 'Report Component Defect';
                Image = TaskQualityMeasure;
                ToolTip = 'Create a quality order for the component on this line (with its lot/serial). Fail it with the defect reason and decide scrap or return to vendor.';

                trigger OnAction()
                var
                    QualityOrder: Record "DOPSWHS Quality Order";
                    QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                    OrderNo: Code[20];
                begin
                    OrderNo := QualityGateMgmt.CreateComponentInspection(Rec);
                    if QualityOrder.Get(OrderNo) then
                        Page.Run(Page::"DOPSWHS Quality Order Card", QualityOrder);
                end;
            }
        }
    }
}
