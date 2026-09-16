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
