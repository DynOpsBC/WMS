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
        end;
    end;
}
