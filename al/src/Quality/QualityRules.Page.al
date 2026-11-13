page 72006 "DOPSWHS Quality Rules"
{
    // KIT-009 / INV-009 (Kitoko, Kas 2026): where an inspection is mandatory.
    Caption = 'Quality Inspection Rules';
    PageType = List;
    SourceTable = "DOPSWHS Quality Rule";
    ApplicationArea = All;
    UsageCategory = Administration;
    AboutTitle = 'Quality inspection rules';
    AboutText = 'Each rule makes an inspection mandatory for purchase receipts or assembly outputs of a location, item category (including its sub-categories), item or vendor. Blank fields match everything; the most specific rule wins. The rules take effect when Receipt Quality Gate / Assembly Quality Gate is switched on in Advanced WMS Setup.';

    layout
    {
        area(Content)
        {
            repeater(Rules)
            {
                field("Source Type"; Rec."Source Type")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the posting the rule guards: purchase receipt or assembly output.';
                }
                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the location the rule applies to. Blank means all locations.';
                }
                field("Item Category Code"; Rec."Item Category Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the item category the rule applies to, including its sub-categories. Blank means all categories.';
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the item the rule applies to. Blank means all items.';
                }
                field("Vendor No."; Rec."Vendor No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the vendor the rule applies to (purchase receipts only). Blank means all vendors.';
                }
                field(Timing; Rec.Timing)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the inspection takes place. Before Posting: the receipt cannot be posted until the inspection has a result. After Posting: posting the receipt creates the inspection and the received lot stays on quality hold until it is passed.';
                }
                field("Create Automatically"; Rec."Create Automatically")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies that the quality order is created automatically: for purchase receipts (Before Posting) when the warehouse receipt line is created, for assembly outputs when the assembly order is released. Otherwise use Create Quality Orders / Create Final Inspection on the document.';
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies a description of the rule.';
                }
                field(Enabled; Rec.Enabled)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether the rule is used.';
                }
            }
        }
    }

    actions
    {
        area(Navigation)
        {
            action(QualityOrders)
            {
                ApplicationArea = All;
                Caption = 'Quality Orders';
                Image = TaskQualityMeasure;
                RunObject = page "DOPSWHS Quality Orders";
                ToolTip = 'Open the quality orders.';
            }
        }
    }
}
