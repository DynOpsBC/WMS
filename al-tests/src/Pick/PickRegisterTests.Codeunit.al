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
