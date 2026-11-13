pageextension 72002 "DOPSWHS Assembly Order Quality" extends "Assembly Order"
{
    // INV-009 / INV-010 (Kitoko, Kas 2026): final inspection of the assembly
    // output and quality orders (incl. component defects) of the order.
    actions
    {
        addlast(Processing)
        {
            group("DOPSWHS Quality")
            {
                Caption = 'Quality Inspection';
                Image = TaskQualityMeasure;

                action("DOPSWHS Create Final Inspection")
                {
                    ApplicationArea = All;
                    Caption = 'Create Final Inspection';
                    Image = CreateDocument;
                    ToolTip = 'Create the final quality inspection of the assembly output. With the assembly quality gate on, the order can only be posted after the inspection is passed.';

                    trigger OnAction()
                    var
                        QualityOrder: Record "DOPSWHS Quality Order";
                        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                        OrderNo: Code[20];
                    begin
                        CurrPage.SaveRecord();
                        OrderNo := QualityGateMgmt.CreateFinalInspection(Rec);
                        if QualityOrder.Get(OrderNo) then
                            Page.Run(Page::"DOPSWHS Quality Order Card", QualityOrder);
                    end;
                }
                action("DOPSWHS Quality Orders")
                {
                    ApplicationArea = All;
                    Caption = 'Quality Orders';
                    Image = TaskQualityMeasure;
                    ToolTip = 'Show the final inspections and component defect records of this assembly order.';

                    trigger OnAction()
                    var
                        QualityOrder: Record "DOPSWHS Quality Order";
                    begin
                        QualityOrder.SetRange("Source Type", QualityOrder."Source Type"::Assembly);
                        QualityOrder.SetRange("Source No.", Rec."No.");
                        Page.Run(Page::"DOPSWHS Quality Orders", QualityOrder);
                    end;
                }
            }
        }
    }
}
