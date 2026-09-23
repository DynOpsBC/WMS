codeunit 72110 "DOPSWHS Bin Rollup Tests"
{
    Subtype = Test;

    [Test]
    procedure ScenarioAOnePalletTwoCartonsEachFiftyTotalsOneHundred()
    var
        Pallet: Record "DOPSWHS LP Header";
        Carton1: Record "DOPSWHS LP Header";
        Carton2: Record "DOPSWHS LP Header";
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateBuiltLP(Pallet, 'PALLET-EUR', 0);
        CreateBuiltLP(Carton1, 'CARTON-M', 50);
        CreateBuiltLP(Carton2, 'CARTON-M', 50);
        Nest(Carton1, Pallet);
        Nest(Carton2, Pallet);
        Assert.AreEqual(100, Rollup.CalculateNestedLPQuantity('BLUE', 'X', 'ITEMY'), 'Scenario A: carton quantities should roll up once.');
    end;

    [Test]
    procedure ScenarioBLooseThirtyPlusPalletFiftyTotalsEighty()
    var
        Pallet: Record "DOPSWHS LP Header";
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLooseQty(30);
        CreateBuiltLP(Pallet, 'PALLET-EUR', 50);
        Assert.AreEqual(80, 30 + Rollup.CalculateNestedLPQuantity('BLUE', 'X', 'ITEMY'), 'Scenario B: loose plus LP should total 80.');
    end;

    [Test]
    procedure ScenarioCWhseEntryAgainstLooseLeavesLPTotal()
    var
        Pallet: Record "DOPSWHS LP Header";
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateLooseQty(30);
        CreateBuiltLP(Pallet, 'PALLET-EUR', 50);
        PostWarehouseEntryAgainstLoose(30);
        Assert.AreEqual(50, Rollup.CalculateNestedLPQuantity('BLUE', 'X', 'ITEMY'), 'Scenario C: loose posting should not reduce LP totals.');
    end;

    [Test]
    procedure ScenarioDThreeLevelPalletCartonToteTotalsNoMultiplication()
    var
        Pallet: Record "DOPSWHS LP Header";
        Carton1: Record "DOPSWHS LP Header";
        Carton2: Record "DOPSWHS LP Header";
        Tote1: Record "DOPSWHS LP Header";
        Tote2: Record "DOPSWHS LP Header";
        Tote3: Record "DOPSWHS LP Header";
        Tote4: Record "DOPSWHS LP Header";
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        CreateBuiltLP(Pallet, 'PALLET-EUR', 0);
        CreateBuiltLP(Carton1, 'CARTON-M', 0); CreateBuiltLP(Carton2, 'CARTON-M', 0);
        CreateBuiltLP(Tote1, 'TOTE-A', 25); CreateBuiltLP(Tote2, 'TOTE-A', 25); CreateBuiltLP(Tote3, 'TOTE-A', 25); CreateBuiltLP(Tote4, 'TOTE-A', 25);
        Nest(Carton1, Pallet); Nest(Carton2, Pallet);
        Nest(Tote1, Carton1); Nest(Tote2, Carton1); Nest(Tote3, Carton2); Nest(Tote4, Carton2);
        Assert.AreEqual(100, Rollup.CalculateNestedLPQuantity('BLUE', 'X', 'ITEMY'), 'Scenario D: leaf quantities should not multiply by container count.');
    end;

    [Test]
    procedure ActiveWarehouseLpSummaryMatchesExactLot()
    var
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
        LpNos: Text[250];
        Qty: Decimal;
    begin
        SeedTrackingSummary();
        Rollup.GetActiveLPTrackingInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', 'LOT-A', '', LpNos, Qty);
        Assert.AreEqual('TEST-LP-A', LpNos, 'Only the LP of LOT-A must appear, once even when it has multiple matching lines.');
        Assert.AreEqual(5, Qty, 'LOT-B, serial-tracked, empty and nonpositive stock must not enter the LOT-A quantity.');
        Rollup.GetActiveLPTrackingInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', 'LOT-B', '', LpNos, Qty);
        Assert.AreEqual('TEST-LP-B', LpNos, 'A different warehouse lot must have its own current LP list.');
        Assert.AreEqual(7, Qty, 'LOT-B quantity must not include LOT-A.');
    end;

    [Test]
    procedure BlankWarehouseLotDoesNotMatchEveryLot()
    var
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
        LpNos: Text[250];
        Qty: Decimal;
    begin
        SeedTrackingSummary();
        Rollup.GetActiveLPTrackingInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', '', '', LpNos, Qty);
        Assert.AreEqual('TEST-LP-EMPTY', LpNos, 'Blank historical tracking must only match current untracked stock.');
        Assert.AreEqual(3, Qty, 'Blank lot is an exact value, not a wildcard.');
    end;

    [Test]
    procedure WarehouseSerialAndMissingMatchesAreIsolated()
    var
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
        LpNos: Text[250];
        Qty: Decimal;
    begin
        SeedTrackingSummary();
        Rollup.GetActiveLPTrackingInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', 'LOT-A', 'S1', LpNos, Qty);
        Assert.AreEqual('TEST-LP-SERIAL', LpNos, 'Only the exact lot and serial may match.');
        Assert.AreEqual(2, Qty, 'Other serials must not contribute quantity.');
        Rollup.GetActiveLPTrackingInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', 'MISSING', '', LpNos, Qty);
        Assert.AreEqual('', LpNos, 'No match must clear the previous row LP list.');
        Assert.AreEqual(0, Qty, 'No match must clear the previous row quantity.');
    end;

    [Test]
    procedure BinContentStillAggregatesAllLots()
    var
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
        LpNos: Text[250];
        Qty: Decimal;
    begin
        SeedTrackingSummary();
        Rollup.GetActiveLPItemInfo('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS', LpNos, Qty);
        Assert.AreEqual(17, Qty, 'Bin Contents has no lot dimension and must still total all positive item stock.');
        Assert.IsTrue(StrPos(LpNos, 'TEST-LP-A') > 0, 'LOT-A must remain in the bin overview.');
        Assert.IsTrue(StrPos(LpNos, 'TEST-LP-B') > 0, 'LOT-B must remain in the bin overview.');
        Assert.IsTrue(StrPos(LpNos, 'TEST-LP-ZERO') = 0, 'An empty LP must not be shown as current stock.');
    end;

    [Test]
    procedure CurrentLPNosCanBeFilteredAsStoredBinContentField()
    var
        BinContent: Record "Bin Content";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Assert: Codeunit "Library Assert";
    begin
        BinContent.Init();
        BinContent."Location Code" := 'LPTEST';
        BinContent."Bin Code" := 'TRACKING';
        BinContent."Item No." := 'ITEM-LPLOT';
        BinContent."Unit of Measure Code" := 'PCS';
        BinContent.Insert(false);
        AddTrackingSummaryLine('TEST-LP-A', 10000, 'LOT-A', '', 4);

        BinContent.SetRange("DOPSWHS Current LP Nos", 'TEST-LP-A');
        Assert.AreEqual(1, BinContent.Count(), 'The LP number must be filterable on Bin Content.');
        BinContent.Reset();
        BinContent.Get('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS');
        Assert.AreEqual('TEST-LP-A', BinContent."DOPSWHS Current LP Nos", 'The LP line must update the stored column.');

        LPLine.Get('TEST-LP-A', 10000);
        LPLine.Quantity := 0;
        LPLine.Modify(false);
        BinContent.Get('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS');
        Assert.AreEqual('', BinContent."DOPSWHS Current LP Nos", 'An empty LP line must leave the column.');

        LPLine.Quantity := 4;
        LPLine.Modify(false);
        LP.Get('TEST-LP-A');
        LP.Status := LP.Status::Unbuilt;
        LP.Modify(false);
        BinContent.Get('LPTEST', 'TRACKING', 'ITEM-LPLOT', '', 'PCS');
        Assert.AreEqual('', BinContent."DOPSWHS Current LP Nos", 'An inactive LP must leave the column.');
    end;

    [Test]
    procedure DrillDownFilterUsesSameExactTrackingScope()
    var
        SourceLine: Record "DOPSWHS LP Line";
        Rollup: Codeunit "DOPSWHS Bin Content Subscriber";
        Assert: Codeunit "Library Assert";
    begin
        SeedTrackingSummary();
        SourceLine.SetFilter("LP No.", 'TEST-LP-*');
        Rollup.FilterActiveLPItemLines(SourceLine, 'ITEM-LPLOT', '', 'PCS', 'LOT-A', '', true);
        Assert.AreEqual(2, SourceLine.Count(), 'Only the two positive LOT-A/unserialized lines may appear in drill-down.');
        SourceLine.CalcSums(Quantity);
        Assert.AreEqual(5, SourceLine.Quantity, 'Drill-down must agree with the summary quantity.');
        Rollup.FilterActiveLPItemLines(SourceLine, 'ITEM-LPLOT', '', 'PCS', '', '', false);
        SourceLine.CalcSums(Quantity);
        Assert.AreEqual(17, SourceLine.Quantity, 'Switching to bin overview must remove previous tracking filters.');
    end;

    [Test]
    procedure LPInquiryShowsContentWithoutBinStockOrSourceLink()
    var
        LPContents: TestPage "DOPSWHS LP Bin Contents";
        Assert: Codeunit "Library Assert";
    begin
        AddTrackingSummaryLine('TEST-LP-NOSTOCK', 10000, 'LOT-A', '', 4080);
        LPContents.OpenView();
        LPContents.Filter.SetFilter("LP No.", 'TEST-LP-NOSTOCK');
        Assert.IsTrue(LPContents.First(), 'An existing LP line must remain visible without any Bin Content row or source ILE.');
        LPContents."LP No.".AssertEquals('TEST-LP-NOSTOCK');
        LPContents.Quantity.AssertEquals(4080);
        LPContents."Source Item Ledger Entry No.".AssertEquals(0);
        LPContents.HasBCBinContent.AssertEquals(false);
        LPContents.BCBinQuantity.AssertEquals(0);
        LPContents.Close();
    end;

    [Test]
    procedure LPInquiryUsesCurrentHeaderBinForProductionLP()
    var
        LP: Record "DOPSWHS LP Header";
        LPContents: TestPage "DOPSWHS LP Bin Contents";
        Assert: Codeunit "Library Assert";
    begin
        AddTrackingSummaryLine('TEST-LP-MOVED', 10000, 'LOT-A', '', 4);
        LP.Get('TEST-LP-MOVED');
        LP."Bin Code" := 'A.URETIM';
        LP.Status := LP.Status::Assigned;
        LP.Modify(false);
        LPContents.OpenView();
        LPContents.Filter.SetFilter("LP Bin Code", 'A.URETIM');
        LPContents.Filter.SetFilter("LP No.", 'TEST-LP-MOVED');
        Assert.IsTrue(LPContents.First(), 'The production LP must be found through its current header bin without stock rows.');
        LPContents."LP Bin Code".AssertEquals('A.URETIM');
        LPContents."LP Status".AssertEquals(LP.Status::Assigned);
        LPContents.Close();
    end;

    [Test]
    procedure LPInquiryExcludesUsedAndZeroQuantityLines()
    var
        LP: Record "DOPSWHS LP Header";
        LPContents: TestPage "DOPSWHS LP Bin Contents";
        Assert: Codeunit "Library Assert";
    begin
        AddTrackingSummaryLine('TEST-LP-INACTIVE', 10000, 'LOT-A', '', 4);
        AddTrackingSummaryLine('TEST-LP-INQUIRY0', 10000, 'LOT-A', '', 0);
        LP.Get('TEST-LP-INACTIVE');
        LP.Status := LP.Status::Used;
        LP.Modify(false);
        LPContents.OpenView();
        LPContents.Filter.SetFilter("LP No.", 'TEST-LP-INACTIVE|TEST-LP-INQUIRY0');
        Assert.IsFalse(LPContents.First(), 'Inactive or empty LP content must not be presented as active LP quantity.');
        LPContents.Close();
    end;

    local procedure SeedTrackingSummary()
    begin
        AddTrackingSummaryLine('TEST-LP-A', 10000, 'LOT-A', '', 4);
        AddTrackingSummaryLine('TEST-LP-A', 20000, 'LOT-A', '', 1);
        AddTrackingSummaryLine('TEST-LP-B', 10000, 'LOT-B', '', 7);
        AddTrackingSummaryLine('TEST-LP-EMPTY', 10000, '', '', 3);
        AddTrackingSummaryLine('TEST-LP-SERIAL', 10000, 'LOT-A', 'S1', 2);
        AddTrackingSummaryLine('TEST-LP-ZERO', 10000, 'LOT-A', '', 0);
        AddTrackingSummaryLine('TEST-LP-NEGATIVE', 10000, 'LOT-A', '', -1);
    end;

    local procedure AddTrackingSummaryLine(LpNo: Code[20]; LineNo: Integer; LotNo: Code[50]; SerialNo: Code[50]; Qty: Decimal)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        // Isolated test fixtures: no production workflow, posting or history writes.
        if not LP.Get(LpNo) then begin
            LP.Init();
            LP."No." := LpNo;
            LP."Location Code" := 'LPTEST';
            LP."Bin Code" := 'TRACKING';
            LP.Status := LP.Status::Built;
            LP.Insert(false);
        end;
        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := LineNo;
        LPLine."Item No." := 'ITEM-LPLOT';
        LPLine."Unit of Measure" := 'PCS';
        LPLine."Lot No." := LotNo;
        LPLine."Serial No." := SerialNo;
        LPLine.Quantity := Qty;
        LPLine.Insert(false);
    end;

    local procedure CreateBuiltLP(var LP: Record "DOPSWHS LP Header"; TemplateCode: Code[20]; Qty: Decimal)
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Build(TemplateCode, 'BLUE', 'X', LP);
        if Qty <> 0 then
            LPMgt.AddLine(LP, 'ITEMY', 'PCS', Qty, '', '', 0D);
        LPMgt.Stop(LP, false);
    end;

    local procedure Nest(var ChildLP: Record "DOPSWHS LP Header"; var ParentLP: Record "DOPSWHS LP Header")
    var
        NestManager: Codeunit "DOPSWHS LP Nest Manager";
        LPLine: Record "DOPSWHS LP Line";
    begin
        NestManager.Nest(ChildLP, ParentLP);
        LPLine.Init();
        LPLine."LP No." := ParentLP."No.";
        LPLine.Validate("Child LP No.", ChildLP."No.");
        LPLine.Insert(true);
    end;

    local procedure CreateLooseQty(Qty: Decimal)
    var
        BinContent: Record "Bin Content";
    begin
        if not BinContent.Get('BLUE', 'X', 'ITEMY', '', 'PCS') then begin
            BinContent.Init();
            BinContent."Location Code" := 'BLUE';
            BinContent."Bin Code" := 'X';
            BinContent."Item No." := 'ITEMY';
            BinContent."Unit of Measure Code" := 'PCS';
            BinContent.Insert(true);
        end;
        BinContent.Quantity := Qty;
        BinContent.Modify(true);
    end;

    local procedure PostWarehouseEntryAgainstLoose(Qty: Decimal)
    var
        WhseEntry: Record "Warehouse Entry";
    begin
        WhseEntry.Init();
        WhseEntry."Entry No." := 72097;
        WhseEntry."Location Code" := 'BLUE';
        WhseEntry."Bin Code" := 'X';
        WhseEntry."Item No." := 'ITEMY';
        WhseEntry.Quantity := -Qty;
        WhseEntry.Insert(true);
    end;

    local procedure Seed()
    var
        Helper: Codeunit "DOPSWHS Test Helper";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        Setup: Record "DOPSWHS Setup";
    begin
        Helper.ResetSetup();
        SeedNoSeries('LP', 'LP03001'); SeedNoSeries('SSCC', '5000000001');
        Setup := Helper.EnsureSetup();
        Setup."LP No. Series" := 'LP'; Setup."SSCC No. Series" := 'SSCC'; Setup."Max LP Nesting Depth" := 3; Setup.Modify(true);
        SeedItem('ITEMY', 'PCS');
        SeedLocationBin('BLUE', 'X');
        SetupWizard.SeedDefaultLPTemplates();
    end;

    local procedure SeedNoSeries(Code: Code[20]; StartNo: Code[20])
    var
        NoSeries: Record "No. Series"; NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(Code) then begin NoSeries.Init(); NoSeries.Code := Code; NoSeries.Insert(true); end;
        if not NoSeriesLine.Get(Code, 10000) then begin NoSeriesLine.Init(); NoSeriesLine."Series Code" := Code; NoSeriesLine."Line No." := 10000; NoSeriesLine."Starting No." := StartNo; NoSeriesLine."Ending No." := IncStr(StartNo); NoSeriesLine.Insert(true); end;
    end;

    local procedure SeedItem(ItemNo: Code[20]; UoM: Code[10])
    var
        Item: Record Item;
    begin
        if not Item.Get(ItemNo) then begin Item.Init(); Item."No." := ItemNo; Item.Description := ItemNo; Item."Base Unit of Measure" := UoM; Item.Insert(true); end;
    end;

    local procedure SeedLocationBin(LocationCode: Code[10]; BinCode: Code[20])
    var
        Location: Record Location; Bin: Record Bin;
    begin
        if not Location.Get(LocationCode) then begin Location.Init(); Location.Code := LocationCode; Location.Insert(true); end;
        if not Bin.Get(LocationCode, BinCode) then begin Bin.Init(); Bin."Location Code" := LocationCode; Bin.Code := BinCode; Bin.Insert(true); end;
    end;
}
