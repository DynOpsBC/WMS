codeunit 72496 "DOPSWHS Subcontract Tests"
{
    Subtype = Test;

    [Test]
    procedure RemainingQuantitySubtractsPostedDispatchAndConsumption()
    var
        Component: Record "Prod. Order Component";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        CreateComponent(Component, 'SUB-REM', 10000, 10000, 'SUB-ITEM', 10, 8, 'BLUE', '');
        Dispatch.Init();
        Dispatch."Idempotency Key" := CreateGuid();
        Dispatch."Prod. Order No." := Component."Prod. Order No.";
        Dispatch."Prod. Order Line No." := Component."Prod. Order Line No.";
        Dispatch."Component Line No." := Component."Line No.";
        Dispatch."Item No." := Component."Item No.";
        Dispatch.Quantity := 3;
        Dispatch.Status := 'POSTED';
        Dispatch.Insert(true);

        Assert.AreEqual(7, Mgmt.GetRemainingDispatchQuantity(Component), 'Posted dispatch must reduce the unsent expected quantity.');
        Component."Remaining Quantity" := 5;
        Component.Modify();
        Assert.AreEqual(5, Mgmt.GetRemainingDispatchQuantity(Component), 'Consumed quantity must cap what can still be sent.');
    end;

    [Test]
    procedure PendingWithoutPostedDocumentDoesNotReduceAvailableQuantity()
    var
        Component: Record "Prod. Order Component";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        CreateComponent(Component, 'SUB-PEND', 10000, 10000, 'SUB-ITEM', 10, 8, 'BLUE', '');
        Dispatch.Init();
        Dispatch."Idempotency Key" := CreateGuid();
        Dispatch."Prod. Order No." := Component."Prod. Order No.";
        Dispatch."Prod. Order Line No." := Component."Prod. Order Line No.";
        Dispatch."Component Line No." := Component."Line No.";
        Dispatch."Item No." := Component."Item No.";
        Dispatch.Quantity := 3;
        Dispatch.Status := 'PENDING';
        Dispatch."Transfer Order No." := 'NOT-POSTED';
        Dispatch.Insert(true);

        Assert.AreEqual(8, Mgmt.GetRemainingDispatchQuantity(Component), 'An unposted transfer must not reduce component availability.');
    end;

    [Test]
    procedure IdempotencyKeyCannotBeReusedForAnotherOperation()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        IdempotencyKey: Guid;
    begin
        EnsureLocation('RED');
        CreateSubcontractOperation(RoutingLine, 'SUB-IDEMP', 'WC-IDEMP', 'RED', 'V-SUB-IDEMP', 'LINK1');
        IdempotencyKey := CreateGuid();
        Dispatch.Init();
        Dispatch."Idempotency Key" := IdempotencyKey;
        Dispatch."Prod. Order No." := 'OTHER-ORDER';
        Dispatch."Routing Reference No." := RoutingLine."Routing Reference No.";
        Dispatch."Routing No." := RoutingLine."Routing No.";
        Dispatch."Operation No." := RoutingLine."Operation No.";
        Dispatch."Transfer Order No." := 'OTHER-TRANSFER';
        Dispatch.Status := 'POSTED';
        Dispatch.Insert(true);

        asserterror Mgmt.Dispatch(RoutingLine, '[]', IdempotencyKey);
        Assert.ExpectedError('başka bir fason emri/operasyonu');
    end;

    [Test]
    procedure MissingSubcontractLocationStopsBeforeTransferCreation()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        CreateSubcontractOperation(RoutingLine, 'SUB-NOLOC', 'WC-NOLOC', '', 'V-SUB-1', '');

        asserterror Mgmt.Dispatch(RoutingLine, '[]', CreateGuid());
        Assert.ExpectedError('Location Code');
    end;

    [Test]
    procedure MissingTargetBinOnBinMandatoryLocationStopsBeforeTransferCreation()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: Record "Work Center";
        Location: Record Location;
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        EnsureLocation('SUB-BINLOC');
        Location.Get('SUB-BINLOC');
        Location."Bin Mandatory" := true;
        Location.Modify();
        CreateSubcontractOperation(RoutingLine, 'SUB-NOBIN', 'WC-NOBIN', 'SUB-BINLOC', 'V-SUB-BIN', '');
        WorkCenter.Get('WC-NOBIN');
        WorkCenter."To-Production Bin Code" := '';
        WorkCenter.Modify();

        asserterror Mgmt.Dispatch(RoutingLine, '[]', CreateGuid());
        Assert.ExpectedError('To-Production Bin Code');
    end;

    [Test]
    procedure SameSourceAndTargetLocationIsRejected()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        Component: Record "Prod. Order Component";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Payload: Text;
    begin
        EnsureReceiptAndShipmentMode();
        EnsureLocation('BLUE');
        CreateSubcontractOperation(RoutingLine, 'SUB-SAME', 'WC-SAME', 'BLUE', 'V-SUB-2', 'LINK1');
        CreateComponent(Component, 'SUB-SAME', 10000, 10000, 'SUB-ITEM', 5, 5, 'BLUE', 'LINK1');
        Payload := '[{"prodOrderLineNo":10000,"componentLineNo":10000,"quantity":1}]';

        asserterror Mgmt.Dispatch(RoutingLine, Payload, CreateGuid());
        Assert.ExpectedError('kaynak ve fason lokasyonu aynı');
    end;

    [Test]
    procedure AggregateOverDispatchIsRejectedBeforeTransferCreation()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        Component: Record "Prod. Order Component";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Payload: Text;
    begin
        EnsureReceiptAndShipmentMode();
        EnsureLocation('BLUE');
        EnsureLocation('RED');
        CreateSubcontractOperation(RoutingLine, 'SUB-OVER', 'WC-OVER', 'RED', 'V-SUB-3', 'LINK1');
        CreateComponent(Component, 'SUB-OVER', 10000, 10000, 'SUB-ITEM', 5, 5, 'BLUE', 'LINK1');
        Payload := '[{"prodOrderLineNo":10000,"componentLineNo":10000,"quantity":3},' +
            '{"prodOrderLineNo":10000,"componentLineNo":10000,"quantity":3}]';

        asserterror Mgmt.Dispatch(RoutingLine, Payload, CreateGuid());
        Assert.ExpectedError('kalan');
    end;

    [Test]
    procedure LotTrackedComponentRequiresLotBeforeTransferCreation()
    var
        RoutingLine: Record "Prod. Order Routing Line";
        Component: Record "Prod. Order Component";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Payload: Text;
    begin
        EnsureReceiptAndShipmentMode();
        EnsureLocation('BLUE');
        EnsureLocation('RED');
        EnsureLotTrackedItem('SUB-LOT');
        CreateSubcontractOperation(RoutingLine, 'SUB-LOT-ORD', 'WC-LOT', 'RED', 'V-SUB-LOT', 'LINK1');
        CreateComponent(Component, 'SUB-LOT-ORD', 10000, 10000, 'SUB-LOT', 5, 5, 'BLUE', 'LINK1');
        Payload := '[{"prodOrderLineNo":10000,"componentLineNo":10000,"quantity":1}]';

        asserterror Mgmt.Dispatch(RoutingLine, Payload, CreateGuid());
        Assert.ExpectedError('lot numarası zorunludur');
    end;

    [Test]
    procedure MultipleUnlinkedSubcontractOperationsRequireRoutingLinkSetup()
    var
        FirstRoutingLine: Record "Prod. Order Routing Line";
        SecondRoutingLine: Record "Prod. Order Routing Line";
        Component: Record "Prod. Order Component";
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        ComponentCount: Integer;
        RemainingQty: Decimal;
    begin
        EnsureLocation('RED');
        CreateSubcontractOperation(FirstRoutingLine, 'SUB-AMB', 'WC-AMB1', 'RED', 'V-SUB-4', '');
        CreateSubcontractOperation(SecondRoutingLine, 'SUB-AMB', 'WC-AMB2', 'RED', 'V-SUB-5', '');
        SecondRoutingLine."Operation No." := '20';
        SecondRoutingLine."No." := 'WC-AMB2';
        SecondRoutingLine.Insert(true);
        CreateComponent(Component, 'SUB-AMB', 10000, 10000, 'SUB-ITEM', 5, 5, 'BLUE', '');

        asserterror Mgmt.GetOperationSummary(FirstRoutingLine, ComponentCount, RemainingQty);
        Assert.ExpectedError('birden fazla fason operasyon');
    end;

    local procedure CreateSubcontractOperation(var RoutingLine: Record "Prod. Order Routing Line"; ProdOrderNo: Code[20]; WorkCenterNo: Code[20]; LocationCode: Code[10]; VendorNo: Code[20]; RoutingLinkCode: Code[10])
    var
        Vendor: Record Vendor;
        WorkCenter: Record "Work Center";
        Location: Record Location;
    begin
        if not Vendor.Get(VendorNo) then begin
            Vendor.Init();
            Vendor."No." := VendorNo;
            Vendor.Name := VendorNo;
            Vendor.Insert(true);
        end;
        if WorkCenter.Get(WorkCenterNo) then
            WorkCenter.Delete(true);
        WorkCenter.Init();
        WorkCenter."No." := WorkCenterNo;
        WorkCenter.Name := WorkCenterNo;
        WorkCenter."Subcontractor No." := VendorNo;
        WorkCenter."Location Code" := LocationCode;
        if Location.Get(LocationCode) and Location."Bin Mandatory" then
            WorkCenter."To-Production Bin Code" := 'SUB-BIN';
        WorkCenter.Insert(true);

        RoutingLine.Init();
        RoutingLine.Status := RoutingLine.Status::Released;
        RoutingLine."Prod. Order No." := ProdOrderNo;
        RoutingLine."Routing Reference No." := 10000;
        RoutingLine."Routing No." := 'SUB-ROUTE';
        RoutingLine."Operation No." := '10';
        RoutingLine.Type := RoutingLine.Type::"Work Center";
        RoutingLine."No." := WorkCenterNo;
        RoutingLine."Routing Link Code" := RoutingLinkCode;
        if not RoutingLine.Get(
            RoutingLine.Status, RoutingLine."Prod. Order No.", RoutingLine."Routing Reference No.",
            RoutingLine."Routing No.", RoutingLine."Operation No.")
        then
            RoutingLine.Insert(true);
    end;

    local procedure CreateComponent(var Component: Record "Prod. Order Component"; ProdOrderNo: Code[20]; ProdOrderLineNo: Integer; ComponentLineNo: Integer; ItemNo: Code[20]; ExpectedQty: Decimal; RemainingQty: Decimal; LocationCode: Code[10]; RoutingLinkCode: Code[10])
    begin
        Component.Init();
        Component.Status := Component.Status::Released;
        Component."Prod. Order No." := ProdOrderNo;
        Component."Prod. Order Line No." := ProdOrderLineNo;
        Component."Line No." := ComponentLineNo;
        Component."Item No." := ItemNo;
        Component.Description := ItemNo;
        Component."Unit of Measure Code" := 'PCS';
        Component.Quantity := ExpectedQty;
        Component."Expected Quantity" := ExpectedQty;
        Component."Remaining Quantity" := RemainingQty;
        Component."Location Code" := LocationCode;
        Component."Routing Link Code" := RoutingLinkCode;
        Component.Insert(true);
    end;

    local procedure EnsureLocation(LocationCode: Code[10])
    var
        Location: Record Location;
    begin
        if Location.Get(LocationCode) then
            exit;
        Location.Init();
        Location.Code := LocationCode;
        Location.Name := LocationCode;
        Location.Insert(true);
    end;

    local procedure EnsureReceiptAndShipmentMode()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        InventorySetup."Direct Transfer Posting" :=
            InventorySetup."Direct Transfer Posting"::"Receipt and Shipment";
        InventorySetup.Modify();
    end;

    local procedure EnsureLotTrackedItem(ItemNo: Code[20])
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        TrackingCode: Code[10];
    begin
        TrackingCode := 'SUB-LOT';
        if not ItemTrackingCode.Get(TrackingCode) then begin
            ItemTrackingCode.Init();
            ItemTrackingCode.Code := TrackingCode;
            ItemTrackingCode.Description := TrackingCode;
            ItemTrackingCode."Lot Specific Tracking" := true;
            ItemTrackingCode.Insert(true);
        end;
        if Item.Get(ItemNo) then
            Item.Delete(true);
        Item.Init();
        Item."No." := ItemNo;
        Item.Description := ItemNo;
        Item."Base Unit of Measure" := 'PCS';
        Item."Item Tracking Code" := TrackingCode;
        Item.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
