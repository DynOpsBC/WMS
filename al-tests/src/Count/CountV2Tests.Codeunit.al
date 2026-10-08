codeunit 72142 "DOPSWHS Count V2 Tests"
{
    Subtype = Test;

    [Test]
    procedure IncompleteCounterIsRejectedBeforeCardConfirmation()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Counter: Record "DOPSWHS Count Counter";
        Card: TestPage "DOPSWHS Count Sheet Card";
    begin
        SheetNo := CreateSavedFindingRound();
        Counter.Get(SheetNo, 1);
        Counter.Completed := false;
        Counter.Modify(true);
        Header.Get(SheetNo);
        Card.OpenEdit();
        Card.GoToRecord(Header);
        // No ConfirmHandler: the actionable validation must run before Confirm.
        asserterror Card.StartNextRound.Invoke();
        Assert.ExpectedError('Sayım Turunu Kaydet');
        Header.Get(SheetNo);
        Assert.AreEqual('', Header."Next Round No.", 'An incomplete count must remain active.');
        Card.Close();
    end;

    [Test]
    [HandlerFunctions('DeclineNextRound')]
    procedure CancellingNextRoundKeepsTheOriginalActive()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Card: TestPage "DOPSWHS Count Sheet Card";
        HeaderCount: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        HeaderCount := Header.Count();
        Header.Get(SheetNo);
        Card.OpenEdit();
        Card.GoToRecord(Header);
        Card.StartNextRound.Invoke();
        Header.Get(SheetNo);
        Assert.AreEqual('', Header."Next Round No.", 'Cancel must not archive the old round.');
        Assert.AreEqual(HeaderCount, Header.Count(), 'Cancel must not allocate a new document.');
        Card.Close();
    end;

    [ConfirmHandler]
    procedure DeclineNextRound(Question: Text[1024]; var Reply: Boolean)
    begin
        Reply := false;
    end;

    [Test]
    procedure EmptyFreshSnapshotRollsBackWithoutArchiving()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        LP: Record "DOPSWHS LP Header";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        HeaderCount: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        LP.Get('CV2-FIND-LP');
        LP."Bin Code" := 'A.A08.22';
        LP.Modify(true);
        HeaderCount := Header.Count();
        asserterror Mgmt.StartNextRound(SheetNo);
        Assert.ExpectedError('güncel stok kalmadı');
        Header.Get(SheetNo);
        Assert.AreEqual('', Header."Next Round No.", 'The old round must stay active after an empty snapshot.');
        Assert.AreEqual(HeaderCount, Header.Count(), 'The failed transition must leave no empty child.');
    end;

    [Test]
    procedure ArchivedHistoryCannotBeMovedIntoAnActiveSheet()
    var
        SheetNo: Code[20];
        NextNo: Code[20];
        Line: Record "DOPSWHS Count Sheet Line";
        Counter: Record "DOPSWHS Count Counter";
        Scan: Record "DOPSWHS Count V2 Scan";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        SheetNo := CreateSavedFindingRound();
        NextNo := Mgmt.StartNextRound(SheetNo);
        Line.SetRange("Sheet No.", SheetNo);
        Line.FindFirst();
        asserterror Line.Rename(NextNo, 990000);
        Assert.ExpectedError('taşınamaz');
        Counter.Get(SheetNo, 1);
        asserterror Counter.Rename(NextNo, 3);
        Assert.ExpectedError('taşınamaz');
        Scan.SetRange("Sheet No.", SheetNo);
        Scan.FindFirst();
        Scan."Sheet No." := NextNo;
        asserterror Scan.Modify(true);
        Assert.ExpectedError('taşınamaz');
        // Even an in-memory parent change must not bypass Delete protection.
        asserterror Scan.Delete(true);
        Assert.ExpectedError('arşivlendi');
        Scan.FindFirst();
        Scan.Reversed := true;
        asserterror Scan.Modify(true);
        Assert.ExpectedError('arşivlendi');
    end;

    [Test]
    procedure StoredArchiveStateProtectsDeleteAndRename()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        SheetNo := CreateSavedFindingRound();
        Mgmt.StartNextRound(SheetNo);
        Header.Get(SheetNo);
        Header."Next Round No." := '';
        asserterror Header.Delete(true);
        Assert.ExpectedError('geçmişi');
        asserterror Header.Rename('CV2-ILLEGAL-RENAME');
        Assert.ExpectedError('geçmişi');
        Assert.IsTrue(Header.Get(SheetNo), 'Historical header must remain at its original key.');
    end;

    [Test]
    procedure ArchivedCardSkipsToThirdRoundWithoutCreatingFourth()
    var
        SheetNo: Code[20];
        SecondNo: Code[20];
        ThirdNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        Card: TestPage "DOPSWHS Count Sheet Card";
        ActiveCard: TestPage "DOPSWHS Count Sheet Card";
        HeaderCount: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        SecondNo := Mgmt.StartNextRound(SheetNo);
        Mgmt.ScanV2Lp(SecondNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Mgmt.CompleteCounter(SecondNo, 1);
        ThirdNo := Mgmt.StartNextRound(SecondNo);
        Assert.AreEqual(SecondNo, Mgmt.StartNextRound(SheetNo), 'Retry on first round must not create a fourth round.');
        HeaderCount := Header.Count();
        Header.Get(SheetNo);
        Card.OpenEdit();
        Card.GoToRecord(Header);
        ActiveCard.Trap();
        Card.OpenNextRound.Invoke();
        ActiveCard."No.".AssertEquals(ThirdNo);
        ActiveCard."Count Round No.".AssertEquals(3);
        Assert.AreEqual(HeaderCount, Header.Count(), 'Navigation must never allocate a new round.');
        ActiveCard.Close();
    end;

    [Test]
    [HandlerFunctions('ConfirmNextRound')]
    procedure CardStartsNextRoundFromFilteredOldCard()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Card: TestPage "DOPSWHS Count Sheet Card";
        NextCard: TestPage "DOPSWHS Count Sheet Card";
    begin
        SheetNo := CreateSavedFindingRound();
        Header.Get(SheetNo);
        Card.OpenEdit();
        Card.GoToRecord(Header);
        Card.Filter.SetFilter("No.", SheetNo);
        Assert.IsFalse(Card.OpenNextRound.Visible(), 'There is no existing next round to open yet.');
        NextCard.Trap();
        Card.StartNextRound.Invoke();
        Header.Get(SheetNo);
        Assert.IsTrue(Header."Next Round No." <> '', 'The original sheet must be archived successfully.');
        NextCard."No.".AssertEquals(Header."Next Round No.");
        NextCard."Round Root No.".AssertEquals(SheetNo);
        NextCard."Count Round No.".AssertEquals(2);
        Assert.IsFalse(NextCard.OpenNextRound.Visible(), 'The new card must be on the active round.');
        NextCard.Close();
    end;

    [Test]
    procedure ArchivedCardOpensExistingRoundWithoutCreatingAnother()
    var
        SheetNo: Code[20];
        NextNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        Card: TestPage "DOPSWHS Count Sheet Card";
        NextCard: TestPage "DOPSWHS Count Sheet Card";
        HeaderCount: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        NextNo := Mgmt.StartNextRound(SheetNo);
        HeaderCount := Header.Count();
        Header.Get(SheetNo);
        Card.OpenEdit();
        Card.GoToRecord(Header);
        Card.Filter.SetFilter("No.", SheetNo);
        Assert.IsFalse(Card.StartNextRound.Visible(), 'Archived cards must not offer another new round.');
        Assert.IsTrue(Card.OpenNextRound.Visible(), 'Archived cards must offer the existing active round.');
        NextCard.Trap();
        Card.OpenNextRound.Invoke();
        NextCard."No.".AssertEquals(NextNo);
        NextCard."Count Round No.".AssertEquals(2);
        Assert.AreEqual(HeaderCount, Header.Count(), 'Opening a round must not create a new sheet.');
        NextCard.Close();
    end;

    [ConfirmHandler]
    procedure ConfirmNextRound(Question: Text[1024]; var Reply: Boolean)
    begin
        Assert.IsTrue(StrPos(Question, 'yeni tur') > 0, 'Only the new-round confirmation is expected.');
        Reply := true;
    end;

    [Test]
    procedure NextRoundPreservesHistoryAndReadsMovedLpStock()
    var
        SheetNo: Code[20];
        NextNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        OldLine: Record "DOPSWHS Count Sheet Line";
        NewLine: Record "DOPSWHS Count Sheet Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Entry: Record "Warehouse Entry";
        Counter: Record "DOPSWHS Count Counter";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        EntriesBefore: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        OldLine.SetRange("Sheet No.", SheetNo);
        OldLine.FindFirst();
        // Emulate the external Ad-hoc result before starting another round.
        LP.Get('CV2-FIND-LP');
        LP."Bin Code" := 'A.B07.11';
        LP.Modify(true);
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.FindFirst();
        LPLine.Quantity := 8;
        LPLine.Modify(true);
        EntriesBefore := Entry.Count();
        NextNo := Mgmt.StartNextRound(SheetNo);
        Header.Get(NextNo);
        Assert.AreEqual(2, Mgmt.GetRoundNo(Header), 'The next round must be numbered.');
        Assert.AreEqual(SheetNo, Header."Previous Round No.", 'Historical sheet must be linked.');
        Assert.AreEqual(SheetNo, Header."Round Root No.", 'Logical page number must not change.');
        OldLine.Get(SheetNo, OldLine."Line No.");
        Assert.AreEqual(10, OldLine."Counted Qty 1", 'First count must not change.');
        Assert.AreEqual('A.A08.22', OldLine."Found From Bin", 'Original system bin must be preserved.');
        NewLine.SetRange("Sheet No.", NextNo);
        NewLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(NewLine.FindFirst(), 'Current LP must be included.');
        Assert.AreEqual(8, NewLine."System Qty", 'New round needs fresh stock.');
        Assert.AreEqual('A.B07.11', NewLine."Bin Code", 'New round needs the current bin.');
        Assert.IsFalse(NewLine."Counted 1", 'New round must require a fresh count.');
        Assert.AreEqual('', NewLine."Found From Bin", 'Historical finding must not carry over.');
        Assert.AreEqual(EntriesBefore, Entry.Count(), 'Starting a round must not post inventory.');
        Counter.SetRange("Sheet No.", NextNo);
        Counter.SetRange(Completed, true);
        Assert.IsTrue(Counter.IsEmpty(), 'Previous completion must not carry over.');
        Assert.AreEqual(NextNo, Mgmt.StartNextRound(SheetNo), 'Retry must return the same new round.');
        asserterror Mgmt.PostSheet(SheetNo);
        Assert.ExpectedError('arşivlendi');
        asserterror Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Assert.ExpectedError('arşivlendi');
        asserterror Mgmt.RecordCount(SheetNo, OldLine."Line No.", 1, 99);
        Assert.ExpectedError('arşivlendi');
        asserterror Mgmt.StartRecount(SheetNo);
        Assert.ExpectedError('arşivlendi');
        asserterror Mgmt.PostSheet(NextNo);
        Assert.ExpectedError('kayded');
    end;

    [Test]
    procedure NextRoundRequiresSavedCountsAndRollsBackOnSnapshotFailure()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Counter: Record "DOPSWHS Count Counter";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        HeaderCount: Integer;
        Card: TestPage "DOPSWHS Count Sheet Card";
    begin
        SheetNo := CreateSavedFindingRound();
        Counter.Get(SheetNo, 1);
        Counter.Completed := false;
        Counter.Modify(true);
        asserterror Mgmt.StartNextRound(SheetNo);
        Counter.Completed := true;
        Counter.Modify(true);
        Header.Get(SheetNo);
        // An invalid/newly changed scope must not leave a half-created round.
        Header."Zone Filter" := 'MISSING';
        Header.Modify(true);
        HeaderCount := Header.Count();
        asserterror Mgmt.StartNextRound(SheetNo);
        Header.Get(SheetNo);
        Assert.AreEqual('', Header."Next Round No.", 'Failed snapshot must leave the old round active.');
        Assert.AreEqual(HeaderCount, Header.Count(), 'Failed snapshot must not leave an orphan round.');
        Card.OpenEdit();
        Card.GoToRecord(Header);
        Assert.IsFalse(Card.OpenNextRound.Visible(), 'A failed transition must not offer a next round that does not exist.');
        Card.Close();
    end;

    [Test]
    procedure ArchivedRoundRejectsDirectEditsAndKeepsScanEvidence()
    var
        SheetNo: Code[20];
        Header: Record "DOPSWHS Count Sheet Header";
        Line: Record "DOPSWHS Count Sheet Line";
        Scan: Record "DOPSWHS Count V2 Scan";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        ScanCount: Integer;
    begin
        SheetNo := CreateSavedFindingRound();
        Scan.SetRange("Sheet No.", SheetNo);
        ScanCount := Scan.Count();
        Mgmt.StartNextRound(SheetNo);
        Assert.AreEqual(ScanCount, Scan.Count(), 'Original scan events must remain.');
        Header.Get(SheetNo);
        Header."Location Code" := 'CHANGED';
        asserterror Header.Modify(true);
        Header.Get(SheetNo);
        asserterror Header.Delete(true);
        Line.SetRange("Sheet No.", SheetNo);
        Line.FindFirst();
        Line."Counted Qty 1" := 99;
        asserterror Line.Modify(true);
        asserterror Line.Delete(true);
    end;

    local procedure CreateSavedFindingRound(): Code[20]
    var
        SheetNo: Code[20];
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        LP: Record "DOPSWHS LP Header";
    begin
        SheetNo := CreateBinFindingFixture();
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Mgmt.CompleteCounter(SheetNo, 1);
        // Emulate completed Ad-hoc before opening the next round. The first
        // count's historical source bin must still remain A.A08.22.
        LP.Get('CV2-FIND-LP');
        LP."Bin Code" := 'A.B07.11';
        LP.Modify(true);
        exit(SheetNo);
    end;

    [Test]
    procedure DifferentBinLpDoesNotPullSourceOrOtherStockBinsIntoCount()
    var
        SheetNo: Code[20];
        Line: Record "DOPSWHS Count Sheet Line";
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Warehouse Entry";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        EntryCount: Integer;
    begin
        // CNT-20261006094232: an LP registered in A.A08.22 is counted in
        // A.B07.11. The same item is also stocked in other A bins/A.TOPLAM.
        SheetNo := CreateBinFindingFixture();
        InsertBuiltLp('CV2-SOURCE-OTHER', 'CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A08.22', 11);
        InsertWarehouseBalance('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A08.22', 21);
        InsertBinContent('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A08.22');
        EnsureItemLocationAndBin('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A05.12');
        InsertBuiltLp('CV2-OTHER-BIN-LP', 'CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A05.12', 20);
        InsertWarehouseBalance('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A05.12', 20);
        InsertBinContent('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A05.12');
        EnsureItemLocationAndBin('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.TOPLAM');
        InsertWarehouseBalance('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.TOPLAM', 30);
        InsertBinContent('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.TOPLAM');
        EnsureItemLocationAndBin('CV2-OTHER', 'CV2PCS', 'CV2FIND', 'A.TOPLAM');
        InsertBuiltLp('CV2-OTHER-ITEM', 'CV2-OTHER', 'CV2PCS', 'CV2FIND', 'A.TOPLAM', 7);
        InsertBuiltLp('CV2-LOCAL-LP', 'CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.B07.11', 4);
        EntryCount := Entry.Count();

        Mgmt.PrepareV2Bin(SheetNo, 'A.B07.11');
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Assert.AreEqual(2, Line.Count(), 'Scanning must add only the found LP to the selected bin.');
        Mgmt.CompleteV2Bin(SheetNo, 'A.B07.11', 1);
        Mgmt.CompleteV2Bin(SheetNo, 'A.B07.11', 1);
        Mgmt.ValidateBinReview(SheetNo);
        Mgmt.CompleteCounter(SheetNo, 1);
        Assert.AreEqual(2, Line.Count(), 'Finishing/review/saving must not import other bins or items.');
        Line.SetFilter("Bin Code", '<>%1', 'A.B07.11');
        Assert.IsTrue(Line.IsEmpty(), 'Only the physically selected bin belongs to the document.');
        Line.SetRange("Bin Code", 'A.B07.11');
        Line.SetRange("LP No.", 'CV2-FIND-LP');
        Line.FindFirst();
        Assert.AreEqual('A.A08.22', Line."Found From Bin", 'The original bin remains visible as evidence.');
        Assert.AreEqual(10, Line."Found LP Qty", 'The original LP quantity remains visible.');
        Assert.AreEqual(0, Line."System Qty", 'The finding must not invent destination stock.');
        Assert.AreEqual(10, Line."Counted Qty 1", 'The physical count must be retained.');
        Line.SetRange("LP No.", 'CV2-LOCAL-LP');
        Line.FindFirst();
        Assert.IsTrue(Line."Counted 1", 'Unscanned stock in the selected bin must still be confirmed as zero.');
        Assert.AreEqual(0, Line."Counted Qty 1", 'Only finishing the selected bin records the missing stock.');
        Assert.AreEqual(4, Line."System Qty", 'Selected-bin system stock must remain intact.');
        asserterror Mgmt.PostSheet(SheetNo);
        Assert.ExpectedError('düzeltme listesidir');
        LP.Get('CV2-FIND-LP');
        Assert.AreEqual('A.A08.22', LP."Bin Code", 'Finding/review must not move the LP.');
        Assert.AreEqual(EntryCount, Entry.Count(), 'No stock movement may be posted by this finding.');
    end;

    [Test]
    procedure SelectedBinStockChangeStillBlocksCompletingCount()
    var
        SheetNo: Code[20];
        LPLine: Record "DOPSWHS LP Line";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        SheetNo := CreateBinFindingFixture();
        Mgmt.PrepareV2Bin(SheetNo, 'A.A08.22');
        LPLine.Get('CV2-FIND-LP', 10000);
        LPLine.Quantity := 9;
        LPLine.Modify(true);
        asserterror Mgmt.CompleteV2Bin(SheetNo, 'A.A08.22', 1);
        Assert.ExpectedError('sayım başladıktan sonra değişmiş');
    end;

    [Test]
    procedure DifferentBinFindingPreservesZeroAndStockAndRequiresNewDocument()
    var
        SheetNo: Code[20];
        SourceLineNo: Integer;
        Line: Record "DOPSWHS Count Sheet Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        NewSheet: Record "DOPSWHS Count Sheet Header";
        Entry: Record "Warehouse Entry";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        ScanId: Guid;
        EntryCount: Integer;
    begin
        SheetNo := CreateBinFindingFixture();
        Mgmt.PrepareV2Bin(SheetNo, 'A.A08.22');
        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'A.A08.22');
        Line.FindFirst();
        SourceLineNo := Line."Line No.";
        Mgmt.RecordCount(SheetNo, SourceLineNo, 1, 0);
        EntryCount := Entry.Count();
        ScanId := CreateGuid();
        Assert.AreEqual(1, Mgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-FIND-LP', 'A.B07.11', 1), 'Finding must be accepted.');
        Mgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-FIND-LP', 'A.B07.11', 1);
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Line.Reset();
        Line.Get(SheetNo, SourceLineNo);
        Assert.AreEqual(0, Line."Counted Qty 1", 'Original zero must be preserved.');
        Assert.IsTrue(Line."Counted 1", 'Explicit zero must remain recorded.');
        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'A.B07.11');
        Assert.AreEqual(1, Line.Count(), 'Retries must not duplicate findings.');
        Line.FindFirst();
        Assert.AreEqual(10, Line."Counted Qty 1", 'Retry sets rather than adds LP quantity.');
        Assert.AreEqual(0, Line."System Qty", 'Destination must not pretend it already held the LP.');
        Assert.AreEqual('A.A08.22', Line."Found From Bin", 'Historical system bin must be captured.');
        Assert.AreEqual(10, Line."Found LP Qty", 'Historical LP quantity must be captured.');
        LP.Get('CV2-FIND-LP');
        LPLine.Get(LP."No.", 10000);
        Assert.AreEqual('A.A08.22', LP."Bin Code", 'Counting must not move the LP.');
        Assert.AreEqual(10, LPLine.Quantity, 'Counting must not change LP quantity.');
        Assert.AreEqual(EntryCount, Entry.Count(), 'Counting must not post warehouse entries.');
        Mgmt.CompleteCounter(SheetNo, 1);
        asserterror Mgmt.PostSheet(SheetNo);
        Assert.ExpectedError('düzeltme listesidir');
        // Simulate the LP location after a separately performed Ad-hoc operation.
        LP."Bin Code" := 'A.B07.11';
        LP.Modify(true);
        Line.FindFirst();
        Assert.AreEqual('A.A08.22', Line."Found From Bin", 'Ad-hoc must not rewrite first-count evidence.');
        asserterror Mgmt.PostSheet(SheetNo);
        Assert.ExpectedError('düzeltme listesidir');
        NewSheet.Init();
        NewSheet."No." := 'CV2-FIND-SECOND';
        NewSheet."Location Code" := 'CV2FIND';
        NewSheet.Insert(true);
        Mgmt.ScanV2Lp(NewSheet."No.", CreateGuid(), LP."No.", 'A.B07.11', 1);
        Line.Reset();
        Line.SetRange("Sheet No.", NewSheet."No.");
        Line.FindFirst();
        Assert.AreEqual(10, Line."System Qty", 'New document must use the corrected current bin.');
        Assert.AreEqual('', Line."Found From Bin", 'Second document must count normally after correction.');
        Assert.IsFalse(Mgmt.HasLPBinFindings(NewSheet."No."), 'Old evidence must not leak into the second document.');
    end;

    [Test]
    procedure PositiveLPCountCannotBeDuplicatedByScanOrManualCorrection()
    var
        SheetNo: Code[20];
        SourceLineNo: Integer;
        Line: Record "DOPSWHS Count Sheet Line";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        SheetNo := CreateBinFindingFixture();
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.A08.22', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Line.FindFirst();
        SourceLineNo := Line."Line No.";
        asserterror Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        Assert.ExpectedError('zaten pozitif miktarla');
        Assert.IsFalse(Mgmt.HasLPBinFindings(SheetNo), 'Rejected scan must not create a finding.');
        Mgmt.RecordCount(SheetNo, SourceLineNo, 1, 0);
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.B07.11', 1);
        asserterror Mgmt.RecordCount(SheetNo, SourceLineNo, 1, 5);
        Assert.ExpectedError('zaten pozitif miktarla');
        Line.Get(SheetNo, SourceLineNo);
        Assert.AreEqual(0, Line."Counted Qty 1", 'Rejected manual correction must leave the original zero intact.');
    end;

    [Test]
    procedure FindingKeepsSourceOutsideScopeAndUndoRemovesPostingBlock()
    var
        SheetNo: Code[20];
        Line: Record "DOPSWHS Count Sheet Line";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        ScanId: Guid;
    begin
        SheetNo := CreateBinFindingFixture();
        ScanId := CreateGuid();
        Mgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-FIND-LP', 'A.B07.11', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'A.A08.22');
        Assert.IsTrue(Line.IsEmpty(), 'An LP finding must not open its source bin.');
        Mgmt.UndoV2Lp(SheetNo, 'CV2-FIND-LP', 'A.B07.11', 1);
        Assert.IsFalse(Mgmt.HasLPBinFindings(SheetNo), 'Undone findings must not require an Ad-hoc correction.');
        asserterror Mgmt.CompleteCounter(SheetNo, 1);
        asserterror Mgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-FIND-LP', 'A.B07.11', 1);
        Mgmt.ScanV2Lp(SheetNo, CreateGuid(), 'CV2-FIND-LP', 'A.A08.22', 1);
    end;

    [Test]
    procedure RejectedScanCannotCreateLinesOrScanEvents()
    var
        SheetNo: Code[20];
        Line: Record "DOPSWHS Count Sheet Line";
        Scan: Record "DOPSWHS Count V2 Scan";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        ScanId: Guid;
    begin
        SheetNo := CreateBinFindingFixture();
        ScanId := CreateGuid();
        asserterror Mgmt.ScanV2Lp(SheetNo, ScanId, 'CV2-FIND-LP', 'MISSING', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Assert.AreEqual(0, Line.Count(), 'Invalid bin must leave no partial counted line.');
        Assert.IsFalse(Scan.Get(ScanId), 'Invalid bin must not consume scan identity.');
    end;

    [Test]
    procedure StockMovementCannotRewriteTheOriginalSystemSnapshot()
    var
        SheetNo: Code[20];
        Line: Record "DOPSWHS Count Sheet Line";
        LP: Record "DOPSWHS LP Header";
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        SheetNo := CreateBinFindingFixture();
        Mgmt.PrepareV2Bin(SheetNo, 'A.A08.22');
        LP.Get('CV2-FIND-LP');
        LP."Bin Code" := 'A.B07.11';
        LP.Modify(true);
        asserterror Mgmt.ScanV2Lp(SheetNo, CreateGuid(), LP."No.", 'A.A08.22', 1);
        Assert.ExpectedError('Yeni Tur Başlat');
        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'A.A08.22');
        Line.FindFirst();
        Assert.AreEqual(10, Line."System Qty", 'An external move must not overwrite the original snapshot with zero.');
        Assert.AreEqual('', Line."Found From Bin", 'An old snapshot must not be reclassified as a new finding.');
    end;

    local procedure CreateBinFindingFixture(): Code[20]
    var
        Mgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
    begin
        EnsureItemLocationAndBin('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A08.22');
        EnsureItemLocationAndBin('CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.B07.11');
        InsertBuiltLp('CV2-FIND-LP', 'CV2-FIND', 'CV2PCS', 'CV2FIND', 'A.A08.22', 10);
        exit(Mgmt.CreateSheet('CV2FIND', Enum::"DOPSWHS Count Mode"::Visible, Counters));
    end;

    [Test]
    procedure UndoKeepsTheBinPendingAndRejectsReplayOfReversedScan()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        ScanId: Guid;
        LineNo: Integer;
    begin
        EnsureItemLocationAndBin('CV2-UNDO', 'CV2PCS', 'CV2UNDO', 'A1');
        SheetNo := CountMgmt.CreateSheet('CV2UNDO', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        ScanId := CreateGuid();
        LineNo := CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-UNDO', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.UndoV2Scan(SheetNo, ScanId);
        Assert.IsTrue(Line.Get(SheetNo, LineNo), 'Undo must retain the bin in count scope.');
        Assert.IsFalse(Line."Counted 1", 'Undo is an unfinished count, not an explicit zero.');
        asserterror CountMgmt.CompleteCounter(SheetNo, 1);
        asserterror CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-UNDO', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        CountMgmt.CompleteCounter(SheetNo, 1);
    end;

    [Test]
    procedure ScanIdentityCannotBeReusedForAnotherCounterOrQuantity()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        ScanId: Guid;
        LineNo: Integer;
    begin
        EnsureItemLocationAndBin('CV2-RETRY', 'CV2PCS', 'CV2RETRY', 'A1');
        SheetNo := CountMgmt.CreateSheet('CV2RETRY', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        ScanId := CreateGuid();
        LineNo := CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-RETRY', '', 'A1', 'CV2PCS', '', '', 5, 1);
        asserterror CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-RETRY', '', 'A1', 'CV2PCS', '', '', 5, 2);
        asserterror CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-RETRY', '', 'A1', 'CV2PCS', '', '', 6, 1);
        CountMgmt.ScanV2Label(SheetNo, ScanId, 'CV2-RETRY', '', 'A1', 'CV2PCS', '', '', 5, 1);
        Line.Get(SheetNo, LineNo);
        Assert.AreEqual(5, Line."Counted Qty 1", 'An identical retry must not add quantity twice.');
        Assert.IsFalse(Line."Counted 2", 'A changed counter must not consume the original operation identity.');
    end;

    [Test]
    procedure RecountInvalidatesOldEventsWithoutSkippingNewCounts()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        OldScanId: Guid;
        LineNo: Integer;
    begin
        EnsureItemLocationAndBin('CV2-AGAIN', 'CV2PCS', 'CV2AGAIN', 'A1');
        SheetNo := CountMgmt.CreateSheet('CV2AGAIN', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        OldScanId := CreateGuid();
        LineNo := CountMgmt.ScanV2Label(SheetNo, OldScanId, 'CV2-AGAIN', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.StartRecount(SheetNo);
        asserterror CountMgmt.ScanV2Label(SheetNo, OldScanId, 'CV2-AGAIN', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-AGAIN', '', 'A1', 'CV2PCS', '', '', 3, 1);
        Line.Get(SheetNo, LineNo);
        Assert.AreEqual(3, Line."Counted Qty 1", 'Only the new recount event contributes to this round.');
    end;

    [Test]
    procedure FinishBinZerosOnlyUncountedLinesForCurrentCounter()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        EnsureItemLocationAndBin('CV2-ZERO', 'CV2PCS', 'CV2ZERO', 'A1');
        InsertBuiltLp('CV2-ZERO-LP', 'CV2-ZERO', 'CV2PCS', 'CV2ZERO', 'A1', 5);
        SheetNo := CountMgmt.CreateSheet('CV2ZERO', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountMgmt.PrepareV2Bin(SheetNo, 'A1');
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Assert.AreEqual(1, Line.Count(), 'Finishing twice must not duplicate expected stock.');
        Line.FindFirst();
        Assert.IsTrue(Line."Counted 1", 'Explicitly finishing the bin confirms missing stock as zero.');
        Assert.AreEqual(0, Line."Counted Qty 1", 'Missing item must be zero for this counter.');
        Assert.IsFalse(Line."Counted 2", 'Another counter must remain uncounted.');
        Assert.IsFalse(Line."Counted 3", 'Another counter must remain uncounted.');
        Assert.AreEqual(5, Line."System Qty", 'System snapshot must not be changed.');
    end;

    [Test]
    procedure FinishBinPreservesAlreadyRecordedQuantity()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        EnsureItemLocationAndBin('CV2-KEEP', 'CV2PCS', 'CV2KEEP', 'A1');
        InsertBuiltLp('CV2-KEEP-LP', 'CV2-KEEP', 'CV2PCS', 'CV2KEEP', 'A1', 5);
        SheetNo := CountMgmt.CreateSheet('CV2KEEP', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountMgmt.PrepareV2Bin(SheetNo, 'A1');
        Line.SetRange("Sheet No.", SheetNo);
        Line.FindFirst();
        CountMgmt.RecordCount(SheetNo, Line."Line No.", 1, 3);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        Line.FindFirst();
        Assert.AreEqual(3, Line."Counted Qty 1", 'Finishing must preserve a physical count already entered.');
    end;

    [Test]
    procedure UnexpectedItemKeepsOtherBinsOutsideScopeUntilExplicitlyOpened()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        Entry: Record "Warehouse Entry";
        BinContent: Record "Bin Content";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        EntryNo: Integer;
    begin
        EnsureItemLocationAndBin('CV2-MOVE', 'CV2PCS', 'CV2MOVE', 'A1');
        EnsureItemLocationAndBin('CV2-MOVE', 'CV2PCS', 'CV2MOVE', 'A2');
        EntryNo := InsertWarehouseBalance('CV2-MOVE', 'CV2PCS', 'CV2MOVE', 'A2', 5);
        BinContent.Init();
        BinContent."Location Code" := 'CV2MOVE';
        BinContent."Bin Code" := 'A2';
        BinContent."Item No." := 'CV2-MOVE';
        BinContent."Unit of Measure Code" := 'CV2PCS';
        BinContent."Qty. per Unit of Measure" := 1;
        BinContent.Insert(true);
        SheetNo := CountMgmt.CreateSheet('CV2MOVE', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-MOVE', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'A2');
        Assert.IsTrue(Line.IsEmpty(), 'A surplus must not automatically open another bin.');
        CountMgmt.ValidateBinReview(SheetNo);
        CountMgmt.PrepareV2Bin(SheetNo, 'A2');
        Assert.IsTrue(Line.FindFirst(), 'An explicitly opened source bin must be included.');
        Assert.IsFalse(Line."Counted 1", 'Opening a bin must not invent a zero count.');
        asserterror CountMgmt.CompleteCounter(SheetNo, 1);
        Entry.Get(EntryNo);
        Assert.AreEqual(5, Entry.Quantity, 'Scanning/finishing must not deduct source stock.');
        CountMgmt.CompleteV2Bin(SheetNo, 'A2', 1);
        CountMgmt.CompleteCounter(SheetNo, 1);
        CountMgmt.EvaluateVariance(SheetNo);
        Line.Reset();
        Line.SetRange("Sheet No.", SheetNo);
        Line.CalcSums(Variance);
        Assert.AreEqual(0, Line.Variance, 'Equal opposite bin differences must balance only after both bins were counted.');
        Entry.Get(EntryNo);
        Assert.AreEqual(5, Entry.Quantity, 'Review must not post any stock adjustment.');
    end;

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
        asserterror CountMgmt.CompleteCounter(SheetNo, 1);
        Assert.ExpectedError('güvenli olmayan sistem miktarı');

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

    [Test]
    procedure ZoneCountSkipsRelatedBinOutsideZoneFilter()
    var
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        SheetNo: Code[20];
    begin
        // BADE 17 Eyl 2026: stock found in zone Z1 that BC keeps in zone Z2.
        // Finishing the Z1 bin used to fail with BinOutsideZoneFilterErr because
        // the coverage rule tried to seed the Z2 bin into a Z1-only sheet.
        EnsureItemLocationAndBin('CV2-ZONE', 'CV2PCS', 'CV2ZONE', 'Z1-A1');
        EnsureItemLocationAndBin('CV2-ZONE', 'CV2PCS', 'CV2ZONE', 'Z2-B1');
        EnsureZone('CV2ZONE', 'Z1', 'Z1-A1');
        EnsureZone('CV2ZONE', 'Z2', 'Z2-B1');
        InsertWarehouseBalance('CV2-ZONE', 'CV2PCS', 'CV2ZONE', 'Z2-B1', 5);
        InsertBinContent('CV2-ZONE', 'CV2PCS', 'CV2ZONE', 'Z2-B1');
        SheetNo := CountMgmt.CreateV2SheetFiltered('CV2ZONE', 'Z1', 'CV2-OPERATOR');
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-ZONE', '', 'Z1-A1', 'CV2PCS', '', '', 5, 1);

        CountMgmt.CompleteV2Bin(SheetNo, 'Z1-A1', 1);

        Line.SetRange("Sheet No.", SheetNo);
        Line.SetRange("Bin Code", 'Z2-B1');
        Assert.IsTrue(Line.IsEmpty(), 'A bin outside the zone filter must not be seeded into the zone count.');
        CountMgmt.CompleteCounter(SheetNo, 1);
    end;

    [Test]
    procedure RelocationPlanPairsSurplusWithCountedShortfall()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        Line: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Plan: Dictionary of [Text, Decimal];
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        PlanKey: Text;
    begin
        // Merve (17 Eyl 2026): "hem pozitif girişi oldu hem satınalma girişi oldu".
        // Found 5 in A1, BC keeps 5 in A2, operator confirms A2 empty: the plan
        // must be ONE move A2 -> A1 (no negative + positive adjustment pair).
        EnsureItemLocationAndBin('CV2-RELOC', 'CV2PCS', 'CV2RELOC', 'A1');
        EnsureItemLocationAndBin('CV2-RELOC', 'CV2PCS', 'CV2RELOC', 'A2');
        InsertWarehouseBalance('CV2-RELOC', 'CV2PCS', 'CV2RELOC', 'A2', 5);
        InsertBinContent('CV2-RELOC', 'CV2PCS', 'CV2RELOC', 'A2');
        SheetNo := CountMgmt.CreateSheet('CV2RELOC', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-RELOC', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A2', 1);
        CountHeader.Get(SheetNo);

        CountMgmt.PlanFoundStockRelocations(SheetNo, CountHeader, Plan);

        PlanKey := CountMgmt.RelocationPlanKey(LineNoForBin(SheetNo, 'A1'), LineNoForBin(SheetNo, 'A2'), 'A2');
        Assert.AreEqual(1, Plan.Count(), 'Exactly one move must be planned.');
        Assert.IsTrue(Plan.ContainsKey(PlanKey), 'The counted-empty source bin must be paired with the surplus line.');
        Assert.AreEqual(5, Plan.Get(PlanKey), 'The whole shortfall must move into the found bin.');
        Line.Get(SheetNo, LineNoForBin(SheetNo, 'A2'));
        Assert.AreEqual(5, Line."System Qty", 'Planning must not change count lines.');
    end;

    [Test]
    procedure RelocationPlanMovesOnlyTheShortfallWhenSourceStillHoldsPart()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Plan: Dictionary of [Text, Decimal];
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
        PlanKey: Text;
    begin
        // BC keeps 5 in A2; operator finds 2 still in A2 and 5 in A1.
        // Only the 3 missing in A2 may move; the other 2 of A1 are a real surplus.
        EnsureItemLocationAndBin('CV2-PART', 'CV2PCS', 'CV2PART', 'A1');
        EnsureItemLocationAndBin('CV2-PART', 'CV2PCS', 'CV2PART', 'A2');
        InsertWarehouseBalance('CV2-PART', 'CV2PCS', 'CV2PART', 'A2', 5);
        InsertBinContent('CV2-PART', 'CV2PCS', 'CV2PART', 'A2');
        SheetNo := CountMgmt.CreateSheet('CV2PART', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-PART', '', 'A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'A1', 1);
        CountMgmt.PrepareV2Bin(SheetNo, 'A2');
        CountMgmt.RecordCount(SheetNo, LineNoForBin(SheetNo, 'A2'), 1, 2);
        CountMgmt.CompleteV2Bin(SheetNo, 'A2', 1);
        CountHeader.Get(SheetNo);

        CountMgmt.PlanFoundStockRelocations(SheetNo, CountHeader, Plan);

        PlanKey := CountMgmt.RelocationPlanKey(LineNoForBin(SheetNo, 'A1'), LineNoForBin(SheetNo, 'A2'), 'A2');
        Assert.IsTrue(Plan.ContainsKey(PlanKey), 'Source bin with a partial shortfall must still be paired.');
        Assert.AreEqual(3, Plan.Get(PlanKey), 'Only the quantity missing in the source bin may move.');
    end;

    [Test]
    procedure RelocationPlanUsesUncountedBinOutsideZoneFilter()
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Plan: Dictionary of [Text, Decimal];
        SheetNo: Code[20];
        PlanKey: Text;
    begin
        // Zone count Z1 finds 5; BC keeps them in zone Z2 (not counted here):
        // the plan pulls from the uncounted bin (source line no 0).
        EnsureItemLocationAndBin('CV2-ZREL', 'CV2PCS', 'CV2ZREL', 'Z1-A1');
        EnsureItemLocationAndBin('CV2-ZREL', 'CV2PCS', 'CV2ZREL', 'Z2-B1');
        EnsureZone('CV2ZREL', 'Z1', 'Z1-A1');
        EnsureZone('CV2ZREL', 'Z2', 'Z2-B1');
        InsertWarehouseBalance('CV2-ZREL', 'CV2PCS', 'CV2ZREL', 'Z2-B1', 5);
        InsertBinContent('CV2-ZREL', 'CV2PCS', 'CV2ZREL', 'Z2-B1');
        SheetNo := CountMgmt.CreateV2SheetFiltered('CV2ZREL', 'Z1', 'CV2-OPERATOR');
        CountMgmt.ScanV2Label(SheetNo, CreateGuid(), 'CV2-ZREL', '', 'Z1-A1', 'CV2PCS', '', '', 5, 1);
        CountMgmt.CompleteV2Bin(SheetNo, 'Z1-A1', 1);
        CountHeader.Get(SheetNo);

        CountMgmt.PlanFoundStockRelocations(SheetNo, CountHeader, Plan);

        PlanKey := CountMgmt.RelocationPlanKey(LineNoForBin(SheetNo, 'Z1-A1'), 0, 'Z2-B1');
        Assert.AreEqual(1, Plan.Count(), 'Exactly one move must be planned.');
        Assert.IsTrue(Plan.ContainsKey(PlanKey), 'The uncounted bin of the other zone must be the source.');
        Assert.AreEqual(5, Plan.Get(PlanKey), 'The full found quantity must come from the other zone.');
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

    local procedure EnsureZone(LocationCode: Code[10]; ZoneCode: Code[10]; BinCode: Code[20])
    var
        Zone: Record Zone;
        Bin: Record Bin;
    begin
        if not Zone.Get(LocationCode, ZoneCode) then begin
            Zone.Init();
            Zone."Location Code" := LocationCode;
            Zone.Code := ZoneCode;
            Zone.Insert(true);
        end;
        Bin.Get(LocationCode, BinCode);
        Bin."Zone Code" := ZoneCode;
        Bin.Modify(true);
    end;

    local procedure InsertBinContent(ItemNo: Code[20]; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20])
    var
        BinContent: Record "Bin Content";
    begin
        if BinContent.Get(LocationCode, BinCode, ItemNo, '', UomCode) then
            exit;
        BinContent.Init();
        BinContent."Location Code" := LocationCode;
        BinContent."Bin Code" := BinCode;
        BinContent."Item No." := ItemNo;
        BinContent."Unit of Measure Code" := UomCode;
        BinContent."Qty. per Unit of Measure" := 1;
        BinContent.Insert(true);
    end;

    local procedure LineNoForBin(SheetNo: Code[20]; BinCode: Code[20]): Integer
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
    begin
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("Bin Code", BinCode);
        CountLine.FindFirst();
        exit(CountLine."Line No.");
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
