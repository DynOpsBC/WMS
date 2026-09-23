page 72059 "DOPSWHS Bin LP Filter Results"
{
    Caption = 'Bulunan LP Kaydı';
    PageType = ListPart;
    SourceTable = "DOPSWHS LP Header";
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(LPs)
            {
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;
                    ToolTip = 'LP kartını açar. Bu kayıt, BC depo gözü stok satırından bağımsızdır.';

                    trigger OnDrillDown()
                    begin
                        Page.Run(Page::"DOPSWHS LP Card", Rec);
                    end;
                }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Line Count"; Rec."Line Count") { ApplicationArea = All; }
                field("Total Quantity"; Rec."Total Quantity")
                {
                    ApplicationArea = All;
                    ToolTip = 'LP satırlarında kayıtlı miktardır; BC raf stoğu olarak yorumlanmamalıdır.';
                }
                field(Contents; ContentsSummary)
                {
                    ApplicationArea = All;
                    Caption = 'LP İçeriği';
                    ToolTip = 'LP satırlarında kayıtlı ürün, miktar ve lot bilgisinin özetidir.';
                }
                field(BCBinContentStatus; BCBinContentStatus)
                {
                    ApplicationArea = All;
                    Caption = 'BC Raf Satırı';
                    ToolTip = 'LP satırlarından en az biri için aynı konum, raf, ürün, varyant ve ölçü biriminde BC Depo Gözü İçeriği satırı bulunup bulunmadığını gösterir.';
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        // The parent page supplies the searched LP number. Do not list every
        // LP in this part before the operator has entered a filter.
        Rec.SetRange("No.", '');
    end;

    trigger OnAfterGetRecord()
    var
        LPLine: Record "DOPSWHS LP Line";
        BinContent: Record "Bin Content";
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
    begin
        Rec.CalcFields("Line Count", "Total Quantity");
        ContentsSummary := BinContentSubscriber.GetLPContentSummary(Rec."No.");
        BCBinContentStatus := 'Yok';
        LPLine.SetRange("LP No.", Rec."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if BinContent.Get(Rec."Location Code", Rec."Bin Code", LPLine."Item No.",
                    LPLine."Variant Code", LPLine."Unit of Measure") then begin
                    BCBinContentStatus := 'Var';
                    exit;
                end;
            until LPLine.Next() = 0;
    end;

    procedure SetLPNo(LPNo: Code[20])
    begin
        Rec.SetRange("No.", LPNo);
        CurrPage.Update(false);
    end;

    var
        BCBinContentStatus: Text[10];
        ContentsSummary: Text[250];
}
