page 72392 "DOPSWHS LP Trace"
{
    // LP İzlenebilirlik: LP No., SSCC, lot, madde ya da belge no ile arar; LP'nin
    // bugünkü durumunu, içeriğini (kaynak gruplarıyla), LP hareket geçmişini,
    // bağlı madde/ambar girişlerini ve belgeleri gösterir. Veri: codeunit 72391.
    PageType = Card;
    Caption = 'LP İzlenebilirlik';
    ApplicationArea = All;
    UsageCategory = Lists;
    AdditionalSearchTerms = 'LP İzlenebilirlik, LP geçmişi, LP izleme, palet geçmişi, LP trace, license plate trace';
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    DataCaptionExpression = CurrentSearch;

    layout
    {
        area(Content)
        {
            usercontrol(Trace; "DOPSWHS LP Trace")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    ControlIsReady := true;
                    RunSearch(CurrentSearch);
                end;

                trigger Search(SearchText: Text)
                begin
                    RunSearch(SearchText);
                end;

                trigger OpenNode(Kind: Text; NodeKey: Text)
                begin
                    TraceData.OpenNode(Kind, NodeKey);
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Refresh)
            {
                ApplicationArea = All;
                Caption = 'Yenile';
                ToolTip = 'Son aramayı yeniler.';
                Image = Refresh;

                trigger OnAction()
                begin
                    RunSearch(CurrentSearch);
                end;
            }
        }
        area(Navigation)
        {
            action(OpenHealthPanel)
            {
                ApplicationArea = All;
                Caption = 'Depo Sağlık Paneli';
                ToolTip = 'Depo sorunlarını listeler.';
                Image = CheckList;
                RunObject = page "DOPSWHS Health Panel";
            }
            action(OpenBinLpCompare)
            {
                ApplicationArea = All;
                Caption = 'Göz ve LP Karşılaştırma';
                ToolTip = 'Göz veya lokasyon stoğunu aktif LP miktarıyla karşılaştırır.';
                Image = CompareCOA;
                RunObject = page "DOPSWHS Bin LP Compare";
            }
        }
        area(Promoted)
        {
            actionref(Refresh_Promoted; Refresh) { }
        }
    }

    /// <summary>Opens the page on a search (LP No., lot, "ITEM LOT", item or document no.).</summary>
    procedure SetSearch(NewSearch: Text)
    begin
        CurrentSearch := CopyStr(DelChr(NewSearch, '<>', ' '), 1, MaxStrLen(CurrentSearch));
    end;

    local procedure RunSearch(SearchText: Text)
    var
        Payload: Text;
    begin
        CurrentSearch := CopyStr(DelChr(SearchText, '<>', ' '), 1, MaxStrLen(CurrentSearch));
        if not ControlIsReady then
            exit;
        CurrPage.Trace.SetBusy(true);
        if not TraceData.TryBuildTraceJson(CurrentSearch, Payload) then
            Payload := TraceData.ErrorJson(GetLastErrorText());
        CurrPage.Trace.SetData(Payload);
    end;

    var
        TraceData: Codeunit "DOPSWHS LP Trace Data";
        CurrentSearch: Text[100];
        ControlIsReady: Boolean;
}
