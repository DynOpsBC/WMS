page 72237 "DOPSWHS LP Auto Rules"
{
    Caption = 'LP Auto Rules';
    PageType = List;
    SourceTable = "DOPSWHS LP Auto Rule";
    ApplicationArea = All;
    UsageCategory = Administration;

    layout
    {
        area(Content)
        {
            repeater(Rules)
            {
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; ToolTip = 'Boş = kendi kuralı olmayan bütün lokasyonlar.'; }
                field("Document Type"; Rec."Document Type") { ApplicationArea = All; ToolTip = 'Ambar Mal Kabul veya Ambar Sevkiyat.'; }
                field(Enabled; Rec.Enabled) { ApplicationArea = All; }
                field("Create Mode"; Rec."Create Mode") { ApplicationArea = All; ToolTip = 'Belge başına: ilk satır eklenince başlığa bağlı tek LP. Satır başına: her belge satırı için ayrı LP.'; }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; }
                field("Stop On Post"; Rec."Stop On Post") { ApplicationArea = All; ToolTip = 'Belge kaydedilince açık LP''ler kapatılır ve SSCC üretilir.'; }
                field("Fill From Document On Post"; Rec."Fill From Document On Post") { ApplicationArea = All; ToolTip = 'BC istemcisinden kaydedilen belgede boş kalan otomatik LP, kaydedilen satırlarla doldurulur.'; }
                field("Print Label On Post"; Rec."Print Label On Post") { ApplicationArea = All; ToolTip = 'Kapatılan LP''nin şablon etiketi belirtilen yazıcıya gönderilir.'; }
                field("Printer Code"; Rec."Printer Code") { ApplicationArea = All; ToolTip = 'Boş = lokasyon/cihaz yazıcı eşlemesi.'; }
                field("Label Copies"; Rec."Label Copies") { ApplicationArea = All; ToolTip = '0 = şablonun kopya sayısı.'; }
                field(Description; Rec.Description) { ApplicationArea = All; }
            }
        }
    }
}
