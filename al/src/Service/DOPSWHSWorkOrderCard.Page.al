page 72010 "DOPSWHS Work Order Card"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Work Order Card';
    PageType = Card;
    SourceTable = "DOPSWHS Work Order";
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; Editable = false; }
                field("Asset No."; Rec."Asset No.") { ApplicationArea = All; }
                field("Contract No."; Rec."Contract No.") { ApplicationArea = All; }
                field("Maintenance Type"; Rec."Maintenance Type") { ApplicationArea = All; }
                field("Fault Code"; Rec."Fault Code") { ApplicationArea = All; }
                field(Priority; Rec.Priority) { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; Editable = false; }
                field("Assigned To"; Rec."Assigned To") { ApplicationArea = All; }
            }
            group(Timing)
            {
                Caption = 'SLA Timing';
                field("Opened At"; Rec."Opened At") { ApplicationArea = All; Editable = false; }
                field("Target Response By"; Rec."Target Response By") { ApplicationArea = All; Editable = false; }
                field("Responded At"; Rec."Responded At") { ApplicationArea = All; Editable = false; }
                field("Target Resolution By"; Rec."Target Resolution By") { ApplicationArea = All; Editable = false; }
                field("Closed At"; Rec."Closed At") { ApplicationArea = All; Editable = false; }
                field("SLA Breached"; Rec."SLA Breached") { ApplicationArea = All; Editable = false; }
                field("Downtime Minutes"; Rec."Downtime Minutes") { ApplicationArea = All; }
            }
            group(Resolution)
            {
                Caption = 'Resolution';
                field("Root Cause"; Rec."Root Cause") { ApplicationArea = All; }
                field("Resolution Notes"; Rec."Resolution Notes") { ApplicationArea = All; }
            }
            part(Lines; "DOPSWHS Work Order Subform")
            {
                ApplicationArea = All;
                SubPageLink = "Work Order No." = field("No.");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(CompleteAction)
            {
                Caption = 'Complete';
                Image = Approve;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::"In Progress";

                trigger OnAction()
                var
                    WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
                begin
                    CurrPage.SaveRecord();
                    WorkOrderSvc.Complete(Rec, Rec."Root Cause", Rec."Resolution Notes");
                    CurrPage.Update(false);
                end;
            }
            action(CloseAction)
            {
                Caption = 'Close';
                Image = Close;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Completed;

                trigger OnAction()
                var
                    WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
                begin
                    WorkOrderSvc.Close(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
    }
}
