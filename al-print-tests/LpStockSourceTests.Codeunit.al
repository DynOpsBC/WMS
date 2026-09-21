codeunit 72182 "DOPSWHS LP Stock Source Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure Appended850LinksToItsOwnEntryAndPrintsDocument()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        ExistingEntry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        ExistingLine: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
        Builder: Codeunit "DOPSWHS MTE Zpl Builder";
        Encoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
    begin
        Fixture(LP, Entry, Line, 850);
        ExistingEntry := Entry;
        ExistingEntry."Entry No." += 1;
        ExistingEntry.Quantity := 150;
        ExistingEntry."Remaining Quantity" := 150;
        ExistingEntry."Document No." := 'MG-150';
        ExistingEntry."DOPSWHS LP No." := LP."No.";
        ExistingEntry.Insert(false);
        ExistingLine := Line;
        ExistingLine."Line No." := 20000;
        ExistingLine.Quantity := 150;
        ExistingLine."Source Item Ledger Entry No." := ExistingEntry."Entry No.";
        ExistingLine."Source Document No." := ExistingEntry."Document No.";
        ExistingLine.Insert(false);

        // This is the 150-linked + 850-appended field case. Repair is a
        // reference change only; neither stock entry nor LP quantity changes.
        Management.RepairUnlinkedStockLinesForEntry(Entry."Entry No.");
        Line.Get(LP."No.", Line."Line No.");
        Check(Line."Source Item Ledger Entry No." = Entry."Entry No.", '850 was not linked to its own entry.');
        Check(Line."Source Document No." = 'MG-850', 'Source document was not restored.');
        Check(Line.Quantity = 850, 'Repair changed the LP quantity.');
        Entry.Get(Entry."Entry No.");
        Check((Entry.Quantity = 850) and (Entry."Remaining Quantity" = 850), 'Repair changed stock.');
        Check(Entry."DOPSWHS LP No." = LP."No.", 'LP is not visible on the 850 stock entry.');
        ExistingEntry.Get(ExistingEntry."Entry No.");
        Check(ExistingEntry."DOPSWHS LP No." = LP."No.", 'The 150 source link was lost.');
        Zpl := Builder.Build(LP, Line, '{"operatorDisplayName":"Source Test"}');
        Check(StrPos(Zpl, Encoder.EncodeFieldData('MG-850')) > 0, 'Label did not print the repaired source document.');
    end;

    [Test]
    procedure AmbiguousSameLotDoesNotAttachToFirstEntry()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        OtherEntry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        OtherEntry := Entry;
        OtherEntry."Entry No." += 1;
        OtherEntry.Quantity := 150;
        OtherEntry."Remaining Quantity" := 150;
        OtherEntry.Insert(false);
        Management.RepairUnlinkedStockLinesForEntry(Entry."Entry No.");
        Line.Get(LP."No.", Line."Line No.");
        Check(Line."Source Item Ledger Entry No." = 0, 'An ambiguous source was guessed.');
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Line.Get(LP."No.", Line."Line No.");
        Check(Line."Source Item Ledger Entry No." = Entry."Entry No.", 'Explicit source selection was not honored.');
    end;

    [Test]
    procedure WrongLocationAndLotAreRejected()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        Entry."Location Code" := 'OTHER';
        Entry.Modify(false);
        asserterror Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Check(StrPos(GetLastErrorText(), 'uyuşmuyor') > 0, 'Wrong location should fail.');
        Entry."Location Code" := LP."Location Code";
        Entry."Lot No." := 'OTHER-LOT';
        Entry.Modify(false);
        asserterror Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Check(StrPos(GetLastErrorText(), 'uyuşmuyor') > 0, 'Wrong lot should fail.');
        Line.Get(LP."No.", Line."Line No.");
        Check(Line."Source Item Ledger Entry No." = 0, 'A failed link changed the source.');
    end;

    [Test]
    procedure OverAllocationIsRejected()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        Entry."Remaining Quantity" := 849;
        Entry.Modify(false);
        asserterror Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Check(StrPos(GetLastErrorText(), 'ayrılabilir miktar') > 0, 'Insufficient source stock should fail.');
    end;

    [Test]
    procedure BoxesAreAllocatedInBaseUnits()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        ItemUom: Record "Item Unit of Measure";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 20);
        ItemUom."Item No." := Line."Item No.";
        ItemUom.Code := 'BOX';
        ItemUom."Qty. per Unit of Measure" := 10;
        ItemUom.Insert(false);
        Line.Quantity := 2;
        Line."Unit of Measure" := 'BOX';
        Line.Modify(false);
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Check(Management.AllocatedQuantityForItemLedgerEntry(Entry."Entry No.") = 20, 'Two boxes must allocate 20 base units.');
        Check(Management.AllocatableQuantityForItemLedgerEntry(Entry."Entry No.") = 0, 'Base quantity was left available for double allocation.');
    end;

    [Test]
    procedure RepeatedRepairIsIdempotentAndAuditedOnce()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Ledger.SetRange("LP No.", LP."No.");
        Ledger.SetRange(Action, Ledger.Action::SourceLinked);
        Check(Ledger.Count() = 1, 'Repair was audited more than once.');
        Check(Management.AllocatedQuantityForItemLedgerEntry(Entry."Entry No.") = 850, 'Repeated repair duplicated allocation.');
    end;

    [Test]
    procedure HistoricalPostedLpReferenceSurvivesRefresh()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Propagation: Codeunit "DOPSWHS LP Propagation";
    begin
        Fixture(LP, Entry, Line, 850);
        Entry.Quantity := -850;
        Entry."Remaining Quantity" := 0;
        Entry."DOPSWHS LP No." := LP."No.";
        Entry.Modify(false);
        Check(Propagation.BackfillItemLedgerEntryLp(Entry), 'Existing historical reference was not recognized.');
        Entry.Get(Entry."Entry No.");
        Check(Entry."DOPSWHS LP No." = LP."No.", 'Refresh erased a historical posted reference.');
    end;

    [Test]
    procedure MissingSourceFailsBeforePrinting()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        asserterror Management.CheckMteStockSources(LP);
        Check(StrPos(GetLastErrorText(), 'Kaynak Girişi Bağla') > 0, 'Missing origin must be explained before printing.');
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        Management.CheckMteStockSources(LP);
    end;

    [Test]
    procedure ExistingSourceCannotBeOverwritten()
    var
        LP: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        OtherEntry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Management: Codeunit "DOPSWHS LP Management";
    begin
        Fixture(LP, Entry, Line, 850);
        Management.LinkStockLineSource(LP, Line."Line No.", Entry."Entry No.");
        OtherEntry := Entry;
        OtherEntry."Entry No." += 1;
        OtherEntry.Insert(false);
        asserterror Management.LinkStockLineSource(LP, Line."Line No.", OtherEntry."Entry No.");
        Check(StrPos(GetLastErrorText(), 'mevcut kaynak değiştirilemez') > 0, 'Existing origin should not be overwritten.');
    end;

    local procedure Fixture(var LP: Record "DOPSWHS LP Header"; var Entry: Record "Item Ledger Entry"; var Line: Record "DOPSWHS LP Line"; Quantity: Decimal)
    var
        Item: Record Item;
        LastEntry: Record "Item Ledger Entry";
    begin
        Item."No." := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20);
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert(false);
        LP."No." := Item."No.";
        LP."Location Code" := 'SRC-TEST';
        LP."Bin Code" := 'BIN';
        LP.Status := LP.Status::Built;
        LP.Insert(false);
        if LastEntry.FindLast() then
            Entry."Entry No." := LastEntry."Entry No." + 1
        else
            Entry."Entry No." := 1;
        Entry."Item No." := Item."No.";
        Entry."Location Code" := LP."Location Code";
        Entry."Lot No." := 'SOURCE-LOT';
        Entry."Document No." := 'MG-850';
        Entry.Quantity := Quantity;
        Entry."Remaining Quantity" := Quantity;
        Entry."Posting Date" := DMY2Date(17, 3, 2026);
        Entry.Insert(false);
        Line."LP No." := LP."No.";
        Line."Line No." := 10000;
        Line."Item No." := Item."No.";
        Line."Lot No." := Entry."Lot No.";
        Line.Quantity := Quantity;
        Line."Unit of Measure" := 'PCS';
        Line."Source Bin Code" := 'BIN';
        Line.Insert(false);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
