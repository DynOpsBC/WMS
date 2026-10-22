codeunit 72151 "DOPSWHS LP Trace Tests"
{
    // LP İzlenebilirlik (codeunit 72391) JSON sözleşmesi. BADE (21 Eki 2026):
    // AB.01740 / A102452-A102511 - 2812 RE001191'den + 188 bozulan LP'den,
    // PU001130 silindi (yetim atama), 109433 geri alındı (LP'ler boşaltıldı).
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions =
        tabledata "Item Ledger Entry" = rimd,
        tabledata "Warehouse Activity Header" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TimelineIsChronologicalNotEntryOrder()
    var
        Trace: JsonObject;
        Timeline: JsonArray;
        Base: DateTime;
    begin
        Seed();
        CreateLp('LT151-LP1', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        Base := CreateDateTime(DMY2Date(21, 10, 2026), 080000T);
        // Kayıt sırası tarih sırasından farklı: ekran tarih sırasıyla göstermeli.
        CreateLedger('LT151-LP1', Enum::"DOPSWHS LP Action"::Built, Base, '', '');
        CreateLedger('LT151-LP1', Enum::"DOPSWHS LP Action"::Moved, Base + 2 * 3600000, 'BIN-MOVE', '');
        CreateLedger('LT151-LP1', Enum::"DOPSWHS LP Action"::ItemAdded, Base + 3600000, '', '');

        Trace := Build('lt151-lp1 ');

        Assert.AreEqual('lp', JText(Trace, 'mode'), 'An LP number must open the LP trace (case-insensitive, trimmed).');
        Timeline := JArray(Trace, 'timeline');
        Assert.AreEqual(3, Timeline.Count(), 'Every LP movement ledger row must be on the timeline.');
        Assert.AreEqual('built', JText(Item(Timeline, 0), 'action'), 'Oldest event first.');
        Assert.AreEqual('itemAdded', JText(Item(Timeline, 1), 'action'), 'Events must be ordered by date, not entry number.');
        Assert.AreEqual('moved', JText(Item(Timeline, 2), 'action'), 'Newest event last.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure AssignmentToDeletedDocumentIsOrphan()
    var
        Trace: JsonObject;
        Lp: JsonObject;
        Doc: JsonObject;
    begin
        Seed();
        CreateLp('LT151-LP2', Enum::"DOPSWHS LP Status"::Assigned, Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, 'LT151-PU-DEL');
        // LPMgt.Assign defter metni: belge türü başlığı + belge no bitişik.
        CreateLedger('LT151-LP2', Enum::"DOPSWHS LP Action"::Assigned, CreateDateTime(DMY2Date(21, 10, 2026), 090000T), 'Warehouse Put-awayLT151-PU-DEL', '');

        Trace := Build('LT151-LP2');

        Lp := JObject(Trace, 'lp');
        Assert.IsTrue(JBool(Lp, 'orphan'), 'An LP assigned to a deleted put-away must be flagged as orphan (yetim).');
        Assert.AreEqual('missing', JText(JObject(Lp, 'assigned'), 'state'), 'The assigned document must be reported missing.');
        Assert.IsTrue(HasInsight(Trace, 'orphanAssignment'), 'An orphan insight must explain how to release the LP.');
        Assert.IsTrue(FindDocument(Trace, 'whsePutaway', 'LT151-PU-DEL', Doc), 'The missing put-away must still be listed as a document node.');
        Assert.IsFalse(JBool(Doc, 'exists'), 'The missing put-away node must be marked as not existing.');
        Assert.AreEqual('LT151-PU-DEL', JText(Item(JArray(Trace, 'timeline'), 0), 'missingDocNo'), 'The assignment row must name the vanished document.');

        // Belge araması: silinmiş belgeye atalı LP ağaçta yetim görünür.
        Trace := Build('LT151-PU-DEL');
        Assert.AreEqual('document', JText(Trace, 'mode'), 'A deleted document still finds the LPs assigned to it.');
        Assert.AreEqual(1, JInteger(JObject(Trace, 'totals'), 'orphanLpCount'), 'The LP assigned to the deleted put-away is orphan.');
        Assert.IsTrue(FindDocument(Trace, 'whsePutaway', 'LT151-PU-DEL', Doc), 'The deleted put-away is listed as missing.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure AssignmentToExistingDocumentIsNotOrphan()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Trace: JsonObject;
        Lp: JsonObject;
        Doc: JsonObject;
    begin
        Seed();
        ActivityHeader.Init();
        ActivityHeader.Type := ActivityHeader.Type::"Put-away";
        ActivityHeader."No." := 'LT151-PU';
        ActivityHeader.Insert(false);
        CreateLp('LT151-LP3', Enum::"DOPSWHS LP Status"::Assigned, Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, 'LT151-PU');

        Trace := Build('LT151-LP3');

        Lp := JObject(Trace, 'lp');
        Assert.IsFalse(JBool(Lp, 'orphan'), 'An LP assigned to an existing put-away is not orphaned.');
        Assert.AreEqual('open', JText(JObject(Lp, 'assigned'), 'state'), 'The assigned put-away exists.');
        Assert.IsFalse(HasInsight(Trace, 'orphanAssignment'), 'No orphan insight for a live document.');
        Assert.IsTrue(FindDocument(Trace, 'whsePutaway', 'LT151-PU', Doc), 'The put-away must be a document node.');
        Assert.AreEqual('whsePutaway', JText(JObject(Doc, 'nav'), 'kind'), 'The put-away node must open the put-away page.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LinesFromDifferentRoutesAreSeparateSourceGroups()
    var
        Trace: JsonObject;
        Groups: JsonArray;
        Lines: JsonArray;
        EntryNo: Integer;
    begin
        Seed();
        EntryNo := CreateEntry(1, 'LT151-R1', LotA(), 3000, 3000, false, 0);
        CreateLp('LT151-LP0', Enum::"DOPSWHS LP Status"::Unbuilt, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLp('LT151-LP4', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        // 2812 doğrudan mal kabulden, 188 bozulan LP'den aktarıldı (aynı mal kabul belgesi).
        CreateLine('LT151-LP4', 10000, LotA(), 2812, 'LT151-RE', EntryNo, '');
        CreateLine('LT151-LP4', 20000, LotA(), 188, 'LT151-RE', EntryNo, 'LT151-LP0');

        Trace := Build('LT151-LP4');

        Groups := JArray(Trace, 'sourceGroups');
        Assert.AreEqual(2, Groups.Count(), 'A transferred line must not be merged with a directly received line.');
        Assert.IsTrue(JBool(Trace, 'mixedSources'), 'The LP must be flagged as mixed-source.');
        Assert.AreEqual('doc:whseReceipt:LT151-RE', JText(Item(Groups, 0), 'key'), 'First group: the receipt.');
        Assert.AreEqual(2812, JDecimal(Item(Groups, 0), 'qty'), 'Receipt group quantity.');
        Assert.AreEqual('lp:LT151-LP0', JText(Item(Groups, 1), 'key'), 'Second group: the source LP.');
        Assert.AreEqual(188, JDecimal(Item(Groups, 1), 'qty'), 'Transferred group quantity.');
        Assert.AreEqual('unbuilt', JText(Item(Groups, 1), 'sourceLpStatus'), 'The source LP status must be shown.');
        Lines := JArray(Trace, 'lines');
        Assert.AreEqual('lp:LT151-LP0', JText(Item(Lines, 1), 'groupKey'), 'Each line must carry its source group key.');
        Assert.IsTrue(HasInsight(Trace, 'mixedSources'), 'A mixed-source insight must be listed.');
        Assert.IsFalse(HasInsight(Trace, 'lpExceedsEntryRemaining'), '3000 linked = 3000 remaining: no warning.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoneSourceEntryStillOnLpIsAnError()
    var
        Trace: JsonObject;
        Entry: JsonObject;
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        OriginalEntryNo := CreateEntry(2, 'LT151-R2', LotB(), 10, 0, false, 0);
        UndoEntryNo := CreateEntry(3, 'LT151-R2', LotB(), -10, 0, true, OriginalEntryNo);
        CreateLp('LT151-LP5', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLine('LT151-LP5', 10000, LotB(), 10, '', OriginalEntryNo, '');

        Trace := Build('LT151-LP5');

        Assert.IsTrue(HasInsight(Trace, 'sourceUndoneLpFull'), 'A full LP on an undone receipt entry must be an error.');
        Assert.IsTrue(FindEntry(Trace, OriginalEntryNo, Entry), 'The source entry must be listed.');
        Assert.AreEqual('sourceLine', JText(Entry, 'matchedBy'), 'The source entry is linked by the LP line.');
        Assert.AreEqual(UndoEntryNo, JInteger(Entry, 'undoneByEntryNo'), 'The source entry must point to its undo entry.');
        Assert.AreEqual(10, JDecimal(Entry, 'thisLpQty'), 'Quantity of this LP on the entry.');
        Assert.IsTrue(FindEntry(Trace, UndoEntryNo, Entry), 'The undo (correction) entry must be listed too.');
        Assert.IsTrue(JBool(Entry, 'correction'), 'The undo entry is a correction.');

        // Lot ağacı: geri alınan girişe bağlı LP işaretlenir.
        Trace := Build(LotB());
        Assert.IsTrue(JBool(Item(JArray(Item(JArray(Trace, 'groups'), 0), 'lps'), 0), 'onUndoneEntry'), 'The LP on an undone entry must be flagged in the lot tree.');
        Assert.IsTrue(HasInsight(Trace, 'sourceUndoneLpFull'), 'The lot tree must report the undone entry still on LPs.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LotTreeComparesLpQuantityWithRemainingPerEntry()
    var
        Trace: JsonObject;
        Group: JsonObject;
        Entries: JsonArray;
        FirstEntryNo: Integer;
        SecondEntryNo: Integer;
    begin
        Seed();
        FirstEntryNo := CreateEntry(4, 'LT151-R4', LotC(), 10, 10, false, 0);
        SecondEntryNo := CreateEntry(5, 'LT151-R5', LotC(), 5, 5, false, 0);
        CreateLp('LT151-LPA', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLp('LT151-LPB', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLp('LT151-LPC', Enum::"DOPSWHS LP Status"::Built, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLine('LT151-LPA', 10000, LotC(), 6, '', FirstEntryNo, '');
        CreateLine('LT151-LPB', 10000, LotC(), 4, '', FirstEntryNo, '');
        CreateLine('LT151-LPC', 10000, LotC(), 8, '', SecondEntryNo, '');

        Trace := Build(LotC());

        Assert.AreEqual('lot', JText(Trace, 'mode'), 'A lot number must open the lot tree.');
        Assert.AreEqual(1, JArray(Trace, 'groups').Count(), 'One item/lot group.');
        Group := Item(JArray(Trace, 'groups'), 0);
        Assert.AreEqual(3, JInteger(Group, 'lpCount'), 'All three LPs of the lot.');
        Assert.AreEqual(18, JDecimal(Group, 'lpQty'), 'LP total of the lot.');
        Assert.AreEqual(15, JDecimal(Group, 'bcRemainingQty'), 'BC remaining quantity of the lot.');
        Assert.AreEqual('excess', JText(Group, 'state'), 'LPs carry more than BC stock.');
        Entries := JArray(Group, 'entries');
        Assert.AreEqual(2, Entries.Count(), 'Both receipt entries.');
        Assert.AreEqual(10, JDecimal(Item(Entries, 0), 'lpQty'), 'First entry: 6 + 4 on LPs.');
        Assert.AreEqual(0, JDecimal(Item(Entries, 0), 'diff'), 'First entry fully on LPs.');
        Assert.AreEqual(-3, JDecimal(Item(Entries, 1), 'diff'), 'Second entry: 8 on LP but 5 remaining.');
        Assert.IsTrue(HasInsight(Trace, 'lpExceedsStock'), 'Lot-level excess must be reported.');
        Assert.IsTrue(HasInsight(Trace, 'lpExceedsEntryRemaining'), 'Entry-level excess must be reported.');

        // "MADDE LOT" araması (Madde Defteri eylemi) aynı ağacı verir.
        Trace := Build(ItemNo() + ' ' + LotC());
        Assert.AreEqual('lot', JText(Trace, 'mode'), 'Item + lot search must open the lot tree.');
        Assert.AreEqual(18, JDecimal(JObject(Trace, 'totals'), 'lpQty'), 'Same totals for item + lot search.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UndoneReceiptShowsEmptiedLps()
    var
        Trace: JsonObject;
        Timeline: JsonArray;
        Historic: JsonArray;
        Entry: JsonObject;
        Link: JsonObject;
        OriginalEntryNo: Integer;
        UndoEntryNo: Integer;
    begin
        Seed();
        OriginalEntryNo := CreateEntry(6, 'LT151-R6', LotD(), 10, 0, false, 0);
        UndoEntryNo := CreateEntry(7, 'LT151-R6', LotD(), -10, 0, true, OriginalEntryNo);
        CreateLp('LT151-LP6', Enum::"DOPSWHS LP Status"::Used, Enum::"DOPSWHS Assigned Doc Type"::None, '');
        CreateLedger('LT151-LP6', Enum::"DOPSWHS LP Action"::Built, CreateDateTime(DMY2Date(20, 10, 2026), 080000T), '', '');
        CreateLedger('LT151-LP6', Enum::"DOPSWHS LP Action"::ItemRemoved, CreateDateTime(DMY2Date(21, 10, 2026), 080000T),
            CopyStr(StrSubstNo('UNDO-RCPT:%1:10000', Format(UndoEntryNo, 0, 9)), 1, 40), LotD());

        // Belge araması: geri alınan irsaliye boşaltılan LP'yi gösterir.
        Trace := Build('LT151-R6');
        Assert.AreEqual('document', JText(Trace, 'mode'), 'A posted document number must open the document tree.');
        Historic := JArray(Trace, 'historicLps');
        Assert.AreEqual(1, Historic.Count(), 'The emptied LP must be listed as historic.');
        Assert.AreEqual('LT151-LP6', JText(Item(Historic, 0), 'no'), 'Historic LP number.');
        Assert.IsTrue(JBool(Item(Historic, 0), 'emptiedByUndo'), 'The LP was emptied by the undo.');
        Assert.IsTrue(HasInsight(Trace, 'emptiedByUndo'), 'Emptied-by-undo insight on the document tree.');

        // LP araması: zaman çizelgesi geri alma girişine bağlanır, girişler listelenir.
        Trace := Build('LT151-LP6');
        Timeline := JArray(Trace, 'timeline');
        Assert.IsTrue(JBool(Item(Timeline, 1), 'undo'), 'The removal row must be marked as undo.');
        Link := JObject(Item(Timeline, 1), 'link');
        Assert.AreEqual('ile', JText(Link, 'kind'), 'The undo row links to the item ledger entry.');
        Assert.AreEqual(Format(UndoEntryNo, 0, 9), JText(Link, 'key'), 'The undo row links to the undo entry.');
        Assert.IsTrue(FindEntry(Trace, UndoEntryNo, Entry), 'The undo entry must be listed.');
        Assert.AreEqual('undo', JText(Entry, 'matchedBy'), 'The undo entry is found via the ledger.');
        Assert.IsTrue(FindEntry(Trace, OriginalEntryNo, Entry), 'The undone receipt entry must be listed.');
        Assert.AreEqual(UndoEntryNo, JInteger(Entry, 'undoneByEntryNo'), 'The receipt entry points to its undo.');
        Assert.IsTrue(HasInsight(Trace, 'emptiedByUndo'), 'Emptied-by-undo insight on the LP.');
    end;

    [Test]
    procedure RelatedDocumentNumberIsExtracted()
    var
        TraceData: Codeunit "DOPSWHS LP Trace Data";
    begin
        Assert.AreEqual('PU001130', TraceData.ExtractDocumentNo('Warehouse Put-awayPU001130'), 'Caption glued to the number.');
        Assert.AreEqual('PI000123', TraceData.ExtractDocumentNo('PICK:PI000123'), 'Prefix with colon.');
        Assert.AreEqual('RE001191', TraceData.ExtractDocumentNo('RE001191'), 'Plain number.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UnknownSearchIsNotFound()
    begin
        Assert.AreEqual('notFound', JText(Build('LT151-NOPE-XYZ'), 'mode'), 'Unknown text must return notFound.');
        Assert.AreEqual('empty', JText(Build('   '), 'mode'), 'Blank search must return the empty state.');
    end;

    // ───────────── Fixtures ─────────────

    local procedure Build(SearchText: Text) Trace: JsonObject
    var
        TraceData: Codeunit "DOPSWHS LP Trace Data";
        Payload: Text;
    begin
        // JSON metni üzerinden: sayfanın gönderdiği sözleşme test edilir.
        Payload := TraceData.BuildTraceJson(SearchText);
        Trace.ReadFrom(Payload);
    end;

    local procedure Seed()
    var
        ItemRec: Record Item;
    begin
        if ItemRec.Get(ItemNo()) then
            exit;
        ItemRec.Init();
        ItemRec."No." := ItemNo();
        ItemRec.Description := 'LT151 LP trace fixture';
        ItemRec."Base Unit of Measure" := 'PCS';
        ItemRec.Insert(false);
    end;

    local procedure CreateEntry(Offset: Integer; DocumentNo: Code[20]; LotNo: Code[50]; Qty: Decimal; RemainingQty: Decimal; IsCorrection: Boolean; AppliesToEntryNo: Integer): Integer
    var
        Entry: Record "Item Ledger Entry";
    begin
        Entry.Init();
        Entry."Entry No." := 2147460000 + Offset;
        Entry."Entry Type" := Entry."Entry Type"::Purchase;
        Entry."Document Type" := Entry."Document Type"::"Purchase Receipt";
        Entry."Document No." := DocumentNo;
        Entry."Document Line No." := 10000;
        Entry."Posting Date" := DMY2Date(21, 10, 2026);
        Entry."Item No." := ItemNo();
        Entry."Location Code" := 'LT151';
        Entry."Lot No." := LotNo;
        Entry.Quantity := Qty;
        Entry."Remaining Quantity" := RemainingQty;
        Entry.Positive := Qty > 0;
        Entry.Open := RemainingQty <> 0;
        Entry.Correction := IsCorrection;
        Entry."Applies-to Entry" := AppliesToEntryNo;
        Entry.Insert(false);
        exit(Entry."Entry No.");
    end;

    local procedure CreateLp(LpNo: Code[20]; Status: Enum "DOPSWHS LP Status"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Init();
        LP."No." := LpNo;
        LP.Status := Status;
        LP."Assigned Document Type" := DocType;
        LP."Assigned Document No." := DocNo;
        LP."Location Code" := 'LT151';
        LP."Bin Code" := 'K.K03.11';
        LP.Insert(false);
    end;

    local procedure CreateLine(LpNo: Code[20]; LineNo: Integer; LotNo: Code[50]; Qty: Decimal; ReceiptNo: Code[20]; SourceEntryNo: Integer; SourceLpNo: Code[20])
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line.Init();
        Line."LP No." := LpNo;
        Line."Line No." := LineNo;
        Line."Item No." := ItemNo();
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := 'PCS';
        Line.Quantity := Qty;
        if ReceiptNo <> '' then begin
            Line."Source Document Type" := Line."Source Document Type"::WhseReceipt;
            Line."Source Document No." := ReceiptNo;
            Line."Source Document Line No." := 10000;
        end;
        Line."Source Item Ledger Entry No." := SourceEntryNo;
        Line."Source LP No." := SourceLpNo;
        Line.Insert(false);
    end;

    local procedure CreateLedger(LpNo: Code[20]; LpAction: Enum "DOPSWHS LP Action"; At: DateTime; RelatedDocument: Code[40]; LotNo: Code[50])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger.Init();
        Ledger."LP No." := LpNo;
        Ledger.Action := LpAction;
        Ledger.DateTime := At;
        Ledger."User ID" := 'LT151';
        Ledger."Related Document" := RelatedDocument;
        if LotNo <> '' then begin
            Ledger."Item No." := ItemNo();
            Ledger."Lot Serial" := LotNo;
        end;
        Ledger.Insert(false);
    end;

    // ───────────── JSON helpers ─────────────

    local procedure HasInsight(Trace: JsonObject; InsightCode: Text): Boolean
    var
        Token: JsonToken;
    begin
        foreach Token in JArray(Trace, 'insights') do
            if JText(Token.AsObject(), 'code') = InsightCode then
                exit(true);
        exit(false);
    end;

    local procedure FindDocument(Trace: JsonObject; Kind: Text; DocNo: Text; var Doc: JsonObject): Boolean
    var
        Token: JsonToken;
    begin
        foreach Token in JArray(Trace, 'documents') do
            if (JText(Token.AsObject(), 'kind') = Kind) and (JText(Token.AsObject(), 'no') = DocNo) then begin
                Doc := Token.AsObject();
                exit(true);
            end;
        exit(false);
    end;

    local procedure FindEntry(Trace: JsonObject; EntryNo: Integer; var Entry: JsonObject): Boolean
    var
        Token: JsonToken;
    begin
        foreach Token in JArray(Trace, 'itemLedger') do
            if JInteger(Token.AsObject(), 'entryNo') = EntryNo then begin
                Entry := Token.AsObject();
                exit(true);
            end;
        exit(false);
    end;

    local procedure Item(Source: JsonArray; Index: Integer): JsonObject
    var
        Token: JsonToken;
    begin
        Source.Get(Index, Token);
        exit(Token.AsObject());
    end;

    local procedure JArray(Source: JsonObject; Name: Text): JsonArray
    var
        Token: JsonToken;
    begin
        Source.Get(Name, Token);
        exit(Token.AsArray());
    end;

    local procedure JObject(Source: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
    begin
        Source.Get(Name, Token);
        exit(Token.AsObject());
    end;

    local procedure JText(Source: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure JBool(Source: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        Source.Get(Name, Token);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure JDecimal(Source: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        Source.Get(Name, Token);
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure JInteger(Source: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Source.Get(Name, Token);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure ItemNo(): Code[20]
    begin
        exit('LT151-ITEM');
    end;

    local procedure LotA(): Code[50]
    begin
        exit('LT151-LOT-A');
    end;

    local procedure LotB(): Code[50]
    begin
        exit('LT151-LOT-B');
    end;

    local procedure LotC(): Code[50]
    begin
        exit('LT151-LOT-C');
    end;

    local procedure LotD(): Code[50]
    begin
        exit('LT151-LOT-D');
    end;

    var
        Assert: Codeunit "Library Assert";
}
