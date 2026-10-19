/// <summary>
/// BADE (24 Eyl 2026): LPs showed A.URETIM while their stock stayed in the old
/// bin. Cause: the LP Bin Code was changed by hand on the BC License Plate card;
/// that moves no stock and writes no LP movement. The terminal ad-hoc move is
/// correct (stock and LP move together).
///
/// 1. BuildReconciliationCsv: read-only report per item/lot over all bins.
/// 2. MoveStockToLpBin: for selected LPs in the configured bins (Setup location
///    + bin filter, e.g. MERKEZDEPO / A.URETIM) the LP's stock is moved from the
///    bin of its last recorded movement to the LP's bin with the terminal's
///    tracked ad-hoc bin move, only when that stock is provably missing in the
///    LP bin and free in the recorded bin. LP contents do not change.
/// The LP card/list no longer allow editing the bin of an LP with content.
/// </summary>
codeunit 72409 "DOPSWHS LP Prod Consumption"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RMD,
        tabledata "DOPSWHS LP Movement Ledger" = RI,
        tabledata "DOPSWHS Setup" = R,
        tabledata "Warehouse Entry" = R,
        tabledata "Warehouse Activity Line" = RM,
        tabledata "Item Ledger Entry" = R,
        tabledata Item = R,
        tabledata "Item Unit of Measure" = R,
        tabledata "Item Tracking Code" = R,
        tabledata Bin = R,
        tabledata "Bin Type" = R,
        tabledata "Work Center" = R,
        tabledata "Machine Center" = R,
        tabledata "Bin Content" = R,
        tabledata Location = R;

    /// <summary>
    /// Preview (ApplyChanges = false) or move the stock of the selected LPs from
    /// the bin of their last recorded movement to the LP's current bin, with the
    /// same tracked ad-hoc bin move the terminal uses. Per LP all conditions must
    /// hold, otherwise it is skipped with a reason: active, not pending receipt,
    /// no child LPs, no serials, current bin inside the configured bins, a
    /// recorded bin that differs, every item/lot of the LP missing in the current
    /// bin and free (not claimed by other LPs) in the recorded bin. LP contents
    /// do not change; one LP movement row records the alignment.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure MoveStockToLpBin(var Selected: Record "DOPSWHS LP Header"; ApplyChanges: Boolean): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Moves: Dictionary of [Text, Decimal];
        Proof: Dictionary of [Text, Decimal];
        MissingLeft: Dictionary of [Text, Decimal];
        FreeLeft: Dictionary of [Text, Decimal];
        Parts: List of [Text];
        Rows: JsonArray;
        Row: JsonObject;
        Result: JsonObject;
        ResultText: Text;
        TrackKey: Text;
        HereKey: Text;
        ThereKey: Text;
        Reason: Text;
        Moved: Text;
        Reference: Code[40];
        RecordedBin: Code[20];
        Done: Integer;
        Skipped: Integer;
        MovedQty: Decimal;
    begin
        if ApplyChanges then begin
            LP.LockTable();
            LPLine.LockTable();
        end;
        Reference := CopyStr('LP-STOK-TASI#' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2>'), 1, 40);
        LP.CopyFilters(Selected);
        if LP.FindSet() then
            repeat
                Reason := '';
                RecordedBin := '';
                Moved := '';
                MovedQty := 0;
                Clear(Moves);
                Clear(Proof);
                if not IsActive(LP) then
                    Reason := 'LP aktif değil veya mal kabulü bekliyor'
                else
                    if not IsSyncBin(LP."Location Code", LP."Bin Code") then
                        Reason := 'LP, Kurulum''daki LP düzeltme lokasyonu/gözleri dışında'
                    else begin
                        RecordedBin := LastRecordedBin(LP."No.");
                        if RecordedBin = '' then
                            Reason := 'LP hareket kaydında göz yok'
                        else
                            if RecordedBin = LP."Bin Code" then
                                Reason := 'LP gözü son hareket kaydıyla aynı; kart üzerinden değiştirilmemiş'
                            else
                                Reason := CollectNeeds(LP, Moves, Proof);
                    end;

                // Stock proof per item/lot: missing in the LP bin, free in the recorded bin.
                if Reason = '' then
                    foreach TrackKey in Proof.Keys() do
                        if Reason = '' then begin
                            HereKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + TrackKey;
                            ThereKey := LP."Location Code" + '|' + RecordedBin + '|' + TrackKey;
                            if not MissingLeft.ContainsKey(HereKey) then
                                MissingLeft.Add(HereKey, OverClaimFor(LP."Location Code", LP."Bin Code", TrackKey));
                            if not FreeLeft.ContainsKey(ThereKey) then
                                FreeLeft.Add(ThereKey, -OverClaimFor(LP."Location Code", RecordedBin, TrackKey));
                            if MissingLeft.Get(HereKey) < Proof.Get(TrackKey) - Tolerance() then
                                Reason := 'LP stoğunun bir kısmı ' + LP."Bin Code" + ' gözünde zaten görünüyor; elle kontrol edin'
                            else
                                if FreeLeft.Get(ThereKey) < Proof.Get(TrackKey) - Tolerance() then
                                    Reason := RecordedBin + ' gözünde bu LP için yeterli serbest stok yok; elle kontrol edin';
                        end;

                Clear(Row);
                Row.Add('lpNo', LP."No.");
                Row.Add('fromBin', RecordedBin);
                Row.Add('toBin', LP."Bin Code");
                if Reason = '' then begin
                    foreach TrackKey in Proof.Keys() do begin
                        HereKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + TrackKey;
                        ThereKey := LP."Location Code" + '|' + RecordedBin + '|' + TrackKey;
                        MissingLeft.Set(HereKey, MissingLeft.Get(HereKey) - Proof.Get(TrackKey));
                        FreeLeft.Set(ThereKey, FreeLeft.Get(ThereKey) - Proof.Get(TrackKey));
                    end;
                    foreach TrackKey in Moves.Keys() do begin
                        Parts := TrackKey.Split('|');
                        if ApplyChanges then
                            // Same tracked bin move as the terminal LP moves (with LP No.).
                            MovementMgmt.AdHocMoveTrackedAtLocation(
                                LP."Location Code", RecordedBin, LP."Bin Code",
                                CopyStr(Parts.Get(1), 1, 20), LP."No.", Moves.Get(TrackKey),
                                CopyStr(UserId(), 1, 50), CopyStr(Parts.Get(3), 1, 50), '');
                        MovedQty += Moves.Get(TrackKey);
                        if Moved <> '' then
                            Moved += ', ';
                        Moved += Parts.Get(1) + ' ' + Format(Moves.Get(TrackKey)) + ' (Lot ' + Parts.Get(3) + ')';
                    end;
                    if ApplyChanges then
                        LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::Moved, RecordedBin, LP."Bin Code", 0, '', '', Reference);
                    if ApplyChanges then
                        Row.Add('result', 'Stok taşındı: ' + Moved)
                    else
                        Row.Add('result', 'Stok taşınacak: ' + Moved);
                    Row.Add('baseQuantity', MovedQty);
                    Done += 1;
                end else begin
                    Row.Add('result', Reason);
                    Skipped += 1;
                end;
                Rows.Add(Row);
            until LP.Next() = 0;
        Result.Add('applied', ApplyChanges);
        Result.Add('moved', Done);
        Result.Add('skipped', Skipped);
        Result.Add('rows', Rows);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>
    /// One button for the LP stock clean-up. Preview (ApplyChanges = false) or
    /// post. For every selected LP of the configured location and every item/lot,
    /// only the quantity still missing in the LP bin is brought in, only from free
    /// stock (not claimed by any LP).
    /// - LPs in the configured correction bins (e.g. A.URETIM), source bins in this
    ///   order: 1) the LP's last recorded bin, 2) a bin whose free quantity equals
    ///   exactly what is missing, 3) the bin with the most free stock.
    /// - Other LPs: only from the bin the LP's own lot was moved to without the LP
    ///   (movement out of the LP bin after the LP arrived there, e.g. a reclass
    ///   journal), at most that quantity.
    /// Never used as source: the LP bin, configured correction bins, the location
    /// adjustment bin, bins blocked for outbound movement.
    /// Open pick/movement Take lines left without stock in their bin because the
    /// stock went to an LP bin (this run or an earlier LP-STOK run) are pointed to
    /// that LP bin. If a line this run would leave uncovered cannot be pointed,
    /// nothing is posted.
    /// Uses the terminal's tracked ad-hoc bin move; LP contents do not change.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure AutoFillToLpBin(var Selected: Record "DOPSWHS LP Header"; ApplyChanges: Boolean): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Moves: Dictionary of [Text, Decimal];
        Proof: Dictionary of [Text, Decimal];
        MissingLeft: Dictionary of [Text, Decimal];
        FreeLeft: Dictionary of [Text, Decimal];
        TraceLeft: Dictionary of [Text, Decimal];
        TraceQtys: Dictionary of [Code[20], Decimal];
        NetMoved: Dictionary of [Text, Decimal];
        RunLinks: Dictionary of [Text, Text];
        PlanLps: List of [Code[20]];
        PlanBins: List of [Code[20]];
        PlanKeys: List of [Text];
        PlanQtys: List of [Decimal];
        LedgerKeys: List of [Text];
        Repoints: List of [Text];
        Candidates: List of [Code[20]];
        Allowed: List of [Code[20]];
        TraceBins: List of [Code[20]];
        Parts: List of [Text];
        Rows: JsonArray;
        PickRows: JsonArray;
        Row: JsonObject;
        Result: JsonObject;
        ResultText: Text;
        MoveKey: Text;
        HereKey: Text;
        ThereKey: Text;
        TraceKey: Text;
        LedgerKey: Text;
        RepointText: Text;
        Reason: Text;
        Moved: Text;
        Why: Text;
        Blocking: Text;
        Reference: Code[40];
        RecordedBin: Code[20];
        CandidateBin: Code[20];
        ChosenBin: Code[20];
        TraceMode: Boolean;
        Remaining: Decimal;
        Free: Decimal;
        BestFree: Decimal;
        Take: Decimal;
        MovedQty: Decimal;
        Done: Integer;
        Skipped: Integer;
        FirstPlan: Integer;
        i: Integer;
    begin
        if ApplyChanges then begin
            LP.LockTable();
            LPLine.LockTable();
        end;
        Reference := CopyStr('LP-STOK-TAMAMLA#' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2>'), 1, 40);
        LP.CopyFilters(Selected);
        if LP.FindSet() then
            repeat
                Reason := '';
                Moved := '';
                MovedQty := 0;
                TraceMode := false;
                Clear(Moves);
                Clear(Proof);
                FirstPlan := PlanKeys.Count() + 1;
                if not IsActive(LP) then
                    Reason := 'LP aktif değil veya mal kabulü bekliyor'
                else
                    if not IsSyncLocation(LP."Location Code") then
                        Reason := 'LP, Kurulum''daki LP düzeltme lokasyonu dışında'
                    else begin
                        TraceMode := not IsSyncBin(LP."Location Code", LP."Bin Code");
                        Reason := CollectNeeds(LP, Moves, Proof);
                    end;
                if Reason = '' then
                    foreach MoveKey in Moves.Keys() do begin
                        Parts := MoveKey.Split('|');
                        if (not IsLotWhse(CopyStr(Parts.Get(1), 1, 20))) and (Parts.Get(3) <> '') then
                            Reason := 'Maddede depo lot izlemesi yok; elle kontrol edin';
                    end;

                // Plan every LP first; nothing is posted before the whole run is planned.
                if Reason = '' then begin
                    RecordedBin := LastRecordedBin(LP."No.");
                    foreach MoveKey in Moves.Keys() do begin
                        Parts := MoveKey.Split('|');
                        HereKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + MoveKey;
                        if not MissingLeft.ContainsKey(HereKey) then
                            MissingLeft.Add(HereKey, OverClaimFor(LP."Location Code", LP."Bin Code", MoveKey));
                        Remaining := Moves.Get(MoveKey);
                        if Remaining > MissingLeft.Get(HereKey) then
                            Remaining := MissingLeft.Get(HereKey);
                        if Remaining > Tolerance() then begin
                            CandidateSourceBins(LP."Location Code", LP."Bin Code", CopyStr(Parts.Get(1), 1, 20), CopyStr(Parts.Get(2), 1, 10), Candidates);
                            Clear(Allowed);
                            if TraceMode then begin
                                // Only the bins this LP's own lot went to without the LP.
                                LotTraceBins(LP, CopyStr(Parts.Get(1), 1, 20), CopyStr(Parts.Get(2), 1, 10), CopyStr(Parts.Get(3), 1, 50), TraceBins, TraceQtys);
                                foreach CandidateBin in TraceBins do
                                    if Candidates.Contains(CandidateBin) then begin
                                        Allowed.Add(CandidateBin);
                                        TraceKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + CandidateBin + '|' + MoveKey;
                                        if not TraceLeft.ContainsKey(TraceKey) then
                                            TraceLeft.Add(TraceKey, TraceQtys.Get(CandidateBin));
                                    end;
                            end else
                                foreach CandidateBin in Candidates do
                                    Allowed.Add(CandidateBin);
                            foreach CandidateBin in Allowed do begin
                                ThereKey := LP."Location Code" + '|' + CandidateBin + '|' + MoveKey;
                                if not FreeLeft.ContainsKey(ThereKey) then
                                    FreeLeft.Add(ThereKey, -OverClaimFor(LP."Location Code", CandidateBin, MoveKey));
                            end;
                            while Remaining > Tolerance() do begin
                                ChosenBin := '';
                                Why := '';
                                if TraceMode then begin
                                    foreach CandidateBin in Allowed do
                                        if ChosenBin = '' then
                                            if (FreeLeft.Get(LP."Location Code" + '|' + CandidateBin + '|' + MoveKey) > Tolerance()) and
                                               (TraceLeft.Get(LP."Location Code" + '|' + LP."Bin Code" + '|' + CandidateBin + '|' + MoveKey) > Tolerance())
                                            then begin
                                                ChosenBin := CandidateBin;
                                                Why := 'LP''nin lotunun LP''siz taşındığı göz';
                                            end;
                                end else begin
                                    // 1) recorded bin, 2) exact free match, 3) most free stock
                                    if (RecordedBin <> '') and Allowed.Contains(RecordedBin) then
                                        if FreeLeft.Get(LP."Location Code" + '|' + RecordedBin + '|' + MoveKey) > Tolerance() then begin
                                            ChosenBin := RecordedBin;
                                            Why := 'kayıtlı göz';
                                        end;
                                    if ChosenBin = '' then
                                        foreach CandidateBin in Allowed do
                                            if ChosenBin = '' then begin
                                                Free := FreeLeft.Get(LP."Location Code" + '|' + CandidateBin + '|' + MoveKey);
                                                if Abs(Free - Remaining) <= Tolerance() then begin
                                                    ChosenBin := CandidateBin;
                                                    Why := 'miktarı birebir tutan göz';
                                                end;
                                            end;
                                    if ChosenBin = '' then begin
                                        BestFree := 0;
                                        foreach CandidateBin in Allowed do begin
                                            Free := FreeLeft.Get(LP."Location Code" + '|' + CandidateBin + '|' + MoveKey);
                                            if Free > BestFree + Tolerance() then begin
                                                BestFree := Free;
                                                ChosenBin := CandidateBin;
                                                Why := 'en çok serbest stok';
                                            end;
                                        end;
                                    end;
                                end;
                                Take := 0;
                                if ChosenBin <> '' then begin
                                    ThereKey := LP."Location Code" + '|' + ChosenBin + '|' + MoveKey;
                                    Take := Remaining;
                                    if Take > FreeLeft.Get(ThereKey) then
                                        Take := FreeLeft.Get(ThereKey);
                                    if TraceMode then begin
                                        TraceKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + ChosenBin + '|' + MoveKey;
                                        if Take > TraceLeft.Get(TraceKey) then
                                            Take := TraceLeft.Get(TraceKey);
                                        TraceLeft.Set(TraceKey, TraceLeft.Get(TraceKey) - Take);
                                    end;
                                    Take := Round(Take, 0.00001);
                                end;
                                if Take <= 0 then
                                    Remaining := 0 // no usable stock left: leave the rest
                                else begin
                                    FreeLeft.Set(ThereKey, FreeLeft.Get(ThereKey) - Take);
                                    MissingLeft.Set(HereKey, MissingLeft.Get(HereKey) - Take);
                                    Remaining -= Take;
                                    PlanLps.Add(LP."No.");
                                    PlanBins.Add(ChosenBin);
                                    PlanKeys.Add(MoveKey);
                                    PlanQtys.Add(Take);
                                    AddNet(NetMoved, LP."Location Code" + '|' + ChosenBin + '|' + Parts.Get(1) + '|' + Parts.Get(2), -Take);
                                    AddNet(NetMoved, LP."Location Code" + '|' + LP."Bin Code" + '|' + Parts.Get(1) + '|' + Parts.Get(2), Take);
                                    AddLink(RunLinks, LP."Location Code" + '|' + ChosenBin + '|' + Parts.Get(1) + '|' + Parts.Get(2), LP."Bin Code");
                                    MovedQty += Take;
                                    if Moved <> '' then
                                        Moved += ', ';
                                    Moved += Parts.Get(1) + ' ' + Format(Take) + ' (Lot ' + Parts.Get(3) + ') ' + ChosenBin + ' gözünden, ' + Why;
                                end;
                            end;
                        end;
                    end;
                    if PlanKeys.Count() < FirstPlan then
                        if TraceMode then
                            Reason := 'Eksik yok ya da LP''nin lotu LP''siz başka göze taşınmamış / orada serbest stok yok; elle kontrol edin'
                        else
                            Reason := 'Tamamlanacak eksik ya da kullanılabilir serbest stok yok';
                end;

                Clear(Row);
                Row.Add('lpNo', LP."No.");
                Row.Add('toBin', LP."Bin Code");
                if Reason = '' then begin
                    if ApplyChanges then
                        Row.Add('result', 'Stok taşındı: ' + Moved)
                    else
                        Row.Add('result', 'Stok taşınacak: ' + Moved);
                    Row.Add('baseQuantity', MovedQty);
                    Done += 1;
                end else begin
                    Row.Add('result', Reason);
                    Skipped += 1;
                end;
                Rows.Add(Row);
            until LP.Next() = 0;

        PlanTakeRepoints(NetMoved, RunLinks, ApplyChanges, PickRows, Repoints, Blocking);

        if ApplyChanges then begin
            if Blocking <> '' then
                Error('Hiçbir şey kaydedilmedi. Stok taşınınca şu açık çekme/taşıma satırlarının gözünde stok kalmıyor ve satır LP gözüne çevrilemiyor; önce bu satırları silin veya düzeltin: %1', Blocking);
            for i := 1 to PlanKeys.Count() do begin
                LP.Get(PlanLps.Get(i));
                Parts := PlanKeys.Get(i).Split('|');
                // Pass the LP: our lot-level free-stock check above replaces the
                // terminal's item-level loose check (a stale LP claim of another
                // lot in the source bin must not block a proven lot move), and
                // the warehouse entry records which LP the stock belongs to.
                MovementMgmt.AdHocMoveTrackedAtLocation(
                    LP."Location Code", PlanBins.Get(i), LP."Bin Code",
                    CopyStr(Parts.Get(1), 1, 20), LP."No.", PlanQtys.Get(i),
                    CopyStr(UserId(), 1, 50), CopyStr(Parts.Get(3), 1, 50), '');
                LedgerKey := LP."No." + '|' + PlanBins.Get(i);
                if not LedgerKeys.Contains(LedgerKey) then begin
                    LedgerKeys.Add(LedgerKey);
                    LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::Moved, PlanBins.Get(i), LP."Bin Code", 0, '', '', Reference);
                end;
            end;
            foreach RepointText in Repoints do
                RepointTakeLine(RepointText);
        end;

        Result.Add('applied', ApplyChanges);
        Result.Add('moved', Done);
        Result.Add('skipped', Skipped);
        Result.Add('repointed', Repoints.Count());
        Result.Add('blocking', Blocking);
        Result.Add('rows', Rows);
        Result.Add('pickLines', PickRows);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>
    /// Open pick/movement Take lines whose bin no longer holds enough of the item
    /// once the stock went to an LP bin (planned in this run or moved by an
    /// earlier LP-STOK run). Such lines are pointed to that LP bin when it has the
    /// whole outstanding quantity free (not taken by other open Take lines).
    /// Partly handled lines, lines with a lot/serial already chosen and lines
    /// reserved for another LP are only reported. Blocking lists the bins this
    /// run would leave short.
    /// </summary>
    local procedure PlanTakeRepoints(var NetMoved: Dictionary of [Text, Decimal]; var RunLinks: Dictionary of [Text, Text]; ApplyChanges: Boolean; var PickRows: JsonArray; var Repoints: List of [Text]; var Blocking: Text)
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        Links: Dictionary of [Text, Text];
        RepointDelta: Dictionary of [Text, Decimal];
        Parts: List of [Text];
        Targets: List of [Text];
        Row: JsonObject;
        LinkKey: Text;
        Target: Text;
        TargetKey: Text;
        ChosenKey: Text;
        Note: Text;
        LocationCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[10];
        ChosenBin: Code[20];
        Balance: Decimal;
        ShortBefore: Decimal;
        Shortfall: Decimal;
        TargetFree: Decimal;
    begin
        foreach LinkKey in RunLinks.Keys() do
            Links.Add(LinkKey, RunLinks.Get(LinkKey));
        AddPastLinks(Links);
        foreach LinkKey in Links.Keys() do begin
            Parts := LinkKey.Split('|');
            LocationCode := CopyStr(Parts.Get(1), 1, MaxStrLen(LocationCode));
            BinCode := CopyStr(Parts.Get(2), 1, MaxStrLen(BinCode));
            ItemNo := CopyStr(Parts.Get(3), 1, MaxStrLen(ItemNo));
            VariantCode := CopyStr(Parts.Get(4), 1, MaxStrLen(VariantCode));
            Balance := BinBalance(LocationCode, BinCode, ItemNo, VariantCode, '', '', false, false);
            ShortBefore := OutstandingTakes(LocationCode, BinCode, ItemNo, VariantCode) - Balance;
            Shortfall := ShortBefore + NetFor(RepointDelta, LinkKey) - NetFor(NetMoved, LinkKey);
            if Shortfall > Tolerance() then begin
                WhseActivityLine.Reset();
                WhseActivityLine.SetRange("Location Code", LocationCode);
                WhseActivityLine.SetRange("Bin Code", BinCode);
                WhseActivityLine.SetRange("Item No.", ItemNo);
                WhseActivityLine.SetRange("Variant Code", VariantCode);
                WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Take);
                WhseActivityLine.SetFilter("Activity Type", '%1|%2', WhseActivityLine."Activity Type"::Pick, WhseActivityLine."Activity Type"::Movement);
                WhseActivityLine.SetFilter("Qty. Outstanding (Base)", '>0');
                if WhseActivityLine.FindSet() then
                    repeat
                        if Shortfall > Tolerance() then begin
                            ChosenBin := '';
                            ChosenKey := '';
                            Note := '';
                            if WhseActivityLine."Qty. Handled (Base)" <> 0 then
                                Note := 'satır kısmen işlenmiş'
                            else
                                if (WhseActivityLine."Lot No." <> '') or (WhseActivityLine."Serial No." <> '') then
                                    Note := 'satırda lot/seri seçilmiş'
                                else begin
                                    Targets := Links.Get(LinkKey).Split(',');
                                    foreach Target in Targets do
                                        if ChosenBin = '' then
                                            if (WhseActivityLine."LP No." = '') or LpInBin(WhseActivityLine."LP No.", CopyStr(Target, 1, 20)) then begin
                                                TargetKey := LocationCode + '|' + Target + '|' + ItemNo + '|' + VariantCode;
                                                TargetFree :=
                                                    BinBalance(LocationCode, CopyStr(Target, 1, 20), ItemNo, VariantCode, '', '', false, false) +
                                                    NetFor(NetMoved, TargetKey) -
                                                    OutstandingTakes(LocationCode, CopyStr(Target, 1, 20), ItemNo, VariantCode) -
                                                    NetFor(RepointDelta, TargetKey);
                                                if TargetFree >= WhseActivityLine."Qty. Outstanding (Base)" - Tolerance() then begin
                                                    ChosenBin := CopyStr(Target, 1, 20);
                                                    ChosenKey := TargetKey;
                                                end;
                                            end;
                                    if ChosenBin = '' then
                                        Note := 'LP gözünde bu satır için yeterli serbest stok yok';
                                end;
                            Clear(Row);
                            Row.Add('document', Format(WhseActivityLine."Activity Type") + ' ' + WhseActivityLine."No.");
                            Row.Add('lineNo', WhseActivityLine."Line No.");
                            Row.Add('itemNo', ItemNo);
                            Row.Add('fromBin', BinCode);
                            Row.Add('quantityBase', WhseActivityLine."Qty. Outstanding (Base)");
                            if ChosenBin <> '' then begin
                                Repoints.Add(Format(WhseActivityLine."Activity Type".AsInteger()) + '|' + WhseActivityLine."No." + '|' + Format(WhseActivityLine."Line No.") + '|' + ChosenBin);
                                AddNet(RepointDelta, ChosenKey, WhseActivityLine."Qty. Outstanding (Base)");
                                AddNet(RepointDelta, LinkKey, -WhseActivityLine."Qty. Outstanding (Base)");
                                Shortfall -= WhseActivityLine."Qty. Outstanding (Base)";
                                Row.Add('toBin', ChosenBin);
                                if ApplyChanges then
                                    Row.Add('result', 'Alma gözü LP gözüne çevrildi')
                                else
                                    Row.Add('result', 'Alma gözü LP gözüne çevrilecek');
                            end else
                                Row.Add('result', 'Elle bakın: ' + Note);
                            PickRows.Add(Row);
                        end;
                    until WhseActivityLine.Next() = 0;
                // Block only what this run makes worse and cannot point elsewhere.
                if RunLinks.ContainsKey(LinkKey) then
                    if Shortfall > NonNegative(ShortBefore) + Tolerance() then begin
                        if Blocking <> '' then
                            Blocking += ', ';
                        Blocking += BinCode + ' ' + ItemNo + ' (' + Format(Shortfall) + ')';
                    end;
            end;
        end;
    end;

    /// <summary>Source bin -> LP bin links written by earlier LP-STOK runs (LP movement rows).</summary>
    local procedure AddPastLinks(var Links: Dictionary of [Text, Text])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        Ledger.SetRange(Action, Ledger.Action::Moved);
        Ledger.SetFilter("Related Document", 'LP-STOK-*');
        if Ledger.FindSet() then
            repeat
                if (Ledger."From Bin" <> '') and (Ledger."To Bin" <> '') and (Ledger."From Bin" <> Ledger."To Bin") then
                    if LP.Get(Ledger."LP No.") then begin
                        LPLine.Reset();
                        LPLine.SetRange("LP No.", LP."No.");
                        LPLine.SetFilter("Item No.", '<>%1', '');
                        if LPLine.FindSet() then
                            repeat
                                AddLink(Links, LP."Location Code" + '|' + Ledger."From Bin" + '|' + LPLine."Item No." + '|' + LPLine."Variant Code", Ledger."To Bin");
                            until LPLine.Next() = 0;
                    end;
            until Ledger.Next() = 0;
    end;

    local procedure RepointTakeLine(RepointText: Text)
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        Bin: Record Bin;
        Parts: List of [Text];
        ActivityType: Integer;
        LineNo: Integer;
        ToBin: Code[20];
    begin
        Parts := RepointText.Split('|');
        Evaluate(ActivityType, Parts.Get(1));
        Evaluate(LineNo, Parts.Get(3));
        ToBin := CopyStr(Parts.Get(4), 1, MaxStrLen(ToBin));
        WhseActivityLine.Get(Enum::"Warehouse Activity Type".FromInteger(ActivityType), CopyStr(Parts.Get(2), 1, 20), LineNo);
        Bin.Get(WhseActivityLine."Location Code", ToBin);
        if WhseActivityLine."Zone Code" <> Bin."Zone Code" then
            WhseActivityLine.Validate("Zone Code", Bin."Zone Code");
        WhseActivityLine.Validate("Bin Code", ToBin);
        WhseActivityLine.Modify(true);
    end;

    /// <summary>
    /// Bins the LP's own lot was moved to without the LP: movement entries out of
    /// the LP bin without an LP number, registered after the LP's last arrival in
    /// that bin, with the paired entry (next entry, same item/lot/quantity) as the
    /// destination.
    /// </summary>
    local procedure LotTraceBins(LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; var TraceBins: List of [Code[20]]; var TraceQtys: Dictionary of [Code[20], Decimal])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
        OutEntry: Record "Warehouse Entry";
        InEntry: Record "Warehouse Entry";
        Since: DateTime;
        Qty: Decimal;
    begin
        Clear(TraceBins);
        Clear(TraceQtys);
        if LotNo = '' then
            exit;
        Ledger.SetRange("LP No.", LP."No.");
        Ledger.SetFilter(Action, '%1|%2|%3|%4|%5',
            Ledger.Action::Built, Ledger.Action::Moved, Ledger.Action::ItemAdded,
            Ledger.Action::TransferIn, Ledger.Action::TransferOut);
        Ledger.SetRange("To Bin", LP."Bin Code");
        if not Ledger.FindLast() then
            exit;
        Since := Ledger.DateTime;
        OutEntry.SetRange("Location Code", LP."Location Code");
        OutEntry.SetRange("Bin Code", LP."Bin Code");
        OutEntry.SetRange("Item No.", ItemNo);
        OutEntry.SetRange("Variant Code", VariantCode);
        OutEntry.SetRange("Lot No.", LotNo);
        OutEntry.SetRange("Entry Type", OutEntry."Entry Type"::Movement);
        OutEntry.SetFilter("Qty. (Base)", '<0');
        OutEntry.SetRange("DOPSWHS LP No.", '');
        if OutEntry.FindSet() then
            repeat
                if OutEntry.SystemCreatedAt > Since then
                    if InEntry.Get(OutEntry."Entry No." + 1) then
                        if (InEntry."Location Code" = OutEntry."Location Code") and
                           (InEntry."Item No." = ItemNo) and (InEntry."Variant Code" = VariantCode) and
                           (InEntry."Lot No." = LotNo) and (InEntry."Qty. (Base)" = -OutEntry."Qty. (Base)") and
                           (InEntry."Bin Code" <> LP."Bin Code") and (InEntry."DOPSWHS LP No." = '')
                        then
                            if TraceQtys.Get(InEntry."Bin Code", Qty) then
                                TraceQtys.Set(InEntry."Bin Code", Qty + InEntry."Qty. (Base)")
                            else begin
                                TraceQtys.Add(InEntry."Bin Code", InEntry."Qty. (Base)");
                                TraceBins.Add(InEntry."Bin Code");
                            end;
            until OutEntry.Next() = 0;
    end;

    local procedure OutstandingTakes(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Location Code", LocationCode);
        WhseActivityLine.SetRange("Bin Code", BinCode);
        WhseActivityLine.SetRange("Item No.", ItemNo);
        WhseActivityLine.SetRange("Variant Code", VariantCode);
        WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Take);
        WhseActivityLine.SetFilter("Activity Type", '%1|%2', WhseActivityLine."Activity Type"::Pick, WhseActivityLine."Activity Type"::Movement);
        WhseActivityLine.CalcSums("Qty. Outstanding (Base)");
        exit(WhseActivityLine."Qty. Outstanding (Base)");
    end;

    local procedure LpInBin(LpNo: Code[20]; BinCode: Code[20]): Boolean
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if not LP.Get(LpNo) then
            exit(false);
        exit(LP."Bin Code" = BinCode);
    end;

    local procedure IsSyncLocation(LocationCode: Code[10]): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if LocationCode = '' then
            exit(false);
        if not Setup.Get() then
            exit(false);
        exit(Setup."Prod. LP Sync Location" = LocationCode);
    end;

    local procedure AddNet(var Net: Dictionary of [Text, Decimal]; NetKey: Text; Delta: Decimal)
    var
        Existing: Decimal;
    begin
        if Net.Get(NetKey, Existing) then
            Net.Set(NetKey, Existing + Delta)
        else
            Net.Add(NetKey, Delta);
    end;

    local procedure NetFor(var Net: Dictionary of [Text, Decimal]; NetKey: Text): Decimal
    var
        Existing: Decimal;
    begin
        if Net.Get(NetKey, Existing) then
            exit(Existing);
        exit(0);
    end;

    local procedure AddLink(var Links: Dictionary of [Text, Text]; LinkKey: Text; TargetBin: Text)
    var
        Existing: Text;
    begin
        if not Links.Get(LinkKey, Existing) then begin
            Links.Add(LinkKey, TargetBin);
            exit;
        end;
        if not Existing.Split(',').Contains(TargetBin) then
            Links.Set(LinkKey, Existing + ',' + TargetBin);
    end;

    /// <summary>
    /// BADE (28 Eyl 2026): production picks registered in BC took stock out of
    /// the configured LP bins (e.g. A.URETIM) without reducing the LPs there, so
    /// the LPs show more than the bin holds. For every item/lot of the active LPs
    /// in those bins where the LPs claim more than the bin balance, the excess is
    /// removed from the LPs - at most the quantity that LP-less production picks
    /// took out of that bin/item/lot since the first of these LPs arrived there
    /// (the proof). Order: the LP assigned to one of those production orders,
    /// then unassigned LPs, then the rest, each by LP No. Only LP lines change;
    /// nothing is posted to warehouse or item ledgers. Stock added to the bin by
    /// a positive adjustment in the same period is reported (count advised).
    /// Preview with ApplyChanges = false; running it again finds nothing.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure DebitUntrackedProductionPicks(ApplyChanges: Boolean): Text
    var
        Setup: Record "DOPSWHS Setup";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Keys: List of [Text];
        Parts: List of [Text];
        Orders: List of [Code[20]];
        Rows: JsonArray;
        Row: JsonObject;
        Result: JsonObject;
        ResultText: Text;
        KeyText: Text;
        Allocation: Text;
        Note: Text;
        Reference: Code[40];
        LocationCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[10];
        LotNo: Code[50];
        UseLot: Boolean;
        Since: DateTime;
        Claims: Decimal;
        Balance: Decimal;
        Excess: Decimal;
        Proof: Decimal;
        Counted: Decimal;
        Reduce: Decimal;
        Reduced: Decimal;
        TotalReduced: Decimal;
        Done: Integer;
        Unexplained: Integer;
    begin
        if not Setup.Get() then
            Error('WMS Kurulum bulunamadı.');
        LocationCode := Setup."Prod. LP Sync Location";
        if (LocationCode = '') or (DelChr(Setup."Prod. LP Sync Bin Filter", '=', ' ') = '') then
            Error('WMS Kurulum''da "LP düzeltme lokasyonu" ve "LP düzeltme gözleri" doldurulmalı (ör. MERKEZDEPO / A.URETIM).');
        if ApplyChanges then begin
            LP.LockTable();
            LPLine.LockTable();
        end;
        Reference := CopyStr('LP-URETIM-DUS#' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2>'), 1, 40);

        // Every bin/item/variant/lot held by an active LP in the configured bins.
        LP.SetRange("Location Code", LocationCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetRange("Pending Receipt No.", '');
        if LP.FindSet() then
            repeat
                if IsSyncBin(LP."Location Code", LP."Bin Code") then begin
                    LPLine.Reset();
                    LPLine.SetRange("LP No.", LP."No.");
                    LPLine.SetFilter("Item No.", '<>%1', '');
                    LPLine.SetFilter(Quantity, '>0');
                    LPLine.SetRange("Serial No.", '');
                    if LPLine.FindSet() then
                        repeat
                            KeyText := LP."Bin Code" + '|' + LPLine."Item No." + '|' + LPLine."Variant Code" + '|';
                            if IsLotWhse(LPLine."Item No.") then
                                KeyText += LPLine."Lot No.";
                            if not Keys.Contains(KeyText) then
                                Keys.Add(KeyText);
                        until LPLine.Next() = 0;
                end;
            until LP.Next() = 0;

        foreach KeyText in Keys do begin
            Parts := KeyText.Split('|');
            BinCode := CopyStr(Parts.Get(1), 1, MaxStrLen(BinCode));
            ItemNo := CopyStr(Parts.Get(2), 1, MaxStrLen(ItemNo));
            VariantCode := CopyStr(Parts.Get(3), 1, MaxStrLen(VariantCode));
            LotNo := CopyStr(Parts.Get(4), 1, MaxStrLen(LotNo));
            UseLot := IsLotWhse(ItemNo);
            Claims := BinClaims(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', UseLot, false);
            Balance := BinBalance(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', UseLot, false);
            Excess := Round(Claims - Balance, 0.00001);
            if Excess > Tolerance() then begin
                Since := FirstArrivalOfKey(LocationCode, BinCode, ItemNo, VariantCode, LotNo, UseLot);
                Excess -= OtherPickTakesSince(LocationCode, BinCode, ItemNo, VariantCode, LotNo, UseLot, Since);
                UntrackedProductionTakes(LocationCode, BinCode, ItemNo, VariantCode, LotNo, UseLot, Since, Proof, Orders);
                // Picks already debited (automatic pick debit or an earlier run of
                // this action) no longer prove anything: repeated runs stay capped.
                Proof -= PickDebitsSince(BinCode, ItemNo, LotNo, UseLot, Since);
                if Proof < 0 then
                    Proof := 0;
                Counted := PositiveAdjustmentsSince(LocationCode, BinCode, ItemNo, VariantCode, LotNo, UseLot, Since);
                if Excess < 0 then
                    Excess := 0;
                Reduce := Excess;
                if Reduce > Proof then
                    Reduce := Proof;
                Allocation := '';
                Reduced := 0;
                if Reduce > Tolerance() then
                    Reduced := AllocateDebit(LocationCode, BinCode, ItemNo, VariantCode, LotNo, UseLot, Reduce, Orders, ApplyChanges, Reference, Allocation);
                Note := '';
                if Excess - Reduced > Tolerance() then begin
                    Note := StrSubstNo('%1 adet fark LP''siz üretim çekmesiyle açıklanamadı; dokunulmadı, sayım gerekir.', Format(Excess - Reduced));
                    Unexplained += 1;
                end;
                if Counted > Tolerance() then begin
                    if Note <> '' then
                        Note += ' ';
                    Note += StrSubstNo('Bu dönemde göze sayım/düzeltmeyle %1 adet eklenmiş; BC stoğu da fazla olabilir, sayım önerilir.', Format(Counted));
                end;
                Clear(Row);
                Row.Add('bin', BinCode);
                Row.Add('itemNo', ItemNo);
                Row.Add('lotNo', LotNo);
                Row.Add('lpQuantity', Claims);
                Row.Add('binQuantity', Balance);
                Row.Add('excess', Excess);
                Row.Add('untrackedProductionPicks', Proof);
                Row.Add('reduced', Reduced);
                Row.Add('allocation', Allocation);
                Row.Add('note', Note);
                Rows.Add(Row);
                if Reduced > Tolerance() then begin
                    Done += 1;
                    TotalReduced += Reduced;
                end;
            end;
        end;

        Result.Add('applied', ApplyChanges);
        Result.Add('reducedRows', Done);
        Result.Add('unexplainedRows', Unexplained);
        Result.Add('totalReduced', TotalReduced);
        Result.Add('rows', Rows);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>Earliest start of the current stay in the bin of the active LPs holding this item/lot.</summary>
    local procedure FirstArrivalOfKey(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean) Since: DateTime
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Arrived: DateTime;
    begin
        LPLine.SetCurrentKey("Item No.");
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if UseLot then
            LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) and (LP."Bin Code" = BinCode) then begin
                        // Start of the LP's current stay in this bin: its latest
                        // position-setting movement into the bin (e.g. a stock
                        // alignment); without one, the LP's creation time.
                        Arrived := LP.SystemCreatedAt;
                        Ledger.Reset();
                        Ledger.SetRange("LP No.", LP."No.");
                        Ledger.SetRange("To Bin", BinCode);
                        Ledger.SetFilter(Action, '%1|%2|%3|%4|%5',
                            Ledger.Action::Built, Ledger.Action::Moved, Ledger.Action::ItemAdded,
                            Ledger.Action::TransferIn, Ledger.Action::TransferOut);
                        if Ledger.FindLast() then
                            Arrived := Ledger.DateTime;
                        if (Since = 0DT) or (Arrived < Since) then
                            Since := Arrived;
                    end;
            until LPLine.Next() = 0;
    end;

    /// <summary>Production pick Takes out of the bin that carried no LP, since a moment; also the production orders involved.</summary>
    local procedure UntrackedProductionTakes(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean; Since: DateTime; var Proof: Decimal; var Orders: List of [Code[20]])
    var
        Entry: Record "Warehouse Entry";
        HintLP: Record "DOPSWHS LP Header";
        Counted: Boolean;
    begin
        // Net production-pick outflow of this bin/item/lot since the moment:
        // Takes minus same-bin Places (breakbulk). An entry stamped with an LP
        // counts only while that LP still stands in this bin (an unused hint);
        // LPs staged whole to production left together with their stock.
        Proof := 0;
        Clear(Orders);
        Entry.SetRange("Location Code", LocationCode);
        Entry.SetRange("Bin Code", BinCode);
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Variant Code", VariantCode);
        if UseLot then
            Entry.SetRange("Lot No.", LotNo);
        Entry.SetRange("Entry Type", Entry."Entry Type"::Movement);
        Entry.SetRange("Reference Document", Entry."Reference Document"::Pick);
        Entry.SetRange("Source Type", Database::"Prod. Order Component");
        if Since <> 0DT then
            Entry.SetFilter(SystemCreatedAt, '>=%1', Since);
        if Entry.FindSet() then
            repeat
                Counted := Entry."DOPSWHS LP No." = '';
                if not Counted then
                    if HintLP.Get(Entry."DOPSWHS LP No.") then
                        Counted := (HintLP."Location Code" = LocationCode) and (HintLP."Bin Code" = BinCode);
                if Counted then begin
                    Proof += -Entry."Qty. (Base)";
                    if (Entry."Qty. (Base)" < 0) and (Entry."Source No." <> '') and not Orders.Contains(Entry."Source No.") then
                        Orders.Add(Entry."Source No.");
                end;
            until Entry.Next() = 0;
        if Proof < 0 then
            Proof := 0;
    end;

    /// <summary>
    /// Registered non-production picks out of the bin since the moment: their
    /// LP is reduced later by the shipment reconciliation, so this part of the
    /// excess must not be debited by the repair.
    /// </summary>
    local procedure OtherPickTakesSince(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean; Since: DateTime): Decimal
    var
        Entry: Record "Warehouse Entry";
    begin
        Entry.SetRange("Location Code", LocationCode);
        Entry.SetRange("Bin Code", BinCode);
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Variant Code", VariantCode);
        if UseLot then
            Entry.SetRange("Lot No.", LotNo);
        Entry.SetRange("Entry Type", Entry."Entry Type"::Movement);
        Entry.SetRange("Reference Document", Entry."Reference Document"::Pick);
        Entry.SetFilter("Source Type", '<>%1', Database::"Prod. Order Component");
        if Since <> 0DT then
            Entry.SetFilter(SystemCreatedAt, '>=%1', Since);
        Entry.CalcSums("Qty. (Base)");
        if Entry."Qty. (Base)" < 0 then
            exit(-Entry."Qty. (Base)");
        exit(0);
    end;

    local procedure PickDebitsSince(BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; UseLot: Boolean; Since: DateTime): Decimal
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Total: Decimal;
    begin
        Ledger.SetRange(Action, Ledger.Action::ItemRemoved);
        Ledger.SetRange("From Bin", BinCode);
        Ledger.SetRange("Item No.", ItemNo);
        if UseLot then
            Ledger.SetRange("Lot Serial", LotNo);
        Ledger.SetFilter("Related Document", 'PP:*|LP-URETIM-DUS*');
        if Since <> 0DT then
            Ledger.SetFilter(DateTime, '>=%1', Since);
        if Ledger.FindSet() then
            repeat
                Total += Ledger.Quantity;
            until Ledger.Next() = 0;
        exit(Total);
    end;

    local procedure PositiveAdjustmentsSince(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean; Since: DateTime): Decimal
    var
        Entry: Record "Warehouse Entry";
    begin
        Entry.SetRange("Location Code", LocationCode);
        Entry.SetRange("Bin Code", BinCode);
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Variant Code", VariantCode);
        if UseLot then
            Entry.SetRange("Lot No.", LotNo);
        Entry.SetRange("Entry Type", Entry."Entry Type"::"Positive Adjmt.");
        if Since <> 0DT then
            Entry.SetFilter(SystemCreatedAt, '>=%1', Since);
        Entry.CalcSums("Qty. (Base)");
        exit(Entry."Qty. (Base)");
    end;

    /// <summary>Removes Qty (base) of the item/lot from the LPs in the bin in priority order; returns what was (or would be) removed.</summary>
    local procedure AllocateDebit(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean; Qty: Decimal; Orders: List of [Code[20]]; ApplyChanges: Boolean; Reference: Code[40]; var Allocation: Text) Removed: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        First: List of [Code[20]];
        Second: List of [Code[20]];
        LpNo: Code[20];
        Taken: Decimal;
    begin
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetRange("Pending Receipt No.", '');
        if LP.FindSet() then
            repeat
                // LPs reserved for another document (e.g. a shipment) are never
                // touched: their posting would fail later.
                if (LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption) and Orders.Contains(LP."Assigned Document No.") then
                    First.Add(LP."No.")
                else
                    if LP."Assigned Document No." = '' then
                        Second.Add(LP."No.");
            until LP.Next() = 0;
        foreach LpNo in Second do
            First.Add(LpNo);
        foreach LpNo in First do
            if Qty - Removed > Tolerance() then begin
                Taken := DebitLpKey(LpNo, ItemNo, VariantCode, LotNo, UseLot, Qty - Removed, ApplyChanges, Reference);
                if Taken > Tolerance() then begin
                    Removed += Taken;
                    if Allocation <> '' then
                        Allocation += ', ';
                    Allocation += LpNo + ' -' + Format(Taken);
                end;
            end;
    end;

    local procedure DebitLpKey(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; UseLot: Boolean; Qty: Decimal; ApplyChanges: Boolean; Reference: Code[40]) Removed: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        TargetLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        QtyPer: Decimal;
        LineBase: Decimal;
        TakeBase: Decimal;
        TakeInLineUoM: Decimal;
    begin
        if not LP.Get(LpNo) then
            exit(0);
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if UseLot then
            LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetRange("Serial No.", '');
        LPLine.SetRange("Child LP No.", '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if (Qty - Removed > Tolerance()) and TryQtyPer(LPLine, QtyPer) and TryLineBase(LPLine, LineBase) then begin
                    TakeBase := Qty - Removed;
                    if TakeBase > LineBase then
                        TakeBase := LineBase;
                    TakeInLineUoM := Round(TakeBase / QtyPer, 0.00001);
                    if TakeInLineUoM >= LPLine.Quantity - 0.00001 then begin
                        TakeInLineUoM := LPLine.Quantity;
                        TakeBase := LineBase;
                    end;
                    if TakeInLineUoM <= 0 then
                        TakeBase := 0;
                end else
                    TakeBase := 0;
                if TakeBase > 0 then begin
                    if ApplyChanges then begin
                        TargetLine.Get(LPLine."LP No.", LPLine."Line No.");
                        if TakeInLineUoM >= TargetLine.Quantity then
                            TargetLine.Delete(true)
                        else begin
                            TargetLine.Validate(Quantity, Round(TargetLine.Quantity - TakeInLineUoM, 0.00001));
                            TargetLine.Modify(true);
                        end;
                        LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::ItemRemoved, LP."Bin Code", '', TakeBase, LPLine."Item No.", LPLine."Lot No.", Reference);
                    end;
                    Removed += TakeBase;
                end;
            until LPLine.Next() = 0;
        if ApplyChanges and (Removed > 0) then begin
            LP.Get(LpNo);
            LPMgt.MarkUsedIfEmptied(LP);
        end;
    end;

    /// <summary>
    /// Bins of the location holding the item that may serve as a source. Only
    /// ordinary storage bins: never the LP bin, the configured correction bins,
    /// the adjustment/receipt/shipment/cross-dock bins, production or assembly
    /// bins of the location, work centers or machine centers (e.g. DO.01), bins
    /// whose bin type cannot be picked from or is a receive/ship type, and bins
    /// blocked for outbound movement.
    /// </summary>
    local procedure CandidateSourceBins(LocationCode: Code[10]; LpBinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; var Candidates: List of [Code[20]])
    var
        BinContent: Record "Bin Content";
        Bin: Record Bin;
        Location: Record Location;
    begin
        Clear(Candidates);
        if not Location.Get(LocationCode) then
            exit;
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        if BinContent.FindSet() then
            repeat
                if (BinContent."Bin Code" <> LpBinCode) and
                   not IsSyncBin(LocationCode, BinContent."Bin Code") and
                   not IsSpecialBin(Location, BinContent."Bin Code") and
                   not Candidates.Contains(BinContent."Bin Code")
                then
                    if Bin.Get(LocationCode, BinContent."Bin Code") then
                        if not (Bin."Block Movement" in [Bin."Block Movement"::Outbound, Bin."Block Movement"::All]) then
                            if IsStorageBinType(Bin) then
                                Candidates.Add(BinContent."Bin Code");
            until BinContent.Next() = 0;
    end;

    local procedure IsSpecialBin(Location: Record Location; BinCode: Code[20]): Boolean
    var
        WorkCenter: Record "Work Center";
        MachineCenter: Record "Machine Center";
    begin
        if BinCode in [Location."Adjustment Bin Code", Location."Receipt Bin Code", Location."Shipment Bin Code",
                       Location."Cross-Dock Bin Code", Location."To-Production Bin Code", Location."From-Production Bin Code",
                       Location."Open Shop Floor Bin Code", Location."To-Assembly Bin Code", Location."From-Assembly Bin Code"]
        then
            exit(true);
        WorkCenter.SetRange("Location Code", Location.Code);
        if WorkCenter.FindSet() then
            repeat
                if BinCode in [WorkCenter."To-Production Bin Code", WorkCenter."From-Production Bin Code", WorkCenter."Open Shop Floor Bin Code"] then
                    exit(true);
            until WorkCenter.Next() = 0;
        MachineCenter.SetRange("Location Code", Location.Code);
        if MachineCenter.FindSet() then
            repeat
                if BinCode in [MachineCenter."To-Production Bin Code", MachineCenter."From-Production Bin Code", MachineCenter."Open Shop Floor Bin Code"] then
                    exit(true);
            until MachineCenter.Next() = 0;
        exit(false);
    end;

    local procedure IsStorageBinType(Bin: Record Bin): Boolean
    var
        BinType: Record "Bin Type";
    begin
        if Bin."Bin Type Code" = '' then
            exit(true);
        if not BinType.Get(Bin."Bin Type Code") then
            exit(false);
        exit(BinType.Pick and not BinType.Receive and not BinType.Ship);
    end;

    /// <summary>
    /// Consumption warehouse journal lines are built with InitWhseJnlLine, so the
    /// general LP carry does not reach them. Copy the consumption's LP number so
    /// the warehouse entry is stamped and DebitOrderLpsAfterConsumption can see
    /// that LP Management debits this LP (no double debit).
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Prod. Order Warehouse Mgt.", 'OnAfterCreateWhseJnlLineFromConsumptionJournal', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'R')]
    local procedure CarryLpOntoConsumptionWhseJnlLine(var WarehouseJournalLine: Record "Warehouse Journal Line"; var ItemJournalLine: Record "Item Journal Line")
    var
        LP: Record "DOPSWHS LP Header";
    begin
        // Only an LP standing in the consumption bin; a source LP left in the
        // pick bin just traces loose stock and must not stamp this bin's entry.
        if ItemJournalLine."DOPSWHS LP No." = '' then
            exit;
        if not LP.Get(ItemJournalLine."DOPSWHS LP No.") then
            exit;
        if (LP."Location Code" = ItemJournalLine."Location Code") and (LP."Bin Code" = ItemJournalLine."Bin Code") then
            WarehouseJournalLine."DOPSWHS LP No." := ItemJournalLine."DOPSWHS LP No.";
    end;

    /// <summary>
    /// BADE (28 Eyl 2026): an intact production LP delivered to the component bin
    /// (e.g. DO.01) is assigned to its production order. Consumption posted
    /// without an LP number (production/consumption journal, automatic flushing)
    /// takes the stock but not the LP. After that consumption's warehouse entry,
    /// the part the LPs in the bin now claim above the bin balance - at most this
    /// entry's quantity - is removed only from LPs assigned to THIS production
    /// order, by LP No. Consumption carrying an LP number is debited by LP
    /// Management. Never blocks the posting.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Jnl.-Register Line", 'OnAfterInsertWhseEntry', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    local procedure DebitOrderLpsAfterConsumption(var WarehouseEntry: Record "Warehouse Entry"; var WarehouseJournalLine: Record "Warehouse Journal Line")
    var
        LP: Record "DOPSWHS LP Header";
        Reference: Code[40];
        Excess: Decimal;
        Remaining: Decimal;
        UseLot: Boolean;
    begin
        if WarehouseEntry.IsTemporary() then
            exit;
        if (WarehouseEntry."Qty. (Base)" >= 0) or (WarehouseEntry."Entry Type" <> WarehouseEntry."Entry Type"::"Negative Adjmt.") then
            exit;
        // BC 24 "Prod. Order Warehouse Mgt.".CreateWhseJnlLineFromConsumptionJournal:
        // Source Type = Item Journal Line, Subtype 4 (consumption), Source No. =
        // production order, Whse. Document Type = Production.
        if (WarehouseEntry."Source Type" <> Database::"Item Journal Line") or (WarehouseEntry."Source Subtype" <> 4) then
            exit;
        if (WarehouseEntry."Whse. Document Type" <> WarehouseEntry."Whse. Document Type"::Production) or (WarehouseEntry."Source No." = '') then
            exit;
        if WarehouseEntry."Serial No." <> '' then
            exit;
        // An LP number of an LP in this bin is debited by LP Management; a
        // source LP left in another bin only traces the origin of loose stock.
        if WarehouseJournalLine."DOPSWHS LP No." <> '' then
            if LP.Get(WarehouseJournalLine."DOPSWHS LP No.") then
                if (LP."Location Code" = WarehouseEntry."Location Code") and (LP."Bin Code" = WarehouseEntry."Bin Code") then
                    exit;
        if not IsSyncLocation(WarehouseEntry."Location Code") then
            exit;
        UseLot := IsLotWhse(WarehouseEntry."Item No.");
        Excess :=
            BinClaims(WarehouseEntry."Location Code", WarehouseEntry."Bin Code", WarehouseEntry."Item No.", WarehouseEntry."Variant Code", WarehouseEntry."Lot No.", '', UseLot, false) -
            BinBalance(WarehouseEntry."Location Code", WarehouseEntry."Bin Code", WarehouseEntry."Item No.", WarehouseEntry."Variant Code", WarehouseEntry."Lot No.", '', UseLot, false);
        if Excess > -WarehouseEntry."Qty. (Base)" then
            Excess := -WarehouseEntry."Qty. (Base)";
        if Excess <= Tolerance() then
            exit;
        Reference := CopyStr('SARF#' + WarehouseEntry."Source No." + '#' + Format(WarehouseEntry."Entry No."), 1, MaxStrLen(Reference));
        Remaining := Excess;
        LP.Reset();
        LP.SetRange("Location Code", WarehouseEntry."Location Code");
        LP.SetRange("Bin Code", WarehouseEntry."Bin Code");
        LP.SetRange(Status, LP.Status::Assigned);
        LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::ProdConsumption);
        LP.SetRange("Assigned Document No.", WarehouseEntry."Source No.");
        if LP.FindSet() then
            repeat
                if Remaining > Tolerance() then
                    Remaining -= DebitLpKey(LP."No.", WarehouseEntry."Item No.", WarehouseEntry."Variant Code", WarehouseEntry."Lot No.", UseLot, Remaining, true, Reference);
            until LP.Next() = 0;
    end;

    /// <summary>
    /// Preview (ApplyChanges = false) or fill the missing stock of the selected
    /// LPs from a bin the user chose (e.g. A.TOPLAM). Per LP item/lot it moves
    /// at most: the LP quantity, what is still missing in the LP bin (LP claims
    /// minus warehouse balance there) and what is free in the source bin (not
    /// claimed by any LP). Uses the terminal's tracked ad-hoc bin move. Only LPs
    /// in the configured location/bins; LP contents do not change.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure FillMissingFromBin(var Selected: Record "DOPSWHS LP Header"; SourceBin: Code[20]; ApplyChanges: Boolean): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Bin: Record Bin;
        LPMgt: Codeunit "DOPSWHS LP Management";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Moves: Dictionary of [Text, Decimal];
        Proof: Dictionary of [Text, Decimal];
        Plan: Dictionary of [Text, Decimal];
        MissingLeft: Dictionary of [Text, Decimal];
        FreeLeft: Dictionary of [Text, Decimal];
        Parts: List of [Text];
        Rows: JsonArray;
        Row: JsonObject;
        Result: JsonObject;
        ResultText: Text;
        MoveKey: Text;
        ProofKey: Text;
        HereKey: Text;
        ThereKey: Text;
        Reason: Text;
        Moved: Text;
        Reference: Code[40];
        Take: Decimal;
        MovedQty: Decimal;
        Done: Integer;
        Skipped: Integer;
    begin
        if SourceBin = '' then
            Error('Kaynak göz seçilmedi.');
        if ApplyChanges then begin
            LP.LockTable();
            LPLine.LockTable();
        end;
        Reference := CopyStr('LP-STOK-TAMAMLA#' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2>'), 1, 40);
        LP.CopyFilters(Selected);
        if LP.FindSet() then
            repeat
                Reason := '';
                Moved := '';
                MovedQty := 0;
                Clear(Moves);
                Clear(Proof);
                if not IsActive(LP) then
                    Reason := 'LP aktif değil veya mal kabulü bekliyor'
                else
                    if not IsSyncBin(LP."Location Code", LP."Bin Code") then
                        Reason := 'LP, Kurulum''daki LP düzeltme lokasyonu/gözleri dışında'
                    else
                        if SourceBin = LP."Bin Code" then
                            Reason := 'Kaynak göz LP''nin kendi gözü'
                        else
                            if not Bin.Get(LP."Location Code", SourceBin) then
                                Reason := SourceBin + ' gözü ' + LP."Location Code" + ' lokasyonunda yok'
                            else
                                Reason := CollectNeeds(LP, Moves, Proof);

                // 1. Every line must be provable before anything is planned.
                if Reason = '' then
                    foreach MoveKey in Moves.Keys() do begin
                        Parts := MoveKey.Split('|');
                        if (not IsLotWhse(CopyStr(Parts.Get(1), 1, 20))) and (Parts.Get(3) <> '') then
                            Reason := 'Maddede depo lot izlemesi yok; elle kontrol edin';
                    end;

                // 2. Plan: at most LP qty, what is missing in the LP bin, what is free in the source.
                if Reason = '' then begin
                    Clear(Plan);
                    foreach MoveKey in Moves.Keys() do begin
                        Parts := MoveKey.Split('|');
                        ProofKey := Parts.Get(1) + '|' + Parts.Get(2) + '|' + Parts.Get(3);
                        HereKey := LP."Location Code" + '|' + LP."Bin Code" + '|' + ProofKey;
                        ThereKey := LP."Location Code" + '|' + SourceBin + '|' + ProofKey;
                        if not MissingLeft.ContainsKey(HereKey) then
                            MissingLeft.Add(HereKey, OverClaimFor(LP."Location Code", LP."Bin Code", ProofKey));
                        if not FreeLeft.ContainsKey(ThereKey) then
                            FreeLeft.Add(ThereKey, -OverClaimFor(LP."Location Code", SourceBin, ProofKey));
                        Take := Moves.Get(MoveKey);
                        if Take > MissingLeft.Get(HereKey) then
                            Take := MissingLeft.Get(HereKey);
                        if Take > FreeLeft.Get(ThereKey) then
                            Take := FreeLeft.Get(ThereKey);
                        Take := Round(Take, 0.00001);
                        if Take > Tolerance() then begin
                            MissingLeft.Set(HereKey, MissingLeft.Get(HereKey) - Take);
                            FreeLeft.Set(ThereKey, FreeLeft.Get(ThereKey) - Take);
                            Plan.Add(MoveKey, Take);
                            MovedQty += Take;
                            if Moved <> '' then
                                Moved += ', ';
                            Moved += Parts.Get(1) + ' ' + Format(Take) + ' (Lot ' + Parts.Get(3) + ')';
                        end;
                    end;
                    if Plan.Count() = 0 then
                        Reason := SourceBin + ' gözünden tamamlanacak eksik yok';
                end;

                // 3. Post only a fully planned LP.
                if (Reason = '') and ApplyChanges then
                    foreach MoveKey in Plan.Keys() do begin
                        Parts := MoveKey.Split('|');
                        MovementMgmt.AdHocMoveTrackedAtLocation(
                            LP."Location Code", SourceBin, LP."Bin Code",
                            CopyStr(Parts.Get(1), 1, 20), LP."No.", Plan.Get(MoveKey),
                            CopyStr(UserId(), 1, 50), CopyStr(Parts.Get(3), 1, 50), '');
                    end;

                Clear(Row);
                Row.Add('lpNo', LP."No.");
                Row.Add('fromBin', SourceBin);
                Row.Add('toBin', LP."Bin Code");
                if Reason = '' then begin
                    if ApplyChanges then begin
                        LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::Moved, SourceBin, LP."Bin Code", 0, '', '', Reference);
                        Row.Add('result', 'Stok taşındı: ' + Moved);
                    end else
                        Row.Add('result', 'Stok taşınacak: ' + Moved);
                    Row.Add('baseQuantity', MovedQty);
                    Done += 1;
                end else begin
                    Row.Add('result', Reason);
                    Skipped += 1;
                end;
                Rows.Add(Row);
            until LP.Next() = 0;
        Result.Add('applied', ApplyChanges);
        Result.Add('moved', Done);
        Result.Add('skipped', Skipped);
        Result.Add('rows', Rows);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>
    /// Moves: base quantity per item|variant|lot (what the ad-hoc move needs).
    /// Proof: base quantity per item|variant|lot-if-warehouse-tracked (what the
    /// warehouse balance can prove). '' when the LP can be handled, else a reason.
    /// </summary>
    local procedure CollectNeeds(LP: Record "DOPSWHS LP Header"; var Moves: Dictionary of [Text, Decimal]; var Proof: Dictionary of [Text, Decimal]): Text
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        MoveKey: Text;
        ProofKey: Text;
        LotWhse: Boolean;
        SnWhse: Boolean;
        LineBase: Decimal;
        Existing: Decimal;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Child LP No.", '<>%1', '');
        if not LPLine.IsEmpty() then
            exit('LP içinde alt LP var; elle kontrol edin');
        LPLine.Reset();
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Serial No.", '<>%1', '');
        if not LPLine.IsEmpty() then
            exit('Seri numaralı satır var; elle kontrol edin');
        LPLine.Reset();
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit('LP boş');
        repeat
            if not Item.Get(LPLine."Item No.") then
                exit('Madde bulunamadı: ' + LPLine."Item No.");
            if LPLine."Variant Code" <> '' then
                exit('Varyantlı satır var; elle kontrol edin');
            if not TryLineBase(LPLine, LineBase) then
                exit('Birim dönüşümü bulunamadı: ' + LPLine."Item No.");
            WarehouseTracking(Item, LotWhse, SnWhse);
            if SnWhse then
                exit('Seri izlemeli madde; elle kontrol edin');
            MoveKey := LPLine."Item No." + '|' + LPLine."Variant Code" + '|' + LPLine."Lot No.";
            ProofKey := LPLine."Item No." + '|' + LPLine."Variant Code" + '|';
            if LotWhse then
                ProofKey += LPLine."Lot No.";
            if Moves.Get(MoveKey, Existing) then
                Moves.Set(MoveKey, Existing + LineBase)
            else
                Moves.Add(MoveKey, LineBase);
            if Proof.Get(ProofKey, Existing) then
                Proof.Set(ProofKey, Existing + LineBase)
            else
                Proof.Add(ProofKey, LineBase);
        until LPLine.Next() = 0;
        exit('');
    end;

    /// <summary>Active LP claims minus warehouse balance in one bin for an item|variant|lot key.</summary>
    local procedure OverClaimFor(LocationCode: Code[10]; BinCode: Code[20]; TrackKey: Text): Decimal
    var
        Parts: List of [Text];
        ItemNo: Code[20];
        VariantCode: Code[10];
        LotNo: Code[50];
        UseLot: Boolean;
    begin
        Parts := TrackKey.Split('|');
        ItemNo := CopyStr(Parts.Get(1), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(Parts.Get(2), 1, MaxStrLen(VariantCode));
        LotNo := CopyStr(Parts.Get(3), 1, MaxStrLen(LotNo));
        UseLot := IsLotWhse(ItemNo);
        exit(BinClaims(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', UseLot, false) -
            BinBalance(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', UseLot, false));
    end;

    local procedure IsLotWhse(ItemNo: Code[20]): Boolean
    var
        Item: Record Item;
        LotWhse: Boolean;
        SnWhse: Boolean;
    begin
        if not Item.Get(ItemNo) then
            exit(false);
        WarehouseTracking(Item, LotWhse, SnWhse);
        exit(LotWhse);
    end;

    /// <summary>
    /// Bin of the LP's last position-setting movement (built, moved, item added,
    /// transfer in/out; an LP bin move is written as Transfer Out "BIN-MOVE").
    /// Assignment/release/link rows only repeat the header bin and are ignored,
    /// so a header bin typed on the card is not taken as recorded.
    /// </summary>
    procedure LastRecordedBin(LpNo: Code[20]): Code[20]
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger.SetRange("LP No.", LpNo);
        Ledger.SetFilter(Action, '%1|%2|%3|%4|%5',
            Ledger.Action::Built, Ledger.Action::Moved, Ledger.Action::ItemAdded,
            Ledger.Action::TransferIn, Ledger.Action::TransferOut);
        Ledger.SetFilter("To Bin", '<>%1', '');
        if Ledger.FindLast() then
            exit(Ledger."To Bin");
        exit('');
    end;

    /// <summary>
    /// Read-only CSV: for every item/variant/lot on the selected LPs, all bins of
    /// the location with LP claims and warehouse balance, every active LP line of
    /// that lot, the posted consumption and a hint per over-claimed bin.
    /// </summary>
    procedure BuildReconciliationCsv(var Selected: Record "DOPSWHS LP Header"): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Groups: List of [Text];
        Parts: List of [Text];
        Csv: TextBuilder;
        Bom: Char;
        GroupKey: Text;
    begin
        Bom := 65279;
        Csv.Append(Format(Bom));
        Csv.AppendLine('Satır Türü;Konum;Madde No;Varyant;Lot No;Depo Gözü;LP No;LP Durumu;Atanan Belge;LP Miktarı (Temel);Göz Bakiyesi (Temel);LP Fazlası (Temel);Açıklama');
        LP.CopyFilters(Selected);
        if LP.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetFilter("Item No.", '<>%1', '');
                if LPLine.FindSet() then
                    repeat
                        GroupKey := LP."Location Code" + '|' + LPLine."Item No." + '|' + LPLine."Variant Code" + '|' + LPLine."Lot No.";
                        if not Groups.Contains(GroupKey) then
                            Groups.Add(GroupKey);
                    until LPLine.Next() = 0;
            until LP.Next() = 0;
        foreach GroupKey in Groups do begin
            Parts := GroupKey.Split('|');
            AppendGroup(Csv, CopyStr(Parts.Get(1), 1, 10), CopyStr(Parts.Get(2), 1, 20), CopyStr(Parts.Get(3), 1, 10), CopyStr(Parts.Get(4), 1, 50));
        end;
        exit(Csv.ToText());
    end;

    local procedure AppendGroup(var Csv: TextBuilder; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50])
    var
        Item: Record Item;
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        WarehouseEntry: Record "Warehouse Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        Bins: List of [Code[20]];
        Orders: List of [Code[20]];
        Balances: Dictionary of [Code[20], Decimal];
        Claims: Dictionary of [Code[20], Decimal];
        BinCode: Code[20];
        OrderNo: Code[20];
        LotWhse: Boolean;
        SnWhse: Boolean;
        LineBase: Decimal;
        Balance: Decimal;
        Claim: Decimal;
        Excess: Decimal;
        ConsumedOut: Decimal;
        MovedOut: Decimal;
        OtherOut: Decimal;
        OutOrders: Text;
        LpHint: Text;
        RecordedBin: Code[20];
        ManualByBin: Dictionary of [Code[20], Text];
        ManualText: Text;
        TotalBalance: Decimal;
        TotalClaim: Decimal;
        Consumed: Decimal;
        OrderText: Text;
        Hint: Text;
    begin
        if not Item.Get(ItemNo) then
            exit;
        WarehouseTracking(Item, LotWhse, SnWhse);

        // Every bin that ever held this lot (from warehouse entries, so a bin
        // whose Bin Content row was removed is not missed) or holds its LP.
        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", VariantCode);
        if LotWhse then
            WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.SetLoadFields("Bin Code");
        if WarehouseEntry.FindSet() then
            repeat
                if (WarehouseEntry."Bin Code" <> '') and not Bins.Contains(WarehouseEntry."Bin Code") then
                    Bins.Add(WarehouseEntry."Bin Code");
            until WarehouseEntry.Next() = 0;
        LPLine.SetCurrentKey("Item No.");
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) and not Bins.Contains(LP."Bin Code") then
                        Bins.Add(LP."Bin Code");
            until LPLine.Next() = 0;

        foreach BinCode in Bins do begin
            Balance := BinBalance(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', LotWhse, false);
            Claim := BinClaims(LocationCode, BinCode, ItemNo, VariantCode, LotNo, '', LotWhse, false);
            Balances.Add(BinCode, Balance);
            Claims.Add(BinCode, Claim);
            TotalBalance += Balance;
            TotalClaim += Claim;
        end;

        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Variant Code", VariantCode);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Consumption);
        if ItemLedgerEntry.FindSet() then
            repeat
                Consumed -= ItemLedgerEntry.Quantity;
                if (ItemLedgerEntry."Order No." <> '') and not Orders.Contains(ItemLedgerEntry."Order No.") then
                    Orders.Add(ItemLedgerEntry."Order No.");
            until ItemLedgerEntry.Next() = 0;
        foreach OrderNo in Orders do begin
            if OrderText <> '' then
                OrderText += ' ';
            OrderText += OrderNo;
        end;

        // LPs whose bin differs from their last recorded movement (bin typed on the card).
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) then begin
                        RecordedBin := LastRecordedBin(LP."No.");
                        if (RecordedBin <> '') and (RecordedBin <> LP."Bin Code") then begin
                            if ManualByBin.Get(LP."Bin Code", ManualText) then
                                ManualByBin.Set(LP."Bin Code", ManualText + ' ' + LP."No." + ' (kayıtlı göz ' + RecordedBin + ')')
                            else
                                ManualByBin.Add(LP."Bin Code", LP."No." + ' (kayıtlı göz ' + RecordedBin + ')');
                        end;
                    end;
            until LPLine.Next() = 0;

        foreach BinCode in Bins do begin
            Balance := Balances.Get(BinCode);
            Claim := Claims.Get(BinCode);
            Excess := Claim - NonNegative(Balance);
            if Excess < 0 then
                Excess := 0;
            Hint := '';
            if (Excess > Tolerance()) and ManualByBin.Get(BinCode, ManualText) then
                Hint := 'LP kartından gözü elle değiştirilmiş LP var: ' + ManualText +
                    '. Stok kayıtlı gözde kalmış olabilir; "Seçili LP''lerin Stoğunu LP Gözüne Taşı" ile taşınabilir.'
            else
            if Excess > Tolerance() then begin
                // Evidence from this bin only: what left it after the LPs arrived.
                BinOutflows(LocationCode, BinCode, ItemNo, VariantCode, LotNo, LotWhse,
                    LpArrivalDate(LocationCode, BinCode, ItemNo, VariantCode, LotNo, LotWhse),
                    ConsumedOut, MovedOut, OtherOut, OutOrders);
                if (ConsumedOut >= Excess - Tolerance()) and (MovedOut < Excess - Tolerance()) then
                    Hint := 'Olası açıklama (kesin LP bağlantısı değil): LP geldikten sonra bu gözden ' + Format(ConsumedOut) + ' üretim tüketimi kaydedilmiş (' + OutOrders + '). Fark tüketimden LP''de kalmış olabilir.'
                else
                    if (MovedOut >= Excess - Tolerance()) and (ConsumedOut < Excess - Tolerance()) then
                        Hint := 'Olası açıklama (kesin değil): LP geldikten sonra bu gözden ' + Format(MovedOut) + ' LP''siz taşıma çıkışı var. LP gözü yanlış olabilir; taşıma belgelerini kontrol edin.'
                    else
                        if (ConsumedOut + MovedOut + OtherOut) >= Excess - Tolerance() then
                            Hint := 'Olası açıklama (kesin değil): LP geldikten sonra bu gözden tüketim ' + Format(ConsumedOut) + ', taşıma ' + Format(MovedOut) + ', diğer çıkış ' + Format(OtherOut) + '. Depo hareketlerinden kontrol edin.'
                        else
                            Hint := 'Açıklanamayan fark: LP geldikten sonra bu gözden yeterli çıkış kaydı yok. Fiziksel sayım gerekli.';
                if not LotWhse then
                    Hint += ' Maddede depo lot izlemesi yok: miktarlar madde toplamıdır.';
            end;
            if (Balance <> 0) or (Claim <> 0) then
                AppendRow(Csv, 'GÖZ', LocationCode, ItemNo, VariantCode, LotNo, BinCode, '', '', '', Claim, Balance, Excess, Hint);
        end;

        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) then
                        if TryLineBase(LPLine, LineBase) then begin
                            RecordedBin := LastRecordedBin(LP."No.");
                            LpHint := '';
                            if (RecordedBin <> '') and (RecordedBin <> LP."Bin Code") and
                               (Claims.Get(LP."Bin Code") - NonNegative(Balances.Get(LP."Bin Code")) > Tolerance())
                            then
                                LpHint := 'LP kartından göz değiştirilmiş: kayıtlı son hareket gözü ' + RecordedBin +
                                    '. Stok o gözde kalmış olabilir; "Seçili LP''lerin Stoğunu LP Gözüne Taşı" ile taşınabilir.';
                            AppendRow(Csv, 'LP', LocationCode, ItemNo, VariantCode, LotNo, LP."Bin Code", LP."No.",
                                Format(LP.Status), Format(LP."Assigned Document Type") + ' ' + LP."Assigned Document No.",
                                LineBase, 0, 0, LpHint);
                        end;
            until LPLine.Next() = 0;

        Excess := TotalClaim - NonNegative(TotalBalance);
        if Excess < 0 then
            Excess := 0;
        AppendRow(Csv, 'LOT TOPLAM', LocationCode, ItemNo, VariantCode, LotNo, '', '', '', '', TotalClaim, TotalBalance, Excess,
            'Konumdaki tüm gözlerin toplamı. Kayıtlı üretim tüketimi: ' + Format(Consumed) + ' (' + OrderText + ')');
    end;

    /// <summary>Earliest date on which an active LP of this lot arrived in the bin (0D if unknown).</summary>
    local procedure LpArrivalDate(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; LotWhse: Boolean): Date
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Earliest: Date;
        Arrived: Date;
    begin
        LPLine.SetCurrentKey("Item No.");
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if LotWhse then
            LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) and (LP."Bin Code" = BinCode) then begin
                        Arrived := 0D;
                        Ledger.Reset();
                        Ledger.SetRange("LP No.", LP."No.");
                        Ledger.SetRange("To Bin", BinCode);
                        if Ledger.FindLast() then
                            Arrived := DT2Date(Ledger.DateTime);
                        if Arrived = 0D then
                            exit(0D); // Unknown arrival: use all bin history.
                        if (Earliest = 0D) or (Arrived < Earliest) then
                            Earliest := Arrived;
                    end;
            until LPLine.Next() = 0;
        exit(Earliest);
    end;

    /// <summary>Outflows from one bin since a date, split into production consumption, movements and other.</summary>
    local procedure BinOutflows(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; LotWhse: Boolean; SinceDate: Date; var ConsumedOut: Decimal; var MovedOut: Decimal; var OtherOut: Decimal; var Orders: Text)
    var
        WarehouseEntry: Record "Warehouse Entry";
        OrderList: List of [Code[20]];
        OrderNo: Code[20];
    begin
        ConsumedOut := 0;
        MovedOut := 0;
        OtherOut := 0;
        Orders := '';
        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Bin Code", BinCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", VariantCode);
        if LotWhse then
            WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.SetFilter("Qty. (Base)", '<0');
        if SinceDate <> 0D then
            WarehouseEntry.SetFilter("Registering Date", '%1..', SinceDate);
        if WarehouseEntry.FindSet() then
            repeat
                if (WarehouseEntry."Whse. Document Type" = WarehouseEntry."Whse. Document Type"::Production) or
                   (WarehouseEntry."Reference Document" = WarehouseEntry."Reference Document"::"Prod.")
                then begin
                    ConsumedOut -= WarehouseEntry."Qty. (Base)";
                    OrderNo := WarehouseEntry."Whse. Document No.";
                    if OrderNo = '' then
                        OrderNo := CopyStr(WarehouseEntry."Reference No.", 1, MaxStrLen(OrderNo));
                    if (OrderNo <> '') and not OrderList.Contains(OrderNo) then
                        OrderList.Add(OrderNo);
                end else
                    if WarehouseEntry."Entry Type" = WarehouseEntry."Entry Type"::Movement then
                        MovedOut -= WarehouseEntry."Qty. (Base)"
                    else
                        OtherOut -= WarehouseEntry."Qty. (Base)";
            until WarehouseEntry.Next() = 0;
        foreach OrderNo in OrderList do begin
            if Orders <> '' then
                Orders += ' ';
            Orders += OrderNo;
        end;
    end;

    local procedure AppendRow(var Csv: TextBuilder; RowType: Text; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; BinCode: Code[20]; LpNo: Code[20]; LpStatus: Text; AssignedDoc: Text; LpQty: Decimal; BinQty: Decimal; Excess: Decimal; Hint: Text)
    begin
        Csv.AppendLine(
            RowType + ';' + LocationCode + ';' + ItemNo + ';' + VariantCode + ';' + LotNo + ';' + BinCode + ';' +
            LpNo + ';' + LpStatus + ';' + DelChr(AssignedDoc, '<>', ' ') + ';' + Format(LpQty) + ';' + Format(BinQty) + ';' +
            Format(Excess) + ';' + Hint.Replace(';', ','));
    end;

    /// <summary>Active LP base quantity in one bin; lot/serial filters only when requested.</summary>
    procedure BinClaims(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; UseLot: Boolean; UseSerial: Boolean): Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LineBase: Decimal;
        Total: Decimal;
    begin
        LPLine.SetCurrentKey("Item No.");
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if UseLot then
            LPLine.SetRange("Lot No.", LotNo);
        if UseSerial then
            LPLine.SetRange("Serial No.", SerialNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if IsActive(LP) and (LP."Location Code" = LocationCode) and (LP."Bin Code" = BinCode) then
                        if TryLineBase(LPLine, LineBase) then
                            Total += LineBase;
            until LPLine.Next() = 0;
        exit(Round(Total, 0.00001));
    end;

    /// <summary>Registered warehouse balance of one bin; lot/serial filters only when requested.</summary>
    procedure BinBalance(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; UseLot: Boolean; UseSerial: Boolean): Decimal
    var
        WarehouseEntry: Record "Warehouse Entry";
    begin
        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Bin Code", BinCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", VariantCode);
        if UseLot then
            WarehouseEntry.SetRange("Lot No.", LotNo);
        if UseSerial then
            WarehouseEntry.SetRange("Serial No.", SerialNo);
        WarehouseEntry.CalcSums("Qty. (Base)");
        exit(WarehouseEntry."Qty. (Base)");
    end;

    /// <summary>
    /// True only for bins listed in Setup "Prod. LP Sync Bin Filter" (e.g. A.URETIM)
    /// of the location in Setup "Prod. LP Sync Location" (e.g. MERKEZDEPO).
    /// Either empty, unknown setup or an invalid filter: false, nothing is changed.
    /// </summary>
    procedure IsSyncBin(LocationCode: Code[10]; BinCode: Code[20]): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if BinCode = '' then
            exit(false);
        if not Setup.Get() then
            exit(false);
        if DelChr(Setup."Prod. LP Sync Bin Filter", '=', ' ') = '' then
            exit(false);
        // The bin code alone is not unique: the location must match as well.
        if (Setup."Prod. LP Sync Location" = '') or (Setup."Prod. LP Sync Location" <> LocationCode) then
            exit(false);
        exit(BinMatchesFilter(LocationCode, BinCode, Setup."Prod. LP Sync Bin Filter"));
    end;

    local procedure BinMatchesFilter(LocationCode: Code[10]; BinCode: Code[20]; BinFilter: Text): Boolean
    var
        TempBin: Record Bin temporary;
    begin
        TempBin."Location Code" := LocationCode;
        TempBin.Code := BinCode;
        TempBin.Insert();
        if not TryApplyBinFilter(TempBin, BinFilter) then
            exit(false);
        exit(not TempBin.IsEmpty());
    end;

    [TryFunction]
    local procedure TryApplyBinFilter(var TempBin: Record Bin temporary; BinFilter: Text)
    begin
        TempBin.SetFilter(Code, BinFilter);
    end;

    local procedure IsActive(LP: Record "DOPSWHS LP Header"): Boolean
    begin
        exit((LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) and (LP."Pending Receipt No." = ''));
    end;

    local procedure WarehouseTracking(Item: Record Item; var LotWhse: Boolean; var SnWhse: Boolean)
    var
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        LotWhse := false;
        SnWhse := false;
        if Item."Item Tracking Code" = '' then
            exit;
        if not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit;
        LotWhse := ItemTrackingCode."Lot Warehouse Tracking";
        SnWhse := ItemTrackingCode."SN Warehouse Tracking";
    end;

    [TryFunction]
    local procedure TryQtyPer(LPLine: Record "DOPSWHS LP Line"; var QtyPer: Decimal)
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        Item.Get(LPLine."Item No.");
        QtyPer := 1;
        if (LPLine."Unit of Measure" <> '') and (LPLine."Unit of Measure" <> Item."Base Unit of Measure") then begin
            ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure");
            QtyPer := ItemUoM."Qty. per Unit of Measure";
            if QtyPer <= 0 then
                Error('Geçersiz birim dönüşümü.');
        end;
    end;

    [TryFunction]
    local procedure TryLineBase(LPLine: Record "DOPSWHS LP Line"; var LineBase: Decimal)
    var
        QtyPer: Decimal;
    begin
        if not TryQtyPer(LPLine, QtyPer) then
            Error('Geçersiz birim dönüşümü.');
        LineBase := Round(LPLine.Quantity * QtyPer, 0.00001);
    end;

    local procedure NonNegative(Value: Decimal): Decimal
    begin
        if Value < 0 then
            exit(0);
        exit(Value);
    end;

    local procedure Tolerance(): Decimal
    begin
        exit(0.00001);
    end;
}
