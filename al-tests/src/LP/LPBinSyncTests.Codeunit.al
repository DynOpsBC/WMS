codeunit 72149 "DOPSWHS LP Bin Sync Tests"
{
    // BADE (22 Eki 2026, 1.14.1.150): BC'den yapılan eksi düzeltme, sayım,
    // iade/transfer sevkiyatı, eksi çıktı LP'yi düşmüyordu (hayalet LP);
    // ambar yeniden sınıflandırma, hareket ve rafa kaldırma LP'yi taşımıyordu
    // (LP eski gözde). DOPSWHS LP Bin Sync: gözden çıkan stok LP toplamını göz
    // stokunun altına indirdiyse fazlası düşülür; tamamı aynı göze giden LP
    // taşınır. Terminalde hazırlanmış LP'si olan mal kabul BC'den kaydedilemez.
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Warehouse Entry" = rimd,
        tabledata "Warehouse Receipt Header" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NegativeAdjustmentDebitsExcessFefo()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateLp('RT150-LP-B', 'B1', 50, EarlierExpiry());
        CreateEntry(1, 'B1', 100, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -30, NegativeAdjmt(), '', TempEntry, true);

        Assert.AreEqual(1, Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', ''), 'Exactly one LP must be debited.');
        Assert.AreEqual(20, LpQty('RT150-LP-B'), 'The LP expiring first (FEFO) must lose the 30 that left the bin.');
        Assert.AreEqual(50, LpQty('RT150-LP-A'), 'The later-expiring LP must stay unchanged.');
        Assert.AreEqual(0, Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', ''), 'A second run must not debit again (LP total equals bin stock).');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NamedLpIsDebitedFirst()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateLp('RT150-LP-B', 'B1', 50, EarlierExpiry());
        CreateEntry(1, 'B1', 100, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -30, NegativeAdjmt(), 'RT150-LP-A', TempEntry, true);

        Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', '');
        Assert.AreEqual(20, LpQty('RT150-LP-A'), 'The LP named on the journal line must be debited first.');
        Assert.AreEqual(50, LpQty('RT150-LP-B'), 'Another LP must stay unchanged.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LooseStockLeavingTheBinKeepsLps()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateLp('RT150-LP-B', 'B1', 50, EarlierExpiry());
        // 30 LP'siz stok vardı; çıkan 30 LP'leri etkilemez.
        CreateEntry(1, 'B1', 130, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -30, NegativeAdjmt(), '', TempEntry, true);

        Assert.AreEqual(0, Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', ''), 'Loose stock covers the reduction; no LP may change.');
        Assert.AreEqual(50, LpQty('RT150-LP-A'), 'LP A must stay full.');
        Assert.AreEqual(50, LpQty('RT150-LP-B'), 'LP B must stay full.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure EmptiedLpBecomesUsed()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 30, LaterExpiry());
        CreateEntry(1, 'B1', 30, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -30, NegativeAdjmt(), '', TempEntry, true);

        Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', '');
        Assert.AreEqual(0, LpQty('RT150-LP-A'), 'The LP must be emptied.');
        Assert.AreEqual(Format(Enum::"DOPSWHS LP Status"::Used), Format(LpStatus('RT150-LP-A')), 'An emptied LP must become Used.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MovementMovesWholeLpHeader()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
        MovedLps: List of [Code[20]];
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateLp('RT150-LP-B', 'B1', 50, EarlierExpiry());
        CreateEntry(1, 'B1', 100, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -50, MovementType(), '', TempEntry, true);
        CreateEntry(3, 'B2', 50, MovementType(), '', TempEntry, true);

        Assert.AreEqual(1, Sync.ProcessBuffer(TempEntry, Sync.ActivityReference('RT150-RMOV'), ''), 'One LP must be moved.');
        Assert.AreEqual('B2', LpBin('RT150-LP-B'), 'The whole LP (FEFO) must follow the stock to the Place bin.');
        Assert.AreEqual(50, LpQty('RT150-LP-B'), 'A moved LP keeps its content.');
        Assert.AreEqual('B1', LpBin('RT150-LP-A'), 'The other LP must stay in the Take bin.');
        Assert.AreEqual(50, LpQty('RT150-LP-A'), 'The other LP must keep its content.');
        Assert.IsTrue(Sync.WasActivitySynced('RT150-RMOV'), 'The registered activity must be marked as synced for the sales reconciliation.');
        Sync.GetActivityMovedLps('RT150-RMOV', 'B1', MovedLps);
        Assert.IsTrue(MovedLps.Contains('RT150-LP-B'), 'The moved LP must be listed for the activity and its Take bin.');
        Assert.AreEqual(0, Sync.ProcessBuffer(TempEntry, Sync.ActivityReference('RT150-RMOV'), ''), 'A second run must not move or debit anything.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialMovementDebitsSourceLp()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateEntry(1, 'B1', 50, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(2, 'B1', -20, MovementType(), '', TempEntry, true);
        CreateEntry(3, 'B2', 20, MovementType(), '', TempEntry, true);

        Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', '');
        Assert.AreEqual('B1', LpBin('RT150-LP-A'), 'A partially moved LP stays in its bin.');
        Assert.AreEqual(30, LpQty('RT150-LP-A'), 'The source LP must not keep the stock that left the bin.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure AdjustmentToAdjustmentBinIsNotAMove()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT150-LP-A', 'B1', 50, LaterExpiry());
        CreateEntry(1, 'B1', 50, PositiveAdjmt(), '', TempEntry, false);
        // Ambar madde günlüğü: göz -> düzeltme gözü, ikisi de Negatif Düzeltme.
        CreateEntry(2, 'B1', -50, NegativeAdjmt(), '', TempEntry, true);
        CreateEntry(3, 'ADJ', 50, NegativeAdjmt(), '', TempEntry, true);

        Sync.ProcessBuffer(TempEntry, 'LPSYNC#RT150', '');
        Assert.AreEqual('B1', LpBin('RT150-LP-A'), 'An LP is never moved into the adjustment bin.');
        Assert.AreEqual(Format(Enum::"DOPSWHS LP Status"::Used), Format(LpStatus('RT150-LP-A')), 'The adjusted-out LP must be emptied.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReceiptWithDraftLpsIsBlockedOutsideTerminal()
    var
        Header: Record "Warehouse Receipt Header";
        LP: Record "DOPSWHS LP Header";
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Header.Init();
        Header."No." := 'RT150-WR';
        Header.Insert(false);
        LP."No." := 'RT150-LP-D';
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'RT150';
        LP."Pending Receipt No." := 'RT150-WR';
        LP."Planned Quantity" := 50;
        LP.Insert(false);

        asserterror Sync.CheckReceiptPostingAllowed('RT150-WR');
        Assert.ExpectedError('terminalde hazırlanmış');

        Sync.EnterTerminalPosting();
        Sync.CheckReceiptPostingAllowed('RT150-WR');
        Sync.ExitTerminalPosting();

        Header.Get('RT150-WR');
        Header."DOPSWHS Posting In Progress" := true;
        Header.Modify(false);
        Sync.CheckReceiptPostingAllowed('RT150-WR');
        Assert.IsFalse(Sync.IsTerminalPosting(), 'The terminal flag must be cleared after the terminal posting.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OrphanDraftLpsAreCleanedOnlyWhenEmptyAndReceiptGone()
    var
        Header: Record "Warehouse Receipt Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        Header.Init();
        Header."No." := 'RT150-WR';
        Header.Insert(false);
        CreateDraftLp('RT150-LP-O', 'RT150-GONE');
        CreateDraftLp('RT150-LP-K', 'RT150-WR');
        CreateDraftLp('RT150-LP-F', 'RT150-GONE');
        Line."LP No." := 'RT150-LP-F';
        Line."Line No." := 10000;
        Line."Item No." := ItemNo();
        Line.Quantity := 5;
        Line.Insert(false);

        Assert.IsTrue(ReceiptMgmt.CleanupOrphanDraftLPs(false) >= 1, 'The empty draft of a missing receipt must be counted.');
        Assert.AreEqual(Format(LP.Status::Built), Format(LpStatus('RT150-LP-O')), 'Counting must not change anything.');
        ReceiptMgmt.CleanupOrphanDraftLPs(true);

        LP.Get('RT150-LP-O');
        Assert.AreEqual(Format(LP.Status::Unbuilt), Format(LP.Status), 'The orphan empty draft must be unbuilt.');
        Assert.AreEqual('', LP."Pending Receipt No.", 'The orphan draft must no longer point to the missing receipt.');
        LP.Get('RT150-LP-K');
        Assert.AreEqual('RT150-WR', LP."Pending Receipt No.", 'A draft of an existing receipt must stay untouched.');
        LP.Get('RT150-LP-F');
        Assert.AreEqual('RT150-GONE', LP."Pending Receipt No.", 'A draft with content must stay untouched.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TerminalShipmentNonSalesDebitsShipBinLp()
    var
        Entry: Record "Warehouse Entry";
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        // BADE 23 Eki: terminalden kaydedilen satın alma iadesi sevkinde LP dolu kalıyordu.
        Seed();
        CreateLp('RT151-LP-S', 'S1', 50, EarlierExpiry());
        CreateEntry(11, 'S1', 50, MovementType(), '', TempEntry, false);
        CreateEntry(12, 'S1', -50, NegativeAdjmt(), '', TempEntry, false);
        Entry.Get(2147470000 + 12);
        Entry."Whse. Document Type" := Entry."Whse. Document Type"::Shipment;
        Entry."Whse. Document No." := 'PWS-RT151';
        Entry.Modify(false);

        Assert.AreEqual(1, Sync.SyncPostedWhseShipment('PWS-RT151'), 'The LP left in the shipping bin must be debited.');
        Assert.AreEqual(0, LpQty('RT151-LP-S'), 'The returned quantity must leave the LP.');
        Assert.AreEqual(0, Sync.SyncPostedWhseShipment('PWS-RT151'), 'A second run must not debit again.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepairLpExcessPreviewsThenDebits()
    var
        TempEntry: Record "Warehouse Entry" temporary;
        Sync: Codeunit "DOPSWHS LP Bin Sync";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLp('RT151-LP-R', 'B1', 50, EarlierExpiry());
        CreateEntry(21, 'B1', 50, PositiveAdjmt(), '', TempEntry, false);
        CreateEntry(22, 'B1', -20, NegativeAdjmt(), '', TempEntry, false);

        Assert.AreEqual(20, Sync.RepairLpExcess('RT151-LP-R', false), 'Preview must report the 20 that is no longer in the bin.');
        Assert.AreEqual(50, LpQty('RT151-LP-R'), 'Preview must not change the LP.');
        Sync.RepairLpExcess('RT151-LP-R', true);
        Assert.AreEqual(30, LpQty('RT151-LP-R'), 'Repair must align the LP with bin stock.');
        Assert.AreEqual(0, Sync.RepairLpExcess('RT151-LP-R', false), 'Nothing left to repair.');
    end;

    local procedure Seed()
    var
        Item: Record Item;
        Location: Record Location;
    begin
        if not Item.Get(ItemNo()) then begin
            Item.Init();
            Item."No." := ItemNo();
            Item.Description := 'RT150 LP bin sync fixture';
            Item."Base Unit of Measure" := 'KG';
            Item.Insert(false);
        end;
        if not Location.Get('RT150') then begin
            Location.Init();
            Location.Code := 'RT150';
            Location."Bin Mandatory" := true;
            Location."Adjustment Bin Code" := 'ADJ';
            Location.Insert(false);
        end;
    end;

    local procedure CreateLp(LpNo: Code[20]; BinCode: Code[20]; Qty: Decimal; ExpirationDate: Date)
    var
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
    begin
        LP."No." := LpNo;
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'RT150';
        LP."Bin Code" := BinCode;
        LP.Insert(false);
        Line."LP No." := LpNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo();
        Line."Unit of Measure" := 'KG';
        Line.Quantity := Qty;
        Line."Expiration Date" := ExpirationDate;
        Line.Insert(false);
    end;

    local procedure CreateDraftLp(LpNo: Code[20]; ReceiptNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP."No." := LpNo;
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'RT150';
        LP."Bin Code" := 'R1';
        LP."Pending Receipt No." := ReceiptNo;
        LP."Planned Quantity" := 50;
        LP.Insert(false);
    end;

    local procedure CreateEntry(Offset: Integer; BinCode: Code[20]; Qty: Decimal; EntryType: Integer; LpNo: Code[20]; var TempEntry: Record "Warehouse Entry" temporary; AddToBuffer: Boolean)
    var
        Entry: Record "Warehouse Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147470000 + Offset;
        Entry."Location Code" := 'RT150';
        Entry."Bin Code" := BinCode;
        Entry."Item No." := ItemNo();
        Entry."Unit of Measure Code" := 'KG';
        Entry."Qty. per Unit of Measure" := 1;
        Entry.Quantity := Qty;
        Entry."Qty. (Base)" := Qty;
        Entry."Entry Type" := EntryType;
        Entry."DOPSWHS LP No." := LpNo;
        Entry.Insert(false);
        if AddToBuffer then begin
            TempEntry := Entry;
            TempEntry.Insert();
        end;
    end;

    local procedure NegativeAdjmt(): Integer
    var
        Entry: Record "Warehouse Entry";
    begin
        exit(Entry."Entry Type"::"Negative Adjmt.");
    end;

    local procedure PositiveAdjmt(): Integer
    var
        Entry: Record "Warehouse Entry";
    begin
        exit(Entry."Entry Type"::"Positive Adjmt.");
    end;

    local procedure MovementType(): Integer
    var
        Entry: Record "Warehouse Entry";
    begin
        exit(Entry."Entry Type"::Movement);
    end;

    local procedure LpQty(LpNo: Code[20]) Total: Decimal
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.SetRange("LP No.", LpNo);
        if Line.FindSet() then
            repeat
                Total += Line.Quantity;
            until Line.Next() = 0;
    end;

    local procedure LpStatus(LpNo: Code[20]): Enum "DOPSWHS LP Status"
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LpNo);
        exit(LP.Status);
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
        exit('RT150-ITEM');
    end;

    local procedure EarlierExpiry(): Date
    begin
        exit(DMY2Date(1, 1, 2027));
    end;

    local procedure LaterExpiry(): Date
    begin
        exit(DMY2Date(1, 6, 2027));
    end;
}
