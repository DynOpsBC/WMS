pageextension 72301 "DOPSWHS Bin Card Ext" extends "Bin Contents"
{
    layout
    {
        addafter(Options)
        {
            group(DOPSWHSLPFilters)
            {
                Caption = 'LP Filtreleri';
                field(DOPSWHSLPNoFilter; LpNoFilter)
                {
                    ApplicationArea = All;
                    Caption = 'LP No. Filtresi';
                    ToolTip = 'LP numarasını girin. LP maddeleri ana tabloda gösterilir. Eksik raf/ürün tanımı oluşturulabilir; BC Miktar yalnız gerçek depo hareketlerini gösterir.';

                    trigger OnValidate()
                    begin
                        ApplyLPFilter();
                    end;
                }
                field(DOPSWHSLPLocationFilter; LpLocationFilter)
                {
                    ApplicationArea = All;
                    Caption = 'LP Konum Filtresi';
                    ToolTip = 'LP Raf İçeriği eyleminde kullanılacak konumu seçin.';

                    trigger OnValidate()
                    begin
                        ApplyLPBinFilter();
                    end;
                }
                field(DOPSWHSLPBinFilter; LpBinFilter)
                {
                    ApplicationArea = All;
                    Caption = 'LP Depo Gözü Filtresi';
                    ToolTip = 'LP Raf İçeriği eyleminde kullanılacak rafı seçin.';

                    trigger OnValidate()
                    begin
                        ApplyLPBinFilter();
                    end;
                }
            }
        }
        // The standard "Bin Contents" page shows its calculated quantity through
        // the CalcQtyUOM control; there is no control named Quantity.
        addafter(CalcQtyUOM)
        {
            field(DOPSWHSLPNos; ActiveLpNos)
            {
                ApplicationArea = All;
                Caption = 'Güncel LP No.ları';
                Editable = false;
                DrillDown = true;
                ToolTip = 'Bu satırdaki ürün, varyant ve ölçü birimiyle eşleşen aktif LP numaraları LP kayıtlarından güncel olarak hesaplanır. Numaraya göre aramak için LP No. Filtresi veya LP Numarasına Göre Ara eylemini kullanın.';

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
                SubPageLink = "Location Code" = field("Location Code"),
                              "Bin Code" = field("Bin Code");
            }
            part(DOPSWHSLPLines; "DOPSWHS LP Bin Lines")
            {
                ApplicationArea = All;
                SubPageLink = "LP Location Code" = field("Location Code"),
                              "LP Bin Code" = field("Bin Code");
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            action(DOPSWHSLPRefresh)
            {
                ApplicationArea = All;
                Caption = 'Raftaki LP Maddelerini Yenile';
                ToolTip = 'Seçili rafın tüm aktif LP maddeleri için eksik BC raf/ürün tanımlarını tamamlar ve sayfayı yeniler. Stok hareketi oluşturmaz.';
                Image = Refresh;
                Promoted = true;
                PromotedCategory = Process;
                trigger OnAction()
                var
                    BinLPIndex: Codeunit "DOPSWHS Bin LP Index";
                begin
                    BinLPIndex.EnsureBinItemRows(Rec."Location Code", Rec."Bin Code");
                    CurrPage.Update(false);
                end;
            }
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
    begin
        Rec.MarkedOnly(false);
        Rec.ClearMarks();
        if LpNoFilter = '' then begin
            CurrPage.Update(false);
            exit;
        end;

        if not LP.Get(LpNoFilter) then
            Error('%1 LP numarası bulunamadı.', LpNoFilter);
        BinLPIndex.EnsureLPItemRows(LP);
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if Rec.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                    LPLine."Variant Code", LPLine."Unit of Measure") then begin
                    Rec.Mark(true);
                end else
                    if (LPLine."Unit of Measure" <> '') and
                       Rec.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                           LPLine."Variant Code", '') then begin
                        Rec.Mark(true);
                    end;
            until LPLine.Next() = 0;

        Rec.MarkedOnly(true);
        CurrPage.Update(false);
    end;

    local procedure ApplyLPBinFilter()
    begin
        if LpNoFilter <> '' then begin
            LpNoFilter := '';
            Rec.MarkedOnly(false);
            Rec.ClearMarks();
        end;
        CurrPage.Update(false);
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
}
