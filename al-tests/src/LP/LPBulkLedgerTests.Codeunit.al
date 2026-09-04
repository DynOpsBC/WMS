codeunit 72144 "DOPSWHS LP Bulk Ledger Tests"
{
    Subtype = Test;

    [Test]
    procedure OneLedgerEntryCreatesTenPalletsWithoutSplittingInventoryHistory()
    var
        BulkRequest: Record "DOPSWHS LP Bulk Request";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WarehouseEntry: Record "Warehouse Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        Counters: array[3] of Code[50];
        CreatedLpNos: List of [Code[20]];
        ReplayedLpNos: List of [Code[20]];
        LpNo: Code[20];
        RequestId: Guid;
        Replayed: Boolean;
        CountSheetNo: Code[20];
        HeaderCountBeforeReplay: Integer;
        OriginalSystemModifiedAt: DateTime;
        OriginalWarehouseSystemModifiedAt: DateTime;
    begin
        Seed();
        CreateItemLedgerEntry(72144001, 1000);
        CreateBinStock(72144001, 1000);
        ItemLedgerEntry.Get(72144001);
        OriginalSystemModifiedAt := ItemLedgerEntry.SystemModifiedAt;
        WarehouseEntry.Get(72144001);
        OriginalWarehouseSystemModifiedAt := WarehouseEntry.SystemModifiedAt;

        RequestId := CreateGuid();
        LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 10, 100,
            RequestId, CreatedLpNos, Replayed);

        Assert.AreEqual(10, CreatedLpNos.Count(), 'Exactly ten physical LP records must be created.');
        Assert.IsFalse(Replayed, 'The first request must create the LP set.');
        ItemLedgerEntry.Get(72144001);
        Assert.AreEqual(1000, ItemLedgerEntry.Quantity, 'The original receipt quantity must stay unchanged.');
        Assert.AreEqual(1000, ItemLedgerEntry."Remaining Quantity", 'LP allocation must not consume or split the ILE.');
        Assert.AreEqual(OriginalSystemModifiedAt, ItemLedgerEntry.SystemModifiedAt, 'The ILE must not be modified.');
        ItemLedgerEntry.SetRange("Document No.", 'BULK-RECEIPT');
        Assert.AreEqual(1, ItemLedgerEntry.Count(), 'The receipt must remain one Item Ledger Entry row.');

        WarehouseEntry.Get(72144001);
        Assert.AreEqual(1000, WarehouseEntry.Quantity, 'The warehouse quantity must stay unchanged.');
        Assert.AreEqual(1000, WarehouseEntry."Qty. (Base)", 'The warehouse base quantity must stay unchanged.');
        Assert.AreEqual('', WarehouseEntry."DOPSWHS LP No.", 'Virtual LP allocation must not stamp the historical warehouse entry.');
        Assert.AreEqual(OriginalWarehouseSystemModifiedAt, WarehouseEntry.SystemModifiedAt, 'The warehouse entry must not be modified.');
        WarehouseEntry.SetRange("Location Code", 'BULKTEST');
        WarehouseEntry.SetRange("Bin Code", 'COUNT-BIN');
        WarehouseEntry.SetRange("Item No.", 'ITEM-BULK');
        Assert.AreEqual(1, WarehouseEntry.Count(), 'Building LP identities in the same bin must not create warehouse movements.');

        LPLine.SetRange("Source Item Ledger Entry No.", 72144001);
        Assert.AreEqual(10, LPLine.Count(), 'Every LP line must reference the same source ILE.');
        LPLine.CalcSums(Quantity);
        Assert.AreEqual(1000, LPLine.Quantity, 'The ten LP lines must allocate exactly 10 x 100.');
        foreach LpNo in CreatedLpNos do begin
            LPHeader.Get(LpNo);
            Assert.AreEqual(LPHeader.Status::Built, LPHeader.Status, 'Every generated LP must be ready for counting.');
            Assert.AreEqual(100, LPHeader."Planned Quantity", 'Every generated LP must carry the requested pallet quantity.');
            Assert.AreEqual(RequestId, LPHeader."Bulk Build Request ID", 'Every LP must retain the retry-safe request ID.');
            Assert.AreEqual(72144001, LPHeader."Bulk Source ILE No.", 'Every LP header must retain the source ILE.');
            LPLine.Get(LpNo, 10000);
            Assert.AreEqual(100, LPLine.Quantity, 'Each generated LP must contain 100 units.');
            Assert.AreEqual(1000, LPLine."Source Document Quantity", 'Each label source must retain the full receipt total.');
            Assert.AreEqual(72144001, LPLine."Source Item Ledger Entry No.", 'Each LP must link back to the one original ILE.');
        end;
        Assert.AreEqual(1000, LPMgt.AllocatedQuantityForItemLedgerEntry(72144001), 'The full ILE quantity must be allocated once.');
        Assert.AreEqual(0, LPMgt.AllocatableQuantityForItemLedgerEntry(72144001), 'No second LP set may be created from the same quantity.');
        BulkRequest.Get(RequestId);
        Assert.IsTrue(BulkRequest.Completed, 'The immutable retry record must be marked complete only after all ten LPs exist.');
        Assert.AreEqual(72144001, BulkRequest."Source ILE No.", 'The retry record must retain the one source ILE.');
        Assert.AreEqual(10, BulkRequest."LP Count", 'The retry record must retain the exact LP count.');
        Assert.AreEqual(100, BulkRequest."Quantity per LP", 'The retry record must retain the exact pallet quantity.');

        LPHeader.Reset();
        HeaderCountBeforeReplay := LPHeader.Count();
        LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 10, 100,
            RequestId, ReplayedLpNos, Replayed);
        Assert.IsTrue(Replayed, 'The same request ID must return the original result.');
        Assert.AreEqual(10, ReplayedLpNos.Count(), 'A replay must return all original LP numbers.');
        foreach LpNo in ReplayedLpNos do
            Assert.IsTrue(CreatedLpNos.Contains(LpNo), 'A replay must not substitute a new LP number.');
        LPHeader.Reset();
        Assert.AreEqual(HeaderCountBeforeReplay, LPHeader.Count(), 'A replay must not create duplicate LP headers.');
        ItemLedgerEntry.Get(72144001);
        Assert.AreEqual(OriginalSystemModifiedAt, ItemLedgerEntry.SystemModifiedAt, 'A replay must leave the ILE untouched.');

        asserterror LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 5, 100,
            RequestId, ReplayedLpNos, Replayed);
        Assert.ExpectedError('farklı bir plan');
        LPHeader.Reset();
        Assert.AreEqual(HeaderCountBeforeReplay, LPHeader.Count(), 'Reusing a request ID for another plan must not create LPs.');

        // Full user scenario: the ten generated labels are scanned into a V2
        // count and a matching count is posted. With zero variance this must
        // remain an LP-only audit operation and never touch inventory history.
        CountSheetNo := CountMgmt.CreateSheet('BULKTEST', Enum::"DOPSWHS Count Mode"::Visible, Counters);
        foreach LpNo in CreatedLpNos do
            Assert.AreEqual(
                1,
                CountMgmt.ScanV2Lp(CountSheetNo, CreateGuid(), LpNo, 'COUNT-BIN', 1),
                'Every generated LP label must resolve to one count line.');
        CountMgmt.CompleteCounter(CountSheetNo, 1);
        CountMgmt.PostSheet(CountSheetNo);
        CountHeader.Get(CountSheetNo);
        Assert.AreEqual(CountHeader.Status::Posted, CountHeader.Status, 'The matching ten-pallet count must post successfully.');
        ItemLedgerEntry.Get(72144001);
        Assert.AreEqual(OriginalSystemModifiedAt, ItemLedgerEntry.SystemModifiedAt, 'Matching LP count posting must leave the ILE untouched.');
        WarehouseEntry.Get(72144001);
        Assert.AreEqual(OriginalWarehouseSystemModifiedAt, WarehouseEntry.SystemModifiedAt, 'Matching LP count posting must leave Warehouse Entry untouched.');
    end;

    [Test]
    procedure CompletedRequestCannotBeRecreatedAfterItsLpWasRemoved()
    var
        BulkRequest: Record "DOPSWHS LP Bulk Request";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        CreatedLpNos: List of [Code[20]];
        ReplayedLpNos: List of [Code[20]];
        RequestId: Guid;
        Replayed: Boolean;
    begin
        Seed();
        CreateItemLedgerEntry(72144004, 100);
        CreateBinStock(72144004, 100);
        ItemLedgerEntry.Get(72144004);
        RequestId := CreateGuid();
        LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 1, 100,
            RequestId, CreatedLpNos, Replayed);
        LPHeader.Get(CreatedLpNos.Get(1));
        LPMgt.Unbuild(LPHeader);
        LPHeader.Delete(true);
        BulkRequest.Get(RequestId);
        Assert.IsTrue(BulkRequest.Completed, 'Removing an LP must not remove its immutable request record.');

        asserterror LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 1, 100,
            RequestId, ReplayedLpNos, Replayed);

        Assert.ExpectedError('LP kayıtları bulunamadı');
        LPHeader.SetRange("Bulk Build Request ID", RequestId);
        Assert.AreEqual(0, LPHeader.Count(), 'A completed request must never create a replacement LP set.');
        ItemLedgerEntry.Get(72144004);
        Assert.AreEqual(100, ItemLedgerEntry.Quantity, 'Lifetime idempotency handling must not modify the ILE.');
    end;

    [Test]
    procedure LegacyLpContentsCannotBeAllocatedAgainFromAnUnlinkedLedgerEntry()
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        LegacyLP: Record "DOPSWHS LP Header";
        LPHeader: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        CreatedLpNos: List of [Code[20]];
        HeaderCountBefore: Integer;
    begin
        Seed();
        CreateItemLedgerEntry(72144002, 1000);
        CreateBinStock(72144002, 1000);
        LPMgt.Build('PALLET-EUR', 'BULKTEST', 'COUNT-BIN', LegacyLP);
        LPMgt.AddLine(LegacyLP, 'ITEM-BULK', 'ADET', 1000, '', '', 0D);
        LPMgt.Stop(LegacyLP, false);
        LPHeader.Reset();
        HeaderCountBefore := LPHeader.Count();
        ItemLedgerEntry.Get(72144002);

        asserterror LPMgt.BuildManyFromItemLedgerEntry(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 10, 100, CreatedLpNos);

        Assert.ExpectedError('LP''ye atanmamış serbest stoku yetersizdir');
        LPHeader.Reset();
        Assert.AreEqual(HeaderCountBefore, LPHeader.Count(), 'A rejected request must not leave partial LP headers behind.');
        ItemLedgerEntry.Get(72144002);
        Assert.AreEqual(1000, ItemLedgerEntry.Quantity, 'A rejected request must not alter the source ILE.');
    end;

    [Test]
    procedure PlannedHeaderOnlyLegacyLpRequiresExplicitCleanup()
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        LegacyLP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
        CreatedLpNos: List of [Code[20]];
    begin
        Seed();
        CreateItemLedgerEntry(72144003, 1000);
        CreateBinStock(72144003, 1000);
        LPMgt.Build('PALLET-EUR', 'BULKTEST', 'COUNT-BIN', LegacyLP);
        LegacyLP."Planned Quantity" := 100;
        LegacyLP.Modify(true);
        LPMgt.Stop(LegacyLP, false);
        ItemLedgerEntry.Get(72144003);

        asserterror LPMgt.BuildManyFromItemLedgerEntry(
            ItemLedgerEntry."Entry No.", 'PALLET-EUR', 'COUNT-BIN', 10, 100, CreatedLpNos);

        Assert.ExpectedError('eski/boş');
        ItemLedgerEntry.Get(72144003);
        Assert.AreEqual(1000, ItemLedgerEntry.Quantity, 'Legacy conflict handling must leave the ILE untouched.');
    end;

    local procedure Seed()
    var
        Helper: Codeunit "DOPSWHS Test Helper";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        Setup: Record "DOPSWHS Setup";
    begin
        Helper.ResetSetup();
        SeedNoSeries('BULK-LP', 'BLP000001', 'BLP009999');
        SeedNoSeries('BULK-SSCC', '7000000001', '7000009999');
        Setup := Helper.EnsureSetup();
        Setup."LP No. Series" := 'BULK-LP';
        Setup."SSCC No. Series" := 'BULK-SSCC';
        Setup."GS1 Company Prefix" := '1234567';
        Setup.Modify(true);
        SeedItem('ITEM-BULK', 'ADET');
        SeedLocationBin('BULKTEST', 'COUNT-BIN');
        SetupWizard.SeedDefaultLPTemplates();
    end;

    local procedure CreateItemLedgerEntry(EntryNo: Integer; Qty: Decimal)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.Init();
        ItemLedgerEntry."Entry No." := EntryNo;
        ItemLedgerEntry."Item No." := 'ITEM-BULK';
        ItemLedgerEntry."Posting Date" := WorkDate();
        ItemLedgerEntry."Entry Type" := ItemLedgerEntry."Entry Type"::Purchase;
        ItemLedgerEntry."Document No." := 'BULK-RECEIPT';
        ItemLedgerEntry."Location Code" := 'BULKTEST';
        ItemLedgerEntry.Quantity := Qty;
        ItemLedgerEntry."Remaining Quantity" := Qty;
        ItemLedgerEntry.Positive := true;
        ItemLedgerEntry.Open := true;
        ItemLedgerEntry.Insert(false);
    end;

    local procedure CreateBinStock(EntryNo: Integer; Qty: Decimal)
    var
        BinContent: Record "Bin Content";
        WarehouseEntry: Record "Warehouse Entry";
    begin
        if not BinContent.Get('BULKTEST', 'COUNT-BIN', 'ITEM-BULK', '', 'ADET') then begin
            BinContent.Init();
            BinContent."Location Code" := 'BULKTEST';
            BinContent."Bin Code" := 'COUNT-BIN';
            BinContent."Item No." := 'ITEM-BULK';
            BinContent."Unit of Measure Code" := 'ADET';
            BinContent.Insert(false);
        end;
        WarehouseEntry.Init();
        WarehouseEntry."Entry No." := EntryNo;
        WarehouseEntry."Registering Date" := WorkDate();
        WarehouseEntry."Location Code" := 'BULKTEST';
        WarehouseEntry."Bin Code" := 'COUNT-BIN';
        WarehouseEntry."Item No." := 'ITEM-BULK';
        WarehouseEntry."Unit of Measure Code" := 'ADET';
        WarehouseEntry."Qty. per Unit of Measure" := 1;
        WarehouseEntry.Quantity := Qty;
        WarehouseEntry."Qty. (Base)" := Qty;
        WarehouseEntry.Insert(false);
    end;

    local procedure SeedNoSeries(Code: Code[20]; StartNo: Code[20]; EndNo: Code[20])
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(Code) then begin
            NoSeries.Init();
            NoSeries.Code := Code;
            NoSeries.Description := Code;
            NoSeries.Insert(true);
        end;
        if not NoSeriesLine.Get(Code, 10000) then begin
            NoSeriesLine.Init();
            NoSeriesLine."Series Code" := Code;
            NoSeriesLine."Line No." := 10000;
            NoSeriesLine."Starting No." := StartNo;
            NoSeriesLine."Ending No." := EndNo;
            NoSeriesLine.Insert(true);
        end;
    end;

    local procedure SeedItem(ItemNo: Code[20]; UoM: Code[10])
    var
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if not UnitOfMeasure.Get(UoM) then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := UoM;
            UnitOfMeasure.Insert(true);
        end;
        if not Item.Get(ItemNo) then begin
            Item.Init();
            Item."No." := ItemNo;
            Item.Description := ItemNo;
            Item."Base Unit of Measure" := UoM;
            Item.Insert(true);
        end;
        if not ItemUnitOfMeasure.Get(ItemNo, UoM) then begin
            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure."Item No." := ItemNo;
            ItemUnitOfMeasure.Code := UoM;
            ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
            ItemUnitOfMeasure.Insert(true);
        end;
    end;

    local procedure SeedLocationBin(LocationCode: Code[10]; BinCode: Code[20])
    var
        Location: Record Location;
        Bin: Record Bin;
    begin
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not Bin.Get(LocationCode, BinCode) then begin
            Bin.Init();
            Bin."Location Code" := LocationCode;
            Bin.Code := BinCode;
            Bin.Insert(true);
        end;
    end;
}
