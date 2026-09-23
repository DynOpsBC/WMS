pageextension 72301 "DOPSWHS Bin Card Ext" extends "Bin Contents"
{
    layout
    {
        addafter(ZoneCode)
        {
            field(DOPSWHSLPNoFilter; LpNoFilter)
            {
                ApplicationArea = All;
                Caption = 'LP No. Filtresi';
                ToolTip = 'LP numarasını girin. LP maddeleri ana tabloda ve LP bölümünde gösterilir. Eksik depo gözü/ürün satırı oluşturulabilir; BC Miktar yalnız gerçek depo hareketlerini gösterir.';

                trigger OnValidate()
                begin
                    ApplyLPFilter();
                end;
            }
            field(DOPSWHSLPLocationFilter; LpLocationFilter)
            {
                ApplicationArea = All;
                Caption = 'LP Konum Filtresi';
                ToolTip = 'LP maddelerini konuma göre daraltın. Depo gözü koduyla birlikte kullanın.';

                trigger OnValidate()
                begin
                    ApplyLPBinFilter();
                end;
            }
            field(DOPSWHSLPBinFilter; LpBinFilter)
            {
                ApplicationArea = All;
                Caption = 'LP Depo Gözü Filtresi';
                ToolTip = 'BC stok satırı olmasa da bu depo gözündeki aktif LP maddelerini gösterir.';

                trigger OnValidate()
                begin
                    ApplyLPBinFilter();
                end;
            }
            field(DOPSWHSLPListLink; LPListLink)
            {
                ApplicationArea = All;
                Caption = 'LP Listesi';
                Editable = false;
                DrillDown = true;
                ToolTip = 'Tüm LP''leri LP numarası, konum ve depo gözü alanlarına göre filtrelemek veya sıralamak için açın.';

                trigger OnDrillDown()
                begin
                    Page.Run(Page::"DOPSWHS LP List");
                end;
            }
            group(DOPSWHSLPResult)
            {
                Caption = 'Bulunan LP';
                Visible = ShowLPFilterResults;
                field(DOPSWHSLPFound; FoundLPNo)
                {
                    ApplicationArea = All;
                    Caption = 'LP No.';
                    Editable = false;
                    DrillDown = true;
                    trigger OnDrillDown()
                    var
                        LP: Record "DOPSWHS LP Header";
                    begin
                        if LP.Get(FoundLPNo) then
                            Page.Run(Page::"DOPSWHS LP Card", LP);
                    end;
                }
                field(DOPSWHSLPFoundBin; FoundLPBin)
                {
                    ApplicationArea = All;
                    Caption = 'Konum / Raf';
                    Editable = false;
                }
                field(DOPSWHSLPFoundContents; FoundLPContents)
                {
                    ApplicationArea = All;
                    Caption = 'LP İçeriği';
                    Editable = false;
                    DrillDown = true;
                    trigger OnDrillDown()
                    begin
                        OpenLPBinContents(FoundLPNo);
                    end;
                }
                field(DOPSWHSLPStockMatch; LPStockMatch)
                {
                    ApplicationArea = All;
                    Caption = 'Ana Tablo Satırı';
                    Editable = false;
                }
            }
            part(DOPSWHSLPLines; "DOPSWHS LP Bin Lines")
            {
                ApplicationArea = All;
                Visible = ShowLPBinLines;
            }
        }
        // The standard "Bin Contents" page shows its calculated quantity through
        // the CalcQtyUOM control; there is no control named Quantity.
        addafter(CalcQtyUOM)
        {
            field(DOPSWHSLPNos; Rec."DOPSWHS Current LP Nos")
            {
                ApplicationArea = All;
                Caption = 'Güncel LP No.ları';
                Editable = false;
                DrillDown = true;
                ToolTip = 'Bu sütundan LP numarasına göre filtreleyip sıralayın. Birden çok LP içeren satırları bulmak için *LP000123* gibi yıldızlı filtre kullanın. Yalnız bu satırdaki ürün, varyant ve ölçü birimiyle eşleşen pozitif LP satırları gösterilir. Raftaki tüm LP başlıkları için Raftaki LP''ler eylemini kullanın.';

                trigger OnDrillDown()
                begin
                    OpenActiveLPContents();
                end;
            }
            field(DOPSWHSLPQuantity; ActiveLpQuantity)
            {
                ApplicationArea = All;
                Caption = 'Güncel LP Miktarı';
                DecimalPlaces = 0 : 5;
                Editable = false;
                DrillDown = true;
                ToolTip = 'Tıklayarak toplam miktarın güncel LP bazında nasıl dağıldığını açın.';

                trigger OnDrillDown()
                begin
                    OpenActiveLPContents();
                end;
            }
        }
        addlast(FactBoxes)
        {
            part(DOPSWHSLPFactboxBin; "DOPSWHS LP Factbox Bin")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            action(DOPSWHSLPBinContents)
            {
                ApplicationArea = All;
                Caption = 'LP Raf İçeriği';
                ToolTip = 'Seçili depo gözündeki aktif LP maddelerini tam sayfada açar. LP veya LP depo gözü filtresi girildiyse onu kullanır; BC stok satırı gerekmez.';
                Image = List;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                begin
                    OpenLPBinContents(LpNoFilter);
                end;
            }
            action(DOPSWHSLPsInBin)
            {
                ApplicationArea = All;
                Caption = 'Raftaki LP''ler';
                ToolTip = 'Seçili satırın rafındaki tüm açık, tamamlanmış ve atanmış LP''leri gösterir. Boş LP''ler de listelenir.';
                Image = List;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    LPHeader: Record "DOPSWHS LP Header";
                begin
                    LPHeader.SetRange("Location Code", Rec."Location Code");
                    LPHeader.SetRange("Bin Code", Rec."Bin Code");
                    LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
                    Page.Run(Page::"DOPSWHS LP List", LPHeader);
                end;
            }
            action(DOPSWHSFindLP)
            {
                ApplicationArea = All;
                Caption = 'LP Numarasına Göre Ara';
                ToolTip = 'Tüm LP kayıtlarını açar. LP No., konum ve raf alanlarında filtreleme ve sıralama yapabilirsiniz; bu sayfadaki konum filtresi taşınmış LP''leri gizlemez.';
                Image = Find;
                Promoted = true;
                PromotedCategory = Process;
                RunObject = page "DOPSWHS LP List";
            }
            action(DOPSWHSFindLPMovements)
            {
                ApplicationArea = All;
                Caption = 'LP Hareketlerini Gör';
                ToolTip = 'LP hareket geçmişini açar. Tarih, LP No., kaynak raf ve hedef raf alanlarıyla taşınan LP''leri arayabilirsiniz.';
                Image = History;
                Promoted = true;
                PromotedCategory = Process;
                RunObject = page "DOPSWHS LP Movement Ledger";
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
    begin
        BinContentSubscriber.GetActiveLPItemInfo(
            Rec."Location Code", Rec."Bin Code", Rec."Item No.", Rec."Variant Code", Rec."Unit of Measure Code",
            ActiveLpNos, ActiveLpQuantity);
    end;

    trigger OnOpenPage()
    begin
        LPListLink := 'LP listesini aç / sırala';
    end;

    trigger OnAfterGetCurrRecord()
    begin
        if LpNoFilter <> '' then
            CurrPage.DOPSWHSLPFactboxBin.Page.SetScope(FoundLPLocation, FoundLPBinCode, FoundLPNo)
        else begin
            if LpBinFilter <> '' then
                CurrPage.DOPSWHSLPFactboxBin.Page.SetScope(LpLocationFilter, LpBinFilter, '')
            else
                CurrPage.DOPSWHSLPFactboxBin.Page.SetScope(Rec."Location Code", Rec."Bin Code", '');
            UpdateLPBinLines();
        end;
    end;

    local procedure OpenActiveLPContents()
    var
        ActiveLPContents: Page "DOPSWHS Active LP Contents";
    begin
        ActiveLPContents.LoadFromBin(
            Rec."Location Code", Rec."Bin Code", Rec."Item No.", Rec."Variant Code", Rec."Unit of Measure Code");
        ActiveLPContents.RunModal();
        // The summary is a page variable computed when the row was fetched; the
        // drill-down reads live data. Re-fetch the row so both agree after a
        // transfer done elsewhere (terminal) without waiting for F5.
        CurrPage.Update(false);
    end;

    local procedure ApplyLPFilter()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        BinLPIndex: Codeunit "DOPSWHS Bin LP Index";
        MatchedBinContent: Boolean;
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
    begin
        Rec.MarkedOnly(false);
        Rec.ClearMarks();
        if LpNoFilter = '' then begin
            ShowLPFilterResults := false;
            Clear(FoundLPNo);
            Clear(FoundLPBin);
            Clear(FoundLPLocation);
            Clear(FoundLPBinCode);
            Clear(FoundLPContents);
            Clear(LPStockMatch);
            CurrPage.Update(false);
            UpdateLPBinLines();
            exit;
        end;

        if not LP.Get(LpNoFilter) then
            Error('%1 LP numarası bulunamadı.', LpNoFilter);
        BinLPIndex.EnsureLPItemRows(LP);
        ShowLPFilterResults := true;
        FoundLPNo := LP."No.";
        FoundLPBin := LP."Location Code" + ' / ' + LP."Bin Code";
        FoundLPLocation := LP."Location Code";
        FoundLPBinCode := LP."Bin Code";
        FoundLPContents := BinContentSubscriber.GetLPContentSummary(LP."No.");
        LPStockMatch := 'Yok';
        Clear(LastLPLocationScope);
        Clear(LastLPBinScope);
        CurrPage.DOPSWHSLPFactboxBin.Page.SetScope(FoundLPLocation, FoundLPBinCode, FoundLPNo);
        ShowLPBinLines := true;
        CurrPage.Update(false);
        ShowLPBinLines := CurrPage.DOPSWHSLPLines.Page.SetScope('', '', FoundLPNo);

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if Rec.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                    LPLine."Variant Code", LPLine."Unit of Measure") then begin
                    Rec.Mark(true);
                    MatchedBinContent := true;
                    LPStockMatch := 'Var; BC miktarı ayrı';
                end else
                    if (LPLine."Unit of Measure" <> '') and
                       Rec.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                           LPLine."Variant Code", '') then begin
                        Rec.Mark(true);
                        MatchedBinContent := true;
                        LPStockMatch := 'Var; BC miktarı ayrı';
                    end;
            until LPLine.Next() = 0;

        Rec.MarkedOnly(true);
        if not MatchedBinContent or Rec.IsEmpty() then begin
            // Keep the entered filter and its stock result consistent. The
            // independent LP summary remains visible even if no stock matches.
            if MatchedBinContent then
                LPStockMatch := 'Var; mevcut liste filtreleri gizliyor'
            else
                LPStockMatch := 'Yok; LP içeriği yukarıda gösterilir';
            CurrPage.Update(false);
            exit;
        end;
        CurrPage.Update(false);
    end;

    local procedure ApplyLPBinFilter()
    begin
        if LpNoFilter <> '' then begin
            LpNoFilter := '';
            Rec.MarkedOnly(false);
            Rec.ClearMarks();
            ShowLPFilterResults := false;
            Clear(FoundLPNo);
            Clear(FoundLPBin);
            Clear(FoundLPLocation);
            Clear(FoundLPBinCode);
            Clear(FoundLPContents);
            Clear(LPStockMatch);
        end;
        Clear(LastLPLocationScope);
        Clear(LastLPBinScope);
        UpdateLPBinLines();
        if LpBinFilter <> '' then
            CurrPage.DOPSWHSLPFactboxBin.Page.SetScope(LpLocationFilter, LpBinFilter, '');
        CurrPage.Update(false);
    end;

    local procedure UpdateLPBinLines()
    var
        ScopeLocation: Code[10];
        ScopeBin: Code[20];
    begin
        if LpNoFilter <> '' then
            exit;
        if LpBinFilter <> '' then begin
            ScopeLocation := LpLocationFilter;
            ScopeBin := LpBinFilter;
        end else begin
            ScopeLocation := Rec."Location Code";
            ScopeBin := Rec."Bin Code";
            if LpLocationFilter <> '' then
                ScopeLocation := LpLocationFilter;
        end;
        if (ScopeLocation = LastLPLocationScope) and (ScopeBin = LastLPBinScope) then
            exit;
        LastLPLocationScope := ScopeLocation;
        LastLPBinScope := ScopeBin;
        ShowLPBinLines := ScopeBin <> '';
        ShowLPBinLines := CurrPage.DOPSWHSLPLines.Page.SetScope(ScopeLocation, ScopeBin, '');
    end;

    local procedure OpenLPBinContents(LPNo: Code[20])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if LPNo <> '' then
            LPLine.SetRange("LP No.", LPNo)
        else
            if LpBinFilter <> '' then begin
                LPLine.SetRange("LP Bin Code", LpBinFilter);
                if LpLocationFilter <> '' then
                    LPLine.SetRange("LP Location Code", LpLocationFilter);
            end else
                if Rec."Bin Code" <> '' then begin
                    LPLine.SetRange("LP Location Code", Rec."Location Code");
                    LPLine.SetRange("LP Bin Code", Rec."Bin Code");
                end;
        Page.Run(Page::"DOPSWHS LP Bin Contents", LPLine);
    end;

    var
        ActiveLpNos: Text[250];
        ActiveLpQuantity: Decimal;
        LpNoFilter: Code[20];
        LpLocationFilter: Code[10];
        LpBinFilter: Code[20];
        LPListLink: Text[50];
        ShowLPFilterResults: Boolean;
        ShowLPBinLines: Boolean;
        LastLPLocationScope: Code[10];
        LastLPBinScope: Code[20];
        FoundLPNo: Code[20];
        FoundLPBin: Text[50];
        FoundLPLocation: Code[10];
        FoundLPBinCode: Code[20];
        FoundLPContents: Text[250];
        LPStockMatch: Text[80];
}
