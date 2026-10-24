/// <summary>
/// Depo Sağlık Paneli (Sorun Merkezi). Depo yöneticisi için
/// tek sayfa: sorunlar kategori kartlarında, önem rengi ve kısa açıklamayla.
/// Tarama salt okunurdur; güvenli düzeltmeler onayla ve yazma izniyle çalışır.
/// </summary>
page 72389 "DOPSWHS Health Panel"
{
    PageType = Card;
    Caption = 'Depo Sağlık Paneli';
    AdditionalSearchTerms = 'Depo Sağlık, Sorun Merkezi, Warehouse Health, WMS Health';
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(Panel; "DOPSWHS Health Panel")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    PanelReady := true;
                    RefreshPanel();
                end;

                trigger RequestRefresh(LocationFilter: Text)
                begin
                    CurrentLocationFilter := CopyStr(LocationFilter, 1, MaxStrLen(CurrentLocationFilter));
                    RefreshPanel();
                end;

                trigger FixIssue(EntryNo: Integer)
                var
                    Ok: Boolean;
                begin
                    if not Issues.Get(EntryNo) then begin
                        NotifyResult(false, 'Bulgu artık listede yok. Panel yenilendi.');
                        RefreshPanel();
                        exit;
                    end;
                    Ok := Detector.RunFixIsolated(Issues);
                    NotifyResult(Ok, Issues."Fix Result");
                    RefreshPanel();
                end;

                trigger FixCategory(CategoryKey: Text)
                var
                    Category: Integer;
                begin
                    Category := Detector.CategoryFromKey(CategoryKey);
                    if Category < 0 then
                        exit;
                    NotifyResult(true, Detector.FixCategory(Category, CurrentLocationFilter, Issues));
                    RefreshPanel();
                end;

                trigger ShowIssue(EntryNo: Integer; Target: Text)
                begin
                    if Issues.Get(EntryNo) then
                        Detector.ShowIssue(Issues, Target);
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
                ToolTip = 'Sorunları yeniden tarar.';
                Image = Refresh;

                trigger OnAction()
                begin
                    RefreshPanel();
                end;
            }
            action(OpenLpList)
            {
                ApplicationArea = All;
                Caption = 'LP Listesi';
                ToolTip = 'LP listesini açar.';
                Image = List;
                RunObject = page "DOPSWHS LP List";
            }
            action(OpenBinLpCompare)
            {
                ApplicationArea = All;
                Caption = 'Göz ve LP Karşılaştırma';
                ToolTip = 'Göz veya lokasyon stoğunu aktif LP miktarıyla karşılaştırır.';
                Image = CompareCOA;
                RunObject = page "DOPSWHS Bin LP Compare";
            }
            action(OpenLpTrace)
            {
                ApplicationArea = All;
                Caption = 'LP İzlenebilirlik';
                ToolTip = 'LP İzlenebilirlik sayfasını açar.';
                Image = Trace;
                RunObject = page "DOPSWHS LP Trace";
            }
            action(OpenPrintQueue)
            {
                ApplicationArea = All;
                Caption = 'Baskı Kuyruğu';
                ToolTip = 'Baskı işleri kuyruğunu açar.';
                Image = PrintDocument;
                RunObject = page "DOPSWHS Print Job Queue";
            }
        }
        area(Promoted)
        {
            actionref(Refresh_Promoted; Refresh) { }
        }
    }

    trigger OnOpenPage()
    var
        WarehouseEmployee: Record "Warehouse Employee";
    begin
        // Varsayılan depo: kullanıcının varsayılan depo çalışanı kaydı; yoksa tüm depolar.
        WarehouseEmployee.SetRange("User ID", UserId());
        WarehouseEmployee.SetRange(Default, true);
        if WarehouseEmployee.FindFirst() then
            CurrentLocationFilter := WarehouseEmployee."Location Code";
    end;

    local procedure RefreshPanel()
    begin
        if not PanelReady then
            exit;
        CurrPage.Panel.SetBusy(true);
        Detector.DetectAll(CurrentLocationFilter, Issues);
        CurrPage.Panel.SetData(Detector.BuildJson(Issues, CurrentLocationFilter));
    end;

    local procedure NotifyResult(Ok: Boolean; Message: Text)
    var
        Result: JsonObject;
        Payload: Text;
    begin
        Result.Add('ok', Ok);
        Result.Add('message', Message);
        Result.WriteTo(Payload);
        CurrPage.Panel.NotifyResult(Payload);
    end;

    var
        Issues: Record "DOPSWHS Health Issue";
        Detector: Codeunit "DOPSWHS Health Detector";
        CurrentLocationFilter: Text[250];
        PanelReady: Boolean;
}
