table 72205 "DOPSWHS Project Move Entry"
{
    // Element4 (18 Kas 2026): "ürünü talep edilen merkeze verirken hangi proje için
    // verdiğimizi de görelim". Terminalden proje koduyla yapılan her taşımanın kaydı:
    // ürün nereden nereye, ne kadar, hangi proje için, kim tarafından. Stok hareketi
    // değildir; taşımanın kendisi standart ambar/madde kaydıdır, bu tablo "neden orada"
    // sorusunu cevaplar.
    Caption = 'Proje Taşıma Kaydı';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Project Move Entries";
    DrillDownPageId = "DOPSWHS Project Move Entries";

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Kayıt No.'; AutoIncrement = true; }
        field(2; "Moved At"; DateTime) { Caption = 'Tarih ve Saat'; }
        field(3; "User ID"; Code[50]) { Caption = 'Kullanıcı'; DataClassification = EndUserIdentifiableInformation; }
        field(4; "Project No."; Code[20]) { Caption = 'Proje No.'; TableRelation = Job; }
        field(5; "Project Description"; Text[100]) { Caption = 'Proje'; }
        field(6; "Item No."; Code[20]) { Caption = 'Madde No.'; TableRelation = Item; }
        field(7; "Item Description"; Text[100]) { Caption = 'Madde'; }
        field(8; "Variant Code"; Code[10]) { Caption = 'Varyant'; }
        field(9; "Lot No."; Code[50]) { Caption = 'Lot No.'; }
        field(10; "Serial No."; Code[50]) { Caption = 'Seri No.'; }
        field(11; Quantity; Decimal) { Caption = 'Miktar'; DecimalPlaces = 0 : 5; }
        field(12; "Unit of Measure Code"; Code[10]) { Caption = 'Birim'; }
        field(13; "Location Code"; Code[10]) { Caption = 'Lokasyon'; TableRelation = Location; }
        field(14; "From Bin Code"; Code[20]) { Caption = 'Nereden (Raf)'; }
        field(15; "To Bin Code"; Code[20]) { Caption = 'Nereye (Raf / Alan)'; }
        field(16; "LP No."; Code[20]) { Caption = 'LP No.'; }
        field(17; "User Name"; Text[100]) { Caption = 'Kullanıcı Adı'; DataClassification = EndUserIdentifiableInformation; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Project; "Project No.", "Moved At") { }
        key(Item; "Item No.", "To Bin Code") { }
    }

    trigger OnModify()
    begin
        Error('Proje taşıma kaydı değiştirilemez.');
    end;

    trigger OnRename()
    begin
        Error('Proje taşıma kaydı değiştirilemez.');
    end;
}
