/// <summary>
/// BADE (22 Eki 2026, 1.14.1.150): LP ile göz stoku BC'den yapılan işlemlerde
/// ayrışıyordu (Sand2809 LP probe: NEGADJ, WPHYS, PRETWS, TRANSFER, NEGOUT =
/// hayalet LP; WRECL, MOVWS, PUTAWAY = LP eski gözde).
///
/// Kural 1 - "raftan çıkan her stok LP'yi düşürsün": bir kayıt bir gözün
/// stokunu azalttığında, kayıttan SONRA gözdeki aktif LP miktarı göz stokunu
/// aşıyorsa aşan kısım (en çok kaydın azalttığı miktar) LP'lerden düşülür:
/// önce kayıtta adı geçen LP, sonra bu belgeye atanmış LP'ler, sonra atanmamış
/// LP'ler (FEFO, LP No.), en son başka belgeye atanmış LP'ler. Boşalan LP Used
/// olur; her düşüm LP hareket defterine yazılır. Kural "yalnız LP toplamı göz
/// stokunu aştığında" çalıştığı için kendiliğinden tekrarsızdır: LP'yi zaten
/// düşen/taşıyan yollar (satış sevkiyatı mutabakatı, sayım, LP'li sarfiyat,
/// üretim toplaması) çalıştıktan sonra fazla kalmaz.
///
/// Kural 2 - "BC'den kaydedilen hareket LP'yi taşısın": aynı kayıt stoku başka
/// bir göze taşıdıysa (Movement girişleri: rafa kaldırma, hareket, toplama,
/// ambar yeniden sınıflandırma), içeriğinin tamamı taşınan LP'nin başlığı yeni
/// göze taşınır. Kısmi taşımada kaynak LP düşülür; taşınan kısım hedefte LP'siz
/// stok olur.
///
/// Zamanlama: günlük/defter kayıtlarında her ambar günlüğü satırının sonunda
/// (Whse. Jnl.-Register Line OnAfterCode), ambar aktivitesi kaydında commit
/// öncesinde (OnCodeOnBeforeCommit), satış kayıtlarında satış LP mutabakatından
/// sonra (DOPSWHS LP Propagation çağırır). Terminal akışları kendi LP
/// işlemlerini kayıttan sonra yaptığı için EnterTerminalPosting ile bu kod
/// devre dışı bırakılır. Hiçbir durumda Error vermez; kayıt LP yüzünden durmaz.
/// Tek istisna: terminalde hazırlanmış LP'si olan ambar mal kabulünün BC'den
/// kaydı (CheckReceiptPostingAllowed).
/// </summary>
codeunit 72456 "DOPSWHS LP Bin Sync"
{
    Access = Public;
    SingleInstance = true;
    Permissions =
        tabledata Item = R,
        tabledata "Item Unit of Measure" = R,
        tabledata "Item Tracking Code" = R,
        tabledata Location = R,
        tabledata "Warehouse Entry" = R,
        tabledata "Warehouse Activity Line" = R,
        tabledata "Warehouse Receipt Header" = R,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RMD,
        tabledata "DOPSWHS LP Movement Ledger" = RI;

    var
        TempLineEntry: Record "Warehouse Entry" temporary;
        TempActivityEntry: Record "Warehouse Entry" temporary;
        TempSalesEntry: Record "Warehouse Entry" temporary;
        AdjustmentBins: Dictionary of [Code[10], Code[20]];
        TerminalDepth: Integer;
        TerminalSince: DateTime;
        DraftLpReceiptErr: Label 'Bu mal kabulde terminalde hazırlanmış LP''ler var; kaydı terminalden yapın veya LP''leri iptal edin. (Mal kabul %1, %2 LP)', Comment = '%1 = warehouse receipt no., %2 = number of draft LPs';

    // =========================================================================
    // Terminal akışları
    // =========================================================================

    /// <summary>
    /// Terminal akışı BC kaydını çağırmadan önce çağırır. Terminal LP'yi kayıttan
    /// sonra kendisi taşır/düşer; bu codeunit o kayıtta hiçbir şey yapmaz ve
    /// mal kabul engeli uygulanmaz. Hata ile kesilen bir kaydın bayrağı 10
    /// dakika sonra kendiliğinden düşer.
    /// </summary>
    procedure EnterTerminalPosting()
    begin
        if not IsTerminalPosting() then
            TerminalDepth := 0;
        TerminalDepth += 1;
        TerminalSince := CurrentDateTime();
    end;

    procedure ExitTerminalPosting()
    begin
        if TerminalDepth > 0 then
            TerminalDepth -= 1;
    end;

    procedure IsTerminalPosting(): Boolean
    begin
        if TerminalDepth <= 0 then
            exit(false);
        if (TerminalSince = 0DT) or (CurrentDateTime() - TerminalSince > StaleAfterMs()) then begin
            TerminalDepth := 0;
            exit(false);
        end;
        exit(true);
    end;

    // =========================================================================
    // Toplama
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Jnl.-Register Line", 'OnAfterInsertWhseEntry', '', false, false)]
    local procedure CollectOnAfterInsertWhseEntry(var WarehouseEntry: Record "Warehouse Entry"; var WarehouseJournalLine: Record "Warehouse Journal Line")
    begin
        if WarehouseEntry.IsTemporary() then
            exit;
        if IsTerminalPosting() then
            exit;
        if (WarehouseEntry."Bin Code" = '') or (WarehouseEntry."Item No." = '') or (WarehouseEntry."Qty. (Base)" = 0) then
            exit;
        // Lot/seri değiştiren yeniden sınıflandırma: LP satırının lotunu madde
        // defteri tarafı (DOPSWHS LP Reclass Relink) günceller.
        if TrackingChanges(WarehouseJournalLine) then
            exit;
        if IsActivityEntry(WarehouseEntry) then begin
            // Üretim toplamasının LP düşümü DOPSWHS Pick Mgmt'tedir.
            if WarehouseEntry."Source Type" = Database::"Prod. Order Component" then
                exit;
            AddToBuffer(TempActivityEntry, WarehouseEntry);
            exit;
        end;
        // Satış: önce satış LP mutabakatı (LP Propagation) çalışır, sonra burası.
        if (WarehouseEntry."Source Type" = Database::"Sales Line") and (WarehouseEntry."Qty. (Base)" < 0) then begin
            AddToBuffer(TempSalesEntry, WarehouseEntry);
            exit;
        end;
        AddToBuffer(TempLineEntry, WarehouseEntry);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Jnl.-Register Line", 'OnBeforeCode', '', false, false)]
    local procedure ResetOnBeforeRegisterLine(var WarehouseJournalLine: Record "Warehouse Journal Line")
    begin
        // Hata ile kesilmiş önceki satırın artığı bu satıra karışmasın.
        TempLineEntry.Reset();
        TempLineEntry.DeleteAll();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Jnl.-Register Line", 'OnAfterCode', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    local procedure ProcessOnAfterRegisterLine(var WarehouseJournalLine: Record "Warehouse Journal Line")
    begin
        TempLineEntry.Reset();
        if TempLineEntry.IsEmpty() then
            exit;
        if not IsTerminalPosting() then
            ProcessBuffer(TempLineEntry, LineReference(TempLineEntry), '');
        TempLineEntry.Reset();
        TempLineEntry.DeleteAll();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Activity-Register", 'OnBeforeCode', '', false, false)]
    local procedure ResetOnBeforeActivityRegister(var WarehouseActivityLine: Record "Warehouse Activity Line")
    begin
        // Geri alınmış önceki bir kaydın artığı bu kayda karışmasın.
        TempActivityEntry.Reset();
        TempActivityEntry.DeleteAll();
    end;

    /// <summary>
    /// Ambar aktivitesi (rafa kaldırma, hareket, toplama) BC'den kaydedildiğinde
    /// LP'yi taşır / düşer. Commit öncesinde çalışır; LP değişiklikleri kayıtla
    /// aynı transaction'dadır.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Activity-Register", 'OnCodeOnBeforeCommit', '', false, false)]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    local procedure ProcessOnActivityBeforeCommit(RegisteredWhseActivHeader: Record "Registered Whse. Activity Hdr.")
    begin
        TempActivityEntry.Reset();
        if TempActivityEntry.IsEmpty() then
            exit;
        if (RegisteredWhseActivHeader."No." <> '') and (not IsTerminalPosting()) then begin
            TempActivityEntry.SetRange("Reference No.", RegisteredWhseActivHeader."No.");
            if not TempActivityEntry.IsEmpty() then
                ProcessBuffer(
                    TempActivityEntry, ActivityReference(RegisteredWhseActivHeader."No."),
                    RegisteredWhseActivHeader."Whse. Activity No.");
        end;
        TempActivityEntry.Reset();
        TempActivityEntry.DeleteAll();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", 'OnBeforePostSalesDoc', '', false, false)]
    local procedure ResetSalesOnBeforePostSalesDoc(var SalesHeader: Record "Sales Header")
    begin
        DiscardDeferredSales();
    end;

    /// <summary>
    /// Satış kaydının göz azaltmaları, satış LP mutabakatından sonra burada
    /// işlenir (DOPSWHS LP Propagation, Sales-Post commit öncesi).
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    procedure FlushDeferredSales()
    begin
        TempSalesEntry.Reset();
        if TempSalesEntry.IsEmpty() then
            exit;
        if not IsTerminalPosting() then
            ProcessBuffer(TempSalesEntry, LineReference(TempSalesEntry), '');
        DiscardDeferredSales();
    end;

    procedure DiscardDeferredSales()
    begin
        TempSalesEntry.Reset();
        TempSalesEntry.DeleteAll();
    end;

    // =========================================================================
    // Satış mutabakatı için: BC'den kaydedilen toplamada taşınan LP'ler
    // =========================================================================

    procedure ActivityReference(RegisteredActivityNo: Code[20]): Code[40]
    begin
        exit(CopyStr('LPSYNC#' + RegisteredActivityNo, 1, 40));
    end;

    /// <summary>True: bu kayıtlı aktivitenin LP etkisi kayıt anında işlendi.</summary>
    procedure WasActivitySynced(RegisteredActivityNo: Code[20]): Boolean
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        if RegisteredActivityNo = '' then
            exit(false);
        Ledger.SetCurrentKey("Related Document", Action);
        Ledger.SetRange("Related Document", ActivityReference(RegisteredActivityNo));
        exit(not Ledger.IsEmpty());
    end;

    /// <summary>Kayıtlı aktivitede FromBinCode gözünden bütün olarak taşınan LP'ler (kayıt sırasıyla).</summary>
    procedure GetActivityMovedLps(RegisteredActivityNo: Code[20]; FromBinCode: Code[20]; var LpNos: List of [Code[20]])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Clear(LpNos);
        if RegisteredActivityNo = '' then
            exit;
        Ledger.SetCurrentKey("Related Document", Action);
        Ledger.SetRange("Related Document", ActivityReference(RegisteredActivityNo));
        Ledger.SetRange(Action, Ledger.Action::Moved);
        if FromBinCode <> '' then
            Ledger.SetRange("From Bin", FromBinCode);
        if Ledger.FindSet() then
            repeat
                if not LpNos.Contains(Ledger."LP No.") then
                    LpNos.Add(Ledger."LP No.");
            until Ledger.Next() = 0;
    end;

    // =========================================================================
    // Çekirdek
    // =========================================================================

    /// <summary>
    /// Test edilebilir çekirdek. TempEntry: bir kaydın ambar girişleri (kopyalar;
    /// gerçek girişler zaten yazılmış olmalı). ActivityNo: kaydedilen aktivitenin
    /// belge no'su (atama bırakma için), yoksa boş. Hiç Error vermez.
    /// Döndürür: değişen LP sayısı (taşınan + düşülen).
    /// </summary>
    procedure ProcessBuffer(var TempEntry: Record "Warehouse Entry" temporary; Reference: Code[40]; ActivityNo: Code[20]) Changed: Integer
    var
        Net: Dictionary of [Text, Decimal];
        MoveIn: Dictionary of [Text, Decimal];
        Named: Dictionary of [Text, Text];
        ExcessLeft: Dictionary of [Text, Decimal];
        Capacity: Dictionary of [Text, Decimal];
        BinKeys: List of [Text];
        Reduced: List of [Text];
        Candidates: List of [Code[20]];
        BinKey: Text;
        NamedText: Text;
        LpNo: Code[20];
        Qty: Decimal;
        Excess: Decimal;
        Existing: Decimal;
    begin
        if not TempEntry.FindSet() then
            exit(0);
        repeat
            BinKey := MakeBinKey(TempEntry."Location Code", TempEntry."Bin Code", TempEntry."Item No.", TempEntry."Variant Code", TempEntry."Lot No.", TempEntry."Serial No.");
            if not BinKeys.Contains(BinKey) then
                BinKeys.Add(BinKey);
            AddQty(Net, BinKey, TempEntry."Qty. (Base)");
            if (TempEntry."Entry Type" = TempEntry."Entry Type"::Movement) and (TempEntry."Qty. (Base)" > 0) then
                AddQty(MoveIn, BinKey, TempEntry."Qty. (Base)");
            if (TempEntry."Qty. (Base)" < 0) and (TempEntry."DOPSWHS LP No." <> '') then begin
                if not Named.Get(BinKey, NamedText) then
                    NamedText := '';
                if StrPos(',' + NamedText + ',', ',' + TempEntry."DOPSWHS LP No." + ',') = 0 then begin
                    if NamedText <> '' then
                        NamedText += ',';
                    NamedText += TempEntry."DOPSWHS LP No.";
                end;
                Named.Set(BinKey, NamedText);
            end;
        until TempEntry.Next() = 0;

        foreach BinKey in BinKeys do begin
            Net.Get(BinKey, Qty);
            if not IsAdjustmentBin(KeyPart(BinKey, 1), KeyPart(BinKey, 2)) then begin
                if Qty < -Tolerance() then begin
                    Excess := BinClaims(BinKey) - BinBalance(BinKey);
                    if Excess > -Qty then
                        Excess := -Qty;
                    if Excess > Tolerance() then begin
                        ExcessLeft.Set(BinKey, Excess);
                        Reduced.Add(BinKey);
                    end;
                end;
                if Qty > Tolerance() then
                    if MoveIn.Get(BinKey, Existing) then
                        if Existing > Tolerance() then begin
                            if Existing > Qty then
                                Existing := Qty;
                            Capacity.Set(BinKey, Existing);
                        end;
            end;
        end;
        if Reduced.Count() = 0 then
            exit(0);

        // 1) Taşıma: içeriğinin tamamı aynı hedef göze giden LP başlığı taşınır.
        if Capacity.Count() > 0 then begin
            CollectCandidates(Reduced, Named, ActivityNo, Candidates);
            foreach LpNo in Candidates do
                if TryMoveWholeLp(LpNo, ExcessLeft, Capacity, Reference, ActivityNo) then
                    Changed += 1;
        end;

        // 2) Düşüm: kalan fazla LP'lerden düşülür.
        foreach BinKey in Reduced do
            if ExcessLeft.Get(BinKey, Excess) then
                if Excess > Tolerance() then begin
                    Clear(Candidates);
                    CollectCandidatesForKey(BinKey, Named, ActivityNo, Candidates);
                    foreach LpNo in Candidates do
                        if Excess > Tolerance() then begin
                            Qty := DebitLp(LpNo, BinKey, Excess, '', Reference);
                            if Qty > 0 then begin
                                Excess -= Qty;
                                Changed += 1;
                            end;
                        end;
                    ExcessLeft.Set(BinKey, Excess);
                end;
    end;

    local procedure TryMoveWholeLp(LpNo: Code[20]; var ExcessLeft: Dictionary of [Text, Decimal]; var Capacity: Dictionary of [Text, Decimal]; Reference: Code[40]; ActivityNo: Code[20]): Boolean
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Need: Dictionary of [Text, Decimal];
        NeedKeys: List of [Text];
        DestBins: List of [Code[20]];
        NeedKey: Text;
        DestKey: Text;
        SourceBin: Code[20];
        DestBin: Code[20];
        SingleItemNo: Code[20];
        SingleLot: Code[50];
        LineBase: Decimal;
        Total: Decimal;
        Available: Decimal;
        Fits: Boolean;
        MixedItems: Boolean;
    begin
        if not LP.Get(LpNo) then
            exit(false);
        if not IsActive(LP) then
            exit(false);
        SourceBin := LP."Bin Code";
        LPLine.SetRange("LP No.", LpNo);
        if not LPLine.FindSet() then
            exit(false);
        repeat
            if LPLine."Child LP No." <> '' then
                exit(false);
            if LPLine.Quantity > 0 then begin
                if LPLine."Item No." = '' then
                    exit(false);
                if not LineBaseQty(LPLine, LineBase) then
                    exit(false);
                NeedKey := MakeBinKey(LP."Location Code", SourceBin, LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.", LPLine."Serial No.");
                AddQty(Need, NeedKey, LineBase);
                if not NeedKeys.Contains(NeedKey) then
                    NeedKeys.Add(NeedKey);
                Total += LineBase;
                if SingleItemNo = '' then begin
                    SingleItemNo := LPLine."Item No.";
                    SingleLot := LPLine."Lot No.";
                end else
                    if (SingleItemNo <> LPLine."Item No.") or (SingleLot <> LPLine."Lot No.") then
                        MixedItems := true;
            end;
        until LPLine.Next() = 0;
        if Total <= Tolerance() then
            exit(false);
        // Her içerik anahtarı bu kayıtta bu gözden en az LP miktarı kadar çıkmış olmalı.
        foreach NeedKey in NeedKeys do begin
            if not ExcessLeft.Get(NeedKey, Available) then
                exit(false);
            if Available + Tolerance() < Need.Get(NeedKey) then
                exit(false);
        end;
        // Ortak hedef göz: ilk anahtarın hedeflerinden, tüm anahtarlara yer olan ilki.
        NeedKeys.Get(1, NeedKey);
        CollectDestinationBins(NeedKey, Capacity, DestBins);
        foreach DestBin in DestBins do
            if not Fits then begin
                Fits := true;
                foreach NeedKey in NeedKeys do begin
                    DestKey := ReplaceBin(NeedKey, DestBin);
                    if not Capacity.Get(DestKey, Available) then
                        Fits := false
                    else
                        if Available + Tolerance() < Need.Get(NeedKey) then
                            Fits := false;
                end;
                if Fits then begin
                    foreach NeedKey in NeedKeys do begin
                        ExcessLeft.Set(NeedKey, ExcessLeft.Get(NeedKey) - Need.Get(NeedKey));
                        DestKey := ReplaceBin(NeedKey, DestBin);
                        Capacity.Set(DestKey, Capacity.Get(DestKey) - Need.Get(NeedKey));
                    end;
                    LP.Validate("Bin Code", DestBin);
                    LP.Modify(true);
                    if MixedItems then begin
                        SingleItemNo := '';
                        SingleLot := '';
                    end;
                    LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::Moved, SourceBin, DestBin, Total, SingleItemNo, SingleLot, Reference);
                    ReleaseFinishedAssignment(LP, ActivityNo);
                    exit(true);
                end;
            end;
        exit(false);
    end;

    /// <summary>LP bu aktiviteye (rafa kaldırma/hareket) atanmışsa ve açık satırı kalmadıysa atamayı bırakır.</summary>
    local procedure ReleaseFinishedAssignment(var LP: Record "DOPSWHS LP Header"; ActivityNo: Code[20])
    var
        OpenLine: Record "Warehouse Activity Line";
    begin
        if (ActivityNo = '') or (LP.Status <> LP.Status::Assigned) or (LP."Assigned Document No." <> ActivityNo) then
            exit;
        if not (LP."Assigned Document Type" in [LP."Assigned Document Type"::WhsePutaway, LP."Assigned Document Type"::WhseMovement]) then
            exit;
        OpenLine.SetRange("No.", ActivityNo);
        OpenLine.SetRange("LP No.", LP."No.");
        OpenLine.SetFilter("Qty. Outstanding", '>0');
        if not OpenLine.IsEmpty() then
            exit;
        LP.Status := LP.Status::Built;
        Clear(LP."Assigned Document Type");
        LP."Assigned Document No." := '';
        LP.Modify(true);
    end;

    local procedure DebitLp(LpNo: Code[20]; BinKey: Text; MaxBase: Decimal; ToBinCode: Code[20]; Reference: Code[40]) Removed: Decimal
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
        if not IsActive(LP) then
            exit(0);
        FilterMatchingLines(LPLine, LpNo, BinKey);
        if LPLine.FindSet() then
            repeat
                if (MaxBase - Removed > Tolerance()) and LineQtyPer(LPLine, QtyPer) then begin
                    LineBase := Round(LPLine.Quantity * QtyPer, 0.00001);
                    TakeBase := MaxBase - Removed;
                    if TakeBase > LineBase then
                        TakeBase := LineBase;
                    TakeInLineUoM := Round(TakeBase / QtyPer, 0.00001);
                    if TakeInLineUoM >= LPLine.Quantity - 0.00001 then begin
                        TakeInLineUoM := LPLine.Quantity;
                        TakeBase := LineBase;
                    end;
                    if TakeInLineUoM > 0 then begin
                        TargetLine.Get(LPLine."LP No.", LPLine."Line No.");
                        if TakeInLineUoM >= TargetLine.Quantity then
                            TargetLine.Delete(true)
                        else begin
                            TargetLine.Validate(Quantity, Round(TargetLine.Quantity - TakeInLineUoM, 0.00001));
                            TargetLine.Modify(true);
                        end;
                        LPMgt.WriteToLedger(
                            LP, Enum::"DOPSWHS LP Action"::ItemRemoved, LP."Bin Code", ToBinCode, TakeBase,
                            LPLine."Item No.", CopyStr(LPLine."Lot No." + LPLine."Serial No.", 1, 50), Reference);
                        Removed += TakeBase;
                    end;
                end;
            until LPLine.Next() = 0;
        if Removed > 0 then begin
            LP.Get(LpNo);
            LPMgt.MarkUsedIfEmptied(LP);
        end;
    end;

    /// <summary>
    /// BADE (23 Eki 2026, 1.14.1.152): LP'nin bu ürün/varyant/lot/seri anahtarındaki
    /// içeriği (temel birim). Lot/seri yalnız maddenin ambar lot/seri izlemesi varsa
    /// anahtara girer (MakeBinKey ile aynı kural).
    /// </summary>
    procedure LpContentBase(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]) Total: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LineBase: Decimal;
    begin
        if not LP.Get(LpNo) then
            exit(0);
        FilterMatchingLines(LPLine, LpNo, MakeBinKey(LP."Location Code", LP."Bin Code", ItemNo, VariantCode, LotNo, SerialNo));
        if LPLine.FindSet() then
            repeat
                if LineBaseQty(LPLine, LineBase) then
                    Total += LineBase;
            until LPLine.Next() = 0;
        Total := Round(Total, 0.00001);
    end;

    /// <summary>
    /// BADE (23 Eki 2026, 1.14.1.152): kısmi yerleştirme. LP'den çıkıp başka göze
    /// konan miktar kadar (en çok MaxBase, temel birim) eşleşen LP satırları düşülür;
    /// LP başlığı yerinde kalır, taşınan kısım hedef gözde LP'siz stok olur (Kural 2
    /// ile aynı sonuç). Defterde ItemRemoved, Kimden = LP gözü, Kime = ToBinCode.
    /// Boşalan LP Used olur. Hiç Error vermez; döndürür: düşülen temel miktar.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    procedure DebitLpContent(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; MaxBase: Decimal; ToBinCode: Code[20]; Reference: Code[40]): Decimal
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if MaxBase <= Tolerance() then
            exit(0);
        if not LP.Get(LpNo) then
            exit(0);
        exit(DebitLp(LpNo, MakeBinKey(LP."Location Code", LP."Bin Code", ItemNo, VariantCode, LotNo, SerialNo), MaxBase, ToBinCode, Reference));
    end;

    // =========================================================================
    // Aday LP'ler ve sıralama
    // =========================================================================

    local procedure CollectCandidates(Reduced: List of [Text]; var Named: Dictionary of [Text, Text]; ActivityNo: Code[20]; var Candidates: List of [Code[20]])
    var
        Sorted: List of [Text];
        BinKey: Text;
        SortEntry: Text;
        LpNo: Code[20];
    begin
        foreach BinKey in Reduced do
            AddSortedCandidates(BinKey, Named, ActivityNo, Sorted);
        foreach SortEntry in Sorted do begin
            LpNo := CopyStr(KeyPart(SortEntry, 2), 1, MaxStrLen(LpNo));
            if not Candidates.Contains(LpNo) then
                Candidates.Add(LpNo);
        end;
    end;

    local procedure CollectCandidatesForKey(BinKey: Text; var Named: Dictionary of [Text, Text]; ActivityNo: Code[20]; var Candidates: List of [Code[20]])
    var
        Reduced: List of [Text];
    begin
        Reduced.Add(BinKey);
        CollectCandidates(Reduced, Named, ActivityNo, Candidates);
    end;

    /// <summary>
    /// Sıralama anahtarı: öncelik (0 kayıtta adı geçen, 1 bu aktiviteye atanmış,
    /// 2 atanmamış, 3 başka belgeye atanmış) + en erken SKT (FEFO) + LP No.
    /// </summary>
    local procedure AddSortedCandidates(BinKey: Text; var Named: Dictionary of [Text, Text]; ActivityNo: Code[20]; var Sorted: List of [Text])
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        NamedText: Text;
        SortEntry: Text;
        Priority: Integer;
        Earliest: Date;
        HasLine: Boolean;
        Index: Integer;
        Inserted: Boolean;
    begin
        if not Named.Get(BinKey, NamedText) then
            NamedText := '';
        LP.SetCurrentKey("Location Code", "Bin Code", Status);
        LP.SetRange("Location Code", KeyPart(BinKey, 1));
        LP.SetRange("Bin Code", KeyPart(BinKey, 2));
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetRange("Pending Receipt No.", '');
        if LP.FindSet() then
            repeat
                FilterMatchingLines(LPLine, LP."No.", BinKey);
                HasLine := false;
                Earliest := 0D;
                if LPLine.FindSet() then
                    repeat
                        HasLine := true;
                        if LPLine."Expiration Date" <> 0D then
                            if (Earliest = 0D) or (LPLine."Expiration Date" < Earliest) then
                                Earliest := LPLine."Expiration Date";
                    until LPLine.Next() = 0;
                if HasLine then begin
                    if StrPos(',' + NamedText + ',', ',' + LP."No." + ',') > 0 then
                        Priority := 0
                    else
                        if LP.Status <> LP.Status::Assigned then
                            Priority := 2
                        else
                            if (ActivityNo <> '') and (LP."Assigned Document No." = ActivityNo) then
                                Priority := 1
                            else
                                Priority := 3;
                    SortEntry := Format(Priority) + DateSortKey(Earliest) + LP."No." + '|' + LP."No.";
                    Inserted := false;
                    for Index := 1 to Sorted.Count() do
                        if not Inserted then
                            if SortEntry < Sorted.Get(Index) then begin
                                Sorted.Insert(Index, SortEntry);
                                Inserted := true;
                            end;
                    if not Inserted then
                        Sorted.Add(SortEntry);
                end;
            until LP.Next() = 0;
    end;

    local procedure DateSortKey(Value: Date): Text
    begin
        if Value = 0D then
            exit('99991231');
        exit(Format(Value, 0, '<Year4><Month,2><Day,2>'));
    end;

    local procedure CollectDestinationBins(SourceKey: Text; var Capacity: Dictionary of [Text, Decimal]; var DestBins: List of [Code[20]])
    var
        CapKey: Text;
        Available: Decimal;
        BinCode: Code[20];
    begin
        foreach CapKey in Capacity.Keys() do
            if SameTracking(CapKey, SourceKey) then begin
                Capacity.Get(CapKey, Available);
                BinCode := CopyStr(KeyPart(CapKey, 2), 1, MaxStrLen(BinCode));
                if (Available > Tolerance()) and (BinCode <> KeyPart(SourceKey, 2)) and (not DestBins.Contains(BinCode)) then
                    DestBins.Add(BinCode);
            end;
    end;

    // =========================================================================
    // Miktarlar
    // =========================================================================

    /// <summary>Gözdeki aktif LP'lerin (mal kabul bekleyenler hariç) bu anahtardaki temel miktarı.</summary>
    /// <summary>
    /// BADE (23 Eki 2026): terminalden kaydedilen ambar sevkiyatında senkron kapalıdır
    /// (EnterTerminalPosting); satış LP mutabakatı yalnız satış satırlarını düşer.
    /// Satın alma iadesi / transfer çıkışı gibi satış dışı sevklerde sevk gözünde
    /// LP dolu kalıyordu. Kayıt bittikten sonra sevkin ambar girişleri üzerinden
    /// yalnız göz stoğunu aşan LP fazlası düşülür; satışta fazla kalmadığı için
    /// hiçbir şey değişmez (çift düşüm olmaz).
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    procedure SyncPostedWhseShipment(PostedShipmentNo: Code[20]): Integer
    var
        WarehouseEntry: Record "Warehouse Entry";
        TempEntry: Record "Warehouse Entry" temporary;
    begin
        if PostedShipmentNo = '' then
            exit(0);
        WarehouseEntry.SetRange("Whse. Document Type", WarehouseEntry."Whse. Document Type"::Shipment);
        WarehouseEntry.SetRange("Whse. Document No.", PostedShipmentNo);
        if WarehouseEntry.FindSet() then
            repeat
                if (WarehouseEntry."Bin Code" <> '') and (WarehouseEntry."Item No." <> '') and (WarehouseEntry."Qty. (Base)" <> 0) then
                    AddToBuffer(TempEntry, WarehouseEntry);
            until WarehouseEntry.Next() = 0;
        TempEntry.Reset();
        if TempEntry.IsEmpty() then
            exit(0);
        exit(ProcessBuffer(TempEntry, LineReference(TempEntry), ''));
    end;

    /// <summary>
    /// Onarım: LP'nin gözünde aktif LP toplamı göz stoğunu aşıyorsa fazlası düşülür
    /// (önce bu LP). Apply = false yalnız düşülecek toplam fazlayı döndürür.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Header", 'RM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Line", 'RMD')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS LP Movement Ledger", 'RI')]
    procedure RepairLpExcess(LpNo: Code[20]; Apply: Boolean): Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        TempEntry: Record "Warehouse Entry" temporary;
        Keys: List of [Text];
        BinKey: Text;
        Excess: Decimal;
        TotalExcess: Decimal;
        NextNo: Integer;
    begin
        if not LP.Get(LpNo) then
            exit(0);
        if not IsActive(LP) or (LP."Bin Code" = '') or (LP."Pending Receipt No." <> '') then
            exit(0);
        if IsAdjustmentBin(LP."Location Code", LP."Bin Code") then
            exit(0);
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then
            repeat
                BinKey := MakeBinKey(LP."Location Code", LP."Bin Code", LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.", LPLine."Serial No.");
                if not Keys.Contains(BinKey) then begin
                    Keys.Add(BinKey);
                    Excess := Round(BinClaims(BinKey) - BinBalance(BinKey), 0.00001);
                    if Excess > Tolerance() then begin
                        TotalExcess += Excess;
                        NextNo += 1;
                        TempEntry.Init();
                        TempEntry."Entry No." := NextNo;
                        TempEntry."Location Code" := LP."Location Code";
                        TempEntry."Bin Code" := LP."Bin Code";
                        TempEntry."Item No." := LPLine."Item No.";
                        TempEntry."Variant Code" := LPLine."Variant Code";
                        TempEntry."Lot No." := LPLine."Lot No.";
                        TempEntry."Serial No." := LPLine."Serial No.";
                        TempEntry."Qty. (Base)" := -Excess;
                        TempEntry."DOPSWHS LP No." := LpNo;
                        TempEntry.Insert();
                    end;
                end;
            until LPLine.Next() = 0;
        if Apply and (TotalExcess > 0) then
            ProcessBuffer(TempEntry, CopyStr('LPREPAIR#' + LpNo, 1, 40), '');
        exit(TotalExcess);
    end;

    procedure BinClaims(BinKey: Text) Total: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LineBase: Decimal;
    begin
        LP.SetCurrentKey("Location Code", "Bin Code", Status);
        LP.SetRange("Location Code", KeyPart(BinKey, 1));
        LP.SetRange("Bin Code", KeyPart(BinKey, 2));
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetRange("Pending Receipt No.", '');
        if LP.FindSet() then
            repeat
                FilterMatchingLines(LPLine, LP."No.", BinKey);
                if LPLine.FindSet() then
                    repeat
                        if LineBaseQty(LPLine, LineBase) then
                            Total += LineBase;
                    until LPLine.Next() = 0;
            until LP.Next() = 0;
        Total := Round(Total, 0.00001);
    end;

    /// <summary>Gözün kayıtlı ambar bakiyesi (lot/seri yalnız ambar izlemesi varsa).</summary>
    procedure BinBalance(BinKey: Text): Decimal
    var
        WarehouseEntry: Record "Warehouse Entry";
        ItemNo: Code[20];
    begin
        ItemNo := CopyStr(KeyPart(BinKey, 3), 1, MaxStrLen(ItemNo));
        WarehouseEntry.SetRange("Location Code", KeyPart(BinKey, 1));
        WarehouseEntry.SetRange("Bin Code", KeyPart(BinKey, 2));
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", KeyPart(BinKey, 4));
        if KeyPart(BinKey, 5) <> '' then
            WarehouseEntry.SetRange("Lot No.", KeyPart(BinKey, 5));
        if KeyPart(BinKey, 6) <> '' then
            WarehouseEntry.SetRange("Serial No.", KeyPart(BinKey, 6));
        WarehouseEntry.CalcSums("Qty. (Base)");
        exit(WarehouseEntry."Qty. (Base)");
    end;

    local procedure FilterMatchingLines(var LPLine: Record "DOPSWHS LP Line"; LpNo: Code[20]; BinKey: Text)
    begin
        LPLine.Reset();
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", KeyPart(BinKey, 3));
        LPLine.SetRange("Variant Code", KeyPart(BinKey, 4));
        if KeyPart(BinKey, 5) <> '' then
            LPLine.SetRange("Lot No.", KeyPart(BinKey, 5));
        if KeyPart(BinKey, 6) <> '' then
            LPLine.SetRange("Serial No.", KeyPart(BinKey, 6));
        LPLine.SetRange("Child LP No.", '');
        LPLine.SetFilter(Quantity, '>0');
    end;

    /// <summary>
    /// Konum|Göz|Madde|Varyant|Lot|Seri. Lot/seri yalnız maddenin ambar lot/seri
    /// izlemesi varsa anahtara girer (ambar girişleri ancak o zaman lot taşır).
    /// </summary>
    procedure MakeBinKey(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]): Text
    var
        LotWhse: Boolean;
        SnWhse: Boolean;
    begin
        WarehouseTracking(ItemNo, LotWhse, SnWhse);
        if not LotWhse then
            LotNo := '';
        if not SnWhse then
            SerialNo := '';
        exit(LocationCode + '|' + BinCode + '|' + ItemNo + '|' + VariantCode + '|' + LotNo + '|' + SerialNo);
    end;

    local procedure ReplaceBin(BinKey: Text; NewBin: Code[20]): Text
    begin
        exit(KeyPart(BinKey, 1) + '|' + NewBin + '|' + KeyPart(BinKey, 3) + '|' + KeyPart(BinKey, 4) + '|' + KeyPart(BinKey, 5) + '|' + KeyPart(BinKey, 6));
    end;

    local procedure SameTracking(KeyA: Text; KeyB: Text): Boolean
    begin
        exit(ReplaceBin(KeyA, '') = ReplaceBin(KeyB, ''));
    end;

    local procedure KeyPart(KeyText: Text; Index: Integer): Text
    var
        Parts: List of [Text];
    begin
        Parts := KeyText.Split('|');
        if Index > Parts.Count() then
            exit('');
        exit(Parts.Get(Index));
    end;

    local procedure AddQty(var Dict: Dictionary of [Text, Decimal]; KeyText: Text; Qty: Decimal)
    var
        Existing: Decimal;
    begin
        if Dict.Get(KeyText, Existing) then
            Dict.Set(KeyText, Existing + Qty)
        else
            Dict.Add(KeyText, Qty);
    end;

    local procedure WarehouseTracking(ItemNo: Code[20]; var LotWhse: Boolean; var SnWhse: Boolean)
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        LotWhse := false;
        SnWhse := false;
        if not Item.Get(ItemNo) then
            exit;
        if Item."Item Tracking Code" = '' then
            exit;
        if not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit;
        LotWhse := ItemTrackingCode."Lot Warehouse Tracking";
        SnWhse := ItemTrackingCode."SN Warehouse Tracking";
    end;

    local procedure LineQtyPer(LPLine: Record "DOPSWHS LP Line"; var QtyPer: Decimal): Boolean
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        QtyPer := 1;
        if not Item.Get(LPLine."Item No.") then
            exit(false);
        if (LPLine."Unit of Measure" = '') or (LPLine."Unit of Measure" = Item."Base Unit of Measure") then
            exit(true);
        if not ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
            exit(false);
        if ItemUoM."Qty. per Unit of Measure" <= 0 then
            exit(false);
        QtyPer := ItemUoM."Qty. per Unit of Measure";
        exit(true);
    end;

    local procedure LineBaseQty(LPLine: Record "DOPSWHS LP Line"; var LineBase: Decimal): Boolean
    var
        QtyPer: Decimal;
    begin
        LineBase := 0;
        if not LineQtyPer(LPLine, QtyPer) then
            exit(false);
        LineBase := Round(LPLine.Quantity * QtyPer, 0.00001);
        exit(true);
    end;

    local procedure IsActive(LP: Record "DOPSWHS LP Header"): Boolean
    begin
        exit((LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) and (LP."Pending Receipt No." = ''));
    end;

    local procedure IsAdjustmentBin(LocationCode: Text; BinCode: Text): Boolean
    var
        Location: Record Location;
        AdjustmentBin: Code[20];
        LocCode: Code[10];
    begin
        LocCode := CopyStr(LocationCode, 1, MaxStrLen(LocCode));
        if not AdjustmentBins.Get(LocCode, AdjustmentBin) then begin
            AdjustmentBin := '';
            if Location.Get(LocCode) then
                AdjustmentBin := Location."Adjustment Bin Code";
            AdjustmentBins.Set(LocCode, AdjustmentBin);
        end;
        exit((AdjustmentBin <> '') and (AdjustmentBin = BinCode));
    end;

    local procedure IsActivityEntry(WarehouseEntry: Record "Warehouse Entry"): Boolean
    begin
        exit(WarehouseEntry."Reference Document" in
            [WarehouseEntry."Reference Document"::"Put-away",
             WarehouseEntry."Reference Document"::Pick,
             WarehouseEntry."Reference Document"::Movement]);
    end;

    local procedure TrackingChanges(WarehouseJournalLine: Record "Warehouse Journal Line"): Boolean
    begin
        if (WarehouseJournalLine."New Lot No." <> '') and (WarehouseJournalLine."New Lot No." <> WarehouseJournalLine."Lot No.") then
            exit(true);
        if (WarehouseJournalLine."New Serial No." <> '') and (WarehouseJournalLine."New Serial No." <> WarehouseJournalLine."Serial No.") then
            exit(true);
        exit(false);
    end;

    local procedure AddToBuffer(var TempBuffer: Record "Warehouse Entry" temporary; WarehouseEntry: Record "Warehouse Entry")
    begin
        TempBuffer.Reset();
        if TempBuffer.Get(WarehouseEntry."Entry No.") then
            exit;
        TempBuffer := WarehouseEntry;
        TempBuffer.Insert();
    end;

    local procedure LineReference(var TempBuffer: Record "Warehouse Entry" temporary): Code[40]
    var
        DocumentNo: Text;
    begin
        TempBuffer.Reset();
        if not TempBuffer.FindFirst() then
            exit('LPSYNC');
        DocumentNo := TempBuffer."Reference No.";
        if DocumentNo = '' then
            DocumentNo := TempBuffer."Whse. Document No.";
        if DocumentNo = '' then
            DocumentNo := TempBuffer."Source No.";
        exit(CopyStr('LPSYNC#' + DocumentNo + '#' + Format(TempBuffer."Entry No.", 0, 9), 1, 40));
    end;

    local procedure Tolerance(): Decimal
    begin
        exit(0.00001);
    end;

    local procedure StaleAfterMs(): Integer
    begin
        exit(600000);
    end;

    // =========================================================================
    // Mal kabul: terminalde hazırlanmış LP'si olan belge BC'den kaydedilemez
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", 'OnBeforeRun', '', false, false)]
    local procedure BlockUiReceiptWithDraftLps(var WarehouseReceiptLine: Record "Warehouse Receipt Line")
    begin
        CheckReceiptPostingAllowed(WarehouseReceiptLine."No.");
    end;

    /// <summary>
    /// BADE (WRCPT): terminalde LP dağıtımı hazırlanmış ambar mal kabulü BC
    /// ekranından kaydedilirse stok LP'siz girer, boş taslak LP'ler silinmiş
    /// belgeye bağlı kalır ve "Stoktan LP Oluştur"u engeller. Terminal kaydı
    /// (Receipt Mgmt) "WMS Posting In Progress" bayrağını koyar ve geçer.
    /// </summary>
    procedure CheckReceiptPostingAllowed(ReceiptNo: Code[20])
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        LP: Record "DOPSWHS LP Header";
    begin
        if ReceiptNo = '' then
            exit;
        if IsTerminalPosting() then
            exit;
        if not WhseReceiptHeader.Get(ReceiptNo) then
            exit;
        if WhseReceiptHeader."DOPSWHS Posting In Progress" then
            exit;
        LP.SetRange("Pending Receipt No.", ReceiptNo);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.IsEmpty() then
            exit;
        Error(DraftLpReceiptErr, ReceiptNo, LP.Count());
    end;
}
