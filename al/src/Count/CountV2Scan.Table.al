table 72014 "DOPSWHS Count V2 Scan"
{
    Caption = 'Count V2 Scan';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Scan ID"; Guid) { Caption = 'Scan ID'; DataClassification = SystemMetadata; }
        field(10; "Sheet No."; Code[20]) { Caption = 'Sheet No.'; DataClassification = CustomerContent; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(20; "Line No."; Integer) { Caption = 'Line No.'; DataClassification = CustomerContent; }
        field(30; "Counter Slot"; Integer) { Caption = 'Counter Slot'; DataClassification = CustomerContent; }
        field(40; Quantity; Decimal) { Caption = 'Quantity'; DataClassification = CustomerContent; }
        field(50; Reversed; Boolean) { Caption = 'Reversed'; DataClassification = CustomerContent; }
        field(60; "Created DateTime"; DateTime) { Caption = 'Created DateTime'; DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Scan ID") { Clustered = true; }
        key(Sheet; "Sheet No.", "Created DateTime") { }
    }

    trigger OnInsert()
    begin
        EnsureSheetIsMutable("Sheet No.");
    end;

    trigger OnModify()
    var
        StoredScan: Record "DOPSWHS Count V2 Scan";
    begin
        // Sheet No. is not part of this table's primary key. Check the stored
        // parent too, so a reassignment cannot remove historical scan evidence.
        StoredScan.Get("Scan ID");
        if StoredScan."Sheet No." <> "Sheet No." then
            Error('Okutma kaydı başka bir sayım turuna taşınamaz.');
        EnsureSheetIsMutable("Sheet No.");
    end;

    trigger OnDelete()
    var
        StoredScan: Record "DOPSWHS Count V2 Scan";
    begin
        StoredScan.Get("Scan ID");
        EnsureSheetIsMutable(StoredScan."Sheet No.");
    end;

    trigger OnRename()
    begin
        Error('Okutma işlem kimliği değiştirilemez.');
    end;

    local procedure EnsureSheetIsMutable(SheetNo: Code[20])
    var
        Header: Record "DOPSWHS Count Sheet Header";
    begin
        Header.LockTable();
        Header.Get(SheetNo);
        if Header."Next Round No." <> '' then
            Error('Bu sayım turu arşivlendi. Aktif Sayım Turunu Aç ile devam edin.');
        if Header.Status = Header.Status::Posted then
            Error('Stoklara işlenmiş sayımın okutma kayıtları değiştirilemez.');
    end;
}
