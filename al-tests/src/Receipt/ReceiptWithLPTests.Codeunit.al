codeunit 72133 "DOPSWHS Receipt With LP Tests"
{
    Subtype = Test;

    [Test]
    procedure PostingFlagDoesNotConflictWithPostedHeaderTransfer()
    var
        ReceiptHeader: Record "Warehouse Receipt Header" temporary;
        PostedHeader: Record "Posted Whse. Receipt Header" temporary;
    begin
        ReceiptHeader."No." := 'LP-TRANSFER-TEST';
        ReceiptHeader."DOPSWHS LP No." := 'LP-TEST';
        ReceiptHeader."DOPSWHS Posting In Progress" := true;

        // Reproduce the standard posting call, including extension fields.
        // This used to fail: source 72423 Boolean -> destination 72423 Code.
        PostedHeader.TransferFields(ReceiptHeader);

        Assert.AreEqual(ReceiptHeader."No.", PostedHeader."No.", 'Standard receipt header transfer must complete while the posting guard is set.');
        Assert.AreEqual('', PostedHeader."DOPSWHS LP No.", 'The posting Boolean must not be copied into the LP reference. LP propagation assigns that reference separately.');
    end;

    [Test]
    procedure ReceiptLpContentIsCreatedOnlyBySuccessfulPost()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
    begin
        TestHelper.EnsureSetup();
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-S3-LP', 30);

        LpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(LpNo, WhseReceiptHeader."DOPSWHS LP No.", 'Started LP must immediately be linked to the receipt header.');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        // Same PATCH is retried and then edited. Before posting, the LP must
        // remain an empty draft carrying only the final planned quantity.
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 5, '', '', 0D, LpNo, 'RECEIVE');
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Confirming a draft receipt must not put item, lot or quantity inside the LP.');
        LP.Get(LpNo);
        Assert.AreEqual(5, LP."Planned Quantity", 'The empty draft LP must retain only its final planned quantity.');
        Assert.AreEqual(WhseReceiptLine."No.", LP."Pending Receipt No.", 'The empty LP must remain linked to its pending receipt.');
        // "LP Kapat" taslak paleti kayıt yapmadan kapatır; içerik yine yalnız kayıtta oluşur.
        ReceiptMgmt.StopLP(WhseReceiptHeader, LpNo, false);
        LP.Get(LpNo);
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Closing a receipt draft must close the pallet without posting.');
        LPLine.Reset();
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Closing a receipt draft must not write LP contents before posting.');

        ReceiptMgmt.PostReceipt(WhseReceiptHeader, false, false);

        LPLine.Reset();
        LPLine.SetRange("LP No.", LpNo);
        LPLine.FindFirst();
        Assert.AreEqual(30, LPLine."Source Document Quantity", 'Posted LP line must retain the total receipt-line quantity for MTE printing.');
        Assert.AreEqual(5, LPLine.Quantity, 'Successful posting must materialize the final receipt quantity once.');
        Assert.AreEqual(1, LPLine.Count(), 'Successful posting must create exactly one physical LP line.');
        Assert.AreEqual(WhseReceiptLine."No.", LPLine."Source Document No.", 'Posted LP line must retain its receipt reference.');
        LP.Get(LpNo);
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Successful posting must close the materialized LP.');
        Assert.AreEqual('', LP."Pending Receipt No.", 'A posted LP must no longer be pending.');
        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(LpNo, PostedWhseReceiptLine."LP No.", 'Posted receipt line must keep LP No.');
    end;

    [Test]
    procedure StartAfterClosingEmptyLpCreatesNextLp()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        FirstLP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        FirstLpNo: Code[20];
        SecondLpNo: Code[20];
    begin
        TestHelper.EnsureSetup();
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-LP-RESTART', 20);

        FirstLpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        // Boş palet kapatılamaz; önce satır eklenir.
        asserterror ReceiptMgmt.StopLP(WhseReceiptHeader, FirstLpNo, false);
        Assert.ExpectedError('boş, kapatılamaz');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 20, '', '', 0D, FirstLpNo, 'RECEIVE');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        ReceiptMgmt.StopLP(WhseReceiptHeader, FirstLpNo, false);
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(FirstLpNo, WhseReceiptHeader."DOPSWHS LP No.", 'Closing an LP must preserve the receipt LP pointer for reopening.');

        SecondLpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        Assert.AreNotEqual(FirstLpNo, SecondLpNo, 'Starting after a physically closed LP must create the next LP.');
        FirstLP.Get(FirstLpNo);
        Assert.AreEqual(Format(FirstLP.Status::Built), Format(FirstLP.Status), 'The physically closed LP must stay built.');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(SecondLpNo, WhseReceiptHeader."DOPSWHS LP No.", 'The receipt must point to the newly opened LP.');
    end;

    [Test]
    procedure BulkReceiptCountsOnlyCurrentBuiltPalletsOnTheSingleSourceLine()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-BULK-ONE-LINE', 100);
        CreateReceiptLP('LP-BULK-01', WhseReceiptLine, 50, true);
        CreateReceiptLP('LP-BULK-02', WhseReceiptLine, 50, true);
        // Önceki kısmi kabulden kalan atanmış LP yeni dalgaya katılmamalı.
        CreateReceiptLP('LP-BULK-OLD', WhseReceiptLine, 25, false);

        Assert.AreEqual(
            2,
            ReceiptMgmt.BulkLpCountForReceiptLine(WhseReceiptLine),
            'Two physical LPs must stay attached to one unchanged receipt line.');
    end;

    [Test]
    procedure CancelledReceiptRemovesItsUnpostedLpQuantity()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-LP', 50);
        CreateReceiptLP('LP-CANCEL-01', WhseReceiptLine, 50, true);

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-01');
        Assert.AreEqual(Format(LP.Status::Unbuilt), Format(LP.Status), 'Cancelled receipt LP must be unbuilt.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'Cancelled receipt must not leave quantity inside its LP.');
    end;

    [Test]
    procedure CancelledReceiptClearsItsEmptyPendingLp()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-DRAFT', 50);
        LP.Init();
        LP."No." := 'LP-CANCEL-DRAFT';
        LP.Status := LP.Status::Open;
        LP."Planned Quantity" := 50;
        LP."Pending Receipt No." := WhseReceiptHeader."No.";
        LP."Pending Receipt Line No." := WhseReceiptLine."Line No.";
        LP.Insert();

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-DRAFT');
        Assert.AreEqual(Format(LP.Status::Unbuilt), Format(LP.Status), 'Cancelled draft LP must be unbuilt.');
        Assert.AreEqual(0, LP."Planned Quantity", 'Cancelled draft LP must not retain a planned stock quantity.');
        Assert.AreEqual('', LP."Pending Receipt No.", 'Cancelled draft LP must not retain a receipt reference.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'Cancelled draft LP must remain empty.');
    end;

    [Test]
    procedure CancelledReceiptNeverChangesAssignedLp()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-SAFE', 50);
        CreateReceiptLP('LP-CANCEL-02', WhseReceiptLine, 50, false);

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-02');
        Assert.AreEqual(Format(LP.Status::Assigned), Format(LP.Status), 'Posted or assigned LP must never be changed by receipt cancellation.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsFalse(LPLine.IsEmpty(), 'Assigned LP quantity must remain intact.');
    end;

    [Test]
    procedure PendingReceiptLpCannotBeEditedOutsideReceipt()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LP.Init();
        LP."No." := 'LP-PENDING-GUARD';
        LP.Status := LP.Status::Open;
        LP."Pending Receipt No." := 'RE-PENDING-GUARD';
        LP."Pending Receipt Line No." := 10000;
        LP."Planned Quantity" := 50;
        LP.Insert();

        asserterror LPMgt.AddLineFromBin(LP, 'ITEM', 'PCS', 50, '', '', 'BIN', 'TEST');
        Assert.ExpectedError('mal kabulünü bekliyor');
        asserterror LPMgt.Stop(LP, false);
        Assert.ExpectedError('mal kabulünü bekliyor');
        asserterror LPMgt.MoveToBin(LP, 'OTHER-BIN', 'TEST');
        Assert.ExpectedError('mal kabulünü bekliyor');
        asserterror LPMgt.Unbuild(LP);
        Assert.ExpectedError('mal kabulünü bekliyor');
        asserterror LP.Delete(true);
        Assert.ExpectedError('mal kabulünü bekliyor');

        LP.Get('LP-PENDING-GUARD');
        Assert.AreEqual(50, LP."Planned Quantity", 'Blocked external actions must preserve the receipt plan.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'A pending receipt LP must stay empty.');
    end;

    [Test]
    procedure ReconfirmBulkRowPreservesEachPalletQuantity()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        Index: Integer;
    begin
        CreateReceipt(Header, Line, 'PO-BULK-RECONFIRM', 100);
        for Index := 1 to 2 do begin
            Clear(LP);
            LP."No." := 'LP-RECONFIRM-' + Format(Index);
            LP.Status := LP.Status::Open;
            LP."Pending Receipt No." := Line."No.";
            LP."Pending Receipt Line No." := Line."Line No.";
            LP."Planned Quantity" := 50;
            LP.Insert();
        end;

        ReceiptMgmt.ConfirmLine(Line, 100, '', '', 0D, 'LP-RECONFIRM-1', 'RECEIVE');

        LP.Get('LP-RECONFIRM-1');
        Assert.AreEqual(50, LP."Planned Quantity", 'Reconfirming the total must preserve the first pallet allocation.');
        LP.Get('LP-RECONFIRM-2');
        Assert.AreEqual(50, LP."Planned Quantity", 'Reconfirming the total must preserve the second pallet allocation.');
        Assert.AreEqual('', Line."DOPSWHS LP No.", 'A bulk source row must not point exclusively at the first pallet.');
        asserterror ReceiptMgmt.ConfirmLine(Line, 90, '', '', 0D, 'LP-RECONFIRM-1', 'RECEIVE');
        Assert.ExpectedError('palet toplamıyla aynı olmalıdır');
    end;

    [Test]
    procedure TwoReceiptLotsKeepOneSourceLineAndSeparatePalletContents()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        SupplierLot: Record "Lot No. Information";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LotNo: Code[50];
        SerialNo: Code[50];
        ExpiryDate: Date;
    begin
        CreateMultiLotFixture(Header, Line);
        ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 1000,
            '[{"groupId":"G1","quantity":400,"lotNo":"A102370","supplierLotNo":"SUP-400"},' +
            '{"groupId":"G2","quantity":600,"lotNo":"A102371","supplierLotNo":"SUP-600"}]',
            'PALLET-EUR', false, '');
        AssertTrackingQuantity(Line, 'A102370', 400);
        AssertTrackingQuantity(Line, 'A102371', 600);
        LP.SetRange("Pending Receipt No.", Header."No.");
        Assert.AreEqual(2, LP.Count(), 'Two empty physical LP drafts are required.');
        LPLine.SetRange("Source Document No.", Header."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'Distribution must not create stock before posting.');
        // Exercise an old client's repeated single-lot PATCH before posting.
        ReceiptMgmt.GetItemTracking(Line, LotNo, SerialNo, ExpiryDate);
        ReceiptMgmt.ConfirmLine(Line, 1000, LotNo, '', ExpiryDate, Header."DOPSWHS LP No.", '');
        AssertTrackingQuantity(Line, 'A102370', 400);
        AssertTrackingQuantity(Line, 'A102371', 600);
        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        AssertTrackingQuantity(Line, 'A102370', 400);
        AssertTrackingQuantity(Line, 'A102371', 600);
        LPLine.SetRange("Lot No.", 'A102370');
        LPLine.FindFirst();
        Assert.AreEqual(400, LPLine.Quantity, 'First LP must retain the 400-unit lot.');
        LPLine.SetRange("Lot No.", 'A102371');
        LPLine.FindFirst();
        Assert.AreEqual(600, LPLine.Quantity, 'Second LP must retain the 600-unit lot.');
        Assert.AreEqual(Line."Line No.", LPLine."Source Document Line No.", 'Both LPs refer to the original receipt line.');
        Line.SetRange("No.", Header."No.");
        Assert.AreEqual(1, Line.Count(), 'Lots must not split the purchase or receipt source line.');
        Assert.IsTrue(LP.IsEmpty(), 'Materialized LPs must no longer be pending.');
        SupplierLot.Get(Line."Item No.", '', 'A102371');
        Assert.AreEqual('SUP-600', SupplierLot.Description, 'Second lot retains its supplier mapping.');
    end;

    [Test]
    procedure PalletsInOneGroupShareOneGeneratedLot()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        FirstLot: Code[50];
        SecondLot: Code[50];
    begin
        CreateMultiLotFixture(Header, Line);
        ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 1000,
            '[{"groupId":"G1","quantity":200},{"groupId":"G1","quantity":200},' +
            '{"groupId":"G2","quantity":600}]', 'PALLET-EUR', false, '');
        LP.SetRange("Pending Receipt No.", Header."No.");
        LP.FindSet();
        FirstLot := LP."Pending Receipt Lot No.";
        Assert.AreNotEqual('', FirstLot, 'First group must receive an internal lot.');
        LP.Next();
        Assert.AreEqual(FirstLot, LP."Pending Receipt Lot No.", 'Two pallets in the same group share the generated lot.');
        LP.Next();
        SecondLot := LP."Pending Receipt Lot No.";
        Assert.AreNotEqual(FirstLot, SecondLot, 'Another group must get a different lot.');
        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        AssertTrackingQuantity(Line, FirstLot, 400);
        AssertTrackingQuantity(Line, SecondLot, 600);
    end;

    [Test]
    procedure LegacyCommonGroupStillCreatesOneTrackingAllocation()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateMultiLotFixture(Header, Line);
        ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 1000,
            '[{"quantity":400,"lotNo":"COMMON"},{"quantity":600}]', 'PALLET-EUR', false, '');
        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        AssertTrackingQuantity(Line, 'COMMON', 1000);
    end;

    [Test]
    procedure SameInternalLotCannotUseDifferentSuppliers()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateMultiLotFixture(Header, Line);
        asserterror ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 1000,
            '[{"groupId":"G1","quantity":400,"lotNo":"COMMON","supplierLotNo":"SUP-A"},' +
            '{"groupId":"G2","quantity":600,"lotNo":"COMMON","supplierLotNo":"SUP-B"}]',
            'PALLET-EUR', false, '');
        Assert.ExpectedError('tedarikçi lotuyla eşleştirilmiş');
    end;

    [Test]
    procedure MultiLotReceiptRejectsQuantityMismatch()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateMultiLotFixture(Header, Line);
        asserterror ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 1000,
            '[{"groupId":"G1","quantity":400,"lotNo":"A"},{"groupId":"G2","quantity":500,"lotNo":"B"}]',
            'PALLET-EUR', false, '');
        Assert.ExpectedError('LP miktarları toplam kabul miktarına eşit olmalıdır');
    end;

    [Test]
    procedure ExcludedLotPlanWaitsForNextWaveAndCancellationClearsIt()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
    begin
        CreateMultiLotFixture(Header, Line);
        ReceiptMgmt.CreateBulkLPDistribution(Header, Line."Line No.", 400,
            '[{"groupId":"G1","quantity":400,"lotNo":"A102370"}]', 'PALLET-EUR', false, '');
        LP.SetRange("Pending Receipt No.", Header."No.");
        LP.FindFirst();
        LpNo := LP."No.";
        ReceiptMgmt.ExcludeLineFromPost(Line);
        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        LP.Get(LpNo);
        Assert.IsTrue(LP."Receipt Tracking Staged", 'Excluded line must retain its lot plan.');
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Excluded line must not materialize stock.');
        ReceiptMgmt.CleanupCanceledReceiptLPs(Header."No.");
        LP.Get(LpNo);
        Assert.AreEqual('', LP."Pending Receipt Lot No.", 'Cancellation clears staged tracking.');
        Assert.IsFalse(LP."Receipt Tracking Staged", 'Cancellation clears the staging marker.');
    end;

    [Test]
    procedure OneLpCarriesBottleAndCap()
    var
        Header: Record "Warehouse Receipt Header";
        BottleLine: Record "Warehouse Receipt Line";
        CapLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
    begin
        // BADE canlı (8 Eki 2026): şişe ve kapak ayrı madde, fiziksel olarak tek
        // palet. İkinci satır "LP'si başka bir mal kabul satırı için bekliyor" diyordu.
        CreateBottleCapFixture(Header, BottleLine, CapLine);
        LpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');
        ReceiptMgmt.ConfirmLine(BottleLine, 30, '', '', 0D, LpNo, '');
        ReceiptMgmt.ConfirmLine(CapLine, 30, '', '', 0D, LpNo, '');
        LP.Get(LpNo);
        Assert.AreEqual(60, LP."Planned Quantity", 'The mixed draft must show the total of both receipt lines.');
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Contents must not be written before posting.');

        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        ReceiptMgmt.EnsureReceiptLinesHaveLp(Header."No.", LpNo);

        AssertLpLine(LpNo, BottleLine, 'RCPT-BOTTLE', 30);
        AssertLpLine(LpNo, CapLine, 'RCPT-CAP', 30);
        Assert.AreEqual(2, LPLine.Count(), 'One pallet must carry both products.');
    end;

    [Test]
    procedure EmptyLpCannotBeClosedAndReadyLinesAreAttachedExplicitly()
    var
        Header: Record "Warehouse Receipt Header";
        BottleLine: Record "Warehouse Receipt Line";
        CapLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LineNos: List of [Integer];
        LpNo: Code[20];
    begin
        // Önce miktar -> LP Başlat -> LP Kapat -> Naklet: boş LP kapanıp stok LP'siz giriyordu.
        CreateBottleCapFixture(Header, BottleLine, CapLine);
        ReceiptMgmt.ConfirmLine(BottleLine, 20, '', '', 0D, '', '');
        ReceiptMgmt.ConfirmLine(CapLine, 8, '', '', 0D, '', '');
        LpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');

        asserterror ReceiptMgmt.StopLP(Header, LpNo, false);
        Assert.ExpectedError('boş, kapatılamaz');

        LineNos.Add(BottleLine."Line No.");
        LineNos.Add(CapLine."Line No.");
        Assert.AreEqual(2, ReceiptMgmt.AttachLinesToLp(Header, LpNo, LineNos), 'Both ready lines must join the LP.');
        ReceiptMgmt.StopLP(Header, LpNo, false);
        LP.Get(LpNo);
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'A pallet with lines can be closed before posting.');

        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        ReceiptMgmt.EnsureReceiptLinesHaveLp(Header."No.", LpNo);
        AssertLpLine(LpNo, BottleLine, 'RCPT-BOTTLE', 20);
        AssertLpLine(LpNo, CapLine, 'RCPT-CAP', 8);
    end;

    [Test]
    procedure LineWithoutLpBlocksPostingOfAnLpReceipt()
    var
        Header: Record "Warehouse Receipt Header";
        BottleLine: Record "Warehouse Receipt Line";
        CapLine: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LineNos: List of [Integer];
        LpNo: Code[20];
    begin
        // Birinci satıra miktar -> LP Başlat -> ikinci satır LP'ye -> Naklet:
        // ilk satır LP'siz kalıyordu. Nakil satırı adıyla durmalı.
        CreateBottleCapFixture(Header, BottleLine, CapLine);
        ReceiptMgmt.ConfirmLine(BottleLine, 12, '', '', 0D, '', '');
        LpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');
        ReceiptMgmt.ConfirmLine(CapLine, 12, '', '', 0D, LpNo, '');

        // Operatör "Şimdi Değil" dediyse sunucu satırı açık LP'ye kendiliğinden bağlamaz.
        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        BottleLine.Get(BottleLine."No.", BottleLine."Line No.");
        Assert.AreEqual('', BottleLine."DOPSWHS LP No.", 'A line must join an LP only with the operator''s confirmation.');
        asserterror ReceiptMgmt.EnsureReceiptLinesHaveLp(Header."No.", LpNo);
        Assert.ExpectedError('RCPT-BOTTLE');
    end;

    [Test]
    procedure OpenEmptyLpDoesNotSilentlyTakeReadyLines()
    var
        Header: Record "Warehouse Receipt Header";
        BottleLine: Record "Warehouse Receipt Line";
        CapLine: Record "Warehouse Receipt Line";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
    begin
        // Önce miktar -> LP Başlat -> "Şimdi Değil" -> Naklet: LP boş kalır, nakil durur.
        CreateBottleCapFixture(Header, BottleLine, CapLine);
        ReceiptMgmt.ConfirmLine(BottleLine, 20, '', '', 0D, '', '');
        ReceiptMgmt.ConfirmLine(CapLine, 8, '', '', 0D, '', '');
        LpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');

        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Unconfirmed lines must not be written into the open LP.');
        asserterror ReceiptMgmt.EnsureReceiptLinesHaveLp(Header."No.", LpNo);
        Assert.ExpectedError('bir LP''ye bağlı değil');
    end;

    [Test]
    procedure ClosedPalletKeepsItsLineWhileAnotherLpIsActive()
    var
        Header: Record "Warehouse Receipt Header";
        BottleLine: Record "Warehouse Receipt Line";
        CapLine: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        FirstLpNo: Code[20];
        SecondLpNo: Code[20];
    begin
        // LP1 kapat -> LP2 başlat -> LP1 satırını düzelt: terminal aktif LP2'yi
        // gönderiyor; satır LP2'ye taşınmamalı.
        CreateBottleCapFixture(Header, BottleLine, CapLine);
        FirstLpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');
        ReceiptMgmt.ConfirmLine(BottleLine, 15, '', '', 0D, FirstLpNo, '');
        Header.Get(Header."No.");
        ReceiptMgmt.StopLP(Header, FirstLpNo, false);
        SecondLpNo := ReceiptMgmt.StartLP(Header, 'PALLET-EUR');
        Assert.AreNotEqual(FirstLpNo, SecondLpNo, 'A closed pallet must lead to a new LP.');
        ReceiptMgmt.ConfirmLine(CapLine, 6, '', '', 0D, SecondLpNo, '');

        // Gerçek PATCH gibi: API gelen LP2'yi kayda yazar ve öyle gönderir.
        BottleLine.Get(BottleLine."No.", BottleLine."Line No.");
        BottleLine."DOPSWHS LP No." := SecondLpNo;
        BottleLine."Qty. to Receive" := 14;
        ReceiptMgmt.ConfirmLine(BottleLine, 14, '', '', 0D, SecondLpNo, '');
        BottleLine.Get(BottleLine."No.", BottleLine."Line No.");
        Assert.AreEqual(FirstLpNo, BottleLine."DOPSWHS LP No.", 'Editing a line of a closed pallet must keep it on that pallet.');

        ReceiptMgmt.PrepareReceiptLPs(Header."No.");
        AssertLpLine(FirstLpNo, BottleLine, 'RCPT-BOTTLE', 14);
        AssertLpLine(SecondLpNo, CapLine, 'RCPT-CAP', 6);
    end;

    local procedure AssertLpLine(LpNo: Code[20]; ReceiptLine: Record "Warehouse Receipt Line"; ItemNo: Code[20]; ExpectedQty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Source Document No.", ReceiptLine."No.");
        LPLine.SetRange("Source Document Line No.", ReceiptLine."Line No.");
        Assert.IsTrue(LPLine.FindFirst(), StrSubstNo('LP %1 must contain receipt line %2.', LpNo, ReceiptLine."Line No."));
        Assert.AreEqual(ItemNo, LPLine."Item No.", StrSubstNo('LP %1 item for receipt line %2.', LpNo, ReceiptLine."Line No."));
        Assert.AreEqual(ExpectedQty, LPLine.Quantity, StrSubstNo('LP %1 quantity for receipt line %2.', LpNo, ReceiptLine."Line No."));
    end;

    /// <summary>Bir satınalma siparişinde iki farklı madde: şişe ve kapak.</summary>
    local procedure CreateBottleCapFixture(var Header: Record "Warehouse Receipt Header"; var BottleLine: Record "Warehouse Receipt Line"; var CapLine: Record "Warehouse Receipt Line")
    var
        Setup: Record "DOPSWHS Setup";
        Helper: Codeunit "DOPSWHS Test Helper";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        NoSeries: Record "No. Series";
        Uom: Record "Unit of Measure";
        Location: Record Location;
        PurchaseHeader: Record "Purchase Header";
    begin
        Setup := Helper.EnsureSetup();
        if not NoSeries.Get('RCPT-LP') then
            SeedReceiptSeries('RCPT-LP', 'RLP000001');
        Setup."LP No. Series" := 'RCPT-LP';
        Setup.Modify();
        SetupWizard.SeedDefaultLPTemplates();
        if not Uom.Get('PCS') then begin
            Uom.Code := 'PCS';
            Uom.Insert();
        end;
        if not Location.Get('RCPT-MIX') then begin
            Location.Code := 'RCPT-MIX';
            Location.Insert();
        end;
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
        PurchaseHeader."No." := 'RCPT-MIX';
        PurchaseHeader.Insert();
        Header."No." := 'RCPT-MIX';
        Header."Location Code" := Location.Code;
        Header.Insert();
        CreateMixLine(Header, PurchaseHeader, BottleLine, 10000, 'RCPT-BOTTLE', 'Şişe - cam şeffaf');
        CreateMixLine(Header, PurchaseHeader, CapLine, 20000, 'RCPT-CAP', 'Kapak - damlalık');
    end;

    local procedure CreateMixLine(Header: Record "Warehouse Receipt Header"; PurchaseHeader: Record "Purchase Header"; var Line: Record "Warehouse Receipt Line"; LineNo: Integer; ItemNo: Code[20]; ItemDescription: Text[100])
    var
        Item: Record Item;
        ItemUom: Record "Item Unit of Measure";
        PurchaseLine: Record "Purchase Line";
    begin
        Item."No." := ItemNo;
        Item.Description := ItemDescription;
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert();
        ItemUom."Item No." := ItemNo;
        ItemUom.Code := 'PCS';
        ItemUom."Qty. per Unit of Measure" := 1;
        ItemUom.Insert();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := LineNo;
        PurchaseLine.Type := PurchaseLine.Type::Item;
        PurchaseLine."No." := ItemNo;
        PurchaseLine."Location Code" := Header."Location Code";
        PurchaseLine."Unit of Measure Code" := 'PCS';
        PurchaseLine."Qty. per Unit of Measure" := 1;
        PurchaseLine.Quantity := 100;
        PurchaseLine."Quantity (Base)" := 100;
        PurchaseLine."Outstanding Quantity" := 100;
        PurchaseLine."Outstanding Qty. (Base)" := 100;
        PurchaseLine.Insert();
        Line."No." := Header."No.";
        Line."Line No." := LineNo;
        Line."Source Type" := Database::"Purchase Line";
        Line."Source Subtype" := 1;
        Line."Source No." := PurchaseHeader."No.";
        Line."Source Line No." := LineNo;
        Line."Item No." := ItemNo;
        Line.Description := ItemDescription;
        Line."Location Code" := Header."Location Code";
        Line."Unit of Measure Code" := 'PCS';
        Line."Qty. per Unit of Measure" := 1;
        Line.Quantity := 100;
        Line."Qty. (Base)" := 100;
        Line."Qty. Outstanding" := 100;
        Line."Qty. Outstanding (Base)" := 100;
        Line.Insert();
    end;

    local procedure AssertTrackingQuantity(Line: Record "Warehouse Receipt Line"; LotNo: Code[50]; ExpectedQty: Decimal)
    var
        Entry: Record "Reservation Entry";
    begin
        Entry.SetRange("Source Type", Database::"Purchase Line");
        Entry.SetRange("Source Subtype", 1);
        Entry.SetRange("Source ID", Line."Source No.");
        Entry.SetRange("Source Ref. No.", Line."Source Line No.");
        Entry.SetRange("Lot No.", LotNo);
        Assert.AreEqual(1, Entry.Count(), 'Pallet quantities must be aggregated once per lot.');
        Entry.FindFirst();
        Assert.AreEqual(ExpectedQty, Entry."Quantity (Base)", 'Tracking quantity must remain lot-specific.');
    end;

    local procedure CreateMultiLotFixture(var Header: Record "Warehouse Receipt Header"; var Line: Record "Warehouse Receipt Line")
    var
        Setup: Record "DOPSWHS Setup";
        Helper: Codeunit "DOPSWHS Test Helper";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        Uom: Record "Unit of Measure";
        ItemUom: Record "Item Unit of Measure";
        Location: Record Location;
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
    begin
        Setup := Helper.EnsureSetup();
        SeedReceiptSeries('RCPT-LP', 'RLP000001');
        SeedReceiptSeries('RCPT-LOT', 'RLOT000001');
        Setup."LP No. Series" := 'RCPT-LP';
        Setup.Modify();
        SetupWizard.SeedDefaultLPTemplates();
        if not Uom.Get('PCS') then begin
            Uom.Code := 'PCS';
            Uom.Insert();
        end;
        Tracking.Code := 'RCPT-LOT';
        Tracking."Lot Specific Tracking" := true;
        Tracking.Insert();
        Item."No." := 'RCPT-MULTI';
        Item.Description := 'Multi-lot receipt regression';
        Item."Base Unit of Measure" := 'PCS';
        Item."Item Tracking Code" := Tracking.Code;
        Item."Lot Nos." := 'RCPT-LOT';
        Item.Insert();
        ItemUom."Item No." := Item."No.";
        ItemUom.Code := 'PCS';
        ItemUom."Qty. per Unit of Measure" := 1;
        ItemUom.Insert();
        Location.Code := 'RCPT-LOT';
        Location.Insert();
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
        PurchaseHeader."No." := 'RCPT-MULTI';
        PurchaseHeader.Insert();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Type := PurchaseLine.Type::Item;
        PurchaseLine."No." := Item."No.";
        PurchaseLine."Location Code" := Location.Code;
        PurchaseLine."Unit of Measure Code" := 'PCS';
        PurchaseLine."Qty. per Unit of Measure" := 1;
        PurchaseLine.Quantity := 1000;
        PurchaseLine."Quantity (Base)" := 1000;
        PurchaseLine."Outstanding Quantity" := 1000;
        PurchaseLine."Outstanding Qty. (Base)" := 1000;
        PurchaseLine.Insert();
        Header."No." := 'RCPT-MULTI';
        Header."Location Code" := Location.Code;
        Header.Insert();
        Line."No." := Header."No.";
        Line."Line No." := 10000;
        Line."Source Type" := Database::"Purchase Line";
        Line."Source Subtype" := 1;
        Line."Source No." := PurchaseHeader."No.";
        Line."Source Line No." := PurchaseLine."Line No.";
        Line."Item No." := Item."No.";
        Line."Location Code" := Location.Code;
        Line."Unit of Measure Code" := 'PCS';
        Line."Qty. per Unit of Measure" := 1;
        Line.Quantity := 1000;
        Line."Qty. (Base)" := 1000;
        Line."Qty. Outstanding" := 1000;
        Line."Qty. Outstanding (Base)" := 1000;
        Line.Insert();
    end;

    local procedure SeedReceiptSeries(SeriesCode: Code[20]; StartNo: Code[20])
    var
        NoSeries: Record "No. Series";
        SeriesLine: Record "No. Series Line";
    begin
        NoSeries.Code := SeriesCode;
        NoSeries."Default Nos." := true;
        NoSeries.Insert();
        SeriesLine."Series Code" := SeriesCode;
        SeriesLine."Line No." := 10000;
        SeriesLine."Starting No." := StartNo;
        SeriesLine."Increment-by No." := 1;
        SeriesLine.Insert();
    end;

    local procedure CreateReceiptLP(LpNo: Code[20]; ReceiptLine: Record "Warehouse Receipt Line"; Qty: Decimal; IsCurrent: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        LP.Init();
        LP."No." := LpNo;
        if IsCurrent then
            LP.Status := LP.Status::Built
        else
            LP.Status := LP.Status::Assigned;
        LP.Insert();

        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := 10000;
        LPLine."Item No." := ReceiptLine."Item No.";
        LPLine."Variant Code" := ReceiptLine."Variant Code";
        LPLine."Unit of Measure" := ReceiptLine."Unit of Measure Code";
        LPLine.Quantity := Qty;
        LPLine."Source Document Type" := LPLine."Source Document Type"::WhseReceipt;
        LPLine."Source Document No." := ReceiptLine."No.";
        LPLine."Source Document Line No." := ReceiptLine."Line No.";
        LPLine.Insert();
    end;

    local procedure CreateReceipt(var Header: Record "Warehouse Receipt Header"; var Line: Record "Warehouse Receipt Line"; SourceNo: Code[20]; Qty: Decimal)
    begin
        Header.Init();
        Header."No." := SourceNo + '-RCPT';
        Header."Location Code" := 'BLUE';
        Header.Insert(true);

        Line.Init();
        Line."No." := Header."No.";
        Line."Line No." := 10000;
        Line."Source No." := SourceNo;
        Line."Item No." := 'ITEM-S3';
        Line.Description := 'Sprint 3 LP receipt item';
        Line."Unit of Measure Code" := 'PCS';
        Line.Quantity := Qty;
        Line."Qty. to Receive" := Qty;
        Line."Bin Code" := 'RECEIVE';
        Line.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
