table 72473 "DOPSWHS Field WO Buffer"
{
    // Kitoko/Element4 #3338: "DynOps Project Management Core" uzantısının Saha İş Emri
    // (tablo 75641) kaydının terminale açılan kopyası. Uzantı derleme bağımlılığı
    // değildir; veri RecordRef ile okunur (DOPSWHS Project Issue Mgmt).
    Caption = 'Saha İş Emri (WMS görünümü)';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; }
        field(2; "Project No."; Code[20]) { Caption = 'Proje No.'; }
        field(3; "Project Task No."; Code[20]) { Caption = 'Proje Görevi No.'; }
        field(4; Description; Text[100]) { Caption = 'Açıklama'; }
        field(5; Team; Text[100]) { Caption = 'Ekip / Taşeron'; }
        field(6; "Planned Start"; Date) { Caption = 'Planlanan Başlangıç'; }
        field(7; "Planned Finish"; Date) { Caption = 'Planlanan Bitiş'; }
        field(8; Status; Text[50]) { Caption = 'Durum'; }
        field(9; "Project Description"; Text[100]) { Caption = 'Proje Açıklaması'; }
        field(10; "Item Line Count"; Integer) { Caption = 'Malzeme Satırı'; }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
    }
}
