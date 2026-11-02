codeunit 72001 "DOPSWHS Quality Gate Mgmt"
{
    // KIT-009 / INV-009 (Kitoko, Kas 2026): mandatory inspection gates.
    //  - Purchase receipt (warehouse receipt or direct purchase order receipt):
    //    a line in the scope of a "Before Posting" rule cannot be received while
    //    its quality order has no result (or does not exist). A failed result
    //    does not stop the receipt: the stock is received into quarantine and,
    //    with the quality lot hold on, its lot stays blocked (KIT-010).
    //    An "After Posting" rule creates the quality orders while posting.
    //  - Assembly output: an order in the scope of a rule cannot be posted
    //    unless its final inspection passed (or was accepted with deviation).
    // Rules come from table "DOPSWHS Quality Rule"; both gates are inactive
    // until switched on in Advanced WMS Setup. An inspection used by a posting
    // is stamped with the posted document, so a further partial posting of
    // the same line requires a new inspection.
    Access = Public;
    Permissions =
        tabledata "Purchase Header" = r,
        tabledata "Purchase Line" = r,
        tabledata "Warehouse Receipt Line" = r,
        tabledata "Reservation Entry" = r,
        tabledata "Item Ledger Entry" = r;

    // -------------------------------------------------------------------------
    // Setup and rules
    // -------------------------------------------------------------------------

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    procedure ReceiptGateEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        Setup.SetLoadFields("Receipt Quality Gate");
        if not Setup.Get('') then
            exit(false);
        exit(Setup."Receipt Quality Gate");
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    procedure AssemblyGateEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        Setup.SetLoadFields("Assembly Quality Gate");
        if not Setup.Get('') then
            exit(false);
        exit(Setup."Assembly Quality Gate");
    end;

    /// <summary>
    /// Most specific enabled rule for the posting, location, item (and its item
    /// category or any parent category) and vendor. Blank rule fields match all.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Rule", 'R')]
    procedure FindRule(SourceType: Enum "DOPSWHS Quality Rule Source"; LocationCode: Code[10]; ItemNo: Code[20]; VendorNo: Code[20]; var QualityRule: Record "DOPSWHS Quality Rule"): Boolean
    var
        CandidateRule: Record "DOPSWHS Quality Rule";
        Item: Record Item;
        BestScore: Integer;
    begin
        Clear(QualityRule);
        if ItemNo = '' then
            exit(false);
        CandidateRule.SetCurrentKey("Source Type", Enabled);
        CandidateRule.SetRange("Source Type", SourceType);
        CandidateRule.SetRange(Enabled, true);
        if CandidateRule.IsEmpty() then
            exit(false);
        Item.SetLoadFields("Item Category Code");
        if not Item.Get(ItemNo) then
            exit(false);
        CandidateRule.SetFilter("Location Code", '%1|%2', '', LocationCode);
        CandidateRule.SetFilter("Item No.", '%1|%2', '', ItemNo);
        if VendorNo <> '' then
            CandidateRule.SetFilter("Vendor No.", '%1|%2', '', VendorNo)
        else
            CandidateRule.SetRange("Vendor No.", '');
        BestScore := -1;
        if CandidateRule.FindSet() then
            repeat
                if CategoryMatches(CandidateRule."Item Category Code", Item."Item Category Code") then
                    if CandidateRule.Specificity() > BestScore then begin
                        QualityRule := CandidateRule;
                        BestScore := CandidateRule.Specificity();
                    end;
            until CandidateRule.Next() = 0;
        exit(BestScore >= 0);
    end;

    /// <summary>True when the purchase line is covered by an enabled rule with the given timing.</summary>
    procedure PurchaseLineInScope(PurchaseLine: Record "Purchase Line"; Timing: Enum "DOPSWHS Quality Insp. Timing"): Boolean
    var
        QualityRule: Record "DOPSWHS Quality Rule";
    begin
        if PurchaseLine.Type <> PurchaseLine.Type::Item then
            exit(false);
        if not FindRule(Enum::"DOPSWHS Quality Rule Source"::"Purchase Receipt", PurchaseLine."Location Code", PurchaseLine."No.", PurchaseLine."Buy-from Vendor No.", QualityRule) then
            exit(false);
        exit(QualityRule.Timing = Timing);
    end;

    local procedure CategoryMatches(RuleCategoryCode: Code[20]; ItemCategoryCode: Code[20]): Boolean
    var
        ItemCategory: Record "Item Category";
        CurrentCode: Code[20];
        Depth: Integer;
    begin
        if RuleCategoryCode = '' then
            exit(true);
        CurrentCode := ItemCategoryCode;
        ItemCategory.SetLoadFields("Parent Category");
        // Depth guard: a corrupt (cyclic) category tree must not hang posting.
        while (CurrentCode <> '') and (Depth < 20) do begin
            if CurrentCode = RuleCategoryCode then
                exit(true);
            if not ItemCategory.Get(CurrentCode) then
                exit(false);
            CurrentCode := ItemCategory."Parent Category";
            Depth += 1;
        end;
        exit(false);
    end;

    // -------------------------------------------------------------------------
    // KIT-009 receipt gate
    // -------------------------------------------------------------------------

    /// <summary>
    /// Creation rule: a warehouse receipt line created for a purchase line in
    /// the scope of a "Before Posting" rule with "Create Automatically" gets its
    /// (line-level) quality order right away. Standard "Get Source Documents" /
    /// "Create Warehouse Receipt" and the terminal's receipt creation both pass here.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purchases Warehouse Mgt.", 'OnAfterCreateRcptLineFromPurchLine', '', false, false)]
    local procedure AutoCreateOnWhseReceiptLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; PurchaseLine: Record "Purchase Line")
    var
        QualityRule: Record "DOPSWHS Quality Rule";
    begin
        if WarehouseReceiptLine.IsTemporary() then
            exit;
        if (PurchaseLine."Document Type" <> PurchaseLine."Document Type"::Order) or (PurchaseLine.Type <> PurchaseLine.Type::Item) then
            exit;
        if not ReceiptGateEnabled() then
            exit;
        if not FindRule(Enum::"DOPSWHS Quality Rule Source"::"Purchase Receipt", PurchaseLine."Location Code", PurchaseLine."No.", PurchaseLine."Buy-from Vendor No.", QualityRule) then
            exit;
        if (QualityRule.Timing <> QualityRule.Timing::"Before Posting") or not QualityRule."Create Automatically" then
            exit;
        CreateOrdersForPurchaseLine(
            PurchaseLine, WarehouseReceiptLine."No.", WarehouseReceiptLine."Qty. Outstanding", WarehouseReceiptLine."Unit of Measure Code",
            WarehouseReceiptLine."Location Code", WarehouseReceiptLine."Bin Code", '');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", 'OnAfterCheckWhseRcptLine', '', false, false)]
    local procedure CheckWarehouseReceiptLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line")
    var
        PurchaseLine: Record "Purchase Line";
    begin
        if WarehouseReceiptLine.IsTemporary() then
            exit;
        // Checked here, before any source document is posted: with the default
        // warehouse receipt posting policy errors raised inside Purch.-Post are
        // swallowed and the user would only see "0 of 1 documents posted".
        if (WarehouseReceiptLine."Source Type" <> Database::"Purchase Line") or
           (WarehouseReceiptLine."Source Subtype" <> PurchaseLine."Document Type"::Order.AsInteger()) or
           (WarehouseReceiptLine."Qty. to Receive" <= 0)
        then
            exit;
        if not ReceiptGateEnabled() then
            exit;
        PurchaseLine.SetLoadFields(Type, "No.", "Variant Code", "Location Code", "Buy-from Vendor No.");
        if not PurchaseLine.Get(PurchaseLine."Document Type"::Order, WarehouseReceiptLine."Source No.", WarehouseReceiptLine."Source Line No.") then
            exit;
        if not PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then
            exit;
        CheckReceiptInspection(PurchaseLine, WarehouseReceiptLine."No.");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterCheckPurchDoc', '', false, false)]
    local procedure CheckPurchaseOrderReceipt(var PurchHeader: Record "Purchase Header"; CommitIsSupressed: Boolean; WhseShip: Boolean; WhseReceive: Boolean; PreviewMode: Boolean; var ErrorMessageMgt: Codeunit "Error Message Management")
    var
        PurchaseLine: Record "Purchase Line";
    begin
        if PurchHeader.IsTemporary() then
            exit;
        // Warehouse receipts are checked per line in CheckWarehouseReceiptLine.
        if WhseReceive or not PurchHeader.Receive then
            exit;
        if PurchHeader."Document Type" <> PurchHeader."Document Type"::Order then
            exit;
        if not ReceiptGateEnabled() then
            exit;
        PurchaseLine.SetLoadFields("Document Type", "Document No.", "Line No.", Type, "No.", "Variant Code", "Location Code", "Buy-from Vendor No.", "Qty. to Receive");
        PurchaseLine.SetRange("Document Type", PurchHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchHeader."No.");
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        PurchaseLine.SetFilter("Qty. to Receive", '<>0');
        if PurchaseLine.FindSet() then
            repeat
                if PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then
                    CheckReceiptInspection(PurchaseLine, '');
            until PurchaseLine.Next() = 0;
    end;

    /// <summary>
    /// The latest inspection of each lot/serial of the line (or of the whole line)
    /// must have a result; when inspections were made per lot, every lot about to
    /// be received needs one.
    /// </summary>
    local procedure CheckReceiptInspection(PurchaseLine: Record "Purchase Line"; WhseDocumentNo: Code[20])
    var
        TempLatest: Record "DOPSWHS Quality Order" temporary;
    begin
        CollectReceiptOrders(PurchaseLine, WhseDocumentNo, true, TempLatest);
        if not TempLatest.FindSet() then
            Error(ReceiptInspectionRequiredErr, PurchaseLine."No.", PurchaseLine."Document No.", PurchaseLine."Line No.");
        repeat
            if TempLatest.IsUndecided() then
                Error(ReceiptInspectionOpenErr, TempLatest."No.", PurchaseLine."No.", TrackingCaption(TempLatest), PurchaseLine."Document No.");
        until TempLatest.Next() = 0;
        CheckReceiptLotsCovered(PurchaseLine, TempLatest);
    end;

    local procedure CheckReceiptLotsCovered(PurchaseLine: Record "Purchase Line"; var TempLatest: Record "DOPSWHS Quality Order" temporary)
    var
        ReservationEntry: Record "Reservation Entry";
    begin
        // A line-level inspection (no lot) covers every lot of the line.
        TempLatest.Reset();
        TempLatest.SetRange("Lot No.", '');
        TempLatest.SetRange("Serial No.", '');
        if not TempLatest.IsEmpty() then begin
            TempLatest.Reset();
            exit;
        end;
        TempLatest.Reset();
        SetPurchaseLineTrackingFilter(ReservationEntry, PurchaseLine);
        ReservationEntry.SetFilter("Lot No.", '<>%1', '');
        ReservationEntry.SetFilter("Qty. to Handle (Base)", '<>0');
        ReservationEntry.SetLoadFields("Lot No.");
        if ReservationEntry.FindSet() then
            repeat
                TempLatest.SetRange("Lot No.", ReservationEntry."Lot No.");
                if TempLatest.IsEmpty() then
                    Error(ReceiptLotNotInspectedErr, ReservationEntry."Lot No.", PurchaseLine."No.", PurchaseLine."Document No.", PurchaseLine."Line No.");
            until ReservationEntry.Next() = 0;
        TempLatest.Reset();
    end;

    /// <summary>
    /// Unconsumed, not closed quality orders of a purchase line: orders created
    /// for the line, plus terminal/manual orders that only name the purchase
    /// order or warehouse receipt and the item. LatestOnly keeps the newest
    /// order per lot/serial (a re-inspection supersedes the earlier result).
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    local procedure CollectReceiptOrders(PurchaseLine: Record "Purchase Line"; WhseDocumentNo: Code[20]; LatestOnly: Boolean; var TempOrders: Record "DOPSWHS Quality Order" temporary)
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        TempOrders.Reset();
        TempOrders.DeleteAll();
        QualityOrder.SetCurrentKey("Source Table No.", "Source Subtype", "Source No.", "Source Line No.");
        QualityOrder.SetRange("Source Table No.", Database::"Purchase Line");
        QualityOrder.SetRange("Source Subtype", PurchaseLine."Document Type".AsInteger());
        QualityOrder.SetRange("Source No.", PurchaseLine."Document No.");
        QualityOrder.SetRange("Source Line No.", PurchaseLine."Line No.");
        QualityOrder.SetRange("Posted Document No.", '');
        QualityOrder.SetFilter(Status, '<>%1', QualityOrder.Status::Closed);
        AddOrders(QualityOrder, LatestOnly, TempOrders);

        QualityOrder.Reset();
        QualityOrder.SetCurrentKey("Source Type", "Source No.");
        QualityOrder.SetRange("Source Type", QualityOrder."Source Type"::Receipt);
        if WhseDocumentNo <> '' then
            QualityOrder.SetFilter("Source No.", '%1|%2', PurchaseLine."Document No.", WhseDocumentNo)
        else
            QualityOrder.SetRange("Source No.", PurchaseLine."Document No.");
        QualityOrder.SetRange("Source Table No.", 0);
        QualityOrder.SetRange("Item No.", PurchaseLine."No.");
        QualityOrder.SetRange("Posted Document No.", '');
        QualityOrder.SetFilter(Status, '<>%1', QualityOrder.Status::Closed);
        AddOrders(QualityOrder, LatestOnly, TempOrders);
    end;

    local procedure AddOrders(var QualityOrder: Record "DOPSWHS Quality Order"; LatestOnly: Boolean; var TempOrders: Record "DOPSWHS Quality Order" temporary)
    begin
        if QualityOrder.FindSet() then
            repeat
                if not LatestOnly then begin
                    if not TempOrders.Get(QualityOrder."No.") then begin
                        TempOrders := QualityOrder;
                        TempOrders.Insert();
                    end;
                end else begin
                    TempOrders.Reset();
                    TempOrders.SetRange("Lot No.", QualityOrder."Lot No.");
                    TempOrders.SetRange("Serial No.", QualityOrder."Serial No.");
                    if TempOrders.FindFirst() then begin
                        if IsNewer(QualityOrder, TempOrders) then begin
                            TempOrders.Delete();
                            TempOrders := QualityOrder;
                            TempOrders.Insert();
                        end;
                    end else begin
                        TempOrders := QualityOrder;
                        TempOrders.Insert();
                    end;
                end;
            until QualityOrder.Next() = 0;
        TempOrders.Reset();
    end;

    local procedure IsNewer(Candidate: Record "DOPSWHS Quality Order"; Current: Record "DOPSWHS Quality Order"): Boolean
    begin
        if Candidate."Created DateTime" <> Current."Created DateTime" then
            exit(Candidate."Created DateTime" > Current."Created DateTime");
        exit(Candidate."No." > Current."No.");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterPurchRcptLineInsert', '', false, false)]
    local procedure HandleReceivedPurchaseLine(PurchaseLine: Record "Purchase Line"; var PurchRcptLine: Record "Purch. Rcpt. Line"; ItemLedgShptEntryNo: Integer; WhseShip: Boolean; WhseReceive: Boolean; CommitIsSupressed: Boolean; PurchInvHeader: Record "Purch. Inv. Header"; var TempTrackingSpecification: Record "Tracking Specification" temporary; PurchRcptHeader: Record "Purch. Rcpt. Header"; TempWhseRcptHeader: Record "Warehouse Receipt Header"; xPurchLine: Record "Purchase Line"; var TempPurchLineGlobal: Record "Purchase Line" temporary)
    var
        QualityRule: Record "DOPSWHS Quality Rule";
        WhseDocumentNo: Code[20];
    begin
        if PurchRcptLine.IsTemporary() then
            exit;
        if (PurchRcptLine.Type <> PurchRcptLine.Type::Item) or (PurchRcptLine.Quantity <= 0) then
            exit;
        if PurchaseLine."Document Type" <> PurchaseLine."Document Type"::Order then
            exit;
        if not ReceiptGateEnabled() then
            exit;
        if not FindRule(Enum::"DOPSWHS Quality Rule Source"::"Purchase Receipt", PurchRcptLine."Location Code", PurchRcptLine."No.", PurchRcptLine."Buy-from Vendor No.", QualityRule) then
            exit;
        if WhseReceive then
            WhseDocumentNo := TempWhseRcptHeader."No.";
        // No errors from here on: within a warehouse receipt they would be
        // swallowed by the posting policy and only hide the real outcome.
        case QualityRule.Timing of
            QualityRule.Timing::"Before Posting":
                ConsumeReceiptOrders(PurchaseLine, PurchRcptLine, WhseDocumentNo);
            QualityRule.Timing::"After Posting":
                CreateOrdersForReceivedLine(PurchaseLine, PurchRcptLine, WhseDocumentNo);
        end;
    end;

    /// <summary>
    /// Stamps the decided inspections of the line with the receipt. A failed
    /// line-level inspection is tied to the lots/serials actually received (one
    /// order per further lot) so the quality hold can block exactly that stock.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RIM')]
    local procedure ConsumeReceiptOrders(PurchaseLine: Record "Purchase Line"; PurchRcptLine: Record "Purch. Rcpt. Line"; WhseDocumentNo: Code[20])
    var
        TempOrders: Record "DOPSWHS Quality Order" temporary;
        QualityOrder: Record "DOPSWHS Quality Order";
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
    begin
        CollectReceiptOrders(PurchaseLine, WhseDocumentNo, false, TempOrders);
        TempOrders.SetFilter(Status, '%1|%2', TempOrders.Status::Passed, TempOrders.Status::Failed);
        if not TempOrders.FindSet() then
            exit;
        repeat
            QualityOrder.Get(TempOrders."No.");
            QualityOrder."Posted Document No." := PurchRcptLine."Document No.";
            if (QualityOrder.Status = QualityOrder.Status::Failed) and
               (QualityOrder."Lot No." = '') and (QualityOrder."Serial No." = '')
            then
                AssignReceivedTracking(QualityOrder, PurchRcptLine);
            QualityOrder.Modify(true);
            QualityLotHold.ApplyHold(QualityOrder);
        until TempOrders.Next() = 0;
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RIM')]
    local procedure AssignReceivedTracking(var QualityOrder: Record "DOPSWHS Quality Order"; PurchRcptLine: Record "Purch. Rcpt. Line")
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        Item: Record Item;
        First: Boolean;
    begin
        SetReceiptEntryFilter(ItemLedgerEntry, PurchRcptLine);
        ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
        if ItemLedgerEntry.IsEmpty() then begin
            ItemLedgerEntry.SetRange("Lot No.");
            ItemLedgerEntry.SetFilter("Serial No.", '<>%1', '');
        end;
        if not ItemLedgerEntry.FindSet() then
            exit;
        Item.SetLoadFields("Base Unit of Measure");
        Item.Get(PurchRcptLine."No.");
        First := true;
        repeat
            if First then begin
                QualityOrder."Variant Code" := ItemLedgerEntry."Variant Code";
                QualityOrder."Lot No." := ItemLedgerEntry."Lot No.";
                QualityOrder."Serial No." := ItemLedgerEntry."Serial No.";
                QualityOrder.Quantity := ItemLedgerEntry.Quantity;
                QualityOrder."Unit of Measure Code" := Item."Base Unit of Measure";
                First := false;
            end else
                CopyResultForTracking(QualityOrder, ItemLedgerEntry, Item."Base Unit of Measure");
        until ItemLedgerEntry.Next() = 0;
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RIM')]
    local procedure CopyResultForTracking(SourceOrder: Record "DOPSWHS Quality Order"; ItemLedgerEntry: Record "Item Ledger Entry"; BaseUomCode: Code[10])
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
    begin
        QualityOrder := SourceOrder;
        QualityOrder."No." := QualityMgmt.GetNextOrderNo();
        QualityOrder."Variant Code" := ItemLedgerEntry."Variant Code";
        QualityOrder."Lot No." := ItemLedgerEntry."Lot No.";
        QualityOrder."Serial No." := ItemLedgerEntry."Serial No.";
        QualityOrder.Quantity := ItemLedgerEntry.Quantity;
        QualityOrder."Unit of Measure Code" := BaseUomCode;
        QualityOrder."Sample Size" := QualityMgmt.GetSampleSize(ItemLedgerEntry.Quantity);
        QualityOrder."Created DateTime" := CurrentDateTime();
        QualityOrder.Insert(true);
        QualityLotHold.ApplyHold(QualityOrder);
    end;

    /// <summary>"After Posting" rule: one open inspection per received lot/serial (or per line when untracked).</summary>
    local procedure CreateOrdersForReceivedLine(PurchaseLine: Record "Purchase Line"; PurchRcptLine: Record "Purch. Rcpt. Line"; WhseDocumentNo: Code[20])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        Item: Record Item;
        QualityOrder: Record "DOPSWHS Quality Order";
        LpNo: Code[20];
    begin
        Item.SetLoadFields("Base Unit of Measure");
        if not Item.Get(PurchRcptLine."No.") then
            exit;
        LpNo := WhseReceiptLineLp(WhseDocumentNo, PurchaseLine);
        SetReceiptEntryFilter(ItemLedgerEntry, PurchRcptLine);
        if ItemLedgerEntry.FindSet() then
            repeat
                CreateOrder(
                    QualityOrder."Source Type"::Receipt, Database::"Purchase Line", PurchaseLine."Document Type".AsInteger(),
                    PurchaseLine."Document No.", PurchaseLine."Line No.", WhseDocumentNo, PurchRcptLine."Document No.",
                    PurchRcptLine."No.", ItemLedgerEntry."Variant Code", ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.",
                    ItemLedgerEntry.Quantity, Item."Base Unit of Measure", ItemLedgerEntry."Location Code", PurchRcptLine."Bin Code",
                    LpNo, PurchRcptLine."Buy-from Vendor No.");
            until ItemLedgerEntry.Next() = 0;
    end;

    local procedure SetReceiptEntryFilter(var ItemLedgerEntry: Record "Item Ledger Entry"; PurchRcptLine: Record "Purch. Rcpt. Line")
    begin
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Document No.");
        ItemLedgerEntry.SetRange("Document No.", PurchRcptLine."Document No.");
        ItemLedgerEntry.SetRange("Document Type", ItemLedgerEntry."Document Type"::"Purchase Receipt");
        ItemLedgerEntry.SetRange("Document Line No.", PurchRcptLine."Line No.");
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Purchase);
        ItemLedgerEntry.SetRange("Item No.", PurchRcptLine."No.");
        ItemLedgerEntry.SetFilter(Quantity, '>0');
    end;

    local procedure WhseReceiptLineLp(WhseDocumentNo: Code[20]; PurchaseLine: Record "Purchase Line"): Code[20]
    var
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
    begin
        if WhseDocumentNo = '' then
            exit('');
        WarehouseReceiptLine.SetLoadFields("DOPSWHS LP No.");
        WarehouseReceiptLine.SetRange("No.", WhseDocumentNo);
        WarehouseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WarehouseReceiptLine.SetRange("Source Subtype", PurchaseLine."Document Type".AsInteger());
        WarehouseReceiptLine.SetRange("Source No.", PurchaseLine."Document No.");
        WarehouseReceiptLine.SetRange("Source Line No.", PurchaseLine."Line No.");
        if WarehouseReceiptLine.FindFirst() then
            exit(WarehouseReceiptLine."DOPSWHS LP No.");
        exit('');
    end;

    // -------------------------------------------------------------------------
    // INV-009 assembly final inspection gate
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Assembly-Post", 'OnBeforePost', '', false, false)]
    local procedure CheckAssemblyFinalInspection(var AssemblyHeader: Record "Assembly Header")
    var
        QualityRule: Record "DOPSWHS Quality Rule";
    begin
        if AssemblyHeader.IsTemporary() then
            exit;
        if (AssemblyHeader."Document Type" <> AssemblyHeader."Document Type"::Order) or (AssemblyHeader."Quantity to Assemble" = 0) then
            exit;
        if not AssemblyGateEnabled() then
            exit;
        if not FindRule(Enum::"DOPSWHS Quality Rule Source"::"Assembly Output", AssemblyHeader."Location Code", AssemblyHeader."Item No.", '', QualityRule) then
            exit;
        CheckFinalInspection(AssemblyHeader);
    end;

    /// <summary>
    /// The latest final inspection per output lot/serial must be passed, or
    /// failed with an executed "Accept with Deviation" decision. A rejected
    /// output is reworked and re-inspected (Rework decision) before posting.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    procedure CheckFinalInspection(AssemblyHeader: Record "Assembly Header")
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        TempLatest: Record "DOPSWHS Quality Order" temporary;
    begin
        SetFinalInspectionFilter(QualityOrder, AssemblyHeader);
        AddOrders(QualityOrder, true, TempLatest);
        if not TempLatest.FindSet() then
            Error(FinalInspectionRequiredErr, AssemblyHeader."No.", AssemblyHeader."Item No.");
        repeat
            if TempLatest.IsUndecided() then
                Error(FinalInspectionOpenErr, AssemblyHeader."No.", TempLatest."No.");
            if (TempLatest.Status = TempLatest.Status::Failed) and
               not (TempLatest."Decision Executed" and (TempLatest.Decision = TempLatest.Decision::"Accept with Deviation"))
            then
                Error(FinalInspectionRejectedErr, AssemblyHeader."No.", TempLatest."No.");
        until TempLatest.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Assembly-Post", 'OnPostOnAfterPostedAssemblyHeaderInsert', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RM')]
    local procedure ConsumeFinalInspections(AssemblyHeader: Record "Assembly Header"; var PostedAssemblyHeader: Record "Posted Assembly Header")
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        OrderNos: List of [Code[20]];
        OrderNo: Code[20];
    begin
        if AssemblyHeader.IsTemporary() then
            exit;
        if not AssemblyGateEnabled() then
            exit;
        SetFinalInspectionFilter(QualityOrder, AssemblyHeader);
        QualityOrder.SetFilter(Status, '%1|%2', QualityOrder.Status::Passed, QualityOrder.Status::Failed);
        QualityOrder.SetLoadFields("No.");
        if QualityOrder.FindSet() then
            repeat
                OrderNos.Add(QualityOrder."No.");
            until QualityOrder.Next() = 0;
        QualityOrder.SetLoadFields();
        foreach OrderNo in OrderNos do begin
            QualityOrder.Get(OrderNo);
            QualityOrder."Posted Document No." := PostedAssemblyHeader."No.";
            QualityOrder.Modify(true);
        end;
    end;

    local procedure SetFinalInspectionFilter(var QualityOrder: Record "DOPSWHS Quality Order"; AssemblyHeader: Record "Assembly Header")
    begin
        QualityOrder.Reset();
        QualityOrder.SetCurrentKey("Source Table No.", "Source Subtype", "Source No.", "Source Line No.");
        QualityOrder.SetRange("Source Table No.", Database::"Assembly Header");
        QualityOrder.SetRange("Source Subtype", AssemblyHeader."Document Type".AsInteger());
        QualityOrder.SetRange("Source No.", AssemblyHeader."No.");
        QualityOrder.SetRange("Source Line No.", 0);
        QualityOrder.SetRange("Item No.", AssemblyHeader."Item No.");
        QualityOrder.SetRange("Posted Document No.", '');
        QualityOrder.SetFilter(Status, '<>%1', QualityOrder.Status::Closed);
    end;

    // -------------------------------------------------------------------------
    // Creating quality orders from documents (page actions)
    // -------------------------------------------------------------------------

    /// <summary>Creates inspections for the receipt lines in the scope of a "Before Posting" rule; returns the number created.</summary>
    procedure CreateOrdersForWhseReceipt(WarehouseReceiptHeader: Record "Warehouse Receipt Header"): Integer
    var
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PurchaseLine: Record "Purchase Line";
        AllLines: Boolean;
        Created: Integer;
        Qty: Decimal;
    begin
        AllLines := not AnyWhseReceiptLineInScope(WarehouseReceiptHeader);
        if AllLines then
            if not (GuiAllowed() and Confirm(NoRuleCreateAllQst, false)) then
                exit(0);
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WarehouseReceiptLine.SetRange("Source Subtype", PurchaseLine."Document Type"::Order.AsInteger());
        WarehouseReceiptLine.SetFilter("Qty. Outstanding", '>0');
        if WarehouseReceiptLine.FindSet() then
            repeat
                if PurchaseLine.Get(PurchaseLine."Document Type"::Order, WarehouseReceiptLine."Source No.", WarehouseReceiptLine."Source Line No.") then
                    if AllLines or PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then begin
                        Qty := WarehouseReceiptLine."Qty. to Receive";
                        if Qty <= 0 then
                            Qty := WarehouseReceiptLine."Qty. Outstanding";
                        Created += CreateOrdersForPurchaseLine(
                            PurchaseLine, WarehouseReceiptHeader."No.", Qty, WarehouseReceiptLine."Unit of Measure Code",
                            WarehouseReceiptLine."Location Code", WarehouseReceiptLine."Bin Code", WarehouseReceiptLine."DOPSWHS LP No.");
                    end;
            until WarehouseReceiptLine.Next() = 0;
        exit(Created);
    end;

    /// <summary>Creates inspections for the purchase order lines in the scope of a "Before Posting" rule; returns the number created.</summary>
    procedure CreateOrdersForPurchaseOrder(PurchaseHeader: Record "Purchase Header"): Integer
    var
        PurchaseLine: Record "Purchase Line";
        AllLines: Boolean;
        Created: Integer;
        Qty: Decimal;
    begin
        PurchaseHeader.TestField("Document Type", PurchaseHeader."Document Type"::Order);
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        PurchaseLine.SetFilter("Outstanding Quantity", '>0');
        AllLines := true;
        if PurchaseLine.FindSet() then
            repeat
                if PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then
                    AllLines := false;
            until (PurchaseLine.Next() = 0) or not AllLines;
        if AllLines then
            if not (GuiAllowed() and Confirm(NoRuleCreateAllQst, false)) then
                exit(0);
        if PurchaseLine.FindSet() then
            repeat
                if AllLines or PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then begin
                    Qty := PurchaseLine."Qty. to Receive";
                    if Qty <= 0 then
                        Qty := PurchaseLine."Outstanding Quantity";
                    Created += CreateOrdersForPurchaseLine(
                        PurchaseLine, '', Qty, PurchaseLine."Unit of Measure Code", PurchaseLine."Location Code", PurchaseLine."Bin Code", '');
                end;
            until PurchaseLine.Next() = 0;
        exit(Created);
    end;

    local procedure AnyWhseReceiptLineInScope(WarehouseReceiptHeader: Record "Warehouse Receipt Header"): Boolean
    var
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PurchaseLine: Record "Purchase Line";
    begin
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WarehouseReceiptLine.SetRange("Source Subtype", PurchaseLine."Document Type"::Order.AsInteger());
        WarehouseReceiptLine.SetFilter("Qty. Outstanding", '>0');
        if WarehouseReceiptLine.FindSet() then
            repeat
                if PurchaseLine.Get(PurchaseLine."Document Type"::Order, WarehouseReceiptLine."Source No.", WarehouseReceiptLine."Source Line No.") then
                    if PurchaseLineInScope(PurchaseLine, Enum::"DOPSWHS Quality Insp. Timing"::"Before Posting") then
                        exit(true);
            until WarehouseReceiptLine.Next() = 0;
        exit(false);
    end;

    /// <summary>
    /// One inspection per lot already assigned to the line (item tracking), or one
    /// for the whole line. Lines/lots that already have an open or decided
    /// inspection for the coming receipt are skipped.
    /// </summary>
    local procedure CreateOrdersForPurchaseLine(PurchaseLine: Record "Purchase Line"; WhseDocumentNo: Code[20]; Qty: Decimal; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20]; LpNo: Code[20]) Created: Integer
    var
        ReservationEntry: Record "Reservation Entry";
        Item: Record Item;
        QualityOrder: Record "DOPSWHS Quality Order";
        LotQty: Dictionary of [Code[50], Decimal];
        Lots: List of [Code[50]];
        LotNo: Code[50];
    begin
        SetPurchaseLineTrackingFilter(ReservationEntry, PurchaseLine);
        ReservationEntry.SetFilter("Lot No.", '<>%1', '');
        ReservationEntry.SetLoadFields("Lot No.", "Quantity (Base)");
        if ReservationEntry.FindSet() then
            repeat
                if not LotQty.ContainsKey(ReservationEntry."Lot No.") then begin
                    LotQty.Add(ReservationEntry."Lot No.", 0);
                    Lots.Add(ReservationEntry."Lot No.");
                end;
                LotQty.Set(ReservationEntry."Lot No.", LotQty.Get(ReservationEntry."Lot No.") + Abs(ReservationEntry."Quantity (Base)"));
            until ReservationEntry.Next() = 0;

        if Lots.Count() > 0 then begin
            Item.SetLoadFields("Base Unit of Measure");
            Item.Get(PurchaseLine."No.");
            foreach LotNo in Lots do
                if not ReceiptOrderExists(PurchaseLine, WhseDocumentNo, LotNo) then begin
                    CreateOrder(
                        QualityOrder."Source Type"::Receipt, Database::"Purchase Line", PurchaseLine."Document Type".AsInteger(),
                        PurchaseLine."Document No.", PurchaseLine."Line No.", WhseDocumentNo, '',
                        PurchaseLine."No.", PurchaseLine."Variant Code", LotNo, '', LotQty.Get(LotNo), Item."Base Unit of Measure",
                        LocationCode, BinCode, LpNo, PurchaseLine."Buy-from Vendor No.");
                    Created += 1;
                end;
            exit(Created);
        end;

        if ReceiptOrderExists(PurchaseLine, WhseDocumentNo, '') then
            exit(0);
        CreateOrder(
            QualityOrder."Source Type"::Receipt, Database::"Purchase Line", PurchaseLine."Document Type".AsInteger(),
            PurchaseLine."Document No.", PurchaseLine."Line No.", WhseDocumentNo, '',
            PurchaseLine."No.", PurchaseLine."Variant Code", '', '', Qty, UomCode,
            LocationCode, BinCode, LpNo, PurchaseLine."Buy-from Vendor No.");
        exit(1);
    end;

    local procedure ReceiptOrderExists(PurchaseLine: Record "Purchase Line"; WhseDocumentNo: Code[20]; LotNo: Code[50]): Boolean
    var
        TempOrders: Record "DOPSWHS Quality Order" temporary;
    begin
        CollectReceiptOrders(PurchaseLine, WhseDocumentNo, false, TempOrders);
        TempOrders.SetRange("Lot No.", LotNo);
        exit(not TempOrders.IsEmpty());
    end;

    local procedure SetPurchaseLineTrackingFilter(var ReservationEntry: Record "Reservation Entry"; PurchaseLine: Record "Purchase Line")
    begin
        ReservationEntry.Reset();
        ReservationEntry.SetRange("Source Type", Database::"Purchase Line");
        ReservationEntry.SetRange("Source Subtype", PurchaseLine."Document Type".AsInteger());
        ReservationEntry.SetRange("Source ID", PurchaseLine."Document No.");
        ReservationEntry.SetRange("Source Batch Name", '');
        ReservationEntry.SetRange("Source Prod. Order Line", 0);
        ReservationEntry.SetRange("Source Ref. No.", PurchaseLine."Line No.");
    end;

    /// <summary>Creates the final inspection of an assembly order (output lot/serial taken from its item tracking when unique).</summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    procedure CreateFinalInspection(AssemblyHeader: Record "Assembly Header"): Code[20]
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        LotNo: Code[50];
        SerialNo: Code[50];
        Qty: Decimal;
    begin
        AssemblyHeader.TestField("Document Type", AssemblyHeader."Document Type"::Order);
        AssemblyHeader.TestField("Item No.");
        SetFinalInspectionFilter(QualityOrder, AssemblyHeader);
        QualityOrder.SetFilter(Status, '%1|%2', QualityOrder.Status::Open, QualityOrder.Status::InProgress);
        if QualityOrder.FindFirst() then
            Error(FinalInspectionExistsErr, QualityOrder."No.", AssemblyHeader."No.");
        Qty := AssemblyHeader."Quantity to Assemble";
        if Qty <= 0 then
            Qty := AssemblyHeader."Remaining Quantity";
        UniqueTracking(Database::"Assembly Header", AssemblyHeader."Document Type".AsInteger(), AssemblyHeader."No.", 0, LotNo, SerialNo);
        exit(
            CreateOrder(
                QualityOrder."Source Type"::Assembly, Database::"Assembly Header", AssemblyHeader."Document Type".AsInteger(),
                AssemblyHeader."No.", 0, '', '',
                AssemblyHeader."Item No.", AssemblyHeader."Variant Code", LotNo, SerialNo, Qty, AssemblyHeader."Unit of Measure Code",
                AssemblyHeader."Location Code", AssemblyHeader."Bin Code", '', ''));
    end;

    /// <summary>INV-010: records a defect found on an assembly component line (lot/serial from its item tracking when unique).</summary>
    procedure CreateComponentInspection(AssemblyLine: Record "Assembly Line"): Code[20]
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        QualityDecisionMgmt: Codeunit "DOPSWHS Quality Decision Mgmt";
        LotNo: Code[50];
        SerialNo: Code[50];
        Qty: Decimal;
    begin
        AssemblyLine.TestField(Type, AssemblyLine.Type::Item);
        AssemblyLine.TestField("No.");
        Qty := AssemblyLine."Quantity to Consume";
        if Qty <= 0 then
            Qty := AssemblyLine."Remaining Quantity";
        UniqueTracking(Database::"Assembly Line", AssemblyLine."Document Type".AsInteger(), AssemblyLine."Document No.", AssemblyLine."Line No.", LotNo, SerialNo);
        exit(
            CreateOrder(
                QualityOrder."Source Type"::Assembly, Database::"Assembly Line", AssemblyLine."Document Type".AsInteger(),
                AssemblyLine."Document No.", AssemblyLine."Line No.", '', '',
                AssemblyLine."No.", AssemblyLine."Variant Code", LotNo, SerialNo, Qty, AssemblyLine."Unit of Measure Code",
                AssemblyLine."Location Code", AssemblyLine."Bin Code", '',
                QualityDecisionMgmt.FindLotVendor(AssemblyLine."No.", AssemblyLine."Variant Code", LotNo)));
    end;

    local procedure UniqueTracking(SourceType: Integer; SourceSubtype: Integer; SourceId: Code[20]; SourceRefNo: Integer; var LotNo: Code[50]; var SerialNo: Code[50])
    var
        ReservationEntry: Record "Reservation Entry";
    begin
        LotNo := '';
        SerialNo := '';
        ReservationEntry.SetRange("Source Type", SourceType);
        ReservationEntry.SetRange("Source Subtype", SourceSubtype);
        ReservationEntry.SetRange("Source ID", SourceId);
        ReservationEntry.SetRange("Source Batch Name", '');
        ReservationEntry.SetRange("Source Prod. Order Line", 0);
        ReservationEntry.SetRange("Source Ref. No.", SourceRefNo);
        ReservationEntry.SetLoadFields("Lot No.", "Serial No.");
        if not ReservationEntry.FindSet() then
            exit;
        LotNo := ReservationEntry."Lot No.";
        SerialNo := ReservationEntry."Serial No.";
        // A serial number identifies one unit: only a single tracking line names it.
        if ReservationEntry.Count() > 1 then
            SerialNo := '';
        repeat
            if ReservationEntry."Lot No." <> LotNo then begin
                LotNo := '';
                exit;
            end;
        until ReservationEntry.Next() = 0;
    end;

    /// <summary>
    /// Creates a quality order through codeunit "DOPSWHS Quality Mgmt" (numbering
    /// and result events), ties it to its source line and stock, and applies the
    /// quality hold to its lot/serial.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RIM')]
    procedure CreateOrder(SourceTypeOption: Integer; SourceTableNo: Integer; SourceSubtype: Integer; SourceNo: Code[20]; SourceLineNo: Integer; WhseDocumentNo: Code[20]; PostedDocumentNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; Qty: Decimal; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20]; LpNo: Code[20]; VendorNo: Code[20]): Code[20]
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
        OrderNo: Code[20];
    begin
        OrderNo := QualityMgmt.CreateOrder(SourceTypeOption, SourceNo, ItemNo, Qty, LocationCode, BinCode, LpNo);
        QualityOrder.Get(OrderNo);
        QualityOrder."Source Table No." := SourceTableNo;
        QualityOrder."Source Subtype" := SourceSubtype;
        QualityOrder."Source Line No." := SourceLineNo;
        QualityOrder."Whse. Document No." := WhseDocumentNo;
        QualityOrder."Posted Document No." := PostedDocumentNo;
        if VariantCode <> '' then
            QualityOrder."Variant Code" := VariantCode;
        if LotNo <> '' then
            QualityOrder."Lot No." := LotNo;
        if SerialNo <> '' then
            QualityOrder."Serial No." := SerialNo;
        QualityOrder."Unit of Measure Code" := UomCode;
        QualityOrder."Vendor No." := VendorNo;
        QualityOrder.Modify(true);
        QualityLotHold.ApplyHold(QualityOrder);
        exit(OrderNo);
    end;

    /// <summary>Opens the quality orders of a source document (line no. 0 = all lines).</summary>
    procedure ShowOrdersForSource(SourceTableNo: Integer; SourceSubtype: Integer; SourceNo: Code[20]; SourceLineNo: Integer)
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        QualityOrder.SetCurrentKey("Source Table No.", "Source Subtype", "Source No.", "Source Line No.");
        QualityOrder.SetRange("Source Table No.", SourceTableNo);
        QualityOrder.SetRange("Source Subtype", SourceSubtype);
        QualityOrder.SetRange("Source No.", SourceNo);
        if SourceLineNo <> 0 then
            QualityOrder.SetRange("Source Line No.", SourceLineNo);
        Page.Run(Page::"DOPSWHS Quality Orders", QualityOrder);
    end;

    /// <summary>Opens the quality orders of all purchase orders on a warehouse receipt.</summary>
    procedure ShowOrdersForWhseReceipt(WarehouseReceiptHeader: Record "Warehouse Receipt Header")
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        SourceNos: List of [Code[20]];
        SourceFilter: Text;
        SourceNo: Code[20];
    begin
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WarehouseReceiptLine.SetLoadFields("Source No.");
        if WarehouseReceiptLine.FindSet() then
            repeat
                if not SourceNos.Contains(WarehouseReceiptLine."Source No.") then
                    SourceNos.Add(WarehouseReceiptLine."Source No.");
            until WarehouseReceiptLine.Next() = 0;
        SourceFilter := WarehouseReceiptHeader."No.";
        foreach SourceNo in SourceNos do
            SourceFilter += '|' + SourceNo;
        QualityOrder.SetFilter("Source No.", SourceFilter);
        Page.Run(Page::"DOPSWHS Quality Orders", QualityOrder);
    end;

    local procedure TrackingCaption(QualityOrder: Record "DOPSWHS Quality Order"): Text
    begin
        if QualityOrder."Lot No." <> '' then
            exit(QualityOrder."Lot No.");
        if QualityOrder."Serial No." <> '' then
            exit(QualityOrder."Serial No.");
        exit('-');
    end;

    var
        ReceiptInspectionRequiredErr: Label 'Item %1 on purchase order %2, line %3 requires a quality inspection before it can be received. Create a quality order (Create Quality Orders) and record its result.', Comment = '%1 = item no., %2 = purchase order no., %3 = line no.';
        ReceiptInspectionOpenErr: Label 'Quality order %1 for item %2 (lot/serial %3) on purchase order %4 is not completed. The receipt is blocked until the quality inspection has a result.', Comment = '%1 = quality order no., %2 = item no., %3 = lot or serial no., %4 = purchase order no.';
        ReceiptLotNotInspectedErr: Label 'Lot %1 of item %2 on purchase order %3, line %4 has no quality inspection. Create a quality order for the lot before receiving it.', Comment = '%1 = lot no., %2 = item no., %3 = purchase order no., %4 = line no.';
        FinalInspectionRequiredErr: Label 'Assembly order %1 (item %2) requires a final quality inspection before it can be posted. Use Create Final Inspection and record the result.', Comment = '%1 = assembly order no., %2 = item no.';
        FinalInspectionOpenErr: Label 'Assembly order %1 cannot be posted: final quality inspection %2 is not completed.', Comment = '%1 = assembly order no., %2 = quality order no.';
        FinalInspectionRejectedErr: Label 'Assembly order %1 cannot be posted: final quality inspection %2 was rejected. Rework and re-inspect the output, or record and execute an Accept with Deviation decision.', Comment = '%1 = assembly order no., %2 = quality order no.';
        FinalInspectionExistsErr: Label 'Final inspection %1 for assembly order %2 is still open.', Comment = '%1 = quality order no., %2 = assembly order no.';
        NoRuleCreateAllQst: Label 'No quality inspection rule covers these lines. Do you want to create quality orders for all lines anyway?';
}
