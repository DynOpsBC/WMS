page 72470 "DOPSWHS EDesp Requests"
{
    Caption = 'E-Despatch Requests (WMS)';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "DOPSWHS EDesp Request";
    SourceTableView = sorting("Entry No.") order(descending);
    CardPageId = "DOPSWHS EDesp Request Card";
    Editable = false;
    InsertAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; ToolTip = 'Specifies the request no.'; }
                field("Source Type"; Rec."Source Type") { ApplicationArea = All; ToolTip = 'Specifies the posted or registered document type.'; }
                field("Source No."; Rec."Source No.") { ApplicationArea = All; ToolTip = 'Specifies the posted or registered document no.'; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; ToolTip = 'Specifies the location the goods leave.'; }
                field("To Location Code"; Rec."To Location Code") { ApplicationArea = All; ToolTip = 'Specifies the target location.'; }
                field("To Bin Code"; Rec."To Bin Code") { ApplicationArea = All; ToolTip = 'Specifies the target bin.'; }
                field("Receiver Name"; Rec."Receiver Name") { ApplicationArea = All; ToolTip = 'Specifies the receiver of the e-despatch.'; }
                field(Purpose; Rec.Purpose) { ApplicationArea = All; ToolTip = 'Specifies the despatch purpose.'; }
                field(Status; Rec.Status) { ApplicationArea = All; StyleExpr = StatusStyle; ToolTip = 'Specifies the status of the e-despatch.'; }
                field("Provider Document No."; Rec."Provider Document No.") { ApplicationArea = All; ToolTip = 'Specifies the e-despatch no.'; }
                field("Last Error"; Rec."Last Error") { ApplicationArea = All; ToolTip = 'Specifies the last error.'; }
                field("Skip Reason"; Rec."Skip Reason") { ApplicationArea = All; ToolTip = 'Specifies why no e-despatch is needed.'; }
                field("Operator User Id"; Rec."Operator User Id") { ApplicationArea = All; ToolTip = 'Specifies the handheld operator.'; }
                field("Created At"; Rec."Created At") { ApplicationArea = All; ToolTip = 'Specifies when the request was created.'; }
                field("Print Count"; Rec."Print Count") { ApplicationArea = All; ToolTip = 'Specifies how often the e-despatch was printed.'; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Retry)
            {
                ApplicationArea = All;
                Caption = 'Retry';
                Image = Refresh;
                ToolTip = 'Asks the e-despatch provider again to build the draft of the selected request.';

                trigger OnAction()
                var
                    RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
                begin
                    if Rec.Status in [Rec.Status::Error, Rec.Status::WaitingAdapter] then begin
                        Rec.Status := Rec.Status::Pending;
                        Rec.Modify(true);
                    end;
                    RequestMgt.EnsureDraft(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(RefreshStatus)
            {
                ApplicationArea = All;
                Caption = 'Refresh Status';
                Image = RefreshLines;
                ToolTip = 'Reads the current e-despatch status from the provider.';

                trigger OnAction()
                var
                    RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
                begin
                    RequestMgt.RefreshStatus(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
        area(Promoted)
        {
            actionref(Retry_Promoted; Retry) { }
            actionref(RefreshStatus_Promoted; RefreshStatus) { }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec.Status of
            Rec.Status::Error, Rec.Status::Rejected:
                StatusStyle := 'Unfavorable';
            Rec.Status::Sent, Rec.Status::Accepted:
                StatusStyle := 'Favorable';
            Rec.Status::WaitingAdapter, Rec.Status::Pending:
                StatusStyle := 'Ambiguous';
            else
                StatusStyle := 'Standard';
        end;
    end;

    var
        StatusStyle: Text;
}
