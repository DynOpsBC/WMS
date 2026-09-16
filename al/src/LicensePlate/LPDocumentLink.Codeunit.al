/// <summary>
/// Links an LP to any open or posted document (EMU/DKÇ, 15 Eyl 2026):
/// - PullFromDocument copies the document's item lines into the LP content
///   (lot/serial split from item tracking or posted ledger entries) and stamps
///   the source on every LP line;
/// - SnapshotFromDocument writes the partner, ship-to, shipment method, agent
///   and external document number onto the LP header. The snapshot is plain
///   data: it stays on the LP after the source document is deleted or posted.
/// </summary>
codeunit 72239 "DOPSWHS LP Document Link"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RIM,
        tabledata "Sales Header" = R,
        tabledata "Sales Line" = R,
        tabledata "Purchase Header" = R,
        tabledata "Purchase Line" = R,
        tabledata "Transfer Header" = R,
        tabledata "Transfer Line" = R,
        tabledata "Warehouse Receipt Header" = R,
        tabledata "Warehouse Receipt Line" = R,
        tabledata "Warehouse Shipment Header" = R,
        tabledata "Warehouse Shipment Line" = R,
        tabledata "Warehouse Activity Header" = R,
        tabledata "Warehouse Activity Line" = R,
        tabledata "Sales Shipment Header" = R,
        tabledata "Sales Shipment Line" = R,
        tabledata "Purch. Rcpt. Header" = R,
        tabledata "Purch. Rcpt. Line" = R,
        tabledata "Posted Whse. Receipt Header" = R,
        tabledata "Posted Whse. Receipt Line" = R,
        tabledata "Posted Whse. Shipment Header" = R,
        tabledata "Posted Whse. Shipment Line" = R,
        tabledata "Transfer Shipment Header" = R,
        tabledata "Transfer Shipment Line" = R,
        tabledata "Transfer Receipt Header" = R,
        tabledata "Transfer Receipt Line" = R,
        tabledata "Reservation Entry" = R,
        tabledata "Item Ledger Entry" = R,
        tabledata "Whse. Item Entry Relation" = R,
        tabledata Location = R;

    /// <summary>
    /// Copies the document's item lines into the open LP and snapshots the
    /// header. Returns the number of LP lines added.
    /// </summary>
    procedure PullFromDocument(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]): Integer
    var
        Added: Integer;
    begin
        if LP.Status <> LP.Status::Open then
            Error(LpNotOpenErr, LP."No.", LP.Status);
        if LP."Pending Receipt No." <> '' then
            Error(LpPendingReceiptErr, LP."No.", LP."Pending Receipt No.");
        if DocNo = '' then
            Error(DocNoRequiredErr);

        SnapshotFromDocument(LP, DocType, DocNo);
        case DocType of
            DocType::SalesOrder:
                Added := PullSalesOrder(LP, DocNo);
            DocType::PurchaseOrder:
                Added := PullPurchaseOrder(LP, DocNo);
            DocType::TransferOrder:
                Added := PullTransferOrder(LP, DocNo);
            DocType::WhseReceipt:
                Added := PullWhseReceipt(LP, DocNo);
            DocType::WhseShipment:
                Added := PullWhseShipment(LP, DocNo);
            DocType::WhsePick, DocType::WhsePutaway, DocType::WhseMovement:
                Added := PullWhseActivity(LP, DocType, DocNo);
            DocType::PostedSalesShipment:
                Added := PullSalesShipment(LP, DocNo);
            DocType::PostedPurchaseReceipt:
                Added := PullPurchReceipt(LP, DocNo);
            DocType::PostedWhseReceipt:
                Added := PullPostedWhseReceipt(LP, DocNo, '');
            DocType::PostedWhseShipment:
                Added := PullPostedWhseShipment(LP, DocNo, '');
            DocType::PostedTransferShipment:
                Added := PullTransferShipment(LP, DocNo);
            DocType::PostedTransferReceipt:
                Added := PullTransferReceipt(LP, DocNo);
            else
                Error(UnsupportedDocTypeErr, DocType);
        end;
        if Added = 0 then
            Error(NoLinesErr, DocType, DocNo);
        LP.Get(LP."No.");
        exit(Added);
    end;

    /// <summary>
    /// Fills an auto-created (empty) LP from the posted warehouse receipt lines
    /// that reference it; LpFilter = '' takes the lines without an LP.
    /// Used by the auto rules for documents posted from the BC client.
    /// </summary>
    procedure PullPostedWhseReceipt(var LP: Record "DOPSWHS LP Header"; PostedNo: Code[20]; LpFilter: Code[20]): Integer
    var
        PostedLine: Record "Posted Whse. Receipt Line";
        Added: Integer;
    begin
        PostedLine.SetRange("No.", PostedNo);
        PostedLine.SetRange("LP No.", LpFilter);
        PostedLine.SetFilter(Quantity, '<>0');
        if PostedLine.FindSet() then
            repeat
                Added += AddFromWhseItemEntryRelation(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedWhseReceipt, PostedNo, PostedLine."Line No.",
                    Database::"Posted Whse. Receipt Line", PostedLine."Item No.", PostedLine."Variant Code",
                    PostedLine."Unit of Measure Code", PostedLine."Qty. per Unit of Measure", PostedLine.Quantity);
            until PostedLine.Next() = 0;
        exit(Added);
    end;

    procedure PullPostedWhseShipment(var LP: Record "DOPSWHS LP Header"; PostedNo: Code[20]; LpFilter: Code[20]): Integer
    var
        PostedLine: Record "Posted Whse. Shipment Line";
        Added: Integer;
    begin
        PostedLine.SetRange("No.", PostedNo);
        PostedLine.SetRange("LP No.", LpFilter);
        PostedLine.SetFilter(Quantity, '<>0');
        if PostedLine.FindSet() then
            repeat
                Added += AddFromWhseItemEntryRelation(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedWhseShipment, PostedNo, PostedLine."Line No.",
                    Database::"Posted Whse. Shipment Line", PostedLine."Item No.", PostedLine."Variant Code",
                    PostedLine."Unit of Measure Code", PostedLine."Qty. per Unit of Measure", PostedLine.Quantity);
            until PostedLine.Next() = 0;
        exit(Added);
    end;

    // ------------------------------------------------------------------
    // Open documents
    // ------------------------------------------------------------------

    local procedure PullSalesOrder(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        SalesLine: Record "Sales Line";
        Added: Integer;
    begin
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        SalesLine.SetRange("Document No.", DocNo);
        SalesLine.SetRange(Type, SalesLine.Type::Item);
        SalesLine.SetFilter("Outstanding Quantity", '>0');
        if SalesLine.FindSet() then
            repeat
                Added += AddTrackedLines(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::SalesOrder, DocNo, SalesLine."Line No.",
                    SalesLine."No.", SalesLine."Variant Code", SalesLine."Unit of Measure Code", SalesLine."Qty. per Unit of Measure",
                    SalesLine."Outstanding Quantity",
                    Database::"Sales Line", SalesLine."Document Type".AsInteger(), DocNo, SalesLine."Line No.");
            until SalesLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullPurchaseOrder(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        PurchaseLine: Record "Purchase Line";
        Added: Integer;
    begin
        PurchaseLine.SetRange("Document Type", PurchaseLine."Document Type"::Order);
        PurchaseLine.SetRange("Document No.", DocNo);
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        PurchaseLine.SetFilter("Outstanding Quantity", '>0');
        if PurchaseLine.FindSet() then
            repeat
                Added += AddTrackedLines(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PurchaseOrder, DocNo, PurchaseLine."Line No.",
                    PurchaseLine."No.", PurchaseLine."Variant Code", PurchaseLine."Unit of Measure Code", PurchaseLine."Qty. per Unit of Measure",
                    PurchaseLine."Outstanding Quantity",
                    Database::"Purchase Line", PurchaseLine."Document Type".AsInteger(), DocNo, PurchaseLine."Line No.");
            until PurchaseLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullTransferOrder(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        TransferLine: Record "Transfer Line";
        Added: Integer;
    begin
        TransferLine.SetRange("Document No.", DocNo);
        TransferLine.SetFilter("Outstanding Quantity", '>0');
        if TransferLine.FindSet() then
            repeat
                // Subtype 0 = outbound (shipment) tracking of the transfer line.
                Added += AddTrackedLines(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::TransferOrder, DocNo, TransferLine."Line No.",
                    TransferLine."Item No.", TransferLine."Variant Code", TransferLine."Unit of Measure Code", TransferLine."Qty. per Unit of Measure",
                    TransferLine."Outstanding Quantity",
                    Database::"Transfer Line", 0, DocNo, TransferLine."Line No.");
            until TransferLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullWhseReceipt(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        Added: Integer;
    begin
        WhseReceiptLine.SetRange("No.", DocNo);
        WhseReceiptLine.SetFilter("Qty. Outstanding", '>0');
        if WhseReceiptLine.FindSet() then
            repeat
                Added += AddTrackedLines(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, DocNo, WhseReceiptLine."Line No.",
                    WhseReceiptLine."Item No.", WhseReceiptLine."Variant Code", WhseReceiptLine."Unit of Measure Code", WhseReceiptLine."Qty. per Unit of Measure",
                    WhseReceiptLine."Qty. Outstanding",
                    WhseReceiptLine."Source Type", WhseReceiptLine."Source Subtype", WhseReceiptLine."Source No.", WhseReceiptLine."Source Line No.");
            until WhseReceiptLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullWhseShipment(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        Added: Integer;
    begin
        WhseShipmentLine.SetRange("No.", DocNo);
        WhseShipmentLine.SetFilter("Qty. Outstanding", '>0');
        if WhseShipmentLine.FindSet() then
            repeat
                Added += AddTrackedLines(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, DocNo, WhseShipmentLine."Line No.",
                    WhseShipmentLine."Item No.", WhseShipmentLine."Variant Code", WhseShipmentLine."Unit of Measure Code", WhseShipmentLine."Qty. per Unit of Measure",
                    WhseShipmentLine."Qty. Outstanding",
                    WhseShipmentLine."Source Type", WhseShipmentLine."Source Subtype", WhseShipmentLine."Source No.", WhseShipmentLine."Source Line No.");
            until WhseShipmentLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullWhseActivity(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
        Added: Integer;
    begin
        case DocType of
            DocType::WhsePick:
                ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
            DocType::WhsePutaway:
                ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
            DocType::WhseMovement:
                ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Movement);
        end;
        ActivityLine.SetRange("No.", DocNo);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        ActivityLine.SetFilter("Qty. Outstanding", '>0');
        if ActivityLine.FindSet() then
            repeat
                AddContentLine(
                    LP, DocType, DocNo, ActivityLine."Line No.",
                    ActivityLine."Item No.", ActivityLine."Variant Code", ActivityLine."Unit of Measure Code",
                    ActivityLine."Qty. Outstanding", ActivityLine."Lot No.", ActivityLine."Serial No.", ActivityLine."Expiration Date",
                    ActivityLine.Quantity);
                Added += 1;
            until ActivityLine.Next() = 0;
        exit(Added);
    end;

    // ------------------------------------------------------------------
    // Posted documents
    // ------------------------------------------------------------------

    local procedure PullSalesShipment(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        ShipmentLine: Record "Sales Shipment Line";
        Added: Integer;
    begin
        ShipmentLine.SetRange("Document No.", DocNo);
        ShipmentLine.SetRange(Type, ShipmentLine.Type::Item);
        ShipmentLine.SetFilter(Quantity, '<>0');
        if ShipmentLine.FindSet() then
            repeat
                Added += AddFromItemLedgerEntries(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedSalesShipment, DocNo, ShipmentLine."Line No.",
                    ShipmentLine."No.", ShipmentLine."Variant Code", ShipmentLine."Unit of Measure Code", ShipmentLine."Qty. per Unit of Measure",
                    ShipmentLine.Quantity, Enum::"Item Ledger Entry Type"::Sale);
            until ShipmentLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullPurchReceipt(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        ReceiptLine: Record "Purch. Rcpt. Line";
        Added: Integer;
    begin
        ReceiptLine.SetRange("Document No.", DocNo);
        ReceiptLine.SetRange(Type, ReceiptLine.Type::Item);
        ReceiptLine.SetFilter(Quantity, '<>0');
        if ReceiptLine.FindSet() then
            repeat
                Added += AddFromItemLedgerEntries(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedPurchaseReceipt, DocNo, ReceiptLine."Line No.",
                    ReceiptLine."No.", ReceiptLine."Variant Code", ReceiptLine."Unit of Measure Code", ReceiptLine."Qty. per Unit of Measure",
                    ReceiptLine.Quantity, Enum::"Item Ledger Entry Type"::Purchase);
            until ReceiptLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullTransferShipment(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        ShipmentLine: Record "Transfer Shipment Line";
        Added: Integer;
    begin
        ShipmentLine.SetRange("Document No.", DocNo);
        ShipmentLine.SetFilter(Quantity, '<>0');
        if ShipmentLine.FindSet() then
            repeat
                Added += AddFromItemLedgerEntries(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedTransferShipment, DocNo, ShipmentLine."Line No.",
                    ShipmentLine."Item No.", ShipmentLine."Variant Code", ShipmentLine."Unit of Measure Code", ShipmentLine."Qty. per Unit of Measure",
                    ShipmentLine.Quantity, Enum::"Item Ledger Entry Type"::Transfer);
            until ShipmentLine.Next() = 0;
        exit(Added);
    end;

    local procedure PullTransferReceipt(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20]): Integer
    var
        ReceiptLine: Record "Transfer Receipt Line";
        Added: Integer;
    begin
        ReceiptLine.SetRange("Document No.", DocNo);
        ReceiptLine.SetFilter(Quantity, '<>0');
        if ReceiptLine.FindSet() then
            repeat
                Added += AddFromItemLedgerEntries(
                    LP, Enum::"DOPSWHS Assigned Doc Type"::PostedTransferReceipt, DocNo, ReceiptLine."Line No.",
                    ReceiptLine."Item No.", ReceiptLine."Variant Code", ReceiptLine."Unit of Measure Code", ReceiptLine."Qty. per Unit of Measure",
                    ReceiptLine.Quantity, Enum::"Item Ledger Entry Type"::Transfer);
            until ReceiptLine.Next() = 0;
        exit(Added);
    end;

    // ------------------------------------------------------------------
    // Line helpers
    // ------------------------------------------------------------------

    /// <summary>
    /// Open document line: one LP line per lot/serial found in the line's item
    /// tracking (Reservation Entry), the untracked remainder as a plain line.
    /// </summary>
    local procedure AddTrackedLines(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]; DocLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; UoM: Code[10]; QtyPerUom: Decimal; TotalQty: Decimal; SourceType: Integer; SourceSubtype: Integer; SourceID: Code[20]; SourceRefNo: Integer): Integer
    var
        ReservationEntry: Record "Reservation Entry";
        TrackedQty: Dictionary of [Text, Decimal];
        TrackedExpiry: Dictionary of [Text, Date];
        TrackingKey: Text;
        Keys: List of [Text];
        Qty: Decimal;
        Remaining: Decimal;
        Added: Integer;
        LotNo: Code[50];
        SerialNo: Code[50];
        Expiry: Date;
    begin
        if (ItemNo = '') or (TotalQty <= 0) then
            exit(0);
        if QtyPerUom <= 0 then
            QtyPerUom := 1;
        Remaining := TotalQty;
        if SourceType <> 0 then begin
            ReservationEntry.SetRange("Source Type", SourceType);
            ReservationEntry.SetRange("Source Subtype", SourceSubtype);
            ReservationEntry.SetRange("Source ID", SourceID);
            ReservationEntry.SetRange("Source Ref. No.", SourceRefNo);
            ReservationEntry.SetRange("Item No.", ItemNo);
            ReservationEntry.SetFilter("Item Tracking", '<>%1', ReservationEntry."Item Tracking"::None);
            if ReservationEntry.FindSet() then
                repeat
                    TrackingKey := ReservationEntry."Lot No." + '|' + ReservationEntry."Serial No.";
                    if TrackedQty.ContainsKey(TrackingKey) then
                        TrackedQty.Set(TrackingKey, TrackedQty.Get(TrackingKey) + Abs(ReservationEntry."Quantity (Base)") / QtyPerUom)
                    else begin
                        TrackedQty.Add(TrackingKey, Abs(ReservationEntry."Quantity (Base)") / QtyPerUom);
                        TrackedExpiry.Add(TrackingKey, ReservationEntry."Expiration Date");
                        Keys.Add(TrackingKey);
                    end;
                until ReservationEntry.Next() = 0;
        end;
        foreach TrackingKey in Keys do begin
            Qty := TrackedQty.Get(TrackingKey);
            if Qty > Remaining then
                Qty := Remaining;
            if Qty > 0 then begin
                SplitTrackingKey(TrackingKey, LotNo, SerialNo);
                Expiry := TrackedExpiry.Get(TrackingKey);
                AddContentLine(LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM, Qty, LotNo, SerialNo, Expiry, TotalQty);
                Added += 1;
                Remaining -= Qty;
            end;
        end;
        if Remaining > 0 then begin
            AddContentLine(LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM, Remaining, '', '', 0D, TotalQty);
            Added += 1;
        end;
        exit(Added);
    end;

    /// <summary>
    /// Posted document line: one LP line per item ledger entry of that line
    /// (lot/serial/expiry come from the entry); falls back to a plain line.
    /// </summary>
    local procedure AddFromItemLedgerEntries(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]; DocLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; UoM: Code[10]; QtyPerUom: Decimal; LineQty: Decimal; EntryType: Enum "Item Ledger Entry Type"): Integer
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        Added: Integer;
    begin
        if ItemNo = '' then
            exit(0);
        if QtyPerUom <= 0 then
            QtyPerUom := 1;
        ItemLedgerEntry.SetRange("Document No.", DocNo);
        ItemLedgerEntry.SetRange("Document Line No.", DocLineNo);
        ItemLedgerEntry.SetRange("Entry Type", EntryType);
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        if ItemLedgerEntry.FindSet() then
            repeat
                if ItemLedgerEntry.Quantity <> 0 then begin
                    AddContentLine(
                        LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM,
                        Abs(ItemLedgerEntry.Quantity) / QtyPerUom,
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", ItemLedgerEntry."Expiration Date", Abs(LineQty));
                    Added += 1;
                end;
            until ItemLedgerEntry.Next() = 0;
        if Added = 0 then begin
            AddContentLine(LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM, Abs(LineQty), '', '', 0D, Abs(LineQty));
            Added += 1;
        end;
        exit(Added);
    end;

    /// <summary>Posted warehouse line: item ledger entries through BC's exact Whse. Item Entry Relation.</summary>
    local procedure AddFromWhseItemEntryRelation(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]; DocLineNo: Integer; SourceTableNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; UoM: Code[10]; QtyPerUom: Decimal; LineQty: Decimal): Integer
    var
        WhseItemEntryRelation: Record "Whse. Item Entry Relation";
        ItemLedgerEntry: Record "Item Ledger Entry";
        Added: Integer;
    begin
        if ItemNo = '' then
            exit(0);
        if QtyPerUom <= 0 then
            QtyPerUom := 1;
        WhseItemEntryRelation.SetSourceFilter(SourceTableNo, 0, DocNo, DocLineNo, true);
        if WhseItemEntryRelation.FindSet() then
            repeat
                if ItemLedgerEntry.Get(WhseItemEntryRelation."Item Entry No.") and (ItemLedgerEntry.Quantity <> 0) then begin
                    AddContentLine(
                        LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM,
                        Abs(ItemLedgerEntry.Quantity) / QtyPerUom,
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", ItemLedgerEntry."Expiration Date", Abs(LineQty));
                    Added += 1;
                end;
            until WhseItemEntryRelation.Next() = 0;
        if Added = 0 then begin
            AddContentLine(LP, DocType, DocNo, DocLineNo, ItemNo, VariantCode, UoM, Abs(LineQty), '', '', 0D, Abs(LineQty));
            Added += 1;
        end;
        exit(Added);
    end;

    local procedure AddContentLine(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]; DocLineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; UoM: Code[10]; Qty: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; DocQty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if Qty <= 0 then
            exit;
        LPMgt.AddLine(LP, ItemNo, UoM, Qty, LotNo, SerialNo, ExpiryDate);
        LPLine.SetRange("LP No.", LP."No.");
        if not LPLine.FindLast() then
            Error(LineNotCreatedErr, LP."No.");
        LPLine."Variant Code" := VariantCode;
        LPLine."Source Document Type" := DocType;
        LPLine."Source Document No." := DocNo;
        LPLine."Source Document Line No." := DocLineNo;
        LPLine."Source Document Quantity" := DocQty;
        LPLine.Modify(true);
    end;

    local procedure SplitTrackingKey(TrackingKey: Text; var LotNo: Code[50]; var SerialNo: Code[50])
    var
        Position: Integer;
    begin
        Position := StrPos(TrackingKey, '|');
        LotNo := CopyStr(CopyStr(TrackingKey, 1, Position - 1), 1, MaxStrLen(LotNo));
        SerialNo := CopyStr(CopyStr(TrackingKey, Position + 1), 1, MaxStrLen(SerialNo));
    end;

    // ------------------------------------------------------------------
    // Header snapshot
    // ------------------------------------------------------------------

    /// <summary>
    /// Writes source document, partner, ship-to and shipping information from
    /// the document onto the LP header. Never raises for a missing document:
    /// the LP simply keeps the document reference.
    /// </summary>
    procedure SnapshotFromDocument(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        SalesHeader: Record "Sales Header";
        PurchaseHeader: Record "Purchase Header";
        TransferHeader: Record "Transfer Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
    begin
        ClearSnapshot(LP);
        LP."Source Document Type" := DocType;
        LP."Source Document No." := DocNo;
        case DocType of
            DocType::SalesOrder:
                if SalesHeader.Get(SalesHeader."Document Type"::Order, DocNo) then
                    SnapshotSales(LP, SalesHeader);
            DocType::PurchaseOrder:
                if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo) then
                    SnapshotPurchase(LP, PurchaseHeader);
            DocType::TransferOrder:
                if TransferHeader.Get(DocNo) then
                    SnapshotTransfer(LP, TransferHeader);
            DocType::WhseReceipt:
                if WhseReceiptHeader.Get(DocNo) then begin
                    LP."External Document No." := WhseReceiptHeader."Vendor Shipment No.";
                    LP."Source Document Date" := WhseReceiptHeader."Posting Date";
                    SnapshotFromWhseReceiptSource(LP, DocNo);
                end;
            DocType::WhseShipment:
                if WhseShipmentHeader.Get(DocNo) then begin
                    LP."Shipment Method Code" := WhseShipmentHeader."Shipment Method Code";
                    LP."Shipping Agent Code" := WhseShipmentHeader."Shipping Agent Code";
                    LP."Shipping Agent Service Code" := WhseShipmentHeader."Shipping Agent Service Code";
                    LP."External Document No." := WhseShipmentHeader."External Document No.";
                    LP."Source Document Date" := WhseShipmentHeader."Posting Date";
                    LP."Container No." := WhseShipmentHeader."DOPSWHS Container No.";
                    LP."Seal No." := WhseShipmentHeader."DOPSWHS Seal No.";
                    SnapshotFromWhseShipmentSource(LP, DocNo);
                end;
            DocType::PostedSalesShipment:
                if SalesShipmentHeader.Get(DocNo) then
                    SnapshotSalesShipment(LP, SalesShipmentHeader);
            DocType::PostedPurchaseReceipt:
                if PurchRcptHeader.Get(DocNo) then
                    SnapshotPurchReceipt(LP, PurchRcptHeader);
            DocType::PostedWhseReceipt:
                if PostedWhseReceiptHeader.Get(DocNo) then begin
                    LP."External Document No." := PostedWhseReceiptHeader."Vendor Shipment No.";
                    LP."Source Document Date" := PostedWhseReceiptHeader."Posting Date";
                    SnapshotFromPostedWhseReceiptSource(LP, DocNo);
                end;
            DocType::PostedWhseShipment:
                if PostedWhseShipmentHeader.Get(DocNo) then begin
                    LP."Shipment Method Code" := PostedWhseShipmentHeader."Shipment Method Code";
                    LP."Shipping Agent Code" := PostedWhseShipmentHeader."Shipping Agent Code";
                    LP."Shipping Agent Service Code" := PostedWhseShipmentHeader."Shipping Agent Service Code";
                    LP."External Document No." := PostedWhseShipmentHeader."External Document No.";
                    LP."Source Document Date" := PostedWhseShipmentHeader."Posting Date";
                    LP."Container No." := PostedWhseShipmentHeader."DOPSWHS Container No.";
                    LP."Seal No." := PostedWhseShipmentHeader."DOPSWHS Seal No.";
                    SnapshotFromPostedWhseShipmentSource(LP, DocNo);
                end;
            DocType::PostedTransferShipment:
                if TransferShipmentHeader.Get(DocNo) then
                    SnapshotTransferShipment(LP, TransferShipmentHeader);
            DocType::PostedTransferReceipt:
                if TransferReceiptHeader.Get(DocNo) then
                    SnapshotTransferReceipt(LP, TransferReceiptHeader);
        end;
        LP.Modify(true);
    end;

    /// <summary>Re-reads the snapshot from the LP's own source document reference.</summary>
    procedure RefreshSnapshot(var LP: Record "DOPSWHS LP Header")
    begin
        if LP."Source Document No." = '' then begin
            if LP."Assigned Document No." = '' then
                Error(NoSourceDocumentErr, LP."No.");
            SnapshotFromDocument(LP, LP."Assigned Document Type", LP."Assigned Document No.");
            exit;
        end;
        SnapshotFromDocument(LP, LP."Source Document Type", LP."Source Document No.");
    end;

    local procedure ClearSnapshot(var LP: Record "DOPSWHS LP Header")
    begin
        Clear(LP."Partner Type");
        Clear(LP."Partner No.");
        Clear(LP."Partner Name");
        Clear(LP."Ship-to Code");
        Clear(LP."Ship-to Name");
        Clear(LP."Ship-to Address");
        Clear(LP."Ship-to City");
        Clear(LP."Ship-to Post Code");
        Clear(LP."Ship-to Country Code");
        Clear(LP."Shipment Method Code");
        Clear(LP."Shipping Agent Code");
        Clear(LP."Shipping Agent Service Code");
        Clear(LP."External Document No.");
        Clear(LP."Source Document Date");
    end;

    local procedure SnapshotSales(var LP: Record "DOPSWHS LP Header"; SalesHeader: Record "Sales Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Customer;
        LP."Partner No." := SalesHeader."Sell-to Customer No.";
        LP."Partner Name" := SalesHeader."Sell-to Customer Name";
        LP."Ship-to Code" := SalesHeader."Ship-to Code";
        LP."Ship-to Name" := SalesHeader."Ship-to Name";
        LP."Ship-to Address" := SalesHeader."Ship-to Address";
        LP."Ship-to City" := SalesHeader."Ship-to City";
        LP."Ship-to Post Code" := SalesHeader."Ship-to Post Code";
        LP."Ship-to Country Code" := SalesHeader."Ship-to Country/Region Code";
        LP."Shipment Method Code" := SalesHeader."Shipment Method Code";
        LP."Shipping Agent Code" := SalesHeader."Shipping Agent Code";
        LP."Shipping Agent Service Code" := SalesHeader."Shipping Agent Service Code";
        LP."External Document No." := SalesHeader."External Document No.";
        LP."Source Document Date" := SalesHeader."Document Date";
    end;

    local procedure SnapshotSalesShipment(var LP: Record "DOPSWHS LP Header"; SalesShipmentHeader: Record "Sales Shipment Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Customer;
        LP."Partner No." := SalesShipmentHeader."Sell-to Customer No.";
        LP."Partner Name" := SalesShipmentHeader."Sell-to Customer Name";
        LP."Ship-to Code" := SalesShipmentHeader."Ship-to Code";
        LP."Ship-to Name" := SalesShipmentHeader."Ship-to Name";
        LP."Ship-to Address" := SalesShipmentHeader."Ship-to Address";
        LP."Ship-to City" := SalesShipmentHeader."Ship-to City";
        LP."Ship-to Post Code" := SalesShipmentHeader."Ship-to Post Code";
        LP."Ship-to Country Code" := SalesShipmentHeader."Ship-to Country/Region Code";
        LP."Shipment Method Code" := SalesShipmentHeader."Shipment Method Code";
        LP."Shipping Agent Code" := SalesShipmentHeader."Shipping Agent Code";
        LP."Shipping Agent Service Code" := SalesShipmentHeader."Shipping Agent Service Code";
        LP."External Document No." := SalesShipmentHeader."External Document No.";
        LP."Source Document Date" := SalesShipmentHeader."Document Date";
    end;

    local procedure SnapshotPurchase(var LP: Record "DOPSWHS LP Header"; PurchaseHeader: Record "Purchase Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Vendor;
        LP."Partner No." := PurchaseHeader."Buy-from Vendor No.";
        LP."Partner Name" := PurchaseHeader."Buy-from Vendor Name";
        LP."Ship-to Code" := PurchaseHeader."Ship-to Code";
        LP."Ship-to Name" := PurchaseHeader."Ship-to Name";
        LP."Ship-to Address" := PurchaseHeader."Ship-to Address";
        LP."Ship-to City" := PurchaseHeader."Ship-to City";
        LP."Ship-to Post Code" := PurchaseHeader."Ship-to Post Code";
        LP."Ship-to Country Code" := PurchaseHeader."Ship-to Country/Region Code";
        LP."Shipment Method Code" := PurchaseHeader."Shipment Method Code";
        LP."External Document No." := PurchaseHeader."Vendor Order No.";
        if LP."External Document No." = '' then
            LP."External Document No." := PurchaseHeader."Vendor Shipment No.";
        LP."Source Document Date" := PurchaseHeader."Document Date";
    end;

    local procedure SnapshotPurchReceipt(var LP: Record "DOPSWHS LP Header"; PurchRcptHeader: Record "Purch. Rcpt. Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Vendor;
        LP."Partner No." := PurchRcptHeader."Buy-from Vendor No.";
        LP."Partner Name" := PurchRcptHeader."Buy-from Vendor Name";
        LP."Ship-to Code" := PurchRcptHeader."Ship-to Code";
        LP."Ship-to Name" := PurchRcptHeader."Ship-to Name";
        LP."Ship-to Address" := PurchRcptHeader."Ship-to Address";
        LP."Ship-to City" := PurchRcptHeader."Ship-to City";
        LP."Ship-to Post Code" := PurchRcptHeader."Ship-to Post Code";
        LP."Ship-to Country Code" := PurchRcptHeader."Ship-to Country/Region Code";
        LP."Shipment Method Code" := PurchRcptHeader."Shipment Method Code";
        LP."External Document No." := PurchRcptHeader."Vendor Shipment No.";
        if LP."External Document No." = '' then
            LP."External Document No." := PurchRcptHeader."Vendor Order No.";
        LP."Source Document Date" := PurchRcptHeader."Document Date";
    end;

    local procedure SnapshotTransfer(var LP: Record "DOPSWHS LP Header"; TransferHeader: Record "Transfer Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Location;
        LP."Partner No." := TransferHeader."Transfer-to Code";
        LP."Partner Name" := TransferHeader."Transfer-to Name";
        LP."Ship-to Code" := TransferHeader."Transfer-to Code";
        LP."Ship-to Name" := TransferHeader."Transfer-to Name";
        LP."Ship-to Address" := TransferHeader."Transfer-to Address";
        LP."Ship-to City" := TransferHeader."Transfer-to City";
        LP."Ship-to Post Code" := TransferHeader."Transfer-to Post Code";
        LP."Ship-to Country Code" := TransferHeader."Trsf.-to Country/Region Code";
        LP."Shipment Method Code" := TransferHeader."Shipment Method Code";
        LP."Shipping Agent Code" := TransferHeader."Shipping Agent Code";
        LP."Shipping Agent Service Code" := TransferHeader."Shipping Agent Service Code";
        LP."External Document No." := TransferHeader."External Document No.";
        LP."Source Document Date" := TransferHeader."Posting Date";
    end;

    local procedure SnapshotTransferShipment(var LP: Record "DOPSWHS LP Header"; TransferShipmentHeader: Record "Transfer Shipment Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Location;
        LP."Partner No." := TransferShipmentHeader."Transfer-to Code";
        LP."Partner Name" := TransferShipmentHeader."Transfer-to Name";
        LP."Ship-to Code" := TransferShipmentHeader."Transfer-to Code";
        LP."Ship-to Name" := TransferShipmentHeader."Transfer-to Name";
        LP."Ship-to Address" := TransferShipmentHeader."Transfer-to Address";
        LP."Ship-to City" := TransferShipmentHeader."Transfer-to City";
        LP."Ship-to Post Code" := TransferShipmentHeader."Transfer-to Post Code";
        LP."Ship-to Country Code" := TransferShipmentHeader."Trsf.-to Country/Region Code";
        LP."Shipment Method Code" := TransferShipmentHeader."Shipment Method Code";
        LP."Shipping Agent Code" := TransferShipmentHeader."Shipping Agent Code";
        LP."Shipping Agent Service Code" := TransferShipmentHeader."Shipping Agent Service Code";
        LP."External Document No." := TransferShipmentHeader."External Document No.";
        LP."Source Document Date" := TransferShipmentHeader."Posting Date";
    end;

    local procedure SnapshotTransferReceipt(var LP: Record "DOPSWHS LP Header"; TransferReceiptHeader: Record "Transfer Receipt Header")
    begin
        LP."Partner Type" := LP."Partner Type"::Location;
        LP."Partner No." := TransferReceiptHeader."Transfer-from Code";
        LP."Partner Name" := TransferReceiptHeader."Transfer-from Name";
        LP."Ship-to Code" := TransferReceiptHeader."Transfer-to Code";
        LP."Ship-to Name" := TransferReceiptHeader."Transfer-to Name";
        LP."Ship-to Address" := TransferReceiptHeader."Transfer-to Address";
        LP."Ship-to City" := TransferReceiptHeader."Transfer-to City";
        LP."Ship-to Post Code" := TransferReceiptHeader."Transfer-to Post Code";
        LP."Ship-to Country Code" := TransferReceiptHeader."Trsf.-to Country/Region Code";
        LP."Shipment Method Code" := TransferReceiptHeader."Shipment Method Code";
        LP."Shipping Agent Code" := TransferReceiptHeader."Shipping Agent Code";
        LP."Shipping Agent Service Code" := TransferReceiptHeader."Shipping Agent Service Code";
        LP."External Document No." := TransferReceiptHeader."External Document No.";
        LP."Source Document Date" := TransferReceiptHeader."Posting Date";
    end;

    /// <summary>Warehouse documents carry their partner on the source order of the first line.</summary>
    local procedure SnapshotFromWhseReceiptSource(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20])
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        WhseReceiptLine.SetRange("No.", DocNo);
        if WhseReceiptLine.FindFirst() then
            SnapshotFromSource(LP, WhseReceiptLine."Source Type", WhseReceiptLine."Source Subtype", WhseReceiptLine."Source No.");
    end;

    local procedure SnapshotFromWhseShipmentSource(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
    begin
        WhseShipmentLine.SetRange("No.", DocNo);
        if WhseShipmentLine.FindFirst() then
            SnapshotFromSource(LP, WhseShipmentLine."Source Type", WhseShipmentLine."Source Subtype", WhseShipmentLine."Source No.");
    end;

    local procedure SnapshotFromPostedWhseReceiptSource(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20])
    var
        PostedLine: Record "Posted Whse. Receipt Line";
    begin
        PostedLine.SetRange("No.", DocNo);
        if PostedLine.FindFirst() then
            SnapshotFromSource(LP, PostedLine."Source Type", PostedLine."Source Subtype", PostedLine."Source No.");
    end;

    local procedure SnapshotFromPostedWhseShipmentSource(var LP: Record "DOPSWHS LP Header"; DocNo: Code[20])
    var
        PostedLine: Record "Posted Whse. Shipment Line";
    begin
        PostedLine.SetRange("No.", DocNo);
        if PostedLine.FindFirst() then
            SnapshotFromSource(LP, PostedLine."Source Type", PostedLine."Source Subtype", PostedLine."Source No.");
    end;

    /// <summary>Partner/ship-to from the order behind a warehouse document; shipping fields already set stay.</summary>
    local procedure SnapshotFromSource(var LP: Record "DOPSWHS LP Header"; SourceType: Integer; SourceSubtype: Integer; SourceNo: Code[20])
    var
        SalesHeader: Record "Sales Header";
        PurchaseHeader: Record "Purchase Header";
        TransferHeader: Record "Transfer Header";
        KeepShipmentMethod: Code[10];
        KeepAgent: Code[10];
        KeepAgentService: Code[10];
        KeepExternal: Code[35];
        KeepDate: Date;
    begin
        KeepShipmentMethod := LP."Shipment Method Code";
        KeepAgent := LP."Shipping Agent Code";
        KeepAgentService := LP."Shipping Agent Service Code";
        KeepExternal := LP."External Document No.";
        KeepDate := LP."Source Document Date";
        case SourceType of
            Database::"Sales Line":
                if SalesHeader.Get(SourceSubtype, SourceNo) then
                    SnapshotSales(LP, SalesHeader);
            Database::"Purchase Line":
                if PurchaseHeader.Get(SourceSubtype, SourceNo) then
                    SnapshotPurchase(LP, PurchaseHeader);
            Database::"Transfer Line":
                if TransferHeader.Get(SourceNo) then
                    SnapshotTransfer(LP, TransferHeader);
        end;
        if KeepShipmentMethod <> '' then
            LP."Shipment Method Code" := KeepShipmentMethod;
        if KeepAgent <> '' then
            LP."Shipping Agent Code" := KeepAgent;
        if KeepAgentService <> '' then
            LP."Shipping Agent Service Code" := KeepAgentService;
        if KeepExternal <> '' then
            LP."External Document No." := KeepExternal;
        if KeepDate <> 0D then
            LP."Source Document Date" := KeepDate;
    end;

    /// <summary>Assigning an LP to a document also snapshots that document unless a snapshot exists.</summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"DOPSWHS LP Management", 'OnAfterAssign', '', false, false)]
    local procedure SnapshotOnAssign(var LP: Record "DOPSWHS LP Header")
    begin
        if (LP."Source Document No." <> '') or (LP."Assigned Document No." = '') then
            exit;
        SnapshotFromDocument(LP, LP."Assigned Document Type", LP."Assigned Document No.");
    end;

    var
        LpNotOpenErr: Label '%1 LP''si %2 durumunda; belge satırları yalnız Açık LP''ye çekilebilir.', Comment = '%1 LP no, %2 status';
        LpPendingReceiptErr: Label '%1 LP''si %2 mal kabulü için ayrılmış; belge satırları çekilemez.', Comment = '%1 LP no, %2 receipt no';
        DocNoRequiredErr: Label 'Belge numarası girin.';
        UnsupportedDocTypeErr: Label '%1 belge türünden LP''ye satır çekme desteklenmiyor.', Comment = '%1 doc type';
        NoLinesErr: Label '%1 %2 belgesinde LP''ye çekilecek açık madde satırı yok.', Comment = '%1 doc type, %2 doc no';
        LineNotCreatedErr: Label '%1 LP satırı oluşturulamadı.', Comment = '%1 LP no';
        NoSourceDocumentErr: Label '%1 LP''sinin kaynak belgesi yok.', Comment = '%1 LP no';
}
