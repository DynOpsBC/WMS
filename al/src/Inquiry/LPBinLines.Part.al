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
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    Caption = 'LP Miktarı';
                    ToolTip = 'LP satırının miktarıdır. BC raf stok miktarı değildir.';
                }
                field(BCBinQuantity; BCBinQuantity)
                {
                    ApplicationArea = All;
                    Caption = 'BC Raf Miktarı';
                    DecimalPlaces = 0 : 5;
                    ToolTip = 'Aynı raftaki ürünün toplam BC miktarıdır; birden çok LP bu stoku paylaşabilir. Sıfırsa LP kaydı tek başına üretim tüketimine stok sağlamaz.';
                }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        BinContent: Record "Bin Content";
    begin
        Rec.CalcFields("LP Location Code", "LP Bin Code");
        Clear(BCBinQuantity);
        if BinContent.Get(Rec."LP Location Code", Rec."LP Bin Code", Rec."Item No.",
            Rec."Variant Code", Rec."Unit of Measure") then begin
            BinContent.CalcFields(Quantity);
            BCBinQuantity := BinContent.Quantity;
        end;
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

    var
        BCBinQuantity: Decimal;
}
