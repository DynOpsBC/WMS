codeunit 72002 "DOPSWHS Quality Lot Hold"
{
    // KIT-010 (Kitoko, Kas 2026): stock under inspection is not usable stock.
    // A quality order that has a lot/serial blocks it in Lot No. / Serial No.
    // Information (standard BC then refuses picks, shipments, consumption,
    // transfers and reservations of that lot); passing the order releases the
    // block, failing keeps it (quarantine). Put-away and movement are not
    // checked by standard BC, so held stock may only be placed in the quarantine
    // bin of its order. Everything here is inactive until Advanced WMS Setup >
    // "Quality Lot Hold" is switched on. A lot that was blocked by hand is never
    // released by this codeunit (only blocks it placed itself, marked "Quality Hold").
    Access = Public;
    Permissions =
        tabledata "Lot No. Information" = rim,
        tabledata "Serial No. Information" = rim;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    procedure HoldEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        Setup.SetLoadFields("Quality Lot Hold");
        if not Setup.Get('') then
            exit(false);
        exit(Setup."Quality Lot Hold");
    end;

    /// <summary>Blocks the order's lot/serial while the order holds it (creates Lot/Serial No. Information when missing).</summary>
    procedure ApplyHold(QualityOrder: Record "DOPSWHS Quality Order")
    begin
        if not HoldEnabled() then
            exit;
        if (QualityOrder."Item No." = '') or not QualityOrder.IsHolding() then
            exit;
        if QualityOrder."Lot No." <> '' then
            HoldLot(QualityOrder);
        if QualityOrder."Serial No." <> '' then
            HoldSerial(QualityOrder);
    end;

    /// <summary>
    /// Releases the order's lot/serial unless another order still holds it.
    /// Runs regardless of the setup switch so stock held while the option was
    /// on is not stranded after it is switched off.
    /// </summary>
    procedure ReleaseHold(QualityOrder: Record "DOPSWHS Quality Order")
    begin
        if QualityOrder."Item No." = '' then
            exit;
        if QualityOrder."Lot No." <> '' then
            ReleaseLot(QualityOrder);
        if QualityOrder."Serial No." <> '' then
            ReleaseSerial(QualityOrder);
    end;

    /// <summary>True when the lot/serial of the order is currently blocked by a quality hold.</summary>
    procedure IsOnHold(QualityOrder: Record "DOPSWHS Quality Order"): Boolean
    var
        LotNoInformation: Record "Lot No. Information";
        SerialNoInformation: Record "Serial No. Information";
    begin
        if QualityOrder."Lot No." <> '' then
            if LotNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.") then
                if LotNoInformation.Blocked and LotNoInformation."DOPSWHS Quality Hold" then
                    exit(true);
        if QualityOrder."Serial No." <> '' then
            if SerialNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Serial No.") then
                if SerialNoInformation.Blocked and SerialNoInformation."DOPSWHS Quality Hold" then
                    exit(true);
        exit(false);
    end;

    /// <summary>
    /// Refuses placing held stock anywhere but the quarantine bin of each order
    /// that holds it (put-away, movement, terminal bin move). Matches orders by
    /// lot/serial, by license plate and, for receipt put-aways, by source line.
    /// </summary>
    procedure CheckPlacementAllowed(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; LpNo: Code[20]; SourceType: Integer; SourceSubtype: Integer; SourceNo: Code[20]; SourceLineNo: Integer)
    var
        TempHolding: Record "DOPSWHS Quality Order" temporary;
    begin
        if not HoldEnabled() then
            exit;
        CollectHoldingOrders(ItemNo, VariantCode, LotNo, SerialNo, LpNo, SourceType, SourceSubtype, SourceNo, SourceLineNo, TempHolding);
        if not TempHolding.FindSet() then
            exit;
        repeat
            if TempHolding."Quarantine Bin" = '' then
                Error(HeldStockPlacementErr, ItemNo, TrackingText(LotNo, SerialNo, LpNo), TempHolding."No.", BinCode);
            if (TempHolding."Quarantine Bin" <> BinCode) or
               ((TempHolding."Location Code" <> '') and (TempHolding."Location Code" <> LocationCode))
            then
                Error(HeldStockQuarantineOnlyErr, ItemNo, TrackingText(LotNo, SerialNo, LpNo), TempHolding."No.", TempHolding."Quarantine Bin");
        until TempHolding.Next() = 0;
    end;

    /// <summary>Refuses taking held stock for a pick (LP/lot/serial under an undecided or failed order).</summary>
    procedure CheckPickAllowed(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; LpNo: Code[20])
    var
        TempHolding: Record "DOPSWHS Quality Order" temporary;
    begin
        if not HoldEnabled() then
            exit;
        CollectHoldingOrders(ItemNo, VariantCode, LotNo, SerialNo, LpNo, 0, 0, '', 0, TempHolding);
        if TempHolding.FindFirst() then
            Error(HeldStockPickErr, ItemNo, TrackingText(LotNo, SerialNo, LpNo), TempHolding."No.");
    end;

    // -------------------------------------------------------------------------
    // Quality order events (terminal API and BC pages both go through
    // codeunit "DOPSWHS Quality Mgmt").
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"DOPSWHS Quality Mgmt", 'OnAfterCreateOrder', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RM')]
    local procedure HoldOnCreate(var QualityOrder: Record "DOPSWHS Quality Order")
    begin
        if QualityOrder.IsTemporary() then
            exit;
        if not HoldEnabled() then
            exit;
        FillTrackingFromLp(QualityOrder);
        ApplyHold(QualityOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"DOPSWHS Quality Mgmt", 'OnAfterPass', '', false, false)]
    local procedure ReleaseOnPass(var QualityOrder: Record "DOPSWHS Quality Order")
    begin
        if QualityOrder.IsTemporary() then
            exit;
        ReleaseHold(QualityOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"DOPSWHS Quality Mgmt", 'OnAfterFail', '', false, false)]
    local procedure KeepHoldOnFail(var QualityOrder: Record "DOPSWHS Quality Order")
    begin
        if QualityOrder.IsTemporary() then
            exit;
        // Usually already blocked at creation; covers orders created before the
        // option was switched on or whose lot was entered afterwards.
        ApplyHold(QualityOrder);
    end;

    // -------------------------------------------------------------------------
    // Warehouse activity registration: put-away / movement / pick of held stock
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Activity-Register", 'OnAfterCheckWhseActivLine', '', false, false)]
    local procedure CheckHeldStockOnRegister(var WarehouseActivityLine: Record "Warehouse Activity Line")
    begin
        if WarehouseActivityLine.IsTemporary() then
            exit;
        if WarehouseActivityLine."Qty. to Handle" = 0 then
            exit;
        if not HoldEnabled() then
            exit;
        case true of
            (WarehouseActivityLine."Action Type" = WarehouseActivityLine."Action Type"::Place) and
            (WarehouseActivityLine."Activity Type" in [WarehouseActivityLine."Activity Type"::"Put-away",
                                                        WarehouseActivityLine."Activity Type"::Movement,
                                                        WarehouseActivityLine."Activity Type"::"Invt. Movement"]):
                CheckPlacementAllowed(
                    WarehouseActivityLine."Location Code", WarehouseActivityLine."Bin Code",
                    WarehouseActivityLine."Item No.", WarehouseActivityLine."Variant Code",
                    WarehouseActivityLine."Lot No.", WarehouseActivityLine."Serial No.", WarehouseActivityLine."LP No.",
                    WarehouseActivityLine."Source Type", WarehouseActivityLine."Source Subtype",
                    WarehouseActivityLine."Source No.", WarehouseActivityLine."Source Line No.");
            (WarehouseActivityLine."Action Type" = WarehouseActivityLine."Action Type"::Take) and
            (WarehouseActivityLine."Activity Type" in [WarehouseActivityLine."Activity Type"::Pick,
                                                        WarehouseActivityLine."Activity Type"::"Invt. Pick"]):
                CheckPickAllowed(
                    WarehouseActivityLine."Item No.", WarehouseActivityLine."Variant Code",
                    WarehouseActivityLine."Lot No.", WarehouseActivityLine."Serial No.", WarehouseActivityLine."LP No.");
        end;
    end;

    // -------------------------------------------------------------------------
    // Item ledger posting: standard BC refuses ANY posting of a blocked lot. A
    // quality hold must still let stock come IN (receipt / output into the held
    // lot) and let a rejected lot go back to its vendor once that decision is
    // executed. Manually blocked lots keep the standard behaviour.
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnBeforeCheckLotNoInfoNotBlocked', '', false, false)]
    local procedure AllowInboundIntoQualityHold(var ItemJnlLine2: Record "Item Journal Line"; var IsHandled: Boolean; var ItemTrackingSetup: Record "Item Tracking Setup"; var TrackingSpecification: Record "Tracking Specification")
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        if IsHandled then
            exit;
        if TrackingSpecification."Lot No." = '' then
            exit;
        if (TrackingSpecification."New Lot No." <> '') and (TrackingSpecification."New Lot No." <> TrackingSpecification."Lot No.") then
            exit;
        LotNoInformation.SetLoadFields(Blocked, "DOPSWHS Quality Hold");
        if not LotNoInformation.Get(ItemJnlLine2."Item No.", ItemJnlLine2."Variant Code", TrackingSpecification."Lot No.") then
            exit;
        if not (LotNoInformation.Blocked and LotNoInformation."DOPSWHS Quality Hold") then
            exit;
        if IsInboundEntry(ItemJnlLine2) then
            IsHandled := true
        else
            if IsVendorReturnEntry(ItemJnlLine2) then
                IsHandled := ReturnDecisionExists(ItemJnlLine2."Item No.", ItemJnlLine2."Variant Code", TrackingSpecification."Lot No.");
    end;

    local procedure IsInboundEntry(ItemJournalLine: Record "Item Journal Line"): Boolean
    begin
        if ItemJournalLine.Quantity <= 0 then
            exit(false);
        case ItemJournalLine."Entry Type" of
            ItemJournalLine."Entry Type"::Purchase:
                exit(ItemJournalLine."Document Type" = ItemJournalLine."Document Type"::"Purchase Receipt");
            ItemJournalLine."Entry Type"::Output,
            ItemJournalLine."Entry Type"::"Assembly Output",
            ItemJournalLine."Entry Type"::"Positive Adjmt.":
                exit(true);
        end;
        exit(false);
    end;

    local procedure IsVendorReturnEntry(ItemJournalLine: Record "Item Journal Line"): Boolean
    begin
        exit(
            (ItemJournalLine."Entry Type" = ItemJournalLine."Entry Type"::Purchase) and
            (ItemJournalLine."Document Type" in [ItemJournalLine."Document Type"::"Purchase Return Shipment",
                                                  ItemJournalLine."Document Type"::"Purchase Credit Memo"]));
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    local procedure ReturnDecisionExists(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]): Boolean
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        QualityOrder.SetCurrentKey("Item No.", "Variant Code", "Lot No.", "Serial No.");
        QualityOrder.SetRange("Item No.", ItemNo);
        QualityOrder.SetRange("Variant Code", VariantCode);
        QualityOrder.SetRange("Lot No.", LotNo);
        QualityOrder.SetRange(Status, QualityOrder.Status::Failed);
        QualityOrder.SetRange(Decision, QualityOrder.Decision::"Return to Vendor");
        QualityOrder.SetRange("Decision Executed", true);
        exit(not QualityOrder.IsEmpty());
    end;

    // -------------------------------------------------------------------------
    // Lot / serial blocking
    // -------------------------------------------------------------------------

    local procedure HoldLot(QualityOrder: Record "DOPSWHS Quality Order")
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        if not LotNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.") then begin
            LotNoInformation.Init();
            LotNoInformation."Item No." := QualityOrder."Item No.";
            LotNoInformation."Variant Code" := QualityOrder."Variant Code";
            LotNoInformation."Lot No." := QualityOrder."Lot No.";
            LotNoInformation.Description := CopyStr(QualityOrder."Item Description", 1, MaxStrLen(LotNoInformation.Description));
            LotNoInformation.Blocked := true;
            LotNoInformation."DOPSWHS Quality Hold" := true;
            LotNoInformation."DOPSWHS Quality Order No." := QualityOrder."No.";
            LotNoInformation.Insert(true);
            LogHold('AdvWMS.Quality.LotHeld', QualityOrder);
            exit;
        end;
        // Already held by quality (possibly by another order) or blocked by hand:
        // leave it; a manual block must not become releasable by an inspection.
        if LotNoInformation."DOPSWHS Quality Hold" or LotNoInformation.Blocked then
            exit;
        LotNoInformation.Blocked := true;
        LotNoInformation."DOPSWHS Quality Hold" := true;
        LotNoInformation."DOPSWHS Quality Order No." := QualityOrder."No.";
        LotNoInformation.Modify(true);
        LogHold('AdvWMS.Quality.LotHeld', QualityOrder);
    end;

    local procedure HoldSerial(QualityOrder: Record "DOPSWHS Quality Order")
    var
        SerialNoInformation: Record "Serial No. Information";
    begin
        if not SerialNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Serial No.") then begin
            SerialNoInformation.Init();
            SerialNoInformation."Item No." := QualityOrder."Item No.";
            SerialNoInformation."Variant Code" := QualityOrder."Variant Code";
            SerialNoInformation."Serial No." := QualityOrder."Serial No.";
            SerialNoInformation.Description := CopyStr(QualityOrder."Item Description", 1, MaxStrLen(SerialNoInformation.Description));
            SerialNoInformation.Blocked := true;
            SerialNoInformation."DOPSWHS Quality Hold" := true;
            SerialNoInformation."DOPSWHS Quality Order No." := QualityOrder."No.";
            SerialNoInformation.Insert(true);
            LogHold('AdvWMS.Quality.SerialHeld', QualityOrder);
            exit;
        end;
        if SerialNoInformation."DOPSWHS Quality Hold" or SerialNoInformation.Blocked then
            exit;
        SerialNoInformation.Blocked := true;
        SerialNoInformation."DOPSWHS Quality Hold" := true;
        SerialNoInformation."DOPSWHS Quality Order No." := QualityOrder."No.";
        SerialNoInformation.Modify(true);
        LogHold('AdvWMS.Quality.SerialHeld', QualityOrder);
    end;

    local procedure ReleaseLot(QualityOrder: Record "DOPSWHS Quality Order")
    var
        LotNoInformation: Record "Lot No. Information";
        OtherOrderNo: Code[20];
    begin
        if not LotNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Lot No.") then
            exit;
        if not LotNoInformation."DOPSWHS Quality Hold" then
            exit;
        OtherOrderNo := OtherHoldingOrderNo(QualityOrder, true);
        if OtherOrderNo <> '' then begin
            if LotNoInformation."DOPSWHS Quality Order No." <> OtherOrderNo then begin
                LotNoInformation."DOPSWHS Quality Order No." := OtherOrderNo;
                LotNoInformation.Modify(true);
            end;
            exit;
        end;
        LotNoInformation.Blocked := false;
        LotNoInformation."DOPSWHS Quality Hold" := false;
        LotNoInformation."DOPSWHS Quality Order No." := '';
        LotNoInformation.Modify(true);
        LogHold('AdvWMS.Quality.LotReleased', QualityOrder);
    end;

    local procedure ReleaseSerial(QualityOrder: Record "DOPSWHS Quality Order")
    var
        SerialNoInformation: Record "Serial No. Information";
        OtherOrderNo: Code[20];
    begin
        if not SerialNoInformation.Get(QualityOrder."Item No.", QualityOrder."Variant Code", QualityOrder."Serial No.") then
            exit;
        if not SerialNoInformation."DOPSWHS Quality Hold" then
            exit;
        OtherOrderNo := OtherHoldingOrderNo(QualityOrder, false);
        if OtherOrderNo <> '' then begin
            if SerialNoInformation."DOPSWHS Quality Order No." <> OtherOrderNo then begin
                SerialNoInformation."DOPSWHS Quality Order No." := OtherOrderNo;
                SerialNoInformation.Modify(true);
            end;
            exit;
        end;
        SerialNoInformation.Blocked := false;
        SerialNoInformation."DOPSWHS Quality Hold" := false;
        SerialNoInformation."DOPSWHS Quality Order No." := '';
        SerialNoInformation.Modify(true);
        LogHold('AdvWMS.Quality.SerialReleased', QualityOrder);
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    local procedure OtherHoldingOrderNo(QualityOrder: Record "DOPSWHS Quality Order"; ByLot: Boolean): Code[20]
    var
        OtherOrder: Record "DOPSWHS Quality Order";
    begin
        OtherOrder.SetCurrentKey("Item No.", "Variant Code", "Lot No.", "Serial No.");
        OtherOrder.SetRange("Item No.", QualityOrder."Item No.");
        OtherOrder.SetRange("Variant Code", QualityOrder."Variant Code");
        if ByLot then
            OtherOrder.SetRange("Lot No.", QualityOrder."Lot No.")
        else
            OtherOrder.SetRange("Serial No.", QualityOrder."Serial No.");
        OtherOrder.SetFilter("No.", '<>%1', QualityOrder."No.");
        OtherOrder.SetFilter(Status, '%1|%2|%3', OtherOrder.Status::Open, OtherOrder.Status::InProgress, OtherOrder.Status::Failed);
        if OtherOrder.FindSet() then
            repeat
                if OtherOrder.IsHolding() then
                    exit(OtherOrder."No.");
            until OtherOrder.Next() = 0;
        exit('');
    end;

    /// <summary>
    /// Orders created on the terminal carry an LP but no lot. When the LP holds a
    /// single lot (or serial) of the inspected item, that lot is what the order
    /// inspects; with several lots the LP-based put-away check still applies.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'RM')]
    local procedure FillTrackingFromLp(var QualityOrder: Record "DOPSWHS Quality Order")
    var
        LPLine: Record "DOPSWHS LP Line";
        LotNo: Code[50];
        SerialNo: Code[50];
        VariantCode: Code[10];
        LineCount: Integer;
    begin
        if (QualityOrder."LP No." = '') or (QualityOrder."Lot No." <> '') or (QualityOrder."Serial No." <> '') then
            exit;
        LPLine.SetRange("LP No.", QualityOrder."LP No.");
        LPLine.SetRange("Item No.", QualityOrder."Item No.");
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit;
        LotNo := LPLine."Lot No.";
        SerialNo := LPLine."Serial No.";
        VariantCode := LPLine."Variant Code";
        repeat
            LineCount += 1;
            if (LPLine."Lot No." <> LotNo) or (LPLine."Variant Code" <> VariantCode) then
                exit;
            if LPLine."Serial No." <> SerialNo then
                SerialNo := '';
        until LPLine.Next() = 0;
        if (LineCount > 1) and (LotNo = '') then
            exit;
        if (LotNo = '') and (SerialNo = '') then
            exit;
        QualityOrder."Variant Code" := VariantCode;
        QualityOrder."Lot No." := LotNo;
        if LineCount = 1 then
            QualityOrder."Serial No." := SerialNo;
        QualityOrder.Modify(true);
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Quality Order", 'R')]
    local procedure CollectHoldingOrders(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; LpNo: Code[20]; SourceType: Integer; SourceSubtype: Integer; SourceNo: Code[20]; SourceLineNo: Integer; var TempHolding: Record "DOPSWHS Quality Order" temporary)
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        TempHolding.Reset();
        TempHolding.DeleteAll();
        if ItemNo = '' then
            exit;

        if LotNo <> '' then begin
            QualityOrder.SetCurrentKey("Item No.", "Variant Code", "Lot No.", "Serial No.");
            QualityOrder.SetRange("Item No.", ItemNo);
            QualityOrder.SetRange("Variant Code", VariantCode);
            QualityOrder.SetRange("Lot No.", LotNo);
            AddHolding(QualityOrder, TempHolding);
        end;

        if SerialNo <> '' then begin
            QualityOrder.Reset();
            QualityOrder.SetCurrentKey("Item No.", "Variant Code", "Lot No.", "Serial No.");
            QualityOrder.SetRange("Item No.", ItemNo);
            QualityOrder.SetRange("Variant Code", VariantCode);
            QualityOrder.SetRange("Serial No.", SerialNo);
            AddHolding(QualityOrder, TempHolding);
        end;

        if LpNo <> '' then begin
            QualityOrder.Reset();
            QualityOrder.SetCurrentKey("LP No.");
            QualityOrder.SetRange("LP No.", LpNo);
            QualityOrder.SetRange("Item No.", ItemNo);
            AddHolding(QualityOrder, TempHolding);
        end;

        // Receipt put-away without warehouse tracking: the activity line has no
        // lot, but it still points at the purchase line the order inspects.
        if (SourceType = Database::"Purchase Line") and (SourceNo <> '') then begin
            QualityOrder.Reset();
            QualityOrder.SetCurrentKey("Source Table No.", "Source Subtype", "Source No.", "Source Line No.");
            QualityOrder.SetRange("Source Table No.", SourceType);
            QualityOrder.SetRange("Source Subtype", SourceSubtype);
            QualityOrder.SetRange("Source No.", SourceNo);
            QualityOrder.SetRange("Source Line No.", SourceLineNo);
            QualityOrder.SetRange("Item No.", ItemNo);
            // Lot-specific orders of other lots on the same line do not hold this stock.
            if LotNo <> '' then
                QualityOrder.SetFilter("Lot No.", '%1|%2', '', LotNo)
            else
                QualityOrder.SetRange("Lot No.", '');
            AddHolding(QualityOrder, TempHolding);
        end;
    end;

    local procedure AddHolding(var QualityOrder: Record "DOPSWHS Quality Order"; var TempHolding: Record "DOPSWHS Quality Order" temporary)
    begin
        QualityOrder.SetFilter(Status, '%1|%2|%3', QualityOrder.Status::Open, QualityOrder.Status::InProgress, QualityOrder.Status::Failed);
        if QualityOrder.FindSet() then
            repeat
                if QualityOrder.IsHolding() then
                    if not TempHolding.Get(QualityOrder."No.") then begin
                        TempHolding := QualityOrder;
                        TempHolding.Insert();
                    end;
            until QualityOrder.Next() = 0;
    end;

    local procedure TrackingText(LotNo: Code[50]; SerialNo: Code[50]; LpNo: Code[20]): Text
    begin
        if LotNo <> '' then
            exit(StrSubstNo(LotTok, LotNo));
        if SerialNo <> '' then
            exit(StrSubstNo(SerialTok, SerialNo));
        if LpNo <> '' then
            exit(StrSubstNo(LpTok, LpNo));
        exit('-');
    end;

    local procedure LogHold(EventId: Text; QualityOrder: Record "DOPSWHS Quality Order")
    var
        Dimensions: Dictionary of [Text, Text];
    begin
        Dimensions.Add('qualityOrderNo', QualityOrder."No.");
        Session.LogMessage(EventId, StrSubstNo('Quality hold %1 for order %2', EventId, QualityOrder."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    var
        HeldStockPlacementErr: Label 'Item %1 (%2) is blocked by quality order %3 until the inspection is passed. It cannot be placed in bin %4.', Comment = '%1 = item no., %2 = lot/serial/LP, %3 = quality order no., %4 = bin code';
        HeldStockQuarantineOnlyErr: Label 'Item %1 (%2) is blocked by quality order %3. It can only be placed in quarantine bin %4.', Comment = '%1 = item no., %2 = lot/serial/LP, %3 = quality order no., %4 = quarantine bin code';
        HeldStockPickErr: Label 'Item %1 (%2) is blocked by quality order %3 and cannot be picked until the inspection is passed.', Comment = '%1 = item no., %2 = lot/serial/LP, %3 = quality order no.';
        LotTok: Label 'lot %1', Comment = '%1 = lot no.';
        SerialTok: Label 'serial %1', Comment = '%1 = serial no.';
        LpTok: Label 'LP %1', Comment = '%1 = license plate no.';
}
