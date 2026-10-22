page 72385 "DOPSWHS Terminal Designer"
{
    // Terminal Ekran Tasarımcısı: teknik bilgi gerektirmeden el terminali
    // menüsünü ve ekran düğmelerini müşteriye göre ayarlama (gizle, sırala,
    // yeniden adlandır, zorunlu okutma). Kaydedilen yerleşim terminale
    // terminalLayouts API'si ile gider; terminal 5 dk'da bir tazeler.
    PageType = Card;
    Caption = 'Terminal Ekran Tasarımcısı';
    ApplicationArea = All;
    UsageCategory = Administration;
    Editable = true;

    layout
    {
        area(Content)
        {
            usercontrol(Designer; "DOPSWHS Terminal Designer")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    Ready := true;
                    PushData();
                end;

                trigger LoadLayout(LayoutCode: Text)
                begin
                    SelectedCode := CopyStr(UpperCase(LayoutCode), 1, MaxStrLen(SelectedCode));
                    PushData();
                end;

                trigger SaveLayout(Json: Text)
                begin
                    if TrySave(Json) then begin
                        Notify(true, StrSubstNo(SavedMsg, SelectedCode));
                        PushData();
                    end else
                        Notify(false, GetLastErrorText());
                end;

                trigger CreateLayout(Json: Text)
                begin
                    if TryCreate(Json) then begin
                        Notify(true, StrSubstNo(CreatedMsg, SelectedCode));
                        PushData();
                    end else
                        Notify(false, GetLastErrorText());
                end;

                trigger DeleteLayout(LayoutCode: Text)
                begin
                    if not Confirm(DeleteQst, false, LayoutCode) then
                        exit;
                    Mgt.DeleteLayout(CopyStr(UpperCase(LayoutCode), 1, 20));
                    SelectedCode := '';
                    Notify(true, StrSubstNo(DeletedMsg, LayoutCode));
                    PushData();
                end;

                trigger RequestPreview(RoleCode: Text; TerminalCode: Text)
                begin
                    CurrPage.Designer.SetPreview(Mgt.BuildPreviewJson(
                        CopyStr(UpperCase(RoleCode), 1, 20), CopyStr(UpperCase(TerminalCode), 1, 20)));
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
                Image = Refresh;
                ToolTip = 'Yerleşimleri BC''den yeniden yükler.';
                trigger OnAction()
                begin
                    PushData();
                end;
            }
        }
    }

    var
        Mgt: Codeunit "DOPSWHS Terminal Layout Mgt";
        SelectedCode: Code[20];
        Ready: Boolean;
        SavedMsg: Label '%1 kaydedildi. Terminaller en geç 5 dakika içinde yeni yerleşimi alır.', Comment = '%1 = layout code';
        CreatedMsg: Label '%1 oluşturuldu.', Comment = '%1 = layout code';
        DeletedMsg: Label '%1 silindi.', Comment = '%1 = layout code';
        DeleteQst: Label '%1 yerleşimi silinsin mi? Bu yerleşimi kullanan terminaller bir üst seviyeye (rol / tüm terminaller) döner.', Comment = '%1 = layout code';

    local procedure PushData()
    begin
        if not Ready then
            exit;
        CurrPage.Designer.SetData(Mgt.BuildDesignerJson(SelectedCode));
    end;

    local procedure TrySave(Json: Text): Boolean
    begin
        exit(RunPending('save', Json));
    end;

    local procedure TryCreate(Json: Text): Boolean
    begin
        exit(RunPending('create', Json));
    end;

    local procedure RunPending(ActionName: Text; Json: Text): Boolean
    var
        Runner: Codeunit "DOPSWHS Terminal Layout Mgt";
    begin
        Runner.SetPending(ActionName, Json);
        if not Runner.Run() then
            exit(false);
        SelectedCode := Runner.GetPendingResult();
        exit(true);
    end;

    local procedure Notify(Ok: Boolean; Message: Text)
    var
        Obj: JsonObject;
        Txt: Text;
    begin
        Obj.Add('ok', Ok);
        Obj.Add('message', Message);
        Obj.WriteTo(Txt);
        CurrPage.Designer.NotifyResult(Txt);
    end;
}
