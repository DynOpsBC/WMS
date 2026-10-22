/// <summary>
/// Depo Sağlık Paneli dedektörleri (BADE 22 Eki 2026; Kitoko'da göz zorunlu
/// olmayan lokasyon, LP kaynak girişi, lokasyon/göz ve satır miktarı testleri eklendi). Her dedektör küçük bir
/// fikstürle (depo HLT) beslenir; tarama depo filtresiyle yalnız bu fikstürü görür.
/// Düzeltme olan kategorilerde FixIssue sonrası bulgunun kaybolduğu da doğrulanır.
/// </summary>
codeunit 72150 "DOPSWHS Health Detector Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Item Ledger Entry" = rimd,
        tabledata "Warehouse Entry" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StockMismatchComparesBinWithActiveLps()
    var
        Issues: Record "DOPSWHS Health Issue";
        Detector: Codeunit "DOPSWHS Health Detector";
        LP: Record "DOPSWHS LP Header";
    begin
        // [GIVEN] K.K03.11: gözde 45.000, iki aktif LP x 45.000 (+ kullanılmış LP yok sayılır)
        EnsureFixture();
        CreateWhseEntry(1, 'K.K03.11', ItemNo(), 'L1', 45000);
        CreateLp('HLT-SM-1', 'K.K03.11', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-SM-1', 'L1', 45000, 0);
        CreateLp('HLT-SM-2', 'K.K03.11', LP.Status::Assigned, LP."Assigned Document Type"::WhsePick, 'HLT-PI');
        AddLpLine('HLT-SM-2', 'L1', 45000, 0);
        CreateLp('HLT-SM-USED', 'K.K03.11', LP.Status::Used, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-SM-USED', 'L1', 45000, 0);
        // K.K03.12: tutarlı (10 = 10)
        CreateWhseEntry(2, 'K.K03.12', ItemNo(), 'L1', 10);
        CreateLp('HLT-SM-3', 'K.K03.12', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-SM-3', 'L1', 10, 0);
        // K.K03.13: gözde 100, LP'de 40 (LP'siz stok)
        CreateWhseEntry(3, 'K.K03.13', ItemNo(), 'L2', 100);
        CreateLp('HLT-SM-4', 'K.K03.13', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-SM-4', 'L2', 40, 0);

        // [WHEN]
        Detector.DetectStockMismatch(LocationCode(), Issues);

        // [THEN]
        Assert.AreEqual(2, Detector.CategoryTotal(Issues.Category::StockMismatch), 'Yalnız iki göz tutarsız.');
        Issues.SetRange("Bin Code", 'K.K03.11');
        Assert.IsTrue(Issues.FindFirst(), 'K.K03.11 bulgusu olmalı.');
        Assert.AreEqual(45000, Issues."Bin Qty. (Base)", 'Göz miktarı');
        Assert.AreEqual(90000, Issues."LP Qty. (Base)", 'Aktif LP miktarı (kullanılmış LP hariç)');
        Assert.AreEqual('L1', Issues."Lot No.", 'Lot');
        Assert.AreEqual(Format(Issues.Severity::Critical), Format(Issues.Severity), 'LP fazlası kritik olmalı.');
        Assert.IsFalse(Issues."Fix Available", 'Otomatik düzeltme olmamalı.');
        Issues.SetRange("Bin Code", 'K.K03.13');
        Assert.IsTrue(Issues.FindFirst(), 'K.K03.13 bulgusu olmalı.');
        Assert.AreEqual(Format(Issues.Severity::Warning), Format(Issues.Severity), 'LP''siz stok uyarı olmalı.');
        Issues.SetRange("Bin Code", 'K.K03.12');
        Assert.IsTrue(Issues.IsEmpty(), 'Tutarlı göz bulgu üretmemeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StockMismatchWithoutLotComparesWholeItem()
    var
        Issues: Record "DOPSWHS Health Issue";
        Detector: Codeunit "DOPSWHS Health Detector";
        LP: Record "DOPSWHS LP Header";
    begin
        // [GIVEN] LP satırında lot yok; gözde iki lot toplamı LP'ye eşit
        EnsureFixture();
        CreateWhseEntry(4, 'K.K04.01', ItemNo(), 'L1', 30);
        CreateWhseEntry(5, 'K.K04.01', ItemNo(), 'L2', 20);
        CreateLp('HLT-SM-5', 'K.K04.01', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-SM-5', '', 50, 0);

        Detector.DetectStockMismatch(LocationCode(), Issues);

        Issues.SetRange("Bin Code", 'K.K04.01');
        Assert.IsTrue(Issues.IsEmpty(), 'Lotsuz LP ürün toplamıyla karşılaştırılmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OrphanAssignmentIsDetectedAndReleased()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        // [GIVEN] biri silinmiş, biri mevcut rafa kaldırmaya atanmış iki LP
        EnsureFixture();
        CreatePutAway('HLT-PA-LIVE');
        CreateLp('HLT-ORF-1', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-PA-GONE');
        CreateLp('HLT-ORF-2', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-PA-LIVE');

        // [WHEN]
        Detector.DetectOrphanAssignments(LocationCode(), Issues);

        // [THEN]
        Assert.AreEqual(1, Detector.CategoryTotal(Issues.Category::OrphanAssignment), 'Yalnız silinmiş belgeye atanmış LP.');
        Issues.FindFirst();
        Assert.AreEqual('HLT-ORF-1', Issues."LP No.", 'Yetim LP');
        Assert.AreEqual('HLT-PA-GONE', Issues."Document No.", 'Belge no');
        Assert.IsTrue(Issues."Fix Available", 'Serbest bırakma sunulmalı.');

        // [WHEN] düzelt
        Detector.FixIssue(Issues);

        // [THEN]
        LP.Get('HLT-ORF-1');
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'LP serbest kalmalı.');
        LP.Get('HLT-ORF-2');
        Assert.AreEqual('HLT-PA-LIVE', LP."Assigned Document No.", 'Mevcut belgedeki atama değişmemeli.');
        Detector.DetectAll(LocationCode(), Issues);
        Assert.AreEqual(0, Detector.CategoryTotal(Issues.Category::OrphanAssignment), 'Düzeltmeden sonra yetim kalmamalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoneReceiptLpIsDetectedAndRepaired()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        // [GIVEN] mal kabul +10 (kalan 0), geri alma -10; LP hâlâ 10 dolu
        EnsureFixture();
        OriginalEntryNo := CreateEntry(1, 'HLT-RCPT', 10000, 'LOT-U', 10, 0, false, 0);
        UndoEntryNo := CreateEntry(2, 'HLT-RCPT', 20000, 'LOT-U', -10, 0, true, OriginalEntryNo);
        CreateLp('HLT-UND-1', 'RCV', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-UND-1', 'LOT-U', 10, OriginalEntryNo);

        // [WHEN]
        Detector.DetectUndoneReceiptLps(LocationCode(), Issues);

        // [THEN]
        Issues.SetRange("Entry Ref.", UndoEntryNo);
        Assert.IsTrue(Issues.FindFirst(), 'Geri alınmış mal kabul bulgusu olmalı.');
        Assert.AreEqual(1, Issues."Affected Count", 'Bir LP satırı boşaltılacak.');
        Assert.AreEqual('HLT-RCPT', Issues."Document No.", 'İrsaliye no');
        Assert.IsTrue(Issues."Fix Available", 'Onarım sunulmalı.');

        // [WHEN] düzelt
        Detector.FixIssue(Issues);

        // [THEN]
        Assert.AreEqual(0, LpQty('HLT-UND-1'), 'LP boşalmalı.');
        Detector.DetectAll(LocationCode(), Issues);
        Issues.SetRange("Entry Ref.", UndoEntryNo);
        Issues.SetRange(Category, Issues.Category::UndoneReceiptLp);
        Assert.IsTrue(Issues.IsEmpty(), 'Onarımdan sonra bulgu kalmamalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoneReceiptBackedByStockIsNotReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        // [GIVEN] kalan miktar LP'yi karşılıyor
        EnsureFixture();
        OriginalEntryNo := CreateEntry(3, 'HLT-RCPT2', 10000, 'LOT-V', 10, 10, false, 0);
        UndoEntryNo := CreateEntry(4, 'HLT-RCPT2', 20000, 'LOT-V', -10, 0, true, OriginalEntryNo);
        CreateLp('HLT-UND-2', 'RCV', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('HLT-UND-2', 'LOT-V', 10, OriginalEntryNo);

        Detector.DetectUndoneReceiptLps(LocationCode(), Issues);

        Issues.SetRange("Entry Ref.", UndoEntryNo);
        Assert.IsTrue(Issues.IsEmpty(), 'Gerçek stokla desteklenen LP bulgu olmamalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StockMismatchNonBinLocationUsesItemLedger()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        // [GIVEN] Kitoko: göz zorunlu olmayan lokasyon. Lot N1: stok 30, LP 40 (göz kodu
        // yazılı olsa da yok sayılır); lot N2: stok 50, LP 20; lot N3: stok 15 = LP 15.
        EnsureFixture();
        CreateItemEntry(30, ItemNo(), NonBinLocationCode(), 'N1', 30, 30);
        CreateItemEntry(31, ItemNo(), NonBinLocationCode(), 'N2', 50, 50);
        CreateItemEntry(32, ItemNo(), NonBinLocationCode(), 'N3', 15, 15);
        CreateLpAt('HLT-NB-1', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-NB-1', 'N1', 25, 0);
        CreateLpAt('HLT-NB-2', NonBinLocationCode(), 'ESKI-RAF', LP.Status::Built);
        AddLpLine('HLT-NB-2', 'N1', 15, 0);
        AddLpLine('HLT-NB-2', 'N2', 20, 0);
        CreateLpAt('HLT-NB-3', NonBinLocationCode(), '', LP.Status::Assigned);
        AddLpLine('HLT-NB-3', 'N3', 15, 0);

        // [WHEN]
        Detector.DetectStockMismatch(NonBinLocationCode(), Issues);

        // [THEN]
        Assert.AreEqual(2, Detector.CategoryTotal(Issues.Category::StockMismatch), 'N1 ve N2 tutarsız; N3 tutarlı.');
        Issues.SetRange("Lot No.", 'N1');
        Assert.IsTrue(Issues.FindFirst(), 'N1 bulgusu olmalı.');
        Assert.AreEqual('', Issues."Bin Code", 'Göz zorunlu olmayan lokasyonda göz boş kalmalı.');
        Assert.AreEqual(30, Issues."Bin Qty. (Base)", 'Madde girişlerinden stok');
        Assert.AreEqual(40, Issues."LP Qty. (Base)", 'İki LP toplamı');
        Assert.AreEqual(Format(Issues.Severity::Critical), Format(Issues.Severity), 'LP fazlası kritik.');
        Issues.SetRange("Lot No.", 'N2');
        Assert.IsTrue(Issues.FindFirst(), 'N2 bulgusu olmalı.');
        Assert.AreEqual(Format(Issues.Severity::Info), Format(Issues.Severity), 'Gözsüz lokasyonda LP''siz stok bilgi.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LpSourceEntryMissingOrExhaustedIsReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
        ExhaustedEntryNo: Integer;
        CoveredEntryNo: Integer;
        HealthyEntryNo: Integer;
    begin
        // [GIVEN] (a) olmayan girişe bağlı LP, (b) tükenmiş ve lokasyonda karşılığı olmayan
        // giriş, (c) tükenmiş ama aynı lotun stoğu başka girişte duran giriş, (d) sağlıklı giriş.
        EnsureFixture();
        ExhaustedEntryNo := CreateItemEntry(40, ItemNo(), NonBinLocationCode(), 'S1', 10, 0);
        CoveredEntryNo := CreateItemEntry(41, ItemNo(), NonBinLocationCode(), 'S2', 10, 0);
        CreateItemEntry(42, ItemNo(), NonBinLocationCode(), 'S2', 10, 10);
        HealthyEntryNo := CreateItemEntry(43, ItemNo(), NonBinLocationCode(), 'S3', 10, 10);
        CreateLpAt('HLT-SRC-1', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-SRC-1', 'S9', 5, 2147460099);
        CreateLpAt('HLT-SRC-2', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-SRC-2', 'S1', 10, ExhaustedEntryNo);
        CreateLpAt('HLT-SRC-3', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-SRC-3', 'S2', 10, CoveredEntryNo);
        CreateLpAt('HLT-SRC-4', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-SRC-4', 'S3', 10, HealthyEntryNo);

        // [WHEN]
        Detector.DetectLpSourceEntries(NonBinLocationCode(), Issues);

        // [THEN]
        Assert.AreEqual(3, Detector.CategoryTotal(Issues.Category::LpSourceEntry), 'Sağlıklı giriş bulgu üretmemeli.');
        Issues.SetRange("LP No.", 'HLT-SRC-1');
        Assert.IsTrue(Issues.FindFirst(), 'Olmayan giriş bulgusu');
        Assert.AreEqual(Format(Issues.Severity::Critical), Format(Issues.Severity), 'Olmayan giriş kritik.');
        Issues.SetRange("LP No.", 'HLT-SRC-2');
        Assert.IsTrue(Issues.FindFirst(), 'Tükenmiş giriş bulgusu');
        Assert.AreEqual(Format(Issues.Severity::Warning), Format(Issues.Severity), 'Karşılıksız tükenmiş giriş uyarı.');
        Assert.AreEqual(ExhaustedEntryNo, Issues."Entry Ref.", 'Giriş no');
        Assert.AreEqual(10, Issues."LP Qty. (Base)", 'Bağlı LP miktarı');
        Issues.SetRange("LP No.", 'HLT-SRC-3');
        Assert.IsTrue(Issues.FindFirst(), 'Karşılığı olan tükenmiş giriş bulgusu');
        Assert.AreEqual(Format(Issues.Severity::Info), Format(Issues.Severity), 'Stok yerinde: bilgi.');
        Assert.AreEqual('HLT-SRC-3', Detector.TraceSearchText(Issues), 'LP izine LP no ile gidilir.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LpLocationAndBinMismatchesAreReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        // [GIVEN] göz zorunlu HLT: tanımlı gözde LP (sağlıklı), tanımsız gözde LP, gözsüz LP,
        // gözsüz ama boş LP; göz kullanmayan HLT-NB'de göz kodlu LP.
        EnsureFixture();
        CreateBin(LocationCode(), 'B-OK');
        CreateLpAt('HLT-LOC-1', LocationCode(), 'B-OK', LP.Status::Built);
        AddLpLine('HLT-LOC-1', '', 1, 0);
        CreateLpAt('HLT-LOC-2', LocationCode(), 'B-YOK', LP.Status::Built);
        AddLpLine('HLT-LOC-2', '', 1, 0);
        CreateLpAt('HLT-LOC-3', LocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-LOC-3', '', 1, 0);
        CreateLpAt('HLT-LOC-4', LocationCode(), '', LP.Status::Open);
        CreateLpAt('HLT-LOC-5', NonBinLocationCode(), 'RAF-1', LP.Status::Built);
        AddLpLine('HLT-LOC-5', '', 1, 0);

        // [WHEN]
        Detector.DetectLpLocationMismatch(LocationCode() + '|' + NonBinLocationCode(), Issues);

        // [THEN]
        AssertLpIssue(Issues, 'HLT-LOC-1', false, 0);
        AssertLpIssue(Issues, 'HLT-LOC-2', true, Issues.Severity::Critical);
        AssertLpIssue(Issues, 'HLT-LOC-3', true, Issues.Severity::Warning);
        AssertLpIssue(Issues, 'HLT-LOC-4', false, 0);
        AssertLpIssue(Issues, 'HLT-LOC-5', true, Issues.Severity::Info);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NegativeZeroAndUnknownUnitLpLinesAreReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        EnsureFixture();
        CreateLpAt('HLT-QTY-1', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-QTY-1', 'Q1', -3, 0);
        CreateLpAt('HLT-QTY-2', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-QTY-2', 'Q1', 0, 0);
        CreateLpAt('HLT-QTY-3', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-QTY-3', 'Q1', 4, 0);
        LPLine.SetRange("LP No.", 'HLT-QTY-3');
        LPLine.FindFirst();
        LPLine."Unit of Measure" := 'KOLI-YOK';
        LPLine.Modify(false);
        CreateLpAt('HLT-QTY-4', NonBinLocationCode(), '', LP.Status::Built);
        AddLpLine('HLT-QTY-4', 'Q1', 4, 0);
        // Kullanılmış LP'deki negatif satır taranmaz.
        CreateLpAt('HLT-QTY-5', NonBinLocationCode(), '', LP.Status::Used);
        AddLpLine('HLT-QTY-5', 'Q1', -1, 0);

        Detector.DetectInvalidLpLines(NonBinLocationCode(), Issues);

        AssertLpIssue(Issues, 'HLT-QTY-1', true, Issues.Severity::Critical);
        AssertLpIssue(Issues, 'HLT-QTY-2', true, Issues.Severity::Info);
        AssertLpIssue(Issues, 'HLT-QTY-3', true, Issues.Severity::Warning);
        AssertLpIssue(Issues, 'HLT-QTY-4', false, 0);
        AssertLpIssue(Issues, 'HLT-QTY-5', false, 0);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BlockedItemStockIsReportedAsInfo()
    var
        Issues: Record "DOPSWHS Health Issue";
        Item: Record Item;
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        // [GIVEN] bloke ürün lokasyonda 5 (açık giriş); bloke olmayan ürün de stokta;
        // bloke ürünün kapanmış girişi bulgu değildir.
        EnsureFixture();
        CreateItem(BlockedItemNo());
        Item.Get(BlockedItemNo());
        Item.Blocked := true;
        Item.Modify();
        CreateItemEntry(10, BlockedItemNo(), LocationCode(), '', 5, 5);
        CreateItemEntry(11, ItemNo(), LocationCode(), '', 7, 7);
        CreateItemEntry(12, BlockedItemNo(), NonBinLocationCode(), '', 3, 0);

        // [WHEN]
        Detector.DetectBlockedItemStock(LocationCode() + '|' + NonBinLocationCode(), Issues);

        // [THEN]
        Assert.AreEqual(1, Detector.CategoryTotal(Issues.Category::BlockedItemStock), 'Yalnız stoklu bloke ürün/lokasyon.');
        Issues.FindFirst();
        Assert.AreEqual(BlockedItemNo(), Issues."Item No.", 'Ürün');
        Assert.AreEqual(LocationCode(), Issues."Location Code", 'Lokasyon');
        Assert.AreEqual(5, Issues."Bin Qty. (Base)", 'Miktar');
        Assert.AreEqual(Format(Issues.Severity::Info), Format(Issues.Severity), 'Bilgi');
        Assert.IsFalse(Issues."Fix Available", 'Düzeltme yok.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FailedAndStuckPrintJobsAreReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        Job: Record "DOPSWHS Print Job Queue";
        Detector: Codeunit "DOPSWHS Health Detector";
        FailedJobId: Integer;
        StuckJobId: Integer;
        FreshJobId: Integer;
        SentJobId: Integer;
        OtherLocationJobId: Integer;
    begin
        // [GIVEN]
        EnsureFixture();
        CreatePrinter('HLT-PRN', LocationCode(), true, CurrentDateTime());
        CreatePrinter('HLT-PRN-X', 'HLTX', true, CurrentDateTime());
        FailedJobId := CreateJob('HLT-PRN', Job.Status::Failed, CurrentDateTime(), 'Yazıcıya ulaşılamadı');
        StuckJobId := CreateJob('HLT-PRN', Job.Status::Queued, CurrentDateTime() - 3600000, '');
        FreshJobId := CreateJob('HLT-PRN', Job.Status::Queued, CurrentDateTime(), '');
        SentJobId := CreateJob('HLT-PRN', Job.Status::Sent, CurrentDateTime() - 3600000, '');
        OtherLocationJobId := CreateJob('HLT-PRN-X', Job.Status::Failed, CurrentDateTime(), 'x');

        // [WHEN]
        Detector.DetectPrintJobs(LocationCode(), Issues);

        // [THEN]
        Issues.SetRange("Entry Ref.", FailedJobId);
        Assert.IsTrue(Issues.FindFirst(), 'Bugün başarısız iş bulgu olmalı.');
        Assert.AreEqual(Format(Issues.Severity::Critical), Format(Issues.Severity), 'Başarısız iş kritik.');
        Assert.IsTrue(StrPos(Issues.Detail, 'Yazıcıya ulaşılamadı') > 0, 'Son hata gösterilmeli.');
        Assert.IsTrue(StrPos(Issues."Ref. Text", 'HLT-PRN') > 0, 'Yazıcı gösterilmeli.');
        Issues.SetRange("Entry Ref.", StuckJobId);
        Assert.IsFalse(Issues.IsEmpty(), '10 dakikadan eski kuyruktaki iş bulgu olmalı.');
        Issues.SetRange("Entry Ref.", FreshJobId);
        Assert.IsTrue(Issues.IsEmpty(), 'Yeni kuyruktaki iş bulgu olmamalı.');
        Issues.SetRange("Entry Ref.", SentJobId);
        Assert.IsTrue(Issues.IsEmpty(), 'Gönderilmiş iş bulgu olmamalı.');
        Issues.SetRange("Entry Ref.", OtherLocationJobId);
        Assert.IsTrue(Issues.IsEmpty(), 'Başka depodaki yazıcının işi filtrelenmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StaleOrInactivePrinterMappingsAreReported()
    var
        Issues: Record "DOPSWHS Health Issue";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        // [GIVEN]
        EnsureFixture();
        CreatePrinter('HLT-OFF', LocationCode(), false, 0DT);
        CreatePrinter('HLT-OLD', LocationCode(), true, CurrentDateTime() - 40 * 86400000L);
        CreatePrinter('HLT-OK', LocationCode(), true, CurrentDateTime());
        CreateMapping('HLT-DEV-1', 'HLT-OFF');
        CreateMapping('HLT-DEV-2', 'HLT-OLD');
        CreateMapping('HLT-DEV-3', 'HLT-OK');
        CreateMapping('HLT-DEV-4', 'HLT-GONE');

        // [WHEN]
        Detector.DetectPrinterMappings(LocationCode(), Issues);

        // [THEN]
        AssertMapping(Issues, 'HLT-DEV-1', true);
        AssertMapping(Issues, 'HLT-DEV-2', true);
        AssertMapping(Issues, 'HLT-DEV-3', false);
        AssertMapping(Issues, 'HLT-DEV-4', true);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CategoryKeepsMaxRowsButCountsAll()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
    begin
        EnsureFixture();
        CreateLp('HLT-MAX-1', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-GONE-1');
        CreateLp('HLT-MAX-2', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-GONE-2');
        CreateLp('HLT-MAX-3', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-GONE-3');

        Detector.SetMaxRowsPerCategory(1);
        Detector.DetectOrphanAssignments(LocationCode(), Issues);

        Assert.AreEqual(1, Issues.Count(), 'Tamponda en çok 1 satır.');
        Assert.AreEqual(3, Detector.CategoryTotal(Issues.Category::OrphanAssignment), 'Toplam bütün bulguları saymalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure JsonHasAllCategoriesAndIssueFields()
    var
        Issues: Record "DOPSWHS Health Issue";
        LP: Record "DOPSWHS LP Header";
        Detector: Codeunit "DOPSWHS Health Detector";
        Root: JsonObject;
        Token: JsonToken;
        CategoryToken: JsonToken;
        IssueToken: JsonToken;
        Found: Boolean;
    begin
        EnsureFixture();
        CreateLp('HLT-JSON-1', 'RCV', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'HLT-GONE-J');

        Detector.DetectAll(LocationCode(), Issues);
        Root.ReadFrom(Detector.BuildJson(Issues, LocationCode()));

        Root.Get('categories', Token);
        Assert.AreEqual(9, Token.AsArray().Count(), 'Dokuz kategori');
        Root.Get('locationFilter', Token);
        Assert.AreEqual(LocationCode(), Token.AsValue().AsText(), 'Depo filtresi');
        Root.Get('categories', Token);
        foreach CategoryToken in Token.AsArray() do begin
            CategoryToken.AsObject().Get('key', Token);
            if Token.AsValue().AsText() = 'orphanAssignment' then begin
                CategoryToken.AsObject().Get('issues', Token);
                foreach IssueToken in Token.AsArray() do begin
                    IssueToken.AsObject().Get('lpNo', Token);
                    if Token.AsValue().AsText() = 'HLT-JSON-1' then begin
                        Found := true;
                        IssueToken.AsObject().Get('fixAvailable', Token);
                        Assert.IsTrue(Token.AsValue().AsBoolean(), 'fixAvailable');
                        IssueToken.AsObject().Get('severity', Token);
                        Assert.AreEqual('warning', Token.AsValue().AsText(), 'severity');
                    end;
                end;
            end;
        end;
        Assert.IsTrue(Found, 'Yetim LP JSON''da olmalı.');
        Assert.AreEqual(1, Detector.CategoryFromKey('orphanAssignment'), 'Anahtar → kategori');
        Assert.AreEqual(-1, Detector.CategoryFromKey('yok'), 'Bilinmeyen anahtar');
        Assert.AreEqual(3, Detector.CategoryFromKey('lpSourceEntry'), 'LP kaynak girişi anahtarı');
        Assert.AreEqual(-1, Detector.CategoryFromKey('putAwayWithoutLp'), 'Kitoko''da LP''siz rafa kaldırma kategorisi yok');
    end;

    // ------------------------------------------------------------------
    // Fikstür
    // ------------------------------------------------------------------

    local procedure EnsureFixture()
    var
        UnitOfMeasure: Record "Unit of Measure";
        Location: Record Location;
    begin
        if not UnitOfMeasure.Get('PCS') then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := 'PCS';
            UnitOfMeasure.Insert();
        end;
        CreateItem(ItemNo());
        if not Location.Get(LocationCode()) then begin
            Location.Init();
            Location.Code := LocationCode();
            Location."Bin Mandatory" := true;
            Location.Insert();
        end;
        // Kitoko lokasyonlarının çoğu gibi göz zorunlu olmayan lokasyon.
        if not Location.Get(NonBinLocationCode()) then begin
            Location.Init();
            Location.Code := NonBinLocationCode();
            Location."Bin Mandatory" := false;
            Location.Insert();
        end;
    end;

    local procedure CreateItem(No: Code[20])
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if not Item.Get(No) then begin
            Item.Init();
            Item."No." := No;
            Item.Description := 'Health panel test item';
            Item."Base Unit of Measure" := 'PCS';
            Item.Insert();
        end;
        if not ItemUnitOfMeasure.Get(No, 'PCS') then begin
            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure."Item No." := No;
            ItemUnitOfMeasure.Code := 'PCS';
            ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
            ItemUnitOfMeasure.Insert();
        end;
    end;

    local procedure CreateWhseEntry(Offset: Integer; BinCode: Code[20]; ItemNoValue: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        WhseEntry: Record "Warehouse Entry";
    begin
        WhseEntry.Init();
        WhseEntry."Entry No." := 2147460000 + Offset;
        WhseEntry."Location Code" := LocationCode();
        WhseEntry."Bin Code" := BinCode;
        WhseEntry."Item No." := ItemNoValue;
        WhseEntry."Unit of Measure Code" := 'PCS';
        WhseEntry."Qty. per Unit of Measure" := 1;
        WhseEntry."Lot No." := LotNo;
        WhseEntry.Quantity := Qty;
        WhseEntry."Qty. (Base)" := Qty;
        WhseEntry.Insert(false);
    end;

    local procedure CreateBinContent(BinCode: Code[20]; ItemNoValue: Code[20])
    var
        BinContent: Record "Bin Content";
    begin
        BinContent.Init();
        BinContent."Location Code" := LocationCode();
        BinContent."Bin Code" := BinCode;
        BinContent."Item No." := ItemNoValue;
        BinContent."Unit of Measure Code" := 'PCS';
        BinContent."Qty. per Unit of Measure" := 1;
        BinContent.Insert(false);
    end;

    local procedure CreateLp(LpNo: Code[20]; BinCode: Code[20]; Status: Enum "DOPSWHS LP Status"; AssignedType: Enum "DOPSWHS Assigned Doc Type"; AssignedNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP."Location Code" := LocationCode();
        LP."Bin Code" := BinCode;
        LP.Status := Status;
        LP."Assigned Document Type" := AssignedType;
        LP."Assigned Document No." := AssignedNo;
        LP.Insert(false);
    end;

    local procedure AddLpLine(LpNo: Code[20]; LotNo: Code[50]; Qty: Decimal; SourceEntryNo: Integer)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        if LPLine.FindLast() then;
        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." += 10000;
        LPLine."Item No." := ItemNo();
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Qty;
        LPLine."Lot No." := LotNo;
        LPLine."Source Item Ledger Entry No." := SourceEntryNo;
        LPLine.Insert(false);
    end;

    local procedure LpQty(LpNo: Code[20]): Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.CalcSums(Quantity);
        exit(LPLine.Quantity);
    end;

    local procedure CreateEntry(Offset: Integer; DocumentNo: Code[20]; DocumentLineNo: Integer; LotNo: Code[50]; Qty: Decimal; RemainingQty: Decimal; IsCorrection: Boolean; AppliesToEntryNo: Integer): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460000 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::Purchase;
        Entry."Document Type" := Entry."Document Type"::"Purchase Receipt";
        Entry."Document No." := DocumentNo;
        Entry."Document Line No." := DocumentLineNo;
        Entry."Item No." := ItemNo();
        Entry."Location Code" := LocationCode();
        Entry."Posting Date" := WorkDate();
        Entry."Lot No." := LotNo;
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := RemainingQty;
        Entry.Positive := Qty > 0;
        Entry.Open := RemainingQty <> 0;
        Entry.Correction := IsCorrection;
        Entry."Applies-to Entry" := AppliesToEntryNo;
        Entry.Insert(false);
        exit(Entry."Entry No.");
    end;

    local procedure CreatePutAway(PutAwayNo: Code[20])
    var
        Header: Record "Warehouse Activity Header";
    begin
        Header.Init();
        Header.Type := Header.Type::"Put-away";
        Header."No." := PutAwayNo;
        Header."Location Code" := LocationCode();
        Header.Insert();
    end;

    local procedure CreateLpAt(LpNo: Code[20]; Location: Code[10]; BinCode: Code[20]; Status: Enum "DOPSWHS LP Status")
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP."Location Code" := Location;
        LP."Bin Code" := BinCode;
        LP.Status := Status;
        LP.Insert(false);
    end;

    local procedure CreateBin(Location: Code[10]; BinCode: Code[20])
    var
        Bin: Record Bin;
    begin
        if Bin.Get(Location, BinCode) then
            exit;
        Bin.Init();
        Bin."Location Code" := Location;
        Bin.Code := BinCode;
        Bin.Insert(false);
    end;

    local procedure CreateItemEntry(Offset: Integer; ItemNoValue: Code[20]; Location: Code[10]; LotNo: Code[50]; Qty: Decimal; RemainingQty: Decimal): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460000 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::"Positive Adjmt.";
        Entry."Document No." := 'HLT-ADJ';
        Entry."Item No." := ItemNoValue;
        Entry."Location Code" := Location;
        Entry."Posting Date" := WorkDate();
        Entry."Lot No." := LotNo;
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := RemainingQty;
        Entry.Positive := Qty > 0;
        Entry.Open := RemainingQty <> 0;
        Entry.Insert(false);
        exit(Entry."Entry No.");
    end;

    local procedure AssertLpIssue(var Issues: Record "DOPSWHS Health Issue"; LpNo: Code[20]; Expected: Boolean; ExpectedSeverity: Integer)
    var
        ActualSeverity: Integer;
    begin
        Issues.Reset();
        Issues.SetRange("LP No.", LpNo);
        Assert.AreEqual(Expected, Issues.FindFirst(), StrSubstNo('%1 bulgusu', LpNo));
        ActualSeverity := Issues.Severity;
        if Expected then
            Assert.AreEqual(ExpectedSeverity, ActualSeverity, StrSubstNo('%1 önemi', LpNo));
        Issues.Reset();
    end;

    local procedure CreatePrinter(PrinterCode: Code[20]; PrinterLocation: Code[10]; IsActive: Boolean; LastSeen: DateTime)
    var
        Printer: Record "DOPSWHS Printer";
    begin
        Printer.Init();
        Printer.Code := PrinterCode;
        Printer.Description := 'Health test printer';
        Printer."Location Code" := PrinterLocation;
        Printer.Active := IsActive;
        Printer."Last Seen At" := LastSeen;
        Printer.Insert(false);
    end;

    local procedure CreateJob(PrinterId: Code[50]; Status: Option; Created: DateTime; LastError: Text[250]): Integer
    var
        Job: Record "DOPSWHS Print Job Queue";
    begin
        Job.Init();
        Job."Printer ID" := PrinterId;
        Job."Source Doc" := 'HLT-DOC';
        Job.Status := Status;
        Job.Created := Created;
        Job."Last Error" := LastError;
        Job.Insert(false);
        exit(Job."Job ID");
    end;

    local procedure CreateMapping(DeviceId: Code[50]; PrinterCode: Code[20])
    var
        DeviceMap: Record "DOPSWHS Device Printer Map";
    begin
        DeviceMap.Init();
        DeviceMap."Device ID" := DeviceId;
        DeviceMap.Usage := DeviceMap.Usage::LpLabel;
        DeviceMap."Printer Code" := PrinterCode;
        DeviceMap.Insert(false);
    end;

    local procedure AssertMapping(var Issues: Record "DOPSWHS Health Issue"; DeviceId: Text; Expected: Boolean)
    begin
        Issues.Reset();
        Issues.SetRange(Category, Issues.Category::PrinterMapping);
        Issues.SetRange("Ref. Text", DeviceId);
        Assert.AreEqual(Expected, not Issues.IsEmpty(), StrSubstNo('%1 eşleşmesi bulgusu', DeviceId));
        Issues.Reset();
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('HLT-ITEM');
    end;

    local procedure BlockedItemNo(): Code[20]
    begin
        exit('HLT-BLOCKED');
    end;

    local procedure LocationCode(): Code[10]
    begin
        exit('HLT');
    end;

    local procedure NonBinLocationCode(): Code[10]
    begin
        exit('HLT-NB');
    end;

    var
        Assert: Codeunit "Library Assert";
}
