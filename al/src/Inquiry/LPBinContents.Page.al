page 72058 "DOPSWHS LP Bin Contents"
{
    Caption = 'LP Raf İçeriği';
    PageType = List;
    SourceTable = "DOPSWHS LP Line";
    SourceTableView = sorting("LP No.", "Line No.") where(Quantity = filter(> 0), "Item No." = filter(<> ''), "LP Status" = filter(Open | Built | Assigned));
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("LP No."; Rec."LP No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;
                    trigger OnDrillDown()
                    var
                        LP: Record "DOPSWHS LP Header";
                    begin
                        LP.Get(Rec."LP No.");
                        Page.Run(Page::"DOPSWHS LP Card", LP);
                    end;
                }
                field("LP Location Code"; Rec."LP Location Code") { ApplicationArea = All; }
                field("LP Bin Code"; Rec."LP Bin Code") { ApplicationArea = All; }
                field("LP Status"; Rec."LP Status") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    Caption = 'LP Miktarı';
                    ToolTip = 'LP satırında kayıtlı miktardır. BC raf miktarı ayrı sütunda gösterilir.';
                }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Source Item Ledger Entry No."; Rec."Source Item Ledger Entry No.") { ApplicationArea = All; }
                field("Source Document No."; Rec."Source Document No.") { ApplicationArea = All; }
                field(HasBCBinContent; HasBCBinContent)
                {
                    ApplicationArea = All;
                    Caption = 'BC Raf Satırı Var';
                }
                field(BCBinQuantity; BCBinQuantity)
                {
                    ApplicationArea = All;
                    Caption = 'BC Raf Miktarı';
                    DecimalPlaces = 0 : 5;
                    ToolTip = 'Aynı konum, raf, ürün, varyant ve ölçü birimindeki toplam BC miktarıdır. Aynı stok satırını paylaşan LP satırlarında tekrarlanabilir; LP bazında ayrılmış miktar değildir.';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        BinContent: Record "Bin Content";
    begin
        Rec.CalcFields("LP Location Code", "LP Bin Code", "LP Status");
        Clear(BCBinQuantity);
        HasBCBinContent := BinContent.Get(
            Rec."LP Location Code", Rec."LP Bin Code", Rec."Item No.", Rec."Variant Code", Rec."Unit of Measure");
        if HasBCBinContent then begin
            BinContent.CalcFields(Quantity);
            BCBinQuantity := BinContent.Quantity;
        end;
    end;

    var
        HasBCBinContent: Boolean;
        BCBinQuantity: Decimal;
}
