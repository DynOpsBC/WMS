codeunit 72428 "DOPSWHS LP Propagation"
{
    // Carries DOPSWHS LP No. across the BC posting chain so the License Plate is visible
    // wherever stock moves: Whse Receipt/Shipment Header + posted twin, Purch Rcpt/Sales Shipment
    // lines, Item Ledger Entry and Value Entry. Mirrors the Warehouse Insight parity goal.
    //
    // Two propagation paths:
    //   (1) Synchronous helpers — called by DOPSWHS Shipment Mgmt / Receipt Mgmt where we already
    //       own the posting orchestration.
    //   (2) BC integration events — for Sales/Purchase posting and Item Jnl posting where we don't
    //       control the orchestration but need to capture the LP onto downstream ledger rows.
    Access = Public;
    // NEDEN: Aşağıdaki abonelikler BC'nin kayıt zincirinde (Purch.-Post, Item
    // Jnl.-Post Line...) kayıtlı satırlara LP numarası yazar. Terminal kullanıcısı
    // çoğu tenant'ta Team Member/Device lisanslıdır ve bu tablolara doğrudan
    // Modify hakkı yoktur; izin verilmezse LP'li mal kabul "Your license does
    // not grant ... Purch. Rcpt. Line: Modify" ile düşer (LP'siz kabulde bu kod
    // hiç çalışmadığı için sorun yalnız LP'li belgelerde görülüyordu).
    Permissions =
        tabledata "Item Ledger Entry" = RM,
        tabledata "Value Entry" = RM,
        tabledata "Warehouse Entry" = RM,
        tabledata "Purch. Rcpt. Line" = RM,
        tabledata "Sales Shipment Line" = RM,
        tabledata "Posted Whse. Receipt Header" = RM,
        tabledata "Posted Whse. Receipt Line" = RM,
        tabledata "Posted Whse. Shipment Header" = RM,
        tabledata "Posted Whse. Shipment Line" = RM,
        tabledata "Warehouse Receipt Header" = RM,
        tabledata "Warehouse Shipment Header" = RM;

    // =========================================================================
    // (1) Synchronous helpers — invoked from DOPSWHS Receipt/Shipment Mgmt
    // =========================================================================

    /// <summary>Sets the header-level DOPSWHS LP No. on the posted Whse Shipment Header by
    /// picking the first non-blank LP from any line. Idempotent.</summary>
    procedure StampPostedShipmentHeader(WhseShipmentNo: Code[20]; PostedShipmentNo: Code[20])
    var
        PostedHeader: Record "Posted Whse. Shipment Header";
        PostedLine: Record "Posted Whse. Shipment Line";
        Lp: Code[20];
    begin
        if PostedShipmentNo = '' then
            exit;
        if not PostedHeader.Get(PostedShipmentNo) then
            exit;
        if PostedHeader."DOPSWHS LP No." <> '' then
            exit;

        PostedLine.SetRange("No.", PostedShipmentNo);
        PostedLine.SetFilter("LP No.", '<>%1', '');
        if PostedLine.FindFirst() then
            Lp := PostedLine."LP No."
        else begin
            PostedLine.Reset();
            PostedLine.SetRange("Whse. Shipment No.", WhseShipmentNo);
            PostedLine.SetFilter("LP No.", '<>%1', '');
            if PostedLine.FindFirst() then
                Lp := PostedLine."LP No.";
        end;
        if Lp = '' then
            exit;
        PostedHeader."DOPSWHS LP No." := Lp;
        PostedHeader.Modify(true);
    end;

    /// <summary>
    /// Final, exact warehouse-shipment reconciliation. Sales-Post can clear or
    /// delete the working Warehouse Shipment Line before its final events run,
    /// so relying only on those events can leave the posted stock movement
    /// without an LP. The posted warehouse line survives and BC records its
    /// exact Item Ledger Entry relation; use that durable link to stamp the
    /// ledger and consume the selected physical LP exactly once.
    /// </summary>
    procedure ReconcilePostedWarehouseShipment(PostedWhseShipmentNo: Code[20])
    var
        PostedWhseShipmentLine: Record "Posted Whse. Shipment Line";
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        ItemLedgerEntry: Record "Item Ledger Entry";
        RelatedEntryFound: Boolean;
    begin
        if PostedWhseShipmentNo = '' then
            exit;

        PostedWhseShipmentLine.SetRange("No.", PostedWhseShipmentNo);
        PostedWhseShipmentLine.SetFilter("LP No.", '<>%1', '');
        if not PostedWhseShipmentLine.FindSet() then
            exit;
        repeat
            RelatedEntryFound := false;
            WhseItemEntryRelation.Reset();
            WhseItemEntryRelation.SetSourceFilter(
                Database::"Posted Whse. Shipment Line", 0,
                PostedWhseShipmentLine."No.", PostedWhseShipmentLine."Line No.", true);
            if WhseItemEntryRelation.FindSet() then
                repeat
                    if ItemLedgerEntry.Get(WhseItemEntryRelation."Item Entry No.") then
                        if (ItemLedgerEntry."Entry Type" = ItemLedgerEntry."Entry Type"::Sale) and
                           (ItemLedgerEntry.Quantity < 0)
                        then begin
                            ReconcileSalesEntry(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", true);
                            StampSalesShipmentLine(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", PostedWhseShipmentLine.SSCC);
                            RelatedEntryFound := true;
                        end;
                until WhseItemEntryRelation.Next() = 0;

            // Older BC versions may omit Whse. Item Entry Relation for a
            // warehouse shipment. Accept the fallback only when the durable
            // posted source/tracking identity resolves to exactly one sale.
            if not RelatedEntryFound then begin
                ItemLedgerEntry.Reset();
                ItemLedgerEntry.SetRange("Document No.", PostedWhseShipmentLine."Posted Source No.");
                ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Sale);
                ItemLedgerEntry.SetRange("Item No.", PostedWhseShipmentLine."Item No.");
                ItemLedgerEntry.SetRange("Variant Code", PostedWhseShipmentLine."Variant Code");
                ItemLedgerEntry.SetRange("Location Code", PostedWhseShipmentLine."Location Code");
                ItemLedgerEntry.SetFilter(Quantity, '<0');
                if ItemLedgerEntry.Count() <> 1 then
                    Error(
                        '%1 kayıtlı ambar sevkiyat satırı için satış stok hareketi kesin olarak bulunamadı. LP %2 düşürülmedi.',
                        PostedWhseShipmentLine."No.", PostedWhseShipmentLine."LP No.");
                ItemLedgerEntry.FindFirst();
                ReconcileSalesEntry(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", true);
                StampSalesShipmentLine(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", PostedWhseShipmentLine.SSCC);
            end;
        until PostedWhseShipmentLine.Next() = 0;
    end;

    local procedure StampSalesShipmentLine(ItemLedgerEntry: Record "Item Ledger Entry"; LpNo: Code[20]; Sscc: Code[18])
    var
        SalesShipmentLine: Record "Sales Shipment Line";
    begin
        if not SalesShipmentLine.Get(ItemLedgerEntry."Document No.", ItemLedgerEntry."Document Line No.") then
            exit;
        if (SalesShipmentLine."DOPSWHS LP No." = LpNo) and
           (SalesShipmentLine."DOPSWHS SSCC" = Sscc)
        then
            exit;
        SalesShipmentLine."DOPSWHS LP No." := LpNo;
        SalesShipmentLine."DOPSWHS SSCC" := Sscc;
        SalesShipmentLine.Modify(true);
    end;

    /// <summary>Sets the working Whse Shipment Header LP from any line that has one (mobile-side
    /// convenience — admins can see the carton attached to the shipment without drilling lines).</summary>
    procedure StampShipmentHeader(WhseShipmentNo: Code[20])
    var
        Header: Record "Warehouse Shipment Header";
        Line: Record "Warehouse Shipment Line";
    begin
        if WhseShipmentNo = '' then
            exit;
        if not Header.Get(WhseShipmentNo) then
            exit;
        if Header."DOPSWHS LP No." <> '' then
            exit;
        Line.SetRange("No.", WhseShipmentNo);
        Line.SetFilter("LP No.", '<>%1', '');
        if not Line.FindFirst() then
            exit;
        Header."DOPSWHS LP No." := Line."LP No.";
        Header.Modify(true);
    end;

    /// <summary>Mirror of StampPostedShipmentHeader for Whse Receipt Posted Whse Receipt.</summary>
    procedure StampPostedReceiptHeader(WhseReceiptNo: Code[20]; PostedReceiptNo: Code[20])
    var
        PostedHeader: Record "Posted Whse. Receipt Header";
        PostedLine: Record "Posted Whse. Receipt Line";
        SourceHeader: Record "Warehouse Receipt Header";
        Lp: Code[20];
    begin
        if PostedReceiptNo = '' then
            exit;
        if not PostedHeader.Get(PostedReceiptNo) then
            exit;
        if PostedHeader."DOPSWHS LP No." <> '' then
            exit;

        PostedLine.SetRange("No.", PostedReceiptNo);
        PostedLine.SetFilter("LP No.", '<>%1', '');
        if PostedLine.FindFirst() then
            Lp := PostedLine."LP No.";
        if (Lp = '') and (WhseReceiptNo <> '') then
            if SourceHeader.Get(WhseReceiptNo) then
                Lp := SourceHeader."DOPSWHS LP No.";
        if Lp = '' then
            exit;
        PostedHeader."DOPSWHS LP No." := Lp;
        PostedHeader.Modify(true);
    end;

    /// <summary>
    /// Stamps each posted receipt line from the exact LP line captured during receiving.
    /// A receipt may contain several LPs for the same item, so the header LP must never be
    /// copied blindly. Source receipt line + item + variant + lot + serial is the stable key.
    /// </summary>
    procedure StampPostedReceiptLines(WhseReceiptNo: Code[20]; PostedReceiptNo: Code[20])
    var
        PostedLine: Record "Posted Whse. Receipt Line";
        ResolvedLpNo: Code[20];
        SingleReceiptLpNo: Code[20];
        HasReceiptLpLines: Boolean;
    begin
        if PostedReceiptNo = '' then
            exit;
        SingleReceiptLpNo := ResolveSingleReceiptLpNo(WhseReceiptNo);
        HasReceiptLpLines := ReceiptHasLpLines(WhseReceiptNo);
        PostedLine.SetRange("No.", PostedReceiptNo);
        if PostedLine.FindSet(true) then
            repeat
                ResolvedLpNo := ResolvePostedReceiptLineLp(WhseReceiptNo, PostedLine);
                if ResolvedLpNo = '' then
                    ResolvedLpNo := SingleReceiptLpNo;

                if ResolvedLpNo <> '' then begin
                    if PostedLine."LP No." <> ResolvedLpNo then begin
                        PostedLine."LP No." := ResolvedLpNo;
                        PostedLine.Modify(true);
                    end;
                end else
                    // Multiple LPs exist but this line cannot be resolved uniquely.
                    // Blank is safer than attaching stock to the wrong physical pallet.
                    if HasReceiptLpLines and (PostedLine."LP No." <> '') then begin
                        Clear(PostedLine."LP No.");
                        PostedLine.Modify(true);
                    end;
            until PostedLine.Next() = 0;
    end;

    /// <summary>
    /// Copies the receipt LP to the exact Item Ledger Entries created by warehouse receipt
    /// posting. BC records that exact link in Whse. Item Entry Relation; using it avoids
    /// guessing by item/lot when a receipt contains repeated lines.
    /// </summary>
    procedure StampPostedReceiptLedgerEntries(PostedReceiptNo: Code[20]; DefaultLpNo: Code[20])
    var
        PostedLine: Record "Posted Whse. Receipt Line";
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LineLpNo: Code[20];
    begin
        if PostedReceiptNo = '' then
            exit;

        PostedLine.SetRange("No.", PostedReceiptNo);
        if not PostedLine.FindSet() then
            exit;
        repeat
            LineLpNo := PostedLine."LP No.";
            if LineLpNo = '' then
                LineLpNo := DefaultLpNo;
            if LineLpNo <> '' then begin
                StampPostedReceiptWarehouseEntries(PostedLine, LineLpNo);
                WhseItemEntryRelation.Reset();
                WhseItemEntryRelation.SetSourceFilter(
                    Database::"Posted Whse. Receipt Line", 0,
                    PostedLine."No.", PostedLine."Line No.", true);
                if WhseItemEntryRelation.FindSet() then
                    repeat
                        if ItemLedgerEntry.Get(WhseItemEntryRelation."Item Entry No.") then
                            StampItemLedgerEntry(ItemLedgerEntry, LineLpNo);
                    until WhseItemEntryRelation.Next() = 0;
            end;
        until PostedLine.Next() = 0;
    end;

    local procedure ResolvePostedReceiptLineLp(WhseReceiptNo: Code[20]; PostedLine: Record "Posted Whse. Receipt Line"): Code[20]
    var
        ReceiptLineNo: Integer;
        LpNo: Code[20];
    begin
        ReceiptLineNo := PostedLine."Whse Receipt Line No.";
        if ReceiptLineNo = 0 then
            ReceiptLineNo := PostedLine."Line No.";
        LpNo := ResolveReceiptLpNo(
            WhseReceiptNo, ReceiptLineNo, PostedLine."Item No.", PostedLine."Variant Code",
            PostedLine."Lot No.", PostedLine."Serial No.");
        if LpNo <> '' then
            exit(LpNo);

        // Posted Whse. Receipt Line may not carry lot/serial even though the
        // resulting Warehouse Entry does. Source line + product is still safe
        // when every matching source LP row belongs to one physical LP.
        LpNo := ResolveUniqueReceiptLp(
            WhseReceiptNo, ReceiptLineNo, PostedLine."Item No.", PostedLine."Variant Code",
            PostedLine."Lot No.", PostedLine."Serial No.", false);
        if LpNo <> '' then
            exit(LpNo);

        // Some tenants also renumber posted receipt lines. Retry without the
        // source-line filter, first with and then without tracking identity.
        LpNo := ResolveReceiptLpNo(
            WhseReceiptNo, 0, PostedLine."Item No.", PostedLine."Variant Code",
            PostedLine."Lot No.", PostedLine."Serial No.");
        if LpNo <> '' then
            exit(LpNo);
        exit(ResolveUniqueReceiptLp(
            WhseReceiptNo, 0, PostedLine."Item No.", PostedLine."Variant Code",
            PostedLine."Lot No.", PostedLine."Serial No.", false));
    end;

    /// <summary>
    /// Resolves one physical LP from the receipt-line identity captured on DOPSWHS LP Line.
    /// If more than one LP matches the same identity, the result is intentionally blank.
    /// </summary>
    procedure ResolveReceiptLpNo(WhseReceiptNo: Code[20]; WhseReceiptLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]): Code[20]
    begin
        exit(ResolveUniqueReceiptLp(
            WhseReceiptNo, WhseReceiptLineNo, ItemNo, VariantCode,
            LotNo, SerialNo, true));
    end;

    local procedure ResolveUniqueReceiptLp(WhseReceiptNo: Code[20]; WhseReceiptLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; MatchTracking: Boolean): Code[20]
    var
        LPLine: Record "DOPSWHS LP Line";
        CandidateLpNo: Code[20];
    begin
        if WhseReceiptNo = '' then
            exit('');
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        LPLine.SetRange("Source Document No.", WhseReceiptNo);
        if WhseReceiptLineNo <> 0 then
            LPLine.SetRange("Source Document Line No.", WhseReceiptLineNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if MatchTracking then begin
            LPLine.SetRange("Lot No.", LotNo);
            LPLine.SetRange("Serial No.", SerialNo);
        end;
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if CandidateLpNo = '' then
                    CandidateLpNo := LPLine."LP No."
                else
                    if CandidateLpNo <> LPLine."LP No." then
                        exit('');
            until LPLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure ResolveSingleReceiptLpNo(WhseReceiptNo: Code[20]): Code[20]
    var
        LPLine: Record "DOPSWHS LP Line";
        CandidateLpNo: Code[20];
    begin
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        LPLine.SetRange("Source Document No.", WhseReceiptNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if CandidateLpNo = '' then
                    CandidateLpNo := LPLine."LP No."
                else
                    if CandidateLpNo <> LPLine."LP No." then
                        exit('');
            until LPLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure ReceiptHasLpLines(WhseReceiptNo: Code[20]): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        LPLine.SetRange("Source Document No.", WhseReceiptNo);
        LPLine.SetFilter(Quantity, '>0');
        exit(not LPLine.IsEmpty());
    end;

    /// <summary>
    /// Repairs an older Item Ledger Entry whose LP was not propagated during posting.
    /// First uses BC's exact warehouse/item relation; for legacy rows without that relation,
    /// it accepts only an unambiguous posted receipt match.
    /// </summary>
    procedure BackfillItemLedgerEntryLp(var ItemLedgerEntry: Record "Item Ledger Entry"): Boolean
    var
        LpNo: Code[20];
    begin
        if ItemLedgerEntry."DOPSWHS LP No." <> '' then
            exit(true);

        LpNo := ResolvePostedReceiptLpForItemEntry(ItemLedgerEntry);
        if LpNo = '' then
            LpNo := ResolveCurrentActiveLpForItemEntry(ItemLedgerEntry);
        if LpNo = '' then
            exit(false);

        StampItemLedgerEntry(ItemLedgerEntry, LpNo);
        StampRelatedReceiptWarehouseEntries(ItemLedgerEntry, LpNo);
        exit(ItemLedgerEntry."DOPSWHS LP No." <> '');
    end;

    local procedure ResolveCurrentActiveLpForItemEntry(ItemLedgerEntry: Record "Item Ledger Entry"): Code[20]
    var
        LPLine: Record "DOPSWHS LP Line";
        LPHeader: Record "DOPSWHS LP Header";
        CandidateLpNo: Code[20];
    begin
        if ItemLedgerEntry.Quantity <= 0 then
            exit('');
        LPLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        LPLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        LPLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
        LPLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if (LPHeader."Location Code" = ItemLedgerEntry."Location Code") and
                       (LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned])
                    then
                        if CandidateLpNo = '' then
                            CandidateLpNo := LPLine."LP No."
                        else
                            if CandidateLpNo <> LPLine."LP No." then
                                exit('');
            until LPLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure StampPostedReceiptWarehouseEntries(PostedLine: Record "Posted Whse. Receipt Line"; LpNo: Code[20])
    var
        WarehouseEntry: Record "Warehouse Entry";
    begin
        WarehouseEntry.SetRange("Whse. Document Type", WarehouseEntry."Whse. Document Type"::Receipt);
        WarehouseEntry.SetRange("Whse. Document No.", PostedLine."No.");
        WarehouseEntry.SetRange("Whse. Document Line No.", PostedLine."Line No.");
        WarehouseEntry.SetRange("Item No.", PostedLine."Item No.");
        // Posted receipt lines can have blank tracking while Warehouse Entry
        // carries the real lot/serial. The posted line already resolved to one
        // LP, so document line + item is the authoritative safe relation.
        if WarehouseEntry.FindSet(true) then
            repeat
                if WarehouseEntry."DOPSWHS LP No." <> LpNo then begin
                    WarehouseEntry."DOPSWHS LP No." := LpNo;
                    WarehouseEntry.Modify();
                end;
            until WarehouseEntry.Next() = 0;
    end;

    local procedure StampRelatedReceiptWarehouseEntries(ItemLedgerEntry: Record "Item Ledger Entry"; LpNo: Code[20])
    var
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        PostedLine: Record "Posted Whse. Receipt Line";
    begin
        if WhseItemEntryRelation.Get(ItemLedgerEntry."Entry No.") then
            if WhseItemEntryRelation."Source Type" = Database::"Posted Whse. Receipt Line" then
                if PostedLine.Get(
                     WhseItemEntryRelation."Source ID",
                     WhseItemEntryRelation."Source Ref. No.")
                then begin
                    StampPostedReceiptWarehouseEntries(PostedLine, LpNo);
                    exit;
                end;

        PostedLine.SetRange("Posted Source No.", ItemLedgerEntry."Document No.");
        PostedLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        PostedLine.SetRange("Location Code", ItemLedgerEntry."Location Code");
        PostedLine.SetTrackingFilterFromItemLedgEntry(ItemLedgerEntry);
        if PostedLine.FindSet() then
            repeat
                if (PostedLine."LP No." = LpNo) or (PostedLine."LP No." = '') then
                    StampPostedReceiptWarehouseEntries(PostedLine, LpNo);
            until PostedLine.Next() = 0;
    end;

    local procedure StampItemLedgerEntry(var ItemLedgerEntry: Record "Item Ledger Entry"; LpNo: Code[20])
    var
        ValueEntry: Record "Value Entry";
    begin
        if (LpNo = '') or (ItemLedgerEntry."DOPSWHS LP No." = LpNo) then
            exit;

        ItemLedgerEntry."DOPSWHS LP No." := LpNo;
        ItemLedgerEntry.Modify();

        ValueEntry.SetRange("Item Ledger Entry No.", ItemLedgerEntry."Entry No.");
        if ValueEntry.FindSet(true) then
            repeat
                if ValueEntry."DOPSWHS LP No." <> LpNo then begin
                    ValueEntry."DOPSWHS LP No." := LpNo;
                    ValueEntry.Modify();
                end;
            until ValueEntry.Next() = 0;
    end;

    local procedure ResolvePostedReceiptLpForItemEntry(ItemLedgerEntry: Record "Item Ledger Entry"): Code[20]
    var
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        PostedLine: Record "Posted Whse. Receipt Line";
        PostedHeader: Record "Posted Whse. Receipt Header";
        CandidateLpNo: Code[20];
        LineLpNo: Code[20];
    begin
        // Preferred path: BC's exact relation from the ledger entry to the posted
        // warehouse receipt line.
        if WhseItemEntryRelation.Get(ItemLedgerEntry."Entry No.") then
            if WhseItemEntryRelation."Source Type" = Database::"Posted Whse. Receipt Line" then
                if PostedLine.Get(
                     WhseItemEntryRelation."Source ID",
                     WhseItemEntryRelation."Source Ref. No.")
                then begin
                    LineLpNo := PostedLine."LP No.";
                    if (LineLpNo = '') and PostedHeader.Get(PostedLine."No.") then
                        LineLpNo := PostedHeader."DOPSWHS LP No.";
                    if LineLpNo <> '' then
                        exit(LineLpNo);
                end;

        // Legacy fallback: posted purchase receipt number + item + location +
        // tracking must resolve to one LP only. Ambiguous matches are not written.
        if ItemLedgerEntry."Document No." = '' then
            exit('');
        PostedLine.Reset();
        PostedLine.SetRange("Posted Source No.", ItemLedgerEntry."Document No.");
        PostedLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        PostedLine.SetRange("Location Code", ItemLedgerEntry."Location Code");
        PostedLine.SetTrackingFilterFromItemLedgEntry(ItemLedgerEntry);
        if not PostedLine.FindSet() then
            exit('');
        repeat
            LineLpNo := PostedLine."LP No.";
            if (LineLpNo = '') and PostedHeader.Get(PostedLine."No.") then
                LineLpNo := PostedHeader."DOPSWHS LP No.";
            if LineLpNo <> '' then begin
                if CandidateLpNo = '' then
                    CandidateLpNo := LineLpNo
                else
                    if CandidateLpNo <> LineLpNo then
                        exit('');
            end;
        until PostedLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    // =========================================================================
    // (2) BC integration event subscribers
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnAfterInsertItemLedgEntry', '', false, false)]
    local procedure CarryLpOntoItemLedgEntry(var ItemLedgerEntry: Record "Item Ledger Entry"; ItemJournalLine: Record "Item Journal Line")
    var
        Lp: Code[20];
    begin
        if ItemLedgerEntry."DOPSWHS LP No." <> '' then
            exit;
        Lp := ItemJournalLine."DOPSWHS LP No.";
        if Lp = '' then
            Lp := ResolveLpForItemJnlLine(ItemJournalLine);
        if Lp = '' then
            exit;
        ItemLedgerEntry."DOPSWHS LP No." := Lp;
        // OnAfterInsertItemLedgEntry fires AFTER Insert(true) and the base app does not re-write
        // the row, so an in-memory assignment is discarded without an explicit Modify. Persist it.
        ItemLedgerEntry.Modify();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnAfterInsertValueEntry', '', false, false)]
    local procedure CarryLpOntoValueEntry(var ValueEntry: Record "Value Entry"; ItemJournalLine: Record "Item Journal Line"; ItemLedgerEntry: Record "Item Ledger Entry")
    begin
        if ValueEntry."DOPSWHS LP No." <> '' then
            exit;
        if ItemLedgerEntry."DOPSWHS LP No." <> '' then begin
            ValueEntry."DOPSWHS LP No." := ItemLedgerEntry."DOPSWHS LP No.";
            // Same as the ILE case: the row is already inserted, so persist explicitly.
            ValueEntry.Modify();
        end;
    end;

    /// <summary>After Sales-Post completes, copy the LP from the originating Warehouse Shipment
    /// Line onto each Posted Sales Shipment Line. Posted line carries
    /// (Order No., Order Line No.) which lets us trace back to Whse Shipment Line.</summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", 'OnAfterPostSalesDoc', '', false, false)]
    local procedure CarryLpOntoPostedSalesShipment(
        var SalesHeader: Record "Sales Header";
        var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        SalesShptHdrNo: Code[20];
        RetRcpHdrNo: Code[20];
        SalesInvHdrNo: Code[20];
        SalesCrMemoHdrNo: Code[20];
        CommitIsSuppressed: Boolean;
        InvtPickPutaway: Boolean;
        var CustLedgerEntry: Record "Cust. Ledger Entry";
        WhseShip: Boolean;
        WhseReceiv: Boolean;
        PreviewMode: Boolean)
    var
        PostedShptLine: Record "Sales Shipment Line";
        WhseShptLine: Record "Warehouse Shipment Line";
    begin
        if (SalesShptHdrNo = '') or PreviewMode then
            exit;
        PostedShptLine.SetRange("Document No.", SalesShptHdrNo);
        if not PostedShptLine.FindSet(true) then
            exit;
        repeat
            if PostedShptLine."DOPSWHS LP No." = '' then begin
                WhseShptLine.SetRange("Source Type", Database::"Sales Line");
                WhseShptLine.SetRange("Source Subtype", SalesHeader."Document Type");
                WhseShptLine.SetRange("Source No.", PostedShptLine."Order No.");
                WhseShptLine.SetRange("Source Line No.", PostedShptLine."Order Line No.");
                WhseShptLine.SetFilter("LP No.", '<>%1', '');
                if WhseShptLine.FindFirst() then begin
                    PostedShptLine."DOPSWHS LP No." := WhseShptLine."LP No.";
                    PostedShptLine."DOPSWHS SSCC" := WhseShptLine.SSCC;
                    PostedShptLine.Modify(true);
                end;
            end;
        until PostedShptLine.Next() = 0;

    end;

    /// <summary>
    /// Runs before Sales-Post commits so the inventory posting and LP reduction are atomic.
    /// An ambiguous LP therefore stops the shipment without leaving inventory and LP out of sync.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", 'OnAfterFinalizePostingOnBeforeCommit', '', false, false)]
    local procedure ReconcileSalesLpBeforeCommit(
        var SalesHeader: Record "Sales Header";
        var SalesShipmentHeader: Record "Sales Shipment Header";
        var SalesInvoiceHeader: Record "Sales Invoice Header";
        var SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        var ReturnReceiptHeader: Record "Return Receipt Header";
        var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        var CommitIsSuppressed: Boolean;
        var PreviewMode: Boolean;
        WhseShip: Boolean;
        WhseReceive: Boolean;
        var EverythingInvoiced: Boolean)
    begin
        if PreviewMode or (SalesShipmentHeader."No." = '') then
            exit;
        ReconcileSalesLp(SalesShipmentHeader."No.", WhseShip);
    end;

    /// <summary>
    /// Reconciles the physical LP from the posted item-ledger lot/serial identity so inventory
    /// and LP contents stay equal. Warehouse shipments prefer their explicitly selected LP;
    /// direct sales fall back to an unambiguous active LP for the same item/lot/serial.
    /// </summary>
    local procedure ReconcileSalesLp(SalesShptHdrNo: Code[20]; WhseShip: Boolean)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        PostedShptLine: Record "Sales Shipment Line";
        PreferredLpNo: Code[20];
        AmbiguousLp: Boolean;
    begin
        ItemLedgerEntry.SetRange("Document No.", SalesShptHdrNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Sale);
        ItemLedgerEntry.SetFilter(Quantity, '<0');
        if not ItemLedgerEntry.FindSet(true) then
            exit;

        repeat
            if PostedShptLine.Get(SalesShptHdrNo, ItemLedgerEntry."Document Line No.") then begin
                Clear(PreferredLpNo);
                Clear(AmbiguousLp);
                // Whse.-Post Shipment invokes Sales-Post through a path where
                // WhseShip is false in some BC versions. Detect the actual
                // Warehouse Shipment Line instead of trusting that advisory
                // argument; this still runs before the inventory commit.
                PreferredLpNo := ResolveWarehouseShipmentLp(PostedShptLine, ItemLedgerEntry, AmbiguousLp);
                if AmbiguousLp then
                    Error(
                        '%1 maddesi, lot %2 için sevkiyatta birden fazla LP seçilmiş. LP miktarları güvenli biçimde düşürülemedi.',
                        ItemLedgerEntry."Item No.", ItemLedgerEntry."Lot No.");
                if PreferredLpNo <> '' then
                    ReconcileSalesEntry(ItemLedgerEntry, PreferredLpNo, true)
                else begin
                    if ItemLedgerEntry."DOPSWHS LP No." <> '' then
                        PreferredLpNo := ItemLedgerEntry."DOPSWHS LP No."
                    else
                        PreferredLpNo := PostedShptLine."DOPSWHS LP No.";
                    ReconcileSalesEntry(ItemLedgerEntry, PreferredLpNo, PreferredLpNo <> '');
                end;
            end;
        until ItemLedgerEntry.Next() = 0;
    end;

    local procedure ResolveWarehouseShipmentLp(PostedShptLine: Record "Sales Shipment Line"; ItemLedgerEntry: Record "Item Ledger Entry"; var Ambiguous: Boolean): Code[20]
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        CandidateLpNo: Code[20];
    begin
        Clear(Ambiguous);
        WhseShptLine.SetRange("Source Type", Database::"Sales Line");
        WhseShptLine.SetRange("Source No.", PostedShptLine."Order No.");
        WhseShptLine.SetRange("Source Line No.", PostedShptLine."Order Line No.");
        WhseShptLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        WhseShptLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        // Sales-Post can clear Qty. to Ship before the before-commit event is
        // raised. The warehouse line and its LP still identify the posted
        // source exactly, so filtering on that transient quantity made a
        // committed shipment skip LP consumption.
        WhseShptLine.SetFilter("LP No.", '<>%1', '');
        if WhseShptLine.FindSet() then
            repeat
                // A mobile lot override is authoritative when present. Blank
                // means BC item tracking owns the split, so keep it eligible.
                if (WhseShptLine."DOPSWHS Lot No." = '') or
                   (WhseShptLine."DOPSWHS Lot No." = ItemLedgerEntry."Lot No.")
                then
                    if CandidateLpNo = '' then
                        CandidateLpNo := WhseShptLine."LP No."
                    else
                        if CandidateLpNo <> WhseShptLine."LP No." then begin
                            Ambiguous := true;
                            exit('');
                        end;
            until WhseShptLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure ReconcileSalesEntry(var ItemLedgerEntry: Record "Item Ledger Entry"; PreferredLpNo: Code[20]; RequirePreferredLp: Boolean)
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        LPManagement: Codeunit "DOPSWHS LP Management";
        RequiredBaseQty: Decimal;
        AvailableBaseQty: Decimal;
        QtyPerUoM: Decimal;
        MatchingLineCount: Integer;
        CandidateAvailableBaseQty: Decimal;
        CandidateLPNo: Code[20];
        CandidateLineNo: Integer;
        ConsumptionReference: Code[40];
    begin
        RequiredBaseQty := Abs(ItemLedgerEntry.Quantity);
        if RequiredBaseQty = 0 then
            exit;
        Item.Get(ItemLedgerEntry."Item No.");

        if PreferredLpNo <> '' then
            LPHeader.SetRange("No.", PreferredLpNo);
        LPHeader.SetRange("Location Code", ItemLedgerEntry."Location Code");
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LPHeader."No.");
                LPLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
                LPLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
                LPLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
                LPLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
                if LPLine.FindSet() then
                    repeat
                        QtyPerUoM := 1;
                        if (LPLine."Unit of Measure" <> '') and
                           (LPLine."Unit of Measure" <> Item."Base Unit of Measure")
                        then begin
                            if ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                                QtyPerUoM := ItemUoM."Qty. per Unit of Measure"
                            else
                                QtyPerUoM := 0;
                        end;
                        AvailableBaseQty := Round(LPLine.Quantity * QtyPerUoM, 0.00001);
                        if (QtyPerUoM > 0) and (AvailableBaseQty > 0) then begin
                            MatchingLineCount += 1;
                            CandidateLPNo := LPLine."LP No.";
                            CandidateLineNo := LPLine."Line No.";
                            CandidateAvailableBaseQty := AvailableBaseQty;
                        end;
                    until LPLine.Next() = 0;
            until LPHeader.Next() = 0;

        // No matching active LP means a direct shipment came from loose stock.
        if (MatchingLineCount = 0) and (not RequirePreferredLp) then
            exit;
        if MatchingLineCount = 0 then
            Error(
                '%1 LP numarasında %2 maddesi, lot %3 için sevk edilebilir satır bulunamadı.',
                PreferredLpNo, ItemLedgerEntry."Item No.", ItemLedgerEntry."Lot No.");
        if MatchingLineCount > 1 then
            Error(
                '%1 maddesi, lot %2 için birden fazla LP eşleşti. Yanlış LP miktarının düşmemesi için sevkiyat durduruldu.',
                ItemLedgerEntry."Item No.", ItemLedgerEntry."Lot No.");
        if CandidateAvailableBaseQty + 0.00001 < RequiredBaseQty then
            Error(
                '%1 LP numarasında sevk için yeterli miktar yoktur. LP miktarı: %2, sevk miktarı: %3.',
                CandidateLPNo, CandidateAvailableBaseQty, RequiredBaseQty);

        ConsumptionReference := CopyStr(
            ItemLedgerEntry."Document No." + '#' + Format(ItemLedgerEntry."Entry No."),
            1, MaxStrLen(ConsumptionReference));
        LPManagement.ConsumeLineForShipment(
            CandidateLPNo, CandidateLineNo, RequiredBaseQty, ConsumptionReference);
        StampItemLedgerEntry(ItemLedgerEntry, CandidateLPNo);
    end;

    /// <summary>After Purch-Post completes, copy the LP from the originating Whse Receipt Header
    /// (`DOPSWHS LP No.` set during receive-with-LP) onto each Posted Purch Rcpt Line tied to
    /// the same purchase order. Best-effort: receipt-time scanned LP propagates to inventory.</summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterPostPurchaseDoc', '', false, false)]
    local procedure CarryLpOntoPostedPurchRcpt(var PurchaseHeader: Record "Purchase Header"; PurchRcpHdrNo: Code[20])
    var
        PostedRcptLine: Record "Purch. Rcpt. Line";
        WhseRcptHdr: Record "Warehouse Receipt Header";
        WhseRcptLine: Record "Warehouse Receipt Line";
        HeaderLp: Code[20];
    begin
        if PurchRcpHdrNo = '' then
            exit;
        // Find the originating Whse Receipt Header (if a receipt was used) via Whse Receipt Line.
        WhseRcptLine.SetRange("Source Type", Database::"Purchase Line");
        WhseRcptLine.SetRange("Source Subtype", PurchaseHeader."Document Type");
        WhseRcptLine.SetRange("Source No.", PurchaseHeader."No.");
        if WhseRcptLine.FindFirst() then begin
            HeaderLp := ResolveSingleReceiptLpNo(WhseRcptLine."No.");
            // Legacy receipts created before LP source metadata existed can
            // still use their single header LP. Never use it for a known
            // multi-LP receipt because it would corrupt every posted line.
            if (HeaderLp = '') and (not ReceiptHasLpLines(WhseRcptLine."No.")) then
                if WhseRcptHdr.Get(WhseRcptLine."No.") then
                    HeaderLp := WhseRcptHdr."DOPSWHS LP No.";
        end;
        if HeaderLp = '' then
            exit;
        PostedRcptLine.SetRange("Document No.", PurchRcpHdrNo);
        if not PostedRcptLine.FindSet(true) then
            exit;
        repeat
            if PostedRcptLine."DOPSWHS LP No." = '' then begin
                PostedRcptLine."DOPSWHS LP No." := HeaderLp;
                PostedRcptLine.Modify(true);
            end;
        until PostedRcptLine.Next() = 0;
    end;

    // =========================================================================
    // Lookup helpers
    // =========================================================================

    /// <summary>
    /// Walks the Item Journal Line context to find the originating warehouse document that captured the LP scan.
    /// Source priority: explicit Whse Activity Line LP, Whse Shipment Line LP, Whse Receipt Header LP.
    /// </summary>
    local procedure ResolveLpForItemJnlLine(ItemJnlLine: Record "Item Journal Line"): Code[20]
    var
        Lp: Code[20];
    begin
        // Sales-Post / Purch.-Post carry the originating ORDER no. on "Order No." while
        // "Document No." becomes the posted document no.; Movement/Production carry their working
        // no. on "Document No." (blank "Order No."). Try both keys so every flow resolves — the
        // "Document No." pass preserves the previous behavior, the "Order No." pass adds
        // shipping/receiving. First non-blank wins.
        Lp := ResolveLpBySourceNo(ItemJnlLine."Order No.", ItemJnlLine."Item No.");
        if Lp <> '' then
            exit(Lp);
        exit(ResolveLpBySourceNo(ItemJnlLine."Document No.", ItemJnlLine."Item No."));
    end;

    local procedure ResolveLpBySourceNo(SourceNo: Code[20]; ItemNo: Code[20]): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        Lp: Code[20];
    begin
        if SourceNo = '' then
            exit('');

        // Pick / PutAway Warehouse Activity Line
        WhseActivityLine.SetRange("Source No.", SourceNo);
        WhseActivityLine.SetRange("Item No.", ItemNo);
        WhseActivityLine.SetFilter("LP No.", '<>%1', '');
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."LP No.");

        // Whse Shipment Line (outbound)
        WhseShipmentLine.SetRange("Source No.", SourceNo);
        WhseShipmentLine.SetRange("Item No.", ItemNo);
        WhseShipmentLine.SetFilter("LP No.", '<>%1', '');
        if WhseShipmentLine.FindFirst() then
            exit(WhseShipmentLine."LP No.");

        // Receipt LP source lines (inbound). Header LP is only a legacy
        // fallback when no line-level source metadata exists.
        WhseReceiptLine.SetRange("Source No.", SourceNo);
        WhseReceiptLine.SetRange("Item No.", ItemNo);
        if WhseReceiptLine.FindFirst() then begin
            Lp := ResolveSingleReceiptLpNo(WhseReceiptLine."No.");
            if Lp <> '' then
                exit(Lp);
            if not ReceiptHasLpLines(WhseReceiptLine."No.") then
                if WhseReceiptHeader.Get(WhseReceiptLine."No.") then
                    exit(WhseReceiptHeader."DOPSWHS LP No.");
        end;

        exit('');
    end;

    // =========================================================================
    // (A) Warehouse Entry stamping — covers Pick/Put-away/Movement register-time
    // =========================================================================

    /// <summary>
    /// Carries the exact physical-inventory LP onto the warehouse journal line before BC registers
    /// it. Keeping the LP on the same posting line avoids ambiguous item/bin/lot matching when two
    /// LPs contain identical stock dimensions.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"WMS Management", 'OnAfterCreateWhseJnlLine', '', false, false)]
    local procedure CarryCountLpOntoWhseJnlLine(var WhseJournalLine: Record "Warehouse Journal Line"; ItemJournalLine: Record "Item Journal Line"; ToTransfer: Boolean)
    begin
        if ItemJournalLine."DOPSWHS LP No." = '' then
            exit;
        WhseJournalLine."DOPSWHS LP No." := ItemJournalLine."DOPSWHS LP No.";
    end;

    /// <summary>Stamps the LP onto each Warehouse Entry as it is registered (bin movements from
    /// pick/put-away/movement). Uses the OnBefore event so the assignment is persisted by the base
    /// Insert(true) with no Modify. The originating Warehouse Activity Line (carrying the scanned
    /// LP) still exists at this point.</summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Jnl.-Register Line", 'OnBeforeInsertWhseEntry', '', false, false)]
    local procedure CarryLpOntoWhseEntry(var WarehouseEntry: Record "Warehouse Entry"; var WarehouseJournalLine: Record "Warehouse Journal Line")
    var
        Lp: Code[20];
    begin
        if WarehouseEntry."DOPSWHS LP No." <> '' then
            exit;
        Lp := WarehouseJournalLine."DOPSWHS LP No.";
        if Lp = '' then
            Lp := ResolveLpForWhseEntry(WarehouseEntry);
        if Lp = '' then
            exit;
        WarehouseEntry."DOPSWHS LP No." := Lp;
    end;

    /// <summary>
    /// Resolves the LP for a Warehouse Entry. Priority mirrors ResolveLpForItemJnlLine:
    /// live Whse Activity Line LP, Whse Shipment Line LP, Whse Receipt Header LP.
    /// </summary>
    local procedure ResolveLpForWhseEntry(WhseEntry: Record "Warehouse Entry"): Code[20]
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        Lp: Code[20];
    begin
        // (a) Pick / Put-away / Movement: the working activity line (with its scanned LP) is still
        // present at OnBefore. Join on the shared source keys + item.
        if WhseEntry."Source No." <> '' then begin
            Lp := ResolveActivityLpForWhseEntry(WhseEntry, true);
            if Lp = '' then
                Lp := ResolveActivityLpForWhseEntry(WhseEntry, false);
            if Lp <> '' then
                exit(Lp);
        end;

        // (b) Outbound: the Warehouse Shipment Line carries the LP (keyed by whse document).
        if WhseEntry."Whse. Document Type" = WhseEntry."Whse. Document Type"::Shipment then begin
            WhseShipmentLine.SetRange("No.", WhseEntry."Whse. Document No.");
            WhseShipmentLine.SetRange("Line No.", WhseEntry."Whse. Document Line No.");
            WhseShipmentLine.SetFilter("LP No.", '<>%1', '');
            if WhseShipmentLine.FindFirst() then
                exit(WhseShipmentLine."LP No.");
        end;

        // (c) Inbound: resolve the physical LP by receipt line + lot/serial.
        // This is the point that previously stamped the header's first LP on
        // every lot and caused LP000063/H100795 to appear on H100796.
        if WhseEntry."Whse. Document Type" = WhseEntry."Whse. Document Type"::Receipt then begin
            Lp := ResolveReceiptLpNo(
                WhseEntry."Whse. Document No.", WhseEntry."Whse. Document Line No.",
                WhseEntry."Item No.", WhseEntry."Variant Code", WhseEntry."Lot No.", WhseEntry."Serial No.");
            if Lp <> '' then
                exit(Lp);
            Lp := ResolveSingleReceiptLpNo(WhseEntry."Whse. Document No.");
            if Lp <> '' then
                exit(Lp);
            if not ReceiptHasLpLines(WhseEntry."Whse. Document No.") then
                if WhseReceiptHeader.Get(WhseEntry."Whse. Document No.") then
                    exit(WhseReceiptHeader."DOPSWHS LP No.");
        end;

        exit('');
    end;

    local procedure ResolveActivityLpForWhseEntry(WhseEntry: Record "Warehouse Entry"; MatchSourceLine: Boolean): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        CandidateLpNo: Code[20];
    begin
        WhseActivityLine.SetRange("Source Type", WhseEntry."Source Type");
        WhseActivityLine.SetRange("Source Subtype", WhseEntry."Source Subtype");
        WhseActivityLine.SetRange("Source No.", WhseEntry."Source No.");
        if MatchSourceLine and (WhseEntry."Source Line No." <> 0) then
            WhseActivityLine.SetRange("Source Line No.", WhseEntry."Source Line No.");
        WhseActivityLine.SetRange("Item No.", WhseEntry."Item No.");
        WhseActivityLine.SetRange("Variant Code", WhseEntry."Variant Code");
        WhseActivityLine.SetRange("Lot No.", WhseEntry."Lot No.");
        WhseActivityLine.SetRange("Serial No.", WhseEntry."Serial No.");
        WhseActivityLine.SetRange("Bin Code", WhseEntry."Bin Code");
        WhseActivityLine.SetFilter("LP No.", '<>%1', '');
        if WhseActivityLine.FindSet() then
            repeat
                if CandidateLpNo = '' then
                    CandidateLpNo := WhseActivityLine."LP No."
                else
                    if CandidateLpNo <> WhseActivityLine."LP No." then
                        exit('');
            until WhseActivityLine.Next() = 0;
        exit(CandidateLpNo);
    end;
}
