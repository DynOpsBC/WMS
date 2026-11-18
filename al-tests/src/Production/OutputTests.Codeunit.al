codeunit 72127 "DOPSWHS Prod Output Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OperationSelectionPostsOutputScrapAndRuntime()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        CreateRoutingLine(RoutingLine, 'PROD-S7-OUT', 10000);
        CreateProdOrderLine(RoutingLine, 'ITEM-S7-FG');

        ProdMgmt.ReportOutput(RoutingLine, 3, 1, 25, '', 'OUTPUT');

        ItemLedgerEntry.SetRange("Order No.", 'PROD-S7-OUT');
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.IsFalse(ItemLedgerEntry.IsEmpty(), 'Output posting must create an item ledger output entry.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialPreparationUsesBcLotSeriesOnceAndDoesNotPostStock()
    var
        Line: Record "Prod. Order Line";
        Request: Record "DOPSWHS Prod Output Request";
        Entry: Record "Item Ledger Entry";
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        RequestId: Guid;
        FirstResult: Text;
    begin
        SeedPartialLine(Line);
        RequestId := CreateGuid();
        FirstResult := Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Assert.AreEqual(FirstResult, Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId), 'Retry must reuse the same BC lot.');
        Request.Get(RequestId);
        Assert.AreEqual('PARTLOT0001', Request."Lot No.", 'Use the item card lot series.');
        Assert.IsFalse(Request.Completed, 'Lot allocation must not post output.');
        Entry.SetRange("Order No.", Line."Prod. Order No.");
        Assert.IsTrue(Entry.IsEmpty(), 'Preparation must not create any inventory entry.');
        asserterror Mgmt.PrepareOutput(Line, 3000, WorkDate(), '', 0D, RequestId);
        // AssertError rolls back the test transaction, including its prepared fixture.
        Assert.ExpectedError('Quantity');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StaleRemainingQuantityBlocksPostingBeforeStockChanges()
    var
        Line: Record "Prod. Order Line";
        Request: Record "DOPSWHS Prod Output Request";
        Entry: Record "Item Ledger Entry";
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        RequestId: Guid;
    begin
        SeedPartialLine(Line);
        RequestId := CreateGuid();
        Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Line."Remaining Quantity" := 1000;
        Line.Modify(false);
        asserterror Mgmt.PostOutput(RequestId);
        Assert.ExpectedError('aşıyor');
        // The rejected transaction leaves no committed output.

        Entry.SetRange("Order No.", Line."Prod. Order No.");
        Assert.IsTrue(Entry.IsEmpty(), 'Overproduction must not create inventory.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PostedReplayAndCancelKeepOriginalResultWithoutPostingAgain()
    var
        Line: Record "Prod. Order Line";
        Request: Record "DOPSWHS Prod Output Request";
        Entry: Record "Item Ledger Entry";
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        RequestId: Guid;
        BeforeCount: Integer;
        Expected: Text;
    begin
        SeedPartialLine(Line);
        RequestId := CreateGuid();
        Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Request.Get(RequestId);
        // Seed a committed request result to exercise the uncertain-response replay branch.
        Request.Completed := true;
        Request."Item Ledger Entry No." := 42;
        Request."Quantity (Base)" := 2000;
        Request.Modify(false);
        Expected := Mgmt.ResultJson(Request);
        BeforeCount := Entry.Count();
        Assert.AreEqual(Expected, Mgmt.PostOutput(RequestId), 'Replayed posting returns the original receipt.');
        Assert.AreEqual(Expected, Mgmt.CancelOutput(RequestId), 'A completed posting cannot be cancelled as a draft.');
        Assert.AreEqual(BeforeCount, Entry.Count(), 'Replay must not create another ledger entry.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelledAndForeignRequestsCannotPost()
    var
        Line: Record "Prod. Order Line";
        Request: Record "DOPSWHS Prod Output Request";
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        RequestId: Guid;
    begin
        SeedPartialLine(Line);
        RequestId := CreateGuid();
        Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Mgmt.CancelOutput(RequestId);
        Request.Get(RequestId);
        Assert.IsTrue(Request.Cancelled, 'Cancellation persists.');
        asserterror Mgmt.PostOutput(RequestId);
        SeedPartialLine(Line);
        RequestId := CreateGuid();
        Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Request.Get(RequestId);
        Request."Created By" := CreateGuid();
        Request.Modify(false);
        asserterror Mgmt.CancelOutput(RequestId);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialQuantityBoundaryAndTypedPickSources()
    var
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Mgmt.ValidateQuantity(2000, 5000);
        Mgmt.ValidateQuantity(3000, 3000);
        asserterror Mgmt.ValidateQuantity(3001, 3000);
        asserterror Mgmt.ValidateQuantity(0, 5000);
        asserterror Mgmt.ValidateQuantity(-1, 5000);
        Assert.AreEqual('Satış siparişi: 001', PickMgmt.SourceDocumentCaption(Database::"Sales Line", 1, '001'), 'Sales order source.');
        Assert.AreEqual('Serbest bırakılmış üretim emri: 001', PickMgmt.SourceDocumentCaption(Database::"Prod. Order Component", 3, '001'), 'Released production source.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RealPartialPostUpdatesLedgerRemainingAndReplaysOnce()
    var
        Line: Record "Prod. Order Line";
        Request: Record "DOPSWHS Prod Output Request";
        Entry: Record "Item Ledger Entry";
        Item: Record Item;
        SourceItem: Record Item;
        Unit: Record "Item Unit of Measure";
        Header: Record "Production Order";
        InventorySetup: Record "Inventory Setup";
        ManufacturingSetup: Record "Manufacturing Setup";
        PostingSetup: Record "Inventory Posting Setup";
        BlankPostingSetup: Record "Inventory Posting Setup";
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
        RequestId: Guid;
        SecondId: Guid;
        Receipt: Text;
    begin
        SeedPartialLine(Line);
        SourceItem.SetRange(Type, SourceItem.Type::Inventory);
        SourceItem.SetFilter("Gen. Prod. Posting Group", '<>%1', '');
        SourceItem.SetFilter("Inventory Posting Group", '<>%1', '');
        SourceItem.FindFirst();
        Item.Get(Line."Item No.");
        Item."Gen. Prod. Posting Group" := SourceItem."Gen. Prod. Posting Group";
        Item."Inventory Posting Group" := SourceItem."Inventory Posting Group";
        Item."Costing Method" := Item."Costing Method"::FIFO;
        Item.Modify(false);
        if not BlankPostingSetup.Get('', Item."Inventory Posting Group") then begin
            PostingSetup.SetRange("Invt. Posting Group Code", Item."Inventory Posting Group");
            PostingSetup.FindFirst();
            BlankPostingSetup := PostingSetup;
            BlankPostingSetup."Location Code" := '';
            BlankPostingSetup.Insert(false);
        end;
        if BlankPostingSetup."WIP Account" = '' then begin
            BlankPostingSetup."WIP Account" := BlankPostingSetup."Inventory Account";
            BlankPostingSetup.Modify(false);
        end;
        ManufacturingSetup.Get();
        ManufacturingSetup."Doc. No. Is Prod. Order No." := true;
        ManufacturingSetup.Modify(false);
        InventorySetup.Get();
        InventorySetup."Automatic Cost Posting" := false;
        InventorySetup."Automatic Cost Adjustment" := InventorySetup."Automatic Cost Adjustment"::Never;
        InventorySetup."Location Mandatory" := false;
        InventorySetup.Modify(false);
        Unit."Item No." := Item."No.";
        Unit.Code := 'PCS';
        Unit."Qty. per Unit of Measure" := 1;
        Unit.Insert(false);
        Header.Status := Header.Status::Released;
        Header."No." := Line."Prod. Order No.";
        Header."Source Type" := Header."Source Type"::Item;
        Header."Source No." := Item."No.";
        Header.Quantity := 5000;
        Header."Due Date" := WorkDate();
        Header.Insert(false);
        Line."Quantity (Base)" := 5000;
        Line."Remaining Qty. (Base)" := 5000;
        Line."Due Date" := WorkDate();
        Line.Modify(false);
        RequestId := CreateGuid();
        Mgmt.PrepareOutput(Line, 2000, WorkDate(), '', 0D, RequestId);
        Receipt := Mgmt.PostOutput(RequestId);
        Request.Get(RequestId);
        Assert.IsTrue(Request.Completed, 'Actual posting must complete the durable request.');
        Assert.AreEqual(2000, Request."Quantity (Base)", 'Actual posted base quantity.');
        Entry.Get(Request."Item Ledger Entry No.");
        Assert.AreEqual(2000, Entry.Quantity, 'Output ledger quantity.');
        Assert.AreEqual(Request."Document No.", Entry."Document No.", 'Keep the unique request document even when manufacturing defaults to the order number.');
        Assert.AreEqual(Request."Lot No.", Entry."Lot No.", 'Allocated lot must reach the ledger.');
        Line.Get(Line.Status, Line."Prod. Order No.", Line."Line No.");
        Assert.AreEqual(2000, Line."Finished Quantity", 'Partial output updates finished quantity.');
        Assert.AreEqual(3000, Line."Remaining Quantity", 'Partial output leaves 3000 available.');
        Assert.AreEqual(Receipt, Mgmt.PostOutput(RequestId), 'Retry returns the original receipt.');
        SecondId := CreateGuid();
        Mgmt.PrepareOutput(Line, 3000, WorkDate(), '', 0D, SecondId);
        Mgmt.PostOutput(SecondId);
        Line.Get(Line.Status, Line."Prod. Order No.", Line."Line No.");
        Assert.AreEqual(5000, Line."Finished Quantity", 'Second partial report completes the planned quantity.');
        Assert.AreEqual(0, Line."Remaining Quantity", 'No remaining output after the second report.');
        Entry.SetRange("Order No.", Line."Prod. Order No.");
        Entry.SetRange("Entry Type", Entry."Entry Type"::Output);
        Assert.AreEqual(2, Entry.Count(), 'Exactly two outputs despite the retry.');
    end;

    local procedure SeedPartialLine(var Line: Record "Prod. Order Line")
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        Series: Record "No. Series";
        SeriesLine: Record "No. Series Line";
        Helper: Codeunit "DOPSWHS Test Helper";
        Setup: Record "DOPSWHS Setup";
    begin
        Helper.ResetSetup();
        Setup := Helper.EnsureSetup();
        Setup."License Service URL" := '';
        Setup.Modify(false);
        Tracking.Init();
        Tracking.Code := 'PART-LOT';
        Tracking."Lot Specific Tracking" := true;
        Tracking.Insert(false);
        Series.Init();
        Series.Code := 'PART-LOT';
        Series."Default Nos." := true;
        Series.Insert(false);
        SeriesLine.Init();
        SeriesLine."Series Code" := Series.Code;
        SeriesLine."Line No." := 10000;
        SeriesLine."Starting No." := 'PARTLOT0001';
        SeriesLine."Ending No." := 'PARTLOT9999';
        SeriesLine."Increment-by No." := 1;
        SeriesLine.Insert(true);
        Item.Init();
        Item."No." := 'PARTIAL-TEST';
        Item."Base Unit of Measure" := 'PCS';
        Item."Item Tracking Code" := Tracking.Code;
        Item."Lot Nos." := Series.Code;
        Item.Insert(false);
        Line.Init();
        Line.Status := Line.Status::Released;
        Line."Prod. Order No." := 'PARTIAL-TEST';
        Line."Line No." := 10000;
        Line."Item No." := Item."No.";
        Line."Unit of Measure Code" := 'PCS';
        Line."Qty. per Unit of Measure" := 1;
        Line.Quantity := 5000;
        Line."Remaining Quantity" := 5000;
        Line.Insert(false);
    end;

    local procedure CreateRoutingLine(var RoutingLine: Record "Prod. Order Routing Line"; ProdOrderNo: Code[20]; RoutingRefNo: Integer)
    begin
        RoutingLine.Init();
        RoutingLine.Status := RoutingLine.Status::Released;
        RoutingLine."Prod. Order No." := ProdOrderNo;
        RoutingLine."Routing Reference No." := RoutingRefNo;
        RoutingLine."Routing No." := 'R-S7';
        RoutingLine."Operation No." := '10';
        RoutingLine."No." := 'WC-S7';
        RoutingLine.Description := 'Assembly operation';
        RoutingLine.Insert(true);
    end;

    local procedure CreateProdOrderLine(var RoutingLine: Record "Prod. Order Routing Line"; ItemNo: Code[20])
    var
        ProdOrderLine: Record "Prod. Order Line";
    begin
        ProdOrderLine.Init();
        ProdOrderLine.Status := RoutingLine.Status;
        ProdOrderLine."Prod. Order No." := RoutingLine."Prod. Order No.";
        ProdOrderLine."Line No." := RoutingLine."Routing Reference No.";
        ProdOrderLine."Item No." := ItemNo;
        ProdOrderLine."Unit of Measure Code" := 'PCS';
        ProdOrderLine."Location Code" := 'BLUE';
        ProdOrderLine."Bin Code" := 'OUTPUT';
        ProdOrderLine.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
