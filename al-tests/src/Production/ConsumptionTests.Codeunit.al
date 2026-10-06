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
