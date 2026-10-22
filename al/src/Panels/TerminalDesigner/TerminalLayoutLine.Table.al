table 72383 "DOPSWHS Terminal Layout Line"
{
    // Bir yerleşimdeki tek öğe: ana menü kutusu (Screen Key = HOME) ya da bir
    // ekrandaki düğme (Screen Key = LABELS, PUTAWAY, ...). Anahtarlar
    // "DOPSWHS Terminal Layout Mgt" kataloğu ve Android TerminalLayoutCatalog ile aynıdır.
    Caption = 'Terminal Layout Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Layout Code"; Code[20])
        {
            Caption = 'Yerleşim Kodu';
            TableRelation = "DOPSWHS Terminal Layout".Code;
            NotBlank = true;
        }
        field(2; "Screen Key"; Code[30])
        {
            Caption = 'Ekran';
            NotBlank = true;
        }
        field(3; "Item Key"; Code[50])
        {
            Caption = 'Öğe';
            NotBlank = true;
        }
        field(10; Visible; Boolean)
        {
            Caption = 'Görünür';
            InitValue = true;
        }
        field(11; "Sort Order"; Integer)
        {
            Caption = 'Sıra';
        }
        field(12; "Label Override"; Text[50])
        {
            Caption = 'Görünen Ad (boşsa standart)';
        }
        field(20; "Require LP Scan"; Boolean)
        {
            Caption = 'LP Okutma Zorunlu';
        }
        field(21; "Require Lot No."; Boolean)
        {
            Caption = 'Lot No. Zorunlu';
        }
        field(22; "Require Bin Scan"; Boolean)
        {
            Caption = 'Raf Okutma Zorunlu';
        }
        field(30; Note; Text[250])
        {
            Caption = 'Not / Yardım Metni';
        }
    }

    keys
    {
        key(PK; "Layout Code", "Screen Key", "Item Key") { Clustered = true; }
        key(Sort; "Layout Code", "Screen Key", "Sort Order") { }
    }
}
