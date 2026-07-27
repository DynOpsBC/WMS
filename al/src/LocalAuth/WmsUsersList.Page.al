page 72361 "DOPSWHS WMS Users"
{
    PageType = List;
    SourceTable = User;
    Caption = 'WMS Users';
    ApplicationArea = All;
    UsageCategory = Lists;
    CardPageId = "DOPSWHS WMS User Card";
    SourceTableView = sorting("User Name") where("User Name" = filter('<>ADMIN'));

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("User Name"; Rec."User Name") { ApplicationArea = All; }
                field("Full Name"; Rec."Full Name") { ApplicationArea = All; }
                field("DOPSWHS WMS Role"; Rec."DOPSWHS WMS Role") { ApplicationArea = All; }
                field("License Type"; Rec."License Type") { ApplicationArea = All; Visible = false; }
                field("User State"; Rec."User State") { ApplicationArea = All; Visible = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(AssignWmsRole)
            {
                Caption = 'Assign WMS Role';
                Image = Setup;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Assign a WMS role to the selected user.';

                trigger OnAction()
                var
                    WmsRole: Record "DOPSWHS App Role";
                begin
                    if WmsRole.FindSet() then begin
                        if Page.RunModal(Page::"DOPSWHS App Role List", WmsRole) = Action::LookupOK then begin
                            Rec."DOPSWHS WMS Role" := WmsRole."Code";
                            Rec.Modify();
                            CurrPage.Update(false);
                        end;
                    end else begin
                        Message('No WMS roles defined. Please create roles in WMS App Roles page.');
                    end;
                end;
            }

            action(ClearWmsRole)
            {
                Caption = 'Clear WMS Role';
                Image = Delete;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Remove the WMS role assignment from the selected user.';

                trigger OnAction()
                begin
                    Rec."DOPSWHS WMS Role" := '';
                    Rec.Modify();
                    CurrPage.Update(false);
                end;
            }

            action(ViewActivityLog)
            {
                Caption = 'View Activity Log';
                Image = Ledger;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'View WMS activity log for this user.';

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
}
