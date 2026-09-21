codeunit 72185 "DOPSWHS Production Pick Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure LocalOperatorClaimsProductionPick()
    var
        Pick: Record "Warehouse Activity Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        Check(Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR') = Pick."No.", 'Existing production pick was not reused.');
        Pick.Get(Pick.Type::Pick, Pick."No.");
        Check(Pick."Assigned User ID" = 'OPERATOR', 'Pick was not assigned to the WMS operator.');
        Check(Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR') = Pick."No.", 'Repeated request was not idempotent.');
    end;

    [Test]
    procedure AnotherOperatorsPickIsNotTaken()
    var
        Pick: Record "Warehouse Activity Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        Pick."Assigned User ID" := 'OTHER';
        Pick.Modify(false);
        asserterror Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR');
        Pick.Get(Pick.Type::Pick, Pick."No.");
        Check(Pick."Assigned User ID" = 'OTHER', 'Existing owner was overwritten.');
    end;

    [Test]
    procedure SameNumberSalesPickIsIgnored()
    var
        Pick: Record "Warehouse Activity Header";
        SalesPick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        SalesPick := Pick;
        SalesPick."No." := 'A-SALES-LP-TEST';
        SalesPick."Assigned User ID" := 'SALES-OP';
        SalesPick.Insert(false);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."No." := SalesPick."No.";
        Line."Source Type" := Database::"Sales Line";
        Line.Insert(false);
        Check(Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR') = Pick."No.", 'Sales pick was returned for a production order.');
        SalesPick.Get(SalesPick.Type::Pick, SalesPick."No.");
        Check(SalesPick."Assigned User ID" = 'SALES-OP', 'Sales assignment changed.');
    end;

    [Test]
    procedure MissingReleasedOrderCannotReuseStalePick()
    var
        Pick: Record "Warehouse Activity Header";
        ProductionOrder: Record "Production Order";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        ProductionOrder.Get(ProductionOrder.Status::Released, 'PROD-LP-TEST');
        ProductionOrder.Delete(false);
        asserterror Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'Serbest bırakılmış') > 0, 'Released order was not checked.');
    end;

    [Test]
    procedure MixedOrderPickCannotBeReused()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Line No." := 30000;
        Line."Source No." := 'ANOTHER-PROD';
        Line.Insert(false);
        asserterror Management.CreateProductionPickFor('PROD-LP-TEST', 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'başka kaynak belgeler') > 0, 'Mixed source pick was reused.');
    end;

    [Test]
    procedure ReadyLpCanBeSmallerThanOutstandingPick()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Check(Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR') = Pick."No.", 'Ready LP was not accepted for part of the outstanding demand.');
        LP.Get(LP."No.");
        Check(LP.Status = LP.Status::Assigned, 'Ready LP was not reserved while awaiting registration.');
        Check(LP."Assigned Document Type" = LP."Assigned Document Type"::WhsePick, 'Ready LP was reserved to the wrong document type.');
        Check(LP."Assigned Document No." = Pick."No.", 'Ready LP was not reserved to this pick.');
        Check(LP."Bin Code" = 'STOCK', 'Creating a pick moved the LP before registration.');
        Check(Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR') = Pick."No.", 'Repeating the same LP selection was not idempotent.');
        LP.Get(LP."No.");
        Check(LP."Assigned Document No." = Pick."No.", 'Repeating the request changed the LP reservation.');
    end;

    [Test]
    procedure AnotherProductionPickCannotReserveTheSameReadyLp()
    var
        Pick: Record "Warehouse Activity Header";
        OtherPick: Record "Warehouse Activity Header";
        Order: Record "Production Order";
        Component: Record "Prod. Order Component";
        Line: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');

        Order.Get(Order.Status::Released, 'PROD-LP-TEST');
        Order."No." := 'PROD-LP-OTHER';
        Order.Insert(false);
        Component.Get(Component.Status::Released, 'PROD-LP-TEST', 10000, 10000);
        Component."Prod. Order No." := Order."No.";
        Component.Insert(false);
        OtherPick := Pick;
        OtherPick."No." := 'P-PROD-LP-OTHER';
        OtherPick."Assigned User ID" := 'OTHER-OP';
        OtherPick.Insert(false);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."No." := OtherPick."No.";
        Line."Source No." := Order."No.";
        Line.Insert(false);

        asserterror Management.CreateProductionPickFromLpFor(Order."No.", LP."No.", 'OTHER-OP');
        Check(StrPos(GetLastErrorText(), 'başka bir belgeye ayrılmış') > 0, 'Second production pick accepted an already reserved LP.');
        LP.Get(LP."No.");
        Check(LP."Assigned Document No." = Pick."No.", 'Second pick stole the ready LP reservation.');
    end;

    [Test]
    procedure ExistingProductionOrderReservationIsPreserved()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := 'PROD-LP-TEST';
        LP.Modify(false);
        Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        LP.Get(LP."No.");
        Check(LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption, 'Existing production assignment type was overwritten.');
        Check(LP."Assigned Document No." = 'PROD-LP-TEST', 'Existing production assignment was overwritten.');
    end;

    [Test]
    procedure OpenLpCannotRaceWarehouseBuilding()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        LP.Status := LP.Status::Open;
        LP.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'henüz hazır değil') > 0, 'Open LP should be completed before production picking.');
    end;

    [Test]
    procedure DifferentLocationRequiresRealStockTransfer()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        LP."Location Code" := 'OTHER';
        LP.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'Lokasyonlar arası stok aktarımı') > 0, 'Cross-location stock was accepted without transfer.');
    end;

    [Test]
    procedure WrongLotPickCannotBeReused()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Lot No." := 'OTHER-LOT';
        Line.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'tamamını') > 0, 'Wrong tracking pick should be rejected.');
    end;

    [Test]
    procedure RepeatedLpLinesCannotReuseTheSamePickCapacity()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 3);
        LPLine.Get(LP."No.", 10000);
        LPLine."Line No." := 20000;
        LPLine.Insert(false);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Qty. Outstanding (Base)" := 4;
        Line.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'tamamını') > 0, 'Repeated LP lines double-counted pick capacity.');
    end;

    [Test]
    procedure RepeatedLpLinesCannotExceedProductionDemand()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 6);
        LPLine.Get(LP."No.", 10000);
        LPLine."Line No." := 20000;
        LPLine.Insert(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'kalan ihtiyacını aşıyor') > 0, 'Repeated LP lines double-counted production demand.');
    end;

    [Test]
    procedure LpDemandComparisonUsesBaseUnits()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ItemUom: Record "Item Unit of Measure";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 6);
        ItemUom.Init();
        ItemUom."Item No." := 'PROD-LP-ITEM';
        ItemUom.Code := 'BOX';
        ItemUom."Qty. per Unit of Measure" := 2;
        ItemUom.Insert(false);
        LPLine.Get(LP."No.", 10000);
        LPLine."Unit of Measure" := 'BOX';
        LPLine.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'kalan ihtiyacını aşıyor') > 0, 'Six boxes were treated as six base units.');
    end;

    [Test]
    procedure ReadyLpScopesPrefilledTakeAndPlaceQuantities()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Line No." := 30000;
        Line."Bin Code" := 'OTHER';
        Line.Insert(false);
        Line."Line No." := 40000;
        Line."Action Type" := Line."Action Type"::Place;
        Line."Bin Code" := 'PROD';
        Line.Insert(false);
        Line.SetRange("Activity Type", Line."Activity Type"::Pick);
        Line.SetRange("No.", Pick."No.");
        Line.ModifyAll("Qty. to Handle", 10);
        Line.ModifyAll("Qty. to Handle (Base)", 10);
        Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Check(Line."Qty. to Handle" = 4, 'Full order demand replaced the selected pallet quantity.');
        Check(Line."LP No." = LP."No.", 'Selected pallet hint is missing.');
        Check(Line.Quantity = 10, 'Outstanding production demand was reduced.');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 20000);
        Check(Line."Qty. to Handle" = 4, 'Selected Place quantity is not balanced.');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 30000);
        Check(Line."Qty. to Handle" = 0, 'Unrelated Take remains scheduled for registration.');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 40000);
        Check(Line."Qty. to Handle" = 0, 'Unrelated Place remains scheduled for registration.');
    end;

    [Test]
    procedure ReadyLpDoesNotResetPartialWork()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Qty. to Handle" := 2;
        Line."Qty. to Handle (Base)" := 2;
        Line.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'başlanmış toplama') > 0, 'Partial work was not protected.');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Check(Line."Qty. to Handle" = 2, 'Existing partial quantity was overwritten.');
    end;

    [Test]
    procedure ReadyLpDoesNotOverwriteScannedPallet()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."LP No." := 'ANOTHER-LP';
        Line.Modify(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'başlanmış toplama') > 0, 'Existing scanned pallet was overwritten.');
    end;

    [Test]
    procedure ReopeningReservedLpPreservesCurrentQuantity()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        Line: Record "Warehouse Activity Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 4);
        Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Line."Qty. to Handle" := 0;
        Line."Qty. to Handle (Base)" := 0;
        Line.Modify(false);
        Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Line.Get(Line."Activity Type"::Pick, Pick."No.", 10000);
        Check(Line."Qty. to Handle" = 0, 'Reopening the pick reset operator work.');
    end;

    [Test]
    procedure DifferentLotsCannotShareOneUntrackedTake()
    var
        Pick: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS Prod Mgmt";
    begin
        Fixture(Pick);
        PalletFixture(LP, 2);
        LPLine.Get(LP."No.", 10000);
        LPLine."Line No." := 20000;
        LPLine."Lot No." := 'LOT-B';
        LPLine.Insert(false);
        asserterror Management.CreateProductionPickFromLpFor('PROD-LP-TEST', LP."No.", 'OPERATOR');
        Check(StrPos(GetLastErrorText(), 'tamamını') > 0, 'Different tracking identities shared a standard line.');
    end;

    local procedure Fixture(var Pick: Record "Warehouse Activity Header")
    var
        Setup: Record "DOPSWHS Setup";
        ProductionOrder: Record "Production Order";
        Component: Record "Prod. Order Component";
        Line: Record "Warehouse Activity Line";
        Item: Record Item;
        Location: Record Location;
        Bin: Record Bin;
        Uom: Record "Unit of Measure";
        ItemUom: Record "Item Unit of Measure";
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(false);
        end;
        Setup."License Service URL" := '';
        Setup.Modify(false);

        Item.Init();
        Item."No." := 'PROD-LP-ITEM';
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert(false);
        if not Uom.Get('PCS') then begin
            Uom.Code := 'PCS';
            Uom.Insert(false);
        end;
        ItemUom."Item No." := Item."No.";
        ItemUom.Code := 'PCS';
        ItemUom."Qty. per Unit of Measure" := 1;
        ItemUom.Insert(false);
        Location.Code := 'P-LP-TEST';
        Location.Insert(false);
        Bin."Location Code" := Location.Code;
        Bin.Code := 'STOCK';
        Bin.Insert(false);
        Bin.Code := 'PROD';
        Bin.Insert(false);
        ProductionOrder.Init();
        ProductionOrder.Status := ProductionOrder.Status::Released;
        ProductionOrder."No." := 'PROD-LP-TEST';
        ProductionOrder.Insert(false);
        Component.Init();
        Component.Status := Component.Status::Released;
        Component."Prod. Order No." := ProductionOrder."No.";
        Component."Prod. Order Line No." := 10000;
        Component."Line No." := 10000;
        Component."Item No." := Item."No.";
        Component."Location Code" := 'P-LP-TEST';
        Component."Bin Code" := 'PROD';
        Component."Unit of Measure Code" := 'PCS';
        Component."Qty. per Unit of Measure" := 1;
        Component."Expected Qty. (Base)" := 10;
        Component."Remaining Qty. (Base)" := 10;
        Component.Insert(false);
        Pick.Init();
        Pick.Type := Pick.Type::Pick;
        Pick."No." := 'P-PROD-LP-TEST';
        Pick."Location Code" := Component."Location Code";
        Pick.Insert(false);
        Line.Init();
        Line."Activity Type" := Line."Activity Type"::Pick;
        Line."No." := Pick."No.";
        Line."Line No." := 10000;
        Line."Action Type" := Line."Action Type"::Take;
        Line."Source Type" := Database::"Prod. Order Component";
        Line."Source Subtype" := Component.Status.AsInteger();
        Line."Source No." := ProductionOrder."No.";
        Line."Source Line No." := Component."Prod. Order Line No.";
        Line."Source Subline No." := Component."Line No.";
        Line."Item No." := Item."No.";
        Line."Location Code" := Component."Location Code";
        Line."Bin Code" := 'STOCK';
        Line."Unit of Measure Code" := 'PCS';
        Line."Qty. per Unit of Measure" := 1;
        Line.Quantity := 10;
        Line."Qty. (Base)" := 10;
        Line."Qty. Outstanding" := 10;
        Line."Qty. Outstanding (Base)" := 10;
        Line."Qty. Rounding Precision" := 0.00001;
        Line."Qty. Rounding Precision (Base)" := 0.00001;
        Line.Insert(false);
        Line."Line No." := 20000;
        Line."Action Type" := Line."Action Type"::Place;
        Line."Bin Code" := 'PROD';
        Line.Insert(false);
    end;

    local procedure PalletFixture(var LP: Record "DOPSWHS LP Header"; Quantity: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LP.Init();
        LP."No." := 'LP-PROD-TEST';
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'P-LP-TEST';
        LP."Bin Code" := 'STOCK';
        LP.Insert(false);
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine."Line No." := 10000;
        LPLine."Item No." := 'PROD-LP-ITEM';
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Quantity;
        LPLine.Insert(false);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
