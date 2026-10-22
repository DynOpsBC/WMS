table 72395 "DOPSWHS Bin LP Compare Buffer"
{
    // Göz ve LP Karşılaştırma: bir gözdeki BC stoğu (depo girişleri / göz içeriği)
    // ile o gözdeki aktif LP miktarının madde + varyant + lot bazında (temel
    // birimde) karşılaştırma satırı. Yalnız geçici kullanılır.
    Caption = 'Göz LP Karşılaştırma Satırı';
    TableType = Temporary;
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Satır No.'; }
        field(10; "Location Code"; Code[10]) { Caption = 'Lokasyon'; }
        field(11; "Zone Code"; Code[10]) { Caption = 'Bölge'; }
        field(12; "Bin Code"; Code[20]) { Caption = 'Göz'; }
        field(20; "Item No."; Code[20]) { Caption = 'Madde No.'; }
        field(21; "Variant Code"; Code[10]) { Caption = 'Varyant'; }
        field(22; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(23; "Base Unit of Measure"; Code[10]) { Caption = 'Temel Birim'; }
        field(24; "Item Description"; Text[100]) { Caption = 'Açıklama'; }
        field(30; "Stock Qty. (Base)"; Decimal) { Caption = 'BC Stok (Temel)'; DecimalPlaces = 0 : 5; }
        field(31; "LP Qty. (Base)"; Decimal) { Caption = 'LP Miktarı (Temel)'; DecimalPlaces = 0 : 5; }
        // Fark = LP − Stok: artı ise LP fazla (hayalet LP), eksi ise LP'siz stok.
        field(32; Difference; Decimal) { Caption = 'Fark (LP − Stok)'; DecimalPlaces = 0 : 5; }
        field(33; "LP Count"; Integer) { Caption = 'LP Sayısı'; }
        field(34; "LP Nos."; Text[2048]) { Caption = 'LP''ler'; }
        field(35; "LP Line Count"; Integer) { Caption = 'LP Satır Sayısı'; }
        field(40; "Comparison Status"; Option)
        {
            Caption = 'Durum';
            OptionMembers = Equal,LpOver,LpNoStock,StockOver,StockNoLp,NegativeStock;
            OptionCaption = 'Eşit,LP fazla,Stok yok LP var,Stok fazla,LP''siz stok,Eksi stok';
        }
        field(41; Reason; Option)
        {
            Caption = 'Olası Neden';
            OptionMembers = "None",UndoneReceipt,OrphanAssignment,LotMismatch,OtherBin;
            OptionCaption = ' ,Geri alınan mal kabul,Yetim atama,Lot uyuşmazlığı,Başka gözde';
        }
        field(42; "Reason Detail"; Text[250]) { Caption = 'Neden Ayrıntısı'; }
        field(43; "Undo Entry Nos."; Text[250]) { Caption = 'Geri Alma Kayıtları'; }
        field(44; "Orphan LP Nos."; Text[250]) { Caption = 'Yetim LP''ler'; }
        field(45; "Repairable LP Lines"; Integer) { Caption = 'Boşaltılabilir LP Satırı'; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(BinItem; "Location Code", "Bin Code", "Item No.", "Variant Code", "Lot No.") { }
    }
}
