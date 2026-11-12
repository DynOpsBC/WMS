table 72204 "DOPSWHS Unbuilt LP Repair Buf."
{
    // BADE 1.14.1.186: bozulmuş (Unbuilt) LP'lerin geçmişten çıkarılan içeriği ve
    // raftaki LP'siz stokla karşılaştırması. Yalnız bellekte (geçici) kullanılır.
    Caption = 'Bozulan LP Onarım Satırı';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Sıra'; }
        field(2; "LP No."; Code[20]) { Caption = 'LP No.'; }
        field(3; "Location Code"; Code[10]) { Caption = 'Lokasyon'; }
        field(4; "Bin Code"; Code[20]) { Caption = 'Raf'; }
        field(5; "Unbuilt At"; DateTime) { Caption = 'Bozulma Zamanı'; }
        field(6; "Unbuilt By"; Code[50]) { Caption = 'Bozan Kullanıcı'; }
        field(7; "Unbuilt Ledger Entry No."; Integer) { Caption = 'Bozulma Hareket No.'; }
        field(10; "Item No."; Code[20]) { Caption = 'Madde No.'; }
        field(11; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(12; Quantity; Decimal) { Caption = 'Geçmişteki Miktar'; DecimalPlaces = 0 : 5; }
        field(13; "Unit of Measure"; Code[10]) { Caption = 'Birim'; }
        field(14; "Loose Qty. (Base)"; Decimal) { Caption = 'Raftaki LP''siz Stok'; DecimalPlaces = 0 : 5; }
        field(20; Result; Option)
        {
            Caption = 'Durum';
            OptionMembers = Ready,"Insufficient Stock",Review,Repaired;
            OptionCaption = 'Onarılabilir,Stok Yetersiz,Elle İncele,Onarıldı';
        }
        field(21; "LP Ready"; Boolean) { Caption = 'LP Onarılabilir'; }
        field(22; Note; Text[250]) { Caption = 'Not'; }
        field(23; "Surplus Only"; Boolean) { Caption = 'Yalnız Fazla Stok'; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(LP; "LP No.") { }
    }
}
