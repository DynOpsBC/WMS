pageextension 72301 "DOPSWHS Bin Card Ext" extends "Bin Contents"
{
    layout
    {
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
                ToolTip = 'Yalnız bu satırdaki ürün, varyant ve ölçü birimiyle eşleşen, miktarı sıfırdan büyük LP satırlarını gösterir. Raftaki tüm LP başlıkları için Raftaki LP''ler eylemini kullanın. Transfer sonrası F5 ile yenileyin.';

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

    var
        ActiveLpNos: Text[250];
        ActiveLpQuantity: Decimal;
}
