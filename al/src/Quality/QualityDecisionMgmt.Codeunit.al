codeunit 72003 "DOPSWHS Quality Decision Mgmt"
{
    // INV-010 (Kitoko, Kas 2026): a rejected (failed) quality order is the
    // non-conformance record. It names the lot/serial and gets a decision:
    //  - Scrap: posts a negative adjustment of the rejected stock through the
    //    item journal set up in Advanced WMS Setup (reason code = decision reason).
    //  - Return to Vendor: creates a draft purchase return order for the vendor
    //    of the lot (lot assigned, applied to the original receipt entry).
    //  - Rework: closes the result and opens a re-inspection order; the lot
    //    stays on quality hold until the re-inspection passes.
    //  - Accept with Deviation: releases the quality hold (concession).
    Access = Public;
    Permissions =
        tabledata "Lot No. Information" = rm,
        tabledata "Serial No. Information" = rm,
        tabledata "Item Journal Line" = rimd,
        tabledata "Reservation Entry" = rimd,
        tabledata "Item Ledger Entry" = r;

    /// <summary>Executes the recorded decision of a failed quality order. Returns the created/posted document no.</summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RIM')]
    procedure ExecuteDecision(var QualityOrder: Record "DOPSWHS Quality Order"): Code[20]
    var
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
        DocumentNo: Code[20];
    begin
        QualityOrder.TestField(Status, QualityOrder.Status::Failed);
        QualityOrder.TestField("Decision Executed", false);
        if QualityOrder.Decision = QualityOrder.Decision::" " then
            Error(DecisionMissingErr, QualityOrder."No.");
        if QualityOrder."Decision Qty." = 0 then
            QualityOrder."Decision Qty." := QualityOrder.Quantity;

        case QualityOrder.Decision of
            QualityOrder.Decision::Scrap:
                begin
                    QualityOrder.TestField("Item No.");
                    if QualityOrder."Decision Qty." <= 0 then
                        Error(DecisionQtyErr, QualityOrder."No.");
                    DocumentNo := PostScrap(QualityOrder);
                end;
            QualityOrder.Decision::"Return to Vendor":
                begin
                    QualityOrder.TestField("Item No.");
                    if QualityOrder."Decision Qty." <= 0 then
                        Error(DecisionQtyErr, QualityOrder."No.");
                    DocumentNo := CreateReturnOrder(QualityOrder);
                end;
            QualityOrder.Decision::Rework:
                DocumentNo := CreateReinspection(QualityOrder);
        end;

        QualityOrder."Decision Executed" := true;
        QualityOrder."Decision Document No." := DocumentNo;
        if QualityOrder.Decision = QualityOrder.Decision::Rework then
            QualityOrder."Re-inspection Order No." := DocumentNo;
        QualityOrder."Decision By" := CopyStr(UserId(), 1, MaxStrLen(QualityOrder."Decision By"));
        QualityOrder."Decision DateTime" := CurrentDateTime();
        QualityOrder.Modify(true);

        // Accept with deviation is a concession: the stock becomes usable. For
        // rework the re-inspection order now holds the lot (released on its pass).
        if QualityOrder.Decision in [QualityOrder.Decision::"Accept with Deviation", QualityOrder.Decision::Rework] then
            QualityLotHold.ReleaseHold(QualityOrder);
        LogDecision(QualityOrder);
        exit(DocumentNo);
    end;

    /// <summary>Vendor of the lot: the latest purchase receipt entry of the item/variant/lot.</summary>
    procedure FindLotVendor(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]): Code[20]
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if (ItemNo = '') or (LotNo = '') then
            exit('');
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive, "Location Code", "Posting Date");
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Variant Code", VariantCode);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Purchase);
        ItemLedgerEntry.SetRange(Positive, true);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Source Type", ItemLedgerEntry."Source Type"::Vendor);
        ItemLedgerEntry.SetLoadFields("Source No.");
        if ItemLedgerEntry.FindLast() then
            exit(ItemLedgerEntry."Source No.");
        exit('');
    end;

    // -------------------------------------------------------------------------
    // Scrap: item journal negative adjustment
    // -------------------------------------------------------------------------

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    local procedure PostScrap(QualityOrder: Record "DOPSWHS Quality Order"): Code[20]
    var
        Setup: Record "DOPSWHS Setup";
        Location: Record Location;
        ItemJournalBatch: Record "Item Journal Batch";
        ItemJournalLine: Record "Item Journal Line";
        OtherLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        BinCode: Code[20];
        DocumentNo: Code[20];
        LotWasBlocked: Boolean;
        SerialWasBlocked: Boolean;
    begin
        Setup.Get('');
        if (Setup."Quality Scrap Jnl. Template" = '') or (Setup."Quality Scrap Jnl. Batch" = '') then
            Error(ScrapJournalMissingErr);
        ItemJournalBatch.Get(Setup."Quality Scrap Jnl. Template", Setup."Quality Scrap Jnl. Batch");

        if QualityOrder."Location Code" <> '' then begin
            Location.Get(QualityOrder."Location Code");
            // Bin-level adjustments of a directed put-away and pick location go
            // through the warehouse item journal + Calculate Whse. Adjustment.
            if Location."Directed Put-away and Pick" then
                Error(ScrapDirectedLocationErr, QualityOrder."Location Code", QualityOrder."No.");
        end;
        BinCode := QualityOrder."Quarantine Bin";
        if BinCode = '' then
            BinCode := QualityOrder."Bin Code";
        if Location."Bin Mandatory" and (BinCode = '') then
            Error(ScrapBinMissingErr, QualityOrder."No.", QualityOrder."Location Code");

        // The batch is posted as a whole: never post somebody else's lines with it.
        OtherLine.SetRange("Journal Template Name", ItemJournalBatch."Journal Template Name");
        OtherLine.SetRange("Journal Batch Name", ItemJournalBatch.Name);
        if not OtherLine.IsEmpty() then
            Error(ScrapBatchNotEmptyErr, ItemJournalBatch."Journal Template Name", ItemJournalBatch.Name);

        ItemJournalLine.Init();
        ItemJournalLine."Journal Template Name" := ItemJournalBatch."Journal Template Name";
        ItemJournalLine."Journal Batch Name" := ItemJournalBatch.Name;
        ItemJournalLine."Line No." := 10000;
        ItemJournalLine.SetUpNewLine(OtherLine);
        if ItemJournalLine."Document No." = '' then
            ItemJournalLine."Document No." := QualityOrder."No.";
        DocumentNo := ItemJournalLine."Document No.";
        ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::"Negative Adjmt.");
        ItemJournalLine.Validate("Item No.", QualityOrder."Item No.");
        if QualityOrder."Variant Code" <> '' then
            ItemJournalLine.Validate("Variant Code", QualityOrder."Variant Code");
        ItemJournalLine.Validate("Location Code", QualityOrder."Location Code");
        if BinCode <> '' then
            ItemJournalLine.Validate("Bin Code", BinCode);
        if QualityOrder."Unit of Measure Code" <> '' then
            ItemJournalLine.Validate("Unit of Measure Code", QualityOrder."Unit of Measure Code");
        ItemJournalLine.Validate(Quantity, QualityOrder."Decision Qty.");
        if QualityOrder."Decision Reason Code" <> '' then
            ItemJournalLine.Validate("Reason Code", QualityOrder."Decision Reason Code");
        ItemJournalLine."External Document No." := QualityOrder."No.";
        ItemJournalLine.Description := CopyStr(StrSubstNo(ScrapDescriptionTxt, QualityOrder."No."), 1, MaxStrLen(ItemJournalLine.Description));
        ItemJournalLine.Insert(true);
        AddJournalTracking(ItemJournalLine, QualityOrder."Lot No.", QualityOrder."Serial No.");

        // Standard posting refuses blocked lots. The rejected stock is scrapped in
        // the same transaction in which its block is lifted and restored; a
        // failing posting rolls both back.
        LotWasBlocked := SetLotBlocked(QualityOrder, false);
        SerialWasBlocked := SetSerialBlocked(QualityOrder, false);
        ItemJnlPostBatch.SetSuppressCommit(true);
        ItemJnlPostBatch.Run(ItemJournalLine);
        if LotWasBlocked then
            SetLotBlocked(QualityOrder, true);
        if SerialWasBlocked then
            SetSerialBlocked(QualityOrder, true);
        exit(DocumentNo);
    end;

    local procedure AddJournalTracking(ItemJournalLine: Record "Item Journal Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        TempReservationEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        if (LotNo = '') and (SerialNo = '') then
            exit;
        TempReservationEntry."Lot No." := LotNo;
        TempReservationEntry."Serial No." := SerialNo;
        CreateReservEntry.CreateReservEntryFor(
            Database::"Item Journal Line", ItemJournalLine."Entry Type".AsInteger(),
            ItemJournalLine."Journal Template Name", ItemJournalLine."Journal Batch Name", 0,
            ItemJournalLine."Line No.", ItemJournalLine."Qty. per Unit of Measure",
            ItemJournalLine.Quantity, ItemJournalLine."Quantity (Base)", TempReservationEntry);
        CreateReservEntry.CreateEntry(
            ItemJournalLine."Item No.", ItemJournalLine."Variant Code", ItemJournalLine."Location Code",
            ItemJournalLine.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    local procedure SetLotBlocked(QualityOrder: Record "DOPSWHS Quality Order"; NewBlocked: Boolean): Boolean
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        if QualityOrder."Lot No." = '' then
            exit(false);
        if not LotNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.") then
            exit(false);
        if LotNoInformation.Blocked = NewBlocked then
            exit(false);
        LotNoInformation.Blocked := NewBlocked;
        LotNoInformation.Modify();
        exit(true);
    end;

    local procedure SetSerialBlocked(QualityOrder: Record "DOPSWHS Quality Order"; NewBlocked: Boolean): Boolean
    var
        SerialNoInformation: Record "Serial No. Information";
    begin
        if QualityOrder."Serial No." = '' then
            exit(false);
        if not SerialNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Serial No.") then
            exit(false);
        if SerialNoInformation.Blocked = NewBlocked then
            exit(false);
        SerialNoInformation.Blocked := NewBlocked;
        SerialNoInformation.Modify();
        exit(true);
    end;

    // -------------------------------------------------------------------------
    // Return to vendor: draft purchase return order
    // -------------------------------------------------------------------------

    local procedure CreateReturnOrder(QualityOrder: Record "DOPSWHS Quality Order"): Code[20]
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        Location: Record Location;
        TempReservationEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
        VendorNo: Code[20];
        BinCode: Code[20];
        ApplToEntryNo: Integer;
    begin
        VendorNo := QualityOrder."Vendor No.";
        if VendorNo = '' then
            VendorNo := FindLotVendor(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.");
        if VendorNo = '' then
            Error(VendorMissingErr, QualityOrder."No.");

        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::"Return Order";
        PurchaseHeader.Insert(true);
        PurchaseHeader.Validate("Buy-from Vendor No.", VendorNo);
        PurchaseHeader."Your Reference" := CopyStr(QualityOrder."No.", 1, MaxStrLen(PurchaseHeader."Your Reference"));
        PurchaseHeader.Modify(true);

        BinCode := QualityOrder."Quarantine Bin";
        if BinCode = '' then
            BinCode := QualityOrder."Bin Code";

        PurchaseLine.Init();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Validate(Type, PurchaseLine.Type::Item);
        PurchaseLine.Validate("No.", QualityOrder."Item No.");
        if QualityOrder."Variant Code" <> '' then
            PurchaseLine.Validate("Variant Code", QualityOrder."Variant Code");
        PurchaseLine.Validate("Location Code", QualityOrder."Location Code");
        if (BinCode <> '') and Location.Get(QualityOrder."Location Code") then
            if Location."Bin Mandatory" and not Location."Directed Put-away and Pick" then
                PurchaseLine.Validate("Bin Code", BinCode);
        if QualityOrder."Unit of Measure Code" <> '' then
            PurchaseLine.Validate("Unit of Measure Code", QualityOrder."Unit of Measure Code");
        PurchaseLine.Validate(Quantity, QualityOrder."Decision Qty.");
        PurchaseLine."Description 2" := CopyStr(StrSubstNo(ReturnDescriptionTxt, QualityOrder."No."), 1, MaxStrLen(PurchaseLine."Description 2"));
        PurchaseLine.Insert(true);

        ApplToEntryNo := FindReceiptEntry(QualityOrder, VendorNo, PurchaseLine."Quantity (Base)");
        if (QualityOrder."Lot No." <> '') or (QualityOrder."Serial No." <> '') then begin
            TempReservationEntry."Lot No." := QualityOrder."Lot No.";
            TempReservationEntry."Serial No." := QualityOrder."Serial No.";
            CreateReservEntry.CreateReservEntryFor(
                Database::"Purchase Line", PurchaseLine."Document Type".AsInteger(), PurchaseLine."Document No.", '', 0,
                PurchaseLine."Line No.", PurchaseLine."Qty. per Unit of Measure", PurchaseLine.Quantity, PurchaseLine."Quantity (Base)",
                TempReservationEntry);
            if ApplToEntryNo <> 0 then
                CreateReservEntry.SetApplyToEntryNo(ApplToEntryNo);
            CreateReservEntry.CreateEntry(
                PurchaseLine."No.", PurchaseLine."Variant Code", PurchaseLine."Location Code", PurchaseLine.Description,
                0D, PurchaseLine."Expected Receipt Date", 0, Enum::"Reservation Status"::Surplus);
        end else
            if ApplToEntryNo <> 0 then begin
                PurchaseLine.Validate("Appl.-to Item Entry", ApplToEntryNo);
                PurchaseLine.Modify(true);
            end;
        exit(PurchaseHeader."No.");
    end;

    /// <summary>Open purchase receipt entry of the inspected stock from this vendor that covers the returned quantity (exact cost reversal).</summary>
    local procedure FindReceiptEntry(QualityOrder: Record "DOPSWHS Quality Order"; VendorNo: Code[20]; QtyBase: Decimal): Integer
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.SetCurrentKey("Item No.", Open, "Variant Code", Positive, "Location Code", "Posting Date");
        ItemLedgerEntry.SetRange("Item No.", QualityOrder."Item No.");
        ItemLedgerEntry.SetRange(Open, true);
        ItemLedgerEntry.SetRange("Variant Code", QualityOrder."Variant Code");
        ItemLedgerEntry.SetRange(Positive, true);
        ItemLedgerEntry.SetRange("Location Code", QualityOrder."Location Code");
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Purchase);
        ItemLedgerEntry.SetRange("Source Type", ItemLedgerEntry."Source Type"::Vendor);
        ItemLedgerEntry.SetRange("Source No.", VendorNo);
        ItemLedgerEntry.SetFilter("Remaining Quantity", '>=%1', QtyBase);
        if QualityOrder."Lot No." <> '' then
            ItemLedgerEntry.SetRange("Lot No.", QualityOrder."Lot No.");
        if QualityOrder."Serial No." <> '' then
            ItemLedgerEntry.SetRange("Serial No.", QualityOrder."Serial No.");
        if (QualityOrder."Posted Document No." <> '') and (QualityOrder."Source Table No." = Database::"Purchase Line") then begin
            ItemLedgerEntry.SetRange("Document No.", QualityOrder."Posted Document No.");
            if ItemLedgerEntry.IsEmpty() then
                ItemLedgerEntry.SetRange("Document No.");
        end;
        ItemLedgerEntry.SetLoadFields("Entry No.");
        if ItemLedgerEntry.FindLast() then
            exit(ItemLedgerEntry."Entry No.");
        exit(0);
    end;

    // -------------------------------------------------------------------------
    // Rework: re-inspection order
    // -------------------------------------------------------------------------

    local procedure CreateReinspection(QualityOrder: Record "DOPSWHS Quality Order"): Code[20]
    var
        QualityGateMgmt: Codeunit "DOPSWHS Quality Gate Mgmt";
        Qty: Decimal;
    begin
        Qty := QualityOrder."Decision Qty.";
        if Qty <= 0 then
            Qty := QualityOrder.Quantity;
        exit(
            QualityGateMgmt.CreateOrder(
                QualityOrder."Source Type", QualityOrder."Source Table No.", QualityOrder."Source Subtype",
                QualityOrder."Source No.", QualityOrder."Source Line No.", QualityOrder."Whse. Document No.", QualityOrder."Posted Document No.",
                QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.", QualityOrder."Serial No.",
                Qty, QualityOrder."Unit of Measure Code", QualityOrder."Location Code", QualityOrder."Bin Code",
                QualityOrder."LP No.", QualityOrder."Vendor No."));
    end;

    // -------------------------------------------------------------------------
    // Page actions (Quality Orders / Quality Order Card)
    // -------------------------------------------------------------------------

    /// <summary>Records a PASS result entered in the result dialog.</summary>
    procedure PassWithDialog(var QualityOrder: Record "DOPSWHS Quality Order")
    var
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        ResultDialog: Page "DOPSWHS Quality Result Dialog";
        Inspector: Code[50];
        Notes: Text[250];
        RejectReason: Code[20];
        QuarantineBin: Code[20];
    begin
        QualityOrder.TestField(Status, QualityOrder.Status::Open);
        ResultDialog.SetOrder(QualityOrder, false);
        if ResultDialog.RunModal() <> Action::OK then
            exit;
        ResultDialog.GetResult(Inspector, Notes, RejectReason, QuarantineBin);
        QualityOrder.Get(QualityOrder."No.");
        QualityMgmt.Pass(QualityOrder, Inspector, Notes);
    end;

    /// <summary>Records a FAIL result (reason, quarantine bin) entered in the result dialog.</summary>
    procedure FailWithDialog(var QualityOrder: Record "DOPSWHS Quality Order")
    var
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        ResultDialog: Page "DOPSWHS Quality Result Dialog";
        Inspector: Code[50];
        Notes: Text[250];
        RejectReason: Code[20];
        QuarantineBin: Code[20];
    begin
        QualityOrder.TestField(Status, QualityOrder.Status::Open);
        ResultDialog.SetOrder(QualityOrder, true);
        if ResultDialog.RunModal() <> Action::OK then
            exit;
        ResultDialog.GetResult(Inspector, Notes, RejectReason, QuarantineBin);
        QualityOrder.Get(QualityOrder."No.");
        QualityMgmt.Fail(QualityOrder, Inspector, RejectReason, Notes, QuarantineBin);
    end;

    /// <summary>Confirms and executes the decision; opens the created return order.</summary>
    procedure ExecuteDecisionWithConfirm(var QualityOrder: Record "DOPSWHS Quality Order")
    var
        PurchaseHeader: Record "Purchase Header";
        DocumentNo: Code[20];
    begin
        QualityOrder.Get(QualityOrder."No.");
        QualityOrder.TestField(Status, QualityOrder.Status::Failed);
        QualityOrder.TestField("Decision Executed", false);
        if QualityOrder.Decision = QualityOrder.Decision::" " then
            Error(DecisionMissingErr, QualityOrder."No.");
        if not Confirm(ExecuteDecisionQst, false, QualityOrder.Decision, QualityOrder."No.") then
            exit;
        DocumentNo := ExecuteDecision(QualityOrder);
        case QualityOrder.Decision of
            QualityOrder.Decision::"Return to Vendor":
                if PurchaseHeader.Get(PurchaseHeader."Document Type"::"Return Order", DocumentNo) then
                    Page.Run(Page::"Purchase Return Order", PurchaseHeader);
            QualityOrder.Decision::Scrap:
                Message(ScrapPostedMsg, QualityOrder."Decision Qty.", QualityOrder."Item No.", DocumentNo);
            QualityOrder.Decision::Rework:
                Message(ReinspectionCreatedMsg, DocumentNo);
            QualityOrder.Decision::"Accept with Deviation":
                Message(AcceptedMsg, QualityOrder."No.");
        end;
    end;

    /// <summary>Releases the quality hold of the order's lot/serial after confirmation (no result is recorded).</summary>
    procedure ReleaseHoldWithConfirm(QualityOrder: Record "DOPSWHS Quality Order")
    var
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
    begin
        if not QualityLotHold.IsOnHold(QualityOrder) then
            Error(NotOnHoldErr, QualityOrder."No.");
        if not Confirm(ReleaseHoldQst, false, QualityOrder."Item No.", QualityOrder."Lot No." + QualityOrder."Serial No.") then
            exit;
        ForceReleaseHold(QualityOrder);
    end;

    /// <summary>Unblocks the lot/serial even if other orders still hold it (explicit user decision).</summary>
    procedure ForceReleaseHold(QualityOrder: Record "DOPSWHS Quality Order")
    var
        LotNoInformation: Record "Lot No. Information";
        SerialNoInformation: Record "Serial No. Information";
    begin
        if QualityOrder."Lot No." <> '' then
            if LotNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.") then
                if LotNoInformation."DOPSWHS Quality Hold" then begin
                    LotNoInformation.Blocked := false;
                    LotNoInformation."DOPSWHS Quality Hold" := false;
                    LotNoInformation."DOPSWHS Quality Order No." := '';
                    LotNoInformation.Modify(true);
                end;
        if QualityOrder."Serial No." <> '' then
            if SerialNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Serial No.") then
                if SerialNoInformation."DOPSWHS Quality Hold" then begin
                    SerialNoInformation.Blocked := false;
                    SerialNoInformation."DOPSWHS Quality Hold" := false;
                    SerialNoInformation."DOPSWHS Quality Order No." := '';
                    SerialNoInformation.Modify(true);
                end;
        LogDecision(QualityOrder);
    end;

    procedure ShowTrackingInformation(QualityOrder: Record "DOPSWHS Quality Order")
    var
        LotNoInformation: Record "Lot No. Information";
        SerialNoInformation: Record "Serial No. Information";
    begin
        if QualityOrder."Lot No." <> '' then begin
            LotNoInformation.SetRange("Item No.", QualityOrder."Item No.");
            LotNoInformation.SetRange("Variant Code", QualityOrder."Variant Code");
            LotNoInformation.SetRange("Lot No.", QualityOrder."Lot No.");
            Page.Run(Page::"Lot No. Information Card", LotNoInformation);
            exit;
        end;
        if QualityOrder."Serial No." <> '' then begin
            SerialNoInformation.SetRange("Item No.", QualityOrder."Item No.");
            SerialNoInformation.SetRange("Variant Code", QualityOrder."Variant Code");
            SerialNoInformation.SetRange("Serial No.", QualityOrder."Serial No.");
            Page.Run(Page::"Serial No. Information Card", SerialNoInformation);
            exit;
        end;
        Error(NoTrackingErr, QualityOrder."No.");
    end;

    procedure ShowItemLedgerEntries(QualityOrder: Record "DOPSWHS Quality Order")
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        QualityOrder.TestField("Item No.");
        ItemLedgerEntry.SetRange("Item No.", QualityOrder."Item No.");
        if QualityOrder."Variant Code" <> '' then
            ItemLedgerEntry.SetRange("Variant Code", QualityOrder."Variant Code");
        if QualityOrder."Lot No." <> '' then
            ItemLedgerEntry.SetRange("Lot No.", QualityOrder."Lot No.");
        if QualityOrder."Serial No." <> '' then
            ItemLedgerEntry.SetRange("Serial No.", QualityOrder."Serial No.");
        Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
    end;

    procedure ShowSourceDocument(QualityOrder: Record "DOPSWHS Quality Order")
    var
        PurchaseHeader: Record "Purchase Header";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
    begin
        case QualityOrder."Source Table No." of
            Database::"Purchase Line":
                if PurchaseHeader.Get(Enum::"Purchase Document Type".FromInteger(QualityOrder."Source Subtype"), QualityOrder."Source No.") then begin
                    Page.Run(Page::"Purchase Order", PurchaseHeader);
                    exit;
                end;
            Database::"Assembly Header", Database::"Assembly Line":
                begin
                    if AssemblyHeader.Get(Enum::"Assembly Document Type".FromInteger(QualityOrder."Source Subtype"), QualityOrder."Source No.") then begin
                        Page.Run(Page::"Assembly Order", AssemblyHeader);
                        exit;
                    end;
                    PostedAssemblyHeader.SetRange("Order No.", QualityOrder."Source No.");
                    if PostedAssemblyHeader.FindLast() then begin
                        Page.Run(Page::"Posted Assembly Order", PostedAssemblyHeader);
                        exit;
                    end;
                end;
        end;
        Error(NoSourceDocumentErr, QualityOrder."No.");
    end;

    procedure ShowDecisionDocument(QualityOrder: Record "DOPSWHS Quality Order")
    var
        PurchaseHeader: Record "Purchase Header";
        ReinspectionOrder: Record "DOPSWHS Quality Order";
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if QualityOrder."Decision Document No." = '' then
            exit;
        case QualityOrder.Decision of
            QualityOrder.Decision::"Return to Vendor":
                if PurchaseHeader.Get(PurchaseHeader."Document Type"::"Return Order", QualityOrder."Decision Document No.") then
                    Page.Run(Page::"Purchase Return Order", PurchaseHeader);
            QualityOrder.Decision::Rework:
                if ReinspectionOrder.Get(QualityOrder."Decision Document No.") then
                    Page.Run(Page::"DOPSWHS Quality Order Card", ReinspectionOrder);
            QualityOrder.Decision::Scrap:
                begin
                    ItemLedgerEntry.SetRange("Document No.", QualityOrder."Decision Document No.");
                    ItemLedgerEntry.SetRange("Item No.", QualityOrder."Item No.");
                    Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
                end;
        end;
    end;

    procedure StatusStyle(QualityOrder: Record "DOPSWHS Quality Order"): Text
    begin
        case QualityOrder.Status of
            QualityOrder.Status::Passed:
                exit('Favorable');
            QualityOrder.Status::Failed:
                exit('Unfavorable');
            QualityOrder.Status::Open, QualityOrder.Status::InProgress:
                exit('Ambiguous');
        end;
        exit('Standard');
    end;

    procedure LookupBin(LocationCode: Code[10]; var Text: Text): Boolean
    var
        Bin: Record Bin;
    begin
        if LocationCode <> '' then
            Bin.SetRange("Location Code", LocationCode);
        if Page.RunModal(Page::"Bin List", Bin) <> Action::LookupOK then
            exit(false);
        Text := Bin.Code;
        exit(true);
    end;

    local procedure LogDecision(QualityOrder: Record "DOPSWHS Quality Order")
    var
        Dimensions: Dictionary of [Text, Text];
    begin
        Dimensions.Add('qualityOrderNo', QualityOrder."No.");
        Dimensions.Add('decision', Format(QualityOrder.Decision));
        Dimensions.Add('documentNo', QualityOrder."Decision Document No.");
        Session.LogMessage('AdvWMS.Quality.DecisionExecuted', StrSubstNo('Quality order %1 decision executed', QualityOrder."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    var
        DecisionMissingErr: Label 'Select a decision for quality order %1 first.', Comment = '%1 = quality order no.';
        DecisionQtyErr: Label 'Decision Qty. must be greater than zero on quality order %1.', Comment = '%1 = quality order no.';
        ScrapJournalMissingErr: Label 'Select the quality scrap journal template and batch in Advanced WMS Setup before posting a scrap decision.';
        ScrapDirectedLocationErr: Label 'Location %1 uses directed put-away and pick. Post the scrap of quality order %2 with the warehouse item journal and Calculate Whse. Adjustment.', Comment = '%1 = location code, %2 = quality order no.';
        ScrapBinMissingErr: Label 'Quality order %1 has no bin. Enter the bin (or quarantine bin) of the rejected stock in location %2 before posting the scrap.', Comment = '%1 = quality order no., %2 = location code';
        ScrapBatchNotEmptyErr: Label 'Item journal %1 / %2 contains other lines. Post or delete them before posting a quality scrap decision.', Comment = '%1 = journal template, %2 = journal batch';
        ScrapDescriptionTxt: Label 'Quality scrap %1', Comment = '%1 = quality order no.';
        ReturnDescriptionTxt: Label 'Quality return %1', Comment = '%1 = quality order no.';
        VendorMissingErr: Label 'Enter the Vendor No. on quality order %1. The vendor could not be found from the lot''s purchase receipt.', Comment = '%1 = quality order no.';
        ExecuteDecisionQst: Label 'Execute the decision %1 for quality order %2?', Comment = '%1 = decision, %2 = quality order no.';
        ScrapPostedMsg: Label '%1 of item %2 was scrapped with document %3.', Comment = '%1 = quantity, %2 = item no., %3 = document no.';
        ReinspectionCreatedMsg: Label 'Re-inspection quality order %1 was created. The stock stays on quality hold until it is passed.', Comment = '%1 = quality order no.';
        AcceptedMsg: Label 'The stock of quality order %1 was accepted with deviation and released.', Comment = '%1 = quality order no.';
        NotOnHoldErr: Label 'The lot/serial of quality order %1 is not on quality hold.', Comment = '%1 = quality order no.';
        ReleaseHoldQst: Label 'Release the quality hold of item %1 (%2)? The stock becomes usable without an inspection result.', Comment = '%1 = item no., %2 = lot/serial no.';
        NoTrackingErr: Label 'Quality order %1 has no lot or serial number.', Comment = '%1 = quality order no.';
        NoSourceDocumentErr: Label 'The source document of quality order %1 cannot be found.', Comment = '%1 = quality order no.';
}
