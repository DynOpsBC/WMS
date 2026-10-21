codeunit 72147 "DOPSWHS Undo Receipt LP Tests"
{
    // BADE (21 Eki 2026): RE001191 / 109433 geri alındı (15286, -45000, lot
    // A102511) ama 90 LP dolu kaldı. BC geri alma kaydını UndoQuantityPosting ile
    // atar; düşüm kayıt üzerinden (Applies-to Entry olmadan da) bulunmalı ve
    // önceki geri almalar Onarım ile boşaltılabilmeli.
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Item Ledger Entry" = rimd,
        tabledata "Posted Whse. Receipt Header" = rimd,
        tabledata "Posted Whse. Receipt Line" = rimd,
        tabledata "Whse. Item Entry Relation" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoDebitFindsOriginalByDocumentAndLotWithoutAppliesTo()
    var
        UndoEntry: Record "Item Ledger Entry";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        OtherLotEntryNo: Integer;
        OriginalEntryNo: Integer;
    begin
        Seed();
        // Aynı irsaliyede başka lot gerçek stokla duruyor.
        OtherLotEntryNo := CreateEntry(1, 'RT147-R1', 10000, LotA(), 10, 10, false, 0);
        OriginalEntryNo := CreateEntry(2, 'RT147-R1', 10000, LotB(), 10, 0, false, 0);
        CreateLp('RT147-LP-A', LotA(), 10, OtherLotEntryNo);
        CreateLp('RT147-LP-B', LotB(), 10, OriginalEntryNo);
        // Lot izlemeli geri alma: Applies-to Entry boş, belge satır no düzeltme satırı.
        UndoEntry.Get(CreateEntry(9, 'RT147-R1', 20000, LotB(), -10, 0, true, 0));

        Assert.AreEqual(1, LPMgt.DebitUndoneReceiptEntryLp(UndoEntry, 0, false, 'RCV'), 'The undo must debit the LP of the original receipt entry found by document and lot.');

        Assert.AreEqual(0, LpQty('RT147-LP-B'), 'The LP of the undone receipt must be emptied.');
        Assert.AreEqual(Format(Enum::"DOPSWHS LP Status"::Used), Format(LpStatus('RT147-LP-B')), 'An emptied LP must not stay active in the receipt bin.');
        Assert.AreEqual(10, LpQty('RT147-LP-A'), 'The LP of another lot with real stock must stay unchanged.');
        Assert.AreEqual(0, LPMgt.DebitUndoneReceiptEntryLp(UndoEntry, 0, false, 'RCV'), 'The same undo entry must not debit twice.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoDebitIgnoresNonCorrectionNegativeReceipt()
    var
        UndoEntry: Record "Item Ledger Entry";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        OriginalEntryNo: Integer;
    begin
        Seed();
        OriginalEntryNo := CreateEntry(1, 'RT147-R1', 10000, LotB(), 10, 0, false, 0);
        CreateLp('RT147-LP-B', LotB(), 10, OriginalEntryNo);
        UndoEntry.Get(CreateEntry(9, 'RT147-R1', 20000, LotB(), -10, 0, false, 0));

        Assert.AreEqual(0, LPMgt.DebitUndoneReceiptEntryLp(UndoEntry, 0, false, ''), 'Only a correction (undo) entry may debit receipt LPs.');
        Assert.AreEqual(10, LpQty('RT147-LP-B'), 'A non-correction negative receipt must leave the LP unchanged.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepairEmptiesOnlyLpsLinkedToTheUndoneEntry()
    var
        OriginalEntry: Record "Item Ledger Entry";
        UndoEntry: Record "Item Ledger Entry";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        EarlierSameLotEntryNo: Integer;
        OtherLotEntryNo: Integer;
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        // Önceki dalga aynı lotla gerçek stokta; başka lot da gerçek stokta.
        EarlierSameLotEntryNo := CreateEntry(1, 'RT147-R0', 10000, LotB(), 10, 10, false, 0);
        OtherLotEntryNo := CreateEntry(2, 'RT147-R1', 10000, LotA(), 10, 10, false, 0);
        OriginalEntryNo := CreateEntry(3, 'RT147-R2', 10000, LotB(), 10, 0, false, 0);
        CreateLp('RT147-LP-C', LotB(), 10, EarlierSameLotEntryNo);
        CreateLp('RT147-LP-A', LotA(), 10, OtherLotEntryNo);
        CreateLp('RT147-LP-B1', LotB(), 6, OriginalEntryNo);
        CreateLp('RT147-LP-B2', LotB(), 4, OriginalEntryNo);
        // Eski yanlış damga: satırın bütün LP'leri.
        OriginalEntry.Get(OriginalEntryNo);
        OriginalEntry."DOPSWHS LP Nos." := 'RT147-LP-C, RT147-LP-B1, RT147-LP-B2';
        OriginalEntry.Modify(false);
        UndoEntryNo := CreateEntry(9, 'RT147-R2', 20000, LotB(), -10, 0, true, OriginalEntryNo);

        Assert.AreEqual(2, LPMgt.PreviewUndoneReceiptLpRepair(UndoEntryNo), 'Preview must count both LP lines of the undone entry.');
        Assert.AreEqual(6, LpQty('RT147-LP-B1'), 'Preview must not change any LP.');
        Assert.AreEqual(2, LPMgt.RepairUndoneReceiptLps(UndoEntryNo), 'Repair must empty both LP lines of the undone entry.');

        Assert.AreEqual(0, LpQty('RT147-LP-B1'), 'Linked LP B1 must be emptied.');
        Assert.AreEqual(0, LpQty('RT147-LP-B2'), 'Linked LP B2 must be emptied.');
        Assert.AreEqual(10, LpQty('RT147-LP-C'), 'An LP of another entry with the same lot and real stock must stay unchanged.');
        Assert.AreEqual(10, LpQty('RT147-LP-A'), 'An LP of another lot with real stock must stay unchanged.');
        OriginalEntry.Get(OriginalEntryNo);
        Assert.AreEqual('RT147-LP-B1, RT147-LP-B2', OriginalEntry."DOPSWHS LP Nos.", 'The undone entry must list only its own LPs.');
        UndoEntry.Get(UndoEntryNo);
        Assert.AreEqual('RT147-LP-B1, RT147-LP-B2', UndoEntry."DOPSWHS LP Nos.", 'The undo entry must list the LPs it emptied.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepairFromEitherRowIsIdempotent()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        UndoEntryNos: List of [Integer];
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        OriginalEntryNo := CreateEntry(1, 'RT147-R2', 10000, LotB(), 10, 0, false, 0);
        CreateLp('RT147-LP-B', LotB(), 10, OriginalEntryNo);
        // Lot izlemeli geri alma kaydında Applies-to Entry boş kalabilir.
        UndoEntryNo := CreateEntry(9, 'RT147-R2', 20000, LotB(), -10, 0, true, 0);

        // Kullanıcı +10 (geri alınan) ya da -10 (geri alma) satırını seçebilir.
        LPMgt.CollectUndoneReceiptEntries(OriginalEntryNo, UndoEntryNos);
        LPMgt.CollectUndoneReceiptEntries(UndoEntryNo, UndoEntryNos);
        Assert.AreEqual(1, UndoEntryNos.Count(), 'Both rows must resolve to the same single undo entry.');
        Assert.IsTrue(UndoEntryNos.Contains(UndoEntryNo), 'The receipt row must resolve to its undo entry.');

        Assert.AreEqual(1, LPMgt.RepairUndoneReceiptLps(UndoEntryNo), 'The first repair must empty the LP line.');
        Assert.AreEqual(0, LpQty('RT147-LP-B'), 'The LP must be empty after repair.');
        Assert.AreEqual(0, LPMgt.PreviewUndoneReceiptLpRepair(UndoEntryNo), 'Nothing must remain to repair.');
        Assert.AreEqual(0, LPMgt.RepairUndoneReceiptLps(UndoEntryNo), 'A second repair must not change anything.');
        Assert.AreEqual(1, CountUndoLedger(UndoEntryNo), 'Exactly one LP removal must be recorded for the undo.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepairNeverEmptiesLpBackedByRemainingStock()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        // Kalan miktar LP miktarına eşit: LP gerçek stokla destekleniyor.
        OriginalEntryNo := CreateEntry(1, 'RT147-R2', 10000, LotB(), 10, 10, false, 0);
        CreateLp('RT147-LP-B', LotB(), 10, OriginalEntryNo);
        UndoEntryNo := CreateEntry(9, 'RT147-R2', 20000, LotB(), -10, 0, true, OriginalEntryNo);

        Assert.AreEqual(0, LPMgt.RepairUndoneReceiptLps(UndoEntryNo), 'Repair must not empty an LP still backed by remaining stock.');
        Assert.AreEqual(10, LpQty('RT147-LP-B'), 'The LP must keep its quantity.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PostedMultiLpReceiptStampsOnlyLpsLinkedToEachEntry()
    var
        EntryL1: Record "Item Ledger Entry";
        EntryL2: Record "Item Ledger Entry";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        Assert: Codeunit "Library Assert";
        EarlierEntryNo: Integer;
    begin
        Seed();
        // Önceki dalga (aynı mal kabul satırı) başka girişe bağlı.
        EarlierEntryNo := CreateEntry(1, 'RT147-R0', 10000, 'RT147-LOT-0', 3, 3, false, 0);
        EntryL1.Get(CreateEntry(2, 'RT147-R1', 10000, LotA(), 10, 10, false, 0));
        EntryL2.Get(CreateEntry(3, 'RT147-R1', 10000, LotB(), 5, 5, false, 0));
        CreatePostedReceipt('RT147-PWR', 'RT147-WR', EntryL1."Entry No.", EntryL2."Entry No.");
        CreateReceiptLp('RT147-LP-0', 'RT147-LOT-0', 3, EarlierEntryNo);
        CreateReceiptLp('RT147-LP-1', LotA(), 6, 0);
        CreateReceiptLp('RT147-LP-2', LotA(), 4, 0);
        CreateReceiptLp('RT147-LP-3', LotB(), 5, 0);

        LpPropagation.StampPostedReceiptLedgerEntries('RT147-PWR', '');

        EntryL1.Get(EntryL1."Entry No.");
        Assert.AreEqual('RT147-LP-1, RT147-LP-2', EntryL1."DOPSWHS LP Nos.", 'Each entry must list only the LPs linked to it.');
        Assert.AreEqual('', EntryL1."DOPSWHS LP No.", 'An entry carried by several LPs keeps the list only.');
        EntryL2.Get(EntryL2."Entry No.");
        Assert.AreEqual('RT147-LP-3', EntryL2."DOPSWHS LP No.", 'An entry carried by one LP must show that LP.');
        Assert.AreEqual('', EntryL2."DOPSWHS LP Nos.", 'An entry carried by one LP must not get the receipt line list.');
    end;

    local procedure Seed()
    var
        Item: Record Item;
    begin
        if Item.Get(ItemNo()) then
            exit;
        Item.Init();
        Item."No." := ItemNo();
        Item.Description := 'RT147 undo receipt fixture';
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert(false);
    end;

    local procedure CreateEntry(Offset: Integer; DocumentNo: Code[20]; DocumentLineNo: Integer; LotNo: Code[50]; Qty: Decimal; RemainingQty: Decimal; IsCorrection: Boolean; AppliesToEntryNo: Integer): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147470000 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::Purchase;
        Entry."Document Type" := Entry."Document Type"::"Purchase Receipt";
        Entry."Document No." := DocumentNo;
        Entry."Document Line No." := DocumentLineNo;
        Entry."Item No." := ItemNo();
        Entry."Location Code" := 'RT147';
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

    local procedure CreateLp(LpNo: Code[20]; LotNo: Code[50]; Qty: Decimal; SourceEntryNo: Integer)
    var
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
    begin
        LP."No." := LpNo;
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::WhsePutaway;
        LP."Assigned Document No." := 'RT147-PU';
        LP."Location Code" := 'RT147';
        LP."Bin Code" := 'RCV';
        LP.Insert(false);
        Line."LP No." := LpNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo();
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := 'PCS';
        Line.Quantity := Qty;
        Line."Source Item Ledger Entry No." := SourceEntryNo;
        Line.Insert(false);
    end;

    local procedure CreateReceiptLp(LpNo: Code[20]; LotNo: Code[50]; Qty: Decimal; SourceEntryNo: Integer)
    var
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
    begin
        LP."No." := LpNo;
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'RT147';
        LP."Bin Code" := 'RCV';
        LP.Insert(false);
        Line."LP No." := LpNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo();
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := 'PCS';
        Line.Quantity := Qty;
        Line."Source Document Type" := Line."Source Document Type"::WhseReceipt;
        Line."Source Document No." := 'RT147-WR';
        Line."Source Document Line No." := 10000;
        Line."Source Item Ledger Entry No." := SourceEntryNo;
        Line.Insert(false);
    end;

    local procedure CreatePostedReceipt(PostedNo: Code[20]; WhseReceiptNo: Code[20]; FirstEntryNo: Integer; SecondEntryNo: Integer)
    var
        PostedHeader: Record "Posted Whse. Receipt Header";
        PostedLine: Record "Posted Whse. Receipt Line";
    begin
        PostedHeader.Init();
        PostedHeader."No." := PostedNo;
        PostedHeader."Whse. Receipt No." := WhseReceiptNo;
        PostedHeader."Location Code" := 'RT147';
        PostedHeader.Insert(false);
        PostedLine.Init();
        PostedLine."No." := PostedNo;
        PostedLine."Line No." := 10000;
        PostedLine."Whse. Receipt No." := WhseReceiptNo;
        PostedLine."Whse Receipt Line No." := 10000;
        PostedLine."Item No." := ItemNo();
        PostedLine."Location Code" := 'RT147';
        PostedLine.Insert(false);
        CreateEntryRelation(FirstEntryNo, PostedNo);
        CreateEntryRelation(SecondEntryNo, PostedNo);
    end;

    local procedure CreateEntryRelation(EntryNo: Integer; PostedNo: Code[20])
    var
        Relation: Record "Whse. Item Entry Relation";
    begin
        Relation.Init();
        Relation."Item Entry No." := EntryNo;
        Relation."Source Type" := Database::"Posted Whse. Receipt Line";
        Relation."Source Subtype" := 0;
        Relation."Source ID" := PostedNo;
        Relation."Source Ref. No." := 10000;
        Relation.Insert(false);
    end;

    local procedure LpQty(LpNo: Code[20]): Decimal
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.SetRange("LP No.", LpNo);
        Line.CalcSums(Quantity);
        exit(Line.Quantity);
    end;

    local procedure LpStatus(LpNo: Code[20]): Enum "DOPSWHS LP Status"
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LpNo);
        exit(LP.Status);
    end;

    local procedure CountUndoLedger(UndoEntryNo: Integer): Integer
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger.SetRange(Action, Ledger.Action::ItemRemoved);
        Ledger.SetFilter("Related Document", 'UNDO-RCPT:%1:*', Format(UndoEntryNo));
        exit(Ledger.Count());
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('RT147-ITEM');
    end;

    local procedure LotA(): Code[50]
    begin
        exit('RT147-LOT-A');
    end;

    local procedure LotB(): Code[50]
    begin
        exit('RT147-LOT-B');
    end;
}
