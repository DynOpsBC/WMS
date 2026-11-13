page 72005 "DOPSWHS Quality Order Card"
{
    // KIT-009 / KIT-010 / INV-010 (Kitoko, Kas 2026): one quality order. Stock
    // fields are editable while the order is open; changing the lot/serial
    // moves the quality hold with it. The decision of a failed order is
    // recorded here and executed with "Execute Decision".
    Caption = 'Quality Order';
    PageType = Card;
    SourceTable = "DOPSWHS Quality Order";
    ApplicationArea = All;
    UsageCategory = None;
    DataCaptionFields = "No.", "Item Description";

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the number of the quality order. It is assigned automatically.';
                }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                    Editable = false;
                    StyleExpr = StatusStyle;
                    ToolTip = 'Specifies the inspection status. Use the Pass and Fail actions to record the result.';
                }
                field("Source Type"; Rec."Source Type")
                {
                    ApplicationArea = All;
                    Editable = IsOpen and (Rec."Source Table No." = 0);
                    ToolTip = 'Specifies what the inspection is for (receipt, assembly, manual, ...).';
                }
                field("Source No."; Rec."Source No.")
                {
                    ApplicationArea = All;
                    Editable = IsOpen and (Rec."Source Table No." = 0);
                    ToolTip = 'Specifies the source document (purchase order, assembly order, warehouse receipt).';
                }
                field("Source Line No."; Rec."Source Line No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the source document line that is inspected.';
                }
                field("Whse. Document No."; Rec."Whse. Document No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the warehouse receipt the inspection was created from.';
                }
                field("Posted Document No."; Rec."Posted Document No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the posted receipt or assembly that used this inspection. A later posting of the same line needs a new inspection.';
                }
                field("Due Date"; Rec."Due Date")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies when the inspection is due.';
                }
                field("Created DateTime"; Rec."Created DateTime")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies when the quality order was created.';
                }
            }
            group(Stock)
            {
                Caption = 'Inspected Stock';
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the inspected item.';

                    trigger OnValidate()
                    var
                        Item: Record Item;
                    begin
                        if Item.Get(Rec."Item No.") then
                            Rec."Item Description" := CopyStr(Item.Description, 1, MaxStrLen(Rec."Item Description"));
                        MoveHold();
                    end;
                }
                field("Item Description"; Rec."Item Description")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the description of the inspected item.';
                }
                field("Variant Code"; Rec."Variant Code")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the variant of the inspected item.';

                    trigger OnValidate()
                    begin
                        MoveHold();
                    end;
                }
                field("Lot No."; Rec."Lot No.")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the inspected lot. With Quality Lot Hold on, the lot is blocked until the order is passed.';

                    trigger OnValidate()
                    begin
                        MoveHold();
                    end;
                }
                field("Serial No."; Rec."Serial No.")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the inspected serial number.';

                    trigger OnValidate()
                    begin
                        MoveHold();
                    end;
                }
                field(OnHold; OnHold)
                {
                    ApplicationArea = All;
                    Caption = 'On Quality Hold';
                    Editable = false;
                    ToolTip = 'Specifies whether the lot/serial of the order is currently blocked by the quality hold.';
                }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the inspected quantity.';
                }
                field("Unit of Measure Code"; Rec."Unit of Measure Code")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the unit of measure of the quantity. Blank means the base unit of measure.';
                }
                field("Sample Size"; Rec."Sample Size")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies how many units are sampled.';
                }
                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the location of the inspected stock.';
                }
                field("Bin Code"; Rec."Bin Code")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the bin of the inspected stock.';

                    trigger OnLookup(var Text: Text): Boolean
                    begin
                        exit(QualityDecisionMgmt.LookupBin(Rec."Location Code", Text));
                    end;
                }
                field("LP No."; Rec."LP No.")
                {
                    ApplicationArea = All;
                    Editable = IsOpen;
                    ToolTip = 'Specifies the license plate of the inspected stock.';
                }
                field("Vendor No."; Rec."Vendor No.")
                {
                    ApplicationArea = All;
                    Editable = DecisionEditable or IsOpen;
                    ToolTip = 'Specifies the vendor of the inspected stock. A return to vendor decision creates the return order for this vendor.';
                }
            }
            group(Result)
            {
                Caption = 'Result';
                field(Inspector; Rec.Inspector)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies who recorded the result.';
                }
                field("Inspected DateTime"; Rec."Inspected DateTime")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies when the result was recorded.';
                }
                field("Result Notes"; Rec."Result Notes")
                {
                    ApplicationArea = All;
                    Editable = false;
                    MultiLine = true;
                    ToolTip = 'Specifies the inspector''s notes.';
                }
                field("Reject Reason"; Rec."Reject Reason")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies why the stock was rejected.';
                }
                field("Quarantine Bin"; Rec."Quarantine Bin")
                {
                    ApplicationArea = All;
                    Editable = IsOpen or DecisionEditable;
                    ToolTip = 'Specifies the only bin in which held stock of this order may be put away or moved.';

                    trigger OnLookup(var Text: Text): Boolean
                    begin
                        exit(QualityDecisionMgmt.LookupBin(Rec."Location Code", Text));
                    end;
                }
            }
            group(DecisionGroup)
            {
                Caption = 'Decision';
                Visible = IsFailed;
                field(Decision; Rec.Decision)
                {
                    ApplicationArea = All;
                    Editable = DecisionEditable;
                    ToolTip = 'Specifies what happens with the rejected stock: Scrap posts a negative adjustment, Return to Vendor creates a purchase return order, Rework opens a re-inspection, Accept with Deviation releases the stock.';
                }
                field("Decision Qty."; Rec."Decision Qty.")
                {
                    ApplicationArea = All;
                    Editable = DecisionEditable;
                    ToolTip = 'Specifies the quantity the decision applies to. Zero means the inspected quantity.';
                }
                field("Decision Reason Code"; Rec."Decision Reason Code")
                {
                    ApplicationArea = All;
                    Editable = DecisionEditable;
                    ToolTip = 'Specifies the reason code written on the scrap journal line.';
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

                    trigger OnDrillDown()
                    begin
                        QualityDecisionMgmt.ShowDecisionDocument(Rec);
                    end;
                }
                field("Decision By"; Rec."Decision By")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies who executed the decision.';
                }
                field("Decision DateTime"; Rec."Decision DateTime")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the decision was executed.';
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
                Enabled = IsOpen;
                ToolTip = 'Record a passed inspection. The quality hold of the lot is released.';

                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    QualityDecisionMgmt.PassWithDialog(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(FailOrder)
            {
                ApplicationArea = All;
                Caption = 'Fail';
                Image = Reject;
                Enabled = IsOpen;
                ToolTip = 'Record a failed inspection with a reason and quarantine bin. The lot stays blocked until a decision is executed.';

                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    QualityDecisionMgmt.FailWithDialog(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(ExecuteDecision)
            {
                ApplicationArea = All;
                Caption = 'Execute Decision';
                Image = PostOrder;
                Enabled = DecisionEditable;
                ToolTip = 'Execute the decision of the failed order: post the scrap, create the purchase return order, open a re-inspection or accept with deviation.';

                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
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
        SetControls();
    end;

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Source Type" := Rec."Source Type"::Manual;
        SetControls();
    end;

    local procedure SetControls()
    begin
        IsOpen := Rec.IsUndecided();
        IsFailed := Rec.Status = Rec.Status::Failed;
        DecisionEditable := IsFailed and not Rec."Decision Executed";
        OnHold := QualityLotHold.IsOnHold(Rec);
        StatusStyle := QualityDecisionMgmt.StatusStyle(Rec);
    end;

    // A new lot/serial on an open order takes over the quality hold; the old
    // one is released unless another order still holds it.
    local procedure MoveHold()
    begin
        if not IsOpen then
            exit;
        if (xRec."Item No." = Rec."Item No.") and (xRec."Variant Code" = Rec."Variant Code") and
           (xRec."Lot No." = Rec."Lot No.") and (xRec."Serial No." = Rec."Serial No.")
        then
            exit;
        if Rec."No." = '' then
            exit;
        QualityLotHold.ReleaseHold(xRec);
        QualityLotHold.ApplyHold(Rec);
        OnHold := QualityLotHold.IsOnHold(Rec);
    end;

    var
        QualityDecisionMgmt: Codeunit "DOPSWHS Quality Decision Mgmt";
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
        IsOpen: Boolean;
        IsFailed: Boolean;
        DecisionEditable: Boolean;
        OnHold: Boolean;
        StatusStyle: Text;
}
