page 72357 "DOPSWHS Picking Order List"
{
    PageType = List;
    Caption = 'Toplanacak Siparişler';
    SourceTable = "DOPSWHS Picking Order Header";
    CardPageId = "DOPSWHS Picking Order Card";
    ApplicationArea = All;
    UsageCategory = Tasks;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Headers)
            {
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; StyleExpr = StatusStyle; }
                field("Assigned User ID"; Rec."Assigned User ID") { ApplicationArea = All; }
                field("Warehouse Pick No."; Rec."Warehouse Pick No.") { ApplicationArea = All; }
                field("Warehouse Shipment No."; Rec."Warehouse Shipment No.") { ApplicationArea = All; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewPickingOrder)
            {
                Caption = 'Yeni Toplama Grubu';
                ApplicationArea = All;
                Image = NewDocument;
                Promoted = true;
                PromotedCategory = New;
                RunObject = page "DOPSWHS Picking Order Card";
                RunPageMode = Create;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec.Status of
            Rec.Status::Open:
                StatusStyle := 'Unfavorable';
            Rec.Status::"Pick Created":
                StatusStyle := 'Ambiguous';
            Rec.Status::Completed:
                StatusStyle := 'Favorable';
        end;
    end;

    var
        StatusStyle: Text;
}
