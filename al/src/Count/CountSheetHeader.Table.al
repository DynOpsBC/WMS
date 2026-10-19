table 72016 "DOPSWHS Count Sheet Header"
{
    Caption = 'Count Sheet';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Count Sheet List";
    DrillDownPageId = "DOPSWHS Count Sheet List";

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; DataClassification = CustomerContent; }
        field(10; "Location Code"; Code[10]) { Caption = 'Location Code'; DataClassification = CustomerContent; TableRelation = Location; }
        field(20; Mode; Enum "DOPSWHS Count Mode") { Caption = 'Mode'; DataClassification = CustomerContent; }
        field(30; Status; Option)
        {
            Caption = 'Status';
            DataClassification = CustomerContent;
            OptionMembers = Open,InProgress,Posted;
            OptionCaption = 'Open,In Progress,Posted';
        }
        field(40; "Created DateTime"; DateTime) { Caption = 'Created DateTime'; DataClassification = CustomerContent; Editable = false; }
        field(50; "Posted DateTime"; DateTime) { Caption = 'Posted DateTime'; DataClassification = CustomerContent; Editable = false; }
        field(60; "Source Phys. Inv. Journal Batch"; Code[10])
        {
            Caption = 'Source Phys. Inv. Journal Batch';
            DataClassification = CustomerContent;
            TableRelation = "Item Journal Batch".Name where("Journal Template Name" = const('PHYS. INV.'));
        }
        field(70; "V2 Scan Mode"; Boolean)
        {
            Caption = 'V2 Scan Mode';
            DataClassification = CustomerContent;

            trigger OnValidate()
            var
                CountMgmt: Codeunit "DOPSWHS Count Mgmt";
            begin
                // BC'de elle değiştirilebilir (BADE 2 Eyl 2026): kurallar
                // CountMgmt'te, PrepareV2 (terminal) ile aynı denetimler.
                CountMgmt.ValidateV2ScanModeChange(Rec, "V2 Scan Mode");
            end;
        }
        field(90; "Count Round No."; Integer) { Caption = 'Sayım Turu'; DataClassification = CustomerContent; Editable = false; }
        field(91; "Previous Round No."; Code[20]) { Caption = 'Önceki Tur Belgesi'; DataClassification = CustomerContent; Editable = false; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(92; "Next Round No."; Code[20]) { Caption = 'Sonraki Tur Belgesi'; DataClassification = CustomerContent; Editable = false; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(93; "Round Root No."; Code[20]) { Caption = 'Sayım Sayfası'; DataClassification = CustomerContent; Editable = false; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(80; "Zone Filter"; Code[10])
        {
            Caption = 'Zone Filter';
            DataClassification = CustomerContent;
            TableRelation = Zone.Code where("Location Code" = field("Location Code"));
        }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
        key(LocationStatus; "Location Code", Status) { }
        key(Created; "Created DateTime") { }
    }

    trigger OnInsert()
    var
        Setup: Record "DOPSWHS Setup";
        NoSeries: Codeunit "No. Series";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        "Count Round No." := 1;
        if "No." = '' then begin
            if Setup.Get('') then
                if Setup."Count Sheet No. Series" <> '' then
                    "No." := NoSeries.GetNextNo(Setup."Count Sheet No. Series");
            if "No." = '' then
                "No." := CopyStr('CNT-' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'), 1, MaxStrLen("No."));
        end;
        if "Created DateTime" = 0DT then
            "Created DateTime" := CurrentDateTime();
        if "Source Phys. Inv. Journal Batch" = '' then
            "Source Phys. Inv. Journal Batch" := CountMgmt.EnsurePhysInvBatch("No.");
    end;

    trigger OnModify()
    var
        StoredHeader: Record "DOPSWHS Count Sheet Header";
    begin
        // A posted count is an immutable inventory document.  Keep the guard in
        // the table as well as the pages/API so alternate clients cannot bypass it.
        // Check persisted state, not xRec: a codeunit-driven Modify can supply
        // an xRec buffer that already contains the newly assigned archive link.
        // The first transition must succeed; later edits must remain blocked.
        StoredHeader.LockTable();
        StoredHeader.Get("No.");
        if StoredHeader."Next Round No." <> '' then
            Error('Arşivlenmiş sayım turu değiştirilemez. Aktif Sayım Turunu Aç ile devam edin. Sonraki tur: %1.', StoredHeader."Next Round No.");
        if StoredHeader.Status = StoredHeader.Status::Posted then
            Error(PostedSheetImmutableErr, "No.");
    end;

    trigger OnDelete()
    begin
        EnsureCanRemove("No.");
    end;

    trigger OnRename()
    begin
        EnsureCanRemove(xRec."No.");
    end;

    local procedure EnsureCanRemove(SheetNo: Code[20])
    var
        StoredHeader: Record "DOPSWHS Count Sheet Header";
    begin
        StoredHeader.LockTable();
        StoredHeader.Get(SheetNo);
        if (StoredHeader."Next Round No." <> '') or (StoredHeader."Previous Round No." <> '') then
            Error('Sayım turu geçmişi silinemez veya yeniden adlandırılamaz.');
        if StoredHeader.Status = StoredHeader.Status::Posted then
            Error(PostedSheetImmutableErr, SheetNo);
    end;

    var
        PostedSheetImmutableErr: Label 'Posted count sheet %1 cannot be changed or deleted.';
}
