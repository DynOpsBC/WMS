table 72474 "DOPSWHS Field WO Line Buffer"
{
    // Kitoko/Element4 #3338: Saha İş Emri satırının (tablo 75643) terminal kopyası.
    Caption = 'Saha İş Emri Satırı (WMS görünümü)';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Work Order No."; Code[20]) { Caption = 'İş Emri No.'; }
        field(2; "Line No."; Integer) { Caption = 'Satır No.'; }
        field(3; Type; Text[30]) { Caption = 'Tür'; }
        field(4; "No."; Code[20]) { Caption = 'No.'; }
        field(5; Description; Text[100]) { Caption = 'Açıklama'; }
        field(6; Quantity; Decimal) { Caption = 'Planlanan Miktar'; DecimalPlaces = 0 : 5; }
        field(7; "Actual Quantity"; Decimal) { Caption = 'Gerçekleşen Miktar'; DecimalPlaces = 0 : 5; }
        field(8; "Unit of Measure Code"; Code[10]) { Caption = 'Ölçü Birimi Kodu'; }
        field(9; "Is Item"; Boolean) { Caption = 'Madde'; }
    }

    keys
    {
        key(PK; "Work Order No.", "Line No.") { Clustered = true; }
    }
}
