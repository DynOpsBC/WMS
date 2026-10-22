page 72469 "DOPSWHS Label Layout List"
{
    Caption = 'Etiket Tasarımları';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    AdditionalSearchTerms = 'Etiket Tasarımları,etiket tasarımı,label layout,ZPL';
    SourceTable = "DOPSWHS Label Layout";
    CardPageId = "DOPSWHS Label Layout Card";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Label Kind"; Rec."Label Kind") { ApplicationArea = All; }
                field("Width (mm)"; Rec."Width (mm)") { ApplicationArea = All; }
                field("Height (mm)"; Rec."Height (mm)") { ApplicationArea = All; }
                field(Active; Rec.Active) { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            // Kitoko (21 Eki 2026): tasarımcıyla sıfırdan yeni tasarım; boş tasarımda
            // hazır şablon galerisi açılır, kaydedilmeden kapatılırsa kayıt silinir.
            action(NewDesign)
            {
                Caption = 'Yeni Tasarım';
                ApplicationArea = All;
                Image = NewDocument;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;
                ToolTip = 'Etiket türünü seçin; tasarımcı boş bir tasarımla açılır ve hazır şablonlardan biriyle başlayabilirsiniz.';

                trigger OnAction()
                var
                    Choice: Integer;
                begin
                    Choice := StrMenu(KindMenuTxt, 1, KindMenuQst);
                    if Choice = 0 then
                        exit;
                    OpenInDesigner(DesignerMgt.CreateNewLayout(Enum::"DOPSWHS Label Kind".FromInteger(Choice - 1)), true);
                end;
            }
            action(CopyDesign)
            {
                Caption = 'Kopyala';
                ApplicationArea = All;
                Image = Copy;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;
                ToolTip = 'Seçili tasarımın kopyasını (pasif) oluşturur ve tasarımcıda açar.';

                trigger OnAction()
                begin
                    OpenInDesigner(DesignerMgt.CopyLayout(Rec."Code"), false);
                end;
            }
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
                ToolTip = 'Seçili tasarımı sürükle-bırak etiket tasarımcısında açar.';
            }
        }
    }

    local procedure OpenInDesigner(LayoutCode: Code[20]; CreatedNew: Boolean)
    var
        Layout: Record "DOPSWHS Label Layout";
        Designer: Page "DOPSWHS Label Designer";
    begin
        Commit();
        Layout.Get(LayoutCode);
        Layout.SetRecFilter();
        Designer.SetTableView(Layout);
        if CreatedNew then
            Designer.SetCreatedNew();
        // Tam sayfa açılsın (RunModal küçük pencere açıyordu); liste yeni kaydı hemen gösterir.
        if Rec.Get(LayoutCode) then;
        CurrPage.Update(false);
        Designer.Run();
    end;

    var
        DesignerMgt: Codeunit "DOPSWHS Label Designer Mgt";
        KindMenuTxt: Label 'Ürün etiketi,Raf etiketi,Alan etiketi,LP / palet etiketi,Lot etiketi';
        KindMenuQst: Label 'Hangi etiket için yeni tasarım?';

    trigger OnOpenPage()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
    begin
        // Kitoko (20 Eki 2026): ilk açılışta varsayılan tasarımlar (pasif) yüklenir.
        if Rec.IsEmpty() then
            if Rec.WritePermission() then
                Engine.SeedDefaults();
        // Kitoko: güncellemeyle eklenen ETIKETV2, mevcut kayıtlı tasarımlarda da listelensin.
        if Rec.WritePermission() then begin
            Engine.EnsureItemV2Layout();
            // Kitoko (21 Eki 2026): LP türü sonradan eklendi; pasif varsayılan LP tasarımı.
            Engine.EnsureLpLayout();
            // Kitoko (22 Eki 2026): pasif "LP-QR" tasarımı (LP QR + Lot 100x50).
            Engine.EnsureLpQrLayout();
            // Kitoko (22 Eki 2026): pasif varsayılan lot etiketi (LOT, 80x40).
            Engine.EnsureLotLayout();
        end;
    end;
}
