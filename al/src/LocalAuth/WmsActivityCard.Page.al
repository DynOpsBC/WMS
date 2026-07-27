page 72362 "DOPSWHS WMS Activity Card"
{
    PageType = Card;
    SourceTable = "DOPSWHS WMS Activity Log";
    Caption = 'WMS Activity Details';
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field(Timestamp; Rec.Timestamp) { ApplicationArea = All; }
                field("Local User"; Rec."Local User") { ApplicationArea = All; }
                field("User Display Name"; Rec."User Display Name") { ApplicationArea = All; }
            }
            group(Action)
            {
                Caption = 'Action';
                field(Action; Rec.Action) { ApplicationArea = All; }
                field("Action Status"; Rec."Action Status") { ApplicationArea = All; StyleExpr = StatusStyle; }
            }
            group(Document)
            {
                Caption = 'Document';
                field("Document Type"; Rec."Document Type") { ApplicationArea = All; }
                field("Document No."; Rec."Document No.") { ApplicationArea = All; }
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
            }
            group(Item)
            {
                Caption = 'Item';
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
            }
            group(Details)
            {
                Caption = 'Details (JSON)';
                field(Details; Rec.Details)
                {
                    ApplicationArea = All;
                    MultiLine = true;
                }
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
