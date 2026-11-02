pageextension 72001 "DOPSWHS Purch. Order Quality" extends "Purchase Order"
{
    // KIT-009 (Kitoko, Kas 2026): inspections of a purchase order that is
    // received without a warehouse receipt.
    actions
    {
        addlast(Processing)
        {
            group("DOPSWHS Quality")
            {
                Caption = 'Quality Inspection';
                Image = TaskQualityMeasure;

                action("DOPSWHS Create Quality Orders")
                {
                    ApplicationArea = All;
                    Caption = 'Create Quality Orders';
                    Image = CreateDocument;
                    ToolTip = 'Create quality orders for the order lines that require an inspection (one per assigned lot). The lines can be received when every inspection has a result.';

                    trigger OnAction()
                    var
                        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                        Created: Integer;
                    begin
                        CurrPage.SaveRecord();
                        Created := QualityGateMgmt.CreateOrdersForPurchaseOrder(Rec);
                        Message(QualityOrdersCreatedMsg, Created);
                    end;
                }
                action("DOPSWHS Quality Orders")
                {
                    ApplicationArea = All;
                    Caption = 'Quality Orders';
                    Image = TaskQualityMeasure;
                    ToolTip = 'Show the quality orders of this purchase order.';

                    trigger OnAction()
                    var
                        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                    begin
                        QualityGateMgmt.ShowOrdersForSource(Database::"Purchase Line", Rec."Document Type".AsInteger(), Rec."No.", 0);
                    end;
                }
            }
        }
    }

    var
        QualityOrdersCreatedMsg: Label '%1 quality order(s) created.', Comment = '%1 = number of quality orders';
}
