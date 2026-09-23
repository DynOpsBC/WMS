page 72059 "DOPSWHS LP Bin Lines"
{
    Caption = 'Raftaki LP Maddeleri';
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
                field("LP Location Code"; Rec."LP Location Code") { ApplicationArea = All; }
                field("LP Bin Code"; Rec."LP Bin Code") { ApplicationArea = All; }
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
        // Wait for the parent to supply a selected bin or LP number. Never show
        // unrelated lines from the whole company while the page first opens.
        Rec.SetRange("LP No.", '');
    end;

    procedure SetScope(LocationCode: Code[10]; BinCode: Code[20]; LPNo: Code[20]): Boolean
    begin
        Rec.SetRange("LP No.");
        Rec.SetRange("LP Location Code");
        Rec.SetRange("LP Bin Code");
        if LPNo <> '' then
            Rec.SetRange("LP No.", LPNo)
        else
            if BinCode <> '' then begin
                Rec.SetRange("LP Bin Code", BinCode);
                if LocationCode <> '' then
                    Rec.SetRange("LP Location Code", LocationCode);
            end else
                Rec.SetRange("LP No.", '');
        CurrPage.Update(false);
        exit(not Rec.IsEmpty());
    end;
}
