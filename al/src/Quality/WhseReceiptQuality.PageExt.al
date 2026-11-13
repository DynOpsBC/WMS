pageextension 72000 "DOPSWHS Whse Receipt Quality" extends "Warehouse Receipt"
{
    // KIT-009 (Kitoko, Kas 2026): inspections of the receipt before posting.
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
                    ToolTip = 'Create quality orders for the receipt lines that require an inspection (one per assigned lot). The receipt can be posted when every inspection has a result.';

                    trigger OnAction()
                    var
                        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                        Created: Integer;
                    begin
                        CurrPage.SaveRecord();
                        Created := QualityGateMgmt.CreateOrdersForWhseReceipt(Rec);
                        Message(QualityOrdersCreatedMsg, Created);
                    end;
                }
                action("DOPSWHS Quality Orders")
                {
                    ApplicationArea = All;
                    Caption = 'Quality Orders';
                    Image = TaskQualityMeasure;
                    ToolTip = 'Show the quality orders of this receipt and its purchase orders.';

                    trigger OnAction()
                    var
                        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
                    begin
                        QualityGateMgmt.ShowOrdersForWhseReceipt(Rec);
                    end;
                }
            }
        }
    }

    var
        QualityOrdersCreatedMsg: Label '%1 quality order(s) created.', Comment = '%1 = number of quality orders';
}
