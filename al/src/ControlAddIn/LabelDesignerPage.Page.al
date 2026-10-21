// Kitoko (21 Eki 2026): etiket tasarımının sürükle-bırak düzenleyicisi. Etiket
// Tasarımı kartı/listesindeki "Tasarımcıyı Aç" ile kayda bağlı açılır.
page 72472 "DOPSWHS Label Designer"
{
    Caption = 'Etiket Tasarımcısı';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "DOPSWHS Label Layout";
    DataCaptionExpression = Rec."Code" + ' - ' + Rec.Description;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(Designer; "DOPSWHS Label Designer")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    IsReady := true;
                    LoadCurrent();
                end;

                trigger SaveRequested(DesignJson: Text)
                begin
                    if not DesignerMgt.CanEdit() then begin
                        CurrPage.Designer.ShowMessage('error', NoWritePermissionErr);
                        exit;
                    end;
                    if not DesignerMgt.TryValidateDesign(Rec."Code", DesignJson) then begin
                        CurrPage.Designer.ShowMessage('error', GetLastErrorText());
                        exit;
                    end;
                    DesignerMgt.SaveFromJson(Rec."Code", DesignJson);
                    if Rec.Get(Rec."Code") then;
                    CurrPage.Designer.ShowMessage('success', StrSubstNo(SavedMsg, Rec."Code"));
                end;

                trigger TestPrintRequested(DesignJson: Text)
                var
                    Printer: Record "DOPSWHS Printer";
                    PrinterList: Page "DOPSWHS Printer List";
                begin
                    if not DesignerMgt.TryValidateDesign(Rec."Code", DesignJson) then begin
                        CurrPage.Designer.ShowMessage('error', GetLastErrorText());
                        exit;
                    end;
                    PrinterList.LookupMode(true);
                    if PrinterList.RunModal() <> Action::LookupOK then
                        exit;
                    PrinterList.GetRecord(Printer);
                    DesignerMgt.TestPrint(Rec."Code", DesignJson, Printer."Code");
                    CurrPage.Designer.ShowMessage('success', StrSubstNo(TestPrintSentMsg, Printer."Code"));
                end;

                trigger PreviewRequested(DesignJson: Text)
                var
                    PngBase64: Text;
                begin
                    if not DesignerMgt.TryPreviewPngBase64(Rec."Code", DesignJson, PngBase64) then begin
                        CurrPage.Designer.ShowMessage('error', GetLastErrorText());
                        exit;
                    end;
                    CurrPage.Designer.ShowPreview(PngBase64);
                end;

                trigger CompanyLogoRequested()
                begin
                    if DesignerMgt.CompanyLogoDataUrl() = '' then begin
                        CurrPage.Designer.ShowMessage('error', NoCompanyLogoErr);
                        exit;
                    end;
                    CurrPage.Designer.LoadDesign(DesignerMgt.DesignToJsonWithCompanyLogo(Rec."Code"));
                end;
            }
        }
    }

    trigger OnAfterGetCurrRecord()
    begin
        if IsReady and (Rec."Code" <> LoadedCode) then
            LoadCurrent();
    end;

    local procedure LoadCurrent()
    begin
        if Rec."Code" = '' then
            exit;
        LoadedCode := Rec."Code";
        CurrPage.Designer.LoadDesign(DesignerMgt.DesignToJson(Rec."Code"));
    end;

    var
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        IsReady: Boolean;
        LoadedCode: Code[20];
        NoWritePermissionErr: Label 'Etiket tasarımlarını değiştirme yetkiniz yok.';
        SavedMsg: Label '"%1" tasarımı kaydedildi.', Comment = '%1 = layout code';
        TestPrintSentMsg: Label 'Test etiketi %1 yazıcısına gönderildi (örnek verilerle).', Comment = '%1 = printer code';
        NoCompanyLogoErr: Label 'Şirket Bilgileri sayfasında logo (Resim) yok.';
}
