page 72397 "DOPSWHS Bin LP Compare"
{
    // Göz ve LP Karşılaştırma: BC göz stoğu ile gözdeki aktif LP miktarını
    // madde/varyant/lot bazında karşılaştırır; farkın olası nedenini ve
    // önerilen düzeltmeyi gösterir. Hesap: codeunit "DOPSWHS Bin LP Compare Mgt".
    PageType = Card;
    Caption = 'Göz ve LP Karşılaştırma';
    ApplicationArea = All;
    UsageCategory = Lists;
    AdditionalSearchTerms = 'Göz LP karşılaştırma, LP stok farkı, Bin LP compare, LP stock difference, hayalet LP';
    Editable = false;

    layout
    {
        area(Content)
        {
            usercontrol(Compare; "DOPSWHS Bin LP Compare")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    CurrPage.Compare.SetLocale(Format(GlobalLanguage()));
                    SendData(InitialFilterJson());
                end;

                trigger Compare(FilterJson: Text)
                begin
                    SendData(FilterJson);
                end;

                trigger RepairUndoneReceipt(UndoEntryNosCsv: Text; FilterJson: Text)
                var
                    UndoEntryNos: List of [Integer];
                    Planned: Integer;
                    Emptied: Integer;
                begin
                    Planned := CompareMgt.PreviewUndoneReceiptRepair(UndoEntryNosCsv, UndoEntryNos);
                    if Planned = 0 then begin
                        Notify('info', 'Boşaltılacak geri alınmış mal kabul LP satırı bulunamadı. Hiçbir şey değişmedi.');
                        exit;
                    end;
                    if not Confirm(RepairConfirmQst, false, UndoEntryNos.Count(), Planned) then
                        exit;
                    Emptied := CompareMgt.ApplyUndoneReceiptRepair(UndoEntryNos);
                    Notify('success', StrSubstNo('%1 LP satırı boşaltıldı.', Emptied));
                    SendData(FilterJson);
                end;

                trigger ReleaseOrphans(LpNosCsv: Text; FilterJson: Text)
                var
                    OrphanCount: Integer;
                begin
                    OrphanCount := CompareMgt.ReleaseOrphanLps(LpNosCsv, false);
                    if OrphanCount = 0 then begin
                        Notify('info', 'Artık bulunmayan bir belgeye atanmış LP yok. Hiçbir şey değişmedi.');
                        exit;
                    end;
                    if not Confirm(ReleaseConfirmQst, false, OrphanCount) then
                        exit;
                    OrphanCount := CompareMgt.ReleaseOrphanLps(LpNosCsv, true);
                    Notify('success', StrSubstNo('%1 LP serbest bırakıldı.', OrphanCount));
                    SendData(FilterJson);
                end;

                trigger OpenLp(LpNo: Text)
                begin
                    CompareMgt.OpenLp(LpNo);
                end;

                trigger OpenBinContent(LocationCode: Text; BinCode: Text; ItemNo: Text; VariantCode: Text)
                begin
                    CompareMgt.OpenBinContent(LocationCode, BinCode, ItemNo, VariantCode);
                end;

                trigger OpenTraceability(LpNo: Text; ItemNo: Text; LotNo: Text)
                begin
                    CompareMgt.OpenTraceability(LpNo, ItemNo, LotNo);
                end;

                trigger ExportExcel(FilterJson: Text)
                begin
                    LastFilterJson := FilterJson;
                    CompareMgt.ExportToExcel(FilterJson);
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
                ToolTip = 'Karşılaştırmayı yeniler.';
                Image = Refresh;

                trigger OnAction()
                begin
                    SendData(InitialFilterJson());
                end;
            }
            action(OpenHealthPanel)
            {
                ApplicationArea = All;
                Caption = 'Depo Sağlık Paneli';
                ToolTip = 'Depo sorunlarını listeler.';
                Image = CheckList;
                RunObject = page "DOPSWHS Health Panel";
            }
            action(OpenLpTrace)
            {
                ApplicationArea = All;
                Caption = 'LP İzlenebilirlik';
                ToolTip = 'LP İzlenebilirlik sayfasını açar.';
                Image = Trace;
                RunObject = page "DOPSWHS LP Trace";
            }
            action(ExportToExcel)
            {
                ApplicationArea = All;
                Caption = 'Excel''e aktar';
                ToolTip = 'Karşılaştırma satırlarını Excel''e aktarır.';
                Image = ExportToExcel;

                trigger OnAction()
                begin
                    CompareMgt.ExportToExcel(InitialFilterJson());
                end;
            }
        }
        area(Promoted)
        {
            actionref(Refresh_Promoted; Refresh) { }
            actionref(ExportToExcel_Promoted; ExportToExcel) { }
        }
    }

    var
        CompareMgt: Codeunit "DOPSWHS Bin LP Compare Mgt";
        LastFilterJson: Text;
        RepairConfirmQst: Label '%1 geri alma kaydı için %2 LP satırı boşaltılacak (yalnız geri alınan miktar kadar; gerçek stoğu olan LP''ye dokunulmaz). Devam edilsin mi?', Comment = '%1 = geri alma kaydı sayısı, %2 = LP satırı sayısı';
        ReleaseConfirmQst: Label '%1 LP artık bulunmayan bir belgeye atanmış. LP''ler serbest bırakılsın mı? Stok ve göz değişmez.', Comment = '%1 = LP sayısı';

    /// <summary>Sayfayı bir lokasyon/göz/madde bağlamıyla açmak için (Göz İçeriği, LP listesi).</summary>
    procedure SetContext(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20])
    begin
        LastFilterJson := CompareMgt.MakeFilterJson(LocationCode, '', BinCode, BinCode, ItemNo, BinCode = '');
    end;

    local procedure InitialFilterJson(): Text
    begin
        exit(LastFilterJson);
    end;

    local procedure SendData(FilterJson: Text)
    var
        DataJson: Text;
    begin
        LastFilterJson := FilterJson;
        ClearLastError();
        if TryBuildData(FilterJson, DataJson) then
            CurrPage.Compare.SetData(DataJson)
        else
            Notify('error', GetLastErrorText());
    end;

    [TryFunction]
    local procedure TryBuildData(FilterJson: Text; var DataJson: Text)
    begin
        DataJson := CompareMgt.BuildDataJson(FilterJson);
    end;

    local procedure Notify(Kind: Text; Message: Text)
    var
        Result: JsonObject;
        ResultText: Text;
    begin
        Result.Add('kind', Kind);
        Result.Add('message', Message);
        Result.WriteTo(ResultText);
        CurrPage.Compare.NotifyResult(ResultText);
    end;
}
