codeunit 72152 "DOPSWHS Bin LP Compare Tests"
{
    // Göz ve LP Karşılaştırma: göz stoğu (Göz İçeriği / Depo Girişi) ile gözdeki
    // aktif LP miktarının madde/lot bazında karşılaştırılması ve olası neden.
    // BADE örneği: K.K03.11 gözünde 45.000 stok, 90.000 LP (1.14.1.147 öncesi).
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Item Ledger Entry" = rimd,
        tabledata "Warehouse Entry" = rimd,
        tabledata "Bin Content" = rimd;

    var
        Assert: Codeunit "Library Assert";
        CompareMgt: Codeunit "DOPSWHS Bin LP Compare Mgt";
        NextWhseEntryNo: Integer;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure EqualStockAndLpIsGreenAndHiddenWhenOnlyDifferences()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 10);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Built, ItemNo(), '', 'PCS', 10);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        Assert.AreEqual(1, TempRow.Count(), 'Tek göz/madde satırı olmalı.');
        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::Equal, TempRow."Comparison Status", 'Stok = LP eşit olmalı.');
        Assert.AreEqual(0, TempRow.Difference, 'Fark sıfır olmalı.');
        Assert.AreEqual(1, TempRow."LP Count", 'Bir LP sayılmalı.');
        Assert.IsFalse(CompareMgt.IncludeRow(TempRow, true), 'Eşit satır "yalnız farklar" açıkken gizlenmeli.');
        Assert.IsTrue(CompareMgt.IncludeRow(TempRow, false), 'Eşit satır tüm satırlarda görünmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PhantomLpQuantityIsRed()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        // K.K03.11: 45.000 stok, iki LP'de toplam 90.000.
        Seed();
        AddStock(BinA(), ItemNo(), '', 45000);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Built, ItemNo(), '', 'PCS', 45000);
        CreateLp('BLP152-LP2', BinA(), Enum::"DOPSWHS LP Status"::Assigned, ItemNo(), '', 'PCS', 45000);
        CreateLiveActivity("Warehouse Activity Type"::Pick, 'BLP152-PI');
        SetAssignment('BLP152-LP2', Enum::"DOPSWHS Assigned Doc Type"::WhsePick, 'BLP152-PI');

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::LpOver, TempRow."Comparison Status", 'LP stoktan fazla (hayalet LP) olmalı.');
        Assert.AreEqual(45000, TempRow."Stock Qty. (Base)", 'BC stok 45.000 olmalı.');
        Assert.AreEqual(90000, TempRow."LP Qty. (Base)", 'LP toplamı 90.000 olmalı.');
        Assert.AreEqual(45000, TempRow.Difference, 'Fark LP − Stok = 45.000 olmalı.');
        Assert.AreEqual(2, TempRow."LP Count", 'İki LP sayılmalı.');
        Assert.AreEqual(TempRow.Reason::"None", TempRow.Reason, 'Canlı belgeye atanmış LP yetim sayılmamalı.');
        Assert.AreEqual('lpOver', CompareMgt.StatusKey(TempRow), 'JSON durum anahtarı lpOver olmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LooseStockWithoutLpIsOrange()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 30);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Open, ItemNo(), '', 'PCS', 10);
        AddStock(BinB(), ItemNo(), '', 5);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::StockOver, TempRow."Comparison Status", 'Stok LP''den fazla olmalı.');
        Assert.AreEqual(-20, TempRow.Difference, '20 adet LP''siz stok olmalı.');
        FindRow(TempRow, BinB(), ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::StockNoLp, TempRow."Comparison Status", 'LP''siz göz LP''siz stok olmalı.');
        Assert.AreEqual(0, TempRow."LP Count", 'LP sayısı sıfır olmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LpLinesAreConvertedToBaseUnit()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
        UomKnown: Boolean;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 35);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Built, ItemNo(), '', 'BOX', 3);
        AddLpLine('BLP152-LP1', 20000, ItemNo(), '', 'PCS', 5);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(35, TempRow."LP Qty. (Base)", '3 KUTU x 10 + 5 ADET = 35 temel birim olmalı.');
        Assert.AreEqual(TempRow."Comparison Status"::Equal, TempRow."Comparison Status", 'Birim çevrimiyle eşit olmalı.');
        Assert.AreEqual(2, TempRow."LP Line Count", 'İki LP satırı sayılmalı.');
        Assert.AreEqual(1, TempRow."LP Count", 'Aynı LP iki kez sayılmamalı.');
        Assert.AreEqual(7, CompareMgt.ToBaseQty(ItemNo(), 'NOUOM', 7, UomKnown), 'Bilinmeyen birim 1 kabul edilmeli.');
        Assert.IsFalse(UomKnown, 'Bilinmeyen birim işaretlenmeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure InactiveLpsAreIgnored()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 10);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Built, ItemNo(), '', 'PCS', 10);
        CreateLp('BLP152-USED', BinA(), Enum::"DOPSWHS LP Status"::Used, ItemNo(), '', 'PCS', 10);
        CreateLp('BLP152-UNB', BinA(), Enum::"DOPSWHS LP Status"::Unbuilt, ItemNo(), '', 'PCS', 10);
        // Kullanılmış LP tek başına bir satır üretmemeli.
        CreateLp('BLP152-USED2', BinB(), Enum::"DOPSWHS LP Status"::Used, ItemNo(), '', 'PCS', 4);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        Assert.AreEqual(1, TempRow.Count(), 'Yalnız aktif LP''li göz satırı olmalı.');
        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(10, TempRow."LP Qty. (Base)", 'Kullanıldı/Bozuldu LP''ler sayılmamalı.');
        Assert.AreEqual(1, TempRow."LP Count", 'Yalnız aktif LP sayılmalı.');
        Assert.AreEqual(TempRow."Comparison Status"::Equal, TempRow."Comparison Status", 'Satır eşit olmalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OrphanAssignmentIsDetectedAndShown()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 20);
        CreateLp('BLP152-ORF', BinA(), Enum::"DOPSWHS LP Status"::Assigned, ItemNo(), '', 'PCS', 10);
        SetAssignment('BLP152-ORF', Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, 'BLP152-GONE');
        CreateLp('BLP152-LIVE', BinA(), Enum::"DOPSWHS LP Status"::Assigned, ItemNo(), '', 'PCS', 10);
        CreateLiveActivity("Warehouse Activity Type"::"Put-away", 'BLP152-PU');
        SetAssignment('BLP152-LIVE', Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, 'BLP152-PU');

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, BinA(), ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::Equal, TempRow."Comparison Status", 'Miktar eşit olmalı.');
        Assert.AreEqual(TempRow.Reason::OrphanAssignment, TempRow.Reason, 'Silinmiş belgeye atanmış LP yetim olmalı.');
        Assert.AreEqual('BLP152-ORF', TempRow."Orphan LP Nos.", 'Yalnız yetim LP listelenmeli.');
        Assert.IsTrue(CompareMgt.IncludeRow(TempRow, true), 'İşlem gereken eşit satır "yalnız farklar"da görünmeli.');
        Assert.AreEqual(1, CompareMgt.ReleaseOrphanLps('BLP152-ORF,BLP152-LIVE', false), 'Ön izleme yalnız yetim LP''yi saymalı.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DifferentLotInSameBinIsLotMismatch()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), LotItemNo(), 'LOT-1', 12);
        CreateLp('BLP152-LP1', BinA(), Enum::"DOPSWHS LP Status"::Built, LotItemNo(), 'LOT-2', 'PCS', 12);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        Assert.AreEqual(2, TempRow.Count(), 'Lot bazında iki satır olmalı.');
        FindRow(TempRow, BinA(), LotItemNo(), 'LOT-2');
        Assert.AreEqual(TempRow."Comparison Status"::LpNoStock, TempRow."Comparison Status", 'LP lotunun stoğu yok.');
        Assert.AreEqual(TempRow.Reason::LotMismatch, TempRow.Reason, 'Aynı gözde başka lot stoğu: lot uyuşmazlığı.');
        FindRow(TempRow, BinA(), LotItemNo(), 'LOT-1');
        Assert.AreEqual(TempRow."Comparison Status"::StockNoLp, TempRow."Comparison Status", 'Stok lotunun LP''si yok.');
        Assert.AreEqual(TempRow.Reason::LotMismatch, TempRow.Reason, 'Karşı satır da lot uyuşmazlığı göstermeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoneReceiptLpIsDetectedWithRepairableLines()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
        UndoEntryNos: List of [Integer];
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        OriginalEntryNo := CreateItemLedgerEntry(1, 10, 0, false, 0);
        UndoEntryNo := CreateItemLedgerEntry(2, -10, 0, true, OriginalEntryNo);
        CreateLp('BLP152-UNDO', BinB(), Enum::"DOPSWHS LP Status"::Built, LotItemNo(), 'LOT-U', 'PCS', 10);
        SetSourceEntry('BLP152-UNDO', OriginalEntryNo);

        CompareMgt.Compare(LocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, BinB(), LotItemNo(), 'LOT-U');
        Assert.AreEqual(TempRow."Comparison Status"::LpNoStock, TempRow."Comparison Status", 'Stok yok, LP var olmalı.');
        Assert.AreEqual(TempRow.Reason::UndoneReceipt, TempRow.Reason, 'Geri alınan mal kabul nedeni bulunmalı.');
        Assert.AreEqual(Format(UndoEntryNo, 0, 9), TempRow."Undo Entry Nos.", 'Geri alma kaydı satıra yazılmalı.');
        Assert.AreEqual(1, TempRow."Repairable LP Lines", 'Bir LP satırı boşaltılabilir olmalı.');
        Assert.AreEqual(1, CompareMgt.PreviewUndoneReceiptRepair(TempRow."Undo Entry Nos.", UndoEntryNos), 'Ön izleme bir LP satırı göstermeli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FiltersLimitBinsAndItems()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Seed();
        AddStock(BinA(), ItemNo(), '', 10);
        AddStock(BinB(), ItemNo(), '', 10);
        CreateLp('BLP152-LP1', BinB(), Enum::"DOPSWHS LP Status"::Built, ItemNo(), '', 'PCS', 15);

        CompareMgt.Compare(LocationCode(), '', BinB(), BinB(), ItemNo(), TempRow);

        Assert.AreEqual(1, TempRow.Count(), 'Göz aralığı yalnız BLP-B''yi içermeli.');
        FindRow(TempRow, BinB(), ItemNo(), '');
        Assert.AreEqual(5, TempRow.Difference, 'LP 5 fazla olmalı.');
    end;

    // ---------------------------------------------------------------- fixture

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NonBinLocationComparesLocationStockFromItemLedger()
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
        Location: Record Location;
        Root: JsonObject;
        Token: JsonToken;
    begin
        // Kitoko: göz zorunlu olmayan lokasyon. Stok açık madde girişlerinden,
        // LP'ler gözüne bakılmadan (LP'de eski bir göz kodu yazılı olsa da) sayılır.
        Seed();
        if not Location.Get(NonBinLocationCode()) then begin
            Location.Init();
            Location.Code := NonBinLocationCode();
            Location."Bin Mandatory" := false;
            Location.Insert(false);
        end;
        CreateLocationEntry(20, NonBinLocationCode(), LotItemNo(), 'L1', 30);
        CreateLocationEntry(21, NonBinLocationCode(), ItemNo(), '', 10);
        CreateLpAt('BLP152-NB1', NonBinLocationCode(), '', LotItemNo(), 'L1', 40);
        CreateLpAt('BLP152-NB2', NonBinLocationCode(), 'ESKI-GOZ', ItemNo(), '', 1);
        AddLpLine('BLP152-NB2', 20000, ItemNo(), '', 'PCS', 9);

        CompareMgt.Compare(NonBinLocationCode(), '', '', '', '', TempRow);

        FindRow(TempRow, '', LotItemNo(), 'L1');
        Assert.AreEqual(TempRow."Comparison Status"::LpOver, TempRow."Comparison Status", 'LP (40) lokasyon stoğundan (30) fazla.');
        Assert.AreEqual(30, TempRow."Stock Qty. (Base)", 'Stok madde girişlerinden.');
        Assert.AreEqual(40, TempRow."LP Qty. (Base)", 'LP toplamı.');
        FindRow(TempRow, '', ItemNo(), '');
        Assert.AreEqual(TempRow."Comparison Status"::Equal, TempRow."Comparison Status", 'Gözü yazılı LP de lokasyon düzeyinde eşleşmeli.');
        TempRow.Reset();
        TempRow.SetFilter("Bin Code", '<>%1', '');
        Assert.IsTrue(TempRow.IsEmpty(), 'Göz zorunlu olmayan lokasyonda göz kırılımı olmamalı.');

        Root.ReadFrom(CompareMgt.BuildDataJson(CompareMgt.MakeFilterJson(NonBinLocationCode(), '', '', '', '', false)));
        Root.Get('binMandatory', Token);
        Assert.IsFalse(Token.AsValue().AsBoolean(), 'JSON göz modu kapalı olmalı.');
    end;

    local procedure Seed()
    var
        Location: Record Location;
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        NextWhseEntryNo := 2147460000;
        if not Location.Get(LocationCode()) then begin
            Location.Init();
            Location.Code := LocationCode();
            Location.Name := 'Göz LP karşılaştırma testi';
            Location."Bin Mandatory" := true;
            Location.Insert(false);
        end;
        CreateBin(BinA());
        CreateBin(BinB());
        if not Item.Get(ItemNo()) then begin
            Item.Init();
            Item."No." := ItemNo();
            Item.Description := 'BLP152 madde';
            Item."Base Unit of Measure" := 'PCS';
            Item.Insert(false);
        end;
        if not ItemUoM.Get(ItemNo(), 'BOX') then begin
            ItemUoM.Init();
            ItemUoM."Item No." := ItemNo();
            ItemUoM.Code := 'BOX';
            ItemUoM."Qty. per Unit of Measure" := 10;
            ItemUoM.Insert(false);
        end;
        if not Item.Get(LotItemNo()) then begin
            Item.Init();
            Item."No." := LotItemNo();
            Item.Description := 'BLP152 lotlu madde';
            Item."Base Unit of Measure" := 'PCS';
            Item."Item Tracking Code" := 'BLP152LOT';
            Item.Insert(false);
        end;
    end;

    local procedure CreateBin(BinCode: Code[20])
    var
        Bin: Record Bin;
    begin
        if Bin.Get(LocationCode(), BinCode) then
            exit;
        Bin.Init();
        Bin."Location Code" := LocationCode();
        Bin.Code := BinCode;
        Bin."Zone Code" := 'PICK';
        Bin.Insert(false);
    end;

    local procedure AddStock(BinCode: Code[20]; Item: Code[20]; LotNo: Code[50]; QtyBase: Decimal)
    var
        BinContent: Record "Bin Content";
        WarehouseEntry: Record "Warehouse Entry";
    begin
        if not BinContent.Get(LocationCode(), BinCode, Item, '', 'PCS') then begin
            BinContent.Init();
            BinContent."Location Code" := LocationCode();
            BinContent."Bin Code" := BinCode;
            BinContent."Item No." := Item;
            BinContent."Unit of Measure Code" := 'PCS';
            BinContent."Zone Code" := 'PICK';
            BinContent.Insert(false);
        end;
        NextWhseEntryNo += 1;
        WarehouseEntry.Init();
        WarehouseEntry."Entry No." := NextWhseEntryNo;
        WarehouseEntry."Location Code" := LocationCode();
        WarehouseEntry."Bin Code" := BinCode;
        WarehouseEntry."Zone Code" := 'PICK';
        WarehouseEntry."Item No." := Item;
        WarehouseEntry."Unit of Measure Code" := 'PCS';
        WarehouseEntry."Qty. per Unit of Measure" := 1;
        WarehouseEntry."Lot No." := LotNo;
        WarehouseEntry.Quantity := QtyBase;
        WarehouseEntry."Qty. (Base)" := QtyBase;
        WarehouseEntry.Insert(false);
    end;

    local procedure CreateLp(LpNo: Code[20]; BinCode: Code[20]; Status: Enum "DOPSWHS LP Status"; Item: Code[20]; LotNo: Code[50]; Uom: Code[10]; Qty: Decimal)
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP."Location Code" := LocationCode();
        LP."Bin Code" := BinCode;
        LP.Status := Status;
        LP.Insert(false);
        AddLpLine(LpNo, 10000, Item, LotNo, Uom, Qty);
    end;

    local procedure AddLpLine(LpNo: Code[20]; LineNo: Integer; Item: Code[20]; LotNo: Code[50]; Uom: Code[10]; Qty: Decimal)
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.Init();
        Line."LP No." := LpNo;
        Line."Line No." := LineNo;
        Line."Item No." := Item;
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := Uom;
        Line.Quantity := Qty;
        Line.Insert(false);
    end;

    local procedure SetAssignment(LpNo: Code[20]; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LpNo);
        LP."Assigned Document Type" := DocType;
        LP."Assigned Document No." := DocNo;
        LP.Modify(false);
    end;

    local procedure SetSourceEntry(LpNo: Code[20]; EntryNo: Integer)
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.Get(LpNo, 10000);
        Line."Source Item Ledger Entry No." := EntryNo;
        Line.Modify(false);
    end;

    local procedure CreateLiveActivity(ActivityType: Enum "Warehouse Activity Type"; DocNo: Code[20])
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.Init();
        ActivityHeader.Type := ActivityType;
        ActivityHeader."No." := DocNo;
        ActivityHeader."Location Code" := LocationCode();
        ActivityHeader.Insert(false);
    end;

    local procedure CreateItemLedgerEntry(Offset: Integer; Qty: Decimal; RemainingQty: Decimal; IsCorrection: Boolean; AppliesToEntryNo: Integer): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460500 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::Purchase;
        Entry."Document Type" := Entry."Document Type"::"Purchase Receipt";
        Entry."Document No." := 'BLP152-RCPT';
        Entry."Document Line No." := 10000;
        Entry."Item No." := LotItemNo();
        Entry."Location Code" := LocationCode();
        Entry."Lot No." := 'LOT-U';
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := RemainingQty;
        Entry.Positive := Qty > 0;
        Entry.Open := RemainingQty <> 0;
        Entry.Correction := IsCorrection;
        Entry."Applies-to Entry" := AppliesToEntryNo;
        Entry.Insert(false);
        exit(Entry."Entry No.");
    end;

    local procedure CreateLpAt(LpNo: Code[20]; Location: Code[10]; BinCode: Code[20]; Item: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP."Location Code" := Location;
        LP."Bin Code" := BinCode;
        LP.Status := LP.Status::Built;
        LP.Insert(false);
        AddLpLine(LpNo, 10000, Item, LotNo, 'PCS', Qty);
    end;

    local procedure CreateLocationEntry(Offset: Integer; Location: Code[10]; Item: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460500 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::"Positive Adjmt.";
        Entry."Document No." := 'BLP152-ADJ';
        Entry."Item No." := Item;
        Entry."Location Code" := Location;
        Entry."Lot No." := LotNo;
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := Qty;
        Entry.Positive := true;
        Entry.Open := true;
        Entry.Insert(false);
    end;

    local procedure NonBinLocationCode(): Code[10]
    begin
        exit('BLP152NB');
    end;

    local procedure FindRow(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; BinCode: Code[20]; Item: Code[20]; LotNo: Code[50])
    begin
        TempRow.Reset();
        TempRow.SetRange("Bin Code", BinCode);
        TempRow.SetRange("Item No.", Item);
        TempRow.SetRange("Lot No.", LotNo);
        Assert.IsTrue(TempRow.FindFirst(), StrSubstNo('%1 / %2 / %3 satırı bulunmalı.', BinCode, Item, LotNo));
        TempRow.Reset();
    end;

    local procedure LocationCode(): Code[10]
    begin
        exit('BLP152');
    end;

    local procedure BinA(): Code[20]
    begin
        exit('BLP-A');
    end;

    local procedure BinB(): Code[20]
    begin
        exit('BLP-B');
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('BLP152-I1');
    end;

    local procedure LotItemNo(): Code[20]
    begin
        exit('BLP152-LOT');
    end;
}
