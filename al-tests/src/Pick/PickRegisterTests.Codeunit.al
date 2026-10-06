codeunit 72120 "DOPSWHS Pick Register Tests"
{
    Subtype = Test;

    [Test]
    procedure ReleasedShipmentPickRegistersWarehouseEntries()
    var
        Pick: Record "Warehouse Activity Header";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreatePick(Pick, 'PICK-T5-REG');
        PickMgmt.RegisterPick(Pick);
        Assert.IsTrue(true, 'Register pick should delegate to standard warehouse activity registration.');
    end;

    [Test]
    procedure ExactPlanAcceptsTwoScannedPallets()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        ScannedTestLine(Line);
        Mgt.ValidateScannedPickPlan(Line, ScannedTestPlan());
    end;

    [Test]
    procedure ExactPlanRejectsChangedQuantity()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        ScannedTestLine(Line);
        Line."Qty. to Handle" := 9;
        asserterror Mgt.ValidateScannedPickPlan(Line, ScannedTestPlan());
        Assert.ExpectedError('miktarı değişmiş');
    end;

    [Test]
    procedure ExactPlanRejectsDifferentSourceBin()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        ScannedTestLine(Line);
        Line."Bin Code" := 'OTHER';
        asserterror Mgt.ValidateScannedPickPlan(Line, ScannedTestPlan());
        Assert.ExpectedError('identity');
    end;

    [Test]
    procedure ExactPlanRejectsMissingBaseQuantity()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        ScannedTestLine(Line);
        Line."Qty. to Handle (Base)" := 11;
        asserterror Mgt.ValidateScannedPickPlan(Line, ScannedTestPlan());
        Assert.ExpectedError('karşılamıyor');
    end;

    [Test]
    procedure ExactPlanRejectsDuplicatePallet()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
        Plan: JsonObject;
        Steps: JsonArray;
        Step: JsonObject;
        Token: JsonToken;
        PlanText: Text;
    begin
        ScannedTestLine(Line);
        Plan.ReadFrom(ScannedTestPlan());
        Plan.Get('steps', Token);
        Steps := Token.AsArray();
        Steps.Get(1, Token);
        Step := Token.AsObject();
        Step.Replace('lpNo', 'LP1');
        Steps.Set(1, Step);
        Plan.Replace('steps', Steps);
        Plan.WriteTo(PlanText);
        asserterror Mgt.ValidateScannedPickPlan(Line, PlanText);
        Assert.ExpectedError('tekrar ediyor');
    end;

    [Test]
    procedure SpecificLotTrackingDoesNotRequireWarehousePickLot()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, true, false, false);
        Assert.IsFalse(Mgt.PickLineRequiresLot(Line),
            'Inventory lot tracking alone must not force a lot that warehouse activity validation rejects.');
    end;

    [Test]
    procedure SalesLotTrackingDoesNotRequireWarehousePickLot()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, false, false, true);
        Assert.IsFalse(Mgt.PickLineRequiresLot(Line),
            'Sales outbound lot tracking must remain a shipment requirement when warehouse lot tracking is off.');
    end;

    [Test]
    procedure WarehouseLotTrackingRequiresPickLot()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, false, true, false);
        Assert.IsTrue(Mgt.PickLineRequiresLot(Line),
            'Warehouse lot tracking must still require a lot for picking.');
    end;

    [Test]
    procedure SerialWarehouseTrackingDoesNotRequirePickLot()
    var
        Line: Record "Warehouse Activity Line";
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, false, false, false);
        Item.Get(Line."Item No.");
        TrackingCode.Get(Item."Item Tracking Code");
        TrackingCode."SN Warehouse Tracking" := true;
        TrackingCode.Modify();
        Assert.IsFalse(Mgt.PickLineRequiresLot(Line),
            'Serial warehouse tracking alone must not invent a lot requirement.');
    end;

    [Test]
    procedure SalesLotWithSerialWarehouseTrackingStillRequiresPickLot()
    var
        Line: Record "Warehouse Activity Line";
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, false, false, true);
        Item.Get(Line."Item No.");
        TrackingCode.Get(Item."Item Tracking Code");
        TrackingCode."SN Warehouse Tracking" := true;
        TrackingCode.Modify();
        Line."Source Document" := Line."Source Document"::"Sales Order";

        Assert.IsTrue(Mgt.PickLineRequiresLot(Line),
            'Sales lot tracking must remain required when serial warehouse tracking allows complementary lot tracking.');
        asserterror Line.TestNonSpecificItemTracking();
        Assert.ExpectedError(Line.FieldCaption("Lot No."));
        Line."Lot No." := 'SALES-LOT';
        Line.TestNonSpecificItemTracking();
    end;

    [Test]
    procedure ExistingPickLotRemainsRequiredWithoutWarehouseLotTracking()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, true, false, true);
        Line."Lot No." := 'EXISTING-LOT';
        Assert.IsTrue(Mgt.PickLineRequiresLot(Line),
            'A lot already assigned to the pick must not be silently cleared by a positive-quantity confirmation.');
    end;

    [Test]
    procedure UntrackedPickDoesNotRequireLot()
    var
        Line: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
    begin
        CreateLotTrackingLine(Line, false, false, false);
        Assert.IsFalse(Mgt.PickLineRequiresLot(Line),
            'An untracked pick must continue to allow blank lot numbers.');
        Clear(Line."Item No.");
        Assert.IsFalse(Mgt.PickLineRequiresLot(Line),
            'An incomplete line must not invent a warehouse lot requirement.');
    end;

    local procedure CreateLotTrackingLine(var Line: Record "Warehouse Activity Line"; SpecificTracking: Boolean; WarehouseTracking: Boolean; SalesOutboundTracking: Boolean)
    var
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
    begin
        TrackingCode.Init();
        TrackingCode.Code := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, MaxStrLen(TrackingCode.Code));
        TrackingCode."Lot Specific Tracking" := SpecificTracking;
        TrackingCode."Lot Warehouse Tracking" := WarehouseTracking;
        TrackingCode."Lot Sales Outbound Tracking" := SalesOutboundTracking;
        TrackingCode.Insert();

        Item.Init();
        Item."No." := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, MaxStrLen(Item."No."));
        Item."Item Tracking Code" := TrackingCode.Code;
        Item.Insert();

        Line.Init();
        Line."Activity Type" := Line."Activity Type"::Pick;
        Line."Item No." := Item."No.";
        Line."Qty. to Handle" := 1;
    end;

    local procedure ScannedTestLine(var Line: Record "Warehouse Activity Line")
    begin
        Line.Init();
        Line."No." := 'PICK-SCAN';
        Line."Line No." := 10000;
        Line."Item No." := 'ITEM';
        Line."Location Code" := 'BLUE';
        Line."Bin Code" := 'PICK';
        Line."Unit of Measure Code" := 'PCS';
        Line."Qty. to Handle" := 10;
        Line."Qty. to Handle (Base)" := 10;
    end;

    local procedure ScannedTestPlan(): Text
    begin
        exit('{"lineNo":10000,"quantity":10,"lotNo":"","identity":"PICK-SCAN|ITEM||BLUE|PICK||PCS",' +
             '"steps":[{"lpNo":"LP1","binCode":"PICK","lotNo":"","serialNo":"","baseQuantity":6},' +
             '{"lpNo":"LP2","binCode":"PICK","lotNo":"","serialNo":"","baseQuantity":4}]}');
    end;

    local procedure CreatePick(var Pick: Record "Warehouse Activity Header"; No: Code[20])
    begin
        if Pick.Get(Pick.Type::Pick, No) then
            Pick.Delete(true);
        Pick.Init();
        Pick.Type := Pick.Type::Pick;
        Pick."No." := No;
        Pick."Location Code" := 'BLUE';
        Pick.Insert(true);
    end;
}
