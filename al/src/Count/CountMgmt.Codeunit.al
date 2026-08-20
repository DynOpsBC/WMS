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

    /// <summary>
    /// Populates count sheet lines from current Bin Content for the sheet's location, snapshotting
    /// the on-hand quantity into "System Qty". Idempotent: clears existing lines first. Returns the
    /// number of lines generated. This is the missing link that makes a sheet countable + postable.
    /// </summary>
    procedure GenerateLines(SheetNo: Code[20]) LinesCreated: Integer
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        BinContent: Record "Bin Content";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        AllocatedQty: Dictionary of [Text, Decimal];
        AllocationKey: Text;
        UomCode: Code[10];
        ResidualQty: Decimal;
        NextLineNo: Integer;
    begin
        CountHeader.Get(SheetNo);
        if CountHeader.Status = CountHeader.Status::Posted then
            Error('Count sheet %1 is already posted.', SheetNo);

        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.DeleteAll(true);

        // Önce palet/kap (LP) içerikleri ayrı satırlar olarak snapshot edilir.
        // Böylece depocu LP barkodunu okutup doğrudan o paletteki miktarı sayar.
        NextLineNo := 0;
        LPHeader.SetRange("Location Code", CountHeader."Location Code");
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                if LPHeader."Bin Code" = '' then
                    Error(LPBinMissingErr, LPHeader."No.", LPHeader."Location Code");
                LPLine.SetRange("LP No.", LPHeader."No.");
                LPLine.SetFilter("Item No.", '<>%1', '');
                if LPLine.FindSet() then
                    repeat
                        UomCode := LPLine."Unit of Measure";
                        if (UomCode = '') and Item.Get(LPLine."Item No.") then
                            UomCode := Item."Base Unit of Measure";
                        NextLineNo += 10000;
                        CountLine.Init();
                        CountLine."Sheet No." := SheetNo;
                        CountLine."Line No." := NextLineNo;
                        CountLine."Item No." := LPLine."Item No.";
                        CountLine."Variant Code" := LPLine."Variant Code";
                        CountLine."Bin Code" := LPHeader."Bin Code";
                        CountLine."LP No." := LPHeader."No.";
                        CountLine."LP Line No." := LPLine."Line No.";
                        CountLine."Lot No." := LPLine."Lot No.";
                        CountLine."Serial No." := LPLine."Serial No.";
                        CountLine."Unit of Measure Code" := UomCode;
                        CountLine."System Qty" := LPLine.Quantity;
                        CountLine.Insert(true);
                        AddAllocatedQty(AllocatedQty, AllocationKeyFor(LPLine."Item No.", LPLine."Variant Code", LPHeader."Bin Code", UomCode), LPLine.Quantity);
                        LinesCreated += 1;
                    until LPLine.Next() = 0;
                LPLine.Reset();
            until LPHeader.Next() = 0;

        // LP'ye bağlı olmayan stok ayrıca sayılır. Aynı stok hem LP satırında hem
        // bin satırında iki kez oluşmasın diye LP miktarı bin içeriğinden düşülür.
        BinContent.SetRange("Location Code", CountHeader."Location Code");
        if BinContent.FindSet() then
            repeat
                BinContent.CalcFields(Quantity);
                AllocationKey := AllocationKeyFor(BinContent."Item No.", BinContent."Variant Code", BinContent."Bin Code", BinContent."Unit of Measure Code");
                ResidualQty := BinContent.Quantity;
                if AllocatedQty.ContainsKey(AllocationKey) then
                    ResidualQty -= AllocatedQty.Get(AllocationKey);
                if ResidualQty < 0 then
                    Error(LPExceedsInventoryErr, BinContent."Item No.", BinContent."Bin Code", -ResidualQty);
                if ResidualQty <> 0 then begin
                    NextLineNo += 10000;
                    CountLine.Init();
                    CountLine."Sheet No." := SheetNo;
                    CountLine."Line No." := NextLineNo;
                    CountLine."Item No." := BinContent."Item No.";
                    CountLine."Variant Code" := BinContent."Variant Code";
                    CountLine."Bin Code" := BinContent."Bin Code";
                    CountLine."Unit of Measure Code" := BinContent."Unit of Measure Code";
                    CountLine."System Qty" := ResidualQty;
                    CountLine.Insert(true);
                    LinesCreated += 1;
                end;
            until BinContent.Next() = 0;
    end;

    /// <summary>Adds (or refreshes) a single count line for a specific item/bin, snapshotting on-hand.</summary>
    procedure AddLine(SheetNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; BinCode: Code[20]): Integer
    var
        CountHeader: Record "DOPSWHS Count Sheet Header";
        CountLine: Record "DOPSWHS Count Sheet Line";
        BinContent: Record "Bin Content";
        Item: Record Item;
        NextLineNo: Integer;
        OnHand: Decimal;
    begin
        CountHeader.Get(SheetNo);
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetRange("Item No.", ItemNo);
        CountLine.SetRange("Bin Code", BinCode);
        if CountLine.FindFirst() then
            exit(CountLine."Line No.");

        if BinContent.Get(CountHeader."Location Code", BinCode, ItemNo, VariantCode, '') then begin
            BinContent.CalcFields(Quantity);
            OnHand := BinContent.Quantity;
        end;

        CountLine.Reset();
        CountLine.SetRange("Sheet No.", SheetNo);
        if CountLine.FindLast() then
            NextLineNo := CountLine."Line No.";
        NextLineNo += 10000;

        CountLine.Init();
        CountLine."Sheet No." := SheetNo;
        CountLine."Line No." := NextLineNo;
        CountLine."Item No." := ItemNo;
        CountLine."Variant Code" := VariantCode;
        CountLine."Bin Code" := BinCode;
        if Item.Get(ItemNo) then
            CountLine."Unit of Measure Code" := Item."Base Unit of Measure";
        CountLine."System Qty" := OnHand;
        CountLine.Insert(true);
        exit(NextLineNo);
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
                ItemJournalLine.Init();
                ItemJournalLine.Validate("Journal Template Name", 'PHYS. INV.');
                ItemJournalLine.Validate("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
                ItemJournalLine."Line No." := LineNo;
                ItemJournalLine.Validate("Posting Date", Today());
                ItemJournalLine."Document No." := CopyStr('CNT-' + SheetNo, 1, MaxStrLen(ItemJournalLine."Document No."));
                ItemJournalLine.Validate("Item No.", CountLine."Item No.");
                ItemJournalLine.Validate("Location Code", CountHeader."Location Code");
                ItemJournalLine.Validate("Variant Code", CountLine."Variant Code");
                ItemJournalLine.Validate("Bin Code", CountLine."Bin Code");
                if CountLine."Unit of Measure Code" <> '' then
                    ItemJournalLine.Validate("Unit of Measure Code", CountLine."Unit of Measure Code");
                // Phys. inventory line: BC derives entry type + quantity from calculated vs counted.
                ItemJournalLine.Validate("Phys. Inventory", true);
                ItemJournalLine.Validate("Qty. (Calculated)", CountLine."System Qty");
                ItemJournalLine.Validate("Qty. (Phys. Inventory)", GetWinningQty(CountLine, GetAssignedCounterCount(SheetNo)));
                ItemJournalLine.Insert(true);
                AddItemTracking(ItemJournalLine, CountLine."Lot No.", CountLine."Serial No.");
            until CountLine.Next() = 0;

        EnsureLicensePlateReferencesExist(SheetNo);

        ItemJournalLine.Reset();
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", CountHeader."Source Phys. Inv. Journal Batch");
        if ItemJournalLine.FindFirst() then
            ItemJnlPostBatch.Run(ItemJournalLine);

        // BC stok postu başarılı olduktan sonra LP içeriğini aynı kazanan sayım
        // miktarıyla eşitle. Böylece etiket ve bir sonraki LP sorgusu yeni miktarı gösterir.
        ApplyWinningCountsToLicensePlates(SheetNo);

        CountHeader.Status := CountHeader.Status::Posted;
        CountHeader."Posted DateTime" := CurrentDateTime();
        CountHeader.Modify(true);

        Dimensions.Add('sheetNo', SheetNo);
        Session.LogMessage('AdvWMS.Count.SheetPosted', StrSubstNo('Count sheet %1 posted.', SheetNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    local procedure EnsureLicensePlateReferencesExist(SheetNo: Code[20])
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        LPLine: Record "DOPSWHS LP Line";
    begin
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetFilter("LP No.", '<>%1', '');
        if CountLine.FindSet() then
            repeat
                if not LPLine.Get(CountLine."LP No.", CountLine."LP Line No.") then
                    Error(LPLineMissingErr, CountLine."LP No.", CountLine."LP Line No.");
            until CountLine.Next() = 0;
    end;

    local procedure AllocationKeyFor(ItemNo: Code[20]; VariantCode: Code[10]; BinCode: Code[20]; UomCode: Code[10]): Text
    begin
        exit(ItemNo + '|' + VariantCode + '|' + BinCode + '|' + UomCode);
    end;

    local procedure AddAllocatedQty(var AllocatedQty: Dictionary of [Text, Decimal]; AllocationKeyValue: Text; Qty: Decimal)
    begin
        if AllocatedQty.ContainsKey(AllocationKeyValue) then
            AllocatedQty.Set(AllocationKeyValue, AllocatedQty.Get(AllocationKeyValue) + Qty)
        else
            AllocatedQty.Add(AllocationKeyValue, Qty);
    end;

    local procedure ApplyWinningCountsToLicensePlates(SheetNo: Code[20])
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        LPLine: Record "DOPSWHS LP Line";
        AssignedCounters: Integer;
    begin
        AssignedCounters := GetAssignedCounterCount(SheetNo);
        CountLine.SetRange("Sheet No.", SheetNo);
        CountLine.SetFilter("LP No.", '<>%1', '');
        if CountLine.FindSet() then
            repeat
                if not LPLine.Get(CountLine."LP No.", CountLine."LP Line No.") then
                    Error(LPLineMissingErr, CountLine."LP No.", CountLine."LP Line No.");
                LPLine.Validate(Quantity, GetWinningQty(CountLine, AssignedCounters));
                LPLine.Modify(true);
            until CountLine.Next() = 0;
    end;

    local procedure AddItemTracking(var ItemJournalLine: Record "Item Journal Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        TempReservEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        if ((LotNo = '') and (SerialNo = '')) or (ItemJournalLine.Quantity = 0) then
            exit;
        TempReservEntry."Lot No." := LotNo;
        TempReservEntry."Serial No." := SerialNo;
        CreateReservEntry.CreateReservEntryFor(
            Database::"Item Journal Line", ItemJournalLine."Entry Type".AsInteger(),
            ItemJournalLine."Journal Template Name", ItemJournalLine."Journal Batch Name", 0,
            ItemJournalLine."Line No.", ItemJournalLine."Qty. per Unit of Measure",
            ItemJournalLine.Quantity, ItemJournalLine."Quantity (Base)", TempReservEntry);
        CreateReservEntry.CreateEntry(
            ItemJournalLine."Item No.", ItemJournalLine."Variant Code", ItemJournalLine."Location Code",
            ItemJournalLine.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    procedure EnsurePhysInvBatch(SheetNo: Code[20]): Code[10]
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

    var
        LPExceedsInventoryErr: Label '%1 ürününün %2 rafındaki LP miktarı BC stok miktarını %3 aşıyor. Sayım satırları üretilmeden önce LP/bin tutarsızlığını düzeltin.', Comment = '%1 item, %2 bin, %3 excess qty';
        LPLineMissingErr: Label '%1 LP numarasının %2 satırı artık bulunamadı. Sayım satırlarını yeniden üretin.', Comment = '%1 LP, %2 line';
        LPBinMissingErr: Label '%1 LP numarası %2 lokasyonunda ancak raf/bin bilgisi boştur. LP sayım satırları üretilmeden önce paleti doğru rafa taşıyın.', Comment = '%1 LP, %2 location';
}
