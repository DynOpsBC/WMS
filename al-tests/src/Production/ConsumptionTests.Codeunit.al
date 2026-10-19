codeunit 72125 "DOPSWHS Prod Consumption Tests"
{
    Subtype = Test;

    [Test]
    procedure ReleasedProdOrderComponentScanCreatesConsumptionEntry()
    var
        Component: Record "Prod. Order Component";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        CreateComponent(Component, 'PROD-S7-CONS', 10000, 'ITEM-S7-COMP', 5);

        ProdMgmt.Consume(Component, 'ITEM-S7-COMP', 5, '', '', '', 'PROD');

        ItemLedgerEntry.SetRange("Order No.", 'PROD-S7-CONS');
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Consumption);
        Assert.IsFalse(ItemLedgerEntry.IsEmpty(), 'Consumption posting must create an item ledger consumption entry.');
        ItemLedgerEntry.FindFirst();
        Assert.AreEqual('', ItemLedgerEntry."DOPSWHS LP No.", 'Consumption without a scanned LP must not infer one from a pick.');
    end;

    [Test]
    procedure RegisteredPartialPickDebitsOnlyTakenQuantity()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RegisteredLine: Record "Registered Whse. Activity Line" temporary;
        Movement: Record "DOPSWHS LP Movement Ledger";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 1750);
        CreateRegisteredTake(RegisteredLine, LP, LPLine, 210.00782);
        LPMgt.DebitProductionPickLp(RegisteredLine, RegisteredLine."Qty. (Base)");
        // A repeated event/retry must not take the same registered pick twice.
        LPMgt.DebitProductionPickLp(RegisteredLine, RegisteredLine."Qty. (Base)");

        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(1539.99218, LPLine.Quantity, 'Only the physically picked quantity must leave the LP.');
        LP.Get(LP."No.");
        Assert.AreEqual('A.URETIM', LP."Bin Code", 'The remaining pallet must stay in its source bin.');
        Assert.AreEqual(LP.Status::Assigned, LP.Status, 'A production-order assignment must remain on the partial pallet.');
        Movement.SetRange("LP No.", LP."No.");
        Movement.SetRange(Action, Movement.Action::ItemRemoved);
        Movement.SetRange("Related Document", 'PP:REG-PROD-LP:10000');
        Assert.AreEqual(1, Movement.Count(), 'The pick must create exactly one LP debit.');
    end;

    [Test]
    procedure PostedConsumptionDebitsStagedLpOnce()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        JournalLine: Record "Item Journal Line" temporary;
        ItemLedgerEntry: Record "Item Ledger Entry" temporary;
        Movement: Record "DOPSWHS LP Movement Ledger";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 20);
        LP."Bin Code" := 'DO.01';
        LP.Modify(false);
        LPMgt.WriteToLedger(LP, Movement.Action::Assigned, 'DO.01', 'DO.01', 0, '', '',
            'PROD:PROD-LP-CONS/PICK:PICK-PROD-LP');
        JournalLine."DOPSWHS LP No." := LP."No.";
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Location Code" := LP."Location Code";
        JournalLine."Bin Code" := 'DO.01';
        ItemLedgerEntry."Entry No." := 456789;
        ItemLedgerEntry."Entry Type" := ItemLedgerEntry."Entry Type"::Consumption;
        ItemLedgerEntry."Item No." := LPLine."Item No.";
        ItemLedgerEntry.Quantity := -5;

        LPMgt.DebitPostedProductionConsumptionLp(JournalLine, ItemLedgerEntry);
        LPMgt.DebitPostedProductionConsumptionLp(JournalLine, ItemLedgerEntry);

        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(15, LPLine.Quantity, 'Posted consumption must reduce the staged LP once.');
        LP.Get(LP."No.");
        Assert.AreEqual(LP.Status::Assigned, LP.Status, 'The LP remainder stays assigned to production.');
        Movement.SetRange("LP No.", LP."No.");
        Movement.SetRange(Action, Movement.Action::ItemRemoved);
        Movement.SetRange("Related Document", 'PC:456789');
        Assert.AreEqual(1, Movement.Count(), 'One posted item entry must create one LP debit.');
    end;

    [Test]
    procedure PostedConsumptionDoesNotDebitSourceLpAfterPartialPick()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        JournalLine: Record "Item Journal Line" temporary;
        ItemLedgerEntry: Record "Item Ledger Entry" temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 20);
        JournalLine."DOPSWHS LP No." := LP."No.";
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Location Code" := LP."Location Code";
        JournalLine."Bin Code" := 'DO.01';
        ItemLedgerEntry."Entry No." := 456790;
        ItemLedgerEntry."Entry Type" := ItemLedgerEntry."Entry Type"::Consumption;
        ItemLedgerEntry."Item No." := LPLine."Item No.";
        ItemLedgerEntry.Quantity := -5;

        LPMgt.DebitPostedProductionConsumptionLp(JournalLine, ItemLedgerEntry);

        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(20, LPLine.Quantity, 'The source LP remainder was already reduced by the registered pick.');
    end;

    [Test]
    procedure PostedConsumptionRejectsLpWithoutRegisteredStage()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        JournalLine: Record "Item Journal Line" temporary;
        ItemLedgerEntry: Record "Item Ledger Entry" temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 20);
        LP."Bin Code" := 'DO.01';
        LP.Modify(false);
        JournalLine."DOPSWHS LP No." := LP."No.";
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Location Code" := LP."Location Code";
        JournalLine."Bin Code" := 'DO.01';
        ItemLedgerEntry."Entry No." := 456791;
        ItemLedgerEntry."Entry Type" := ItemLedgerEntry."Entry Type"::Consumption;
        ItemLedgerEntry."Item No." := LPLine."Item No.";
        ItemLedgerEntry.Quantity := -5;

        asserterror LPMgt.DebitPostedProductionConsumptionLp(JournalLine, ItemLedgerEntry);
        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(20, LPLine.Quantity, 'An unregistered LP move must not be silently consumed.');
    end;

    [Test]
    procedure ConsumptionWithoutLpIsNotBlockedByStagedLpStock()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        JournalLine: Record "Item Journal Line" temporary;
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        // BADE 28 Eyl 2026: BC consumption (journal/automatic flushing) without
        // an LP number is never blocked; the order's LP is debited afterwards.
        CreateProductionLp(LP, LPLine, 20);
        LP."Bin Code" := 'DO.01';
        LP.Modify(false);
        JournalLine."Entry Type" := JournalLine."Entry Type"::Consumption;
        JournalLine."Order Type" := JournalLine."Order Type"::Production;
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Item No." := LPLine."Item No.";
        JournalLine."Location Code" := LP."Location Code";
        JournalLine."Bin Code" := 'DO.01';
        JournalLine."Quantity (Base)" := 5;

        ProdMgmt.ValidateProductionConsumptionSource(JournalLine);
        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(20, LPLine.Quantity, 'Validation itself must not change the LP.');
    end;

    [Test]
    procedure SourceLpNumberDoesNotBlockConsumptionOrDebitStagedLp()
    var
        SourceLP: Record "DOPSWHS LP Header";
        SourceLine: Record "DOPSWHS LP Line";
        StagedLP: Record "DOPSWHS LP Header";
        StagedLine: Record "DOPSWHS LP Line";
        WarehouseEntry: Record "Warehouse Entry";
        JournalLine: Record "Item Journal Line" temporary;
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        CreateProductionLp(SourceLP, SourceLine, 20);
        StagedLP := SourceLP;
        StagedLP."No." := 'PROD-LP-STAGED';
        StagedLP."Bin Code" := 'DO.01';
        StagedLP.Insert(false);
        StagedLine := SourceLine;
        StagedLine."LP No." := StagedLP."No.";
        StagedLine.Insert(false);
        WarehouseEntry.Init();
        WarehouseEntry."Entry No." := 900001;
        WarehouseEntry."Location Code" := 'BLUE';
        WarehouseEntry."Bin Code" := 'DO.01';
        WarehouseEntry."Item No." := SourceLine."Item No.";
        WarehouseEntry."Qty. (Base)" := 20;
        WarehouseEntry.Insert(false);

        JournalLine."Entry Type" := JournalLine."Entry Type"::Consumption;
        JournalLine."Order Type" := JournalLine."Order Type"::Production;
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Item No." := SourceLine."Item No.";
        JournalLine."Location Code" := 'BLUE';
        JournalLine."Bin Code" := 'DO.01';
        JournalLine."DOPSWHS LP No." := SourceLP."No.";
        JournalLine."Quantity (Base)" := 5;

        // A source LP left in another bin only traces loose stock; the posting
        // is not blocked and the staged LP is not debited by this validation.
        ProdMgmt.ValidateProductionConsumptionSource(JournalLine);
        StagedLine.Get(StagedLP."No.", StagedLine."Line No.");
        Assert.AreEqual(20, StagedLine.Quantity, 'Validation must not debit another LP.');
    end;

    [Test]
    procedure ConsumptionJournalRejectsLpAssignedToAnotherOrder()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        JournalLine: Record "Item Journal Line" temporary;
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        CreateProductionLp(LP, LPLine, 20);
        LP."Bin Code" := 'DO.01';
        LP."Assigned Document No." := 'OTHER-ORDER';
        LP.Modify(false);
        JournalLine."Entry Type" := JournalLine."Entry Type"::Consumption;
        JournalLine."Order Type" := JournalLine."Order Type"::Production;
        JournalLine."Order No." := 'PROD-LP-CONS';
        JournalLine."Item No." := LPLine."Item No.";
        JournalLine."Location Code" := LP."Location Code";
        JournalLine."Bin Code" := LP."Bin Code";
        JournalLine."DOPSWHS LP No." := LP."No.";
        JournalLine."Quantity (Base)" := 5;

        asserterror ProdMgmt.ValidateProductionConsumptionSource(JournalLine);
        Assert.IsTrue(StrPos(GetLastErrorText(), 'atanmış değil') > 0,
            'A BC journal must reject an LP assigned to another production order before stock posting.');
    end;

    [Test]
    procedure RegisteredPickRejectsMoreThanLpContains()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RegisteredLine: Record "Registered Whse. Activity Line" temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 10);
        CreateRegisteredTake(RegisteredLine, LP, LPLine, 10.00002);
        asserterror LPMgt.DebitProductionPickLp(RegisteredLine, RegisteredLine."Qty. (Base)");
        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(10, LPLine.Quantity, 'A rejected pick must leave the LP untouched.');
    end;

    [Test]
    procedure RegisteredPartialPickReleasesCompletedPickAssignment()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RegisteredLine: Record "Registered Whse. Activity Line" temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 20);
        LP."Assigned Document Type" := LP."Assigned Document Type"::WhsePick;
        LP."Assigned Document No." := 'PICK-PROD-LP';
        LP.Modify(false);
        CreateRegisteredTake(RegisteredLine, LP, LPLine, 5);

        LPMgt.DebitProductionPickLp(RegisteredLine, RegisteredLine."Qty. (Base)");

        LP.Get(LP."No.");
        Assert.AreEqual(LP.Status::Built, LP.Status, 'The remaining LP must be available after its pick is registered.');
        Assert.AreEqual('', LP."Assigned Document No.", 'The registered pick must release its LP assignment.');
        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(15, LPLine.Quantity, 'The source LP must retain the unpicked balance.');
    end;

    [Test]
    procedure RegisteredFullPickMarksLpUsed()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RegisteredLine: Record "Registered Whse. Activity Line" temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        CreateProductionLp(LP, LPLine, 10);
        CreateRegisteredTake(RegisteredLine, LP, LPLine, 10);
        LPMgt.DebitProductionPickLp(RegisteredLine, RegisteredLine."Qty. (Base)");
        LP.Get(LP."No.");
        Assert.AreEqual(LP.Status::Used, LP.Status, 'An empty LP must be marked used.');
        Assert.AreEqual('', LP."Assigned Document No.", 'An empty LP must release its order.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'A fully picked LP must have no item lines.');
    end;

    [Test]
    procedure HistoricalPickWithMissingLpReferenceCanBeRepairedOnce()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        TempTake: Record "Registered Whse. Activity Line" temporary;
        RegisteredTake: Record "Registered Whse. Activity Line";
        RegisteredPlace: Record "Registered Whse. Activity Line";
        SourceEntry: Record "Warehouse Entry";
        TargetEntry: Record "Warehouse Entry";
        LastEntry: Record "Warehouse Entry";
        LPMgt: Codeunit "DOPSWHS LP Management";
        FirstEntryNo: Integer;
    begin
        CreateProductionLp(LP, LPLine, 20);
        CreateRegisteredTake(TempTake, LP, LPLine, 5);
        RegisteredTake := TempTake;
        RegisteredTake."LP No." := '';
        RegisteredTake."Source Line No." := 10000;
        RegisteredTake."Source Subline No." := 10000;
        RegisteredTake.Insert(false);
        RegisteredPlace := RegisteredTake;
        RegisteredPlace."Line No." := 20000;
        RegisteredPlace."Action Type" := RegisteredPlace."Action Type"::Place;
        RegisteredPlace."Bin Code" := 'DO.01';
        RegisteredPlace.Insert(false);

        if LastEntry.FindLast() then
            FirstEntryNo := LastEntry."Entry No." + 1
        else
            FirstEntryNo := 1;
        SourceEntry.Init();
        SourceEntry."Entry No." := FirstEntryNo;
        SourceEntry."Location Code" := LP."Location Code";
        SourceEntry."Bin Code" := LP."Bin Code";
        SourceEntry."Item No." := LPLine."Item No.";
        SourceEntry.Quantity := 15;
        SourceEntry."Qty. (Base)" := 15;
        SourceEntry.Insert(false);
        TargetEntry := SourceEntry;
        TargetEntry."Entry No." := FirstEntryNo + 1;
        TargetEntry."Bin Code" := 'DO.01';
        TargetEntry.Quantity := 5;
        TargetEntry."Qty. (Base)" := 5;
        TargetEntry.Insert(false);

        LPMgt.RepairHistoricalProductionPickLp(LP."No.", RegisteredTake."No.", RegisteredTake."Line No.", false);
        LPMgt.RepairHistoricalProductionPickLp(LP."No.", RegisteredTake."No.", RegisteredTake."Line No.", true);
        LPMgt.RepairHistoricalProductionPickLp(LP."No.", RegisteredTake."No.", RegisteredTake."Line No.", true);

        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(15, LPLine.Quantity, 'Historical repair must debit the selected LP once.');
        RegisteredTake.Get(RegisteredTake."Activity Type"::Pick, RegisteredTake."No.", RegisteredTake."Line No.");
        Assert.AreEqual('', RegisteredTake."LP No.", 'Historical registration must remain immutable.');
    end;

    [Test]
    procedure HistoricalSplitPickRepairsAllTakeLinesTogether()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        TempTake: Record "Registered Whse. Activity Line" temporary;
        FirstTake: Record "Registered Whse. Activity Line";
        SecondTake: Record "Registered Whse. Activity Line";
        FirstPlace: Record "Registered Whse. Activity Line";
        SecondPlace: Record "Registered Whse. Activity Line";
        SourceEntry: Record "Warehouse Entry";
        TargetEntry: Record "Warehouse Entry";
        LastEntry: Record "Warehouse Entry";
        Movement: Record "DOPSWHS LP Movement Ledger";
        LPMgt: Codeunit "DOPSWHS LP Management";
        FirstEntryNo: Integer;
        Preview: Text;
    begin
        CreateProductionLp(LP, LPLine, 20);
        CreateRegisteredTake(TempTake, LP, LPLine, 3);
        FirstTake := TempTake;
        FirstTake."LP No." := '';
        FirstTake."Source Line No." := 10000;
        FirstTake."Source Subline No." := 10000;
        FirstTake.Insert(false);
        SecondTake := FirstTake;
        SecondTake."Line No." := 30000;
        SecondTake."Qty. (Base)" := 2;
        SecondTake.Insert(false);
        FirstPlace := FirstTake;
        FirstPlace."Line No." := 20000;
        FirstPlace."Action Type" := FirstPlace."Action Type"::Place;
        FirstPlace."Bin Code" := 'DO.01';
        FirstPlace.Insert(false);
        SecondPlace := SecondTake;
        SecondPlace."Line No." := 40000;
        SecondPlace."Action Type" := SecondPlace."Action Type"::Place;
        SecondPlace."Bin Code" := 'DO.01';
        SecondPlace.Insert(false);

        if LastEntry.FindLast() then
            FirstEntryNo := LastEntry."Entry No." + 1
        else
            FirstEntryNo := 1;
        SourceEntry.Init();
        SourceEntry."Entry No." := FirstEntryNo;
        SourceEntry."Location Code" := LP."Location Code";
        SourceEntry."Bin Code" := LP."Bin Code";
        SourceEntry."Item No." := LPLine."Item No.";
        SourceEntry.Quantity := 15;
        SourceEntry."Qty. (Base)" := 15;
        SourceEntry.Insert(false);
        TargetEntry := SourceEntry;
        TargetEntry."Entry No." := FirstEntryNo + 1;
        TargetEntry."Bin Code" := 'DO.01';
        TargetEntry.Quantity := 5;
        TargetEntry."Qty. (Base)" := 5;
        TargetEntry.Insert(false);

        Preview := LPMgt.RepairHistoricalProductionPickLp(LP."No.", FirstTake."No.", FirstTake."Line No.", false);
        Assert.IsTrue(StrPos(Preview, '2 Al satırı') > 0, 'A split registered pick must preview as one group.');
        LPMgt.RepairHistoricalProductionPickLp(LP."No.", FirstTake."No.", FirstTake."Line No.", true);
        LPMgt.RepairHistoricalProductionPickLp(LP."No.", SecondTake."No.", SecondTake."Line No.", true);

        LPLine.Get(LP."No.", LPLine."Line No.");
        Assert.AreEqual(15, LPLine.Quantity, 'The entire split pick must debit the LP once.');
        Movement.SetRange("LP No.", LP."No.");
        Movement.SetRange(Action, Movement.Action::ItemRemoved);
        Movement.SetFilter("Related Document", 'PP:*');
        Assert.AreEqual(2, Movement.Count(), 'Both registered Take lines need an idempotency ledger entry.');
    end;

    local procedure CreateRegisteredTake(var RegisteredLine: Record "Registered Whse. Activity Line" temporary; LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line"; Qty: Decimal)
    begin
        RegisteredLine.Init();
        RegisteredLine."Activity Type" := RegisteredLine."Activity Type"::Pick;
        RegisteredLine."No." := 'REG-PROD-LP';
        RegisteredLine."Line No." := 10000;
        RegisteredLine."Whse. Activity No." := 'PICK-PROD-LP';
        RegisteredLine."Action Type" := RegisteredLine."Action Type"::Take;
        RegisteredLine."Source Type" := Database::"Prod. Order Component";
        RegisteredLine."Source Subtype" := 3;
        RegisteredLine."Source No." := 'PROD-LP-CONS';
        RegisteredLine."Location Code" := LP."Location Code";
        RegisteredLine."Bin Code" := LP."Bin Code";
        RegisteredLine."Item No." := LPLine."Item No.";
        RegisteredLine."LP No." := LP."No.";
        RegisteredLine."Qty. (Base)" := Qty;
        RegisteredLine.Insert(false);
    end;

    local procedure CreateProductionLp(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"; Qty: Decimal)
    var
        Item: Record Item;
    begin
        Item.Init();
        Item."No." := 'PROD-LP-CONS-ITEM';
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert(false);
        LP.Init();
        LP."No." := 'PROD-LP-CONS-LP';
        LP."Location Code" := 'BLUE';
        LP."Bin Code" := 'A.URETIM';
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := 'PROD-LP-CONS';
        LP.Insert(false);
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine."Line No." := 10000;
        LPLine."Item No." := Item."No.";
        LPLine."Unit of Measure" := Item."Base Unit of Measure";
        LPLine.Quantity := Qty;
        LPLine.Insert(false);
    end;

    local procedure CreateComponent(var Component: Record "Prod. Order Component"; ProdOrderNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; Qty: Decimal)
    begin
        Component.Init();
        Component.Status := Component.Status::Released;
        Component."Prod. Order No." := ProdOrderNo;
        Component."Prod. Order Line No." := 10000;
        Component."Line No." := LineNo;
        Component."Item No." := ItemNo;
        Component.Description := 'Sprint 7 component';
        Component."Unit of Measure Code" := 'PCS';
        Component.Quantity := Qty;
        Component."Remaining Quantity" := Qty;
        Component."Location Code" := 'BLUE';
        Component."Bin Code" := 'PROD';
        Component.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
