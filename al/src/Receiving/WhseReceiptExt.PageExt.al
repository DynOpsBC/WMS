pageextension 72303 "DOPSWHS Whse Receipt Ext" extends "Warehouse Receipt"
{
    layout
    {
        addlast(FactBoxes)
        {
            group("DOPSWHS Mobile")
            {
                Caption = 'DOPSWHS Mobile';
                field("DOPSWHS Assigned User"; Rec."Assigned User ID")
                {
                    ApplicationArea = All;
                    Caption = 'Assigned User';
                }
                field("DOPSWHS Percent Complete"; PercentComplete)
                {
                    ApplicationArea = All;
                    Caption = '% Complete';
                    ExtendedDatatype = Ratio;
                    Editable = false;
                }
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

                action("DOPSWHS Start LP")
                {
                    ApplicationArea = All;
                    Caption = 'Start LP';
                    trigger OnAction()
                    var
                        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
                        LpNo: Code[20];
                    begin
                        LpNo := ReceiptMgmt.StartLP(Rec, 'PALLET-EUR');
                        Message('License Plate %1 started.', LpNo);
                    end;
                }

                action("DOPSWHS Stop LP")
                {
                    ApplicationArea = All;
                    Caption = 'Stop LP';
                    trigger OnAction()
                    var
                        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
                        LpNo: Code[20];
                    begin
                        LpNo := AskLpNo();
                        if LpNo = '' then
                            exit;
                        ReceiptMgmt.StopLP(Rec, LpNo, true);
                        Message('License Plate %1 stopped and label was sent.', LpNo);
                    end;
                }

                action("DOPSWHS Assign User")
                {
                    ApplicationArea = All;
                    Caption = 'Assign to User';
                    trigger OnAction()
                    var
                        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
                        AssignedUserId: Code[50];
                    begin
                        AssignedUserId := PickUser();
                        if AssignedUserId = '' then
                            exit;
                        ReceiptMgmt.AssignUser(Rec, AssignedUserId);
                        CurrPage.Update(false);
                    end;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        PercentComplete := CalcPercentComplete();
    end;

    var
        PercentComplete: Integer;

    local procedure CalcPercentComplete(): Integer
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        TotalQty: Decimal;
        ReceivedQty: Decimal;
    begin
        WhseReceiptLine.SetRange("No.", Rec."No.");
        if WhseReceiptLine.FindSet() then
            repeat
                TotalQty += WhseReceiptLine.Quantity;
                ReceivedQty += WhseReceiptLine."Qty. Received";
            until WhseReceiptLine.Next() = 0;

        if TotalQty = 0 then
            exit(0);
        exit(Round(ReceivedQty / TotalQty * 100, 1));
    end;

    local procedure PickUser(): Code[50]
    var
        User: Record User;
    begin
        if Page.RunModal(Page::"User Lookup", User) = Action::LookupOK then
            exit(User."User Name");
        exit('');
    end;

    local procedure AskLpNo(): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if Page.RunModal(Page::"DOPSWHS LP List", LP) = Action::LookupOK then
            exit(LP."No.");
        exit('');
    end;
}
