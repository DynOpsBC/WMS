// Kitoko (20 Eki 2026): "etiketlerin tasarımını değiştirebileceğim bir ekran,
// hardcoded olmasın". Ürün/raf/alan etiketi ZPL'i bu tablolardan üretilir;
// aktif tasarım yoksa PrintDispatcher'daki sabit tasarım kullanılır.
table 72461 "DOPSWHS Label Layout"
{
    Caption = 'Etiket Tasarımı';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Label Layout List";
    DrillDownPageId = "DOPSWHS Label Layout List";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Kod';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(2; Description; Text[100])
        {
            Caption = 'Açıklama';
            DataClassification = CustomerContent;
        }
        field(3; "Label Kind"; Enum "DOPSWHS Label Kind")
        {
            Caption = 'Etiket Türü';
            DataClassification = CustomerContent;
        }
        field(4; "Width (mm)"; Decimal)
        {
            Caption = 'Genişlik (mm)';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Etiket genişliği (mm). 0 = Kurulum sayfasındaki etiket ölçüsü (boşsa 80 mm).';
        }
        field(5; "Height (mm)"; Decimal)
        {
            Caption = 'Yükseklik (mm)';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Etiket yüksekliği (mm). 0 = Kurulum sayfasındaki etiket ölçüsü (boşsa 40 mm).';
        }
        field(6; Dpi; Integer)
        {
            Caption = 'Çözünürlük (dpi)';
            DataClassification = CustomerContent;
            InitValue = 203;
            MinValue = 0;
            ToolTip = 'Yazıcı çözünürlüğü. 203 dpi = 8 nokta/mm (çoğu Zebra), 300 dpi = 12 nokta/mm.';
        }
        field(7; Active; Boolean)
        {
            Caption = 'Aktif';
            DataClassification = CustomerContent;
            ToolTip = 'Aktif tasarım, aynı türdeki etiketlerin baskısında koddaki sabit tasarımın yerine kullanılır. Bir türde yalnız bir tasarım aktif olabilir.';

            trigger OnValidate()
            var
                Other: Record "DOPSWHS Label Layout";
            begin
                if not Active then
                    exit;
                Other.SetRange("Label Kind", "Label Kind");
                Other.SetFilter("Code", '<>%1', "Code");
                Other.SetRange(Active, true);
                if Other.FindSet() then
                    repeat
                        Other.Active := false;
                        Other.Modify();
                    until Other.Next() = 0;
            end;
        }
    }

    keys
    {
        key(PK; "Code") { Clustered = true; }
        key(Kind; "Label Kind", Active) { }
    }

    trigger OnDelete()
    var
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        LayoutLine.SetRange("Layout Code", "Code");
        LayoutLine.DeleteAll();
    end;
}
