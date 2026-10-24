codeunit 72391 "DOPSWHS LP Trace Data"
{
    // LP İzlenebilirlik (page 72392 "DOPSWHS LP Trace").
    // Bütün veri burada tek bir JSON'da toplanır; sayfa ve React eklentisi yalnız
    // çizer. Her sorgu LP, madde, lot ya da belge filtresiyle ve Max* sınırlarıyla
    // yapılır; sınır aşılırsa "truncated" altında işaretlenir.

    var
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
        Documents: JsonArray;
        DocumentKeys: List of [Text];
        Insights: JsonArray;
        Truncated: JsonObject;
        ResolveCache: Dictionary of [Text, Text];
        ItemDescriptions: Dictionary of [Text, Text];
        UndoEntryCache: Dictionary of [Integer, Integer];
        OrphanLpCount: Integer;
        EmptiedByUndoCount: Integer;
        NodeNotFoundMsg: Label '%1 bulunamadı.', Comment = '%1 = document, LP or entry number';

    /// <summary>Builds the LP trace payload for a search text (LP No., SSCC, item, lot or document).</summary>
    procedure BuildTraceJson(SearchText: Text): Text
    var
        Payload: Text;
    begin
        BuildTrace(SearchText).WriteTo(Payload);
        exit(Payload);
    end;

    /// <summary>Same as BuildTraceJson but never throws; the page shows the error text instead.</summary>
    [TryFunction]
    procedure TryBuildTraceJson(SearchText: Text; var Payload: Text)
    begin
        Payload := BuildTraceJson(SearchText);
    end;

    procedure ErrorJson(ErrorText: Text): Text
    var
        Trace: JsonObject;
        Payload: Text;
    begin
        Trace.Add('version', 1);
        Trace.Add('mode', 'error');
        Trace.Add('message', ErrorText);
        Trace.WriteTo(Payload);
        exit(Payload);
    end;

    procedure BuildTrace(SearchText: Text): JsonObject
    var
        LP: Record "DOPSWHS LP Header";
        Item: Record Item;
        Trace: JsonObject;
        Tokens: List of [Text];
        Search: Text;
        Handled: Boolean;
    begin
        ResetState();
        Search := UpperCase(DelChr(SearchText, '<>', ' '));
        Trace.Add('version', 1);
        Trace.Add('query', Search);
        Trace.Add('generatedAt', FormatDateTime(CurrentDateTime()));
        if Search = '' then begin
            Trace.Add('mode', 'empty');
            Handled := true;
        end;
        if not Handled then
            if FindLp(Search, LP) then begin
                AddLpTrace(Trace, LP);
                Handled := true;
            end;
        if not Handled then
            if Search.Contains(' ') then begin
                // "MADDE LOT" (Madde Defteri Girişleri eyleminden gelir).
                Tokens := Search.Split(' ');
                if Tokens.Count() >= 2 then
                    if (StrLen(Tokens.Get(1)) <= MaxStrLen(Item."No.")) and (StrLen(Tokens.Get(Tokens.Count())) <= 50) then
                        if Item.Get(CopyStr(Tokens.Get(1), 1, MaxStrLen(Item."No."))) then begin
                            AddLotTree(Trace, CopyStr(Tokens.Get(Tokens.Count()), 1, 50), Item."No.");
                            Handled := true;
                        end;
            end;
        if not Handled then
            if StrLen(Search) <= MaxStrLen(Item."No.") then
                if Item.Get(CopyStr(Search, 1, MaxStrLen(Item."No."))) then begin
                    AddItemTree(Trace, Item."No.");
                    Handled := true;
                end;
        if not Handled then
            if IsKnownLot(Search) then begin
                AddLotTree(Trace, CopyStr(Search, 1, 50), '');
                Handled := true;
            end;
        if not Handled then
            Handled := AddDocumentTree(Trace, Search);
        if not Handled then
            Trace.Add('mode', 'notFound');
        Trace.Add('documents', SortedDocuments());
        Trace.Add('insights', Insights);
        Trace.Add('truncated', Truncated);
        exit(Trace);
    end;

    /// <summary>Opens the BC page behind a clicked node of the trace screen.</summary>
    procedure OpenNode(Kind: Text; NodeKey: Text)
    var
        LP: Record "DOPSWHS LP Header";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WarehouseEntry: Record "Warehouse Entry";
        Item: Record Item;
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        ProductionOrder: Record "Production Order";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
        DocNo: Code[20];
        EntryNo: Integer;
    begin
        NodeKey := DelChr(NodeKey, '<>', ' ');
        if NodeKey = '' then
            exit;
        DocNo := CopyStr(NodeKey, 1, MaxStrLen(DocNo));
        case Kind of
            'lp':
                if LP.Get(DocNo) then begin
                    LP.SetRecFilter();
                    Page.Run(Page::"DOPSWHS LP Card", LP);
                    exit;
                end;
            'lpLedger':
                begin
                    Ledger.SetRange("LP No.", DocNo);
                    Page.Run(Page::"DOPSWHS LP Movement Ledger", Ledger);
                    exit;
                end;
            'ile':
                if Evaluate(EntryNo, NodeKey) then begin
                    ItemLedgerEntry.SetRange("Entry No.", EntryNo);
                    Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
                    exit;
                end;
            'whseEntry':
                if Evaluate(EntryNo, NodeKey) then begin
                    WarehouseEntry.SetRange("Entry No.", EntryNo);
                    Page.Run(Page::"Warehouse Entries", WarehouseEntry);
                    exit;
                end;
            'item':
                if Item.Get(DocNo) then begin
                    Item.SetRecFilter();
                    Page.Run(Page::"Item Card", Item);
                    exit;
                end;
            'whseReceipt':
                if WhseReceiptHeader.Get(DocNo) then begin
                    WhseReceiptHeader.SetRecFilter();
                    Page.Run(Page::"Warehouse Receipt", WhseReceiptHeader);
                    exit;
                end;
            'postedWhseReceipt':
                if PostedWhseReceiptHeader.Get(DocNo) then begin
                    PostedWhseReceiptHeader.SetRecFilter();
                    Page.Run(Page::"Posted Whse. Receipt", PostedWhseReceiptHeader);
                    exit;
                end;
            'purchRcpt':
                if PurchRcptHeader.Get(DocNo) then begin
                    PurchRcptHeader.SetRecFilter();
                    Page.Run(Page::"Posted Purchase Receipt", PurchRcptHeader);
                    exit;
                end;
            'purchaseOrder':
                if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo) then begin
                    PurchaseHeader.SetRecFilter();
                    Page.Run(Page::"Purchase Order", PurchaseHeader);
                    exit;
                end;
            'whsePutaway':
                if ActivityHeader.Get(ActivityHeader.Type::"Put-away", DocNo) then begin
                    ActivityHeader.SetRecFilter();
                    Page.Run(Page::"Warehouse Put-away", ActivityHeader);
                    exit;
                end;
            'whsePick':
                if ActivityHeader.Get(ActivityHeader.Type::Pick, DocNo) then begin
                    ActivityHeader.SetRecFilter();
                    Page.Run(Page::"Warehouse Pick", ActivityHeader);
                    exit;
                end;
            'whseMovement':
                if ActivityHeader.Get(ActivityHeader.Type::Movement, DocNo) then begin
                    ActivityHeader.SetRecFilter();
                    Page.Run(Page::"Warehouse Movement", ActivityHeader);
                    exit;
                end;
            'regPutaway':
                if RegisteredHeader.Get(RegisteredHeader.Type::"Put-away", DocNo) then begin
                    RegisteredHeader.SetRecFilter();
                    Page.Run(Page::"Registered Put-away", RegisteredHeader);
                    exit;
                end;
            'regPick':
                if RegisteredHeader.Get(RegisteredHeader.Type::Pick, DocNo) then begin
                    RegisteredHeader.SetRecFilter();
                    Page.Run(Page::"Registered Pick", RegisteredHeader);
                    exit;
                end;
            'regMovement':
                if RegisteredHeader.Get(RegisteredHeader.Type::Movement, DocNo) then begin
                    RegisteredHeader.SetRecFilter();
                    Page.Run(Page::"Registered Movement", RegisteredHeader);
                    exit;
                end;
            'whseShipment':
                if WhseShipmentHeader.Get(DocNo) then begin
                    WhseShipmentHeader.SetRecFilter();
                    Page.Run(Page::"Warehouse Shipment", WhseShipmentHeader);
                    exit;
                end;
            'postedWhseShipment':
                if PostedWhseShipmentHeader.Get(DocNo) then begin
                    PostedWhseShipmentHeader.SetRecFilter();
                    Page.Run(Page::"Posted Whse. Shipment", PostedWhseShipmentHeader);
                    exit;
                end;
            'salesShipment':
                if SalesShipmentHeader.Get(DocNo) then begin
                    SalesShipmentHeader.SetRecFilter();
                    Page.Run(Page::"Posted Sales Shipment", SalesShipmentHeader);
                    exit;
                end;
            'prodOrder':
                begin
                    ProductionOrder.SetRange("No.", DocNo);
                    if ProductionOrder.FindFirst() then begin
                        ProductionOrder.SetRecFilter();
                        case ProductionOrder.Status of
                            ProductionOrder.Status::Released:
                                Page.Run(Page::"Released Production Order", ProductionOrder);
                            ProductionOrder.Status::Finished:
                                Page.Run(Page::"Finished Production Order", ProductionOrder);
                            ProductionOrder.Status::"Firm Planned":
                                Page.Run(Page::"Firm Planned Prod. Order", ProductionOrder);
                            ProductionOrder.Status::Planned:
                                Page.Run(Page::"Planned Production Order", ProductionOrder);
                            else
                                Page.Run(Page::"Production Order List", ProductionOrder);
                        end;
                        exit;
                    end;
                end;
            'assemblyOrder':
                if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then begin
                    AssemblyHeader.SetRecFilter();
                    Page.Run(Page::"Assembly Order", AssemblyHeader);
                    exit;
                end;
            'postedAssembly':
                if PostedAssemblyHeader.Get(DocNo) then begin
                    PostedAssemblyHeader.SetRecFilter();
                    Page.Run(Page::"Posted Assembly Order", PostedAssemblyHeader);
                    exit;
                end;
        end;
        Message(NodeNotFoundMsg, NodeKey);
    end;

    // ───────────────────────────── LP modu ─────────────────────────────

    local procedure AddLpTrace(var Trace: JsonObject; var LP: Record "DOPSWHS LP Header")
    var
        TempEntry: Record "Item Ledger Entry" temporary;
        Items: List of [Text];
        SourceEntries: List of [Integer];
        UndoEntries: List of [Integer];
        LpQtyBySource: Dictionary of [Integer, Decimal];
        UndoneBy: Dictionary of [Integer, Integer];
        Lines: JsonArray;
        Groups: JsonArray;
        Header: JsonObject;
    begin
        Trace.Add('mode', 'lp');
        Header := LpHeaderJson(LP);
        BuildLpLines(LP, Lines, Groups, Items, SourceEntries, LpQtyBySource);
        Trace.Add('lines', Lines);
        Trace.Add('sourceGroups', Groups);
        Trace.Add('mixedSources', Groups.Count() > 1);
        Trace.Add('timeline', BuildTimeline(LP, Items, UndoEntries));
        Trace.Add('itemLedger', BuildLpItemLedger(LP, Items, SourceEntries, UndoEntries, LpQtyBySource, TempEntry, UndoneBy));
        Trace.Add('warehouseEntries', BuildLpWarehouseEntries(LP, Items));
        AddLpActivityDocuments(LP, Items);
        AddLpInsights(LP, Header, Groups, SourceEntries, UndoEntries, LpQtyBySource, TempEntry, UndoneBy);
        Trace.Add('lp', Header);
    end;

    local procedure LpHeaderJson(var LP: Record "DOPSWHS LP Header") Header: JsonObject
    var
        Parent: Record "DOPSWHS LP Header";
        Child: Record "DOPSWHS LP Header";
        Assigned: JsonObject;
        ParentJson: JsonObject;
        ChildJson: JsonObject;
        Children: JsonArray;
        NavKind: Text;
        NavKey: Text;
        State: Text;
        ChildCount: Integer;
    begin
        LP.CalcFields("Total Quantity", "Line Count", "Weight kg");
        Header.Add('no', LP."No.");
        Header.Add('status', StatusKey(LP.Status));
        Header.Add('statusCaption', Format(LP.Status));
        Header.Add('locationCode', LP."Location Code");
        Header.Add('binCode', LP."Bin Code");
        Header.Add('templateCode', LP."LP Template Code");
        Header.Add('sscc', LP.SSCC);
        Header.Add('totalQty', LP."Total Quantity");
        Header.Add('lineCount', LP."Line Count");
        Header.Add('plannedQty', LP."Planned Quantity");
        Header.Add('weightKg', LP."Weight kg");
        Header.Add('builtBy', LP."Built By User");
        Header.Add('builtAt', FormatDateTime(LP."Built DateTime"));
        Header.Add('lastModifiedAt', FormatDateTime(LP."Last Modified DateTime"));
        Header.Add('pendingReceiptNo', LP."Pending Receipt No.");
        Header.Add('notes', LP.Notes);

        if (LP."Assigned Document No." <> '') or (LP."Assigned Document Type" <> LP."Assigned Document Type"::None) then begin
            State := ResolveTypedDocument(LP."Assigned Document Type", LP."Assigned Document No.", 'assigned', NavKind, NavKey);
            Assigned.Add('type', DocTypeKey(LP."Assigned Document Type"));
            Assigned.Add('typeCaption', DocTypeCaption(LP."Assigned Document Type"));
            Assigned.Add('no', LP."Assigned Document No.");
            Assigned.Add('state', State);
            Assigned.Add('exists', State <> 'missing');
            AddNav(Assigned, NavKind, NavKey);
            Header.Add('assigned', Assigned);
        end else
            Header.Add('assigned', NullValue());
        Header.Add('orphan', LPMgt.IsAssignmentOrphaned(LP));

        if (LP."Parent LP No." <> '') and Parent.Get(LP."Parent LP No.") then begin
            ParentJson.Add('no', Parent."No.");
            ParentJson.Add('status', StatusKey(Parent.Status));
            ParentJson.Add('binCode', Parent."Bin Code");
            Header.Add('parent', ParentJson);
        end else
            Header.Add('parent', NullValue());

        Child.SetCurrentKey("Parent LP No.");
        Child.SetRange("Parent LP No.", LP."No.");
        if Child.FindSet() then
            repeat
                ChildCount += 1;
                if ChildCount > MaxChildren() then
                    MarkTruncated('children')
                else begin
                    Child.CalcFields("Total Quantity");
                    Clear(ChildJson);
                    ChildJson.Add('no', Child."No.");
                    ChildJson.Add('status', StatusKey(Child.Status));
                    ChildJson.Add('binCode', Child."Bin Code");
                    ChildJson.Add('totalQty', Child."Total Quantity");
                    Children.Add(ChildJson);
                end;
            until (Child.Next() = 0) or (ChildCount > MaxChildren());
        Header.Add('children', Children);
    end;

    local procedure BuildLpLines(var LP: Record "DOPSWHS LP Header"; var Lines: JsonArray; var Groups: JsonArray; var Items: List of [Text]; var SourceEntries: List of [Integer]; var LpQtyBySource: Dictionary of [Integer, Decimal])
    var
        LPLine: Record "DOPSWHS LP Line";
        SourceLP: Record "DOPSWHS LP Header";
        Line: JsonObject;
        Group: JsonObject;
        GroupKeys: List of [Text];
        GroupQty: Dictionary of [Text, Decimal];
        GroupLineCount: Dictionary of [Text, Integer];
        GroupLine: Dictionary of [Text, Integer];
        GroupKey: Text;
        NavKind: Text;
        NavKey: Text;
        DocState: Text;
        Qty: Decimal;
        BaseQty: Decimal;
        Counter: Integer;
        LineNo: Integer;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        if LPLine.FindSet() then
            repeat
                GroupKey := SourceGroupKey(LPLine);
                BaseQty := LineBaseQty(LPLine);
                Clear(Line);
                Line.Add('lineNo', LPLine."Line No.");
                Line.Add('itemNo', LPLine."Item No.");
                Line.Add('itemDescription', ItemDescription(LPLine."Item No."));
                Line.Add('variantCode', LPLine."Variant Code");
                Line.Add('lotNo', LPLine."Lot No.");
                Line.Add('serialNo', LPLine."Serial No.");
                Line.Add('packageNo', LPLine."Package No.");
                Line.Add('qty', LPLine.Quantity);
                Line.Add('baseQty', BaseQty);
                Line.Add('uom', LPLine."Unit of Measure");
                Line.Add('expirationDate', FormatDate(LPLine."Expiration Date"));
                Line.Add('sourceBin', LPLine."Source Bin Code");
                Line.Add('sourceDocType', DocTypeKey(LPLine."Source Document Type"));
                Line.Add('sourceDocTypeCaption', DocTypeCaption(LPLine."Source Document Type"));
                Line.Add('sourceDocNo', LPLine."Source Document No.");
                Line.Add('sourceDocLineNo', LPLine."Source Document Line No.");
                Line.Add('sourceDocQty', LPLine."Source Document Quantity");
                Line.Add('sourceIleNo', LPLine."Source Item Ledger Entry No.");
                Line.Add('sourceLpNo', LPLine."Source LP No.");
                Line.Add('childLpNo', LPLine."Child LP No.");
                Line.Add('groupKey', GroupKey);
                if LPLine."Source Document No." <> '' then begin
                    DocState := ResolveTypedDocument(LPLine."Source Document Type", LPLine."Source Document No.", 'source', NavKind, NavKey);
                    Line.Add('sourceDocState', DocState);
                    AddNav(Line, NavKind, NavKey);
                end else begin
                    Line.Add('sourceDocState', 'none');
                    Line.Add('nav', NullValue());
                end;
                Lines.Add(Line);

                if (LPLine."Item No." <> '') and not Items.Contains(LPLine."Item No.") then
                    Items.Add(LPLine."Item No.");
                if LPLine."Source Item Ledger Entry No." <> 0 then begin
                    if not SourceEntries.Contains(LPLine."Source Item Ledger Entry No.") then
                        SourceEntries.Add(LPLine."Source Item Ledger Entry No.");
                    if not LpQtyBySource.Get(LPLine."Source Item Ledger Entry No.", Qty) then
                        Qty := 0;
                    LpQtyBySource.Set(LPLine."Source Item Ledger Entry No.", Qty + BaseQty);
                end;

                if not GroupKeys.Contains(GroupKey) then begin
                    GroupKeys.Add(GroupKey);
                    GroupLine.Set(GroupKey, LPLine."Line No.");
                end;
                if not GroupQty.Get(GroupKey, Qty) then
                    Qty := 0;
                GroupQty.Set(GroupKey, Qty + BaseQty);
                if not GroupLineCount.Get(GroupKey, Counter) then
                    Counter := 0;
                GroupLineCount.Set(GroupKey, Counter + 1);
            until LPLine.Next() = 0;

        foreach GroupKey in GroupKeys do begin
            LineNo := GroupLine.Get(GroupKey);
            LPLine.Get(LP."No.", LineNo);
            Clear(Group);
            Group.Add('key', GroupKey);
            Group.Add('kind', GroupKey.Split(':').Get(1));
            Group.Add('label', SourceGroupLabel(LPLine));
            Group.Add('sourceLpNo', LPLine."Source LP No.");
            if (LPLine."Source LP No." <> '') and SourceLP.Get(LPLine."Source LP No.") then
                Group.Add('sourceLpStatus', StatusKey(SourceLP.Status))
            else
                Group.Add('sourceLpStatus', '');
            Group.Add('sourceDocType', DocTypeKey(LPLine."Source Document Type"));
            Group.Add('sourceDocNo', LPLine."Source Document No.");
            Group.Add('sourceIleNo', LPLine."Source Item Ledger Entry No.");
            Group.Add('qty', GroupQty.Get(GroupKey));
            Group.Add('lineCount', GroupLineCount.Get(GroupKey));
            Groups.Add(Group);
        end;
    end;

    local procedure BuildTimeline(var LP: Record "DOPSWHS LP Header"; var Items: List of [Text]; var UndoEntries: List of [Integer]) Timeline: JsonArray
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Entry: JsonObject;
        MissingDocNo: Text;
        Total: Integer;
    begin
        Ledger.SetCurrentKey("LP No.", DateTime);
        Ledger.SetRange("LP No.", LP."No.");
        Total := Ledger.Count();
        if not Ledger.FindSet() then
            exit;
        if Total > MaxTimelineRows() then begin
            // En yeni MaxTimelineRows kayıt gösterilir; eskiler LP Hareket Defterinde.
            Ledger.Next(Total - MaxTimelineRows());
            MarkTruncated('timeline');
        end;
        repeat
            Clear(Entry);
            Entry.Add('entryNo', Ledger."Entry No.");
            Entry.Add('action', ActionKey(Ledger.Action));
            Entry.Add('actionCaption', Format(Ledger.Action));
            Entry.Add('at', FormatDateTime(Ledger.DateTime));
            Entry.Add('user', Ledger."User ID");
            Entry.Add('device', Ledger."Device ID");
            Entry.Add('fromBin', Ledger."From Bin");
            Entry.Add('toBin', Ledger."To Bin");
            Entry.Add('qty', Ledger.Quantity);
            Entry.Add('itemNo', Ledger."Item No.");
            Entry.Add('lotSerial', Ledger."Lot Serial");
            Entry.Add('relatedDocument', Ledger."Related Document");
            Entry.Add('sourceLpNo', Ledger."Source LP No.");
            Entry.Add('targetLpNo', Ledger."Target LP No.");
            AddTimelineLink(Entry, Ledger, LP."No.", UndoEntries, MissingDocNo);
            Entry.Add('missingDocNo', MissingDocNo);
            Timeline.Add(Entry);
            if (Ledger."Item No." <> '') and not Items.Contains(Ledger."Item No.") then
                Items.Add(Ledger."Item No.");
        until Ledger.Next() = 0;
    end;

    local procedure AddTimelineLink(var Entry: JsonObject; var Ledger: Record "DOPSWHS LP Movement Ledger"; CurrentLpNo: Code[20]; var UndoEntries: List of [Integer]; var MissingDocNo: Text)
    var
        OtherLP: Record "DOPSWHS LP Header";
        Link: JsonObject;
        Parts: List of [Text];
        Ref: Text;
        Candidate: Text;
        NavKind: Text;
        NavKey: Text;
        EntryNo: Integer;
    begin
        MissingDocNo := '';
        Ref := Ledger."Related Document";
        if Ref.StartsWith('UNDO-RCPT:') then begin
            Parts := Ref.Split(':');
            if Parts.Count() >= 2 then
                if Evaluate(EntryNo, Parts.Get(2)) then begin
                    if not UndoEntries.Contains(EntryNo) then
                        UndoEntries.Add(EntryNo);
                    Link.Add('kind', 'ile');
                    Link.Add('key', Format(EntryNo, 0, 9));
                    Link.Add('label', 'Geri alma girişi ' + Format(EntryNo, 0, 9));
                    Entry.Add('link', Link);
                    Entry.Add('undo', true);
                    exit;
                end;
        end;
        Entry.Add('undo', false);
        if (Ledger."Source LP No." <> '') and (Ledger."Source LP No." <> CurrentLpNo) then begin
            AddLpLink(Entry, Ledger."Source LP No.", 'Kaynak LP ');
            exit;
        end;
        if (Ledger."Target LP No." <> '') and (Ledger."Target LP No." <> CurrentLpNo) then begin
            AddLpLink(Entry, Ledger."Target LP No.", 'Hedef LP ');
            exit;
        end;
        if not IsResolvableReference(Ref) then begin
            Entry.Add('link', NullValue());
            exit;
        end;
        Candidate := ExtractDocumentNo(Ref);
        if ResolveDocumentNo(Candidate, 'ledger', NavKind, NavKey) then begin
            Link.Add('kind', NavKind);
            Link.Add('key', NavKey);
            Link.Add('label', KindCaption(NavKind) + ' ' + NavKey);
            Entry.Add('link', Link);
            exit;
        end;
        if (StrLen(Candidate) <= MaxStrLen(OtherLP."No.")) and (Candidate <> CurrentLpNo) then
            if OtherLP.Get(CopyStr(Candidate, 1, MaxStrLen(OtherLP."No."))) then begin
                AddLpLink(Entry, OtherLP."No.", 'LP ');
                exit;
            end;
        // Çözülemeyen (silinmiş) belge: ekranda "bulunamadı" diye gösterilir.
        if Ledger.Action in [Ledger.Action::Assigned, Ledger.Action::Released, Ledger.Action::Moved] then
            MissingDocNo := Candidate;
        Entry.Add('link', NullValue());
    end;

    local procedure AddLpLink(var Entry: JsonObject; LpNo: Code[20]; LabelPrefix: Text)
    var
        Link: JsonObject;
    begin
        Link.Add('kind', 'lp');
        Link.Add('key', LpNo);
        Link.Add('label', LabelPrefix + LpNo);
        Entry.Add('link', Link);
    end;

    local procedure BuildLpItemLedger(var LP: Record "DOPSWHS LP Header"; var Items: List of [Text]; var SourceEntries: List of [Integer]; var UndoEntries: List of [Integer]; var LpQtyBySource: Dictionary of [Integer, Decimal]; var TempEntry: Record "Item Ledger Entry" temporary; var UndoneBy: Dictionary of [Integer, Integer]) Result: JsonArray
    var
        Entry: Record "Item Ledger Entry";
        MatchedBy: Dictionary of [Integer, Text];
        Collected: List of [Integer];
        UndoNos: List of [Integer];
        ItemNo: Text;
        How: Text;
        EntryNo: Integer;
        UndoNo: Integer;
        OriginalNo: Integer;
        ThisLpQty: Decimal;
    begin
        foreach EntryNo in SourceEntries do
            if Entry.Get(EntryNo) then
                CollectEntry(Entry, 'sourceLine', TempEntry, MatchedBy);
        foreach EntryNo in UndoEntries do
            if Entry.Get(EntryNo) then
                CollectEntry(Entry, 'undo', TempEntry, MatchedBy);
        foreach ItemNo in Items do begin
            Entry.Reset();
            Entry.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(Entry."Item No.")));
            Entry.SetRange("DOPSWHS LP No.", LP."No.");
            if Entry.FindSet() then
                repeat
                    CollectEntry(Entry, 'lpNo', TempEntry, MatchedBy);
                until (Entry.Next() = 0) or (TempEntry.Count() >= MaxEntries());
            Entry.SetRange("DOPSWHS LP No.");
            Entry.SetFilter("DOPSWHS LP Nos.", '*' + LP."No." + '*');
            if Entry.FindSet() then
                repeat
                    if ListContainsLp(Entry."DOPSWHS LP Nos.", LP."No.") then
                        CollectEntry(Entry, 'lpNos', TempEntry, MatchedBy);
                until (Entry.Next() = 0) or (TempEntry.Count() >= MaxEntries());
        end;

        // Geri alma eşleri: mal kabul girişi <-> düzeltme (geri alma) girişi.
        if TempEntry.FindSet() then
            repeat
                Collected.Add(TempEntry."Entry No.");
            until TempEntry.Next() = 0;
        foreach EntryNo in Collected do begin
            TempEntry.Get(EntryNo);
            if TempEntry.Correction and (TempEntry.Quantity < 0) then begin
                OriginalNo := FindUndoOriginal(TempEntry);
                if OriginalNo <> 0 then begin
                    UndoneBy.Set(OriginalNo, EntryNo);
                    if Entry.Get(OriginalNo) then
                        CollectEntry(Entry, 'undone', TempEntry, MatchedBy);
                end;
            end else begin
                Clear(UndoNos);
                LPMgt.CollectUndoneReceiptEntries(EntryNo, UndoNos);
                foreach UndoNo in UndoNos do
                    if UndoNo <> EntryNo then begin
                        UndoneBy.Set(EntryNo, UndoNo);
                        if Entry.Get(UndoNo) then
                            CollectEntry(Entry, 'undo', TempEntry, MatchedBy);
                    end;
            end;
        end;

        TempEntry.Reset();
        if TempEntry.FindSet() then
            repeat
                if not MatchedBy.Get(TempEntry."Entry No.", How) then
                    How := '';
                if not LpQtyBySource.Get(TempEntry."Entry No.", ThisLpQty) then
                    ThisLpQty := 0;
                if not UndoneBy.Get(TempEntry."Entry No.", UndoNo) then
                    UndoNo := 0;
                Result.Add(EntryJson(TempEntry, How, UndoNo, ThisLpQty));
                AddLedgerDocuments(TempEntry);
            until TempEntry.Next() = 0;
    end;

    local procedure CollectEntry(var Entry: Record "Item Ledger Entry"; How: Text; var TempEntry: Record "Item Ledger Entry" temporary; var MatchedBy: Dictionary of [Integer, Text])
    begin
        if TempEntry.Get(Entry."Entry No.") then
            exit;
        if TempEntry.Count() >= MaxEntries() then begin
            MarkTruncated('itemLedger');
            exit;
        end;
        TempEntry := Entry;
        TempEntry.Insert(false);
        MatchedBy.Set(Entry."Entry No.", How);
    end;

    local procedure EntryJson(var Entry: Record "Item Ledger Entry"; How: Text; UndoneByEntryNo: Integer; ThisLpQty: Decimal) Result: JsonObject
    begin
        Result.Add('entryNo', Entry."Entry No.");
        Result.Add('postingDate', FormatDate(Entry."Posting Date"));
        Result.Add('entryType', Format(Entry."Entry Type"));
        Result.Add('documentType', Format(Entry."Document Type"));
        Result.Add('documentNo', Entry."Document No.");
        Result.Add('documentLineNo', Entry."Document Line No.");
        Result.Add('orderNo', Entry."Order No.");
        Result.Add('itemNo', Entry."Item No.");
        Result.Add('variantCode', Entry."Variant Code");
        Result.Add('lotNo', Entry."Lot No.");
        Result.Add('serialNo', Entry."Serial No.");
        Result.Add('locationCode', Entry."Location Code");
        Result.Add('qty', Entry.Quantity);
        Result.Add('remainingQty', Entry."Remaining Quantity");
        Result.Add('open', Entry.Open);
        Result.Add('positive', Entry.Positive);
        Result.Add('correction', Entry.Correction);
        Result.Add('appliesToEntry', Entry."Applies-to Entry");
        Result.Add('lpNo', Entry."DOPSWHS LP No.");
        Result.Add('lpNos', Entry."DOPSWHS LP Nos.");
        Result.Add('matchedBy', How);
        Result.Add('undoneByEntryNo', UndoneByEntryNo);
        Result.Add('thisLpQty', ThisLpQty);
        Result.Add('linkedLpQty', LinkedLpBaseQty(Entry."Entry No."));
    end;

    local procedure AddLedgerDocuments(var Entry: Record "Item Ledger Entry")
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        NavKind: Text;
        NavKey: Text;
    begin
        case Entry."Document Type" of
            Entry."Document Type"::"Purchase Receipt":
                if PurchRcptHeader.Get(Entry."Document No.") then
                    ResolveDocumentNo(Entry."Document No.", 'ledger', NavKind, NavKey)
                else
                    AddDocument('purchRcpt', Entry."Document No.", 'missing', 'ledger', 'Alış irsaliyesi bulunamadı', '', '');
            Entry."Document Type"::"Sales Shipment":
                if SalesShipmentHeader.Get(Entry."Document No.") then
                    ResolveDocumentNo(Entry."Document No.", 'ledger', NavKind, NavKey);
        end;
        if (Entry."Order Type" = Entry."Order Type"::Production) and (Entry."Order No." <> '') then
            if not ResolveDocumentNo(Entry."Order No.", 'ledger', NavKind, NavKey) then
                AddDocument('prodOrder', Entry."Order No.", 'missing', 'ledger', 'Üretim emri bulunamadı', '', '');
    end;

    local procedure FindUndoOriginal(var UndoEntry: Record "Item Ledger Entry"): Integer
    var
        Original: Record "Item Ledger Entry";
    begin
        if UndoEntry."Applies-to Entry" <> 0 then
            exit(UndoEntry."Applies-to Entry");
        Original.SetRange("Document No.", UndoEntry."Document No.");
        Original.SetRange("Item No.", UndoEntry."Item No.");
        Original.SetRange("Variant Code", UndoEntry."Variant Code");
        Original.SetRange("Lot No.", UndoEntry."Lot No.");
        Original.SetRange("Serial No.", UndoEntry."Serial No.");
        Original.SetRange(Correction, false);
        Original.SetRange(Quantity, -UndoEntry.Quantity);
        Original.SetFilter("Entry No.", '<%1', UndoEntry."Entry No.");
        if Original.FindLast() then
            exit(Original."Entry No.");
        exit(0);
    end;

    local procedure BuildLpWarehouseEntries(var LP: Record "DOPSWHS LP Header"; var Items: List of [Text]) Result: JsonArray
    var
        WarehouseEntry: Record "Warehouse Entry";
        TempWarehouseEntry: Record "Warehouse Entry" temporary;
        Row: JsonObject;
        DocNos: List of [Text];
        ItemNo: Text;
        DocNo: Text;
        NavKind: Text;
        NavKey: Text;
    begin
        foreach ItemNo in Items do begin
            WarehouseEntry.Reset();
            WarehouseEntry.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(WarehouseEntry."Item No.")));
            WarehouseEntry.SetRange("DOPSWHS LP No.", LP."No.");
            if WarehouseEntry.FindSet() then
                repeat
                    if TempWarehouseEntry.Count() >= MaxEntries() then
                        MarkTruncated('warehouseEntries')
                    else begin
                        TempWarehouseEntry := WarehouseEntry;
                        if TempWarehouseEntry.Insert(false) then;
                    end;
                until (WarehouseEntry.Next() = 0) or (TempWarehouseEntry.Count() >= MaxEntries());
        end;
        if TempWarehouseEntry.FindSet() then
            repeat
                Clear(Row);
                Row.Add('entryNo', TempWarehouseEntry."Entry No.");
                Row.Add('registeringDate', FormatDate(TempWarehouseEntry."Registering Date"));
                Row.Add('entryType', Format(TempWarehouseEntry."Entry Type"));
                Row.Add('locationCode', TempWarehouseEntry."Location Code");
                Row.Add('zoneCode', TempWarehouseEntry."Zone Code");
                Row.Add('binCode', TempWarehouseEntry."Bin Code");
                Row.Add('itemNo', TempWarehouseEntry."Item No.");
                Row.Add('lotNo', TempWarehouseEntry."Lot No.");
                Row.Add('qty', TempWarehouseEntry.Quantity);
                Row.Add('qtyBase', TempWarehouseEntry."Qty. (Base)");
                Row.Add('uom', TempWarehouseEntry."Unit of Measure Code");
                Row.Add('sourceDocument', Format(TempWarehouseEntry."Source Document"));
                Row.Add('sourceNo', TempWarehouseEntry."Source No.");
                Row.Add('whseDocumentType', Format(TempWarehouseEntry."Whse. Document Type"));
                Row.Add('whseDocumentNo', TempWarehouseEntry."Whse. Document No.");
                Row.Add('referenceDocument', Format(TempWarehouseEntry."Reference Document"));
                Row.Add('referenceNo', TempWarehouseEntry."Reference No.");
                Row.Add('userId', TempWarehouseEntry."User ID");
                Result.Add(Row);
                if (TempWarehouseEntry."Whse. Document No." <> '') and not DocNos.Contains(TempWarehouseEntry."Whse. Document No.") then
                    DocNos.Add(TempWarehouseEntry."Whse. Document No.");
                if (TempWarehouseEntry."Reference No." <> '') and not DocNos.Contains(TempWarehouseEntry."Reference No.") then
                    DocNos.Add(TempWarehouseEntry."Reference No.");
            until TempWarehouseEntry.Next() = 0;
        foreach DocNo in DocNos do
            if DocNos.IndexOf(DocNo) <= MaxResolvedDocs() then
                ResolveDocumentNo(DocNo, 'warehouse', NavKind, NavKey);
    end;

    local procedure AddLpActivityDocuments(var LP: Record "DOPSWHS LP Header"; var Items: List of [Text])
    var
        ActivityLine: Record "Warehouse Activity Line";
        RegisteredLine: Record "Registered Whse. Activity Line";
        ItemNo: Text;
        Scanned: Integer;
    begin
        foreach ItemNo in Items do begin
            ActivityLine.Reset();
            ActivityLine.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(ActivityLine."Item No.")));
            ActivityLine.SetRange("LP No.", LP."No.");
            Scanned := 0;
            if ActivityLine.FindSet() then
                repeat
                    Scanned += 1;
                    AddActivityDocument(ActivityLine."Activity Type", ActivityLine."No.", false);
                until (ActivityLine.Next() = 0) or (Scanned >= MaxActivityLines());

            RegisteredLine.Reset();
            RegisteredLine.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(RegisteredLine."Item No.")));
            RegisteredLine.SetRange("LP No.", LP."No.");
            Scanned := 0;
            if RegisteredLine.FindSet() then
                repeat
                    Scanned += 1;
                    AddActivityDocument(RegisteredLine."Activity Type", RegisteredLine."No.", true);
                until (RegisteredLine.Next() = 0) or (Scanned >= MaxActivityLines());
        end;
    end;

    local procedure AddActivityDocument(ActivityType: Enum "Warehouse Activity Type"; DocNo: Code[20]; Registered: Boolean)
    var
        Kind: Text;
    begin
        case ActivityType of
            ActivityType::"Put-away":
                Kind := 'Putaway';
            ActivityType::Pick:
                Kind := 'Pick';
            ActivityType::Movement:
                Kind := 'Movement';
            else
                exit;
        end;
        if Registered then begin
            Kind := 'reg' + Kind;
            AddDocument(Kind, DocNo, 'posted', 'activity', '', Kind, DocNo);
        end else begin
            Kind := 'whse' + Kind;
            AddDocument(Kind, DocNo, 'open', 'activity', '', Kind, DocNo);
        end;
    end;

    local procedure AddLpInsights(var LP: Record "DOPSWHS LP Header"; var Header: JsonObject; var Groups: JsonArray; var SourceEntries: List of [Integer]; var UndoEntries: List of [Integer]; var LpQtyBySource: Dictionary of [Integer, Decimal]; var TempEntry: Record "Item Ledger Entry" temporary; var UndoneBy: Dictionary of [Integer, Integer])
    var
        LPLine: Record "DOPSWHS LP Line";
        Token: JsonToken;
        Group: JsonObject;
        Labels: Text;
        State: Text;
        EntryNo: Integer;
        UndoNo: Integer;
        ThisLpQty: Decimal;
        LinkedQty: Decimal;
    begin
        if LPMgt.IsAssignmentOrphaned(LP) then
            AddInsight('error', 'orphanAssignment',
                StrSubstNo('LP, artık bulunmayan %1 %2 belgesine atanmış (yetim).',
                    DocTypeCaption(LP."Assigned Document Type"), LP."Assigned Document No."), 'lp', LP."No.")
        else
            if LP."Assigned Document No." <> '' then
                if Header.Get('assigned', Token) then
                    if Token.IsObject() then begin
                        State := GetText(Token.AsObject(), 'state');
                        if State = 'missing' then
                            AddInsight('warning', 'assignedDocMissing',
                                StrSubstNo('Atandığı %1 %2 belgesi artık bulunmuyor.', DocTypeCaption(LP."Assigned Document Type"), LP."Assigned Document No."), '', '');
                    end;

        if Groups.Count() > 1 then begin
            foreach Token in Groups do begin
                Group := Token.AsObject();
                if Labels <> '' then
                    Labels += ' + ';
                Labels += StrSubstNo('%1 (%2)', GetText(Group, 'label'), Format(GetDecimal(Group, 'qty')));
            end;
            AddInsight('info', 'mixedSources', StrSubstNo('LP içeriği %1 farklı kaynaktan geliyor: %2.', Groups.Count(), Labels), '', '');
        end;

        foreach EntryNo in SourceEntries do
            if TempEntry.Get(EntryNo) then begin
                if not LpQtyBySource.Get(EntryNo, ThisLpQty) then
                    ThisLpQty := 0;
                if UndoneBy.Get(EntryNo, UndoNo) and (ThisLpQty > 0) then
                    AddInsight('error', 'sourceUndoneLpFull',
                        StrSubstNo('Kaynak madde girişi %1 (%2) geri alınmış (düzeltme %3) ama bu LP''de hâlâ %4 bağlı miktar var.',
                            Format(EntryNo, 0, 9), TempEntry."Document No.", Format(UndoNo, 0, 9), Format(ThisLpQty)), 'ile', Format(UndoNo, 0, 9))
                else begin
                    LinkedQty := LinkedLpBaseQty(EntryNo);
                    if TempEntry.Positive and (LinkedQty > TempEntry."Remaining Quantity") then
                        AddInsight('warning', 'lpExceedsEntryRemaining',
                            StrSubstNo('Kaynak madde girişi %1 kalan miktarı (%2), bu girişe bağlı tüm LP''lerin toplamından (%3) az.',
                                Format(EntryNo, 0, 9), Format(TempEntry."Remaining Quantity"), Format(LinkedQty)), 'ile', Format(EntryNo, 0, 9));
                end;
            end;

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetRange("Source Item Ledger Entry No.", 0);
        if not LPLine.IsEmpty() then
            AddInsight('warning', 'missingSourceEntry',
                StrSubstNo('%1 satırın kaynak madde girişi bağlı değil (LP kartı > Kaynak Girişi Bağla).', LPLine.Count()), 'lp', LP."No.");

        if UndoEntries.Count() > 0 then
            AddInsight('info', 'emptiedByUndo',
                StrSubstNo('LP, geri alınan mal kabul nedeniyle boşaltıldı (geri alma girişi %1).', Format(UndoEntries.Get(1), 0, 9)), 'ile', Format(UndoEntries.Get(1), 0, 9));

        if LP."Pending Receipt No." <> '' then
            AddInsight('info', 'pendingReceipt', StrSubstNo('LP, %1 mal kabulünün kaydedilmesini bekliyor.', LP."Pending Receipt No."), 'whseReceipt', LP."Pending Receipt No.");

        LPLine.Reset();
        LPLine.SetRange("LP No.", LP."No.");
        if (LP.Status in [LP.Status::Used, LP.Status::Unbuilt]) and not LPLine.IsEmpty() then
            AddInsight('warning', 'inactiveWithLines', StrSubstNo('LP durumu %1 ama hâlâ satırı var.', Format(LP.Status)), '', '');
    end;

    // ───────────────────────────── Ağaç modları (lot / madde / belge) ─────────────────────────────

    local procedure AddLotTree(var Trace: JsonObject; LotNo: Code[50]; ItemFilter: Code[20])
    var
        LPLine: Record "DOPSWHS LP Line";
        Entry: Record "Item Ledger Entry";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        TempLine: Record "DOPSWHS LP Line" temporary;
        GroupKeys: List of [Text];
        HistoricLps: List of [Text];
        Scanned: Integer;
    begin
        Trace.Add('mode', 'lot');
        if ItemFilter <> '' then
            Trace.Add('title', StrSubstNo('%1 · Lot %2', ItemFilter, LotNo))
        else
            Trace.Add('title', StrSubstNo('Lot %1', LotNo));
        Trace.Add('lotNo', LotNo);
        Trace.Add('itemNo', ItemFilter);

        LPLine.SetRange("Lot No.", LotNo);
        if ItemFilter <> '' then
            LPLine.SetRange("Item No.", ItemFilter);
        CollectLines(LPLine, TempLine, GroupKeys);

        Entry.SetRange("Lot No.", LotNo);
        if ItemFilter <> '' then
            Entry.SetRange("Item No.", ItemFilter);
        CollectEntryGroups(Entry, GroupKeys);

        // Bu lotu bir zamanlar taşımış ama artık taşımayan LP'ler (boşaltılmış, bozulmuş, kullanılmış).
        Ledger.SetRange("Lot Serial", LotNo);
        if ItemFilter <> '' then
            Ledger.SetRange("Item No.", ItemFilter);
        Ledger.SetFilter(Action, '%1|%2|%3', Ledger.Action::ItemAdded, Ledger.Action::TransferIn, Ledger.Action::ItemRemoved);
        Ledger.SetLoadFields("LP No.");
        if Ledger.FindSet() then
            repeat
                Scanned += 1;
                AddHistoricLp(Ledger."LP No.", TempLine, HistoricLps);
            until (Ledger.Next() = 0) or (Scanned >= MaxTreeLines()) or (HistoricLps.Count() >= MaxHistoricLps());

        AddTree(Trace, TempLine, GroupKeys, HistoricLps, false);
    end;

    local procedure AddItemTree(var Trace: JsonObject; ItemNo: Code[20])
    var
        LPLine: Record "DOPSWHS LP Line";
        Entry: Record "Item Ledger Entry";
        TempLine: Record "DOPSWHS LP Line" temporary;
        GroupKeys: List of [Text];
        HistoricLps: List of [Text];
    begin
        Trace.Add('mode', 'item');
        Trace.Add('title', StrSubstNo('%1 · %2', ItemNo, ItemDescription(ItemNo)));
        Trace.Add('itemNo', ItemNo);
        LPLine.SetCurrentKey("Item No.");
        LPLine.SetRange("Item No.", ItemNo);
        CollectLines(LPLine, TempLine, GroupKeys);
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange(Open, true);
        CollectEntryGroups(Entry, GroupKeys);
        AddTree(Trace, TempLine, GroupKeys, HistoricLps, true);
    end;

    local procedure AddDocumentTree(var Trace: JsonObject; Search: Text): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
        LPHeader: Record "DOPSWHS LP Header";
        Entry: Record "Item Ledger Entry";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        ActivityLine: Record "Warehouse Activity Line";
        RegisteredLine: Record "Registered Whse. Activity Line";
        TempLine: Record "DOPSWHS LP Line" temporary;
        GroupKeys: List of [Text];
        HistoricLps: List of [Text];
        UndoNos: List of [Integer];
        DocNo: Code[20];
        NavKind: Text;
        NavKey: Text;
        Found: Boolean;
        Scanned: Integer;
        UndoNo: Integer;
    begin
        if StrLen(Search) > MaxStrLen(DocNo) then
            exit(false);
        DocNo := CopyStr(Search, 1, MaxStrLen(DocNo));
        Found := ResolveDocumentNo(DocNo, 'query', NavKind, NavKey);

        LPLine.SetRange("Source Document No.", DocNo);
        CollectLines(LPLine, TempLine, GroupKeys);

        LPHeader.SetCurrentKey("Pending Receipt No.", "Pending Receipt Line No.");
        LPHeader.SetRange("Pending Receipt No.", DocNo);
        CollectHeaders(LPHeader, TempLine, GroupKeys, HistoricLps);
        LPHeader.Reset();
        LPHeader.SetRange("Assigned Document No.", DocNo);
        CollectHeaders(LPHeader, TempLine, GroupKeys, HistoricLps);
        // Silinmiş belgeye atalı LP'ler: belgeyi "bulunamadı" düğümü olarak göster.
        if not Found then
            if LPHeader.FindFirst() then
                ResolveTypedDocument(LPHeader."Assigned Document Type", DocNo, 'query', NavKind, NavKey);

        ActivityLine.SetRange("No.", DocNo);
        ActivityLine.SetFilter("LP No.", '<>%1', '');
        if ActivityLine.FindSet() then
            repeat
                Scanned += 1;
                CollectLp(ActivityLine."LP No.", TempLine, GroupKeys, HistoricLps);
            until (ActivityLine.Next() = 0) or (Scanned >= MaxActivityLines());
        RegisteredLine.SetRange("No.", DocNo);
        RegisteredLine.SetFilter("LP No.", '<>%1', '');
        Scanned := 0;
        if RegisteredLine.FindSet() then
            repeat
                Scanned += 1;
                CollectLp(RegisteredLine."LP No.", TempLine, GroupKeys, HistoricLps);
            until (RegisteredLine.Next() = 0) or (Scanned >= MaxActivityLines());

        // Belgenin madde girişleri: lot grupları, girişe bağlı LP satırları ve geri alma ile boşalan LP'ler.
        Entry.SetCurrentKey("Document No.");
        Entry.SetRange("Document No.", DocNo);
        Scanned := 0;
        if Entry.FindSet() then
            repeat
                Scanned += 1;
                Found := true;
                AddGroupKey(Entry."Item No." + '|' + Entry."Lot No.", GroupKeys);
                LPLine.Reset();
                LPLine.SetCurrentKey("Source Item Ledger Entry No.");
                LPLine.SetRange("Source Item Ledger Entry No.", Entry."Entry No.");
                CollectLines(LPLine, TempLine, GroupKeys);
                Clear(UndoNos);
                if Entry.Correction and (Entry.Quantity < 0) then
                    UndoNos.Add(Entry."Entry No.")
                else
                    LPMgt.CollectUndoneReceiptEntries(Entry."Entry No.", UndoNos);
                foreach UndoNo in UndoNos do begin
                    Ledger.Reset();
                    Ledger.SetCurrentKey("Related Document", Action);
                    Ledger.SetFilter("Related Document", 'UNDO-RCPT:%1:*', Format(UndoNo, 0, 9));
                    Ledger.SetLoadFields("LP No.");
                    if Ledger.FindSet() then
                        repeat
                            AddHistoricLp(Ledger."LP No.", TempLine, HistoricLps);
                        until (Ledger.Next() = 0) or (HistoricLps.Count() >= MaxHistoricLps());
                end;
                AddLedgerDocuments(Entry);
            until (Entry.Next() = 0) or (Scanned >= MaxEntries());

        if not Found and TempLine.IsEmpty() and (HistoricLps.Count() = 0) then
            exit(false);
        Trace.Add('mode', 'document');
        if NavKind <> '' then
            Trace.Add('title', StrSubstNo('%1 %2', KindCaption(NavKind), DocNo))
        else
            Trace.Add('title', StrSubstNo('Belge %1', DocNo));
        Trace.Add('documentNo', DocNo);
        AddTree(Trace, TempLine, GroupKeys, HistoricLps, false);
        exit(true);
    end;

    local procedure CollectLines(var LPLine: Record "DOPSWHS LP Line"; var TempLine: Record "DOPSWHS LP Line" temporary; var GroupKeys: List of [Text])
    var
        Scanned: Integer;
    begin
        if LPLine.FindSet() then
            repeat
                Scanned += 1;
                if LPLine."Item No." <> '' then
                    if not TempLine.Get(LPLine."LP No.", LPLine."Line No.") then begin
                        TempLine := LPLine;
                        TempLine.Insert(false);
                        AddGroupKey(LPLine."Item No." + '|' + LPLine."Lot No.", GroupKeys);
                    end;
            until (LPLine.Next() = 0) or (Scanned >= MaxTreeLines());
        if Scanned >= MaxTreeLines() then
            MarkTruncated('lpLines');
    end;

    local procedure CollectHeaders(var LPHeader: Record "DOPSWHS LP Header"; var TempLine: Record "DOPSWHS LP Line" temporary; var GroupKeys: List of [Text]; var HistoricLps: List of [Text])
    var
        Scanned: Integer;
    begin
        LPHeader.SetLoadFields("No.");
        if LPHeader.FindSet() then
            repeat
                Scanned += 1;
                CollectLp(LPHeader."No.", TempLine, GroupKeys, HistoricLps);
            until (LPHeader.Next() = 0) or (Scanned >= MaxHistoricLps());
    end;

    local procedure CollectLp(LpNo: Code[20]; var TempLine: Record "DOPSWHS LP Line" temporary; var GroupKeys: List of [Text]; var HistoricLps: List of [Text])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.IsEmpty() then
            AddHistoricLp(LpNo, TempLine, HistoricLps)
        else
            CollectLines(LPLine, TempLine, GroupKeys);
    end;

    local procedure AddHistoricLp(LpNo: Code[20]; var TempLine: Record "DOPSWHS LP Line" temporary; var HistoricLps: List of [Text])
    begin
        if (LpNo = '') or HistoricLps.Contains(LpNo) then
            exit;
        TempLine.Reset();
        TempLine.SetRange("LP No.", LpNo);
        if not TempLine.IsEmpty() then begin
            TempLine.Reset();
            exit;
        end;
        TempLine.Reset();
        if HistoricLps.Count() >= MaxHistoricLps() then begin
            MarkTruncated('historicLps');
            exit;
        end;
        HistoricLps.Add(LpNo);
    end;

    local procedure CollectEntryGroups(var Entry: Record "Item Ledger Entry"; var GroupKeys: List of [Text])
    var
        Scanned: Integer;
    begin
        Entry.SetLoadFields("Item No.", "Lot No.");
        if Entry.FindSet() then
            repeat
                Scanned += 1;
                AddGroupKey(Entry."Item No." + '|' + Entry."Lot No.", GroupKeys);
            until (Entry.Next() = 0) or (Scanned >= MaxTreeLines());
    end;

    local procedure AddGroupKey(GroupKey: Text; var GroupKeys: List of [Text])
    begin
        if GroupKeys.Contains(GroupKey) then
            exit;
        if GroupKeys.Count() >= MaxGroups() then begin
            MarkTruncated('groups');
            exit;
        end;
        GroupKeys.Add(GroupKey);
    end;

    local procedure AddTree(var Trace: JsonObject; var TempLine: Record "DOPSWHS LP Line" temporary; var GroupKeys: List of [Text]; var HistoricLps: List of [Text]; OpenEntriesOnly: Boolean)
    var
        Groups: JsonArray;
        Totals: JsonObject;
        Group: JsonObject;
        GroupKey: Text;
        LpCount: Integer;
        LpQty: Decimal;
        BcQty: Decimal;
    begin
        OrphanLpCount := 0;
        EmptiedByUndoCount := 0;
        foreach GroupKey in GroupKeys do begin
            Group := GroupJson(GroupKey, TempLine, OpenEntriesOnly);
            LpCount += GetInteger(Group, 'lpCount');
            LpQty += GetDecimal(Group, 'lpQty');
            BcQty += GetDecimal(Group, 'bcRemainingQty');
            Groups.Add(Group);
        end;
        Trace.Add('groups', Groups);
        Trace.Add('historicLps', HistoricLpsJson(HistoricLps));
        Totals.Add('groupCount', GroupKeys.Count());
        Totals.Add('lpCount', LpCount);
        Totals.Add('lpQty', LpQty);
        Totals.Add('bcRemainingQty', BcQty);
        Totals.Add('historicLpCount', HistoricLps.Count());
        Totals.Add('orphanLpCount', OrphanLpCount);
        Trace.Add('totals', Totals);
        if OrphanLpCount > 0 then
            AddInsight('error', 'orphanAssignment',
                StrSubstNo('%1 LP artık bulunmayan bir belgeye atanmış (yetim).', OrphanLpCount), '', '');
        if EmptiedByUndoCount > 0 then
            AddInsight('info', 'emptiedByUndo',
                StrSubstNo('%1 LP geri alınan mal kabul nedeniyle boşaltıldı.', EmptiedByUndoCount), '', '');
    end;

    local procedure GroupJson(GroupKey: Text; var TempLine: Record "DOPSWHS LP Line" temporary; OpenEntriesOnly: Boolean) Group: JsonObject
    var
        Entry: Record "Item Ledger Entry";
        Parts: List of [Text];
        LpNos: List of [Text];
        Lps: JsonArray;
        ItemNo: Code[20];
        LotNo: Code[50];
        LpNo: Text;
        LpQty: Decimal;
        UnlinkedQty: Decimal;
        BcQty: Decimal;
        State: Text;
    begin
        Parts := GroupKey.Split('|');
        ItemNo := CopyStr(Parts.Get(1), 1, MaxStrLen(ItemNo));
        if Parts.Count() > 1 then
            LotNo := CopyStr(Parts.Get(2), 1, MaxStrLen(LotNo));

        TempLine.Reset();
        TempLine.SetRange("Item No.", ItemNo);
        TempLine.SetRange("Lot No.", LotNo);
        if TempLine.FindSet() then
            repeat
                if not LpNos.Contains(TempLine."LP No.") then
                    LpNos.Add(TempLine."LP No.");
                LpQty += LineBaseQty(TempLine);
                if TempLine."Source Item Ledger Entry No." = 0 then
                    UnlinkedQty += LineBaseQty(TempLine);
            until TempLine.Next() = 0;
        foreach LpNo in LpNos do
            if Lps.Count() < MaxLpsPerGroup() then
                Lps.Add(LpRowJson(CopyStr(LpNo, 1, 20), ItemNo, LotNo, TempLine))
            else
                MarkTruncated('lps');
        TempLine.Reset();

        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Lot No.", LotNo);
        Entry.CalcSums("Remaining Quantity");
        BcQty := Entry."Remaining Quantity";

        if LpQty > BcQty then begin
            State := 'excess';
            AddInsight('warning', 'lpExceedsStock',
                StrSubstNo('%1 / lot %2: LP''lerdeki miktar (%3) BC kalan miktarından (%4) fazla.', ItemNo, LotNo, Format(LpQty), Format(BcQty)), '', '');
        end else
            if LpQty < BcQty then
                State := 'partial'
            else
                State := 'ok';
        if UnlinkedQty > 0 then
            AddInsight('warning', 'missingSourceEntry',
                StrSubstNo('%1 / lot %2: %3 miktarın kaynak madde girişi bağlı değil.', ItemNo, LotNo, Format(UnlinkedQty)), '', '');

        Group.Add('key', GroupKey);
        Group.Add('itemNo', ItemNo);
        Group.Add('itemDescription', ItemDescription(ItemNo));
        Group.Add('lotNo', LotNo);
        Group.Add('lpCount', LpNos.Count());
        Group.Add('lpQty', LpQty);
        Group.Add('bcRemainingQty', BcQty);
        Group.Add('unlinkedLpQty', UnlinkedQty);
        Group.Add('diff', BcQty - LpQty);
        Group.Add('state', State);
        Group.Add('lps', Lps);
        Group.Add('entries', GroupEntriesJson(ItemNo, LotNo, OpenEntriesOnly));
    end;

    local procedure LpRowJson(LpNo: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; var TempLine: Record "DOPSWHS LP Line" temporary) Row: JsonObject
    var
        LP: Record "DOPSWHS LP Header";
        Lines: JsonArray;
        Line: JsonObject;
        SourceKeys: List of [Text];
        SourceEntryNos: List of [Integer];
        Qty: Decimal;
        Orphan: Boolean;
        OnUndoneEntry: Boolean;
    begin
        TempLine.Reset();
        TempLine.SetRange("LP No.", LpNo);
        TempLine.SetRange("Item No.", ItemNo);
        TempLine.SetRange("Lot No.", LotNo);
        if TempLine.FindSet() then
            repeat
                Qty += LineBaseQty(TempLine);
                if not SourceKeys.Contains(SourceGroupKey(TempLine)) then
                    SourceKeys.Add(SourceGroupKey(TempLine));
                Clear(Line);
                Line.Add('lineNo', TempLine."Line No.");
                Line.Add('qty', TempLine.Quantity);
                Line.Add('baseQty', LineBaseQty(TempLine));
                Line.Add('uom', TempLine."Unit of Measure");
                Line.Add('sourceDocType', DocTypeKey(TempLine."Source Document Type"));
                Line.Add('sourceDocNo', TempLine."Source Document No.");
                Line.Add('sourceIleNo', TempLine."Source Item Ledger Entry No.");
                Line.Add('sourceLpNo', TempLine."Source LP No.");
                Line.Add('groupKey', SourceGroupKey(TempLine));
                Line.Add('sourceLabel', SourceGroupLabel(TempLine));
                Line.Add('sourceUndoneBy', UndoEntryOf(TempLine."Source Item Ledger Entry No."));
                if UndoEntryOf(TempLine."Source Item Ledger Entry No.") <> 0 then
                    OnUndoneEntry := true;
                if (TempLine."Source Item Ledger Entry No." <> 0) and not SourceEntryNos.Contains(TempLine."Source Item Ledger Entry No.") then
                    SourceEntryNos.Add(TempLine."Source Item Ledger Entry No.");
                Lines.Add(Line);
            until TempLine.Next() = 0;

        Row.Add('no', LpNo);
        if LP.Get(LpNo) then begin
            Orphan := LPMgt.IsAssignmentOrphaned(LP);
            Row.Add('status', StatusKey(LP.Status));
            Row.Add('statusCaption', Format(LP.Status));
            Row.Add('locationCode', LP."Location Code");
            Row.Add('binCode', LP."Bin Code");
            Row.Add('assignedDocType', DocTypeKey(LP."Assigned Document Type"));
            Row.Add('assignedDocNo', LP."Assigned Document No.");
        end else begin
            Row.Add('status', 'missing');
            Row.Add('statusCaption', '');
            Row.Add('locationCode', '');
            Row.Add('binCode', '');
            Row.Add('assignedDocType', 'none');
            Row.Add('assignedDocNo', '');
        end;
        if Orphan then
            OrphanLpCount += 1;
        Row.Add('orphan', Orphan);
        Row.Add('qty', Qty);
        Row.Add('lineCount', Lines.Count());
        Row.Add('mixedSources', SourceKeys.Count() > 1);
        Row.Add('onUndoneEntry', OnUndoneEntry);
        if SourceEntryNos.Count() = 1 then
            Row.Add('sourceIleNo', SourceEntryNos.Get(1))
        else
            Row.Add('sourceIleNo', 0);
        Row.Add('lines', Lines);
    end;

    local procedure GroupEntriesJson(ItemNo: Code[20]; LotNo: Code[50]; OpenEntriesOnly: Boolean) Result: JsonArray
    var
        Entry: Record "Item Ledger Entry";
        TempEntry: Record "Item Ledger Entry" temporary;
        Row: JsonObject;
        UndoNo: Integer;
        LpQty: Decimal;
        Scanned: Integer;
    begin
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Lot No.", LotNo);
        Entry.SetRange(Positive, true);
        if OpenEntriesOnly then
            Entry.SetRange(Open, true);
        if Entry.FindSet() then
            repeat
                Scanned += 1;
                TempEntry := Entry;
                TempEntry.Insert(false);
            until (Entry.Next() = 0) or (Scanned >= MaxEntriesPerGroup());
        if Scanned >= MaxEntriesPerGroup() then
            MarkTruncated('entries');
        if not OpenEntriesOnly then begin
            Entry.SetRange(Positive, false);
            Entry.SetRange(Correction, true);
            Scanned := 0;
            if Entry.FindSet() then
                repeat
                    Scanned += 1;
                    TempEntry := Entry;
                    if TempEntry.Insert(false) then;
                until (Entry.Next() = 0) or (Scanned >= MaxEntriesPerGroup());
        end;

        if TempEntry.FindSet() then
            repeat
                UndoNo := 0;
                if TempEntry.Positive and not TempEntry.Correction then
                    UndoNo := UndoEntryOf(TempEntry."Entry No.");
                LpQty := LinkedLpBaseQty(TempEntry."Entry No.");
                Clear(Row);
                Row.Add('entryNo', TempEntry."Entry No.");
                Row.Add('postingDate', FormatDate(TempEntry."Posting Date"));
                Row.Add('entryType', Format(TempEntry."Entry Type"));
                Row.Add('documentType', Format(TempEntry."Document Type"));
                Row.Add('documentNo', TempEntry."Document No.");
                Row.Add('locationCode', TempEntry."Location Code");
                Row.Add('qty', TempEntry.Quantity);
                Row.Add('remainingQty', TempEntry."Remaining Quantity");
                Row.Add('open', TempEntry.Open);
                Row.Add('positive', TempEntry.Positive);
                Row.Add('correction', TempEntry.Correction);
                Row.Add('undoneByEntryNo', UndoNo);
                Row.Add('lpQty', LpQty);
                if TempEntry.Positive then
                    Row.Add('diff', TempEntry."Remaining Quantity" - LpQty)
                else
                    Row.Add('diff', 0);
                Result.Add(Row);
                if TempEntry.Positive then
                    if (UndoNo <> 0) and (LpQty > 0) then
                        AddInsight('error', 'sourceUndoneLpFull',
                            StrSubstNo('Madde girişi %1 (%2, lot %3) geri alınmış (düzeltme %4) ama LP''lerde hâlâ %5 bağlı miktar var. Madde Defteri > "Geri Alınan Mal Kabul LP''lerini Boşalt".',
                                Format(TempEntry."Entry No.", 0, 9), TempEntry."Document No.", LotNo, Format(UndoNo, 0, 9), Format(LpQty)), 'ile', Format(TempEntry."Entry No.", 0, 9))
                    else
                        if LpQty > TempEntry."Remaining Quantity" then
                            AddInsight('warning', 'lpExceedsEntryRemaining',
                                StrSubstNo('Madde girişi %1 kalan miktarı (%2), bağlı LP toplamından (%3) az.',
                                    Format(TempEntry."Entry No.", 0, 9), Format(TempEntry."Remaining Quantity"), Format(LpQty)), 'ile', Format(TempEntry."Entry No.", 0, 9));
            until TempEntry.Next() = 0;
    end;

    local procedure HistoricLpsJson(var HistoricLps: List of [Text]) Result: JsonArray
    var
        LP: Record "DOPSWHS LP Header";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Row: JsonObject;
        LpNo: Text;
        EmptiedByUndo: Boolean;
    begin
        foreach LpNo in HistoricLps do begin
            Clear(Row);
            Row.Add('no', LpNo);
            if LP.Get(CopyStr(LpNo, 1, MaxStrLen(LP."No."))) then begin
                Row.Add('status', StatusKey(LP.Status));
                Row.Add('statusCaption', Format(LP.Status));
                Row.Add('locationCode', LP."Location Code");
                Row.Add('binCode', LP."Bin Code");
                Row.Add('assignedDocNo', LP."Assigned Document No.");
                if LPMgt.IsAssignmentOrphaned(LP) then begin
                    OrphanLpCount += 1;
                    Row.Add('orphan', true);
                end else
                    Row.Add('orphan', false);
            end else begin
                Row.Add('status', 'missing');
                Row.Add('statusCaption', '');
                Row.Add('locationCode', '');
                Row.Add('binCode', '');
                Row.Add('assignedDocNo', '');
                Row.Add('orphan', false);
            end;
            Ledger.Reset();
            Ledger.SetCurrentKey("LP No.", DateTime);
            Ledger.SetRange("LP No.", CopyStr(LpNo, 1, MaxStrLen(Ledger."LP No.")));
            if Ledger.FindLast() then begin
                Row.Add('lastAction', ActionKey(Ledger.Action));
                Row.Add('lastAt', FormatDateTime(Ledger.DateTime));
                Row.Add('lastRelatedDocument', Ledger."Related Document");
            end else begin
                Row.Add('lastAction', '');
                Row.Add('lastAt', '');
                Row.Add('lastRelatedDocument', '');
            end;
            Ledger.SetFilter("Related Document", 'UNDO-RCPT:*');
            EmptiedByUndo := not Ledger.IsEmpty();
            if EmptiedByUndo then
                EmptiedByUndoCount += 1;
            Row.Add('emptiedByUndo', EmptiedByUndo);
            Result.Add(Row);
        end;
    end;

    // ───────────────────────────── Belge çözümleme ─────────────────────────────

    /// <summary>
    /// A typed LP document reference (assigned or source). State: open (document
    /// itself exists), posted (only its posted/registered form exists), missing.
    /// </summary>
    local procedure ResolveTypedDocument(DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]; Role: Text; var NavKind: Text; var NavKey: Text): Text
    var
        Kind: Text;
        State: Text;
    begin
        NavKind := '';
        NavKey := '';
        if DocNo = '' then
            exit('none');
        Kind := KindForDocType(DocType);
        if ResolveDocumentNo(DocNo, Role, NavKind, NavKey) then begin
            State := DocumentState(Kind, DocNo);
            if State = '' then
                State := 'open';
            exit(State);
        end;
        if Kind = '' then
            Kind := 'unknown';
        AddDocument(Kind, DocNo, 'missing', Role, 'Belge bulunamadı (silinmiş olabilir)', '', '');
        exit('missing');
    end;

    /// <summary>Looks a document number up in every warehouse/purchase/production table; adds each hit to the document list.</summary>
    local procedure ResolveDocumentNo(DocNoText: Text; Role: Text; var NavKind: Text; var NavKey: Text): Boolean
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        ProductionOrder: Record "Production Order";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
        DocNo: Code[20];
        Cached: Text;
        WhseReceiptExists: Boolean;
        WhseShipmentExists: Boolean;
    begin
        NavKind := '';
        NavKey := '';
        DocNoText := UpperCase(DelChr(DocNoText, '<>', ' '));
        if (DocNoText = '') or (StrLen(DocNoText) > MaxStrLen(DocNo)) then
            exit(false);
        DocNo := CopyStr(DocNoText, 1, MaxStrLen(DocNo));
        if ResolveCache.Get(DocNo, Cached) then begin
            if Cached = '' then
                exit(false);
            NavKind := Cached.Split('|').Get(1);
            NavKey := Cached.Split('|').Get(2);
            exit(true);
        end;

        if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo) then
            AddFound('purchaseOrder', DocNo, Role, '', NavKind, NavKey);

        WhseReceiptExists := WhseReceiptHeader.Get(DocNo);
        if WhseReceiptExists then
            AddFound('whseReceipt', DocNo, Role, '', NavKind, NavKey);
        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", DocNo);
        if PostedWhseReceiptHeader.FindSet() then begin
            if not WhseReceiptExists then
                AddDocument('whseReceipt', DocNo, 'posted', Role, 'Kaydedildi: ' + PostedWhseReceiptHeader."No.", 'postedWhseReceipt', PostedWhseReceiptHeader."No.");
            repeat
                AddFound('postedWhseReceipt', PostedWhseReceiptHeader."No.", 'related', 'Ambar mal kabulü ' + DocNo, NavKind, NavKey);
            until PostedWhseReceiptHeader.Next() = 0;
        end;
        if PostedWhseReceiptHeader.Get(DocNo) then
            AddFound('postedWhseReceipt', DocNo, Role, '', NavKind, NavKey);

        if PurchRcptHeader.Get(DocNo) then begin
            AddFound('purchRcpt', DocNo, Role, '', NavKind, NavKey);
            if PurchRcptHeader."Order No." <> '' then
                if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, PurchRcptHeader."Order No.") then
                    AddDocument('purchaseOrder', PurchRcptHeader."Order No.", 'open', 'related', '', 'purchaseOrder', PurchRcptHeader."Order No.");
        end;

        ResolveActivity(ActivityHeader.Type::"Put-away", 'Putaway', DocNo, Role, NavKind, NavKey);
        ResolveActivity(ActivityHeader.Type::Movement, 'Movement', DocNo, Role, NavKind, NavKey);
        ResolveActivity(ActivityHeader.Type::Pick, 'Pick', DocNo, Role, NavKind, NavKey);
        if RegisteredHeader.Get(RegisteredHeader.Type::"Put-away", DocNo) then
            AddFound('regPutaway', DocNo, Role, '', NavKind, NavKey);
        if RegisteredHeader.Get(RegisteredHeader.Type::Movement, DocNo) then
            AddFound('regMovement', DocNo, Role, '', NavKind, NavKey);
        if RegisteredHeader.Get(RegisteredHeader.Type::Pick, DocNo) then
            AddFound('regPick', DocNo, Role, '', NavKind, NavKey);

        WhseShipmentExists := WhseShipmentHeader.Get(DocNo);
        if WhseShipmentExists then
            AddFound('whseShipment', DocNo, Role, '', NavKind, NavKey);
        PostedWhseShipmentHeader.SetRange("Whse. Shipment No.", DocNo);
        if PostedWhseShipmentHeader.FindSet() then begin
            if not WhseShipmentExists then
                AddDocument('whseShipment', DocNo, 'posted', Role, 'Kaydedildi: ' + PostedWhseShipmentHeader."No.", 'postedWhseShipment', PostedWhseShipmentHeader."No.");
            repeat
                AddFound('postedWhseShipment', PostedWhseShipmentHeader."No.", 'related', 'Ambar sevkiyatı ' + DocNo, NavKind, NavKey);
            until PostedWhseShipmentHeader.Next() = 0;
        end;
        if PostedWhseShipmentHeader.Get(DocNo) then
            AddFound('postedWhseShipment', DocNo, Role, '', NavKind, NavKey);
        if SalesShipmentHeader.Get(DocNo) then
            AddFound('salesShipment', DocNo, Role, '', NavKind, NavKey);

        ProductionOrder.SetRange("No.", DocNo);
        if ProductionOrder.FindFirst() then
            AddFound('prodOrder', DocNo, Role, Format(ProductionOrder.Status), NavKind, NavKey);
        if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then
            AddFound('assemblyOrder', DocNo, Role, '', NavKind, NavKey);
        if PostedAssemblyHeader.Get(DocNo) then
            AddFound('postedAssembly', DocNo, Role, '', NavKind, NavKey);

        if NavKind = '' then
            ResolveCache.Set(DocNo, '')
        else
            ResolveCache.Set(DocNo, NavKind + '|' + NavKey);
        exit(NavKind <> '');
    end;

    local procedure ResolveActivity(ActivityType: Enum "Warehouse Activity Type"; KindSuffix: Text; DocNo: Code[20]; Role: Text; var NavKind: Text; var NavKey: Text)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        Exists: Boolean;
    begin
        Exists := ActivityHeader.Get(ActivityType, DocNo);
        if Exists then
            AddFound('whse' + KindSuffix, DocNo, Role, '', NavKind, NavKey);
        RegisteredHeader.SetRange(Type, ActivityType);
        RegisteredHeader.SetRange("Whse. Activity No.", DocNo);
        if RegisteredHeader.FindSet() then begin
            if not Exists then
                AddDocument('whse' + KindSuffix, DocNo, 'posted', Role, 'Kaydedildi: ' + RegisteredHeader."No.", 'reg' + KindSuffix, RegisteredHeader."No.");
            repeat
                AddFound('reg' + KindSuffix, RegisteredHeader."No.", 'related', KindCaption('whse' + KindSuffix) + ' ' + DocNo, NavKind, NavKey);
            until RegisteredHeader.Next() = 0;
        end;
    end;

    local procedure AddFound(Kind: Text; DocNo: Code[20]; Role: Text; Note: Text; var NavKind: Text; var NavKey: Text)
    begin
        AddDocument(Kind, DocNo, StateForKind(Kind), Role, Note, Kind, DocNo);
        if NavKind = '' then begin
            NavKind := Kind;
            NavKey := DocNo;
        end;
    end;

    local procedure AddDocument(Kind: Text; DocNo: Code[20]; State: Text; Role: Text; Note: Text; NavKind: Text; NavKey: Text)
    var
        Doc: JsonObject;
        DocKey: Text;
    begin
        DocKey := Kind + '|' + DocNo;
        if DocumentKeys.Contains(DocKey) then
            exit;
        if DocumentKeys.Count() >= MaxDocuments() then begin
            MarkTruncated('documents');
            exit;
        end;
        DocumentKeys.Add(DocKey);
        Doc.Add('key', DocKey);
        Doc.Add('kind', Kind);
        Doc.Add('kindCaption', KindCaption(Kind));
        Doc.Add('no', DocNo);
        Doc.Add('state', State);
        Doc.Add('exists', State <> 'missing');
        Doc.Add('stage', KindStage(Kind));
        Doc.Add('role', Role);
        Doc.Add('note', Note);
        AddNav(Doc, NavKind, NavKey);
        Documents.Add(Doc);
    end;

    local procedure DocumentState(Kind: Text; DocNo: Code[20]): Text
    var
        Token: JsonToken;
        Index: Integer;
    begin
        Index := DocumentKeys.IndexOf(Kind + '|' + DocNo);
        if Index = 0 then
            exit('');
        Documents.Get(Index - 1, Token);
        exit(GetText(Token.AsObject(), 'state'));
    end;

    local procedure SortedDocuments() Sorted: JsonArray
    var
        Token: JsonToken;
        Stage: Integer;
    begin
        for Stage := 0 to 100 do
            foreach Token in Documents do
                if GetInteger(Token.AsObject(), 'stage') = Stage then
                    Sorted.Add(Token.AsObject());
    end;

    local procedure StateForKind(Kind: Text): Text
    begin
        if Kind in ['postedWhseReceipt', 'purchRcpt', 'regPutaway', 'regMovement', 'regPick', 'postedWhseShipment', 'salesShipment', 'postedAssembly'] then
            exit('posted');
        exit('open');
    end;

    local procedure KindForDocType(DocType: Enum "DOPSWHS Assigned Doc Type"): Text
    begin
        case DocType of
            DocType::WhseReceipt:
                exit('whseReceipt');
            DocType::WhsePick:
                exit('whsePick');
            DocType::WhseShipment:
                exit('whseShipment');
            DocType::WhsePutaway:
                exit('whsePutaway');
            DocType::WhseMovement:
                exit('whseMovement');
            DocType::ProdConsumption, DocType::ProdOutput:
                exit('prodOrder');
            DocType::Assembly:
                exit('assemblyOrder');
        end;
        exit('');
    end;

    procedure KindCaption(Kind: Text): Text
    begin
        case Kind of
            'purchaseOrder':
                exit('Satınalma siparişi');
            'whseReceipt':
                exit('Ambar mal kabulü');
            'postedWhseReceipt':
                exit('Kayıtlı ambar mal kabulü');
            'purchRcpt':
                exit('Alış irsaliyesi');
            'whsePutaway':
                exit('Ambar yerine koyma');
            'regPutaway':
                exit('Kayıtlı yerine koyma');
            'whseMovement':
                exit('Ambar hareketi');
            'regMovement':
                exit('Kayıtlı hareket');
            'whsePick':
                exit('Ambar toplama');
            'regPick':
                exit('Kayıtlı toplama');
            'prodOrder':
                exit('Üretim emri');
            'assemblyOrder':
                exit('Montaj emri');
            'postedAssembly':
                exit('Kayıtlı montaj emri');
            'whseShipment':
                exit('Ambar sevkiyatı');
            'postedWhseShipment':
                exit('Kayıtlı ambar sevkiyatı');
            'salesShipment':
                exit('Satış irsaliyesi');
            'lp':
                exit('LP');
            'ile':
                exit('Madde girişi');
        end;
        exit('Belge');
    end;

    local procedure KindStage(Kind: Text): Integer
    begin
        case Kind of
            'purchaseOrder':
                exit(10);
            'whseReceipt':
                exit(20);
            'postedWhseReceipt':
                exit(25);
            'purchRcpt':
                exit(30);
            'whsePutaway':
                exit(40);
            'regPutaway':
                exit(45);
            'whseMovement':
                exit(50);
            'regMovement':
                exit(55);
            'prodOrder', 'assemblyOrder':
                exit(60);
            'postedAssembly':
                exit(65);
            'whsePick':
                exit(70);
            'regPick':
                exit(75);
            'whseShipment':
                exit(80);
            'postedWhseShipment':
                exit(85);
            'salesShipment':
                exit(90);
        end;
        exit(100);
    end;

    // ───────────────────────────── Yardımcılar ─────────────────────────────

    local procedure ResetState()
    var
        EmptyArray: JsonArray;
        EmptyInsights: JsonArray;
        EmptyObject: JsonObject;
    begin
        Documents := EmptyArray;
        Insights := EmptyInsights;
        Truncated := EmptyObject;
        Clear(DocumentKeys);
        Clear(ResolveCache);
        Clear(ItemDescriptions);
        Clear(UndoEntryCache);
        OrphanLpCount := 0;
        EmptiedByUndoCount := 0;
    end;

    local procedure FindLp(Search: Text; var LP: Record "DOPSWHS LP Header"): Boolean
    begin
        if StrLen(Search) <= MaxStrLen(LP."No.") then
            if LP.Get(CopyStr(Search, 1, MaxStrLen(LP."No."))) then
                exit(true);
        if StrLen(Search) = MaxStrLen(LP.SSCC) then begin
            LP.SetCurrentKey(SSCC);
            LP.SetRange(SSCC, CopyStr(Search, 1, MaxStrLen(LP.SSCC)));
            if LP.FindFirst() then
                exit(true);
        end;
        exit(false);
    end;

    local procedure IsKnownLot(Search: Text): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
        Entry: Record "Item Ledger Entry";
    begin
        if StrLen(Search) > MaxStrLen(LPLine."Lot No.") then
            exit(false);
        Entry.SetRange("Lot No.", CopyStr(Search, 1, MaxStrLen(Entry."Lot No.")));
        if not Entry.IsEmpty() then
            exit(true);
        LPLine.SetRange("Lot No.", CopyStr(Search, 1, MaxStrLen(LPLine."Lot No.")));
        exit(not LPLine.IsEmpty());
    end;

    /// <summary>
    /// Lines that came by different routes get different keys: a line moved from
    /// another LP (Source LP No.) is not the same source as one received directly
    /// on the same receipt (e.g. part from the receipt, part from an unbuilt LP).
    /// </summary>
    procedure SourceGroupKey(LPLine: Record "DOPSWHS LP Line"): Text
    begin
        if LPLine."Source LP No." <> '' then
            exit('lp:' + LPLine."Source LP No.");
        if LPLine."Source Document No." <> '' then
            exit('doc:' + DocTypeKey(LPLine."Source Document Type") + ':' + LPLine."Source Document No.");
        if LPLine."Source Item Ledger Entry No." <> 0 then
            exit('ile:' + Format(LPLine."Source Item Ledger Entry No.", 0, 9));
        if LPLine."Child LP No." <> '' then
            exit('child:' + LPLine."Child LP No.");
        exit('none:');
    end;

    local procedure SourceGroupLabel(LPLine: Record "DOPSWHS LP Line"): Text
    begin
        if LPLine."Source LP No." <> '' then begin
            if LPLine."Source Document No." <> '' then
                exit(StrSubstNo('LP %1 üzerinden (%2)', LPLine."Source LP No.", LPLine."Source Document No."));
            exit(StrSubstNo('LP %1 üzerinden', LPLine."Source LP No."));
        end;
        if LPLine."Source Document No." <> '' then
            exit(StrSubstNo('%1 %2', DocTypeCaption(LPLine."Source Document Type"), LPLine."Source Document No.").Trim());
        if LPLine."Source Item Ledger Entry No." <> 0 then
            exit('Madde girişi ' + Format(LPLine."Source Item Ledger Entry No.", 0, 9));
        if LPLine."Child LP No." <> '' then
            exit('Alt LP ' + LPLine."Child LP No.");
        exit('Kaynak bilgisi yok');
    end;

    local procedure IsResolvableReference(Ref: Text): Boolean
    begin
        if Ref = '' then
            exit(false);
        if Ref in ['EMPTIED', 'BIN-MOVE', 'BIN-ASSIGN', 'RECLASS', 'PHYSINV', 'BULK', 'BATCH', 'MULTI', 'UNBUILD', 'CREATENEWLP', 'REMOVEEXCESS', 'REMOVEUSEDPORTION', 'RECEIPT', 'ITEM', 'SSCC'] then
            exit(false);
        exit(true);
    end;

    /// <summary>
    /// Ledger "Related Document" is free text: a document no., "PICK:<no.>" or a
    /// caption glued to the number ("Warehouse Put-away<no.>"). Returns the
    /// trailing run of document-number characters.
    /// </summary>
    procedure ExtractDocumentNo(Ref: Text): Text
    var
        Index: Integer;
    begin
        Ref := DelChr(Ref, '<>', ' ');
        for Index := StrLen(Ref) downto 2 do
            if IsDocChar(CopyStr(Ref, Index, 1)) and not IsDocChar(CopyStr(Ref, Index - 1, 1)) then
                exit(CopyStr(Ref, Index));
        exit(Ref);
    end;

    local procedure IsDocChar(Character: Text): Boolean
    begin
        exit(StrPos('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/', Character) > 0);
    end;

    local procedure ListContainsLp(LpNos: Text; LpNo: Code[20]): Boolean
    var
        Part: Text;
    begin
        foreach Part in LpNos.Split(',') do
            if Part.Trim() = LpNo then
                exit(true);
        exit(false);
    end;

    /// <summary>Undo (correction) entry of an undone receipt entry, 0 when the entry was not undone. Cached per trace.</summary>
    local procedure UndoEntryOf(EntryNo: Integer): Integer
    var
        UndoNos: List of [Integer];
        UndoNo: Integer;
    begin
        if EntryNo = 0 then
            exit(0);
        if UndoEntryCache.Get(EntryNo, UndoNo) then
            exit(UndoNo);
        LPMgt.CollectUndoneReceiptEntries(EntryNo, UndoNos);
        foreach UndoNo in UndoNos do
            if UndoNo <> EntryNo then begin
                UndoEntryCache.Set(EntryNo, UndoNo);
                exit(UndoNo);
            end;
        UndoEntryCache.Set(EntryNo, 0);
        exit(0);
    end;

    local procedure LinkedLpBaseQty(EntryNo: Integer) Total: Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if EntryNo = 0 then
            exit(0);
        LPLine.SetCurrentKey("Source Item Ledger Entry No.");
        LPLine.SetRange("Source Item Ledger Entry No.", EntryNo);
        if LPLine.FindSet() then
            repeat
                Total += LineBaseQty(LPLine);
            until LPLine.Next() = 0;
    end;

    local procedure LineBaseQty(LPLine: Record "DOPSWHS LP Line"): Decimal
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if (LPLine."Unit of Measure" = '') or (LPLine."Item No." = '') then
            exit(LPLine.Quantity);
        if Item.Get(LPLine."Item No.") then
            if Item."Base Unit of Measure" = LPLine."Unit of Measure" then
                exit(LPLine.Quantity);
        if ItemUnitOfMeasure.Get(LPLine."Item No.", LPLine."Unit of Measure") then
            if ItemUnitOfMeasure."Qty. per Unit of Measure" <> 0 then
                exit(LPLine.Quantity * ItemUnitOfMeasure."Qty. per Unit of Measure");
        exit(LPLine.Quantity);
    end;

    local procedure ItemDescription(ItemNo: Text): Text
    var
        Item: Record Item;
        Description: Text;
    begin
        if ItemNo = '' then
            exit('');
        if ItemDescriptions.Get(ItemNo, Description) then
            exit(Description);
        if StrLen(ItemNo) <= MaxStrLen(Item."No.") then
            if Item.Get(CopyStr(ItemNo, 1, MaxStrLen(Item."No."))) then
                Description := Item.Description;
        ItemDescriptions.Set(ItemNo, Description);
        exit(Description);
    end;

    local procedure AddInsight(Level: Text; InsightCode: Text; Message: Text; NavKind: Text; NavKey: Text)
    var
        Insight: JsonObject;
    begin
        Insight.Add('level', Level);
        Insight.Add('code', InsightCode);
        Insight.Add('text', Message);
        AddNav(Insight, NavKind, NavKey);
        Insights.Add(Insight);
    end;

    local procedure AddNav(var Target: JsonObject; NavKind: Text; NavKey: Text)
    var
        Nav: JsonObject;
    begin
        if (NavKind = '') or (NavKey = '') then begin
            Target.Add('nav', NullValue());
            exit;
        end;
        Nav.Add('kind', NavKind);
        Nav.Add('key', NavKey);
        Target.Add('nav', Nav);
    end;

    local procedure MarkTruncated(Section: Text)
    begin
        if not Truncated.Contains(Section) then
            Truncated.Add(Section, true);
    end;

    procedure StatusKey(Status: Enum "DOPSWHS LP Status"): Text
    var
        Index: Integer;
    begin
        Index := Status.Ordinals().IndexOf(Status.AsInteger());
        if Index = 0 then
            exit(Format(Status.AsInteger(), 0, 9));
        exit(LowerFirst(Status.Names().Get(Index)));
    end;

    procedure ActionKey(LpAction: Enum "DOPSWHS LP Action"): Text
    var
        Index: Integer;
    begin
        Index := LpAction.Ordinals().IndexOf(LpAction.AsInteger());
        if Index = 0 then
            exit(Format(LpAction.AsInteger(), 0, 9));
        exit(LowerFirst(LpAction.Names().Get(Index)));
    end;

    procedure DocTypeKey(DocType: Enum "DOPSWHS Assigned Doc Type"): Text
    var
        Index: Integer;
    begin
        Index := DocType.Ordinals().IndexOf(DocType.AsInteger());
        if Index = 0 then
            exit(Format(DocType.AsInteger(), 0, 9));
        exit(LowerFirst(DocType.Names().Get(Index)));
    end;

    local procedure DocTypeCaption(DocType: Enum "DOPSWHS Assigned Doc Type"): Text
    begin
        case DocType of
            DocType::None:
                exit('');
            DocType::WhseReceipt:
                exit('Ambar mal kabulü');
            DocType::WhsePick:
                exit('Ambar toplama');
            DocType::WhseShipment:
                exit('Ambar sevkiyatı');
            DocType::WhsePutaway:
                exit('Ambar yerine koyma');
            DocType::WhseMovement:
                exit('Ambar hareketi');
            DocType::ProdConsumption:
                exit('Üretim tüketimi');
            DocType::ProdOutput:
                exit('Üretim çıktısı');
            DocType::Assembly:
                exit('Montaj');
        end;
        exit(Format(DocType));
    end;

    local procedure LowerFirst(Value: Text): Text
    begin
        if Value = '' then
            exit('');
        exit(LowerCase(CopyStr(Value, 1, 1)) + CopyStr(Value, 2));
    end;

    local procedure GetText(Source: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure GetDecimal(Source: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if Source.Get(Name, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsDecimal());
        exit(0);
    end;

    local procedure GetInteger(Source: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if Source.Get(Name, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsInteger());
        exit(0);
    end;

    local procedure NullValue() Value: JsonValue
    begin
        Value.SetValueToNull();
    end;

    local procedure FormatDateTime(Value: DateTime): Text
    begin
        if Value = 0DT then
            exit('');
        exit(Format(Value, 0, 9));
    end;

    local procedure FormatDate(Value: Date): Text
    begin
        if Value = 0D then
            exit('');
        exit(Format(Value, 0, 9));
    end;

    local procedure MaxTimelineRows(): Integer
    begin
        exit(500);
    end;

    local procedure MaxEntries(): Integer
    begin
        exit(200);
    end;

    local procedure MaxEntriesPerGroup(): Integer
    begin
        exit(60);
    end;

    local procedure MaxDocuments(): Integer
    begin
        exit(60);
    end;

    local procedure MaxResolvedDocs(): Integer
    begin
        exit(20);
    end;

    local procedure MaxChildren(): Integer
    begin
        exit(50);
    end;

    local procedure MaxActivityLines(): Integer
    begin
        exit(300);
    end;

    local procedure MaxTreeLines(): Integer
    begin
        exit(3000);
    end;

    local procedure MaxGroups(): Integer
    begin
        exit(40);
    end;

    local procedure MaxLpsPerGroup(): Integer
    begin
        exit(300);
    end;

    local procedure MaxHistoricLps(): Integer
    begin
        exit(300);
    end;

}
