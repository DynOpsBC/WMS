table 72462 "DOPSWHS Label Layout Line"
{
    Caption = 'Etiket Tasarım Satırı';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Layout Code"; Code[20])
        {
            Caption = 'Tasarım Kodu';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Label Layout"."Code";
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Satır No.';
            DataClassification = CustomerContent;
        }
        field(3; "Element Type"; Enum "DOPSWHS Label Element Type")
        {
            Caption = 'Eleman Türü';
            DataClassification = CustomerContent;
        }
        field(4; "X (mm)"; Decimal)
        {
            Caption = 'X (mm)';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
        }
        field(5; "Y (mm)"; Decimal)
        {
            Caption = 'Y (mm)';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
        }
        field(6; "Width (mm)"; Decimal)
        {
            Caption = 'Genişlik';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Kutu/çizgi genişliği; metinde en geniş satır, barkodda en geniş çubuk alanı, QR kodda kenar uzunluğu (mm). 0 = etiketin sağ kenarına kadar.';
        }
        field(7; "Height (mm)"; Decimal)
        {
            Caption = 'Yükseklik';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Kutu/çizgi yüksekliği veya barkod çubuk yüksekliği (mm). Metinde kullanılmaz (Yazı Boyu geçerli).';
        }
        field(8; "Font Height (mm)"; Decimal)
        {
            Caption = 'Yazı Boyu';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Yazı yüksekliği (mm). 0 = 2,75 mm.';
        }
        field(9; "Font Width (mm)"; Decimal)
        {
            Caption = 'Yazı Eni';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Harf genişliği (mm). 0 = yazı boyuyla aynı (normal oran).';
        }
        field(10; "Min Font Height (mm)"; Decimal)
        {
            Caption = 'En Küçük Yazı Boyu';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Genişliğe sığdır açıkken yazının küçülebileceği en düşük boy (mm). 0 = Yazı Boyunun yarısı. Bu boyda da sığmazsa harfler daraltılır.';
        }
        field(11; Alignment; Enum "DOPSWHS Label Alignment")
        {
            Caption = 'Hizalama';
            DataClassification = CustomerContent;
        }
        field(12; "Source Field"; Text[30])
        {
            Caption = 'Alan';
            DataClassification = CustomerContent;
            ToolTip = 'Etiket türüne göre veri alanı (ör. ItemNo, BinCode). Boşsa Sabit Metin kullanılır. Alan listesi için arama düğmesine basın.';

            trigger OnValidate()
            var
                LayoutHeader: Record "DOPSWHS Label Layout";
                LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
            begin
                if "Source Field" = '' then
                    exit;
                if LayoutHeader.Get("Layout Code") then
                    if not LayoutFields.IsValidKey(LayoutHeader."Label Kind", "Source Field") then
                        Error('"%1" bu etiket türü için geçerli bir alan değil. Geçerli alanlar: %2', "Source Field", LayoutFields.KeyList(LayoutHeader."Label Kind"));
            end;
        }
        field(13; "Static Text"; Text[100])
        {
            Caption = 'Sabit Metin';
            DataClassification = CustomerContent;
            ToolTip = 'Alan boşsa basılacak sabit yazı (ör. başlık).';
        }
        field(14; Prefix; Text[30])
        {
            Caption = 'Ön Ek';
            DataClassification = CustomerContent;
            ToolTip = 'Değerin önüne eklenir. Değer boşsa hiçbir şey basılmaz.';
        }
        field(15; Suffix; Text[30])
        {
            Caption = 'Son Ek';
            DataClassification = CustomerContent;
            ToolTip = 'Değerin arkasına eklenir.';
        }
        field(16; "Max Lines"; Integer)
        {
            Caption = 'En Çok Satır';
            DataClassification = CustomerContent;
            MinValue = 0;
            ToolTip = 'Metin bu kadar satıra sözcük sınırından bölünür; fazlası basılmaz. 0/1 = tek satır.';
        }
        field(17; "Fit to Width"; Boolean)
        {
            Caption = 'Genişliğe Sığdır';
            DataClassification = CustomerContent;
            ToolTip = 'Uzun değerlerde yazı, Genişlik içine sığana kadar küçültülür.';
        }
        field(18; Inverted; Boolean)
        {
            Caption = 'Ters (Beyaz)';
            DataClassification = CustomerContent;
            ToolTip = 'Yazıyı zemin siyahsa beyaz basar (siyah şerit üstünde başlık için).';
        }
        field(19; "Show Text"; Boolean)
        {
            Caption = 'Barkod Altı Yazı';
            DataClassification = CustomerContent;
            ToolTip = 'Barkodun altına okunabilir değeri de basar.';
        }
        field(20; "Thickness (mm)"; Decimal)
        {
            Caption = 'Kalınlık';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 2;
            MinValue = 0;
            ToolTip = 'Kutu çerçeve kalınlığı (mm). 0 = içi dolu kutu.';
        }
        field(21; Enabled; Boolean)
        {
            Caption = 'Etkin';
            DataClassification = CustomerContent;
            InitValue = true;
        }
    }

    keys
    {
        key(PK; "Layout Code", "Line No.") { Clustered = true; }
    }
}
