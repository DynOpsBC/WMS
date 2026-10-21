/// <summary>
/// BADE (21 Eki 2026): a put-away created later from standard BC has one blank-LP
/// Take/Place pair while the receipt LPs stand in the Take bin, some still assigned
/// to the deleted put-away. "LP'ye göre böl" must split the pair by those LPs.
/// </summary>
codeunit 72148 "DOPSWHS PutAway Bin LP Split"
{
    Subtype = Test;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure SplitsDeletedPutAwayLpsIntoOnePairEach()
    var
        LP: Record "DOPSWHS LP Header";
        ActivityLine: Record "Warehouse Activity Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
        Index: Integer;
        LpCount: Integer;
        LineCount: Integer;
        RemainderBaseQty: Decimal;
    begin
        // [GIVEN] PU001130 senaryosu: 45.000'lik tek LP'siz çift; gözde 15 LP,
        // her biri 2812 (mal kabul satırı) + 188 (birleştirilen LP'den) = 3000,
        // hepsi silinmiş bir yerleştirmeye atanmış.
        EnsureFixture();
        CreatePutAway('PA-BLS-1');
        InsertPair('PA-BLS-1', 10000, 'BLS-R1', 'LOT-A', 45000);
        for Index := 1 to 15 do begin
            LpNo := LpCode('BLS1-', Index);
            CreateLp(LpNo, 'BLS-R1', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-BLS-GONE');
            AddLpLine(LpNo, 10000, 'LOT-A', 2812, true);
            AddLpLine(LpNo, 20000, 'LOT-A', 188, false);
        end;

        // [WHEN] önizleme
        ReceiptMgmt.PreviewSplitPutAwayByBinLPs('PA-BLS-1', LpCount, LineCount, RemainderBaseQty);

        // [THEN] önizleme hiçbir şeyi değiştirmez
        Assert.AreEqual(15, LpCount, 'Önizleme 15 LP bulmalı.');
        Assert.AreEqual(30, LineCount, 'Önizleme 30 satır (15 Al/Koy çifti) bildirmeli.');
        Assert.IsTrue(RemainderBaseQty = 0, 'LP''ler çifti tam karşılıyor; kalan olmamalı.');
        Assert.AreEqual(2, CountLines('PA-BLS-1'), 'Önizleme satır oluşturmamalı.');
        LP.Get(LpCode('BLS1-', 1));
        Assert.AreEqual('PA-BLS-GONE', LP."Assigned Document No.", 'Önizleme LP atamasını değiştirmemeli.');

        // [WHEN] bölme
        Assert.AreEqual(30, ReceiptMgmt.SplitPutAwayByBinLPs('PA-BLS-1'), 'Her LP için bir Al ve bir Koy satırı dönmeli.');

        // [THEN] her LP'nin 3000'lik tek Al ve tek Koy satırı var, LP'siz satır kalmadı
        Assert.AreEqual(30, CountLines('PA-BLS-1'), 'Belgede 30 satır olmalı.');
        for Index := 1 to 15 do begin
            LpNo := LpCode('BLS1-', Index);
            AssertLpPair('PA-BLS-1', LpNo, 3000);
            LP.Get(LpNo);
            Assert.AreEqual(Format(LP.Status::Assigned), Format(LP.Status), 'LP atanmış kalmalı.');
            Assert.AreEqual(Format(LP."Assigned Document Type"::WhsePutaway), Format(LP."Assigned Document Type"), 'LP yerleştirmeye atanmalı.');
            Assert.AreEqual('PA-BLS-1', LP."Assigned Document No.", 'LP yeni yerleştirmeye atanmalı.');
            Ledger.SetRange("LP No.", LpNo);
            Ledger.SetRange(Action, Ledger.Action::Released);
            Assert.IsFalse(Ledger.IsEmpty(), 'Yetim atama defter kaydıyla serbest bırakılmalı.');
        end;
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", 'PA-BLS-1');
        ActivityLine.SetRange("LP No.", '');
        Assert.IsTrue(ActivityLine.IsEmpty(), 'LP''siz satır kalmamalı.');
        AssertBalanced('PA-BLS-1', 45000);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure KeepsRemainderOnBlankLpPair()
    var
        LP: Record "DOPSWHS LP Header";
        ActivityLine: Record "Warehouse Activity Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        MaxLpLineNo: Integer;
    begin
        // [GIVEN] 10.000'lik çift, gözde 2 x 3000 LP
        EnsureFixture();
        CreatePutAway('PA-BLS-2');
        InsertPair('PA-BLS-2', 10000, 'BLS-R2', 'LOT-A', 10000);
        CreateLp('BLS2-01', 'BLS-R2', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS2-01', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS2-02', 'BLS-R2', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS2-02', 10000, 'LOT-A', 3000, true);

        // [WHEN]
        Assert.AreEqual(4, ReceiptMgmt.SplitPutAwayByBinLPs('PA-BLS-2'), '2 LP için 4 satır dönmeli.');

        // [THEN] LP satırları + 4000'lik LP''siz çift, toplam değişmedi
        AssertLpPair('PA-BLS-2', 'BLS2-01', 3000);
        AssertLpPair('PA-BLS-2', 'BLS2-02', 3000);
        AssertLpPair('PA-BLS-2', '', 4000);
        AssertBalanced('PA-BLS-2', 10000);

        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", 'PA-BLS-2');
        ActivityLine.SetFilter("LP No.", '<>%1', '');
        ActivityLine.FindLast();
        MaxLpLineNo := ActivityLine."Line No.";
        ActivityLine.SetRange("LP No.", '');
        ActivityLine.FindFirst();
        Assert.IsTrue(ActivityLine."Line No." > MaxLpLineNo, 'Kalan çift LP satırlarından sonra gelmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure IgnoresOtherBinOtherLotMixedAndForeignLps()
    var
        LP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        // [GIVEN] 6000'lik LOT-A çifti; yalnız BLS3-OK uygun
        EnsureFixture();
        CreatePutAway('PA-BLS-3');
        InsertPair('PA-BLS-3', 10000, 'BLS-R3', 'LOT-A', 6000);
        CreatePutAway('PA-BLS-LIVE');

        CreateLp('BLS3-OK', 'BLS-R3', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS3-OK', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS3-BIN', 'BLS-R3X', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS3-BIN', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS3-LOT', 'BLS-R3', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS3-LOT', 10000, 'LOT-B', 3000, true);
        CreateLp('BLS3-MIX', 'BLS-R3', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS3-MIX', 10000, 'LOT-A', 1000, true);
        AddLpLine('BLS3-MIX', 20000, 'LOT-B', 1000, true);
        CreateLp('BLS3-LIVE', 'BLS-R3', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-BLS-LIVE');
        AddLpLine('BLS3-LIVE', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS3-UNB', 'BLS-R3', LP.Status::Unbuilt, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS3-UNB', 10000, 'LOT-A', 3000, true);

        // [WHEN]
        Assert.AreEqual(2, ReceiptMgmt.SplitPutAwayByBinLPs('PA-BLS-3'), 'Yalnız uygun tek LP bölünmeli.');

        // [THEN]
        AssertLpPair('PA-BLS-3', 'BLS3-OK', 3000);
        AssertLpPair('PA-BLS-3', '', 3000);
        AssertBalanced('PA-BLS-3', 6000);
        AssertLpNotOnPutAway('PA-BLS-3', 'BLS3-BIN');
        AssertLpNotOnPutAway('PA-BLS-3', 'BLS3-LOT');
        AssertLpNotOnPutAway('PA-BLS-3', 'BLS3-MIX');
        AssertLpNotOnPutAway('PA-BLS-3', 'BLS3-LIVE');
        AssertLpNotOnPutAway('PA-BLS-3', 'BLS3-UNB');
        LP.Get('BLS3-LIVE');
        Assert.AreEqual('PA-BLS-LIVE', LP."Assigned Document No.", 'Mevcut belgeye atanmış LP''ye dokunulmamalı.');
        LP.Get('BLS3-BIN');
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Başka gözdeki LP değişmemeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RejectsMoreLpQuantityThanThePairAndChangesNothing()
    var
        LP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        // [GIVEN] 3000'lik çift, gözde 2 x 3000 LP
        EnsureFixture();
        CreatePutAway('PA-BLS-4');
        InsertPair('PA-BLS-4', 10000, 'BLS-R4', 'LOT-A', 3000);
        CreateLp('BLS4-01', 'BLS-R4', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS4-01', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS4-02', 'BLS-R4', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS4-02', 10000, 'LOT-A', 3000, true);

        // [WHEN/THEN] hata, hiçbir şey değişmez
        asserterror ReceiptMgmt.SplitPutAwayByBinLPs('PA-BLS-4');
        Assert.ExpectedError('hiçbir Al/Koy çiftine sığmadı');
        Assert.AreEqual(2, CountLines('PA-BLS-4'), 'Satırlar değişmemeli.');
        AssertLpPair('PA-BLS-4', '', 3000);
        LP.Get('BLS4-01');
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'LP ataması değişmemeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure SplitLinesMeetRegisterRules()
    var
        LP: Record "DOPSWHS LP Header";
        PlaceLine: Record "Warehouse Activity Line";
        TakeLine: Record "Warehouse Activity Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        // [GIVEN] 9000'lik çift, 3 x 3000 yetim LP
        EnsureFixture();
        CreatePutAway('PA-BLS-5');
        InsertPair('PA-BLS-5', 10000, 'BLS-R5', 'LOT-A', 9000);
        CreateLp('BLS5-01', 'BLS-R5', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-BLS-GONE5');
        AddLpLine('BLS5-01', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS5-02', 'BLS-R5', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-BLS-GONE5');
        AddLpLine('BLS5-02', 10000, 'LOT-A', 3000, true);
        CreateLp('BLS5-03', 'BLS-R5', LP.Status::Built, LP."Assigned Document Type"::None, '');
        AddLpLine('BLS5-03', 10000, 'LOT-A', 3000, true);

        ReceiptMgmt.SplitPutAwayByBinLPs('PA-BLS-5');

        // [THEN] MovementMgmt.RegisterDirected kuralları: Koy satırında
        // Qty. to Handle = Qty. Outstanding (kısmi LP yok), Al/Koy tabanda dengeli,
        // Al gözü/Koy gözü ve depo belgesi bağı (terminal eşleştirmesi) korunur.
        PlaceLine.SetRange("Activity Type", PlaceLine."Activity Type"::"Put-away");
        PlaceLine.SetRange("No.", 'PA-BLS-5');
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        Assert.AreEqual(3, PlaceLine.Count(), '3 Koy satırı olmalı.');
        PlaceLine.FindSet();
        repeat
            Assert.AreNotEqual('', PlaceLine."LP No.", 'Her Koy satırında LP olmalı.');
            Assert.AreEqual(PlaceLine."Qty. Outstanding", PlaceLine."Qty. to Handle", 'LP satırı tamamıyla işlenecek şekilde hazır olmalı.');
            Assert.AreEqual(PutBin(), PlaceLine."Bin Code", 'Koy gözü korunmalı.');
            Assert.AreEqual('PR-BLS', PlaceLine."Whse. Document No.", 'Depo belgesi bağı korunmalı.');
            Assert.AreEqual(10000, PlaceLine."Whse. Document Line No.", 'Depo belgesi satırı korunmalı.');

            TakeLine.SetRange("Activity Type", PlaceLine."Activity Type");
            TakeLine.SetRange("No.", PlaceLine."No.");
            TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
            TakeLine.SetRange("LP No.", PlaceLine."LP No.");
            Assert.AreEqual(1, TakeLine.Count(), 'Her LP için tek Al satırı olmalı.');
            TakeLine.FindFirst();
            Assert.AreEqual('BLS-R5', TakeLine."Bin Code", 'Al gözü korunmalı.');
            Assert.AreEqual(PlaceLine."Qty. to Handle (Base)", TakeLine."Qty. to Handle (Base)", 'Al/Koy çifti dengeli olmalı.');
            Assert.AreEqual(PlaceLine."Whse. Document Line No.", TakeLine."Whse. Document Line No.", 'Çift aynı depo belgesi satırına bağlı olmalı.');
        until PlaceLine.Next() = 0;
        AssertBalanced('PA-BLS-5', 9000);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OrphanReleaseTouchesOnlyOrphanedLps()
    var
        LP: Record "DOPSWHS LP Header";
        Scope: Record "DOPSWHS LP Header";
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        // [GIVEN]
        EnsureFixture();
        CreatePutAway('PA-ORF-LIVE');
        RegisteredHeader.Init();
        RegisteredHeader.Type := RegisteredHeader.Type::Pick;
        RegisteredHeader."No." := 'RPI-ORF-1';
        RegisteredHeader."Whse. Activity No." := 'PI-ORF-REG';
        RegisteredHeader.Insert();

        CreateLp('ORF-GONE-PA', 'BLS-R6', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-ORF-GONE');
        CreateLp('ORF-GONE-PI', 'BLS-R6', LP.Status::Assigned, LP."Assigned Document Type"::WhsePick, 'PI-ORF-GONE');
        CreateLp('ORF-LIVE-PA', 'BLS-R6', LP.Status::Assigned, LP."Assigned Document Type"::WhsePutaway, 'PA-ORF-LIVE');
        CreateLp('ORF-REG-PI', 'BLS-R6', LP.Status::Assigned, LP."Assigned Document Type"::WhsePick, 'PI-ORF-REG');
        CreateLp('ORF-BUILT', 'BLS-R6', LP.Status::Built, LP."Assigned Document Type"::None, '');

        Scope.SetFilter("No.", 'ORF-*');

        // [WHEN] sayım hiçbir şeyi değiştirmez
        Assert.AreEqual(2, LPMgt.ReleaseOrphanAssignments(Scope, false), 'Yalnız 2 yetim atama sayılmalı.');
        LP.Get('ORF-GONE-PA');
        Assert.AreEqual(Format(LP.Status::Assigned), Format(LP.Status), 'Sayım LP''yi değiştirmemeli.');

        // [WHEN] serbest bırakma
        Assert.AreEqual(2, LPMgt.ReleaseOrphanAssignments(Scope, true), '2 LP serbest bırakılmalı.');

        // [THEN]
        AssertLpStatus('ORF-GONE-PA', LP.Status::Built, '');
        AssertLpStatus('ORF-GONE-PI', LP.Status::Built, '');
        AssertLpStatus('ORF-LIVE-PA', LP.Status::Assigned, 'PA-ORF-LIVE');
        AssertLpStatus('ORF-REG-PI', LP.Status::Assigned, 'PI-ORF-REG');
        AssertLpStatus('ORF-BUILT', LP.Status::Built, '');
    end;

    local procedure EnsureFixture()
    var
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Location: Record Location;
    begin
        if not UnitOfMeasure.Get('PCS') then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := 'PCS';
            UnitOfMeasure.Insert();
        end;
        if not Item.Get(ItemNo()) then begin
            Item.Init();
            Item."No." := ItemNo();
            Item.Description := 'Bin LP split test item';
            Item."Base Unit of Measure" := 'PCS';
            Item.Insert();
        end;
        if not ItemUnitOfMeasure.Get(ItemNo(), 'PCS') then begin
            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure."Item No." := ItemNo();
            ItemUnitOfMeasure.Code := 'PCS';
            ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
            ItemUnitOfMeasure.Insert();
        end;
        if not Location.Get(LocationCode()) then begin
            Location.Init();
            Location.Code := LocationCode();
            Location.Insert();
        end;
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

    local procedure InsertPair(PutAwayNo: Code[20]; FirstLineNo: Integer; TakeBinCode: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        InsertActivityLine(PutAwayNo, FirstLineNo, ActivityLine."Action Type"::Take, TakeBinCode, LotNo, Qty);
        InsertActivityLine(PutAwayNo, FirstLineNo + 10000, ActivityLine."Action Type"::Place, PutBin(), LotNo, Qty);
    end;

    local procedure InsertActivityLine(PutAwayNo: Code[20]; LineNo: Integer; ActionType: Enum "Warehouse Action Type"; BinCode: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.Init();
        ActivityLine."Activity Type" := ActivityLine."Activity Type"::"Put-away";
        ActivityLine."No." := PutAwayNo;
        ActivityLine."Line No." := LineNo;
        ActivityLine."Action Type" := ActionType;
        ActivityLine."Location Code" := LocationCode();
        ActivityLine."Bin Code" := BinCode;
        ActivityLine."Item No." := ItemNo();
        ActivityLine."Unit of Measure Code" := 'PCS';
        ActivityLine."Qty. per Unit of Measure" := 1;
        ActivityLine.Quantity := Qty;
        ActivityLine."Qty. (Base)" := Qty;
        ActivityLine."Qty. Outstanding" := Qty;
        ActivityLine."Qty. Outstanding (Base)" := Qty;
        ActivityLine."Qty. to Handle" := Qty;
        ActivityLine."Qty. to Handle (Base)" := Qty;
        ActivityLine."Lot No." := LotNo;
        ActivityLine."Whse. Document Type" := ActivityLine."Whse. Document Type"::Receipt;
        ActivityLine."Whse. Document No." := 'PR-BLS';
        ActivityLine."Whse. Document Line No." := 10000;
        ActivityLine."Source Type" := Database::"Purchase Line";
        ActivityLine."Source Subtype" := 1;
        ActivityLine."Source No." := 'PO-BLS';
        ActivityLine."Source Line No." := 10000;
        ActivityLine.Insert();
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
        LP.Insert();
    end;

    local procedure AddLpLine(LpNo: Code[20]; LineNo: Integer; LotNo: Code[50]; Qty: Decimal; FromReceipt: Boolean)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := LineNo;
        LPLine."Item No." := ItemNo();
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Qty;
        LPLine."Lot No." := LotNo;
        if FromReceipt then begin
            LPLine."Source Document Type" := LPLine."Source Document Type"::WhseReceipt;
            LPLine."Source Document No." := 'RE-BLS';
            LPLine."Source Document Line No." := 10000;
        end else
            // Bozulan LP'den taşınan miktar: kaynak belge yok, yalnız kayıtlı fiş no.
            LPLine."Source Document No." := 'PR-BLS';
        LPLine.Insert();
    end;

    local procedure AssertLpPair(PutAwayNo: Code[20]; LpNo: Code[20]; ExpectedQty: Decimal)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        ActivityLine.SetRange("LP No.", LpNo);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        Assert.AreEqual(1, ActivityLine.Count(), StrSubstNo('%1 için tek Al satırı olmalı.', LpNo));
        ActivityLine.FindFirst();
        Assert.AreEqual(ExpectedQty, ActivityLine.Quantity, StrSubstNo('%1 Al miktarı', LpNo));
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. (Base)", StrSubstNo('%1 Al taban miktarı', LpNo));
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        Assert.AreEqual(1, ActivityLine.Count(), StrSubstNo('%1 için tek Koy satırı olmalı.', LpNo));
        ActivityLine.FindFirst();
        Assert.AreEqual(ExpectedQty, ActivityLine.Quantity, StrSubstNo('%1 Koy miktarı', LpNo));
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. (Base)", StrSubstNo('%1 Koy taban miktarı', LpNo));
    end;

    local procedure AssertBalanced(PutAwayNo: Code[20]; ExpectedQty: Decimal)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        ActivityLine.CalcSums("Qty. (Base)", "Qty. to Handle (Base)");
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. (Base)", 'Al toplamı değişmemeli.');
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. to Handle (Base)", 'Al işlenecek toplamı');
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.CalcSums("Qty. (Base)", "Qty. to Handle (Base)");
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. (Base)", 'Koy toplamı değişmemeli.');
        Assert.AreEqual(ExpectedQty, ActivityLine."Qty. to Handle (Base)", 'Koy işlenecek toplamı');
    end;

    local procedure AssertLpNotOnPutAway(PutAwayNo: Code[20]; LpNo: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        ActivityLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(ActivityLine.IsEmpty(), StrSubstNo('%1 yerleştirmeye eklenmemeli.', LpNo));
    end;

    local procedure AssertLpStatus(LpNo: Code[20]; ExpectedStatus: Enum "DOPSWHS LP Status"; ExpectedDocNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LpNo);
        Assert.AreEqual(Format(ExpectedStatus), Format(LP.Status), StrSubstNo('%1 durumu', LpNo));
        Assert.AreEqual(ExpectedDocNo, LP."Assigned Document No.", StrSubstNo('%1 atanmış belge', LpNo));
    end;

    local procedure CountLines(PutAwayNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        exit(ActivityLine.Count());
    end;

    local procedure LpCode(Prefix: Text; Index: Integer): Code[20]
    begin
        exit(CopyStr(Prefix + Format(Index, 0, '<Integer,2><Filler Character,0>'), 1, 20));
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('BLS-ITEM');
    end;

    local procedure LocationCode(): Code[10]
    begin
        exit('BLS');
    end;

    local procedure PutBin(): Code[20]
    begin
        exit('A.01.01');
    end;

    var
        Assert: Codeunit Assert;
}
