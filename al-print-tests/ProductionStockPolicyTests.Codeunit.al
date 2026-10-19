codeunit 72183 "DOPSWHS Stock Policy Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Item Ledger Entry" = rimd;

    [Test]
    procedure OtherItemsUseReceiptDateEvenWhenExpiryDiffers()
    var
        Candidate: Record "DOPSWHS Pick Stock Candidate";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
    begin
        MakeItem('AB.TEST65');
        MakeEntry(-65001, 'AB.TEST65', 'A101296', DMY2Date(13, 4, 2026), WorkDate() + 200, 113583);
        MakeEntry(-65002, 'AB.TEST65', 'A101812', DMY2Date(8, 7, 2026), WorkDate() + 10, 102965);
        Policy.BuildCandidates('AB.TEST65', '', 'TEST65', Candidate);
        Candidate.FindFirst();
        Check(Candidate."Lot No." = 'A101296', 'AB FIFO must use receipt date, not expiry or bin.');
    end;

    [Test]
    procedure HmYmUseExpiryBeforeReceiptDate()
    var
        Candidate: Record "DOPSWHS Pick Stock Candidate";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
        ItemNo: Code[20];
        Index: Integer;
    begin
        for Index := 1 to 2 do begin
            if Index = 1 then ItemNo := 'HM.TEST65' else ItemNo := 'YM.TEST65';
            MakeItem(ItemNo);
            MakeEntry(-65010 - Index * 3, ItemNo, 'OLD-RECEIPT', WorkDate() - 100, WorkDate() + 100, 50);
            MakeEntry(-65011 - Index * 3, ItemNo, 'FIRST-EXPIRY', WorkDate() - 10, WorkDate() + 10, 50);
            MakeEntry(-65012 - Index * 3, ItemNo, 'NO-EXPIRY', WorkDate() - 200, 0D, 50);
            Policy.BuildCandidates(ItemNo, '', 'TEST65', Candidate);
            Candidate.FindFirst();
            Check(Candidate."Lot No." = 'FIRST-EXPIRY', 'HM/YM must prioritize earliest expiry.');
            Candidate.FindLast();
            Check(Candidate."Lot No." = 'NO-EXPIRY', 'Undated stock must not precede dated HM/YM stock.');
        end;
    end;

    [Test]
    procedure BlockedExpiredAndEmptyStockAreExcluded()
    var
        Candidate: Record "DOPSWHS Pick Stock Candidate";
        Lot: Record "Lot No. Information";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
    begin
        MakeItem('HM.BLOCK65');
        MakeEntry(-65030, 'HM.BLOCK65', 'EXPIRED', WorkDate() - 100, WorkDate() - 1, 50);
        MakeEntry(-65031, 'HM.BLOCK65', 'BLOCKED', WorkDate() - 90, WorkDate() + 1, 50);
        MakeEntry(-65032, 'HM.BLOCK65', 'EMPTY', WorkDate() - 80, WorkDate() + 2, 0);
        MakeEntry(-65033, 'HM.BLOCK65', 'VALID', WorkDate() - 70, WorkDate() + 3, 50);
        Lot.Init(); Lot."Item No." := 'HM.BLOCK65'; Lot."Lot No." := 'BLOCKED'; Lot.Blocked := true; Lot.Insert(false);
        Policy.BuildCandidates('HM.BLOCK65', '', 'TEST65', Candidate);
        Check(Candidate.Count() = 1, 'Unavailable lots leaked into candidates.');
        Candidate.FindFirst();
        Check(Candidate."Lot No." = 'VALID', 'Wrong usable lot.');
    end;

    [Test]
    procedure SandboxAB00175ProducesOldLotTracking()
    var
        Component: Record "Prod. Order Component";
        Params: Record "Create Pick Parameters";
        Tracking: Record "Whse. Item Tracking Line" temporary;
        Pick: Codeunit "Create Pick";
        Probe: Codeunit "DOPSWHS Stock Pick Probe";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
        Qty: Decimal;
        QtyBase: Decimal;
    begin
        Component.SetRange(Status, Component.Status::Released);
        Component.SetRange("Prod. Order No.", 'RLO.B100852');
        Component.SetRange("Item No.", 'AB.00175');
        Component.FindFirst();
        Policy.SetPreparedLp(false);
        Params."Whse. Document" := Params."Whse. Document"::Production;
        Params."Whse. Document Type" := Params."Whse. Document Type"::Pick;
        Pick.SetParameters(Params);
        Pick.SetCustomWhseSourceLine(Component, 1, Database::"Prod. Order Component", Component.Status.AsInteger(), Component."Prod. Order No.", Component."Prod. Order Line No.", Component."Line No.");
        Pick.SetTempWhseItemTrkgLine(Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        QtyBase := 1050;
        Qty := QtyBase / Component."Qty. per Unit of Measure";
        Pick.CreateTempLine(Component."Location Code", Component."Item No.", Component."Variant Code", Component."Unit of Measure Code", '', Component."Bin Code", Component."Qty. per Unit of Measure", Qty, QtyBase);
        Check(QtyBase = 0, StrSubstNo('1050 requested, %1 remains unallocated.', QtyBase));
        Pick.ReturnTempItemTrkgLines(Tracking);
        Tracking.FindFirst();
        Check(Tracking."Lot No." = 'A101296', StrSubstNo('Expected A101296, actual %1.', Tracking."Lot No."));
        BindSubscription(Probe);
        Probe.Verify(Pick, 'A101296', 1050);
        UnbindSubscription(Probe);
    end;

    [Test]
    procedure SandboxDemandSpillsFromOldToNewLot()
    var
        Component: Record "Prod. Order Component";
        TestOrder: Record "Production Order";
        TestOrderLine: Record "Prod. Order Line";
        Params: Record "Create Pick Parameters";
        Tracking: Record "Whse. Item Tracking Line" temporary;
        Pick: Codeunit "Create Pick";
        Probe: Codeunit "DOPSWHS Stock Pick Probe";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
        Qty: Decimal;
        QtyBase: Decimal;
    begin
        Component.SetRange(Status, Component.Status::Released);
        Component.SetRange("Prod. Order No.", 'RLO.B100852');
        Component.SetRange("Item No.", 'AB.00175');
        Component.FindFirst();
        CleanupSplitOrder();
        TestOrder.Get(Component.Status, Component."Prod. Order No.");
        TestOrder."No." := 'FIFO-TEST65';
        TestOrder.Insert(false);
        TestOrderLine.Get(Component.Status, Component."Prod. Order No.", Component."Prod. Order Line No.");
        TestOrderLine."Prod. Order No." := 'FIFO-TEST65';
        TestOrderLine.Insert(false);
        Component."Prod. Order No." := 'FIFO-TEST65';
        Component."Expected Quantity" := 120000 / Component."Qty. per Unit of Measure";
        Component."Expected Qty. (Base)" := 120000;
        Component."Remaining Quantity" := Component."Expected Quantity";
        Component."Remaining Qty. (Base)" := 120000;
        Component."Qty. Picked" := 0;
        Component."Qty. Picked (Base)" := 0;
        Component.Insert(false);
        Policy.SetPreparedLp(false);
        Params."Whse. Document" := Params."Whse. Document"::Production;
        Params."Whse. Document Type" := Params."Whse. Document Type"::Pick;
        Pick.SetParameters(Params);
        Pick.SetCustomWhseSourceLine(Component, 1, Database::"Prod. Order Component", Component.Status.AsInteger(), Component."Prod. Order No.", Component."Prod. Order Line No.", Component."Line No.");
        Pick.SetTempWhseItemTrkgLine(Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        QtyBase := 120000;
        Qty := QtyBase / Component."Qty. per Unit of Measure";
        Pick.CreateTempLine(Component."Location Code", Component."Item No.", Component."Variant Code", Component."Unit of Measure Code", '', Component."Bin Code", Component."Qty. per Unit of Measure", Qty, QtyBase);
        Check(QtyBase = 0, StrSubstNo('120000 requested, %1 remains unallocated.', QtyBase));
        Pick.ReturnTempItemTrkgLines(Tracking);
        Tracking.FindFirst();
        Check(Tracking."Lot No." = 'A101296', StrSubstNo('Expected A101296, actual %1.', Tracking."Lot No."));
        BindSubscription(Probe);
        Probe.Verify(Pick, '', 120000);
        Tracking.FindLast();
        Check(Tracking."Lot No." = 'A101812', StrSubstNo('Expected spill to A101812. Last lot: %1, tracking count: %2.', Tracking."Lot No.", Tracking.Count()));
        UnbindSubscription(Probe);
        CleanupSplitOrder();
    end;

    [Test]
    procedure SandboxExplicitNewLotIsPreserved()
    var
        Component: Record "Prod. Order Component";
        Params: Record "Create Pick Parameters";
        Tracking: Record "Whse. Item Tracking Line" temporary;
        Pick: Codeunit "Create Pick";
        Probe: Codeunit "DOPSWHS Stock Pick Probe";
        Policy: Codeunit "DOPSWHS Prod Stock Policy";
        ExplicitTracking: Record "Whse. Item Tracking Line" temporary;
        Qty: Decimal;
        QtyBase: Decimal;
    begin
        Component.SetRange(Status, Component.Status::Released);
        Component.SetRange("Prod. Order No.", 'RLO.B100852');
        Component.SetRange("Item No.", 'AB.00175');
        Component.FindFirst();
        Policy.SetPreparedLp(false);
        Params."Whse. Document" := Params."Whse. Document"::Production;
        Params."Whse. Document Type" := Params."Whse. Document Type"::Pick;
        Pick.SetParameters(Params);
        Pick.SetCustomWhseSourceLine(Component, 1, Database::"Prod. Order Component", Component.Status.AsInteger(), Component."Prod. Order No.", Component."Prod. Order Line No.", Component."Line No.");
        Pick.SetTempWhseItemTrkgLine(Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        ExplicitTracking.Init();
        ExplicitTracking."Entry No." := 1;
        ExplicitTracking."Source Type" := Database::"Prod. Order Component";
        ExplicitTracking."Source ID" := Component."Prod. Order No.";
        ExplicitTracking."Source Prod. Order Line" := Component."Prod. Order Line No.";
        ExplicitTracking."Source Ref. No." := Component."Line No.";
        ExplicitTracking."Location Code" := Component."Location Code";
        ExplicitTracking."Item No." := Component."Item No.";
        ExplicitTracking."Lot No." := 'A101812';
        ExplicitTracking."Quantity (Base)" := 1050;
        ExplicitTracking."Qty. to Handle (Base)" := 1050;
        ExplicitTracking."Qty. to Handle" := 1050 / Component."Qty. per Unit of Measure";
        ExplicitTracking.Insert();
        Pick.SetTempWhseItemTrkgLineFromBuffer(ExplicitTracking, Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        QtyBase := 1050;
        Qty := QtyBase / Component."Qty. per Unit of Measure";
        Pick.CreateTempLine(Component."Location Code", Component."Item No.", Component."Variant Code", Component."Unit of Measure Code", '', Component."Bin Code", Component."Qty. per Unit of Measure", Qty, QtyBase);
        Check(QtyBase = 0, StrSubstNo('1050 requested, %1 remains unallocated.', QtyBase));
        Pick.ReturnTempItemTrkgLines(Tracking);
        Tracking.FindFirst();
        Check(Tracking."Lot No." = 'A101812', StrSubstNo('Explicit A101812 must be preserved, actual %1.', Tracking."Lot No."));
        BindSubscription(Probe);
        Probe.Verify(Pick, 'A101812', 1050);
        UnbindSubscription(Probe);
    end;

    [Test]
    procedure CleanupSyntheticStock()
    begin
        CleanupItem('AB.TEST65');
        CleanupItem('HM.TEST65');
        CleanupItem('YM.TEST65');
        CleanupItem('HM.BLOCK65');
        CleanupSplitOrder();
    end;

    local procedure CleanupSplitOrder()
    var
        Component: Record "Prod. Order Component";
        OrderLine: Record "Prod. Order Line";
        Order: Record "Production Order";
    begin
        Component.SetRange("Prod. Order No.", 'FIFO-TEST65');
        Component.DeleteAll(false);
        OrderLine.SetRange("Prod. Order No.", 'FIFO-TEST65');
        OrderLine.DeleteAll(false);
        Order.SetRange("No.", 'FIFO-TEST65');
        Order.DeleteAll(false);
    end;

    local procedure CleanupItem(No: Code[20])
    var
        Item: Record Item;
        Entry: Record "Item Ledger Entry";
        Lot: Record "Lot No. Information";
    begin
        Entry.SetRange("Item No.", No);
        Entry.SetRange("Entry No.", -65099, -65000);
        Entry.DeleteAll(false);
        Lot.SetRange("Item No.", No);
        Lot.DeleteAll(false);
        if Item.Get(No) then Item.Delete(false);
    end;

    local procedure MakeItem(No: Code[20])
    var Item: Record Item;
    begin
        CleanupItem(No);
        Item.Init(); Item."No." := No; Item.Insert(false);
    end;

    local procedure MakeEntry(No: Integer; ItemNo: Code[20]; Lot: Code[50]; Posted: Date; Expiry: Date; Remaining: Decimal)
    var Entry: Record "Item Ledger Entry";
    begin
        Entry.Init(); Entry."Entry No." := No; Entry."Item No." := ItemNo;
        Entry."Location Code" := 'TEST65'; Entry."Posting Date" := Posted;
        Entry."Lot No." := Lot; Entry."Expiration Date" := Expiry;
        Entry.Positive := true; Entry.Open := Remaining > 0;
        Entry.Quantity := Remaining; Entry."Remaining Quantity" := Remaining;
        Entry.Insert(false);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then Error('%1', Message);
    end;
}
