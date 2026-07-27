page 72362 "DOPSWHS WMS User Card"
{
    PageType = Card;
    SourceTable = User;
    Caption = 'WMS User Card';
    ApplicationArea = All;
    DeleteAllowed = false;
    InsertAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';

                field("User Name"; Rec."User Name") { ApplicationArea = All; Editable = false; }
                field("Full Name"; Rec."Full Name") { ApplicationArea = All; Editable = false; }
                field("Authentication Email"; Rec."Authentication Email") { ApplicationArea = All; Editable = false; }
                field("User State"; Rec."User State") { ApplicationArea = All; Editable = false; }
                field("License Type"; Rec."License Type") { ApplicationArea = All; Editable = false; }
            }

            group(WMS)
            {
                Caption = 'WMS Settings';

                field("DOPSWHS WMS Role"; Rec."DOPSWHS WMS Role")
                {
                    ApplicationArea = All;
                    ToolTip = 'Assign a WMS role to this user for warehouse operations access.';
                }
            }
        }

        area(FactBoxes)
        {
            part(ActivityLogFactbox; "DOPSWHS WMS Activity Card")
            {
                ApplicationArea = All;
                SubPageLink = "Local User" = field("User Name");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ViewFullActivityLog)
            {
                Caption = 'View Full Activity Log';
                Image = Ledger;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'View complete WMS activity log for this user.';

                trigger OnAction()
                var
                    ActivityLog: Record "DOPSWHS WMS Activity Log";
                begin
                    ActivityLog.FilterGroup(2);
                    ActivityLog.SetRange("Local User", Rec."User Name");
                    ActivityLog.FilterGroup(0);
                    Page.Run(Page::"DOPSWHS WMS Activity Log", ActivityLog);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        // Page initialization
    end;
}
