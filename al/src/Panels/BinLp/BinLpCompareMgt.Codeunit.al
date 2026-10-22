codeunit 72396 "DOPSWHS Bin LP Compare Mgt"
{
    // Göz ve LP Karşılaştırma (yönetici ekranı). Bir lokasyondaki her göz +
    // madde + varyant + lot için BC stoğunu (Göz İçeriği / Depo Girişleri,
    // temel birimde) o gözdeki aktif LP miktarıyla (Açık/Oluşturuldu/Atandı,
    // LP satırı temel birime çevrilmiş) karşılaştırır; farkın olası nedenini
    // (geri alınan mal kabul, yetim atama, lot uyuşmazlığı, başka göz) bulur.
    // Sınırlı: önce lokasyona göre süzülür, gruplama sözlüklerle yapılır,
    // pahalı neden aramaları yalnız farklı satırlarda çalışır.
    // Kitoko (22 Eki 2026): göz zorunlu OLMAYAN lokasyonda karşılaştırma
    // lokasyon düzeyindedir: stok madde girişlerinden (açık girişlerin kalan
    // miktarı), LP'ler gözüne bakılmadan; satırın göz kodu boş kalır.

    var
        LPManagement: Codeunit "DOPSWHS Panel LP Repair";
        RowIndex: Dictionary of [Text, Integer];
        LpSeenInRow: Dictionary of [Text, Boolean];
        RowSourceEntries: Dictionary of [Integer, Text];
        ItemDescriptionCache: Dictionary of [Code[20], Text];
        ItemBaseUomCache: Dictionary of [Code[20], Code[10]];
        ItemTrackedCache: Dictionary of [Code[20], Boolean];
        QtyPerUomCache: Dictionary of [Text, Decimal];
        BinZoneCache: Dictionary of [Code[20], Code[10]];
        OrphanCache: Dictionary of [Code[20], Boolean];
        UndoCandidatesCache: Dictionary of [Integer, Text];
        UndoPreviewCache: Dictionary of [Integer, Integer];
        LpDetails: JsonObject;
        LastEntryNo: Integer;
        CurrLocation: Code[10];
        CurrZone: Code[10];
        CurrBinFrom: Code[20];
        CurrBinTo: Code[20];
        CurrItemFilter: Text;
        CurrBinMandatory: Boolean;
        LocationRequiredErr: Label 'Karşılaştırma için bir lokasyon seçin.';
        MaxJsonRows: Integer;

    /// <summary>
    /// Karşılaştırmayı çalıştırır ve geçici tabloyu doldurur. Her iki tarafı da
    /// sıfır olan satırlar yazılmaz.
    /// </summary>
    procedure Compare(LocationCode: Code[10]; ZoneCode: Code[10]; BinFrom: Code[20]; BinTo: Code[20]; ItemFilter: Text; var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    begin
        if LocationCode = '' then
            Error(LocationRequiredErr);
        ResetState();
        CurrLocation := LocationCode;
        CurrZone := ZoneCode;
        CurrBinFrom := BinFrom;
        CurrBinTo := BinTo;
        CurrItemFilter := ItemFilter;
        CurrBinMandatory := IsBinMandatoryLocation(LocationCode);
        TempRow.Reset();
        TempRow.DeleteAll();

        if CurrBinMandatory then
            CollectBinStock(TempRow)
        else
            CollectLocationStock(TempRow);
        CollectLpQuantities(TempRow);
        ClassifyRows(TempRow);
        DetectUndoneReceipts(TempRow);
        DetectOrphanAssignments(TempRow);
        DetectLotAndBinMismatches(TempRow);
        TempRow.Reset();
    end;

    /// <summary>Ekran için JSON: filtreler, seçim listeleri, özet ve satırlar.</summary>
    procedure BuildDataJson(FilterJsonText: Text): Text
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
        Result: JsonObject;
        ResultText: Text;
        LocationCode: Code[10];
        ZoneCode: Code[10];
        BinFrom: Code[20];
        BinTo: Code[20];
        ItemFilter: Text;
        OnlyDiff: Boolean;
    begin
        ParseFilter(FilterJsonText, LocationCode, ZoneCode, BinFrom, BinTo, ItemFilter, OnlyDiff);
        if LocationCode = '' then
            LocationCode := DefaultLocation();

        Result.Add('location', LocationCode);
        Result.Add('zone', ZoneCode);
        Result.Add('binFrom', BinFrom);
        Result.Add('binTo', BinTo);
        Result.Add('item', ItemFilter);
        Result.Add('onlyDiff', OnlyDiff);
        Result.Add('generatedAt', Format(CurrentDateTime(), 0, 9));
        Result.Add('traceabilityAvailable', IsTraceabilityAvailable());
        Result.Add('locations', LocationsJson());
        Result.Add('zones', ZonesJson(LocationCode));
        Result.Add('binMandatory', IsBinMandatoryLocation(LocationCode));

        if LocationCode = '' then begin
            Result.Add('needsLocation', true);
            Result.Add('summary', EmptySummaryJson());
            Result.Add('rows', EmptyArray());
            Result.Add('truncated', false);
            Result.WriteTo(ResultText);
            exit(ResultText);
        end;

        Compare(LocationCode, ZoneCode, BinFrom, BinTo, ItemFilter, TempRow);
        Result.Add('needsLocation', false);
        Result.Add('summary', SummaryJson(TempRow));
        AddRowsJson(Result, TempRow, OnlyDiff);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>Sayfa bağlamından (göz içeriği / LP listesi) ilk filtre JSON'u.</summary>
    procedure MakeFilterJson(LocationCode: Code[10]; ZoneCode: Code[10]; BinFrom: Code[20]; BinTo: Code[20]; ItemFilter: Text; OnlyDiff: Boolean): Text
    var
        FilterObj: JsonObject;
        FilterText: Text;
    begin
        FilterObj.Add('location', LocationCode);
        FilterObj.Add('zone', ZoneCode);
        FilterObj.Add('binFrom', BinFrom);
        FilterObj.Add('binTo', BinTo);
        FilterObj.Add('item', ItemFilter);
        FilterObj.Add('onlyDiff', OnlyDiff);
        FilterObj.WriteTo(FilterText);
        exit(FilterText);
    end;

    /// <summary>Satırları (yalnız farklar seçiliyse farklı/işlem gereken satırlar) Excel'e indirir.</summary>
    procedure ExportToExcel(FilterJsonText: Text)
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
        TempExcelBuffer: Record "Excel Buffer" temporary;
        LocationCode: Code[10];
        ZoneCode: Code[10];
        BinFrom: Code[20];
        BinTo: Code[20];
        ItemFilter: Text;
        OnlyDiff: Boolean;
    begin
        ParseFilter(FilterJsonText, LocationCode, ZoneCode, BinFrom, BinTo, ItemFilter, OnlyDiff);
        Compare(LocationCode, ZoneCode, BinFrom, BinTo, ItemFilter, TempRow);

        TempExcelBuffer.NewRow();
        AddHeader(TempExcelBuffer, 'Göz');
        AddHeader(TempExcelBuffer, 'Bölge');
        AddHeader(TempExcelBuffer, 'Madde No.');
        AddHeader(TempExcelBuffer, 'Açıklama');
        AddHeader(TempExcelBuffer, 'Varyant');
        AddHeader(TempExcelBuffer, 'Lot No.');
        AddHeader(TempExcelBuffer, 'Birim');
        AddHeader(TempExcelBuffer, 'BC Stok');
        AddHeader(TempExcelBuffer, 'LP Miktarı');
        AddHeader(TempExcelBuffer, 'Fark (LP - Stok)');
        AddHeader(TempExcelBuffer, 'LP Sayısı');
        AddHeader(TempExcelBuffer, 'Durum');
        AddHeader(TempExcelBuffer, 'Olası Neden');
        AddHeader(TempExcelBuffer, 'Ayrıntı');
        AddHeader(TempExcelBuffer, 'LP''ler');

        TempRow.SetCurrentKey("Location Code", "Bin Code", "Item No.", "Variant Code", "Lot No.");
        if TempRow.FindSet() then
            repeat
                if IncludeRow(TempRow, OnlyDiff) then begin
                    TempExcelBuffer.NewRow();
                    AddText(TempExcelBuffer, TempRow."Bin Code");
                    AddText(TempExcelBuffer, TempRow."Zone Code");
                    AddText(TempExcelBuffer, TempRow."Item No.");
                    AddText(TempExcelBuffer, TempRow."Item Description");
                    AddText(TempExcelBuffer, TempRow."Variant Code");
                    AddText(TempExcelBuffer, TempRow."Lot No.");
                    AddText(TempExcelBuffer, TempRow."Base Unit of Measure");
                    AddNumber(TempExcelBuffer, TempRow."Stock Qty. (Base)");
                    AddNumber(TempExcelBuffer, TempRow."LP Qty. (Base)");
                    AddNumber(TempExcelBuffer, TempRow.Difference);
                    AddNumber(TempExcelBuffer, TempRow."LP Count");
                    AddText(TempExcelBuffer, Format(TempRow."Comparison Status"));
                    AddText(TempExcelBuffer, Format(TempRow.Reason));
                    AddText(TempExcelBuffer, TempRow."Reason Detail");
                    AddText(TempExcelBuffer, TempRow."LP Nos.");
                end;
            until TempRow.Next() = 0;

        TempExcelBuffer.CreateNewBook('Göz LP');
        TempExcelBuffer.WriteSheet('Göz ve LP Karşılaştırma ' + LocationCode, CompanyName(), UserId());
        TempExcelBuffer.CloseBook();
        TempExcelBuffer.SetFriendlyFilename('goz-lp-karsilastirma-' + LocationCode);
        TempExcelBuffer.OpenExcel();
    end;

    /// <summary>Satırın ekranda (yalnız farklar açıkken) gösterilip gösterilmeyeceği.</summary>
    procedure IncludeRow(TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; OnlyDiff: Boolean): Boolean
    begin
        if not OnlyDiff then
            exit(true);
        exit((TempRow."Comparison Status" <> TempRow."Comparison Status"::Equal) or (TempRow.Reason <> TempRow.Reason::"None"));
    end;

    // ---------------------------------------------------------------------
    // Düzeltme işlemleri (sayfa onay ister; mevcut LP Yönetimi kurallarına uyar)
    // ---------------------------------------------------------------------

    /// <summary>Virgüllü geri alma kayıt nolarını ayrıştırır, boşaltılacak LP satırı sayısını döndürür.</summary>
    procedure PreviewUndoneReceiptRepair(UndoEntryNosCsv: Text; var UndoEntryNos: List of [Integer]) PlannedLines: Integer
    var
        UndoEntryNo: Integer;
    begin
        ParseIntegerCsv(UndoEntryNosCsv, UndoEntryNos);
        foreach UndoEntryNo in UndoEntryNos do
            PlannedLines += LPManagement.PreviewUndoneReceiptLpRepair(UndoEntryNo);
    end;

    procedure ApplyUndoneReceiptRepair(UndoEntryNos: List of [Integer]) EmptiedLines: Integer
    var
        UndoEntryNo: Integer;
    begin
        foreach UndoEntryNo in UndoEntryNos do
            EmptiedLines += LPManagement.RepairUndoneReceiptLps(UndoEntryNo);
    end;

    /// <summary>Verilen LP'lerden yetim atananların sayısı (ApplyRelease = false) ya da serbest bırakılan sayısı.</summary>
    procedure ReleaseOrphanLps(LpNosCsv: Text; ApplyRelease: Boolean) Total: Integer
    var
        Scope: Record "DOPSWHS LP Header";
        LpNos: List of [Text];
        LpNo: Text;
    begin
        LpNos := LpNosCsv.Split(',');
        foreach LpNo in LpNos do begin
            LpNo := DelChr(LpNo, '<>', ' ');
            if LpNo <> '' then begin
                Scope.Reset();
                Scope.SetRange("No.", CopyStr(LpNo, 1, MaxStrLen(Scope."No.")));
                Total += LPManagement.ReleaseOrphanAssignments(Scope, ApplyRelease);
            end;
        end;
    end;

    procedure OpenLp(LpNo: Text)
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if LP.Get(CopyStr(LpNo, 1, MaxStrLen(LP."No."))) then
            Page.Run(Page::"DOPSWHS LP Card", LP);
    end;

    procedure OpenBinContent(LocationCode: Text; BinCode: Text; ItemNo: Text; VariantCode: Text)
    var
        BinContent: Record "Bin Content";
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        // Göz zorunlu olmayan lokasyonda göz içeriği yok: açık madde girişleri açılır.
        if not IsBinMandatoryLocation(CopyStr(LocationCode, 1, 10)) then begin
            ItemLedgerEntry.SetRange("Location Code", CopyStr(LocationCode, 1, MaxStrLen(ItemLedgerEntry."Location Code")));
            ItemLedgerEntry.SetRange(Open, true);
            if ItemNo <> '' then begin
                ItemLedgerEntry.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(ItemLedgerEntry."Item No.")));
                ItemLedgerEntry.SetRange("Variant Code", CopyStr(VariantCode, 1, MaxStrLen(ItemLedgerEntry."Variant Code")));
            end;
            Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
            exit;
        end;
        BinContent.SetRange("Location Code", CopyStr(LocationCode, 1, MaxStrLen(BinContent."Location Code")));
        if BinCode <> '' then
            BinContent.SetRange("Bin Code", CopyStr(BinCode, 1, MaxStrLen(BinContent."Bin Code")));
        if ItemNo <> '' then begin
            BinContent.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(BinContent."Item No.")));
            BinContent.SetRange("Variant Code", CopyStr(VariantCode, 1, MaxStrLen(BinContent."Variant Code")));
        end;
        Page.Run(Page::"Bin Contents", BinContent);
    end;

    // ---------------------------------------------------------------------
    // LP İzlenebilirlik bağlantısı: doğrudan page "DOPSWHS LP Trace" açılır.
    // Olaylar (OnIsLpTraceabilityAvailable / OnOpenLpTraceability) başka bir
    // ekranın devralması için korunur.
    // ---------------------------------------------------------------------
    procedure IsTraceabilityAvailable(): Boolean
    var
        Available: Boolean;
    begin
        // LP İzlenebilirlik (page "DOPSWHS LP Trace") aynı uygulamada; olay
        // aboneleri yine de kendi ekranlarını açabilir.
        Available := true;
        OnIsLpTraceabilityAvailable(Available);
        exit(Available);
    end;

    procedure OpenTraceability(LpNo: Text; ItemNo: Text; LotNo: Text)
    var
        TracePage: Page "DOPSWHS LP Trace";
        Handled: Boolean;
    begin
        OnOpenLpTraceability(
            CopyStr(LpNo, 1, 20), CopyStr(ItemNo, 1, 20), CopyStr(LotNo, 1, 50), Handled);
        if Handled then
            exit;
        if LpNo <> '' then
            TracePage.SetSearch(LpNo)
        else
            if LotNo <> '' then
                TracePage.SetSearch(ItemNo + ' ' + LotNo)
            else
                TracePage.SetSearch(ItemNo);
        TracePage.Run();
    end;

    [IntegrationEvent(false, false)]
    procedure OnIsLpTraceabilityAvailable(var Available: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    procedure OnOpenLpTraceability(LpNo: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; var Handled: Boolean)
    begin
    end;

    // ---------------------------------------------------------------------
    // Karşılaştırma
    // ---------------------------------------------------------------------

    local procedure ResetState()
    begin
        Clear(RowIndex);
        Clear(LpSeenInRow);
        Clear(RowSourceEntries);
        Clear(BinZoneCache);
        Clear(OrphanCache);
        Clear(UndoCandidatesCache);
        Clear(UndoPreviewCache);
        Clear(LpDetails);
        LastEntryNo := 0;
    end;

    local procedure CollectBinStock(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        BinContent: Record "Bin Content";
        WarehouseEntry: Record "Warehouse Entry";
    begin
        BinContent.SetRange("Location Code", CurrLocation);
        if CurrZone <> '' then
            BinContent.SetRange("Zone Code", CurrZone);
        if (CurrBinFrom <> '') and (CurrBinTo <> '') then
            BinContent.SetRange("Bin Code", CurrBinFrom, CurrBinTo)
        else
            if CurrBinFrom <> '' then
                BinContent.SetFilter("Bin Code", CurrBinFrom)
            else
                if CurrBinTo <> '' then
                    BinContent.SetRange("Bin Code", '', CurrBinTo);
        if CurrItemFilter <> '' then
            BinContent.SetFilter("Item No.", CurrItemFilter);
        BinContent.SetLoadFields("Location Code", "Zone Code", "Bin Code", "Item No.", "Variant Code", "Unit of Measure Code");
        if not BinContent.FindSet() then
            exit;
        repeat
            if not BinZoneCache.ContainsKey(BinContent."Bin Code") then
                BinZoneCache.Add(BinContent."Bin Code", BinContent."Zone Code");
            if IsLotTracked(BinContent."Item No.") then begin
                // Lot kırılımı yalnız izlemeli maddelerde depo girişlerinden okunur.
                WarehouseEntry.Reset();
                WarehouseEntry.SetRange("Location Code", BinContent."Location Code");
                WarehouseEntry.SetRange("Bin Code", BinContent."Bin Code");
                WarehouseEntry.SetRange("Item No.", BinContent."Item No.");
                WarehouseEntry.SetRange("Variant Code", BinContent."Variant Code");
                WarehouseEntry.SetRange("Unit of Measure Code", BinContent."Unit of Measure Code");
                WarehouseEntry.SetLoadFields("Lot No.", "Qty. (Base)");
                if WarehouseEntry.FindSet() then
                    repeat
                        AddStock(TempRow, BinContent."Bin Code", BinContent."Zone Code", BinContent."Item No.",
                            BinContent."Variant Code", WarehouseEntry."Lot No.", WarehouseEntry."Qty. (Base)");
                    until WarehouseEntry.Next() = 0;
            end else begin
                BinContent.CalcFields("Quantity (Base)");
                if BinContent."Quantity (Base)" <> 0 then
                    AddStock(TempRow, BinContent."Bin Code", BinContent."Zone Code", BinContent."Item No.",
                        BinContent."Variant Code", '', BinContent."Quantity (Base)");
            end;
        until BinContent.Next() = 0;
    end;

    /// <summary>Göz zorunlu olmayan lokasyon: açık madde girişlerinin kalan miktarı (madde/varyant/lot).</summary>
    local procedure CollectLocationStock(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.SetRange("Location Code", CurrLocation);
        ItemLedgerEntry.SetRange(Open, true);
        if CurrItemFilter <> '' then
            ItemLedgerEntry.SetFilter("Item No.", CurrItemFilter);
        ItemLedgerEntry.SetLoadFields("Item No.", "Variant Code", "Lot No.", "Remaining Quantity");
        if ItemLedgerEntry.FindSet() then
            repeat
                if ItemLedgerEntry."Remaining Quantity" <> 0 then
                    AddStock(TempRow, '', '', ItemLedgerEntry."Item No.", ItemLedgerEntry."Variant Code",
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Remaining Quantity");
            until ItemLedgerEntry.Next() = 0;
    end;

    local procedure IsBinMandatoryLocation(LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
    begin
        if LocationCode = '' then
            exit(false);
        Location.SetLoadFields("Bin Mandatory");
        if Location.Get(LocationCode) then
            exit(Location."Bin Mandatory");
        exit(false);
    end;

    local procedure CollectLpQuantities(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RowBin: Code[20];
        ZoneCode: Code[10];
        BaseQty: Decimal;
        UomKnown: Boolean;
        Orphan: Boolean;
        EntryNo: Integer;
    begin
        LP.SetCurrentKey("Location Code", "Bin Code", Status);
        LP.SetRange("Location Code", CurrLocation);
        if CurrBinMandatory then
            if (CurrBinFrom <> '') and (CurrBinTo <> '') then
                LP.SetRange("Bin Code", CurrBinFrom, CurrBinTo)
            else
                if CurrBinFrom <> '' then
                    LP.SetFilter("Bin Code", CurrBinFrom)
                else
                    if CurrBinTo <> '' then
                        LP.SetRange("Bin Code", '', CurrBinTo);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetLoadFields("No.", "Location Code", "Bin Code", Status, "Assigned Document Type", "Assigned Document No.",
            "Pending Receipt No.", "Built DateTime", "Parent LP No.");
        if not LP.FindSet() then
            exit;
        repeat
            // Göz zorunlu lokasyonda gözsüz LP de (göz filtresi yoksa) boş göz
            // satırında görünür: stokla eşleşmez, fark olarak çıkar.
            RowBin := '';
            ZoneCode := '';
            if CurrBinMandatory then begin
                RowBin := LP."Bin Code";
                if RowBin <> '' then
                    ZoneCode := BinZone(RowBin);
            end;
            if (not CurrBinMandatory) or (RowBin <> '') or ((CurrZone = '') and (CurrBinFrom = '') and (CurrBinTo = '')) then begin
                if (not CurrBinMandatory) or (CurrZone = '') or (ZoneCode = CurrZone) then begin
                    Orphan := IsOrphan(LP);
                    LPLine.Reset();
                    LPLine.SetRange("LP No.", LP."No.");
                    if CurrItemFilter <> '' then
                        LPLine.SetFilter("Item No.", CurrItemFilter)
                    else
                        LPLine.SetFilter("Item No.", '<>%1', '');
                    LPLine.SetLoadFields("LP No.", "Line No.", "Item No.", "Variant Code", "Unit of Measure", Quantity,
                        "Lot No.", "Serial No.", "Expiration Date", "Source Bin Code", "Source Document Type",
                        "Source Document No.", "Source Document Line No.", "Source Item Ledger Entry No.", "Source LP No.");
                    if LPLine.FindSet() then
                        repeat
                            if LPLine."Item No." <> '' then begin
                                BaseQty := ToBaseQty(LPLine."Item No.", LPLine."Unit of Measure", LPLine.Quantity, UomKnown);
                                EntryNo := GetOrCreateRow(TempRow, RowBin, ZoneCode, LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.");
                                TempRow.Get(EntryNo);
                                TempRow."LP Qty. (Base)" += BaseQty;
                                TempRow."LP Line Count" += 1;
                                if not LpSeenInRow.ContainsKey(Format(EntryNo) + '|' + LP."No.") then begin
                                    LpSeenInRow.Add(Format(EntryNo) + '|' + LP."No.", true);
                                    TempRow."LP Count" += 1;
                                    TempRow."LP Nos." := AppendCsv(TempRow."LP Nos.", LP."No.", MaxStrLen(TempRow."LP Nos."));
                                    if Orphan then
                                        TempRow."Orphan LP Nos." := AppendCsv(TempRow."Orphan LP Nos.", LP."No.", MaxStrLen(TempRow."Orphan LP Nos."));
                                end;
                                TempRow.Modify();
                                if LPLine."Source Item Ledger Entry No." <> 0 then
                                    RememberSourceEntry(EntryNo, LPLine."Source Item Ledger Entry No.");
                                AddLineDetail(EntryNo, LP, LPLine, BaseQty, UomKnown, Orphan);
                            end;
                        until LPLine.Next() = 0;
                end;
            end;
        until LP.Next() = 0;
    end;

    local procedure ClassifyRows(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        EmptyRows: List of [Integer];
        EntryNo: Integer;
        Tolerance: Decimal;
    begin
        Tolerance := QtyTolerance();
        TempRow.Reset();
        if TempRow.FindSet() then
            repeat
                if (Abs(TempRow."Stock Qty. (Base)") <= Tolerance) and (Abs(TempRow."LP Qty. (Base)") <= Tolerance) and
                   (TempRow."LP Count" = 0)
                then
                    EmptyRows.Add(TempRow."Entry No.")
                else begin
                    TempRow.Difference := TempRow."LP Qty. (Base)" - TempRow."Stock Qty. (Base)";
                    case true of
                        TempRow."Stock Qty. (Base)" < -Tolerance:
                            TempRow."Comparison Status" := TempRow."Comparison Status"::NegativeStock;
                        Abs(TempRow.Difference) <= Tolerance:
                            TempRow."Comparison Status" := TempRow."Comparison Status"::Equal;
                        TempRow.Difference > 0:
                            if TempRow."Stock Qty. (Base)" <= Tolerance then
                                TempRow."Comparison Status" := TempRow."Comparison Status"::LpNoStock
                            else
                                TempRow."Comparison Status" := TempRow."Comparison Status"::LpOver;
                        else
                            if TempRow."LP Qty. (Base)" <= Tolerance then
                                TempRow."Comparison Status" := TempRow."Comparison Status"::StockNoLp
                            else
                                TempRow."Comparison Status" := TempRow."Comparison Status"::StockOver;
                    end;
                    TempRow.Modify();
                end;
            until TempRow.Next() = 0;
        foreach EntryNo in EmptyRows do
            if TempRow.Get(EntryNo) then
                TempRow.Delete();
    end;

    local procedure DetectUndoneReceipts(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        SourceEntries: List of [Text];
        SourceEntryText: Text;
        UndoText: Text;
        UndoParts: List of [Text];
        UndoPart: Text;
        SourceEntryNo: Integer;
        UndoEntryNo: Integer;
        Planned: Integer;
        RowUndo: List of [Integer];
        RepairableLines: Integer;
    begin
        // Yalnız LP'nin stoktan fazla olduğu satırlar: geri alınan mal kabulün
        // LP'si dolu kalmışsa LP kaynağı (Source Item Ledger Entry No.) onu gösterir.
        TempRow.Reset();
        TempRow.SetFilter("Comparison Status", '%1|%2', TempRow."Comparison Status"::LpOver, TempRow."Comparison Status"::LpNoStock);
        if TempRow.FindSet() then
            repeat
                Clear(RowUndo);
                RepairableLines := 0;
                if RowSourceEntries.Get(TempRow."Entry No.", SourceEntryText) then begin
                    SourceEntries := SourceEntryText.Split(',');
                    foreach SourceEntryText in SourceEntries do
                        if Evaluate(SourceEntryNo, SourceEntryText) then begin
                            UndoText := UndoCandidates(SourceEntryNo);
                            if UndoText <> '' then begin
                                UndoParts := UndoText.Split(',');
                                foreach UndoPart in UndoParts do
                                    if Evaluate(UndoEntryNo, UndoPart) then
                                        if not RowUndo.Contains(UndoEntryNo) then begin
                                            Planned := UndoPreview(UndoEntryNo);
                                            if Planned > 0 then begin
                                                RowUndo.Add(UndoEntryNo);
                                                RepairableLines += Planned;
                                            end;
                                        end;
                            end;
                        end;
                end;
                if RowUndo.Count() > 0 then begin
                    TempRow.Reason := TempRow.Reason::UndoneReceipt;
                    TempRow."Undo Entry Nos." := CopyStr(JoinIntegers(RowUndo), 1, MaxStrLen(TempRow."Undo Entry Nos."));
                    TempRow."Repairable LP Lines" := RepairableLines;
                    TempRow."Reason Detail" := CopyStr(
                        StrSubstNo('Mal kabul geri alınmış (kayıt %1) ama LP dolu kalmış; %2 LP satırı boşaltılabilir.',
                            TempRow."Undo Entry Nos.", RepairableLines),
                        1, MaxStrLen(TempRow."Reason Detail"));
                    TempRow.Modify();
                end;
            until TempRow.Next() = 0;
        TempRow.Reset();
    end;

    local procedure DetectOrphanAssignments(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    begin
        TempRow.Reset();
        TempRow.SetFilter("Orphan LP Nos.", '<>%1', '');
        TempRow.SetRange(Reason, TempRow.Reason::"None");
        if TempRow.FindSet() then
            repeat
                TempRow.Reason := TempRow.Reason::OrphanAssignment;
                TempRow."Reason Detail" := CopyStr(
                    StrSubstNo('LP atandığı belge artık yok (%1); LP başka işlemlerde kullanılamaz.', TempRow."Orphan LP Nos."),
                    1, MaxStrLen(TempRow."Reason Detail"));
                TempRow.Modify();
            until TempRow.Next() = 0;
        TempRow.Reset();
    end;

    local procedure DetectLotAndBinMismatches(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary)
    var
        StockSurplusByBinItem: Dictionary of [Text, Text];
        LpSurplusByBinItem: Dictionary of [Text, Text];
        StockSurplusByItemLot: Dictionary of [Text, Text];
        LpSurplusByItemLot: Dictionary of [Text, Text];
        Found: Text;
        LpSurplus: Boolean;
    begin
        TempRow.Reset();
        if TempRow.FindSet() then
            repeat
                case TempRow."Comparison Status" of
                    TempRow."Comparison Status"::StockOver, TempRow."Comparison Status"::StockNoLp:
                        begin
                            AddToIndex(StockSurplusByBinItem, BinItemKey(TempRow), LotLabel(TempRow."Lot No."));
                            AddToIndex(StockSurplusByItemLot, ItemLotKey(TempRow), TempRow."Bin Code");
                        end;
                    TempRow."Comparison Status"::LpOver, TempRow."Comparison Status"::LpNoStock:
                        begin
                            AddToIndex(LpSurplusByBinItem, BinItemKey(TempRow), LotLabel(TempRow."Lot No."));
                            AddToIndex(LpSurplusByItemLot, ItemLotKey(TempRow), TempRow."Bin Code");
                        end;
                end;
            until TempRow.Next() = 0;

        TempRow.SetRange(Reason, TempRow.Reason::"None");
        TempRow.SetFilter("Comparison Status", '%1|%2|%3|%4',
            TempRow."Comparison Status"::LpOver, TempRow."Comparison Status"::LpNoStock,
            TempRow."Comparison Status"::StockOver, TempRow."Comparison Status"::StockNoLp);
        if TempRow.FindSet() then
            repeat
                LpSurplus := TempRow."Comparison Status" in [TempRow."Comparison Status"::LpOver, TempRow."Comparison Status"::LpNoStock];
                if LpSurplus then begin
                    if StockSurplusByBinItem.Get(BinItemKey(TempRow), Found) then
                        SetReason(TempRow, TempRow.Reason::LotMismatch, StrSubstNo('Bu gözde LP''siz stok farklı lotta: %1. LP lotu yanlış girilmiş olabilir.', Found))
                    else
                        if StockSurplusByItemLot.Get(ItemLotKey(TempRow), Found) then
                            SetReason(TempRow, TempRow.Reason::OtherBin, StrSubstNo('Bu madde/lot stoğu başka gözde: %1. LP fiziksel olarak taşınmış ama sistemde taşınmamış olabilir.', Found));
                end else begin
                    if LpSurplusByBinItem.Get(BinItemKey(TempRow), Found) then
                        SetReason(TempRow, TempRow.Reason::LotMismatch, StrSubstNo('Bu gözdeki LP''lerde farklı lot var: %1.', Found))
                    else
                        if LpSurplusByItemLot.Get(ItemLotKey(TempRow), Found) then
                            SetReason(TempRow, TempRow.Reason::OtherBin, StrSubstNo('Bu madde/lotun LP''si başka gözde kayıtlı: %1.', Found));
                end;
            until TempRow.Next() = 0;
        TempRow.Reset();
    end;

    local procedure SetReason(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; NewReason: Option; Detail: Text)
    begin
        TempRow.Reason := NewReason;
        TempRow."Reason Detail" := CopyStr(Detail, 1, MaxStrLen(TempRow."Reason Detail"));
        TempRow.Modify();
    end;

    // ---------------------------------------------------------------------
    // Yardımcılar
    // ---------------------------------------------------------------------

    local procedure AddStock(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; BinCode: Code[20]; ZoneCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; QtyBase: Decimal)
    var
        EntryNo: Integer;
    begin
        EntryNo := GetOrCreateRow(TempRow, BinCode, ZoneCode, ItemNo, VariantCode, LotNo);
        TempRow.Get(EntryNo);
        TempRow."Stock Qty. (Base)" += QtyBase;
        TempRow.Modify();
    end;

    local procedure GetOrCreateRow(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; BinCode: Code[20]; ZoneCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]) EntryNo: Integer
    var
        RowKey: Text;
    begin
        RowKey := BinCode + '|' + ItemNo + '|' + VariantCode + '|' + LotNo;
        if RowIndex.Get(RowKey, EntryNo) then
            exit(EntryNo);
        LastEntryNo += 1;
        EntryNo := LastEntryNo;
        TempRow.Init();
        TempRow."Entry No." := EntryNo;
        TempRow."Location Code" := CurrLocation;
        TempRow."Zone Code" := ZoneCode;
        TempRow."Bin Code" := BinCode;
        TempRow."Item No." := ItemNo;
        TempRow."Variant Code" := VariantCode;
        TempRow."Lot No." := LotNo;
        LoadItem(ItemNo);
        TempRow."Base Unit of Measure" := ItemBaseUomCache.Get(ItemNo);
        TempRow."Item Description" := CopyStr(ItemDescriptionCache.Get(ItemNo), 1, MaxStrLen(TempRow."Item Description"));
        TempRow.Insert();
        RowIndex.Add(RowKey, EntryNo);
    end;

    local procedure LoadItem(ItemNo: Code[20])
    var
        Item: Record Item;
    begin
        if ItemBaseUomCache.ContainsKey(ItemNo) then
            exit;
        Item.SetLoadFields(Description, "Base Unit of Measure", "Item Tracking Code");
        if Item.Get(ItemNo) then begin
            ItemBaseUomCache.Add(ItemNo, Item."Base Unit of Measure");
            ItemDescriptionCache.Add(ItemNo, Item.Description);
            ItemTrackedCache.Add(ItemNo, Item."Item Tracking Code" <> '');
        end else begin
            ItemBaseUomCache.Add(ItemNo, '');
            ItemDescriptionCache.Add(ItemNo, '');
            ItemTrackedCache.Add(ItemNo, false);
        end;
    end;

    local procedure IsLotTracked(ItemNo: Code[20]): Boolean
    begin
        LoadItem(ItemNo);
        exit(ItemTrackedCache.Get(ItemNo));
    end;

    /// <summary>LP satırı miktarını temel birime çevirir; birim bulunamazsa 1 kabul eder ve UomKnown = false döner.</summary>
    procedure ToBaseQty(ItemNo: Code[20]; UomCode: Code[10]; Qty: Decimal; var UomKnown: Boolean): Decimal
    var
        ItemUoM: Record "Item Unit of Measure";
        CacheKey: Text;
        QtyPer: Decimal;
    begin
        UomKnown := true;
        LoadItem(ItemNo);
        if (UomCode = '') or (UomCode = ItemBaseUomCache.Get(ItemNo)) then
            exit(Qty);
        CacheKey := ItemNo + '|' + UomCode;
        if not QtyPerUomCache.Get(CacheKey, QtyPer) then begin
            QtyPer := 0;
            ItemUoM.SetLoadFields("Qty. per Unit of Measure");
            if ItemUoM.Get(ItemNo, UomCode) then
                QtyPer := ItemUoM."Qty. per Unit of Measure";
            QtyPerUomCache.Add(CacheKey, QtyPer);
        end;
        if QtyPer <= 0 then begin
            UomKnown := false;
            exit(Qty);
        end;
        exit(Round(Qty * QtyPer, 0.00001));
    end;

    local procedure BinZone(BinCode: Code[20]) ZoneCode: Code[10]
    var
        Bin: Record Bin;
    begin
        if BinZoneCache.Get(BinCode, ZoneCode) then
            exit(ZoneCode);
        Bin.SetLoadFields("Zone Code");
        if Bin.Get(CurrLocation, BinCode) then
            ZoneCode := Bin."Zone Code";
        BinZoneCache.Add(BinCode, ZoneCode);
    end;

    local procedure IsOrphan(LP: Record "DOPSWHS LP Header") Orphan: Boolean
    begin
        if LP.Status <> LP.Status::Assigned then
            exit(false);
        if OrphanCache.Get(LP."No.", Orphan) then
            exit(Orphan);
        Orphan := LPManagement.IsAssignmentOrphaned(LP);
        OrphanCache.Add(LP."No.", Orphan);
    end;

    local procedure UndoCandidates(SourceEntryNo: Integer) Result: Text
    var
        UndoEntryNos: List of [Integer];
    begin
        if UndoCandidatesCache.Get(SourceEntryNo, Result) then
            exit(Result);
        LPManagement.CollectUndoneReceiptEntries(SourceEntryNo, UndoEntryNos);
        Result := JoinIntegers(UndoEntryNos);
        UndoCandidatesCache.Add(SourceEntryNo, Result);
    end;

    local procedure UndoPreview(UndoEntryNo: Integer) Planned: Integer
    begin
        if UndoPreviewCache.Get(UndoEntryNo, Planned) then
            exit(Planned);
        Planned := LPManagement.PreviewUndoneReceiptLpRepair(UndoEntryNo);
        UndoPreviewCache.Add(UndoEntryNo, Planned);
    end;

    local procedure RememberSourceEntry(EntryNo: Integer; SourceEntryNo: Integer)
    var
        Existing: Text;
    begin
        if not RowSourceEntries.Get(EntryNo, Existing) then begin
            RowSourceEntries.Add(EntryNo, Format(SourceEntryNo, 0, 9));
            exit;
        end;
        if (',' + Existing + ',').Contains(',' + Format(SourceEntryNo, 0, 9) + ',') then
            exit;
        RowSourceEntries.Set(EntryNo, Existing + ',' + Format(SourceEntryNo, 0, 9));
    end;

    local procedure AddLineDetail(EntryNo: Integer; LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line"; BaseQty: Decimal; UomKnown: Boolean; Orphan: Boolean)
    var
        Line: JsonObject;
        Lines: JsonArray;
        Token: JsonToken;
        DetailKey: Text;
    begin
        Line.Add('lpNo', LP."No.");
        Line.Add('lpStatus', Format(LP.Status));
        Line.Add('assignedDocType', AssignedDocTypeText(LP));
        Line.Add('assignedDocNo', LP."Assigned Document No.");
        Line.Add('pendingReceiptNo', LP."Pending Receipt No.");
        Line.Add('parentLpNo', LP."Parent LP No.");
        Line.Add('orphan', Orphan);
        if LP."Built DateTime" <> 0DT then
            Line.Add('builtAt', Format(LP."Built DateTime", 0, 9))
        else
            Line.Add('builtAt', '');
        Line.Add('lineNo', LPLine."Line No.");
        Line.Add('qty', LPLine.Quantity);
        Line.Add('uom', LPLine."Unit of Measure");
        Line.Add('qtyBase', BaseQty);
        Line.Add('uomMissing', not UomKnown);
        Line.Add('lot', LPLine."Lot No.");
        Line.Add('serial', LPLine."Serial No.");
        if LPLine."Expiration Date" <> 0D then
            Line.Add('expirationDate', Format(LPLine."Expiration Date", 0, 9))
        else
            Line.Add('expirationDate', '');
        Line.Add('sourceEntryNo', LPLine."Source Item Ledger Entry No.");
        if LPLine."Source Document No." <> '' then
            Line.Add('sourceDocType', Format(LPLine."Source Document Type"))
        else
            Line.Add('sourceDocType', '');
        Line.Add('sourceDocNo', LPLine."Source Document No.");
        Line.Add('sourceDocLineNo', LPLine."Source Document Line No.");
        Line.Add('sourceBin', LPLine."Source Bin Code");
        Line.Add('sourceLpNo', LPLine."Source LP No.");

        DetailKey := Format(EntryNo, 0, 9);
        if LpDetails.Get(DetailKey, Token) then begin
            Lines := Token.AsArray();
            Lines.Add(Line);
            LpDetails.Replace(DetailKey, Lines);
        end else begin
            Lines.Add(Line);
            LpDetails.Add(DetailKey, Lines);
        end;
    end;

    local procedure AssignedDocTypeText(LP: Record "DOPSWHS LP Header"): Text
    begin
        if LP."Assigned Document Type" = LP."Assigned Document Type"::None then
            exit('');
        exit(Format(LP."Assigned Document Type"));
    end;

    local procedure AddToIndex(var Index: Dictionary of [Text, Text]; IndexKey: Text; Value: Text)
    var
        Existing: Text;
    begin
        if not Index.Get(IndexKey, Existing) then begin
            Index.Add(IndexKey, Value);
            exit;
        end;
        if (', ' + Existing + ', ').Contains(', ' + Value + ', ') then
            exit;
        if StrLen(Existing) > 120 then
            exit;
        Index.Set(IndexKey, Existing + ', ' + Value);
    end;

    local procedure BinItemKey(TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary): Text
    begin
        exit(TempRow."Bin Code" + '|' + TempRow."Item No." + '|' + TempRow."Variant Code");
    end;

    local procedure ItemLotKey(TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary): Text
    begin
        exit(TempRow."Item No." + '|' + TempRow."Variant Code" + '|' + TempRow."Lot No.");
    end;

    local procedure LotLabel(LotNo: Code[50]): Text
    begin
        if LotNo = '' then
            exit('(lotsuz)');
        exit(LotNo);
    end;

    local procedure AppendCsv(Existing: Text; Value: Text; MaxLen: Integer): Text
    begin
        if Existing = '' then
            exit(CopyStr(Value, 1, MaxLen));
        if StrLen(Existing) + 2 + StrLen(Value) > MaxLen then
            exit(Existing);
        exit(Existing + ', ' + Value);
    end;

    local procedure JoinIntegers(Values: List of [Integer]) Result: Text
    var
        Value: Integer;
    begin
        foreach Value in Values do
            if Result = '' then
                Result := Format(Value, 0, 9)
            else
                Result += ',' + Format(Value, 0, 9);
    end;

    local procedure ParseIntegerCsv(Csv: Text; var Values: List of [Integer])
    var
        Parts: List of [Text];
        Part: Text;
        Value: Integer;
    begin
        Parts := Csv.Split(',');
        foreach Part in Parts do
            if Evaluate(Value, DelChr(Part, '<>', ' ')) then
                if (Value > 0) and not Values.Contains(Value) then
                    Values.Add(Value);
    end;

    local procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
    end;

    local procedure DefaultLocation(): Code[10]
    var
        WarehouseEmployee: Record "Warehouse Employee";
    begin
        WarehouseEmployee.SetRange("User ID", UserId());
        WarehouseEmployee.SetRange(Default, true);
        if WarehouseEmployee.FindFirst() then
            exit(WarehouseEmployee."Location Code");
        WarehouseEmployee.SetRange(Default);
        if WarehouseEmployee.FindFirst() then
            exit(WarehouseEmployee."Location Code");
        exit('');
    end;

    local procedure ParseFilter(FilterJsonText: Text; var LocationCode: Code[10]; var ZoneCode: Code[10]; var BinFrom: Code[20]; var BinTo: Code[20]; var ItemFilter: Text; var OnlyDiff: Boolean)
    var
        FilterObj: JsonObject;
    begin
        OnlyDiff := true;
        if FilterJsonText = '' then
            exit;
        if not FilterObj.ReadFrom(FilterJsonText) then
            exit;
        LocationCode := CopyStr(UpperCase(JsonText(FilterObj, 'location')), 1, MaxStrLen(LocationCode));
        ZoneCode := CopyStr(UpperCase(JsonText(FilterObj, 'zone')), 1, MaxStrLen(ZoneCode));
        BinFrom := CopyStr(UpperCase(JsonText(FilterObj, 'binFrom')), 1, MaxStrLen(BinFrom));
        BinTo := CopyStr(UpperCase(JsonText(FilterObj, 'binTo')), 1, MaxStrLen(BinTo));
        ItemFilter := CopyStr(UpperCase(JsonText(FilterObj, 'item')), 1, 250);
        OnlyDiff := JsonBool(FilterObj, 'onlyDiff', true);
    end;

    local procedure JsonText(Obj: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(DelChr(Token.AsValue().AsText(), '<>', ' '));
    end;

    local procedure JsonBool(Obj: JsonObject; Name: Text; DefaultValue: Boolean): Boolean
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit(DefaultValue);
        if not Token.IsValue() then
            exit(DefaultValue);
        if Token.AsValue().IsNull() then
            exit(DefaultValue);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure LocationsJson() Locations: JsonArray
    var
        Location: Record Location;
        Entry: JsonObject;
    begin
        // Kitoko: göz zorunlu olmayan lokasyonlar da listelenir (lokasyon düzeyinde karşılaştırma).
        Location.SetRange("Use As In-Transit", false);
        Location.SetLoadFields(Code, Name, "Bin Mandatory");
        if Location.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('code', Location.Code);
                Entry.Add('name', Location.Name);
                Entry.Add('binMandatory', Location."Bin Mandatory");
                Locations.Add(Entry);
            until Location.Next() = 0;
    end;

    local procedure ZonesJson(LocationCode: Code[10]) Zones: JsonArray
    var
        Zone: Record Zone;
        Entry: JsonObject;
    begin
        if LocationCode = '' then
            exit;
        Zone.SetRange("Location Code", LocationCode);
        Zone.SetLoadFields(Code, Description);
        if Zone.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('code', Zone.Code);
                Entry.Add('name', Zone.Description);
                Zones.Add(Entry);
            until Zone.Next() = 0;
    end;

    local procedure EmptyArray() Result: JsonArray
    begin
    end;

    local procedure EmptySummaryJson() Summary: JsonObject
    var
        TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary;
    begin
        Summary := SummaryJson(TempRow);
    end;

    local procedure SummaryJson(var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary) Summary: JsonObject
    var
        Bins: Dictionary of [Code[20], Boolean];
        Lps: Dictionary of [Text, Boolean];
        OrphanLps: Dictionary of [Text, Boolean];
        LpNos: List of [Text];
        LpNo: Text;
        Counts: array[6] of Integer;
        StatusIndex: Integer;
        StockTotal: Decimal;
        LpTotal: Decimal;
        LpSurplus: Decimal;
        StockSurplus: Decimal;
        UndoneRows: Integer;
        ReasonRows: Integer;
    begin
        TempRow.Reset();
        if TempRow.FindSet() then
            repeat
                StatusIndex := TempRow."Comparison Status";
                Counts[StatusIndex + 1] += 1;
                StockTotal += TempRow."Stock Qty. (Base)";
                LpTotal += TempRow."LP Qty. (Base)";
                // Eksi stok satırı ne LP fazlası ne LP'siz stoktur; ayrıca sayılır.
                if TempRow."Comparison Status" <> TempRow."Comparison Status"::NegativeStock then
                    if TempRow.Difference > 0 then
                        LpSurplus += TempRow.Difference
                    else
                        StockSurplus += -TempRow.Difference;
                if not Bins.ContainsKey(TempRow."Bin Code") then
                    Bins.Add(TempRow."Bin Code", true);
                if TempRow."LP Nos." <> '' then begin
                    LpNos := TempRow."LP Nos.".Split(', ');
                    foreach LpNo in LpNos do
                        if not Lps.ContainsKey(LpNo) then
                            Lps.Add(LpNo, true);
                end;
                if TempRow."Orphan LP Nos." <> '' then begin
                    LpNos := TempRow."Orphan LP Nos.".Split(', ');
                    foreach LpNo in LpNos do
                        if not OrphanLps.ContainsKey(LpNo) then
                            OrphanLps.Add(LpNo, true);
                end;
                if TempRow.Reason = TempRow.Reason::UndoneReceipt then
                    UndoneRows += 1;
                if TempRow.Reason <> TempRow.Reason::"None" then
                    ReasonRows += 1;
            until TempRow.Next() = 0;
        Summary.Add('rows', TempRow.Count());
        Summary.Add('equal', Counts[1]);
        Summary.Add('lpOver', Counts[2]);
        Summary.Add('lpNoStock', Counts[3]);
        Summary.Add('stockOver', Counts[4]);
        Summary.Add('stockNoLp', Counts[5]);
        Summary.Add('negativeStock', Counts[6]);
        Summary.Add('stockTotal', StockTotal);
        Summary.Add('lpTotal', LpTotal);
        Summary.Add('lpSurplusQty', LpSurplus);
        Summary.Add('stockSurplusQty', StockSurplus);
        Summary.Add('bins', Bins.Count());
        Summary.Add('lps', Lps.Count());
        Summary.Add('orphanLps', OrphanLps.Count());
        Summary.Add('undoneReceiptRows', UndoneRows);
        Summary.Add('reasonRows', ReasonRows);
    end;

    local procedure AddRowsJson(var Result: JsonObject; var TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary; OnlyDiff: Boolean)
    var
        Rows: JsonArray;
        Row: JsonObject;
        Token: JsonToken;
        EmptyLines: JsonArray;
        Written: Integer;
        Truncated: Boolean;
    begin
        if MaxJsonRows = 0 then
            MaxJsonRows := 3000;
        TempRow.Reset();
        TempRow.SetCurrentKey("Location Code", "Bin Code", "Item No.", "Variant Code", "Lot No.");
        if TempRow.FindSet() then
            repeat
                if IncludeRow(TempRow, OnlyDiff) then
                    if Written >= MaxJsonRows then
                        Truncated := true
                    else begin
                        Clear(Row);
                        Row.Add('id', TempRow."Entry No.");
                        Row.Add('bin', TempRow."Bin Code");
                        Row.Add('zone', TempRow."Zone Code");
                        Row.Add('item', TempRow."Item No.");
                        Row.Add('description', TempRow."Item Description");
                        Row.Add('variant', TempRow."Variant Code");
                        Row.Add('lot', TempRow."Lot No.");
                        Row.Add('uom', TempRow."Base Unit of Measure");
                        Row.Add('stock', TempRow."Stock Qty. (Base)");
                        Row.Add('lp', TempRow."LP Qty. (Base)");
                        Row.Add('diff', TempRow.Difference);
                        Row.Add('lpCount', TempRow."LP Count");
                        Row.Add('status', StatusKey(TempRow));
                        Row.Add('reason', ReasonKey(TempRow));
                        Row.Add('reasonDetail', TempRow."Reason Detail");
                        Row.Add('undoEntryNos', TempRow."Undo Entry Nos.");
                        Row.Add('orphanLpNos', TempRow."Orphan LP Nos.");
                        Row.Add('repairableLines', TempRow."Repairable LP Lines");
                        if LpDetails.Get(Format(TempRow."Entry No.", 0, 9), Token) then
                            Row.Add('lines', Token)
                        else
                            Row.Add('lines', EmptyLines);
                        Rows.Add(Row);
                        Written += 1;
                    end;
            until TempRow.Next() = 0;
        Result.Add('rows', Rows);
        Result.Add('truncated', Truncated);
        Result.Add('maxRows', MaxJsonRows);
    end;

    procedure StatusKey(TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary): Text
    begin
        case TempRow."Comparison Status" of
            TempRow."Comparison Status"::Equal:
                exit('equal');
            TempRow."Comparison Status"::LpOver:
                exit('lpOver');
            TempRow."Comparison Status"::LpNoStock:
                exit('lpNoStock');
            TempRow."Comparison Status"::StockOver:
                exit('stockOver');
            TempRow."Comparison Status"::StockNoLp:
                exit('stockNoLp');
            TempRow."Comparison Status"::NegativeStock:
                exit('negativeStock');
        end;
    end;

    procedure ReasonKey(TempRow: Record "DOPSWHS Bin LP Compare Buffer" temporary): Text
    begin
        case TempRow.Reason of
            TempRow.Reason::UndoneReceipt:
                exit('undoneReceipt');
            TempRow.Reason::OrphanAssignment:
                exit('orphanAssignment');
            TempRow.Reason::LotMismatch:
                exit('lotMismatch');
            TempRow.Reason::OtherBin:
                exit('otherBin');
        end;
        exit('none');
    end;

    local procedure AddHeader(var TempExcelBuffer: Record "Excel Buffer" temporary; Caption: Text)
    begin
        TempExcelBuffer.AddColumn(Caption, false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
    end;

    local procedure AddText(var TempExcelBuffer: Record "Excel Buffer" temporary; Value: Text)
    begin
        TempExcelBuffer.AddColumn(Value, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
    end;

    local procedure AddNumber(var TempExcelBuffer: Record "Excel Buffer" temporary; Value: Decimal)
    begin
        TempExcelBuffer.AddColumn(Value, false, '', false, false, false, '#,##0.#####', TempExcelBuffer."Cell Type"::Number);
    end;
}
