/// <summary>
/// Depo Sağlık Paneli (Sorun Merkezi) bulgu tamponu.
/// Yalnız geçici (TableType = Temporary): hiçbir şey veritabanına yazılmaz.
/// Codeunit "DOPSWHS Health Detector" doldurur; panel JSON olarak gösterir.
/// </summary>
table 72387 "DOPSWHS Health Issue"
{
    Caption = 'Depo Sağlık Bulgusu';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Sıra No.'; }
        field(2; Category; Option)
        {
            Caption = 'Kategori';
            // Kitoko: BADE'deki "LP'siz rafa kaldırma" (Receipt Mgmt.SplitPutAwayByBinLPs)
            // bu hatta yok; yerine LP kaynak girişi, lokasyon/göz ve satır miktarı kontrolleri.
            OptionMembers = StockMismatch,OrphanAssignment,UndoneReceiptLp,LpSourceEntry,LpLocationMismatch,InvalidLpQty,BlockedItemStock,PrintJob,PrinterMapping;
            OptionCaption = 'LP ≠ stok,Yetim LP ataması,Geri alınmış mal kabulde dolu LP,LP kaynak girişi,LP lokasyon/göz uyuşmazlığı,Hatalı LP satırı,Bloke ürün stoğu,Baskı işi,Yazıcı eşleşmesi';
        }
        field(3; Severity; Option)
        {
            Caption = 'Önem';
            OptionMembers = Info,Warning,Critical;
            OptionCaption = 'Bilgi,Uyarı,Kritik';
        }
        field(10; Title; Text[250]) { Caption = 'Başlık'; }
        field(11; Detail; Text[2048]) { Caption = 'Açıklama'; }
        field(20; "Location Code"; Code[10]) { Caption = 'Depo'; }
        field(21; "Bin Code"; Code[20]) { Caption = 'Göz'; }
        field(22; "Item No."; Code[20]) { Caption = 'Ürün No.'; }
        field(23; "Variant Code"; Code[10]) { Caption = 'Varyant'; }
        field(24; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(25; "LP No."; Code[20]) { Caption = 'LP No.'; }
        field(26; "Document No."; Code[20]) { Caption = 'Belge No.'; }
        field(27; "Entry Ref."; Integer) { Caption = 'Kayıt No.'; }
        field(28; "Ref. Text"; Text[250]) { Caption = 'Referans'; }
        field(30; "Bin Qty. (Base)"; Decimal) { Caption = 'Göz Miktarı'; DecimalPlaces = 0 : 5; }
        field(31; "LP Qty. (Base)"; Decimal) { Caption = 'LP Miktarı'; DecimalPlaces = 0 : 5; }
        field(32; "Affected Count"; Integer) { Caption = 'Etkilenen Sayı'; }
        field(40; "Fix Available"; Boolean) { Caption = 'Düzeltme Var'; }
        field(41; "Fix Caption"; Text[100]) { Caption = 'Düzeltme'; }
        field(42; "Fix Confirm"; Text[500]) { Caption = 'Düzeltme Onayı'; }
        field(43; "Show Caption"; Text[100]) { Caption = 'Göster'; }
        field(50; "Fix Result"; Text[500]) { Caption = 'Düzeltme Sonucu'; }
        field(51; "Fix Succeeded"; Boolean) { Caption = 'Düzeltme Başarılı'; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(CategorySeverity; Category, Severity) { }
    }
}
