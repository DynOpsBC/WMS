page 72361 "DOPSWHS Packing Order List"
{
    PageType = List;
    Caption = 'Sipariş Paketleme';
    SourceTable = "DOPSWHS Packing Order";
    SourceTableView = where(Status = filter(Ready | "In Progress"));
    CardPageId = "DOPSWHS Packing Order Card";
    ApplicationArea = All;
    UsageCategory = Tasks;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Orders)
            {
                field("Sales Order No."; Rec."Sales Order No.") { ApplicationArea = All; StyleExpr = OrderStyle; }
                field("Customer Name"; Rec."Customer Name") { ApplicationArea = All; StyleExpr = OrderStyle; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Pick No."; Rec."Pick No.") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; StyleExpr = OrderStyle; }
                field("Started By User"; Rec."Started By User") { ApplicationArea = All; }
                field("Ready DateTime"; Rec."Ready DateTime") { ApplicationArea = All; }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec.Status = Rec.Status::Ready then
            OrderStyle := 'Favorable'
        else
            OrderStyle := 'Standard';
    end;

    var
        OrderStyle: Text;
}
