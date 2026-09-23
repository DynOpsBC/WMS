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
                ToolTip = 'LP numarasını girerek yalnız bu LP''nin bulunduğu depo gözü ve madde satırlarını gösterin. Filtreyi temizleyerek tüm satırlara dönün.';

                trigger OnValidate()
                begin
                    ApplyLPFilter();
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
                ToolTip = 'Bu raf ve maddedeki güncel LP dağılımını gösterir. Değer satır yüklendiği anda hesaplanır; terminalden yapılan transfer sonrası F5 ile yenileyin veya tıklayıp güncel dağılımı açın.';

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
        }
    }

    actions
    {
        addlast(Processing)
        {
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
    begin
        Rec.MarkedOnly(false);
        Rec.ClearMarks();
        if LpNoFilter = '' then begin
            CurrPage.Update(false);
            exit;
        end;

        if not LP.Get(LpNoFilter) then
            Error('%1 LP numarası bulunamadı.', LpNoFilter);

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if Rec.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                    LPLine."Variant Code", LPLine."Unit of Measure") then
                    Rec.Mark(true);
            until LPLine.Next() = 0;

        Rec.MarkedOnly(true);
        CurrPage.Update(false);
    end;

    var
        ActiveLpNos: Text[250];
        ActiveLpQuantity: Decimal;
        LpNoFilter: Code[20];
        LPListLink: Text[50];
}
