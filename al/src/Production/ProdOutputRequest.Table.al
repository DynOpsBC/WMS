table 72234 "DOPSWHS Prod Output Request"
{
    Caption = 'Production Output Request';
    DataClassification = CustomerContent;
    fields
    {
        field(1; "Request ID"; Guid) { DataClassification = SystemMetadata; }
        field(2; "Prod. Order No."; Code[20]) { }
        field(3; "Prod. Order Line No."; Integer) { }
        field(4; "Item No."; Code[20]) { }
        field(5; "Variant Code"; Code[10]) { }
        field(6; "Unit of Measure Code"; Code[10]) { }
        field(7; "Qty. per Unit of Measure"; Decimal) { }
        field(8; "Location Code"; Code[10]) { }
        field(9; "Bin Code"; Code[20]) { }
        field(10; Quantity; Decimal) { DecimalPlaces = 0 : 5; }
        field(11; "Posting Date"; Date) { }
        field(12; "Lot No."; Code[50]) { }
        field(13; "Expiration Date"; Date) { }
        field(14; "Requested Expiration Date"; Date) { }
        field(15; Completed; Boolean) { }
        field(16; Cancelled; Boolean) { }
        field(17; "Document No."; Code[20]) { }
        field(18; "Item Ledger Entry No."; Integer) { }
        field(19; "Quantity (Base)"; Decimal) { DecimalPlaces = 0 : 5; }
        field(20; "Base Unit of Measure"; Code[10]) { }
        field(21; "Created By"; Guid) { DataClassification = EndUserPseudonymousIdentifiers; }
        field(22; "Created At"; DateTime) { DataClassification = SystemMetadata; }
        field(23; "Requested Bin Code"; Code[20]) { }
    }
    keys { key(PK; "Request ID") { Clustered = true; } }
    trigger OnDelete()
    begin
        Error('Üretim bildirim geçmişi silinemez.');
    end;
    trigger OnRename()
    begin
        Error('Üretim bildirim kimliği değiştirilemez.');
    end;
}
