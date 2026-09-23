page 72059 "DOPSWHS LP Bin Lines"
{
    Caption = 'LP İçindeki Maddeler';
    PageType = ListPart;
    SourceTable = "DOPSWHS LP Line";
    SourceTableView = sorting("LP No.", "Line No.") where(Quantity = filter(> 0), "Item No." = filter(<> ''), "LP Status" = filter(Open | Built | Assigned));
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    Caption = 'LP Miktarı';
                    ToolTip = 'LP satırının miktarıdır. BC raf stok miktarı değildir.';
                }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Source Item Ledger Entry No."; Rec."Source Item Ledger Entry No.") { ApplicationArea = All; }
                field("Source Document No."; Rec."Source Document No.") { ApplicationArea = All; }
            }
        }
    }

    trigger OnOpenPage()
    begin
        // The parent page sets one LP after its filter is validated. Until then,
        // do not display unrelated LP lines from other bins.
        Rec.SetRange("LP No.", '');
    end;

    procedure SetLPNo(LPNo: Code[20])
    begin
        Rec.SetRange("LP No.", LPNo);
        CurrPage.Update(false);
    end;
}
