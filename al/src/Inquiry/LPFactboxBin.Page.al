page 72078 "DOPSWHS LP Factbox Bin"
{
    PageType = ListPart;
    SourceTable = Integer;
    SourceTableView = where(Number = const(1));
    ApplicationArea = All;
    Caption = 'License Plates';

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("LP No."; LpNo) { ApplicationArea = All; Caption = 'LP No.'; }
                field("Bin Code"; BinCode) { ApplicationArea = All; Caption = 'Bin Code'; }
                field(Quantity; QuantityText) { ApplicationArea = All; Caption = 'Quantity'; }
                field(Status; StatusText) { ApplicationArea = All; Caption = 'Status'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        // Sprint 2: bind to LP Line table once created
        LpNo := '';
        BinCode := '';
        QuantityText := '';
        StatusText := '';
    end;

    var
        LpNo: Text[20];
        BinCode: Text[20];
        QuantityText: Text[30];
        StatusText: Text[30];
}
