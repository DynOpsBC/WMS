codeunit 72005 "DOPSWHS Cycle Count Mgmt"
{
    // KIT-014 (Kitoko, Kas 2026): cycle counting of critical items on top of the
    // standard Phys. Invt. Counting Periods. Critical items (or SKUs) get a
    // counting period on their card; the Cycle Count Plan lists the items that
    // are due and creates a WMS count sheet for the selected ones (counted on the
    // terminal like any count sheet). Posting that sheet moves the counted items
    // to their next counting period, with the same calculation BC uses when a
    // phys. inventory journal created by "Calculate Counting Period" is posted.
    Access = Public;
    Permissions =
        tabledata Item = rm,
        tabledata "Stockkeeping Unit" = rm;

    /// <summary>Creates a count sheet at the location for the selected items (all their bins and LPs) and returns its No.</summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Count Sheet Header", 'RM')]
    procedure CreateCycleCountSheet(var Item: Record Item; LocationCode: Code[10]; CountMode: Enum "DOPSWHS Count Mode"; var LinesCreated: Integer): Code[20]
    var
        Location: Record Location;
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        SelectionFilterManagement: Codeunit SelectionFilterManagement;
        Counters: array[3] of Code[50];
        ItemFilter: Text;
        SheetNo: Code[20];
        Dimensions: Dictionary of [Text, Text];
    begin
        if LocationCode = '' then
            Error(LocationRequiredErr);
        Location.Get(LocationCode);
        ItemFilter := SelectionFilterManagement.GetSelectionFilterForItem(Item);
        if ItemFilter = '' then
            Error(NoItemsSelectedErr);
        SheetNo := CountMgmt.CreateSheet(LocationCode, CountMode, Counters);
        CountHeader.Get(SheetNo);
        CountHeader."Cycle Count" := true;
        CountHeader.Modify(true);
        LinesCreated := CountMgmt.GenerateLinesForItems(SheetNo, ItemFilter);
        Dimensions.Add('sheetNo', SheetNo);
        Dimensions.Add('locationCode', LocationCode);
        Dimensions.Add('lines', Format(LinesCreated));
        Session.LogMessage('AdvWMS.Count.CycleCountCreated', StrSubstNo('Cycle count sheet %1 created.', SheetNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
        exit(SheetNo);
    end;

    /// <summary>
    /// After a cycle count sheet (or a later round of it) is posted: every counted
    /// item/SKU with a counting period gets "Last Counting Period Update" = work
    /// date and its next counting period.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Count Sheet Line", 'R')]
    procedure UpdateCountingPeriods(CountHeader: Record "DOPSWHS Count Sheet Header")
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        StockkeepingUnit: Record "Stockkeeping Unit";
        Item: Record Item;
        DoneSkus: List of [Text];
        DoneItems: List of [Code[20]];
        SkuKey: Text;
    begin
        if not IsCycleCount(CountHeader) then
            exit;
        CountLine.SetRange("Sheet No.", CountHeader."No.");
        CountLine.SetLoadFields("Item No.", "Variant Code");
        if not CountLine.FindSet() then
            exit;
        repeat
            SkuKey := CountLine."Item No." + '|' + CountLine."Variant Code";
            if not DoneSkus.Contains(SkuKey) then begin
                DoneSkus.Add(SkuKey);
                if StockkeepingUnit.Get(CountHeader."Location Code", CountLine."Item No.", CountLine."Variant Code") and
                   (StockkeepingUnit."Phys Invt Counting Period Code" <> '')
                then
                    UpdateSku(StockkeepingUnit)
                else
                    if not DoneItems.Contains(CountLine."Item No.") then begin
                        DoneItems.Add(CountLine."Item No.");
                        if Item.Get(CountLine."Item No.") then
                            if Item."Phys Invt Counting Period Code" <> '' then
                                UpdateItem(Item);
                    end;
            end;
        until CountLine.Next() = 0;
    end;

    /// <summary>Counting status of an item/SKU: not planned, not due, due, overdue.</summary>
    procedure GetDueStatus(LastCountingUpdate: Date; NextStartDate: Date; NextEndDate: Date): Text
    begin
        case DueState(LastCountingUpdate, NextStartDate, NextEndDate) of
            1:
                exit(NotDueTxt);
            2:
                exit(DueTxt);
            3:
                exit(OverdueTxt);
        end;
        exit(NotPlannedTxt);
    end;

    /// <summary>Style for the counting status (Unfavorable = overdue, Attention = due).</summary>
    procedure GetDueStyle(LastCountingUpdate: Date; NextStartDate: Date; NextEndDate: Date): Text
    begin
        case DueState(LastCountingUpdate, NextStartDate, NextEndDate) of
            1:
                exit('Favorable');
            2:
                exit('Attention');
            3:
                exit('Unfavorable');
        end;
        exit('Standard');
    end;

    /// <summary>True when the item/SKU is due or overdue for counting.</summary>
    procedure IsDue(LastCountingUpdate: Date; NextStartDate: Date; NextEndDate: Date): Boolean
    begin
        exit(DueState(LastCountingUpdate, NextStartDate, NextEndDate) >= 2);
    end;

    // 0 = not planned, 1 = not due, 2 = due, 3 = overdue (same rule as the
    // standard "Calculate Counting Period": due once the period has started and
    // the item was not counted since).
    local procedure DueState(LastCountingUpdate: Date; NextStartDate: Date; NextEndDate: Date): Integer
    begin
        if (NextStartDate = 0D) or (NextEndDate = 0D) then
            exit(0);
        if (LastCountingUpdate >= NextStartDate) or (WorkDate() < NextStartDate) then
            exit(1);
        if WorkDate() > NextEndDate then
            exit(3);
        exit(2);
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Count Sheet Header", 'R')]
    procedure IsCycleCount(CountHeader: Record "DOPSWHS Count Sheet Header"): Boolean
    var
        RootHeader: Record "DOPSWHS Count Sheet Header";
    begin
        if CountHeader."Cycle Count" then
            exit(true);
        // Later rounds (Start Next Round) are separate sheets of the same count.
        if (CountHeader."Round Root No." <> '') and (CountHeader."Round Root No." <> CountHeader."No.") then
            if RootHeader.Get(CountHeader."Round Root No.") then
                exit(RootHeader."Cycle Count");
        exit(false);
    end;

    local procedure UpdateItem(var Item: Record Item)
    var
        PhysInvtCountingPeriod: Record "Phys. Invt. Counting Period";
        PhysInvtCountManagement: Codeunit "Phys. Invt. Count.-Management";
    begin
        if not PhysInvtCountingPeriod.Get(Item."Phys Invt Counting Period Code") then
            exit;
        if PhysInvtCountingPeriod."Count Frequency per Year" = 0 then
            exit;
        Item."Last Counting Period Update" := WorkDate();
        PhysInvtCountManagement.CalcPeriod(
            Item."Last Counting Period Update", Item."Next Counting Start Date", Item."Next Counting End Date",
            PhysInvtCountingPeriod."Count Frequency per Year");
        Item.Modify();
    end;

    local procedure UpdateSku(var StockkeepingUnit: Record "Stockkeeping Unit")
    var
        PhysInvtCountingPeriod: Record "Phys. Invt. Counting Period";
        PhysInvtCountManagement: Codeunit "Phys. Invt. Count.-Management";
    begin
        if not PhysInvtCountingPeriod.Get(StockkeepingUnit."Phys Invt Counting Period Code") then
            exit;
        if PhysInvtCountingPeriod."Count Frequency per Year" = 0 then
            exit;
        StockkeepingUnit."Last Counting Period Update" := WorkDate();
        PhysInvtCountManagement.CalcPeriod(
            StockkeepingUnit."Last Counting Period Update", StockkeepingUnit."Next Counting Start Date", StockkeepingUnit."Next Counting End Date",
            PhysInvtCountingPeriod."Count Frequency per Year");
        StockkeepingUnit.Modify();
    end;

    var
        LocationRequiredErr: Label 'Select the location to count.';
        NoItemsSelectedErr: Label 'Select the items to count.';
        NotPlannedTxt: Label 'Not Planned';
        NotDueTxt: Label 'Not Due';
        DueTxt: Label 'Due';
        OverdueTxt: Label 'Overdue';
}
