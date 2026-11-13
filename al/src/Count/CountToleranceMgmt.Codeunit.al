codeunit 72004 "DOPSWHS Count Tolerance Mgmt"
{
    // KIT-014 (Kitoko, Kas 2026): count variance tolerance. A line exceeds the
    // tolerance when its variance is above "Count Tolerance %" of the system
    // quantity or above "Count Tolerance Amount (LCY)" (base quantity x item
    // unit cost); with both thresholds 0 every variance counts as exceeding.
    // Warning: the user confirms before posting. Approval Required: a user on
    // the inventory approver list ("Approve Count Variance") approves the count
    // sheet (or posts the phys. inventory journal himself) first. The check
    // runs for WMS count sheets (Count Mgmt.PostSheet, BC and terminal) and for
    // standard phys. inventory journals. Default: Disabled.
    Access = Public;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    procedure GetToleranceSetup(var ToleranceCheck: Enum "DOPSWHS Count Tolerance Check"; var TolerancePct: Decimal; var ToleranceAmount: Decimal)
    var
        Setup: Record "DOPSWHS Setup";
    begin
        ToleranceCheck := ToleranceCheck::Disabled;
        TolerancePct := 0;
        ToleranceAmount := 0;
        Setup.SetLoadFields("Count Tolerance Check", "Count Tolerance %", "Count Tolerance Amount");
        if not Setup.Get('') then
            exit;
        ToleranceCheck := Setup."Count Tolerance Check";
        TolerancePct := Setup."Count Tolerance %";
        ToleranceAmount := Setup."Count Tolerance Amount";
    end;

    /// <summary>
    /// Variance % (of the system quantity; 100 when the system quantity is 0)
    /// and value (LCY) of a counted line. Returns true when it exceeds the tolerance.
    /// </summary>
    procedure EvaluateVariance(ItemNo: Code[20]; UomCode: Code[10]; SystemQty: Decimal; VarianceQty: Decimal; var VariancePct: Decimal; var VarianceAmount: Decimal): Boolean
    var
        ToleranceCheck: Enum "DOPSWHS Count Tolerance Check";
        TolerancePct: Decimal;
        ToleranceAmount: Decimal;
    begin
        GetToleranceSetup(ToleranceCheck, TolerancePct, ToleranceAmount);
        exit(EvaluateVarianceWith(ItemNo, UomCode, SystemQty, VarianceQty, TolerancePct, ToleranceAmount, VariancePct, VarianceAmount));
    end;

    local procedure EvaluateVarianceWith(ItemNo: Code[20]; UomCode: Code[10]; SystemQty: Decimal; VarianceQty: Decimal; TolerancePct: Decimal; ToleranceAmount: Decimal; var VariancePct: Decimal; var VarianceAmount: Decimal): Boolean
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        GeneralLedgerSetup: Record "General Ledger Setup";
        QtyPerUom: Decimal;
    begin
        VariancePct := 0;
        VarianceAmount := 0;
        if VarianceQty = 0 then
            exit(false);
        QtyPerUom := 1;
        if UomCode <> '' then
            if ItemUnitOfMeasure.Get(ItemNo, UomCode) then
                if ItemUnitOfMeasure."Qty. per Unit of Measure" <> 0 then
                    QtyPerUom := ItemUnitOfMeasure."Qty. per Unit of Measure";
        Item.SetLoadFields("Unit Cost");
        if Item.Get(ItemNo) then begin
            GeneralLedgerSetup.SetLoadFields("Amount Rounding Precision");
            GeneralLedgerSetup.Get();
            VarianceAmount := Round(Abs(VarianceQty) * QtyPerUom * Item."Unit Cost", GeneralLedgerSetup."Amount Rounding Precision");
        end;
        if SystemQty <> 0 then
            VariancePct := Round(Abs(VarianceQty) / Abs(SystemQty) * 100, 0.01)
        else
            VariancePct := 100;
        if (TolerancePct = 0) and (ToleranceAmount = 0) then
            exit(true);
        exit(((TolerancePct > 0) and (VariancePct > TolerancePct)) or ((ToleranceAmount > 0) and (VarianceAmount > ToleranceAmount)));
    end;

    /// <summary>Lines of a count sheet above the tolerance and their total variance value (uses the evaluated Variance of each line).</summary>
    procedure GetSheetSummary(SheetNo: Code[20]; var ExceedingLines: Integer; var ExceedingAmount: Decimal; var TotalVarianceAmount: Decimal)
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        ToleranceCheck: Enum "DOPSWHS Count Tolerance Check";
        TolerancePct: Decimal;
        ToleranceAmount: Decimal;
        VariancePct: Decimal;
        VarianceAmount: Decimal;
    begin
        ExceedingLines := 0;
        ExceedingAmount := 0;
        TotalVarianceAmount := 0;
        GetToleranceSetup(ToleranceCheck, TolerancePct, ToleranceAmount);
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetFilter(Variance, '<>0');
        CountLine.SetLoadFields("Item No.", "Unit of Measure Code", "System Qty", Variance);
        if CountLine.FindSet() then
            repeat
                if EvaluateVarianceWith(CountLine."Item No.", CountLine."Unit of Measure Code", CountLine."System Qty", CountLine.Variance, TolerancePct, ToleranceAmount, VariancePct, VarianceAmount) then begin
                    ExceedingLines += 1;
                    ExceedingAmount += VarianceAmount;
                end;
                TotalVarianceAmount += VarianceAmount;
            until CountLine.Next() = 0;
    end;

    /// <summary>
    /// Called by Count Mgmt.PostSheet after the variances are evaluated and
    /// before any stock is posted. CountHeader is the posting's locked record;
    /// an approval given here is written to it.
    /// </summary>
    procedure CheckSheetBeforePost(var CountHeader: Record "DOPSWHS Count Sheet Header")
    var
        ToleranceCheck: Enum "DOPSWHS Count Tolerance Check";
        TolerancePct: Decimal;
        ToleranceAmount: Decimal;
        ExceedingLines: Integer;
        ExceedingAmount: Decimal;
        TotalVarianceAmount: Decimal;
    begin
        GetToleranceSetup(ToleranceCheck, TolerancePct, ToleranceAmount);
        if ToleranceCheck = ToleranceCheck::Disabled then
            exit;
        GetSheetSummary(CountHeader."No.", ExceedingLines, ExceedingAmount, TotalVarianceAmount);
        if ExceedingLines = 0 then
            exit;
        case ToleranceCheck of
            ToleranceCheck::Warning:
                begin
                    if GuiAllowed() then
                        if not Confirm(SheetWarningQst, false, CountHeader."No.", ExceedingLines, ExceedingAmount, ToleranceText(TolerancePct, ToleranceAmount)) then
                            Error('');
                    LogTolerance('AdvWMS.Count.ToleranceWarning', CountHeader."No.", ExceedingLines, ExceedingAmount);
                end;
            ToleranceCheck::"Approval Required":
                begin
                    if ApprovalStillValid(CountHeader, ExceedingLines, ExceedingAmount) then
                        exit;
                    // Terminal postings run under a shared service account: only
                    // an approval recorded beforehand in BC counts there.
                    if GuiAllowed() and IsCountApprover(UserId()) then
                        if Confirm(ApproveAndPostQst, false, CountHeader."No.", ExceedingLines, ExceedingAmount) then begin
                            RecordApproval(CountHeader, ExceedingLines, ExceedingAmount);
                            exit;
                        end else
                            Error('');
                    Error(SheetApprovalRequiredErr, CountHeader."No.", ExceedingLines, ExceedingAmount, ToleranceText(TolerancePct, ToleranceAmount));
                end;
        end;
    end;

    /// <summary>Approves the variances above tolerance of a count sheet (Count Sheet Card action).</summary>
    procedure ApproveSheet(SheetNo: Code[20])
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        ExceedingLines: Integer;
        ExceedingAmount: Decimal;
        TotalVarianceAmount: Decimal;
    begin
        if not IsCountApprover(UserId()) then
            Error(NotApproverErr, UserId());
        CountMgmt.AssertActiveRound(SheetNo);
        CountMgmt.EvaluateVariance(SheetNo);
        CountHeader.LockTable();
        CountHeader.Get(SheetNo);
        if CountHeader.Status = CountHeader.Status::Posted then
            Error(SheetPostedErr, SheetNo);
        GetSheetSummary(SheetNo, ExceedingLines, ExceedingAmount, TotalVarianceAmount);
        if ExceedingLines = 0 then begin
            Message(NothingToApproveMsg, SheetNo);
            exit;
        end;
        if not Confirm(ApproveQst, false, SheetNo, ExceedingLines, ExceedingAmount) then
            exit;
        RecordApproval(CountHeader, ExceedingLines, ExceedingAmount);
    end;

    local procedure ApprovalStillValid(CountHeader: Record "DOPSWHS Count Sheet Header"; ExceedingLines: Integer; ExceedingAmount: Decimal): Boolean
    begin
        exit(
            (CountHeader."Variance Approved By" <> '') and
            (CountHeader."Approved Exceeding Lines" = ExceedingLines) and
            (CountHeader."Approved Variance Amount" = ExceedingAmount));
    end;

    local procedure RecordApproval(var CountHeader: Record "DOPSWHS Count Sheet Header"; ExceedingLines: Integer; ExceedingAmount: Decimal)
    begin
        CountHeader."Variance Approved By" := CopyStr(UserId(), 1, MaxStrLen(CountHeader."Variance Approved By"));
        CountHeader."Variance Approved At" := CurrentDateTime();
        CountHeader."Approved Exceeding Lines" := ExceedingLines;
        CountHeader."Approved Variance Amount" := ExceedingAmount;
        CountHeader.Modify(true);
        LogTolerance('AdvWMS.Count.ToleranceApproved', CountHeader."No.", ExceedingLines, ExceedingAmount);
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Inventory Approver", 'R')]
    procedure IsCountApprover(UserName: Text): Boolean
    var
        InventoryApprover: Record "DOPSWHS Inventory Approver";
    begin
        if UserName = '' then
            exit(false);
        InventoryApprover.SetRange("User ID", CopyStr(UserName, 1, MaxStrLen(InventoryApprover."User ID")));
        InventoryApprover.SetRange("Approve Count Variance", true);
        exit(not InventoryApprover.IsEmpty());
    end;

    // -------------------------------------------------------------------------
    // Standard phys. inventory journal (not created by a WMS count sheet)
    // -------------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Batch", 'OnBeforeCheckLines', '', false, false)]
    local procedure CheckPhysInventoryJournal(var ItemJnlLine: Record "Item Journal Line"; var WindowIsOpen: Boolean)
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalLine: Record "Item Journal Line";
        ToleranceCheck: Enum "DOPSWHS Count Tolerance Check";
        TolerancePct: Decimal;
        ToleranceAmount: Decimal;
        VariancePct: Decimal;
        VarianceAmount: Decimal;
        ExceedingLines: Integer;
        ExceedingAmount: Decimal;
    begin
        if ItemJnlLine.IsTemporary() then
            exit;
        GetToleranceSetup(ToleranceCheck, TolerancePct, ToleranceAmount);
        if ToleranceCheck = ToleranceCheck::Disabled then
            exit;
        ItemJournalTemplate.SetLoadFields(Type);
        if not ItemJournalTemplate.Get(ItemJnlLine."Journal Template Name") then
            exit;
        if ItemJournalTemplate.Type <> ItemJournalTemplate.Type::"Phys. Inventory" then
            exit;
        // Count sheet postings were checked (and approved) on the sheet itself;
        // a WMS first count is the opening stock load, not a periodic count.
        if IsCountSheetBatch(ItemJnlLine."Journal Batch Name") or IsFirstCountDocument(ItemJnlLine."Document No.") then
            exit;
        ItemJournalLine.SetRange("Journal Template Name", ItemJnlLine."Journal Template Name");
        ItemJournalLine.SetRange("Journal Batch Name", ItemJnlLine."Journal Batch Name");
        ItemJournalLine.SetRange("Phys. Inventory", true);
        ItemJournalLine.SetLoadFields("Item No.", "Unit of Measure Code", "Qty. (Calculated)", "Qty. (Phys. Inventory)");
        if ItemJournalLine.FindSet() then
            repeat
                if EvaluateVarianceWith(
                    ItemJournalLine."Item No.", ItemJournalLine."Unit of Measure Code", ItemJournalLine."Qty. (Calculated)",
                    ItemJournalLine."Qty. (Phys. Inventory)" - ItemJournalLine."Qty. (Calculated)",
                    TolerancePct, ToleranceAmount, VariancePct, VarianceAmount)
                then begin
                    ExceedingLines += 1;
                    ExceedingAmount += VarianceAmount;
                end;
            until ItemJournalLine.Next() = 0;
        if ExceedingLines = 0 then
            exit;
        case ToleranceCheck of
            ToleranceCheck::Warning:
                if GuiAllowed() then
                    if not Confirm(JournalWarningQst, false, ExceedingLines, ExceedingAmount, ToleranceText(TolerancePct, ToleranceAmount)) then
                        Error('');
            ToleranceCheck::"Approval Required":
                if not IsCountApprover(UserId()) then
                    Error(JournalApprovalRequiredErr, ItemJnlLine."Journal Batch Name", ExceedingLines, ExceedingAmount, ToleranceText(TolerancePct, ToleranceAmount));
        end;
        LogTolerance('AdvWMS.Count.JournalTolerance', ItemJnlLine."Journal Batch Name", ExceedingLines, ExceedingAmount);
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Count Sheet Header", 'R')]
    local procedure IsCountSheetBatch(BatchName: Code[10]): Boolean
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
    begin
        if BatchName = '' then
            exit(false);
        CountHeader.SetRange("Source Phys. Inv. Journal Batch", BatchName);
        exit(not CountHeader.IsEmpty());
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS First Count Header", 'R')]
    local procedure IsFirstCountDocument(DocumentNo: Code[20]): Boolean
    var
        FirstCountHeader: Record "DOPSWHS First Count Header";
    begin
        if DocumentNo = '' then
            exit(false);
        FirstCountHeader.SetLoadFields("No.");
        exit(FirstCountHeader.Get(DocumentNo));
    end;

    procedure ToleranceText(TolerancePct: Decimal; ToleranceAmount: Decimal): Text
    begin
        if (TolerancePct = 0) and (ToleranceAmount = 0) then
            exit(ZeroToleranceTxt);
        if ToleranceAmount = 0 then
            exit(StrSubstNo(PctToleranceTxt, TolerancePct));
        if TolerancePct = 0 then
            exit(StrSubstNo(AmountToleranceTxt, ToleranceAmount));
        exit(StrSubstNo(BothToleranceTxt, TolerancePct, ToleranceAmount));
    end;

    local procedure LogTolerance(EventId: Text; DocumentNo: Code[20]; ExceedingLines: Integer; ExceedingAmount: Decimal)
    var
        Dimensions: Dictionary of [Text, Text];
    begin
        Dimensions.Add('documentNo', DocumentNo);
        Dimensions.Add('exceedingLines', Format(ExceedingLines));
        Dimensions.Add('exceedingAmount', Format(ExceedingAmount, 0, 9));
        Session.LogMessage(EventId, StrSubstNo('Count tolerance %1 for %2', EventId, DocumentNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    var
        SheetWarningQst: Label 'Count sheet %1 has %2 line(s) above the count tolerance (%4), total variance value %3. Do you want to post it anyway?', Comment = '%1 = count sheet no., %2 = number of lines, %3 = variance amount, %4 = tolerance text';
        ApproveAndPostQst: Label 'Count sheet %1 has %2 line(s) above the count tolerance, total variance value %3. You are an inventory control approver. Approve the variances and post?', Comment = '%1 = count sheet no., %2 = number of lines, %3 = variance amount';
        SheetApprovalRequiredErr: Label 'Count sheet %1 has %2 line(s) above the count tolerance (%4), total variance value %3. An inventory control approver must approve the variances (Approve Variances on the count sheet) before it can be posted.', Comment = '%1 = count sheet no., %2 = number of lines, %3 = variance amount, %4 = tolerance text';
        ApproveQst: Label 'Approve %2 line(s) above the count tolerance on count sheet %1 (total variance value %3)?', Comment = '%1 = count sheet no., %2 = number of lines, %3 = variance amount';
        NothingToApproveMsg: Label 'Count sheet %1 has no variance above the count tolerance.', Comment = '%1 = count sheet no.';
        NotApproverErr: Label 'User %1 is not an inventory control approver for count variances (Inventory Control Approvers).', Comment = '%1 = user id';
        SheetPostedErr: Label 'Count sheet %1 is already posted.', Comment = '%1 = count sheet no.';
        JournalWarningQst: Label 'The phys. inventory journal has %1 line(s) above the count tolerance (%3), total variance value %2. Do you want to post it anyway?', Comment = '%1 = number of lines, %2 = variance amount, %3 = tolerance text';
        JournalApprovalRequiredErr: Label 'Phys. inventory journal batch %1 has %2 line(s) above the count tolerance (%4), total variance value %3. Only an inventory control approver can post it.', Comment = '%1 = journal batch, %2 = number of lines, %3 = variance amount, %4 = tolerance text';
        ZeroToleranceTxt: Label 'no tolerance';
        PctToleranceTxt: Label '%1 percent', Comment = '%1 = tolerance percentage';
        AmountToleranceTxt: Label '%1 LCY', Comment = '%1 = tolerance amount';
        BothToleranceTxt: Label '%1 percent or %2 LCY', Comment = '%1 = tolerance percentage, %2 = tolerance amount';
}
