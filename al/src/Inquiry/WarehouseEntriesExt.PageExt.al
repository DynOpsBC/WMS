pageextension 72314 "DOPSWHS Warehouse Entries" extends "Warehouse Entries"
{
    layout
    {
        addafter("Lot No.")
        {
            field("DOPSWHS LP No."; Rec."DOPSWHS LP No.")
            {
                ApplicationArea = All;
                Caption = 'Hareket Anındaki LP No.';
                ToolTip = 'Bu tarihsel ambar hareketi oluştuğunda yazılan LP numarasıdır; sonraki LP bölmelerinde değişmez.';
                DrillDown = true;

                trigger OnDrillDown()
                var
                    LPHeader: Record "DOPSWHS LP Header";
                begin
                    if (Rec."DOPSWHS LP No." <> '') and LPHeader.Get(Rec."DOPSWHS LP No.") then
                        Page.Run(Page::"DOPSWHS LP Card", LPHeader);
                end;
            }
            field(DOPSWHSCurrLPNos; CurrentActiveLpNos)
            {
                ApplicationArea = All;
                Caption = 'Güncel LP No.ları';
                Editable = false;
                DrillDown = true;
                ToolTip = 'Bu satırla aynı lokasyon, raf, madde, varyant, ölçü birimi, lot ve seri için güncel LP dağılımıdır. Hareket geçmişini göstermez; boş lot yalnız lotsuz stokla eşleşir.';

                trigger OnDrillDown()
                begin
                    OpenActiveLPContents();
                end;
            }
            field(DOPSWHSCurrLPQty; CurrentActiveLpQuantity)
            {
                ApplicationArea = All;
                Caption = 'Güncel LP Miktarı';
                DecimalPlaces = 0 : 5;
                Editable = false;
                DrillDown = true;
                ToolTip = 'Bu satırın madde, lot ve seri bilgisine uyan aynı raftaki güncel LP miktarıdır; tarihsel hareket miktarı değildir. Ayrıntı için tıklayın.';

                trigger OnDrillDown()
                begin
                    OpenActiveLPContents();
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
    begin
        BinContentSubscriber.GetActiveLPTrackingInfo(
            Rec."Location Code", Rec."Bin Code", Rec."Item No.", Rec."Variant Code", Rec."Unit of Measure Code",
            Rec."Lot No.", Rec."Serial No.",
            CurrentActiveLpNos, CurrentActiveLpQuantity);
    end;

    local procedure OpenActiveLPContents()
    var
        ActiveLPContents: Page "DOPSWHS Active LP Contents";
    begin
        ActiveLPContents.LoadFromWarehouseEntry(Rec);
        ActiveLPContents.RunModal();
    end;

    var
        CurrentActiveLpNos: Text[250];
        CurrentActiveLpQuantity: Decimal;
}
