page 72004 "DOPSWHS Quality Orders"
{
    // KIT-009 / INV-010 (Kitoko, Kas 2026): quality orders managed in Business
    // Central (until now only the terminal API page 72256 existed). Results are
    // recorded through codeunit "DOPSWHS Quality Mgmt", like on the terminal.
    Caption = 'Quality Orders';
    PageType = List;
    SourceTable = "DOPSWHS Quality Order";
    CardPageId = "DOPSWHS Quality Order Card";
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;
    SourceTableView = sorting("No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Orders)
            {
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the number of the quality order.';
                }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                    StyleExpr = StatusStyle;
                    ToolTip = 'Specifies the inspection status: Open until a result is recorded, then Passed or Failed.';
                }
                field("Source Type"; Rec."Source Type")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies what the inspection is for (receipt, assembly, manual, ...).';
                }
                field("Source No."; Rec."Source No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the source document (purchase order, assembly order, warehouse receipt).';
                }
                field("Source Line No."; Rec."Source Line No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the source document line that is inspected.';
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the inspected item.';
                }
                field("Item Description"; Rec."Item Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the description of the inspected item.';
                }
                field("Variant Code"; Rec."Variant Code")
                {
                    ApplicationArea = All;
                    Visible = false;
                    ToolTip = 'Specifies the variant of the inspected item.';
                }
                field("Lot No."; Rec."Lot No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the inspected lot. With Quality Lot Hold on, the lot is blocked until the order is passed.';
                }
                field("Serial No."; Rec."Serial No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the inspected serial number.';
                }
                field(OnHold; OnHold)
                {
                    ApplicationArea = All;
                    Caption = 'On Quality Hold';
                    ToolTip = 'Specifies whether the lot/serial of the order is currently blocked by the quality hold.';
                }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the inspected quantity.';
                }
                field("Unit of Measure Code"; Rec."Unit of Measure Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the unit of measure of the quantity. Blank means the base unit of measure.';
                }
                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the location of the inspected stock.';
                }
                field("Bin Code"; Rec."Bin Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the bin of the inspected stock.';
                }
                field("Quarantine Bin"; Rec."Quarantine Bin")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the only bin in which held stock of this order may be placed.';
                }
                field("LP No."; Rec."LP No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the license plate of the inspected stock.';
                }
                field("Vendor No."; Rec."Vendor No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the vendor of the inspected stock.';
                }
                field(Inspector; Rec.Inspector)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies who recorded the result.';
                }
                field("Inspected DateTime"; Rec."Inspected DateTime")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the result was recorded.';
                }
                field("Reject Reason"; Rec."Reject Reason")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies why the stock was rejected.';
                }
                field(Decision; Rec.Decision)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies what happens with rejected stock: scrap, return to vendor, rework or accept with deviation.';
                }
                field("Decision Executed"; Rec."Decision Executed")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether the decision has been executed.';
                }
                field("Decision Document No."; Rec."Decision Document No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the scrap journal document, return order or re-inspection order created by the decision.';
                }
                field("Posted Document No."; Rec."Posted Document No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the posted receipt or assembly that used this inspection.';
                }
                field("Whse. Document No."; Rec."Whse. Document No.")
                {
                    ApplicationArea = All;
                    Visible = false;
                    ToolTip = 'Specifies the warehouse receipt the inspection was created from.';
                }
                field("Due Date"; Rec."Due Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the inspection is due.';
                }
                field("Created DateTime"; Rec."Created DateTime")
                {
                    ApplicationArea = All;
                    Visible = false;
                    ToolTip = 'Specifies when the quality order was created.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PassOrder)
            {
                ApplicationArea = All;
                Caption = 'Pass';
                Image = Approve;
                ToolTip = 'Record a passed inspection. The quality hold of the lot is released.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.PassWithDialog(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(FailOrder)
            {
                ApplicationArea = All;
                Caption = 'Fail';
                Image = Reject;
                ToolTip = 'Record a failed inspection with a reason and quarantine bin. The lot stays blocked until a decision is executed.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.FailWithDialog(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(ExecuteDecision)
            {
                ApplicationArea = All;
                Caption = 'Execute Decision';
                Image = PostOrder;
                ToolTip = 'Execute the decision of the failed order: post the scrap, create the purchase return order, open a re-inspection or accept with deviation.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.ExecuteDecisionWithConfirm(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(ReleaseHold)
            {
                ApplicationArea = All;
                Caption = 'Release Quality Hold';
                Image = ReOpen;
                ToolTip = 'Unblock the lot/serial of the order without a result, for example to pick a rejected lot for its return shipment.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.ReleaseHoldWithConfirm(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
        area(Navigation)
        {
            action(LotInformation)
            {
                ApplicationArea = All;
                Caption = 'Lot No. Information';
                Image = LotInfo;
                ToolTip = 'Open the lot information card of the inspected lot.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.ShowTrackingInformation(Rec);
                end;
            }
            action(ItemLedgerEntries)
            {
                ApplicationArea = All;
                Caption = 'Item Ledger Entries';
                Image = ItemLedger;
                ToolTip = 'Show the item ledger entries of the inspected item and lot/serial.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.ShowItemLedgerEntries(Rec);
                end;
            }
            action(SourceDocument)
            {
                ApplicationArea = All;
                Caption = 'Source Document';
                Image = Document;
                ToolTip = 'Open the purchase order or assembly order the inspection belongs to.';

                trigger OnAction()
                begin
                    QualityDecisionMgmt.ShowSourceDocument(Rec);
                end;
            }
            action(QualityRules)
            {
                ApplicationArea = All;
                Caption = 'Quality Inspection Rules';
                Image = CheckRulesSyntax;
                RunObject = page "DOPSWHS Quality Rules";
                ToolTip = 'Define which receipts and assembly outputs require an inspection.';
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(PassOrder_Promoted; PassOrder) { }
                actionref(FailOrder_Promoted; FailOrder) { }
                actionref(ExecuteDecision_Promoted; ExecuteDecision) { }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        OnHold := QualityLotHold.IsOnHold(Rec);
        StatusStyle := QualityDecisionMgmt.StatusStyle(Rec);
    end;

    var
        QualityDecisionMgmt: Codeunit "DOPSWHS Quality Decision Mgmt";
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
        OnHold: Boolean;
        StatusStyle: Text;
}
