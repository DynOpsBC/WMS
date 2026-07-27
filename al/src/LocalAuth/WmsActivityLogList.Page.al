page 72361 "DOPSWHS WMS Activity Log"
{
    PageType = List;
    SourceTable = "DOPSWHS WMS Activity Log";
    Caption = 'WMS Activity Log';
    ApplicationArea = All;
    UsageCategory = Lists;
    CardPageId = "DOPSWHS WMS Activity Card";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(Timestamp; Rec.Timestamp) { ApplicationArea = All; }
                field("Local User"; Rec."Local User") { ApplicationArea = All; }
                field("User Display Name"; Rec."User Display Name") { ApplicationArea = All; }
                field(Action; Rec.Action) { ApplicationArea = All; }
                field("Action Status"; Rec."Action Status") { ApplicationArea = All; StyleExpr = StatusStyle; }
                field("Document Type"; Rec."Document Type") { ApplicationArea = All; }
                field("Document No."; Rec."Document No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ExportToExcel)
            {
                Caption = 'Export to Excel';
                Image = Export;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    // Standard XLSX export via System.IO / EPPlus (would require additional configuration)
                    // For now, user can use "Copy to Excel" from standard BC export menu
                    Message('Use "Copy to Excel" from the standard menu to export this data.');
                end;
            }
            action(ClearLog)
            {
                Caption = 'Clear Activity Log';
                Image = Delete;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Delete all activity log entries older than 90 days.';

                trigger OnAction()
                var
                    ActivityLog: Record "DOPSWHS WMS Activity Log";
                    CutoffDate: DateTime;
                    DeletedCount: Integer;
                begin
                    if Dialog.Confirm('Delete activity log entries older than 90 days?', true) then
                    begin
                        CutoffDate := CurrentDateTime - 90;
                        ActivityLog.SetFilter(Timestamp, '<%1', CutoffDate);
                        DeletedCount := ActivityLog.Count();
                        if DeletedCount > 0 then
                        begin
                            ActivityLog.DeleteAll();
                            Message('Deleted %1 old activity log entries.', DeletedCount);
                        end
                        else
                            Message('No old entries to delete.');
                    end;
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec."Action Status" of
            Rec."Action Status"::Success:
                StatusStyle := 'Favorable';
            Rec."Action Status"::Fail:
                StatusStyle := 'Unfavorable';
            Rec."Action Status"::Timeout:
                StatusStyle := 'Ambiguous';
        end;
    end;

    var
        StatusStyle: Text;
}
