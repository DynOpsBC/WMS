page 72008 "DOPSWHS Work Orders"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Work Orders';
    PageType = List;
    SourceTable = "DOPSWHS Work Order";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "DOPSWHS Work Order Card";

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Asset No."; Rec."Asset No.") { ApplicationArea = All; }
                field("Maintenance Type"; Rec."Maintenance Type") { ApplicationArea = All; }
                field(Priority; Rec.Priority) { ApplicationArea = All; }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                    StyleExpr = StatusStyleExpr;
                }
                field("Assigned To"; Rec."Assigned To") { ApplicationArea = All; }
                field("Opened At"; Rec."Opened At") { ApplicationArea = All; }
                field("Target Resolution By"; Rec."Target Resolution By") { ApplicationArea = All; }
                field("SLA Breached"; Rec."SLA Breached")
                {
                    ApplicationArea = All;
                    StyleExpr = StatusStyleExpr;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(AssignToMe)
            {
                Caption = 'Assign to Me';
                Image = AssignUser;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Open;

                trigger OnAction()
                var
                    WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
                begin
                    WorkOrderSvc.Assign(Rec, CopyStr(UserId(), 1, 50));
                    CurrPage.Update(false);
                end;
            }
            action(StartAction)
            {
                Caption = 'Start';
                Image = Start;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status in [Rec.Status::Assigned, Rec.Status::"Waiting Parts"];

                trigger OnAction()
                var
                    WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
                begin
                    WorkOrderSvc.Start(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec."SLA Breached" then
            StatusStyleExpr := 'Unfavorable'
        else
            case Rec.Status of
                Rec.Status::Closed, Rec.Status::Completed:
                    StatusStyleExpr := 'Favorable';
                Rec.Status::Cancelled:
                    StatusStyleExpr := 'Subordinate';
                else
                    StatusStyleExpr := 'Ambiguous';
            end;
    end;

    var
        StatusStyleExpr: Text;
}
