codeunit 72153 "DOPSWHS Reclass LP Tests"
{
    // BADE (22 Eki 2026): HM.00516 / lot H100807. SKT değiştiren madde yeniden
    // sınıflandırması eski mal kabul girişini kapattı, yeni SKT'li pozitif
    // transfer girişi açtı; LP satırları eski girişte ve eski SKT'de kaldı.
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Item Ledger Entry" = rimd,
        tabledata "Item Application Entry" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReclassWithNewExpiryRelinksLpsAndUpdatesExpiry()
    var
        NewEntry: Record "Item Ledger Entry";
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
    begin
        Seed();
        SetupReclass(100, 0, 100, LotOld(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 40, OldEntryNo);
        CreateLp('RT149-LP-B', 'B1', LotOld(), 60, OldEntryNo);

        Assert.AreEqual(2, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'Both LP lines of the reclassed entry must follow the new entry.');

        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-A'), 'LP A must be linked to the new transfer entry.');
        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-B'), 'LP B must be linked to the new transfer entry.');
        Assert.AreEqual(NewExpiry(), LineExpiry('RT149-LP-A'), 'LP A must carry the new expiration date.');
        Assert.AreEqual(NewExpiry(), LineExpiry('RT149-LP-B'), 'LP B must carry the new expiration date.');
        NewEntry.Get(NewEntryNo);
        Assert.AreEqual('RT149-LP-A, RT149-LP-B', NewEntry."DOPSWHS LP Nos.", 'The new entry must list its LPs.');
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'A second run must not change anything.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReclassWithNewLotUpdatesLpLot()
    var
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
    begin
        Seed();
        SetupReclass(50, 0, 50, LotNew(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 50, OldEntryNo);

        Assert.AreEqual(1, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'The LP line must follow the new lot entry.');
        Assert.AreEqual(LotNew(), LineLot('RT149-LP-A'), 'The LP line must take the new lot number.');
        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-A'), 'The LP line must be linked to the new entry.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialReclassRelinksOnlyMovedQuantity()
    var
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
    begin
        Seed();
        // 100 kg'nin 50'si yeniden sınıflandırıldı; eski girişte 50 kaldı.
        SetupReclass(100, 50, 50, LotOld(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 30, OldEntryNo);
        CreateLp('RT149-LP-B', 'B1', LotOld(), 30, OldEntryNo);
        CreateLp('RT149-LP-C', 'B1', LotOld(), 40, OldEntryNo);

        Assert.AreEqual(1, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'Only whole lines that fit the moved 50 may follow.');
        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-A'), 'LP A (30) fits the moved quantity.');
        Assert.AreEqual(OldEntryNo, LineSource('RT149-LP-B'), 'LP B would over-link the new entry and must stay.');
        Assert.AreEqual(OldEntryNo, LineSource('RT149-LP-C'), 'LP C must stay on the old entry.');
        Assert.AreEqual(OldExpiry(), LineExpiry('RT149-LP-C'), 'An LP left on the old entry keeps its expiration date.');
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'A second run must not over-link the new entry.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LpInOtherBinIsUntouched()
    var
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
    begin
        Seed();
        SetupReclass(100, 0, 100, LotOld(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 40, OldEntryNo);
        CreateLp('RT149-LP-X', 'B2', LotOld(), 60, OldEntryNo);

        // Raf değişiyor ve günlükte LP yok: hangi palet taşındı bilinmez.
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B3', ''), 'A bin change without an explicit LP must not relink.');
        Assert.AreEqual(1, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'Only the LP in the from-bin may follow.');
        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-A'), 'LP A in the from-bin must follow.');
        Assert.AreEqual(OldEntryNo, LineSource('RT149-LP-X'), 'LP X in another bin must stay untouched.');
        Assert.AreEqual(OldExpiry(), LineExpiry('RT149-LP-X'), 'LP X must keep its expiration date.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BinChangeWithJournalLpRelinksOnlyThatLp()
    var
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
    begin
        Seed();
        SetupReclass(100, 0, 100, LotOld(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 40, OldEntryNo);
        CreateLp('RT149-LP-B', 'B1', LotOld(), 60, OldEntryNo);

        Assert.AreEqual(1, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B3', 'RT149-LP-B'), 'Only the journal LP may follow a bin change.');
        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-B'), 'The journal LP must follow.');
        Assert.AreEqual(OldEntryNo, LineSource('RT149-LP-A'), 'Another LP must stay.');
        Assert.AreEqual('B1', LpBin('RT149-LP-B'), 'The relink must not move the LP header.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PostingPathNeverFails()
    var
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
        OrphanEntryNo: Integer;
    begin
        Seed();
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(2147460999, 'B1', 'B1', ''), 'A missing entry must be ignored.');
        // Uygulama kaydı olmayan pozitif transfer.
        OrphanEntryNo := CreateEntry(50, "Item Ledger Entry Type"::Transfer, 10, 10, LotOld(), NewExpiry(), 'RT149-RC');
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(OrphanEntryNo, 'B1', 'B1', ''), 'A transfer entry without application must be ignored.');
        // Transferred-from girişi silinmiş.
        CreateAppl(50, OrphanEntryNo, OrphanEntryNo, 0, 2147460998, 10);
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(OrphanEntryNo, 'B1', 'B1', ''), 'A missing source entry must be ignored.');
        // Birim dönüşümü olmayan LP satırı atlanır, hata vermez.
        SetupReclass(100, 0, 100, LotOld(), OldEntryNo, NewEntryNo);
        CreateLpUom('RT149-LP-U', 'B1', LotOld(), 4, 'RT149-BOX', OldEntryNo);
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(NewEntryNo, 'B1', 'B1', ''), 'An LP line with an unknown unit must be skipped.');
        Assert.AreEqual(0, Relink.RelinkPostedTransferEntry(OldEntryNo, 'B1', 'B1', ''), 'A non-transfer entry must be ignored.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RelinkActionMovesLineFromExhaustedSource()
    var
        LP: Record "DOPSWHS LP Header";
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        OldEntryNo: Integer;
        NewEntryNo: Integer;
        FilterText: Text;
    begin
        Seed();
        SetupReclass(100, 0, 100, LotNew(), OldEntryNo, NewEntryNo);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 100, OldEntryNo);
        LP.Get('RT149-LP-A');

        FilterText := Relink.GetRelinkCandidateFilter(LP, GetLine('RT149-LP-A'));
        Assert.AreEqual(Format(NewEntryNo, 0, 9), FilterText, 'The successor reclass entry must be offered.');
        Relink.RelinkExhaustedStockLine(LP, 10000, NewEntryNo);

        Assert.AreEqual(NewEntryNo, LineSource('RT149-LP-A'), 'The line must be relinked to the successor entry.');
        Assert.AreEqual(LotNew(), LineLot('RT149-LP-A'), 'The line must take the successor lot.');
        Assert.AreEqual(NewExpiry(), LineExpiry('RT149-LP-A'), 'The line must take the successor expiration date.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RelinkActionRefusesLineBackedByRemainingStock()
    var
        LP: Record "DOPSWHS LP Header";
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        BackedEntryNo: Integer;
        OtherEntryNo: Integer;
    begin
        Seed();
        BackedEntryNo := CreateEntry(1, "Item Ledger Entry Type"::Purchase, 100, 100, LotOld(), OldExpiry(), 'RT149-P');
        OtherEntryNo := CreateEntry(2, "Item Ledger Entry Type"::Purchase, 100, 100, LotOld(), NewExpiry(), 'RT149-P2');
        CreateLp('RT149-LP-A', 'B1', LotOld(), 100, BackedEntryNo);
        LP.Get('RT149-LP-A');

        asserterror Relink.RelinkExhaustedStockLine(LP, 10000, OtherEntryNo);
        Assert.ExpectedError('kaynak değiştirilemez');
        Assert.AreEqual(BackedEntryNo, LineSource('RT149-LP-A'), 'An LP backed by remaining stock must keep its source.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepairFollowsReclassChainAndSkipsBackedLps()
    var
        Origin: Record "Item Ledger Entry";
        Relink: Codeunit "DOPSWHS LP Reclass Relink";
        Assert: Codeunit "Library Assert";
        SourceEntryNos: List of [Integer];
        PurchaseNo: Integer;
        Neg1No: Integer;
        T1No: Integer;
        Neg2No: Integer;
        T2No: Integer;
        BackedNo: Integer;
        PreviewText: Text;
    begin
        Seed();
        // P (100, kalan 0) -> T1 (kalan 0) -> T2 (kalan 100, yeni SKT).
        PurchaseNo := CreateEntry(1, "Item Ledger Entry Type"::Purchase, 100, 0, LotOld(), OldExpiry(), 'RT149-P');
        Neg1No := CreateEntry(2, "Item Ledger Entry Type"::Transfer, -100, 0, LotOld(), OldExpiry(), 'RT149-RC1');
        T1No := CreateEntry(3, "Item Ledger Entry Type"::Transfer, 100, 0, LotOld(), MidExpiry(), 'RT149-RC1');
        Neg2No := CreateEntry(4, "Item Ledger Entry Type"::Transfer, -100, 0, LotOld(), MidExpiry(), 'RT149-RC2');
        T2No := CreateEntry(5, "Item Ledger Entry Type"::Transfer, 100, 100, LotOld(), NewExpiry(), 'RT149-RC2');
        CreateAppl(1, Neg1No, PurchaseNo, Neg1No, 0, -100);
        CreateAppl(2, T1No, T1No, Neg1No, PurchaseNo, 100);
        CreateAppl(3, Neg2No, T1No, Neg2No, 0, -100);
        CreateAppl(4, T2No, T2No, Neg2No, T1No, 100);
        CreateLp('RT149-LP-A', 'B1', LotOld(), 40, PurchaseNo);
        CreateLp('RT149-LP-B', 'B1', LotOld(), 60, PurchaseNo);
        // Gerçek stokla desteklenen başka giriş.
        BackedNo := CreateEntry(6, "Item Ledger Entry Type"::Purchase, 20, 20, LotOld(), OldExpiry(), 'RT149-P3');
        CreateLp('RT149-LP-C', 'B1', LotOld(), 20, BackedNo);

        Relink.CollectRelinkSourceEntries(T2No, SourceEntryNos);
        Relink.CollectRelinkSourceEntries(BackedNo, SourceEntryNos);
        Assert.IsTrue(SourceEntryNos.Contains(PurchaseNo), 'Selecting the latest reclass entry must find the purchase entry holding the LPs.');

        Assert.AreEqual(2, Relink.PreviewReclassRelink(SourceEntryNos, PreviewText), 'Preview must count the two LP lines on the exhausted entry.');
        Assert.AreEqual(PurchaseNo, LineSource('RT149-LP-A'), 'Preview must not change any LP.');
        Assert.AreEqual(2, Relink.ApplyReclassRelink(SourceEntryNos), 'Repair must relink both lines.');

        Assert.AreEqual(T2No, LineSource('RT149-LP-A'), 'LP A must reach the open end of the chain.');
        Assert.AreEqual(T2No, LineSource('RT149-LP-B'), 'LP B must reach the open end of the chain.');
        Assert.AreEqual(NewExpiry(), LineExpiry('RT149-LP-A'), 'LP A must carry the latest expiration date.');
        Assert.AreEqual(BackedNo, LineSource('RT149-LP-C'), 'An LP backed by remaining stock must stay untouched.');
        Assert.AreEqual(OldExpiry(), LineExpiry('RT149-LP-C'), 'The backed LP keeps its expiration date.');
        Assert.AreEqual(0, Relink.ApplyReclassRelink(SourceEntryNos), 'A second repair must not change anything.');

        Origin.Get(T2No);
        Relink.FindOriginEntry(Origin);
        Assert.AreEqual(PurchaseNo, Origin."Entry No.", 'The label must read receipt data from the original purchase entry.');
    end;

    local procedure SetupReclass(OldQty: Decimal; OldRemainingAfter: Decimal; TransferQty: Decimal; NewLotNo: Code[50]; var OldEntryNo: Integer; var NewEntryNo: Integer)
    var
        NegEntryNo: Integer;
    begin
        OldEntryNo := CreateEntry(1, "Item Ledger Entry Type"::Purchase, OldQty, OldRemainingAfter, LotOld(), OldExpiry(), 'RT149-P');
        NegEntryNo := CreateEntry(2, "Item Ledger Entry Type"::Transfer, -TransferQty, 0, LotOld(), OldExpiry(), 'RT149-RC');
        NewEntryNo := CreateEntry(3, "Item Ledger Entry Type"::Transfer, TransferQty, TransferQty, NewLotNo, NewExpiry(), 'RT149-RC');
        CreateAppl(1, NegEntryNo, OldEntryNo, NegEntryNo, 0, -TransferQty);
        CreateAppl(2, NewEntryNo, NewEntryNo, NegEntryNo, OldEntryNo, TransferQty);
    end;

    local procedure Seed()
    var
        Item: Record Item;
    begin
        if Item.Get(ItemNo()) then
            exit;
        Item.Init();
        Item."No." := ItemNo();
        Item.Description := 'RT149 reclass relink fixture';
        Item."Base Unit of Measure" := 'KG';
        Item.Insert(false);
    end;

    local procedure CreateEntry(Offset: Integer; EntryType: Enum "Item Ledger Entry Type"; Qty: Decimal; RemainingQty: Decimal; LotNo: Code[50]; ExpirationDate: Date; DocumentNo: Code[20]): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460000 + Offset;
        Entry."Entry Type" := EntryType;
        Entry."Document No." := DocumentNo;
        Entry."Item No." := ItemNo();
        Entry."Location Code" := 'RT149';
        Entry."Lot No." := LotNo;
        Entry."Expiration Date" := ExpirationDate;
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := RemainingQty;
        Entry.Positive := Qty > 0;
        Entry.Open := RemainingQty <> 0;
        Entry.Insert(false);
        exit(Entry."Entry No.");
    end;

    local procedure CreateAppl(Offset: Integer; ItemLedgerEntryNo: Integer; InboundEntryNo: Integer; OutboundEntryNo: Integer; TransferredFromEntryNo: Integer; Qty: Decimal)
    var
        Appl: Record "Item Application Entry";
    begin
        Appl.Init();
        Appl."Entry No." := 2147460000 + Offset;
        Appl."Item Ledger Entry No." := ItemLedgerEntryNo;
        Appl."Inbound Item Entry No." := InboundEntryNo;
        Appl."Outbound Item Entry No." := OutboundEntryNo;
        Appl."Transferred-from Entry No." := TransferredFromEntryNo;
        Appl.Quantity := Qty;
        Appl.Insert(false);
    end;

    local procedure CreateLp(LpNo: Code[20]; BinCode: Code[20]; LotNo: Code[50]; Qty: Decimal; SourceEntryNo: Integer)
    begin
        CreateLpUom(LpNo, BinCode, LotNo, Qty, 'KG', SourceEntryNo);
    end;

    local procedure CreateLpUom(LpNo: Code[20]; BinCode: Code[20]; LotNo: Code[50]; Qty: Decimal; UnitOfMeasure: Code[10]; SourceEntryNo: Integer)
    var
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
    begin
        LP."No." := LpNo;
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'RT149';
        LP."Bin Code" := BinCode;
        LP.Insert(false);
        Line."LP No." := LpNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo();
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := UnitOfMeasure;
        Line.Quantity := Qty;
        Line."Expiration Date" := OldExpiry();
        Line."Source Document Type" := Line."Source Document Type"::WhseReceipt;
        Line."Source Document No." := 'RT149-WR';
        Line."Source Item Ledger Entry No." := SourceEntryNo;
        Line.Insert(false);
    end;

    local procedure GetLine(LpNo: Code[20]): Record "DOPSWHS LP Line"
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.Get(LpNo, 10000);
        exit(Line);
    end;

    local procedure LineSource(LpNo: Code[20]): Integer
    begin
        exit(GetLine(LpNo)."Source Item Ledger Entry No.");
    end;

    local procedure LineExpiry(LpNo: Code[20]): Date
    begin
        exit(GetLine(LpNo)."Expiration Date");
    end;

    local procedure LineLot(LpNo: Code[20]): Code[50]
    begin
        exit(GetLine(LpNo)."Lot No.");
    end;

    local procedure LpBin(LpNo: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LpNo);
        exit(LP."Bin Code");
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('RT149-ITEM');
    end;

    local procedure LotOld(): Code[50]
    begin
        exit('RT149-LOT');
    end;

    local procedure LotNew(): Code[50]
    begin
        exit('RT149-LOT-N');
    end;

    local procedure OldExpiry(): Date
    begin
        exit(DMY2Date(1, 1, 2027));
    end;

    local procedure MidExpiry(): Date
    begin
        exit(DMY2Date(1, 3, 2027));
    end;

    local procedure NewExpiry(): Date
    begin
        exit(DMY2Date(1, 6, 2027));
    end;
}
