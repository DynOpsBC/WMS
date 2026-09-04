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
        tabledata "Warehouse Shipment Header" = RM,
        tabledata "Warehouse Shipment Line" = R,
        tabledata "Registered Whse. Activity Line" = R,
        tabledata "Whse. Item Entry Relation" = R;

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
    /// Final, exact warehouse-shipment reconciliation for posted lines that carry
    /// an operator-selected LP. Sales-Post deletes a fully shipped working line
    /// before its before-commit event; the posted warehouse line survives and
    /// names the sales shipment it produced ("Posted Source No."). BC writes
    /// Whse. Item Entry Relation only for receipts, so the sale entries are
    /// resolved through that posted source document: every negative Sale entry
    /// of the same sales line (one per lot/serial split) is reconciled against
    /// the line's LP. ReconcileSalesEntry is idempotent per entry, so an entry
    /// the before-commit event already handled is only re-stamped, never
    /// consumed twice.
    /// </summary>
    procedure ReconcilePostedWarehouseShipment(PostedWhseShipmentNo: Code[20])
    var
        PostedWhseShipmentLine: Record "Posted Whse. Shipment Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if PostedWhseShipmentNo = '' then
            exit;

        PostedWhseShipmentLine.SetRange("No.", PostedWhseShipmentNo);
        PostedWhseShipmentLine.SetFilter("LP No.", '<>%1', '');
        if not PostedWhseShipmentLine.FindSet() then
            exit;
        repeat
            if not FindPostedSourceSaleEntries(PostedWhseShipmentLine, ItemLedgerEntry) then
                Error(
                    '%1 kayıtlı ambar sevkiyat satırı için satış stok hareketi bulunamadı. LP %2 düşürülmedi.',
                    PostedWhseShipmentLine."No.", PostedWhseShipmentLine."LP No.");
            repeat
                ReconcileSalesEntry(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", true);
                StampSalesShipmentLine(ItemLedgerEntry, PostedWhseShipmentLine."LP No.", PostedWhseShipmentLine.SSCC);
            until ItemLedgerEntry.Next() = 0;
        until PostedWhseShipmentLine.Next() = 0;
    end;

    /// <summary>
    /// Negative Sale entries of the sales shipment a posted warehouse line
    /// produced. Sales-Post keeps the sales line number on the posted shipment
    /// line and on the item ledger entry, so the source line pins the entries
    /// when the same item ships on several lines; the line filter is dropped
    /// only when it matches nothing.
    /// </summary>
    local procedure FindPostedSourceSaleEntries(PostedWhseShipmentLine: Record "Posted Whse. Shipment Line"; var ItemLedgerEntry: Record "Item Ledger Entry"): Boolean
    begin
        ItemLedgerEntry.Reset();
        ItemLedgerEntry.SetCurrentKey("Document No.", "Document Type", "Document Line No.");
        ItemLedgerEntry.SetRange("Document No.", PostedWhseShipmentLine."Posted Source No.");
        ItemLedgerEntry.SetRange("Document Type", ItemLedgerEntry."Document Type"::"Sales Shipment");
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Sale);
        ItemLedgerEntry.SetRange("Item No.", PostedWhseShipmentLine."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", PostedWhseShipmentLine."Variant Code");
        ItemLedgerEntry.SetRange("Location Code", PostedWhseShipmentLine."Location Code");
        ItemLedgerEntry.SetFilter(Quantity, '<0');
        ItemLedgerEntry.SetRange("Document Line No.", PostedWhseShipmentLine."Source Line No.");
        if ItemLedgerEntry.FindSet(true) then
            exit(true);
        // Standard BC always keeps the sales line number on the shipment line
        // and its ledger entries. Accept the unfiltered set only when it is
        // unambiguous; binding another line's entries to this LP would consume
        // the wrong pallet on the strict path.
        ItemLedgerEntry.SetRange("Document Line No.");
        if ItemLedgerEntry.Count() <> 1 then
            exit(false);
        exit(ItemLedgerEntry.FindSet(true));
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
        PostedHeader: Record "Posted Whse. Receipt Header";
        PostedLine: Record "Posted Whse. Receipt Line";
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LineLpNo: Code[20];
        LineLpNos: Text[250];
        WhseReceiptNo: Code[20];
        ReceiptLineNo: Integer;
        CurrentLpCount: Integer;
    begin
        if PostedReceiptNo = '' then
            exit;
        if PostedHeader.Get(PostedReceiptNo) then
            WhseReceiptNo := PostedHeader."Whse. Receipt No.";

        PostedLine.SetRange("No.", PostedReceiptNo);
        if not PostedLine.FindSet() then
            exit;
        repeat
            Clear(LineLpNos);
            ReceiptLineNo := PostedLine."Whse Receipt Line No.";
            if ReceiptLineNo = 0 then
                ReceiptLineNo := PostedLine."Line No.";
            LineLpNos := ResolveReceiptLpNosText(
                WhseReceiptNo, ReceiptLineNo,
                PostedLine."Item No.", PostedLine."Variant Code", CurrentLpCount);

            LineLpNo := PostedLine."LP No.";
            if CurrentLpCount = 1 then
                LineLpNo := CopyStr(LineLpNos, 1, MaxStrLen(LineLpNo))
            else
                if LineLpNo = '' then
                LineLpNo := DefaultLpNo;

            // Birden fazla fiziksel LP tek standart stok hareketine bağlıdır.
            // Bu durumda başlıktaki ilk LP'yi bütün harekete yazmak yerine LP
            // listesini yalnız özel liste alanında sakla.
            if CurrentLpCount > 1 then begin
                WhseItemEntryRelation.Reset();
                WhseItemEntryRelation.SetSourceFilter(
                    Database::"Posted Whse. Receipt Line", 0,
                    PostedLine."No.", PostedLine."Line No.", true);
                if WhseItemEntryRelation.FindSet() then
                    repeat
                        if ItemLedgerEntry.Get(WhseItemEntryRelation."Item Entry No.") then
                            StampInboundItemLedgerEntryLpList(ItemLedgerEntry, LineLpNos);
                    until WhseItemEntryRelation.Next() = 0;
            end else
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

    local procedure ResolveReceiptLpNosText(WhseReceiptNo: Code[20]; WhseReceiptLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; var LpCount: Integer): Text[250]
    var
        LPLine: Record "DOPSWHS LP Line";
        LPHeader: Record "DOPSWHS LP Header";
        SeenLpNos: Dictionary of [Code[20], Boolean];
        LpListText: Text;
        Result: Text[250];
    begin
        Clear(LpCount);
        if WhseReceiptNo = '' then
            exit('');
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        LPLine.SetRange("Source Document No.", WhseReceiptNo);
        LPLine.SetRange("Source Document Line No.", WhseReceiptLineNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") and (LPHeader.Status = LPHeader.Status::Built) then
                    if not SeenLpNos.ContainsKey(LPLine."LP No.") then begin
                        SeenLpNos.Add(LPLine."LP No.", true);
                        if LpListText <> '' then
                            LpListText += ', ';
                        LpListText += LPLine."LP No.";
                    end;
            until LPLine.Next() = 0;
        LpCount := SeenLpNos.Count();
        Result := CopyStr(LpListText, 1, MaxStrLen(Result));
        exit(Result);
    end;

    local procedure StampInboundItemLedgerEntryLpList(var ItemLedgerEntry: Record "Item Ledger Entry"; LpNos: Text[250])
    begin
        if ItemLedgerEntry."DOPSWHS LP Nos." = LpNos then
            exit;
        ItemLedgerEntry."DOPSWHS LP Nos." := LpNos;
        ItemLedgerEntry.Modify();
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
    /// Whse.-Post Shipment builds the posted line with TransferFields, which
    /// copies by field NUMBER: the operator LP on Warehouse Shipment Line (field
    /// 72406) never reached Posted Whse. Shipment Line (field 72405). Copy it
    /// before the insert so the posted line is the durable record of the
    /// explicit LP: Sales-Post deletes a fully shipped working line before its
    /// before-commit event, and ReconcilePostedWarehouseShipment / Shipment Mgmt
    /// write the same value afterwards.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Shipment", 'OnCreatePostedShptLineOnBeforePostedWhseShptLineInsert', '', false, false)]
    local procedure CarryLpOntoPostedWhseShptLine(var PostedWhseShptLine: Record "Posted Whse. Shipment Line"; WhseShptLine: Record "Warehouse Shipment Line")
    begin
        if PostedWhseShptLine."LP No." <> '' then
            exit;
        if WhseShptLine."LP No." = '' then
            exit;
        PostedWhseShptLine."LP No." := WhseShptLine."LP No.";
        PostedWhseShptLine.SSCC := WhseShptLine.SSCC;
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
    /// and LP contents stay equal. A warehouse shipment line with an explicitly selected LP
    /// (read from the posted warehouse line of this posting, else the working line) keeps
    /// the strict path: that LP must cover the quantity. Every other sale is reconciled from
    /// the registered pick that physically moved the stock: deterministic split across
    /// pallets, never an error.
    /// </summary>
    local procedure ReconcileSalesLp(SalesShptHdrNo: Code[20]; WhseShip: Boolean)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        PostedShptLine: Record "Sales Shipment Line";
        PreferredLpNo: Code[20];
        HintLpNo: Code[20];
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
                    // No operator-selected LP on the shipment line. An LP stamped
                    // earlier (item-journal heuristic or posted line) is only a
                    // preference: the registered pick decides which pallet(s)
                    // were physically taken.
                    HintLpNo := ItemLedgerEntry."DOPSWHS LP No.";
                    if HintLpNo = '' then
                        HintLpNo := PostedShptLine."DOPSWHS LP No.";
                    ReconcileSalesEntryFromPick(ItemLedgerEntry, PostedShptLine, HintLpNo);
                end;
            end;
        until ItemLedgerEntry.Next() = 0;
    end;

    /// <summary>
    /// The operator-selected LP of the warehouse shipment line this entry came
    /// from. The posted warehouse line of THIS posting is checked first: it is
    /// created while the sales line posts (before FinalizePosting) and carries
    /// the LP since CarryLpOntoPostedWhseShptLine, whereas Sales-Post deletes a
    /// fully shipped working line before the before-commit event. Working lines
    /// remain the fallback for partially shipped lines.
    /// </summary>
    local procedure ResolveWarehouseShipmentLp(PostedShptLine: Record "Sales Shipment Line"; ItemLedgerEntry: Record "Item Ledger Entry"; var Ambiguous: Boolean): Code[20]
    var
        PostedWhseShptLine: Record "Posted Whse. Shipment Line";
        WhseShptLine: Record "Warehouse Shipment Line";
        CandidateLpNo: Code[20];
    begin
        Clear(Ambiguous);
        // The posted warehouse line of THIS posting is authoritative, blank
        // included: the working-line fallback below is not scoped to one
        // warehouse shipment, so a sales line split over two shipments would
        // otherwise consume the other shipment's pallet on the strict path.
        if FindPostedWhseShptLine(ItemLedgerEntry, PostedShptLine, PostedWhseShptLine) then
            exit(PostedWhseShptLine."LP No.");

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

    /// <summary>
    /// Posted warehouse shipment line created for this sales line in the
    /// posting that produced the ledger entry ("Posted Source No." is the sales
    /// shipment no.). Whse.-Post Shipment posts one warehouse shipment at a time
    /// and a sales line appears once per warehouse shipment, so at most one line
    /// matches.
    /// </summary>
    local procedure FindPostedWhseShptLine(ItemLedgerEntry: Record "Item Ledger Entry"; PostedShptLine: Record "Sales Shipment Line"; var PostedWhseShptLine: Record "Posted Whse. Shipment Line"): Boolean
    begin
        if PostedShptLine."Order No." = '' then
            exit(false);
        PostedWhseShptLine.Reset();
        PostedWhseShptLine.SetCurrentKey("Posted Source No.", "Posting Date");
        PostedWhseShptLine.SetRange("Posted Source No.", ItemLedgerEntry."Document No.");
        PostedWhseShptLine.SetRange("Source Type", Database::"Sales Line");
        PostedWhseShptLine.SetRange("Source No.", PostedShptLine."Order No.");
        PostedWhseShptLine.SetRange("Source Line No.", PostedShptLine."Order Line No.");
        PostedWhseShptLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        PostedWhseShptLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        exit(PostedWhseShptLine.FindFirst());
    end;

    /// <summary>
    /// Strict path for an explicitly selected LP: that LP must hold exactly one
    /// matching line with enough quantity, otherwise posting stops. Idempotent per
    /// ledger entry across the Sales-Post event and the posted-shipment relation.
    /// </summary>
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
        MatchingLpCount: Integer;
        TotalAvailableBaseQty: Decimal;
        CandidateAvailableBaseQty: Decimal;
        CandidateLPNo: Code[20];
        CandidateLineNo: Integer;
        ConsumptionReference: Code[40];
    begin
        RequiredBaseQty := Abs(ItemLedgerEntry.Quantity);
        if RequiredBaseQty = 0 then
            exit;
        // The same ledger entry is reached from the Sales-Post before-commit
        // event and from ReconcilePostedWarehouseShipment. Whichever ran first
        // already removed this entry's stock from an LP (possibly several in the
        // pick-guided path); a second pass must neither consume again nor fail
        // on the now-reduced LP.
        ConsumptionReference := BuildConsumptionReference(ItemLedgerEntry);
        if EntryAlreadyReconciled(ConsumptionReference) then
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
                            if CandidateLPNo <> LPLine."LP No." then begin
                                MatchingLpCount += 1;
                                TotalAvailableBaseQty := 0;
                            end;
                            CandidateLPNo := LPLine."LP No.";
                            CandidateLineNo := LPLine."Line No.";
                            CandidateAvailableBaseQty := AvailableBaseQty;
                            TotalAvailableBaseQty += AvailableBaseQty;
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
        // Several matching lines on ONE pallet are not ambiguous: LP Management
        // never merges lines, so the same item+lot can sit on two lines (two
        // receipts, or PCS and BOX). Consume them in line order. Only lines
        // spread over different pallets stop the shipment.
        if MatchingLpCount > 1 then
            Error(
                '%1 maddesi, lot %2 için birden fazla LP eşleşti. Yanlış LP miktarının düşmemesi için sevkiyat durduruldu.',
                ItemLedgerEntry."Item No.", ItemLedgerEntry."Lot No.");
        if TotalAvailableBaseQty + QtyTolerance() < RequiredBaseQty then
            Error(
                '%1 LP numarasında sevk için yeterli miktar yoktur. LP miktarı: %2, sevk miktarı: %3.',
                CandidateLPNo, TotalAvailableBaseQty, RequiredBaseQty);

        if MatchingLineCount = 1 then
            LPManagement.ConsumeLineForShipment(
                CandidateLPNo, CandidateLineNo, RequiredBaseQty, ConsumptionReference)
        else
            ConsumeStrictLpLines(
                ItemLedgerEntry, CandidateLPNo, Item, RequiredBaseQty, ConsumptionReference);
        StampItemLedgerEntry(ItemLedgerEntry, CandidateLPNo);
    end;

    /// <summary>
    /// Consumes the required base quantity from the lines of ONE pallet in line
    /// order. LP Management treats LP + reference as "already consumed", so each
    /// line gets its own ordinal suffix on the shared ILE reference.
    /// </summary>
    local procedure ConsumeStrictLpLines(ItemLedgerEntry: Record "Item Ledger Entry"; LpNo: Code[20]; Item: Record Item; RequiredBaseQty: Decimal; ConsumptionReference: Code[40])
    var
        LPLine: Record "DOPSWHS LP Line";
        ItemUoM: Record "Item Unit of Measure";
        LPManagement: Codeunit "DOPSWHS LP Management";
        LinesConsumedPerLp: Dictionary of [Code[20], Integer];
        QtyPerUoM: Decimal;
        AvailableBaseQty: Decimal;
        QtyToConsume: Decimal;
        RemainingBaseQty: Decimal;
    begin
        RemainingBaseQty := RequiredBaseQty;
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        LPLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        LPLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
        LPLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        if not LPLine.FindSet() then
            exit;
        repeat
            QtyPerUoM := 1;
            if (LPLine."Unit of Measure" <> '') and (LPLine."Unit of Measure" <> Item."Base Unit of Measure") then
                if ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                    QtyPerUoM := ItemUoM."Qty. per Unit of Measure"
                else
                    QtyPerUoM := 0;
            AvailableBaseQty := Round(LPLine.Quantity * QtyPerUoM, 0.00001);
            if (QtyPerUoM > 0) and (AvailableBaseQty > 0) then begin
                QtyToConsume := AvailableBaseQty;
                if QtyToConsume > RemainingBaseQty then
                    QtyToConsume := RemainingBaseQty;
                if QtyToConsume > QtyTolerance() then begin
                    LPManagement.ConsumeLineForShipment(
                        LpNo, LPLine."Line No.", QtyToConsume,
                        LineConsumptionReference(ConsumptionReference, LpNo, LinesConsumedPerLp));
                    RemainingBaseQty -= QtyToConsume;
                end;
            end;
        until (LPLine.Next() = 0) or (RemainingBaseQty <= QtyTolerance());
    end;

    // -------------------------------------------------------------------------
    // Pick-guided (non-explicit) sales reconciliation
    // -------------------------------------------------------------------------

    /// <summary>
    /// Reconciles a sale that carried no explicitly selected LP. The registered
    /// pick Take lines of the posted warehouse shipment line (netted for
    /// breakbulk, minus what earlier postings of the same line already shipped)
    /// say which pallet or bin each base quantity physically left. Candidates
    /// are the active LP lines at the ledger location holding the same
    /// item/variant/lot/serial, minus LPs reserved for another document.
    /// With pick evidence:
    ///   1. each Take line in registration order, up to its picked base quantity:
    ///      the LP it names, then the LPs standing in its bin (LP No./Line No.);
    ///   2. what a Take bin could not explain, from the hint LP (an LP stamped
    ///      earlier) when it stands in that bin, then from the other LPs of that
    ///      bin - never more than the bin's unexplained quantity, never a pallet
    ///      outside the picked bins;
    ///   3. only if nothing at all was consumed and exactly one LP line at the
    ///      location matches, that line (LP bin stale after a BC-side move).
    /// Without pick evidence (ship-only locations, inventory picks): the hint LP
    /// when it is a candidate, else the single matching LP line, else nothing.
    /// Quantity that no evidence explains stays loose stock; this path never
    /// raises. Several LPs may be reduced for one ledger entry; each reduction
    /// is written to the LP Movement Ledger under the same ILE-qualified
    /// reference (a per-LP ordinal is appended for a second line of the same
    /// LP, because LP Management treats LP + reference as "already consumed").
    /// The entry is stamped with the first consumed LP; when nothing was
    /// consumed an earlier heuristic stamp is cleared so the ledger never
    /// claims an LP that was not reduced.
    /// </summary>
    local procedure ReconcileSalesEntryFromPick(var ItemLedgerEntry: Record "Item Ledger Entry"; PostedShptLine: Record "Sales Shipment Line"; HintLpNo: Code[20])
    var
        TempPickTake: Record "Registered Whse. Activity Line" temporary;
        TempCandidate: Record "DOPSWHS LP Line" temporary;
        LinesConsumedPerLp: Dictionary of [Code[20], Integer];
        UnmetByBin: Dictionary of [Code[20], Decimal];
        TakeBins: List of [Code[20]];
        ConsumptionReference: Code[40];
        WhseShipmentNo: Code[20];
        FirstConsumedLpNo: Code[20];
        RemainingBaseQty: Decimal;
        TakeBaseQty: Decimal;
        ConsumedBaseQty: Decimal;
    begin
        RemainingBaseQty := Abs(ItemLedgerEntry.Quantity);
        if RemainingBaseQty = 0 then
            exit;
        Clear(ConsumedLpNos);
        ConsumptionReference := BuildConsumptionReference(ItemLedgerEntry);
        if EntryAlreadyReconciled(ConsumptionReference) then
            exit;

        CollectRegisteredPickTakes(ItemLedgerEntry, PostedShptLine, TempPickTake, WhseShipmentNo);
        BuildSalesLpCandidates(ItemLedgerEntry, TempPickTake, HintLpNo, WhseShipmentNo, TempCandidate);

        if TempCandidate.IsEmpty() then begin
            // The sale came from loose stock, or from pallets that cannot be
            // identified safely. Reducing a guessed pallet would be worse than none.
            ClearItemLedgerEntryLp(ItemLedgerEntry);
            exit;
        end;

        if TempPickTake.IsEmpty() then
            ConsumeWithoutPickEvidence(
                TempCandidate, HintLpNo, RemainingBaseQty,
                ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo)
        else begin
            // 1. Follow the registered pick: what was physically taken, and from where.
            if TempPickTake.FindSet() then
                repeat
                    TakeBaseQty := TempPickTake."Qty. (Base)";
                    if TakeBaseQty > RemainingBaseQty then
                        TakeBaseQty := RemainingBaseQty;
                    if TakeBaseQty > QtyTolerance() then begin
                        ConsumedBaseQty := 0;
                        if TempPickTake."LP No." <> '' then
                            ConsumedBaseQty := ConsumeSalesCandidates(
                                TempCandidate, TempPickTake."LP No.", '', TakeBaseQty,
                                ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
                        // A Take without LP, or naming an LP that does not hold this
                        // lot (mis-scan, cross-line copy): the pallet standing in the
                        // Take bin is the physical source.
                        if (TakeBaseQty - ConsumedBaseQty > QtyTolerance()) and (TempPickTake."Bin Code" <> '') then
                            ConsumedBaseQty += ConsumeSalesCandidates(
                                TempCandidate, '', TempPickTake."Bin Code", TakeBaseQty - ConsumedBaseQty,
                                ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
                        RemainingBaseQty -= ConsumedBaseQty;
                        AddUnmetBinQty(UnmetByBin, TakeBins, TempPickTake."Bin Code", TakeBaseQty - ConsumedBaseQty);
                    end;
                until (TempPickTake.Next() = 0) or (RemainingBaseQty <= QtyTolerance());

            // 2. The unexplained part of each Take bin: hint LP first, then the
            //    other LPs of that bin. A pallet outside the picked bins is never
            //    touched, whatever the remainder.
            if (RemainingBaseQty > QtyTolerance()) and (HintLpNo <> '') then
                RemainingBaseQty -= ConsumeWithinTakeBins(
                    TempCandidate, HintLpNo, UnmetByBin, TakeBins, RemainingBaseQty,
                    ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
            if RemainingBaseQty > QtyTolerance() then
                RemainingBaseQty -= ConsumeWithinTakeBins(
                    TempCandidate, '', UnmetByBin, TakeBins, RemainingBaseQty,
                    ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);

            // 3. No pallet found where the pick says the stock was (LP bin stale
            //    after a BC-side movement): only an unambiguous single LP line at
            //    the location may stand in.
            if (FirstConsumedLpNo = '') and (RemainingBaseQty > QtyTolerance()) then
                ConsumeSingleCandidateLine(
                    TempCandidate, RemainingBaseQty,
                    ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
        end;

        // The ledger entry carries one LP. When the sale spanned several pallets the
        // first consumed LP (pick order, then LP No.) is stamped; the LP Movement
        // Ledger holds the exact per-LP split under the same reference.
        if FirstConsumedLpNo <> '' then begin
            StampItemLedgerEntry(ItemLedgerEntry, FirstConsumedLpNo);
            // BADE saha bildirimi: iki paletten toplanan sevkiyat kaydında
            // yalnız tek palet görünüyordu. Birden fazla palet tüketildiyse
            // hepsi tüketim sırasıyla "LP No.leri" alanına yazılır.
            StampItemLedgerEntryLpList(ItemLedgerEntry);
        end else
            ClearItemLedgerEntryLp(ItemLedgerEntry);
    end;

    /// <summary>
    /// Bu madde defteri girişi için tüketilen paletleri "DOPSWHS LP Nos."
    /// alanına yazar. KURAL: alan yalnız BİRDEN FAZLA farklı palet
    /// tüketildiğinde doldurulur; tek palette boş bırakılır çünkü tek palet
    /// zaten TableRelation'lı "DOPSWHS LP No." alanında görünür.
    /// </summary>
    local procedure StampItemLedgerEntryLpList(var ItemLedgerEntry: Record "Item Ledger Entry")
    var
        LpNo: Code[20];
        LpListText: Text;
        NewValue: Text[250];
    begin
        if ConsumedLpNos.Count() <= 1 then begin
            if ItemLedgerEntry."DOPSWHS LP Nos." <> '' then begin
                ItemLedgerEntry."DOPSWHS LP Nos." := '';
                ItemLedgerEntry.Modify();
            end;
            exit;
        end;

        foreach LpNo in ConsumedLpNos do begin
            if LpListText <> '' then
                LpListText += ', ';
            LpListText += LpNo;
        end;
        NewValue := CopyStr(LpListText, 1, MaxStrLen(NewValue));
        if ItemLedgerEntry."DOPSWHS LP Nos." = NewValue then
            exit;
        ItemLedgerEntry."DOPSWHS LP Nos." := NewValue;
        ItemLedgerEntry.Modify();
    end;

    /// <summary>Aynı paletin ikinci kez eklenmesini engelleyerek tüketim
    /// sırasını korur.</summary>
    local procedure TrackConsumedLp(LpNo: Code[20])
    begin
        if LpNo = '' then
            exit;
        if ConsumedLpNos.Contains(LpNo) then
            exit;
        ConsumedLpNos.Add(LpNo);
    end;

    /// <summary>
    /// No registered pick explains the sale (ship-only location, inventory pick,
    /// pick registered without bins). The former location-wide rule applies
    /// without its error: the hint LP when it is a candidate, else the single
    /// matching LP line; several matching pallets stay untouched rather than
    /// guessed by LP No.
    /// </summary>
    local procedure ConsumeWithoutPickEvidence(var TempCandidate: Record "DOPSWHS LP Line" temporary; HintLpNo: Code[20]; RemainingBaseQty: Decimal; ConsumptionReference: Code[40]; var LinesConsumedPerLp: Dictionary of [Code[20], Integer]; var FirstConsumedLpNo: Code[20])
    begin
        if HintLpNo <> '' then begin
            TempCandidate.Reset();
            TempCandidate.SetRange("LP No.", HintLpNo);
            if not TempCandidate.IsEmpty() then begin
                ConsumeSalesCandidates(
                    TempCandidate, HintLpNo, '', RemainingBaseQty,
                    ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
                exit;
            end;
        end;
        ConsumeSingleCandidateLine(
            TempCandidate, RemainingBaseQty,
            ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
    end;

    /// <summary>
    /// Consumes from the only candidate line that still has stock; does nothing
    /// when none or several remain.
    /// </summary>
    local procedure ConsumeSingleCandidateLine(var TempCandidate: Record "DOPSWHS LP Line" temporary; MaxBaseQty: Decimal; ConsumptionReference: Code[40]; var LinesConsumedPerLp: Dictionary of [Code[20], Integer]; var FirstConsumedLpNo: Code[20])
    var
        SingleLpNo: Code[20];
        LineCount: Integer;
    begin
        TempCandidate.Reset();
        TempCandidate.SetFilter(Quantity, '>%1', QtyTolerance());
        if TempCandidate.FindSet() then
            repeat
                LineCount += 1;
                SingleLpNo := TempCandidate."LP No.";
            until (TempCandidate.Next() = 0) or (LineCount > 1);
        TempCandidate.Reset();
        if LineCount <> 1 then
            exit;
        ConsumeSalesCandidates(
            TempCandidate, SingleLpNo, '', MaxBaseQty,
            ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
    end;

    /// <summary>
    /// Consumes up to MaxBaseQty from the candidate buffer, optionally restricted
    /// to one LP and/or to the LPs standing in one bin, in LP No. / Line No.
    /// order. Returns the base quantity actually consumed and keeps the buffer
    /// quantities current.
    /// </summary>
    local procedure ConsumeSalesCandidates(var TempCandidate: Record "DOPSWHS LP Line" temporary; LpNoFilter: Code[20]; BinCodeFilter: Code[20]; MaxBaseQty: Decimal; ConsumptionReference: Code[40]; var LinesConsumedPerLp: Dictionary of [Code[20], Integer]; var FirstConsumedLpNo: Code[20]) ConsumedBaseQty: Decimal
    var
        LPManagement: Codeunit "DOPSWHS LP Management";
        QtyToConsume: Decimal;
        TakeBaseQty: Decimal;
    begin
        QtyToConsume := MaxBaseQty;
        if QtyToConsume <= QtyTolerance() then
            exit(0);
        TempCandidate.Reset();
        if LpNoFilter <> '' then
            TempCandidate.SetRange("LP No.", LpNoFilter);
        if BinCodeFilter <> '' then
            TempCandidate.SetRange("Source Bin Code", BinCodeFilter);
        if not TempCandidate.FindSet(true) then begin
            TempCandidate.Reset();
            exit(0);
        end;
        repeat
            if TempCandidate.Quantity > QtyTolerance() then begin
                TakeBaseQty := TempCandidate.Quantity;
                if TakeBaseQty > QtyToConsume then
                    TakeBaseQty := QtyToConsume;
                TakeBaseQty := Round(TakeBaseQty, 0.00001);
                if TakeBaseQty > 0 then begin
                    LPManagement.ConsumeLineForShipment(
                        TempCandidate."LP No.", TempCandidate."Line No.", TakeBaseQty,
                        LineConsumptionReference(ConsumptionReference, TempCandidate."LP No.", LinesConsumedPerLp));
                    TempCandidate.Quantity -= TakeBaseQty;
                    TempCandidate.Modify();
                    QtyToConsume -= TakeBaseQty;
                    ConsumedBaseQty += TakeBaseQty;
                    if FirstConsumedLpNo = '' then
                        FirstConsumedLpNo := TempCandidate."LP No.";
                    // Tek çıkış noktası: her fiilî LP azaltması burada geçer,
                    // bu yüzden tüketim sırası da burada birikir.
                    TrackConsumedLp(TempCandidate."LP No.");
                end;
            end;
        until (TempCandidate.Next() = 0) or (QtyToConsume <= QtyTolerance());
        TempCandidate.Reset();
        exit(ConsumedBaseQty);
    end;

    /// <summary>
    /// Consumes the unexplained quantity of each Take bin (registration order),
    /// optionally only from one LP, never more per bin than the pick left
    /// unexplained there. Keeps the per-bin bookkeeping current.
    /// </summary>
    local procedure ConsumeWithinTakeBins(var TempCandidate: Record "DOPSWHS LP Line" temporary; LpNoFilter: Code[20]; var UnmetByBin: Dictionary of [Code[20], Decimal]; TakeBins: List of [Code[20]]; MaxBaseQty: Decimal; ConsumptionReference: Code[40]; var LinesConsumedPerLp: Dictionary of [Code[20], Integer]; var FirstConsumedLpNo: Code[20]) ConsumedBaseQty: Decimal
    var
        BinCode: Code[20];
        UnmetBaseQty: Decimal;
        BoundBaseQty: Decimal;
        TakenBaseQty: Decimal;
        QtyToConsume: Decimal;
    begin
        QtyToConsume := MaxBaseQty;
        foreach BinCode in TakeBins do
            if QtyToConsume > QtyTolerance() then begin
                UnmetByBin.Get(BinCode, UnmetBaseQty);
                if UnmetBaseQty > QtyTolerance() then begin
                    BoundBaseQty := UnmetBaseQty;
                    if BoundBaseQty > QtyToConsume then
                        BoundBaseQty := QtyToConsume;
                    TakenBaseQty := ConsumeSalesCandidates(
                        TempCandidate, LpNoFilter, BinCode, BoundBaseQty,
                        ConsumptionReference, LinesConsumedPerLp, FirstConsumedLpNo);
                    UnmetByBin.Set(BinCode, UnmetBaseQty - TakenBaseQty);
                    QtyToConsume -= TakenBaseQty;
                    ConsumedBaseQty += TakenBaseQty;
                end;
            end;
        exit(ConsumedBaseQty);
    end;

    local procedure AddUnmetBinQty(var UnmetByBin: Dictionary of [Code[20], Decimal]; var TakeBins: List of [Code[20]]; BinCode: Code[20]; UnmetBaseQty: Decimal)
    var
        ExistingBaseQty: Decimal;
    begin
        if (BinCode = '') or (UnmetBaseQty <= QtyTolerance()) then
            exit;
        if UnmetByBin.Get(BinCode, ExistingBaseQty) then
            UnmetByBin.Set(BinCode, ExistingBaseQty + UnmetBaseQty)
        else begin
            UnmetByBin.Add(BinCode, UnmetBaseQty);
            TakeBins.Add(BinCode);
        end;
    end;

    /// <summary>
    /// Registered pick Take lines that moved this ledger entry's stock, in
    /// registration order, netted for breakbulk and reduced by what earlier
    /// postings of the same warehouse shipment line (or earlier entries of the
    /// same posting) already shipped from the front of that order. The
    /// warehouse shipment line comes from the posted warehouse line of this
    /// posting (Sales-Post inserts it during line posting, before FinalizePosting;
    /// BC never writes Whse. Item Entry Relation for a shipment), else from a
    /// still-open partially shipped working line; only when neither exists are
    /// the picks resolved through the sales source line. Returns the warehouse
    /// shipment no. so an LP assigned to that shipment qualifies as a candidate.
    /// </summary>
    local procedure CollectRegisteredPickTakes(ItemLedgerEntry: Record "Item Ledger Entry"; PostedShptLine: Record "Sales Shipment Line"; var TempPickTake: Record "Registered Whse. Activity Line" temporary; var WhseShipmentNo: Code[20])
    var
        PostedWhseShptLine: Record "Posted Whse. Shipment Line";
        WhseShptLine: Record "Warehouse Shipment Line";
        RegdWhseActivityLine: Record "Registered Whse. Activity Line";
        WhseShipmentLineNo: Integer;
        CurrentPostedNo: Code[20];
        AlreadyShippedBase: Decimal;
        TakesCarryTracking: Boolean;
    begin
        TempPickTake.Reset();
        TempPickTake.DeleteAll();
        Clear(WhseShipmentNo);
        if PostedShptLine."Order No." = '' then
            exit;

        if FindPostedWhseShptLine(ItemLedgerEntry, PostedShptLine, PostedWhseShptLine) then begin
            WhseShipmentNo := PostedWhseShptLine."Whse. Shipment No.";
            WhseShipmentLineNo := PostedWhseShptLine."Whse Shipment Line No.";
            CurrentPostedNo := PostedWhseShptLine."No.";
        end else begin
            WhseShptLine.SetRange("Source Type", Database::"Sales Line");
            WhseShptLine.SetRange("Source No.", PostedShptLine."Order No.");
            WhseShptLine.SetRange("Source Line No.", PostedShptLine."Order Line No.");
            WhseShptLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
            WhseShptLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
            if WhseShptLine.FindFirst() then begin
                WhseShipmentNo := WhseShptLine."No.";
                WhseShipmentLineNo := WhseShptLine."Line No.";
            end;
        end;

        if WhseShipmentNo <> '' then begin
            RegdWhseActivityLine.SetRange("Whse. Document Type", RegdWhseActivityLine."Whse. Document Type"::Shipment);
            RegdWhseActivityLine.SetRange("Whse. Document No.", WhseShipmentNo);
            RegdWhseActivityLine.SetRange("Whse. Document Line No.", WhseShipmentLineNo);
            TakesCarryTracking := CollectPickTakes(ItemLedgerEntry, RegdWhseActivityLine, TempPickTake);
            if TempPickTake.IsEmpty() then
                exit;
            AlreadyShippedBase := ShippedBaseThroughWhseShipmentLine(
                ItemLedgerEntry, WhseShipmentNo, WhseShipmentLineNo, CurrentPostedNo, TakesCarryTracking);
        end else begin
            // Last resort: every registered shipment pick of the sales line at
            // this location, across all its warehouse shipments; the offset
            // below is then measured across all its sales shipments too.
            RegdWhseActivityLine.SetRange("Source Type", Database::"Sales Line");
            RegdWhseActivityLine.SetRange("Source No.", PostedShptLine."Order No.");
            RegdWhseActivityLine.SetRange("Source Line No.", PostedShptLine."Order Line No.");
            RegdWhseActivityLine.SetRange("Whse. Document Type", RegdWhseActivityLine."Whse. Document Type"::Shipment);
            RegdWhseActivityLine.SetRange("Location Code", ItemLedgerEntry."Location Code");
            TakesCarryTracking := CollectPickTakes(ItemLedgerEntry, RegdWhseActivityLine, TempPickTake);
            if TempPickTake.IsEmpty() then
                exit;
            AlreadyShippedBase := ShippedBaseForSalesLine(ItemLedgerEntry, PostedShptLine, TakesCarryTracking);
        end;
        AlreadyShippedBase += ShippedBaseEarlierInThisDocument(ItemLedgerEntry, TakesCarryTracking);
        SkipShippedPickTakes(TempPickTake, AlreadyShippedBase);
    end;

    /// <summary>
    /// Copies the registered Take lines of the filtered activity lines that
    /// match the entry's item/variant and tracking. Items tracked only at ledger
    /// level (no warehouse lot/serial tracking) register their pick lines with
    /// blank tracking; those lines still say which pallet and bin the stock
    /// left. Returns true when the copied Take lines carry the entry's
    /// lot/serial, false when the blank-tracking fallback (or nothing) applied.
    /// </summary>
    local procedure CollectPickTakes(ItemLedgerEntry: Record "Item Ledger Entry"; var RegdWhseActivityLine: Record "Registered Whse. Activity Line"; var TempPickTake: Record "Registered Whse. Activity Line" temporary): Boolean
    begin
        RegdWhseActivityLine.SetRange("Activity Type", RegdWhseActivityLine."Activity Type"::Pick);
        RegdWhseActivityLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        RegdWhseActivityLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        if ItemLedgerEntry."Lot No." <> '' then
            RegdWhseActivityLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
        if ItemLedgerEntry."Serial No." <> '' then
            RegdWhseActivityLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        if CopyPickTakes(RegdWhseActivityLine, TempPickTake) then
            exit((ItemLedgerEntry."Lot No." <> '') or (ItemLedgerEntry."Serial No." <> ''));
        if (ItemLedgerEntry."Lot No." = '') and (ItemLedgerEntry."Serial No." = '') then
            exit(false);
        RegdWhseActivityLine.SetRange("Lot No.", '');
        RegdWhseActivityLine.SetRange("Serial No.", '');
        CopyPickTakes(RegdWhseActivityLine, TempPickTake);
        exit(false);
    end;

    /// <summary>
    /// Copies the Take lines and nets breakbulk: Whse.-Activity-Register also
    /// registers the breakbulk pair (Take 1 PALLET from bin X, Place its base
    /// quantity back into bin X) and Registered Whse. Activity Line has no
    /// Breakbulk No. Every Place into a Take bin is netted against that bin's
    /// Take lines so the buffer holds what physically left each bin; the real
    /// Place goes to the shipment bin, never to a Take bin.
    /// </summary>
    local procedure CopyPickTakes(var RegdWhseActivityLine: Record "Registered Whse. Activity Line"; var TempPickTake: Record "Registered Whse. Activity Line" temporary): Boolean
    begin
        RegdWhseActivityLine.SetRange("Action Type", RegdWhseActivityLine."Action Type"::Take);
        if not RegdWhseActivityLine.FindSet() then
            exit(false);
        repeat
            TempPickTake := RegdWhseActivityLine;
            TempPickTake.Insert();
        until RegdWhseActivityLine.Next() = 0;

        RegdWhseActivityLine.SetRange("Action Type", RegdWhseActivityLine."Action Type"::Place);
        if RegdWhseActivityLine.FindSet() then
            repeat
                NetBreakbulkPlace(TempPickTake, RegdWhseActivityLine."Bin Code", RegdWhseActivityLine."Qty. (Base)");
            until RegdWhseActivityLine.Next() = 0;
        RegdWhseActivityLine.SetRange("Action Type", RegdWhseActivityLine."Action Type"::Take);
        exit(true);
    end;

    local procedure NetBreakbulkPlace(var TempPickTake: Record "Registered Whse. Activity Line" temporary; BinCode: Code[20]; PlaceBaseQty: Decimal)
    begin
        if (BinCode = '') or (PlaceBaseQty <= QtyTolerance()) then
            exit;
        TempPickTake.Reset();
        TempPickTake.SetRange("Bin Code", BinCode);
        if TempPickTake.FindSet() then
            repeat
                if TempPickTake."Qty. (Base)" <= PlaceBaseQty + QtyTolerance() then begin
                    PlaceBaseQty -= TempPickTake."Qty. (Base)";
                    TempPickTake.Delete();
                end else begin
                    TempPickTake."Qty. (Base)" -= PlaceBaseQty;
                    TempPickTake.Modify();
                    PlaceBaseQty := 0;
                end;
            until (TempPickTake.Next() = 0) or (PlaceBaseQty <= QtyTolerance());
        TempPickTake.Reset();
    end;

    /// <summary>
    /// Removes the base quantity earlier postings already shipped from the front
    /// of the registration-ordered Take buffer: stock leaves the shipment bin in
    /// the order it was picked into it, so a partial shipment consumed the first
    /// Take lines and this posting continues where it stopped.
    /// </summary>
    local procedure SkipShippedPickTakes(var TempPickTake: Record "Registered Whse. Activity Line" temporary; SkipBaseQty: Decimal)
    begin
        if SkipBaseQty <= QtyTolerance() then
            exit;
        TempPickTake.Reset();
        if not TempPickTake.FindSet() then
            exit;
        repeat
            if TempPickTake."Qty. (Base)" <= SkipBaseQty + QtyTolerance() then begin
                SkipBaseQty -= TempPickTake."Qty. (Base)";
                TempPickTake.Delete();
            end else begin
                TempPickTake."Qty. (Base)" -= SkipBaseQty;
                TempPickTake.Modify();
                SkipBaseQty := 0;
            end;
        until (TempPickTake.Next() = 0) or (SkipBaseQty <= QtyTolerance());
    end;

    /// <summary>
    /// Base quantity earlier postings of the same warehouse shipment line shipped
    /// for this entry's item (and tracking, when the Take lines carry it): the
    /// Sale entries of the other posted warehouse lines' sales shipments.
    /// </summary>
    local procedure ShippedBaseThroughWhseShipmentLine(ItemLedgerEntry: Record "Item Ledger Entry"; WhseShipmentNo: Code[20]; WhseShipmentLineNo: Integer; CurrentPostedNo: Code[20]; MatchTracking: Boolean) ShippedBaseQty: Decimal
    var
        PostedWhseShptLine: Record "Posted Whse. Shipment Line";
    begin
        PostedWhseShptLine.SetCurrentKey("Whse. Shipment No.", "Whse Shipment Line No.");
        PostedWhseShptLine.SetRange("Whse. Shipment No.", WhseShipmentNo);
        PostedWhseShptLine.SetRange("Whse Shipment Line No.", WhseShipmentLineNo);
        if CurrentPostedNo <> '' then
            PostedWhseShptLine.SetFilter("No.", '<>%1', CurrentPostedNo);
        if PostedWhseShptLine.FindSet() then
            repeat
                ShippedBaseQty += SaleEntriesBaseQty(
                    ItemLedgerEntry, PostedWhseShptLine."Posted Source No.", PostedWhseShptLine."Source Line No.", 0, MatchTracking);
            until PostedWhseShptLine.Next() = 0;
        exit(ShippedBaseQty);
    end;

    /// <summary>Base quantity the other sales shipments of the same order line shipped for this entry's item (and tracking).</summary>
    local procedure ShippedBaseForSalesLine(ItemLedgerEntry: Record "Item Ledger Entry"; PostedShptLine: Record "Sales Shipment Line"; MatchTracking: Boolean) ShippedBaseQty: Decimal
    var
        SalesShptLine: Record "Sales Shipment Line";
    begin
        SalesShptLine.SetCurrentKey("Order No.", "Order Line No.", "Posting Date");
        SalesShptLine.SetRange("Order No.", PostedShptLine."Order No.");
        SalesShptLine.SetRange("Order Line No.", PostedShptLine."Order Line No.");
        SalesShptLine.SetFilter("Document No.", '<>%1', ItemLedgerEntry."Document No.");
        if SalesShptLine.FindSet() then
            repeat
                ShippedBaseQty += SaleEntriesBaseQty(
                    ItemLedgerEntry, SalesShptLine."Document No.", SalesShptLine."Line No.", 0, MatchTracking);
            until SalesShptLine.Next() = 0;
        exit(ShippedBaseQty);
    end;

    /// <summary>
    /// Base quantity the earlier Sale entries of the same document line consumed
    /// in this posting (a line can produce several entries for one lot when the
    /// reservation is split), so a second entry continues where the first stopped.
    /// </summary>
    local procedure ShippedBaseEarlierInThisDocument(ItemLedgerEntry: Record "Item Ledger Entry"; MatchTracking: Boolean): Decimal
    begin
        exit(SaleEntriesBaseQty(
            ItemLedgerEntry, ItemLedgerEntry."Document No.", ItemLedgerEntry."Document Line No.",
            ItemLedgerEntry."Entry No.", MatchTracking));
    end;

    local procedure SaleEntriesBaseQty(ItemLedgerEntry: Record "Item Ledger Entry"; DocumentNo: Code[20]; DocumentLineNo: Integer; BeforeEntryNo: Integer; MatchTracking: Boolean) BaseQty: Decimal
    var
        SaleEntry: Record "Item Ledger Entry";
    begin
        if DocumentNo = '' then
            exit(0);
        SaleEntry.SetCurrentKey("Document No.", "Document Type", "Document Line No.");
        SaleEntry.SetRange("Document No.", DocumentNo);
        SaleEntry.SetRange("Document Type", SaleEntry."Document Type"::"Sales Shipment");
        SaleEntry.SetRange("Document Line No.", DocumentLineNo);
        SaleEntry.SetRange("Entry Type", SaleEntry."Entry Type"::Sale);
        SaleEntry.SetRange("Item No.", ItemLedgerEntry."Item No.");
        SaleEntry.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        if MatchTracking then begin
            SaleEntry.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
            SaleEntry.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        end;
        if BeforeEntryNo <> 0 then
            SaleEntry.SetFilter("Entry No.", '<%1', BeforeEntryNo);
        SaleEntry.SetFilter(Quantity, '<0');
        if SaleEntry.FindSet() then
            repeat
                BaseQty += Abs(SaleEntry.Quantity);
            until SaleEntry.Next() = 0;
        exit(BaseQty);
    end;

    /// <summary>
    /// Fills a temporary LP Line buffer with the consumable lines of active LPs at
    /// the ledger location that hold the same item/variant/lot/serial. In the
    /// buffer, Quantity is the available BASE quantity and "Source Bin Code" is
    /// the LP's bin; the primary key (LP No., Line No.) gives the deterministic
    /// order. The pick evidence bounds the consumption, not the buffer, with one
    /// exception: an LP reserved for another document (Status Assigned, elsewhere
    /// than this shipment or one of its registered picks) is left out unless a
    /// Take line names it or it is the hint LP. Every other flow of the app
    /// refuses such an LP, and consuming it would strip the other document's
    /// assignment.
    /// </summary>
    local procedure BuildSalesLpCandidates(ItemLedgerEntry: Record "Item Ledger Entry"; var TempPickTake: Record "Registered Whse. Activity Line" temporary; HintLpNo: Code[20]; WhseShipmentNo: Code[20]; var TempCandidate: Record "DOPSWHS LP Line" temporary)
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        PickedLpNos: List of [Code[20]];
        PickActivityNos: List of [Code[20]];
        QtyPerUoM: Decimal;
        AvailableBaseQty: Decimal;
    begin
        TempCandidate.Reset();
        TempCandidate.DeleteAll();
        if not Item.Get(ItemLedgerEntry."Item No.") then
            exit;

        if TempPickTake.FindSet() then
            repeat
                if (TempPickTake."LP No." <> '') and (not PickedLpNos.Contains(TempPickTake."LP No.")) then
                    PickedLpNos.Add(TempPickTake."LP No.");
                // Whse.-Activity-Register keeps the source pick no. on the
                // registered line; the registered no. is accepted as well.
                if (TempPickTake."Whse. Activity No." <> '') and (not PickActivityNos.Contains(TempPickTake."Whse. Activity No.")) then
                    PickActivityNos.Add(TempPickTake."Whse. Activity No.");
                if (TempPickTake."No." <> '') and (not PickActivityNos.Contains(TempPickTake."No.")) then
                    PickActivityNos.Add(TempPickTake."No.");
            until TempPickTake.Next() = 0;

        LPHeader.SetRange("Location Code", ItemLedgerEntry."Location Code");
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if not LPHeader.FindSet() then
            exit;
        repeat
            if LpMayBeConsumed(LPHeader, HintLpNo, WhseShipmentNo, PickedLpNos, PickActivityNos) then begin
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
                            TempCandidate := LPLine;
                            TempCandidate.Quantity := AvailableBaseQty;
                            TempCandidate."Source Bin Code" := LPHeader."Bin Code";
                            TempCandidate.Insert();
                        end;
                    until LPLine.Next() = 0;
            end;
        until LPHeader.Next() = 0;
    end;

    local procedure LpMayBeConsumed(LPHeader: Record "DOPSWHS LP Header"; HintLpNo: Code[20]; WhseShipmentNo: Code[20]; PickedLpNos: List of [Code[20]]; PickActivityNos: List of [Code[20]]): Boolean
    begin
        if PickedLpNos.Contains(LPHeader."No.") or (LPHeader."No." = HintLpNo) then
            exit(true);
        if (LPHeader.Status <> LPHeader.Status::Assigned) or (LPHeader."Assigned Document No." = '') then
            exit(true);
        case LPHeader."Assigned Document Type" of
            LPHeader."Assigned Document Type"::WhseShipment:
                exit(LPHeader."Assigned Document No." = WhseShipmentNo);
            LPHeader."Assigned Document Type"::WhsePick:
                exit(PickActivityNos.Contains(LPHeader."Assigned Document No."));
        end;
        exit(false);
    end;

    /// <summary>
    /// Removes a heuristic LP stamp (item-journal resolution) from an entry whose
    /// stock was not taken from any LP, together with its value entries, so the
    /// ledger never claims a pallet that was not reduced.
    /// </summary>
    local procedure ClearItemLedgerEntryLp(var ItemLedgerEntry: Record "Item Ledger Entry")
    var
        ValueEntry: Record "Value Entry";
    begin
        if (ItemLedgerEntry."DOPSWHS LP No." = '') and (ItemLedgerEntry."DOPSWHS LP Nos." = '') then
            exit;
        ItemLedgerEntry."DOPSWHS LP No." := '';
        ItemLedgerEntry."DOPSWHS LP Nos." := '';
        ItemLedgerEntry.Modify();

        ValueEntry.SetRange("Item Ledger Entry No.", ItemLedgerEntry."Entry No.");
        ValueEntry.SetFilter("DOPSWHS LP No.", '<>%1', '');
        if ValueEntry.FindSet(true) then
            repeat
                ValueEntry."DOPSWHS LP No." := '';
                ValueEntry.Modify();
            until ValueEntry.Next() = 0;
    end;

    /// <summary>Movement-ledger reference that identifies one item ledger entry:
    /// posted document no. + '#' + entry no. Shared by both reconciliation paths.</summary>
    local procedure BuildConsumptionReference(ItemLedgerEntry: Record "Item Ledger Entry"): Code[40]
    var
        ConsumptionReference: Code[40];
    begin
        ConsumptionReference := CopyStr(
            ItemLedgerEntry."Document No." + '#' + Format(ItemLedgerEntry."Entry No."),
            1, MaxStrLen(ConsumptionReference));
        exit(ConsumptionReference);
    end;

    /// <summary>
    /// Reference for one consumed LP line. LP Management treats LP No. + reference
    /// as "already consumed", so a second line of the same LP within one entry gets
    /// an ordinal suffix; the first line keeps the plain entry reference.
    /// </summary>
    local procedure LineConsumptionReference(ConsumptionReference: Code[40]; LpNo: Code[20]; var LinesConsumedPerLp: Dictionary of [Code[20], Integer]): Code[40]
    var
        LineReference: Code[40];
        Ordinal: Integer;
    begin
        if LinesConsumedPerLp.Get(LpNo, Ordinal) then begin
            Ordinal += 1;
            LinesConsumedPerLp.Set(LpNo, Ordinal);
        end else begin
            Ordinal := 1;
            LinesConsumedPerLp.Add(LpNo, Ordinal);
        end;
        if Ordinal = 1 then
            exit(ConsumptionReference);
        LineReference := CopyStr(ConsumptionReference + '/' + Format(Ordinal), 1, MaxStrLen(LineReference));
        exit(LineReference);
    end;

    /// <summary>True when any LP was already reduced for this ledger entry reference.</summary>
    local procedure EntryAlreadyReconciled(ConsumptionReference: Code[40]): Boolean
    var
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
    begin
        if ConsumptionReference = '' then
            exit(false);
        MovementLedger.SetRange(Action, MovementLedger.Action::ItemRemoved);
        MovementLedger.SetRange("Related Document", ConsumptionReference);
        exit(not MovementLedger.IsEmpty());
    end;

    local procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
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

    var
        // Bir madde defteri girişi mutabakatı boyunca fiilen azaltılan
        // paletler, tüketim sırasıyla. ReconcileSalesEntryFromPick başında
        // temizlenir; ConsumeSalesCandidates içindeki tek azaltma noktasında
        // doldurulur.
        ConsumedLpNos: List of [Code[20]];
}
