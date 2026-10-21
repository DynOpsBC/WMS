// Kitoko (21 Eki 2026): etiket tasarımcısına yüklenen resimler (COMPANY = şirket logosu kopyası).
page 72473 "DOPSWHS Label Image List"
{
    Caption = 'Etiket Resimleri';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "DOPSWHS Label Image";
    InsertAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; Editable = false; ToolTip = 'Resmin kodu; tasarım elemanının Resim alanı bu koda bağlanır.'; }
                field(Name; Rec.Name) { ApplicationArea = All; ToolTip = 'Resmin adı.'; }
                field("Width (px)"; Rec."Width (px)") { ApplicationArea = All; Editable = false; ToolTip = 'Yüklenen resmin genişliği (piksel).'; }
                field("Height (px)"; Rec."Height (px)") { ApplicationArea = All; Editable = false; ToolTip = 'Yüklenen resmin yüksekliği (piksel).'; }
                field("Last Modified"; Rec."Last Modified") { ApplicationArea = All; ToolTip = 'Son değişiklik zamanı.'; }
            }
        }
    }
}
