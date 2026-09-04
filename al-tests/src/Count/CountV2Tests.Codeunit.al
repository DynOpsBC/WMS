codeunit 72142 "DOPSWHS Count V2 Tests"
{
    Subtype = Test;

    [Test]
    procedure PrepareV2MarksEmptySheetAndIsIdempotent()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        SheetNo := CountMgmt.CreateSheet('', Enum::"DOPSWHS Count Mode"::Visible, Counters);

        CountMgmt.PrepareV2(SheetNo);
        CountMgmt.PrepareV2(SheetNo);

        CountHeader.Get(SheetNo);
        Assert.IsTrue(CountHeader."V2 Scan Mode", 'An empty sheet must be reserved for V2 scans.');
    end;

    [Test]
    procedure ScanTenLpsUsesEachLpQuantityWithoutMultiplyingBinBalance()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        ItemJournalLine: Record "Item Journal Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WarehouseEntry: Record "Warehouse Entry";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        ScanId: Guid;
        LastScanId: Guid;
        SheetNo: Code[20];
        LpNo: Code[20];
        WarehouseEntryNo: Integer;
        ItemLedgerEntryCountBefore: Integer;
        ItemLedgerQuantityBefore: Decimal;
        ItemLedgerRemainingBefore: Decimal;
        ItemLedgerModifiedBefore: DateTime;
        LpIndex: Integer;
    begin
        EnsureItemLocationAndBin('CV2-ITEM', 'CV2PCS', 'CV2LOC', 'CV2BIN');
        WarehouseEntryNo := InsertWarehouseBalance('CV2-ITEM', 'CV2PCS', 'CV2LOC', 'CV2BIN', 1000);
        InsertItemLedgerBalance(72142001, 'CV2-ITEM', 'CV2LOC', 1000);
        ItemLedgerEntry.SetRange("Item No.", 'CV2-ITEM');
        ItemLedgerEntryCountBefore := ItemLedgerEntry.Count();
        ItemLedgerEntry.CalcSums(Quantity);
        ItemLedgerQuantityBefore := ItemLedgerEntry.Quantity;
        ItemLedgerEntry.Get(72142001);
        ItemLedgerRemainingBefore := ItemLedgerEntry."Remaining Quantity";
        ItemLedgerModifiedBefore := ItemLedgerEntry.SystemModifiedAt;
        for LpIndex := 1 to 10 do begin
            LpNo := CopyStr('CV2LP-' + Format(LpIndex), 1, MaxStrLen(LpNo));
            InsertBuiltLp(LpNo, 'CV2-ITEM', 'CV2PCS', 'CV2LOC', 'CV2BIN', 100);
        end;

        SheetNo := CountMgmt.CreateSheet('CV2LOC', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        for LpIndex := 1 to 10 do begin
            LpNo := CopyStr('CV2LP-' + Format(LpIndex), 1, MaxStrLen(LpNo));
            ScanId := CreateGuid();
            Assert.AreEqual(1, CountMgmt.ScanV2Lp(SheetNo, ScanId, LpNo, 'CV2BIN', 1), 'Each one-line LP scan must count one line.');
            LastScanId := ScanId;
        end;

        Assert.AreEqual(1, CountMgmt.ScanV2Lp(SheetNo, LastScanId, 'CV2LP-10', 'CV2BIN', 1), 'Retrying the same scan ID must be idempotent.');

        CountLine.SetRange("Sheet No.", SheetNo);
        Assert.AreEqual(10, CountLine.Count(), 'Ten LPs must create ten count lines.');
        CountLine.SetFilter("System Qty", '<>%1', 100);
        Assert.IsTrue(CountLine.IsEmpty(), 'Every LP line must snapshot its own 100 units, not the 1000-unit bin balance.');
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetFilter("Counted Qty 1", '<>%1', 100);
        Assert.IsTrue(CountLine.IsEmpty(), 'Every LP line must be counted as its own 100 units.');
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("Counted 1", false);
        Assert.IsTrue(CountLine.IsEmpty(), 'Every LP line must be marked as counted by slot 1.');
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("Unexpected Stock", true);
        Assert.IsTrue(CountLine.IsEmpty(), 'LPs registered in their system bin must not be marked as unexpected.');
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.CalcSums("System Qty", "Counted Qty 1");
        Assert.AreEqual(1000, CountLine."System Qty", 'LP system quantities must total the single 1000-unit bin balance.');
        Assert.AreEqual(1000, CountLine."Counted Qty 1", 'Ten 100-unit LP scans must total 1000 counted units.');

        CountMgmt.EvaluateVariance(SheetNo);
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetFilter(Variance, '<>%1', 0);
        Assert.IsTrue(CountLine.IsEmpty(), 'Matching LP quantities must produce no inventory variance.');

        // A new scan ID also repairs count lines captured by the unsafe older
        // implementation; it must refresh the snapshot without adding a row.
        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("LP No.", 'CV2LP-10');
        CountLine.FindFirst();
        CountLine."System Qty" := 1000;
        CountLine."Unexpected Stock" := true;
        CountLine.Modify(true);
        ScanId := CreateGuid();
        Assert.AreEqual(1, CountMgmt.ScanV2Lp(SheetNo, ScanId, 'CV2LP-10', 'CV2BIN', 1), 'Rescanning an LP must reuse its existing count line.');
        Assert.AreEqual(10, CountLinesForSheet(SheetNo), 'Rescanning an LP must not create an extra count line.');
        CountLine.FindFirst();
        Assert.AreEqual(100, CountLine."System Qty", 'Rescanning must repair an unsafe legacy system snapshot.');
        Assert.IsFalse(CountLine."Unexpected Stock", 'A repaired LP in its registered bin must not remain unexpected.');

        CountMgmt.CompleteCounter(SheetNo, 1);
        CountMgmt.PostSheet(SheetNo);
        CountHeader.Get(SheetNo);
        Assert.AreEqual(CountHeader.Status::Posted, CountHeader.Status, 'A clean 10 x 100 count must post successfully.');
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
        ItemJournalLine.SetRange("Document No.", SheetNo);
        Assert.IsTrue(ItemJournalLine.IsEmpty(), 'Zero-variance LP rows must never be sent to inventory posting.');

        WarehouseEntry.Get(WarehouseEntryNo);
        Assert.AreEqual(1000, WarehouseEntry.Quantity, 'Scanning and posting matching LPs must not change the warehouse entry.');
        WarehouseEntry.Reset();
        WarehouseEntry.SetRange("Location Code", 'CV2LOC');
        WarehouseEntry.SetRange("Bin Code", 'CV2BIN');
        WarehouseEntry.SetRange("Item No.", 'CV2-ITEM');
        Assert.AreEqual(1, WarehouseEntry.Count(), 'Scanning LPs must not split the single warehouse entry.');
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetRange("Item No.", 'CV2-ITEM');
        Assert.AreEqual(ItemLedgerEntryCountBefore, ItemLedgerEntry.Count(), 'Matching LP count posting must not create or split item ledger entries.');
        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(ItemLedgerQuantityBefore, ItemLedgerEntry.Quantity, 'Matching LP count posting must not change item ledger quantity.');
        ItemLedgerEntry.Get(72142001);
        Assert.AreEqual(ItemLedgerRemainingBefore, ItemLedgerEntry."Remaining Quantity", 'The original receipt remaining quantity must stay unchanged.');
        Assert.AreEqual(ItemLedgerModifiedBefore, ItemLedgerEntry.SystemModifiedAt, 'The original receipt ILE must not be modified.');
    end;

    [Test]
    procedure LegacyInflatedLpSnapshotCannotReachInventoryPosting()
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WarehouseEntry: Record "Warehouse Entry";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        ScanId: Guid;
        SheetNo: Code[20];
        WarehouseEntryNo: Integer;
        ItemLedgerModifiedBefore: DateTime;
    begin
        EnsureItemLocationAndBin('CV2-GUARD', 'CV2PCS', 'CV2SAFE', 'CV2BIN');
        WarehouseEntryNo := InsertWarehouseBalance('CV2-GUARD', 'CV2PCS', 'CV2SAFE', 'CV2BIN', 1000);
        InsertItemLedgerBalance(72142002, 'CV2-GUARD', 'CV2SAFE', 1000);
        InsertBuiltLp('CV2-GUARD-LP', 'CV2-GUARD', 'CV2PCS', 'CV2SAFE', 'CV2BIN', 100);
        ItemLedgerEntry.Get(72142002);
        ItemLedgerModifiedBefore := ItemLedgerEntry.SystemModifiedAt;

        SheetNo := CountMgmt.CreateSheet('CV2SAFE', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        ScanId := CreateGuid();
        CountMgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-GUARD-LP', 'CV2BIN', 1);
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("LP No.", 'CV2-GUARD-LP');
        CountLine.FindFirst();
        CountLine."System Qty" := 1000;
        CountLine.Modify(true);
        CountMgmt.CompleteCounter(SheetNo, 1);

        asserterror CountMgmt.PostSheet(SheetNo);
        Assert.ExpectedError('güvenli olmayan sistem miktarı');
        WarehouseEntry.Get(WarehouseEntryNo);
        Assert.AreEqual(1000, WarehouseEntry.Quantity, 'Rejected legacy snapshot must not change the warehouse entry.');
        ItemLedgerEntry.Get(72142002);
        Assert.AreEqual(1000, ItemLedgerEntry.Quantity, 'Rejected legacy snapshot must not change the receipt quantity.');
        Assert.AreEqual(1000, ItemLedgerEntry."Remaining Quantity", 'Rejected legacy snapshot must not change remaining quantity.');
        Assert.AreEqual(ItemLedgerModifiedBefore, ItemLedgerEntry.SystemModifiedAt, 'Rejected legacy snapshot must not modify the ILE.');
    end;

    [Test]
    procedure StartRecountClearsEveryCapturedCountField()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        SheetNo := CountMgmt.CreateSheet('', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountLine.Init();
        CountLine."Sheet No." := SheetNo;
        CountLine."Line No." := 10000;
        CountLine."Counted Qty 1" := 11;
        CountLine."Counted Qty 2" := 12;
        CountLine."Counted Qty 3" := 13;
        CountLine."Counted 1" := true;
        CountLine."Counted 2" := true;
        CountLine."Counted 3" := true;
        CountLine.Variance := 2;
        CountLine."Recount Required" := true;
        CountLine.Insert(true);

        CountMgmt.StartRecount(SheetNo);

        CountLine.Get(SheetNo, 10000);
        Assert.AreEqual(0, CountLine."Counted Qty 1", 'First count quantity must be reset.');
        Assert.AreEqual(0, CountLine."Counted Qty 2", 'Second count quantity must be reset.');
        Assert.AreEqual(0, CountLine."Counted Qty 3", 'Third count quantity must be reset.');
        Assert.IsFalse(CountLine."Counted 1", 'First count flag must be reset.');
        Assert.IsFalse(CountLine."Counted 2", 'Second count flag must be reset.');
        Assert.IsFalse(CountLine."Counted 3", 'Third count flag must be reset.');
        Assert.AreEqual(0, CountLine.Variance, 'Variance must be reset.');
        Assert.IsFalse(CountLine."Recount Required", 'Recount marker must be reset.');
        CountHeader.Get(SheetNo);
        Assert.AreEqual(CountHeader.Status::InProgress, CountHeader.Status, 'Sheet must return to in-progress.');
    end;

    [Test]
    procedure PostedSheetHeaderLinesAndCountersAreImmutable()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        Counter: Record "DOPSWHS Count Counter";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        SheetNo := CountMgmt.CreateSheet('', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountLine.Init();
        CountLine."Sheet No." := SheetNo;
        CountLine."Line No." := 10000;
        CountLine.Insert(true);
        Counter.Init();
        Counter."Sheet No." := SheetNo;
        Counter."Counter Slot" := 1;
        Counter.Insert(true);
        CountHeader.Get(SheetNo);
        CountHeader.Status := CountHeader.Status::Posted;
        CountHeader.Modify(true);

        CountHeader."Location Code" := 'ILLEGAL';
        asserterror CountHeader.Modify(true);
        CountLine.Get(SheetNo, 10000);
        CountLine."Counted Qty 1" := 99;
        asserterror CountLine.Modify(true);
        Counter.Get(SheetNo, 1);
        Counter."Assigned DateTime" := CurrentDateTime();
        asserterror Counter.Modify(true);
    end;

    local procedure EnsureItemLocationAndBin(ItemNo: Code[20]; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20])
    var
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Location: Record Location;
        Bin: Record Bin;
    begin
        if not UnitOfMeasure.Get(UomCode) then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := UomCode;
            UnitOfMeasure.Insert(true);
        end;
        if not Item.Get(ItemNo) then begin
            Item.Init();
            Item."No." := ItemNo;
            Item.Description := ItemNo;
            Item."Base Unit of Measure" := UomCode;
            Item.Insert(true);
        end;
        if not ItemUnitOfMeasure.Get(ItemNo, UomCode) then begin
            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure."Item No." := ItemNo;
            ItemUnitOfMeasure.Code := UomCode;
            ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
            ItemUnitOfMeasure.Insert(true);
        end;
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not Bin.Get(LocationCode, BinCode) then begin
            Bin.Init();
            Bin."Location Code" := LocationCode;
            Bin.Code := BinCode;
            Bin.Insert(true);
        end;
    end;

    local procedure InsertWarehouseBalance(ItemNo: Code[20]; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20]; Qty: Decimal): Integer
    var
        WarehouseEntry: Record "Warehouse Entry";
        EntryNo: Integer;
    begin
        if WarehouseEntry.FindLast() then
            EntryNo := WarehouseEntry."Entry No." + 1
        else
            EntryNo := 1;
        WarehouseEntry.Init();
        WarehouseEntry."Entry No." := EntryNo;
        WarehouseEntry."Location Code" := LocationCode;
        WarehouseEntry."Bin Code" := BinCode;
        WarehouseEntry."Item No." := ItemNo;
        WarehouseEntry."Unit of Measure Code" := UomCode;
        WarehouseEntry."Registering Date" := WorkDate();
        WarehouseEntry."Qty. per Unit of Measure" := 1;
        WarehouseEntry.Quantity := Qty;
        WarehouseEntry."Qty. (Base)" := Qty;
        WarehouseEntry.Insert(true);
        exit(EntryNo);
    end;

    local procedure InsertItemLedgerBalance(EntryNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; Qty: Decimal)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.Init();
        ItemLedgerEntry."Entry No." := EntryNo;
        ItemLedgerEntry."Item No." := ItemNo;
        ItemLedgerEntry."Posting Date" := WorkDate();
        ItemLedgerEntry."Entry Type" := ItemLedgerEntry."Entry Type"::Purchase;
        ItemLedgerEntry."Document No." := 'CV2-RECEIPT';
        ItemLedgerEntry."Location Code" := LocationCode;
        ItemLedgerEntry.Quantity := Qty;
        ItemLedgerEntry."Remaining Quantity" := Qty;
        ItemLedgerEntry.Positive := true;
        ItemLedgerEntry.Open := true;
        ItemLedgerEntry.Insert(false);
    end;

    local procedure InsertBuiltLp(LpNo: Code[20]; ItemNo: Code[20]; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20]; Qty: Decimal)
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPHeader.Init();
        LPHeader."No." := LpNo;
        LPHeader."Location Code" := LocationCode;
        LPHeader."Bin Code" := BinCode;
        LPHeader.Status := LPHeader.Status::Built;
        LPHeader.Insert(true);

        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := 10000;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := UomCode;
        LPLine.Quantity := Qty;
        LPLine.Insert(true);
    end;

    local procedure CountLinesForSheet(SheetNo: Code[20]): Integer
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
    begin
        CountLine.SetRange("Sheet No.", SheetNo);
        exit(CountLine.Count());
    end;

    var
        Assert: Codeunit Assert;
}
