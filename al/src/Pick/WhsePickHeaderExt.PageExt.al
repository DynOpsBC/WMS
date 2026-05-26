pageextension 72311 "DOPSWHS Whse Pick Header Ext" extends "Warehouse Pick"
{
    layout
    {
        addlast(General)
        {
            field("DOPSWHS Assigned User"; Rec."Assigned User ID")
            {
                ApplicationArea = All;
                Caption = 'Assigned User';
                ToolTip = 'Specifies the mobile user assigned to this pick.';
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            group("DOPSWHS Mobile")
            {
                Caption = 'DOPSWHS Mobile';
                action("DOPSWHS Start Shipping LP")
                {
                    ApplicationArea = All;
                    Caption = 'Start Shipping LP';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                    begin
                        Message('Started LP %1.', PickMgmt.StartShippingLP(Rec, 'PALLET-EUR'));
                    end;
                }
                action("DOPSWHS Stop Shipping LP")
                {
                    ApplicationArea = All;
                    Caption = 'Stop Shipping LP';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                        LP: Record "DOPSWHS LP Header";
                        LpNo: Code[20];
                    begin
                        if Page.RunModal(Page::"DOPSWHS LP List", LP) <> Action::LookupOK then
                            exit;
                        LpNo := LP."No.";
                        Message('SSCC %1.', PickMgmt.StopShippingLP(Rec, LpNo, true));
                    end;
                }
                action("DOPSWHS Reassign to User")
                {
                    ApplicationArea = All;
                    Caption = 'Reassign to User';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                        User: Record User;
                    begin
                        if Page.RunModal(Page::"User Lookup", User) <> Action::LookupOK then
                            exit;
                        PickMgmt.ReassignPick(Rec, User."User Name", 'Manual page action');
                    end;
                }
                action("DOPSWHS Mark Short")
                {
                    ApplicationArea = All;
                    Caption = 'Mark Short';
                    trigger OnAction()
                    begin
                        Page.Run(Page::"DOPSWHS Short Pick Reason List");
                    end;
                }
            }
        }
    }
}
