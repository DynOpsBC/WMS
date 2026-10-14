page 72481 "DOPSWHS Count Sheet Line Part"
{
    Caption = 'Count Sheet Lines';
    PageType = ListPart;
    SourceTable = "DOPSWHS Count Sheet Line";
    ApplicationArea = All;
    AutoSplitKey = true;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                // Sayıldı: herhangi bir sayıcı slotuna miktar girildi mi?
                // Satır stili de buradan beslenir: sayıldı+fark yok = yeşil,
                // sayıldı+fark var = dikkat, sayılmadı = standart.
                field(Counted; CountedFlag)
                {
                    Caption = 'Sayıldı';
                    ApplicationArea = All;
                    Editable = false;
                    StyleExpr = LineStyle;
                }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; StyleExpr = LineStyle; }
                field(ItemDescription; ItemDescription)
                {
                    Caption = 'Description';
                    ApplicationArea = All;
                    Editable = false;
                    StyleExpr = LineStyle;
                }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; StyleExpr = LineStyle; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; StyleExpr = LineStyle; }
                field("Found From Bin"; Rec."Found From Bin") { ApplicationArea = All; ToolTip = 'LP farklı rafta sayıldığında sistemde kayıtlı olan raf. Ad-hoc sonrasında da ilk sayımın kaydı korunur.'; }
                field("Found LP Qty"; Rec."Found LP Qty") { ApplicationArea = All; }
                field("LP Line No."; Rec."LP Line No.") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
                field(PreviousSystemBin; PreviousSystemBin) { Caption = 'Önceki Tur Sistem Rafı'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousCountedBin; PreviousCountedBin) { Caption = 'Önceki Tur Sayılan Raf'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousSystemQty; PreviousSystemQty) { Caption = 'Önceki Tur Sistem Miktarı'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousQty1; PreviousQty1) { Caption = 'Önceki Tur Sayıcı 1'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousQty2; PreviousQty2) { Caption = 'Önceki Tur Sayıcı 2'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousQty3; PreviousQty3) { Caption = 'Önceki Tur Sayıcı 3'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousVariance; PreviousVariance) { Caption = 'Önceki Tur Stok Farkı'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field(PreviousFound; PreviousFound) { Caption = 'Önceki Turda Satır Var'; ApplicationArea = All; Editable = false; Visible = HasPreviousRound; }
                field("System Qty"; Rec."System Qty") { ApplicationArea = All; StyleExpr = LineStyle; }
                field("Counted Qty 1"; Rec."Counted Qty 1") { ApplicationArea = All; StyleExpr = LineStyle; }
                field("Counted Qty 2"; Rec."Counted Qty 2") { ApplicationArea = All; }
                field("Counted Qty 3"; Rec."Counted Qty 3") { ApplicationArea = All; }
                field(Variance; Rec.Variance) { ApplicationArea = All; StyleExpr = VarianceStyle; }
                field("Recount Required"; Rec."Recount Required") { ApplicationArea = All; StyleExpr = VarianceStyle; }
                field("Unexpected Stock"; Rec."Unexpected Stock") { ApplicationArea = All; StyleExpr = VarianceStyle; }
                field("Moved From Bin"; Rec."Moved From Bin") { ApplicationArea = All; ToolTip = 'Kayıtta bulunan stoğun taşındığı kaynak raf (Count Relocates Found Stock).'; }
                field("Moved Qty"; Rec."Moved Qty") { ApplicationArea = All; ToolTip = 'Kayıtta bu rafa taşınan miktar.'; }
                field("Line No."; Rec."Line No.") { ApplicationArea = All; Visible = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RefreshBin)
            {
                ApplicationArea = All;
                Caption = 'Bu Rafı Yenile';
                ToolTip = 'Sayım sürerken bu raftan mal alındıysa rafın sistem miktarlarını güncel stokla yeniler. Rafın bu turdaki sayımı silinir ve raf yeniden sayılır; diğer raflar ve önceki turlar korunur.';
                Image = Refresh;

                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                    LinesCreated: Integer;
                begin
                    Rec.TestField("Bin Code");
                    if not Confirm(RefreshBinQst, false, Rec."Bin Code") then
                        exit;
                    LinesCreated := CountMgmt.RefreshV2Bin(Rec."Sheet No.", Rec."Bin Code");
                    CurrPage.Update(false);
                    Message(RefreshBinDoneMsg, Rec."Bin Code", LinesCreated);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
    begin
        LoadPreviousRound();
        CountedFlag :=
            Rec."Counted 1" or Rec."Counted 2" or Rec."Counted 3" or
            (Rec."Counted Qty 1" <> 0) or (Rec."Counted Qty 2" <> 0) or (Rec."Counted Qty 3" <> 0);

        Clear(ItemDescription);
        if (Rec."Item No." <> '') and Item.Get(Rec."Item No.") then
            ItemDescription := Item.Description;

        // Fark: sayım girilmişse kazanan slotla anlık kıyas (post öncesi Variance
        // alanı henüz hesaplanmamış olabilir, o yüzden Counted Qty 1'e bakılır).
        if not CountedFlag then begin
            LineStyle := 'Standard';
            VarianceStyle := 'Subordinate';
        end else
            if (Rec.Variance <> 0) or (Rec."Counted Qty 1" <> Rec."System Qty") then begin
                LineStyle := 'Attention';
                VarianceStyle := 'Unfavorable';
            end else begin
                LineStyle := 'Favorable';
                VarianceStyle := 'Favorable';
            end;
        if CountedFlag and (Rec."Found From Bin" <> '') then
            LineStyle := 'Ambiguous';
        if Rec."Recount Required" then
            VarianceStyle := 'Unfavorable';
    end;

    local procedure LoadPreviousRound()
    var
        Header: Record "DOPSWHS Count Sheet Header";
        PreviousLine: Record "DOPSWHS Count Sheet Line";
    begin
        Clear(PreviousSystemQty);
        Clear(PreviousQty1);
        Clear(PreviousQty2);
        Clear(PreviousQty3);
        Clear(PreviousVariance);
        Clear(PreviousSystemBin);
        Clear(PreviousCountedBin);
        PreviousFound := false;
        HasPreviousRound := false;
        if not Header.Get(Rec."Sheet No.") then
            exit;
        HasPreviousRound := Header."Previous Round No." <> '';
        if not HasPreviousRound then
            exit;
        PreviousLine.SetRange("Sheet No.", Header."Previous Round No.");
        PreviousLine.SetRange("Item No.", Rec."Item No.");
        PreviousLine.SetRange("Variant Code", Rec."Variant Code");
        PreviousLine.SetRange("Unit of Measure Code", Rec."Unit of Measure Code");
        PreviousLine.SetRange("Lot No.", Rec."Lot No.");
        PreviousLine.SetRange("Serial No.", Rec."Serial No.");
        PreviousLine.SetRange("LP No.", Rec."LP No.");
        if Rec."LP No." = '' then
            PreviousLine.SetRange("Bin Code", Rec."Bin Code")
        else
            PreviousLine.SetRange("LP Line No.", Rec."LP Line No.");
        if PreviousLine.FindSet() then
            repeat
                PreviousFound := true;
                PreviousSystemQty += PreviousLine."System Qty";
                PreviousQty1 += PreviousLine."Counted Qty 1";
                PreviousQty2 += PreviousLine."Counted Qty 2";
                PreviousQty3 += PreviousLine."Counted Qty 3";
                PreviousVariance += PreviousLine.Variance;
                if PreviousLine."Found From Bin" <> '' then
                    PreviousSystemBin := PreviousLine."Found From Bin"
                else
                    if PreviousSystemBin = '' then
                        PreviousSystemBin := PreviousLine."Bin Code";
                if (PreviousLine."Counted Qty 1" > 0) or (PreviousLine."Counted Qty 2" > 0) or (PreviousLine."Counted Qty 3" > 0) then
                    PreviousCountedBin := PreviousLine."Bin Code";
            until PreviousLine.Next() = 0;
    end;

    var
        RefreshBinQst: Label '%1 rafının sistem miktarları güncel stokla yenilenecek ve bu turdaki sayımı silinecek. Raf yeniden sayılmalı. Devam edilsin mi?', Comment = '%1 bin code';
        RefreshBinDoneMsg: Label '%1 rafı yenilendi (%2 satır). Rafı terminalden yeniden sayın.', Comment = '%1 bin code, %2 line count';
        HasPreviousRound: Boolean;
        PreviousFound: Boolean;
        PreviousSystemQty: Decimal;
        PreviousQty1: Decimal;
        PreviousQty2: Decimal;
        PreviousQty3: Decimal;
        PreviousVariance: Decimal;
        PreviousSystemBin: Code[20];
        PreviousCountedBin: Code[20];
        CountedFlag: Boolean;
        ItemDescription: Text[100];
        LineStyle: Text;
        VarianceStyle: Text;
}
