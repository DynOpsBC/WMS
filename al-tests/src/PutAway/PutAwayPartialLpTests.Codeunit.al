/// <summary>
/// BADE (23 Eki 2026, 1.14.1.152 - Merve): karma LP'nin yalnız bir ürünü yerleştirilip
/// kalanı sonraya bırakılabilir; tam LP eskisi gibi tek göze taşınır. Ayrıca boş göz
/// önerisi ve mal kabul sonrası yerleştirmenin atanmamış kalması.
/// </summary>
codeunit 72170 "DOPSWHS PutAway Partial LP"
{
    Subtype = Test;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialItemOfMixedLpIsNotRejected()
    var
        Header: Record "Warehouse Activity Header";
        TempPartial: Record "Warehouse Activity Line" temporary;
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Destinations: Dictionary of [Code[20], Code[20]];
    begin
        // [GIVEN] LP000706 senaryosu: aynı LP'de AB.00006 (10) ve AB.00007 (5); yalnız AB.00006 seçildi
        EnsureFixture();
        CreatePutAway(Header, 'PA-PPL-1');
        CreateLp('PPL-LP1', SourceBin(), 'PA-PPL-1');
        AddLpLine('PPL-LP1', 10000, ItemA(), 10);
        AddLpLine('PPL-LP1', 20000, ItemB(), 5);
        InsertPair('PA-PPL-1', 10000, ItemA(), 'PPL-LP1', 10, 10, 'PPL.T1');
        InsertPair('PA-PPL-1', 30000, ItemB(), 'PPL-LP1', 5, 0, 'PPL.T2');

        // [WHEN]
        MovementMgmt.CollectPutAwayLpDestinations(Header, Destinations, TempPartial);

        // [THEN] hata yok; LP başlığı taşınmaz, yalnız seçilen Koy satırı kısmi listede
        Assert.AreEqual(0, Destinations.Count(), 'Kısmi LP başlığı taşınmamalı.');
        Assert.AreEqual(1, TempPartial.Count(), 'Yalnız seçilen Koy satırı kısmi listede olmalı.');
        TempPartial.FindFirst();
        Assert.AreEqual(ItemA(), TempPartial."Item No.", 'Kısmi satır AB.00006 olmalı.');
        Assert.AreEqual('PPL.T1', TempPartial."Bin Code", 'Operatörün seçtiği göz korunmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialFinalizeDebitsOnlyPlacedQuantity()
    var
        Header: Record "Warehouse Activity Header";
        TempPartial: Record "Warehouse Activity Line" temporary;
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Destinations: Dictionary of [Code[20], Code[20]];
    begin
        // [GIVEN] yalnız AB.00006 seçildi ve kaydedildi
        EnsureFixture();
        CreatePutAway(Header, 'PA-PPL-2');
        CreateLp('PPL-LP2', SourceBin(), 'PA-PPL-2');
        AddLpLine('PPL-LP2', 10000, ItemA(), 10);
        AddLpLine('PPL-LP2', 20000, ItemB(), 5);
        InsertPair('PA-PPL-2', 10000, ItemA(), 'PPL-LP2', 10, 10, 'PPL.T1');
        InsertPair('PA-PPL-2', 30000, ItemB(), 'PPL-LP2', 5, 0, 'PPL.T2');
        MovementMgmt.CollectPutAwayLpDestinations(Header, Destinations, TempPartial);
        // standart kayıt AB.00006 çiftini siler
        DeleteLines('PA-PPL-2', 10000, 20000);

        // [WHEN]
        MovementMgmt.FinalizePartialPutAwayLps(TempPartial, 'PA-PPL-2');

        // [THEN] LP kaynak gözde, yalnız AB.00007 kaldı, belgeye atanmış kalır
        LP.Get('PPL-LP2');
        Assert.AreEqual(SourceBin(), LP."Bin Code", 'LP başlığı kaynak gözde kalmalı.');
        Assert.AreEqual(Format(LP.Status::Assigned), Format(LP.Status), 'Kalan satır varken LP atanmış kalmalı.');
        LPLine.SetRange("LP No.", 'PPL-LP2');
        LPLine.SetRange("Item No.", ItemA());
        Assert.IsTrue(LPLine.IsEmpty(), 'Yerleştirilen AB.00006 LP''den düşülmeli.');
        LPLine.SetRange("Item No.", ItemB());
        LPLine.FindFirst();
        Assert.AreEqual(5, LPLine.Quantity, 'AB.00007 LP''de aynen kalmalı.');
        Ledger.SetRange("LP No.", 'PPL-LP2');
        Ledger.SetRange(Action, Ledger.Action::ItemRemoved);
        Ledger.SetRange("Item No.", ItemA());
        Ledger.FindFirst();
        Assert.AreEqual(10, Ledger.Quantity, 'Defterde tam yerleştirilen miktar düşülmeli.');
        Assert.AreEqual(SourceBin(), Ledger."From Bin", 'Defter kaynak gözü');
        Assert.AreEqual('PPL.T1', Ledger."To Bin", 'Defter hedef gözü (operatörün seçtiği)');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialQuantityOfLineReducesLpAndReleasesWhenDone()
    var
        Header: Record "Warehouse Activity Header";
        TempPartial: Record "Warehouse Activity Line" temporary;
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Destinations: Dictionary of [Code[20], Code[20]];
    begin
        // [GIVEN] tek ürünlü LP (10); satırın 4'ü yerleştirildi, belge başka açık satır içermiyor
        EnsureFixture();
        CreatePutAway(Header, 'PA-PPL-3');
        CreateLp('PPL-LP3', SourceBin(), 'PA-PPL-3');
        AddLpLine('PPL-LP3', 10000, ItemA(), 10);
        InsertPair('PA-PPL-3', 10000, ItemA(), 'PPL-LP3', 10, 4, 'PPL.T1');
        MovementMgmt.CollectPutAwayLpDestinations(Header, Destinations, TempPartial);
        Assert.AreEqual(0, Destinations.Count(), 'Kısmi miktarda LP başlığı taşınmamalı.');
        Assert.AreEqual(1, TempPartial.Count(), 'Kısmi miktar kısmi listede olmalı.');
        DeleteLines('PA-PPL-3', 10000, 20000);

        // [WHEN]
        MovementMgmt.FinalizePartialPutAwayLps(TempPartial, 'PA-PPL-3');

        // [THEN] LP'de 6 kaldı; belgede açık satırı kalmadığı için atama bırakıldı
        LPLine.Get('PPL-LP3', 10000);
        Assert.AreEqual(6, LPLine.Quantity, 'LP yalnız yerleştirilen 4 kadar azalmalı.');
        LP.Get('PPL-LP3');
        Assert.AreEqual(SourceBin(), LP."Bin Code", 'LP kaynak gözde kalmalı.');
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Açık satırı kalmayan LP serbest bırakılmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure WholeMixedLpStillMovesAsOneUnit()
    var
        Header: Record "Warehouse Activity Header";
        TempPartial: Record "Warehouse Activity Line" temporary;
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Destinations: Dictionary of [Code[20], Code[20]];
        TargetBin: Code[20];
    begin
        // [GIVEN] LP'nin iki ürünü de tam miktarla aynı göze seçildi
        EnsureFixture();
        CreatePutAway(Header, 'PA-PPL-4');
        CreateLp('PPL-LP4', SourceBin(), 'PA-PPL-4');
        AddLpLine('PPL-LP4', 10000, ItemA(), 10);
        AddLpLine('PPL-LP4', 20000, ItemB(), 5);
        InsertPair('PA-PPL-4', 10000, ItemA(), 'PPL-LP4', 10, 10, 'PPL.T1');
        InsertPair('PA-PPL-4', 30000, ItemB(), 'PPL-LP4', 5, 5, 'PPL.T1');

        // [WHEN]
        MovementMgmt.CollectPutAwayLpDestinations(Header, Destinations, TempPartial);

        // [THEN] eski davranış: LP başlığı tek hedefe taşınacak
        Assert.IsTrue(Destinations.Get('PPL-LP4', TargetBin), 'Tam LP hedef listesinde olmalı.');
        Assert.AreEqual('PPL.T1', TargetBin, 'Tam LP seçilen göze taşınmalı.');
        Assert.AreEqual(0, TempPartial.Count(), 'Tam LP kısmi listeye girmemeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure WholeLpToTwoBinsIsRejected()
    var
        Header: Record "Warehouse Activity Header";
        TempPartial: Record "Warehouse Activity Line" temporary;
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Destinations: Dictionary of [Code[20], Code[20]];
    begin
        EnsureFixture();
        CreatePutAway(Header, 'PA-PPL-5');
        CreateLp('PPL-LP5', SourceBin(), 'PA-PPL-5');
        AddLpLine('PPL-LP5', 10000, ItemA(), 10);
        AddLpLine('PPL-LP5', 20000, ItemB(), 5);
        InsertPair('PA-PPL-5', 10000, ItemA(), 'PPL-LP5', 10, 10, 'PPL.T1');
        InsertPair('PA-PPL-5', 30000, ItemB(), 'PPL-LP5', 5, 5, 'PPL.T2');

        asserterror MovementMgmt.CollectPutAwayLpDestinations(Header, Destinations, TempPartial);
        Assert.ExpectedError('aynı hedef rafı seçin');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure EmptyBinPreferredOverOccupiedBcBin()
    var
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
        Header: Record "Warehouse Activity Header";
        Suggestions: JsonArray;
    begin
        // [GIVEN] BC'nin önerdiği PPL.Z1-01 dolu (aktif LP); aynı bölgede 02 bloke, 03 ve 04 boş;
        // iki LP aynı BC gözüne yönlendirilmiş
        EnsureFixture();
        CreateBin('PPL.Z1-01', 'Z1');
        CreateBin('PPL.Z1-02', 'Z1');
        BlockBin('PPL.Z1-02');
        CreateBin('PPL.Z1-03', 'Z1');
        CreateBin('PPL.Z1-04', 'Z1');
        CreateLp('PPL-OCC', 'PPL.Z1-01', '');
        AddLpLine('PPL-OCC', 10000, ItemA(), 1);
        CreatePutAway(Header, 'PA-PPL-6');
        InsertPairInZone('PA-PPL-6', 10000, ItemA(), 'PPL-LP6A', 'PPL.Z1-01', 'Z1');
        InsertPairInZone('PA-PPL-6', 30000, ItemB(), 'PPL-LP6A', 'PPL.Z1-01', 'Z1');
        InsertPairInZone('PA-PPL-6', 50000, ItemA(), 'PPL-LP6B', 'PPL.Z1-01', 'Z1');

        // [WHEN]
        Suggestions.ReadFrom(DirectedPutAway.SuggestEmptyBinsJson('PA-PPL-6'));

        // [THEN] her Koy satırı için öneri; aynı LP aynı göz, iki LP farklı boş göz
        Assert.AreEqual(3, Suggestions.Count(), 'Her açık Koy satırı için bir öneri dönmeli.');
        AssertSuggestion(Suggestions, 20000, 'PPL.Z1-03', 'EMPTY');
        AssertSuggestion(Suggestions, 40000, 'PPL.Z1-03', 'EMPTY');
        AssertSuggestion(Suggestions, 60000, 'PPL.Z1-04', 'EMPTY');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure EmptyBcBinIsKeptAndOtherZoneIsFallback()
    var
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
        Header: Record "Warehouse Activity Header";
        Location: Record Location;
        Suggestions: JsonArray;
    begin
        // [GIVEN] BC gözü PPL.Z2-01 boş; ikinci LP için Z2'de başka boş göz yok (02 mal kabul gözü),
        // Z3'te boş göz var; üçüncü LP için hiç boş göz kalmıyor
        EnsureFixture();
        CreateBin('PPL.Z2-01', 'Z2');
        CreateBin('PPL.Z2-02', 'Z2');
        CreateBin('PPL.Z3-01', 'Z3');
        Location.Get(LocationCode());
        Location."Receipt Bin Code" := 'PPL.Z2-02';
        Location.Modify();
        CreatePutAway(Header, 'PA-PPL-7');
        InsertPairInZone('PA-PPL-7', 10000, ItemA(), 'PPL-LP7A', 'PPL.Z2-01', 'Z2');
        InsertPairInZone('PA-PPL-7', 30000, ItemA(), 'PPL-LP7B', 'PPL.Z2-01', 'Z2');
        InsertPairInZone('PA-PPL-7', 50000, ItemA(), 'PPL-LP7C', 'PPL.Z2-01', 'Z2');

        // [WHEN]
        Suggestions.ReadFrom(DirectedPutAway.SuggestEmptyBinsJson('PA-PPL-7'));

        // [THEN]
        AssertSuggestion(Suggestions, 20000, 'PPL.Z2-01', 'BC');
        AssertSuggestion(Suggestions, 40000, 'PPL.Z3-01', 'EMPTY');
        AssertSuggestion(Suggestions, 60000, 'PPL.Z2-01', 'BC_FALLBACK');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReceiptPutAwayLeftUnassignedWhenConfigured()
    var
        PutAway: Record "Warehouse Activity Header";
        Setup: Record "DOPSWHS Setup";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        EnsureSetupRecord(Setup);
        Setup."Put-away Assignment" := Setup."Put-away Assignment"::Unassigned;
        Setup.Modify();
        CreateAssignedPutAway(PutAway, 'PA-PPL-A1', 'RCV1');

        ReceiptMgmt.ApplyPutAwayAssignment(PutAway."No.", 'RCV1');

        PutAway.Get(PutAway.Type::"Put-away", PutAway."No.");
        Assert.AreEqual('', PutAway."Assigned User ID", 'Mal kabulü yapanın ataması silinmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReceiptOperatorModeKeepsOldAssignment()
    var
        PutAway: Record "Warehouse Activity Header";
        Setup: Record "DOPSWHS Setup";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        EnsureSetupRecord(Setup);
        Setup."Put-away Assignment" := Setup."Put-away Assignment"::"Receipt Operator";
        Setup.Modify();
        CreateAssignedPutAway(PutAway, 'PA-PPL-A2', '');

        ReceiptMgmt.ApplyPutAwayAssignment(PutAway."No.", 'RCV1');

        PutAway.Get(PutAway.Type::"Put-away", PutAway."No.");
        Assert.AreEqual('RCV1', PutAway."Assigned User ID", 'Receipt Operator modunda eski davranış sürmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UnassignModeNeverTouchesAnotherOwner()
    var
        PutAway: Record "Warehouse Activity Header";
        Setup: Record "DOPSWHS Setup";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        EnsureSetupRecord(Setup);
        Setup."Put-away Assignment" := Setup."Put-away Assignment"::"Edition Default";
        Setup.Modify();
        CreateAssignedPutAway(PutAway, 'PA-PPL-A3', 'OTHER');

        ReceiptMgmt.ApplyPutAwayAssignment(PutAway."No.", 'RCV1');

        PutAway.Get(PutAway.Type::"Put-away", PutAway."No.");
        Assert.AreEqual('OTHER', PutAway."Assigned User ID", 'Başka kullanıcıya yapılmış atama korunmalı.');
    end;

    local procedure AssertSuggestion(Suggestions: JsonArray; LineNo: Integer; ExpectedBin: Code[20]; ExpectedSource: Text)
    var
        Token: JsonToken;
        Value: JsonToken;
        Entry: JsonObject;
    begin
        foreach Token in Suggestions do begin
            Entry := Token.AsObject();
            Entry.Get('lineNo', Value);
            if Value.AsValue().AsInteger() = LineNo then begin
                Entry.Get('binCode', Value);
                Assert.AreEqual(ExpectedBin, Value.AsValue().AsText(), StrSubstNo('%1 satırı önerilen göz', LineNo));
                Entry.Get('source', Value);
                Assert.AreEqual(ExpectedSource, Value.AsValue().AsText(), StrSubstNo('%1 satırı öneri kaynağı', LineNo));
                exit;
            end;
        end;
        Error('%1 satırı için öneri yok.', LineNo);
    end;

    local procedure EnsureFixture()
    var
        UnitOfMeasure: Record "Unit of Measure";
        Location: Record Location;
    begin
        if not UnitOfMeasure.Get('PCS') then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := 'PCS';
            UnitOfMeasure.Insert();
        end;
        EnsureItem(ItemA());
        EnsureItem(ItemB());
        if not Location.Get(LocationCode()) then begin
            Location.Init();
            Location.Code := LocationCode();
            Location.Insert();
        end;
    end;

    local procedure EnsureItem(No: Code[20])
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if not Item.Get(No) then begin
            Item.Init();
            Item."No." := No;
            Item.Description := No;
            Item."Base Unit of Measure" := 'PCS';
            Item.Insert();
        end;
        if not ItemUnitOfMeasure.Get(No, 'PCS') then begin
            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure."Item No." := No;
            ItemUnitOfMeasure.Code := 'PCS';
            ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
            ItemUnitOfMeasure.Insert();
        end;
    end;

    local procedure EnsureSetupRecord(var Setup: Record "DOPSWHS Setup")
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert();
        end;
    end;

    local procedure CreatePutAway(var Header: Record "Warehouse Activity Header"; PutAwayNo: Code[20])
    begin
        Header.Init();
        Header.Type := Header.Type::"Put-away";
        Header."No." := PutAwayNo;
        Header."Location Code" := LocationCode();
        Header.Insert();
    end;

    local procedure CreateAssignedPutAway(var Header: Record "Warehouse Activity Header"; PutAwayNo: Code[20]; AssignedUserId: Code[50])
    begin
        Header.Init();
        Header.Type := Header.Type::"Put-away";
        Header."No." := PutAwayNo;
        Header."Assigned User ID" := AssignedUserId;
        Header.Insert();
    end;

    local procedure CreateBin(BinCode: Code[20]; ZoneCode: Code[10])
    var
        Bin: Record Bin;
    begin
        Bin.Init();
        Bin."Location Code" := LocationCode();
        Bin.Code := BinCode;
        Bin."Zone Code" := ZoneCode;
        Bin.Empty := true;
        Bin.Insert();
    end;

    local procedure BlockBin(BinCode: Code[20])
    var
        Bin: Record Bin;
    begin
        Bin.Get(LocationCode(), BinCode);
        Bin."Block Movement" := Bin."Block Movement"::Inbound;
        Bin.Modify();
    end;

    local procedure CreateLp(LpNo: Code[20]; BinCode: Code[20]; AssignedPutAwayNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP."Location Code" := LocationCode();
        LP."Bin Code" := BinCode;
        if AssignedPutAwayNo <> '' then begin
            LP.Status := LP.Status::Assigned;
            LP."Assigned Document Type" := LP."Assigned Document Type"::WhsePutaway;
            LP."Assigned Document No." := AssignedPutAwayNo;
        end else
            LP.Status := LP.Status::Built;
        LP.Insert();
    end;

    local procedure AddLpLine(LpNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; Qty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := LineNo;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Qty;
        LPLine.Insert();
    end;

    local procedure InsertPair(PutAwayNo: Code[20]; FirstLineNo: Integer; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; QtyToHandle: Decimal; PlaceBinCode: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        InsertActivityLine(PutAwayNo, FirstLineNo, ActivityLine."Action Type"::Take, SourceBin(), '', ItemNo, LpNo, Qty, QtyToHandle);
        InsertActivityLine(PutAwayNo, FirstLineNo + 10000, ActivityLine."Action Type"::Place, PlaceBinCode, '', ItemNo, LpNo, Qty, QtyToHandle);
    end;

    local procedure InsertPairInZone(PutAwayNo: Code[20]; FirstLineNo: Integer; ItemNo: Code[20]; LpNo: Code[20]; PlaceBinCode: Code[20]; ZoneCode: Code[10])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        InsertActivityLine(PutAwayNo, FirstLineNo, ActivityLine."Action Type"::Take, SourceBin(), '', ItemNo, LpNo, 1, 1);
        InsertActivityLine(PutAwayNo, FirstLineNo + 10000, ActivityLine."Action Type"::Place, PlaceBinCode, ZoneCode, ItemNo, LpNo, 1, 1);
    end;

    local procedure InsertActivityLine(PutAwayNo: Code[20]; LineNo: Integer; ActionType: Enum "Warehouse Action Type"; BinCode: Code[20]; ZoneCode: Code[10]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; QtyToHandle: Decimal)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.Init();
        ActivityLine."Activity Type" := ActivityLine."Activity Type"::"Put-away";
        ActivityLine."No." := PutAwayNo;
        ActivityLine."Line No." := LineNo;
        ActivityLine."Action Type" := ActionType;
        ActivityLine."Location Code" := LocationCode();
        ActivityLine."Zone Code" := ZoneCode;
        ActivityLine."Bin Code" := BinCode;
        ActivityLine."Item No." := ItemNo;
        ActivityLine."Unit of Measure Code" := 'PCS';
        ActivityLine."Qty. per Unit of Measure" := 1;
        ActivityLine.Quantity := Qty;
        ActivityLine."Qty. (Base)" := Qty;
        ActivityLine."Qty. Outstanding" := Qty;
        ActivityLine."Qty. Outstanding (Base)" := Qty;
        ActivityLine."Qty. to Handle" := QtyToHandle;
        ActivityLine."Qty. to Handle (Base)" := QtyToHandle;
        ActivityLine."LP No." := LpNo;
        ActivityLine."Whse. Document Type" := ActivityLine."Whse. Document Type"::Receipt;
        ActivityLine."Whse. Document No." := 'PR-PPL';
        ActivityLine."Whse. Document Line No." := LineNo;
        ActivityLine.Insert();
    end;

    local procedure DeleteLines(PutAwayNo: Code[20]; FromLineNo: Integer; ToLineNo: Integer)
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        ActivityLine.SetRange("Line No.", FromLineNo, ToLineNo);
        ActivityLine.DeleteAll();
    end;

    local procedure ItemA(): Code[20]
    begin
        exit('PPL-AB06');
    end;

    local procedure ItemB(): Code[20]
    begin
        exit('PPL-AB07');
    end;

    local procedure LocationCode(): Code[10]
    begin
        exit('PPL');
    end;

    local procedure SourceBin(): Code[20]
    begin
        exit('PPL.K03.11');
    end;

    var
        Assert: Codeunit Assert;
}
