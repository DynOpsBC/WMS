codeunit 72050 "DOPSWHS Count Mgmt"
{
    Access = Public;

    procedure CreateSheet(LocationCode: Code[10]; CountMode: Enum "DOPSWHS Count Mode"; var Counters: array[3] of Code[50]): Code[20]
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        ItemJournalBatch: Record "Item Journal Batch";
        Counter: Record "DOPSWHS Count Counter";
        Slot: Integer;
        Dimensions: Dictionary of [Text, Text];
    begin
        CountHeader.Init();
        CountHeader.Validate("Location Code", LocationCode);
        CountHeader.Validate(Mode, CountMode);
        CountHeader.Status := CountHeader.Status::Open;
        CountHeader.Insert(true);
        CountHeader."Source Phys. Inv. Journal Batch" := EnsurePhysInvBatch(CountHeader."No.");
        CountHeader.Modify(true);

        ItemJournalBatch.Get('PHYS. INV.', CountHeader."Source Phys. Inv. Journal Batch");
        for Slot := 1 to 3 do
            if Counters[Slot] <> '' then begin
                Counter.Init();
                Counter."Sheet No." := CountHeader."No.";
                Counter."Counter Slot" := Slot;
                Counter."User ID" := Counters[Slot];
                Counter."Assigned DateTime" := CurrentDateTime();
                Counter.Insert(true);
            end;

        Dimensions.Add('sheetNo', CountHeader."No.");
        Dimensions.Add('locationCode', LocationCode);
        Session.LogMessage('AdvWMS.Count.SheetCreated', StrSubstNo('Count sheet %1 created.', CountHeader."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
        exit(CountHeader."No.");
    end;

    procedure RecordCount(SheetNo: Code[20]; LineNo: Integer; CounterSlot: Integer; Qty: Decimal)
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
    begin
        if not (CounterSlot in [1, 2, 3]) then
            Error('Counter slot must be 1, 2, or 3.');

        CountLine.Get(SheetNo, LineNo);
        case CounterSlot of
            1:
                CountLine.Validate("Counted Qty 1", Qty);
            2:
                CountLine.Validate("Counted Qty 2", Qty);
            3:
                CountLine.Validate("Counted Qty 3", Qty);
        end;
        CountLine.Modify(true);
    end;

    procedure EvaluateVariance(SheetNo: Code[20])
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        Counter: Record "DOPSWHS Count Counter";
        AssignedCounters: Integer;
        WinningQty: Decimal;
    begin
        Counter.SetRange("Sheet No.", SheetNo);
        AssignedCounters := Counter.Count();

        CountLine.SetRange("Sheet No.", SheetNo);
        if CountLine.FindSet(true) then
            repeat
                CountLine.CalcFields("System Qty");
                WinningQty := GetWinningQty(CountLine, AssignedCounters);
                CountLine.Variance := WinningQty - CountLine."System Qty";
                CountLine."Recount Required" := ShouldRecount(CountLine, AssignedCounters);
                CountLine.Modify(true);
            until CountLine.Next() = 0;
    end;

    procedure PostSheet(SheetNo: Code[20])
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        Dimensions: Dictionary of [Text, Text];
        LineNo: Integer;
    begin
        CountHeader.Get(SheetNo);
        if CountHeader.Status = CountHeader.Status::Posted then
            Error('Count sheet %1 is already posted.', SheetNo);

        EvaluateVariance(SheetNo);
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("Recount Required", true);
        if not CountLine.IsEmpty() then
            Error('Count sheet %1 has recount-required lines.', SheetNo);

        Clear(ItemJournalLine);
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
        ItemJournalLine.DeleteAll(true);

        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        if CountLine.FindSet() then
            repeat
                LineNo += 10000;
                CountLine.CalcFields("System Qty");
                ItemJournalLine.Init();
                ItemJournalLine.Validate("Journal Template Name", 'PHYS. INV.');
                ItemJournalLine.Validate("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
                ItemJournalLine."Line No." := LineNo;
                ItemJournalLine.Validate("Posting Date", Today());
                ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::"Positive Adjmt.");
                ItemJournalLine.Validate("Item No.", CountLine."Item No.");
                ItemJournalLine.Validate("Location Code", CountHeader."Location Code");
                ItemJournalLine.Validate("Bin Code", CountLine."Bin Code");
                ItemJournalLine.Validate("Variant Code", CountLine."Variant Code");
                ItemJournalLine.Validate("Qty. (Phys. Inventory)", GetWinningQty(CountLine, GetAssignedCounterCount(SheetNo)));
                ItemJournalLine.Insert(true);
            until CountLine.Next() = 0;

        ItemJournalLine.Reset();
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
        if ItemJournalLine.FindFirst() then
            ItemJnlPostBatch.Run(ItemJournalLine);

        CountHeader.Status := CountHeader.Status::Posted;
        CountHeader."Posted DateTime" := CurrentDateTime();
        CountHeader.Modify(true);

        Dimensions.Add('sheetNo', SheetNo);
        Session.LogMessage('AdvWMS.Count.SheetPosted', StrSubstNo('Count sheet %1 posted.', SheetNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    local procedure EnsurePhysInvBatch(SheetNo: Code[20]): Code[10]
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
        BatchName: Code[10];
    begin
        BatchName := CopyStr('DOPS-CNT-' + SheetNo, 1, MaxStrLen(BatchName));
        if not ItemJournalTemplate.Get('PHYS. INV.') then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'PHYS. INV.';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::"Phys. Inventory";
            ItemJournalTemplate.Insert(true);
        end;
        if not ItemJournalBatch.Get('PHYS. INV.', BatchName) then begin
            ItemJournalBatch.Init();
            ItemJournalBatch."Journal Template Name" := 'PHYS. INV.';
            ItemJournalBatch.Name := BatchName;
            ItemJournalBatch.Description := CopyStr(StrSubstNo('Count sheet %1', SheetNo), 1, MaxStrLen(ItemJournalBatch.Description));
            ItemJournalBatch.Insert(true);
        end;
        exit(BatchName);
    end;

    local procedure GetAssignedCounterCount(SheetNo: Code[20]): Integer
    var
        Counter: Record "DOPSWHS Count Counter";
    begin
        Counter.SetRange("Sheet No.", SheetNo);
        exit(Counter.Count());
    end;

    local procedure GetWinningQty(CountLine: Record "DOPSWHS Count Sheet Line"; AssignedCounters: Integer): Decimal
    begin
        if AssignedCounters >= 3 then begin
            if CountLine."Counted Qty 1" = CountLine."Counted Qty 2" then
                exit(CountLine."Counted Qty 1");
            if CountLine."Counted Qty 1" = CountLine."Counted Qty 3" then
                exit(CountLine."Counted Qty 1");
            if CountLine."Counted Qty 2" = CountLine."Counted Qty 3" then
                exit(CountLine."Counted Qty 2");
        end;
        exit(CountLine."Counted Qty 1");
    end;

    local procedure ShouldRecount(CountLine: Record "DOPSWHS Count Sheet Line"; AssignedCounters: Integer): Boolean
    begin
        if AssignedCounters < 3 then
            exit(false);
        exit((Abs(CountLine."Counted Qty 1" - CountLine."Counted Qty 2") > 0) or (Abs(CountLine."Counted Qty 1" - CountLine."Counted Qty 3") > 0) or (Abs(CountLine."Counted Qty 2" - CountLine."Counted Qty 3") > 0));
    end;
}
