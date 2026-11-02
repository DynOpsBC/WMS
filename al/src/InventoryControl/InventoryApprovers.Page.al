page 72007 "DOPSWHS Inventory Approvers"
{
    // KIT-014 / KIT-015 (Kitoko, Kas 2026): authorized users for count
    // variances above tolerance and for item reclassification journals.
    Caption = 'Inventory Control Approvers';
    PageType = List;
    SourceTable = "DOPSWHS Inventory Approver";
    ApplicationArea = All;
    UsageCategory = Administration;
    AboutTitle = 'Inventory control approvers';
    AboutText = 'Users listed here may approve count variances above the count tolerance and post item reclassification journals. The list is only used when Count Tolerance Check = Approval Required or Reclass Posting Restricted is switched on in Advanced WMS Setup.';

    layout
    {
        area(Content)
        {
            repeater(Approvers)
            {
                field("User ID"; Rec."User ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the Business Central user.';
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies a description, for example the role of the user.';
                }
                field("Approve Count Variance"; Rec."Approve Count Variance")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies that the user may approve count variances above the count tolerance and post such phys. inventory journals.';
                }
                field("Approve Reclassification"; Rec."Approve Reclassification")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies that the user may post item reclassification journals when reclass posting is restricted.';
                }
            }
        }
    }
}
