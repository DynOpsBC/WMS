page 72470 "DOPSWHS Label Layout Card"
{
    Caption = 'Etiket Tasarımı';
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "DOPSWHS Label Layout";

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Genel';
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Label Kind"; Rec."Label Kind") { ApplicationArea = All; ToolTip = 'Hangi etiketin yerine kullanılacağı. Alan listesi türe göre değişir.'; }
                field("Width (mm)"; Rec."Width (mm)") { ApplicationArea = All; }
                field("Height (mm)"; Rec."Height (mm)") { ApplicationArea = All; }
                field(Dpi; Rec.Dpi) { ApplicationArea = All; }
                field(Active; Rec.Active) { ApplicationArea = All; }
            }
            part(Lines; "DOPSWHS Label Layout Lines")
            {
                ApplicationArea = All;
                Caption = 'Elemanlar';
                SubPageLink = "Layout Code" = field("Code");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            // Kitoko (21 Eki 2026): sürükle-bırak etiket tasarımcısı.
            action(OpenDesigner)
            {
                Caption = 'Tasarımcıyı Aç';
                ApplicationArea = All;
                Image = Design;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                RunObject = page "DOPSWHS Label Designer";
                RunPageLink = "Code" = field("Code");
                ToolTip = 'Bu tasarımı sürükle-bırak etiket tasarımcısında açar.';
            }
            action(LoadDefault)
            {
                Caption = 'Varsayılanı Yükle';
                ApplicationArea = All;
                Image = Refresh;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Bu tasarımın tüm elemanlarını silip bu etiket türünün koddaki varsayılan görünümünü (80x40 mm) yükler.';

                trigger OnAction()
                var
                    Engine: Codeunit "DOPSWHS Label Layout Engine";
                begin
                    if not Confirm('"%1" tasarımının tüm elemanları silinip varsayılan tasarım yüklenecek. Devam edilsin mi?', false, Rec."Code") then
                        exit;
                    Engine.ResetToDefault(Rec."Code");
                    CurrPage.Update(false);
                end;
            }
            action(ShowZpl)
            {
                Caption = 'ZPL Göster';
                ApplicationArea = All;
                Image = ViewDetails;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Örnek verilerle üretilen ZPL kodunu gösterir.';

                trigger OnAction()
                var
                    Engine: Codeunit "DOPSWHS Label Layout Engine";
                begin
                    Message(Engine.BuildSampleZpl(Rec."Code"));
                end;
            }
            action(TestPrint)
            {
                Caption = 'Test Baskı';
                ApplicationArea = All;
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Seçeceğiniz yazıcıda ÖRNEK verilerle bir etiket basar (gerçek ürün/raf verisi kullanılmaz).';

                trigger OnAction()
                var
                    Printer: Record "DOPSWHS Printer";
                    Engine: Codeunit "DOPSWHS Label Layout Engine";
                    Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
                    PrinterList: Page "DOPSWHS Printer List";
                begin
                    PrinterList.LookupMode(true);
                    if PrinterList.RunModal() <> Action::LookupOK then
                        exit;
                    PrinterList.GetRecord(Printer);
                    Dispatcher.PrintLayoutTest(Engine.BuildSampleZpl(Rec."Code"), Printer."Code", Rec."Label Kind");
                    Message('Test etiketi %1 yazıcısına gönderildi.', Printer."Code");
                end;
            }
            action(Preview)
            {
                Caption = 'Önizleme';
                ApplicationArea = All;
                Image = Picture;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Yalnız ÖRNEK verili ZPL''i labelary.com sitesine gönderir ve dönen etiket resmini (PNG) indirir. Gerçek ürün/raf/müşteri verisi gönderilmez.';

                trigger OnAction()
                var
                    PreviewMgt: Codeunit "DOPSWHS Label Layout Preview";
                begin
                    PreviewMgt.ShowPreview(Rec."Code");
                end;
            }
        }
    }
}
