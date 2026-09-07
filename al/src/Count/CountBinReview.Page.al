page 72060 "DOPSWHS Count Bin Review"
{
    Caption = 'Raf Farklarını İncele';
    PageType = List;
    SourceTable = "DOPSWHS Count Sheet Line";
    SourceTableView = sorting("Sheet No.", "Item No.", "Variant Code", "Lot No.", "Serial No.", "Unit of Measure Code", "Bin Code");
    Editable = false;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
                field("System Qty"; Rec."System Qty") { ApplicationArea = All; }
                field("Counted Qty 1"; Rec."Counted Qty 1") { ApplicationArea = All; }
                field("Counted Qty 2"; Rec."Counted Qty 2") { ApplicationArea = All; }
                field("Counted Qty 3"; Rec."Counted Qty 3") { ApplicationArea = All; }
                field(Variance; Rec.Variance) { ApplicationArea = All; }
                field(NetVariance; NetVariance) { Caption = 'Raflar Toplamı Stok Farkı'; ApplicationArea = All; }
                field("Recount Required"; Rec."Recount Required") { ApplicationArea = All; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Line: Record "DOPSWHS Count Sheet Line";
    begin
        Line.SetRange("Sheet No.", Rec."Sheet No.");
        Line.SetRange("Item No.", Rec."Item No.");
        Line.SetRange("Variant Code", Rec."Variant Code");
        Line.SetRange("Lot No.", Rec."Lot No.");
        Line.SetRange("Serial No.", Rec."Serial No.");
        Line.SetRange("Unit of Measure Code", Rec."Unit of Measure Code");
        Line.CalcSums(Variance);
        NetVariance := Line.Variance;
    end;

    var
        NetVariance: Decimal;
}
