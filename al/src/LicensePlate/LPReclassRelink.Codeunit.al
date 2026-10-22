codeunit 72455 "DOPSWHS LP Reclass Relink"
{
    // BADE (22 Eki 2026, HM.00516 / lot H100807): SKT değiştirmek için yapılan
    // madde yeniden sınıflandırma (Transfer) eski mal kabul girişini kapatıp yeni
    // SKT'li pozitif transfer girişi açıyor. LP satırları kalanı 0 olan eski
    // girişe ve eski SKT'ye bağlı kalıyor, LP/MTE etiketleri eski SKT'yi basıyordu.
    //
    // (1) Kayıt anı: Item Jnl.-Post Line yeni pozitif transfer girişini eklediğinde
    //     (OnAfterInsertTransferEntry) giriş not edilir; satırın kaydı bitince
    //     (OnAfterPostItemJnlLine) eski girişe bağlı aktif LP satırları, taşınan
    //     miktar kadar yeni girişe bağlanır; lot/SKT yeni girişten alınır. Bu yol
    //     hiçbir durumda Error vermez; kayıt LP yüzünden durmaz.
    // (2) Onarım: önceden kaydedilmiş yeniden sınıflandırmalar için madde defteri
    //     girişlerinden ön izleme + onayla, LP kartından tek satır için elle.
    // Kural: kendi girişinin kalan miktarıyla desteklenen LP satırına dokunulmaz;
    // yalnız girişin kalanını aşan (açıkta kalan) LP miktarı taşınır.
    Access = Public;
    SingleInstance = true;
    Permissions =
        tabledata Item = R,
        tabledata "Item Unit of Measure" = R,
        tabledata "Item Ledger Entry" = RM,
        tabledata "Item Application Entry" = R,
        tabledata "DOPSWHS LP Header" = R,
        tabledata "DOPSWHS LP Line" = RM,
        tabledata "DOPSWHS LP Movement Ledger" = RI;

    var
        PendingEntryNos: List of [Integer];
        PendingFromBins: Dictionary of [Integer, Code[20]];
        PendingToBins: Dictionary of [Integer, Code[20]];
        PendingLpNos: Dictionary of [Integer, Code[20]];

    // =========================================================================
    // (1) Kayıt anı
    // =========================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnBeforePostItemJnlLine', '', false, false)]
    local procedure ClearPendingOnBeforePostItemJnlLine(var ItemJournalLine: Record "Item Journal Line")
    begin
        // Önceki geri alınmış bir kaydın artığı yeni kayda taşınmasın.
        ClearPending();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnAfterInsertTransferEntry', '', false, false)]
    local procedure CollectOnAfterInsertTransferEntry(var ItemJournalLine: Record "Item Journal Line"; NewItemLedgerEntry: Record "Item Ledger Entry"; OldItemLedgerEntry: Record "Item Ledger Entry")
    begin
        // Burada madde defteri girişine yazılmaz: BC eski girişin bellekteki
        // kopyasını hâlâ tutuyor. LP bağları satırın kaydı bitince güncellenir.
        if not IsPositiveTransfer(NewItemLedgerEntry) then
            exit;
        if NewItemLedgerEntry."Location Code" <> OldItemLedgerEntry."Location Code" then
            exit;
        if PendingEntryNos.Contains(NewItemLedgerEntry."Entry No.") then
            exit;
        PendingEntryNos.Add(NewItemLedgerEntry."Entry No.");
        PendingFromBins.Set(NewItemLedgerEntry."Entry No.", ItemJournalLine."Bin Code");
        PendingToBins.Set(NewItemLedgerEntry."Entry No.", ItemJournalLine."New Bin Code");
        PendingLpNos.Set(NewItemLedgerEntry."Entry No.", ItemJournalLine."DOPSWHS LP No.");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnAfterPostItemJnlLine', '', false, false)]
    local procedure RelinkOnAfterPostItemJnlLine(var ItemJournalLine: Record "Item Journal Line")
    var
        EntryNos: List of [Integer];
        FromBins: List of [Code[20]];
        ToBins: List of [Code[20]];
        LpNos: List of [Code[20]];
        EntryNo: Integer;
        BinCode: Code[20];
        Index: Integer;
    begin
        if PendingEntryNos.Count() = 0 then
            exit;
        foreach EntryNo in PendingEntryNos do begin
            EntryNos.Add(EntryNo);
            Clear(BinCode);
            if PendingFromBins.Get(EntryNo, BinCode) then;
            FromBins.Add(BinCode);
            Clear(BinCode);
            if PendingToBins.Get(EntryNo, BinCode) then;
            ToBins.Add(BinCode);
            Clear(BinCode);
            if PendingLpNos.Get(EntryNo, BinCode) then;
            LpNos.Add(BinCode);
        end;
        ClearPending();
        for Index := 1 to EntryNos.Count() do
            RelinkPostedTransferEntry(EntryNos.Get(Index), FromBins.Get(Index), ToBins.Get(Index), LpNos.Get(Index));
    end;

    /// <summary>
    /// Kayıt yolu çekirdeği (test edilebilir). NewEntryNo pozitif transfer
    /// girişidir; kaynak (uygulanan eski) girişe bağlı aktif LP satırlarını en
    /// çok taşınan miktar ve eski girişte açıkta kalan LP miktarı kadar yeni
    /// girişe bağlar. Raf: günlük satırında kaynak raf varsa yalnız o raftaki
    /// LP'ler; raf değişiyorsa yalnız günlük satırındaki açık LP. Hiç Error
    /// vermez. Döndürür: taşınan LP satırı sayısı.
    /// </summary>
    procedure RelinkPostedTransferEntry(NewEntryNo: Integer; FromBinCode: Code[20]; ToBinCode: Code[20]; JournalLpNo: Code[20]): Integer
    var
        NewEntry: Record "Item Ledger Entry";
        OldEntry: Record "Item Ledger Entry";
        LPLine: Record "DOPSWHS LP Line";
        Sources: Dictionary of [Integer, Decimal];
        Planned: Dictionary of [Integer, Decimal];
        TargetNos: List of [Integer];
        TargetCaps: List of [Decimal];
        Log: TextBuilder;
        SourceEntryNo: Integer;
        AltBinCode: Code[20];
        Capacity: Decimal;
        TransferredQty: Decimal;
        MovedLines: Integer;
    begin
        if not (LPLine.WritePermission() and NewEntry.WritePermission()) then
            exit(0);
        if not NewEntry.Get(NewEntryNo) then
            exit(0);
        if not IsPositiveTransfer(NewEntry) then
            exit(0);
        if (ToBinCode <> '') and (ToBinCode <> FromBinCode) then begin
            // Raf değişiyor: hangi paletin taşındığını yalnız günlükteki LP söyler.
            // LP başlığı burada taşınmaz; hareket kodu başlığı kendisi taşır.
            if JournalLpNo = '' then
                exit(0);
            AltBinCode := ToBinCode;
        end;
        ResolveTransferSources(NewEntry, Sources);
        foreach SourceEntryNo in Sources.Keys() do
            if OldEntry.Get(SourceEntryNo) then
                if (OldEntry."Location Code" = NewEntry."Location Code") and
                   (OldEntry."Item No." = NewEntry."Item No.") and
                   (OldEntry."Variant Code" = NewEntry."Variant Code")
                then begin
                    NewEntry.Get(NewEntryNo);
                    TransferredQty := Sources.Get(SourceEntryNo);
                    Capacity := AllocatableQuantity(NewEntry);
                    if Capacity > TransferredQty then
                        Capacity := TransferredQty;
                    if Capacity > QtyTolerance() then begin
                        Clear(TargetNos);
                        Clear(TargetCaps);
                        TargetNos.Add(NewEntry."Entry No.");
                        TargetCaps.Add(Capacity);
                        MovedLines += MoveLines(OldEntry, TargetNos, TargetCaps, FromBinCode, AltBinCode, JournalLpNo, true, Planned, Log);
                    end;
                end;
        exit(MovedLines);
    end;

    // =========================================================================
    // (2) Onarım: madde defteri girişlerinden
    // =========================================================================

    /// <summary>
    /// Seçilen girişten geriye doğru yeniden sınıflandırma zincirini izler ve
    /// LP satırı bağlı girişleri (eski mal kabul vb.) listeye ekler. Seçilen giriş
    /// eski giriş, eksi ya da artı transfer girişi olabilir.
    /// </summary>
    procedure CollectRelinkSourceEntries(EntryNo: Integer; var SourceEntryNos: List of [Integer])
    var
        Entry: Record "Item Ledger Entry";
        Appl: Record "Item Application Entry";
        Sources: Dictionary of [Integer, Decimal];
        Queue: List of [Integer];
        Visited: List of [Integer];
        CurrentNo: Integer;
        SourceNo: Integer;
        Position: Integer;
    begin
        Queue.Add(EntryNo);
        Position := 1;
        while (Position <= Queue.Count()) and (Position <= MaxChainEntries()) do begin
            CurrentNo := Queue.Get(Position);
            Position += 1;
            if not Visited.Contains(CurrentNo) then begin
                Visited.Add(CurrentNo);
                if Entry.Get(CurrentNo) then begin
                    if (Entry.Quantity > 0) and HasActiveLpLines(CurrentNo) then
                        if not SourceEntryNos.Contains(CurrentNo) then
                            SourceEntryNos.Add(CurrentNo);
                    if IsPositiveTransfer(Entry) then begin
                        Clear(Sources);
                        ResolveTransferSources(Entry, Sources);
                        foreach SourceNo in Sources.Keys() do
                            Queue.Add(SourceNo);
                    end else
                        if (Entry."Entry Type" = Entry."Entry Type"::Transfer) and (Entry.Quantity < 0) then begin
                            Appl.Reset();
                            Appl.SetRange("Item Ledger Entry No.", Entry."Entry No.");
                            Appl.SetRange("Outbound Item Entry No.", Entry."Entry No.");
                            Appl.SetFilter("Inbound Item Entry No.", '<>0');
                            if Appl.FindSet() then
                                repeat
                                    Queue.Add(Appl."Inbound Item Entry No.");
                                until Appl.Next() = 0;
                        end;
                end;
            end;
        end;
    end;

    /// <summary>Değişiklik yapmadan taşınacak LP satırlarını sayar ve özetler.</summary>
    procedure PreviewReclassRelink(var SourceEntryNos: List of [Integer]; var PreviewText: Text): Integer
    begin
        exit(RunReclassRelink(SourceEntryNos, false, PreviewText));
    end;

    /// <summary>Ön izlemedeki taşımayı uygular. Döndürür: taşınan LP satırı sayısı.</summary>
    procedure ApplyReclassRelink(var SourceEntryNos: List of [Integer]): Integer
    var
        Dummy: Text;
    begin
        exit(RunReclassRelink(SourceEntryNos, true, Dummy));
    end;

    local procedure RunReclassRelink(var SourceEntryNos: List of [Integer]; ApplyChanges: Boolean; var PreviewText: Text): Integer
    var
        SourceEntry: Record "Item Ledger Entry";
        Planned: Dictionary of [Integer, Decimal];
        TargetNos: List of [Integer];
        TargetCaps: List of [Decimal];
        SortedNos: List of [Integer];
        Log: TextBuilder;
        SourceNo: Integer;
        MovedLines: Integer;
    begin
        SortEntryNos(SourceEntryNos, SortedNos);
        foreach SourceNo in SortedNos do
            if SourceEntry.Get(SourceNo) then begin
                Clear(TargetNos);
                Clear(TargetCaps);
                PlanTargets(SourceEntry, ExcessQuantity(SourceEntry), 1, TargetNos, TargetCaps, Planned);
                if TargetNos.Count() > 0 then
                    MovedLines += MoveLines(SourceEntry, TargetNos, TargetCaps, '', '', '', ApplyChanges, Planned, Log);
            end;
        PreviewText := Log.ToText();
        exit(MovedLines);
    end;

    // =========================================================================
    // (2b) Onarım: LP kartından tek satır (Kaynak Girişi Bağla)
    // =========================================================================

    /// <summary>
    /// Mevcut kaynağı tükenmiş (girişi yok ya da kalanı bağlı LP miktarından az)
    /// satır için seçilebilecek açık girişlerin Entry No. filtresi: yeniden
    /// sınıflandırma zincirindeki ardıl girişler ile aynı ürün/varyant/lot/seri/
    /// lokasyondaki açık girişler. Kaynak gerçek stokla destekleniyorsa hata verir.
    /// </summary>
    procedure GetRelinkCandidateFilter(var LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line"): Text
    var
        CurrentEntry: Record "Item Ledger Entry";
        Entry: Record "Item Ledger Entry";
        Planned: Dictionary of [Integer, Decimal];
        TargetNos: List of [Integer];
        TargetCaps: List of [Decimal];
        Candidates: List of [Integer];
        CandidateNo: Integer;
        FilterText: Text;
    begin
        EnsureRelinkAllowed(LP, LPLine);
        if CurrentEntry.Get(LPLine."Source Item Ledger Entry No.") then begin
            PlanTargets(CurrentEntry, 999999999, 1, TargetNos, TargetCaps, Planned);
            foreach CandidateNo in TargetNos do
                AddUnique(Candidates, CandidateNo);
        end;
        Entry.SetRange("Item No.", LPLine."Item No.");
        Entry.SetRange("Variant Code", LPLine."Variant Code");
        Entry.SetRange("Lot No.", LPLine."Lot No.");
        Entry.SetRange("Serial No.", LPLine."Serial No.");
        Entry.SetRange("Location Code", LP."Location Code");
        Entry.SetFilter(Quantity, '>0');
        Entry.SetFilter("Remaining Quantity", '>0');
        if Entry.FindSet() then
            repeat
                if Entry."Entry No." <> LPLine."Source Item Ledger Entry No." then
                    AddUnique(Candidates, Entry."Entry No.");
            until (Entry.Next() = 0) or (Candidates.Count() >= MaxChainEntries());
        foreach CandidateNo in Candidates do begin
            if FilterText <> '' then
                FilterText += '|';
            FilterText += Format(CandidateNo, 0, 9);
        end;
        if FilterText = '' then
            Error('%1 LP satırı için bağlanabilecek açık madde defteri girişi bulunamadı (aynı ürün/lot ya da yeniden sınıflandırma ardılı).', LPLine."LP No.");
        exit(FilterText);
    end;

    /// <summary>
    /// Tükenmiş kaynağa bağlı LP satırını seçilen açık girişe yeniden bağlar;
    /// lot/seri (ardıl girişte değiştiyse) ve SKT seçilen girişten alınır.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure RelinkExhaustedStockLine(var LP: Record "DOPSWHS LP Header"; LineNo: Integer; NewEntryNo: Integer)
    var
        OldEntry: Record "Item Ledger Entry";
        NewEntry: Record "Item Ledger Entry";
        LPLine: Record "DOPSWHS LP Line";
        BaseQty: Decimal;
        OldEntryNo: Integer;
        IsSuccessor: Boolean;
    begin
        OldEntry.LockTable();
        LP.LockTable();
        LPLine.LockTable();
        LP.Get(LP."No.");
        LPLine.Get(LP."No.", LineNo);
        EnsureRelinkAllowed(LP, LPLine);
        OldEntryNo := LPLine."Source Item Ledger Entry No.";
        if NewEntryNo = OldEntryNo then
            exit;
        NewEntry.Get(NewEntryNo);
        if (NewEntry."Item No." <> LPLine."Item No.") or (NewEntry."Variant Code" <> LPLine."Variant Code") or
           (NewEntry."Location Code" <> LP."Location Code") or (NewEntry.Quantity <= 0)
        then
            Error('%1 girişi LP satırının ürün, varyant veya lokasyonuyla uyuşmuyor.', NewEntryNo);
        if NewEntry."Remaining Quantity" <= 0 then
            Error('%1 girişinde kalan miktar yok.', NewEntryNo);
        if OldEntry.Get(OldEntryNo) then
            IsSuccessor := IsChainSuccessor(OldEntry, NewEntryNo, 1);
        if not IsSuccessor then
            if (NewEntry."Lot No." <> LPLine."Lot No.") or (NewEntry."Serial No." <> LPLine."Serial No.") then
                Error('%1 girişinin lot/seri numarası LP satırından farklı ve yeniden sınıflandırma ardılı değil.', NewEntryNo);
        if not TryBaseQuantity(LPLine, BaseQty) then
            Error('%1 / %2 birim dönüşümü geçersiz.', LPLine."Item No.", LPLine."Unit of Measure");
        if AllocatableQuantity(NewEntry) + QtyTolerance() < BaseQty then
            Error('%1 girişinde LP''ye ayrılabilir miktar %2; gerekli temel miktar %3.', NewEntryNo, AllocatableQuantity(NewEntry), BaseQty);
        if not OldEntry.Get(OldEntryNo) then
            Clear(OldEntry);
        RelinkLine(LP, LPLine, OldEntry, NewEntry, BaseQty);
        if OldEntry."Entry No." <> 0 then
            RefreshEntryReferences(OldEntry."Entry No.", false);
        RefreshEntryReferences(NewEntry."Entry No.", true);
    end;

    local procedure EnsureRelinkAllowed(var LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line")
    var
        CurrentEntry: Record "Item Ledger Entry";
    begin
        LPLine.TestField("Item No.");
        if LPLine."Source Item Ledger Entry No." = 0 then
            Error('Satırın kaynak girişi yok; Kaynak Girişi Bağla ile bağlayın.');
        if LPLine.Quantity <= 0 then
            Error('Kaynak bağlantısı için LP satır miktarı sıfırdan büyük olmalıdır.');
        if LPLine."Child LP No." <> '' then
            Error('İç içe LP satırının kaynağı değiştirilemez.');
        if LP."Pending Receipt No." <> '' then
            Error('%1 LP''si %2 mal kabulünü bekliyor.', LP."No.", LP."Pending Receipt No.");
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            Error('Yalnız aktif LP satırlarının kaynak bağlantısı değiştirilebilir.');
        if CurrentEntry.Get(LPLine."Source Item Ledger Entry No.") then
            if ExcessQuantity(CurrentEntry) <= QtyTolerance() then
                Error('Satır zaten %1 girişine bağlı ve bu girişin kalan miktarı (%2) bağlı LP miktarını karşılıyor; kaynak değiştirilemez.',
                    CurrentEntry."Entry No.", CurrentEntry."Remaining Quantity");
    end;

    // =========================================================================
    // Etiket: yeniden sınıflandırma girişinden asıl mal kabul/üretim girişine
    // =========================================================================

    /// <summary>
    /// Pozitif transfer (yeniden sınıflandırma) girişinden geriye, asıl giriş
    /// (mal kabul, üretim çıkışı, pozitif düzeltme) bulunana kadar ilerler.
    /// Etiketteki tedarikçi, mal kabul tarihi/no bilgisi için kullanılır.
    /// </summary>
    procedure FindOriginEntry(var Entry: Record "Item Ledger Entry")
    var
        Previous: Record "Item Ledger Entry";
        Sources: Dictionary of [Integer, Decimal];
        SourceNo: Integer;
        BestNo: Integer;
        BestQty: Decimal;
        Depth: Integer;
    begin
        for Depth := 1 to MaxChainDepth() do begin
            if not IsPositiveTransfer(Entry) then
                exit;
            Clear(Sources);
            ResolveTransferSources(Entry, Sources);
            BestNo := 0;
            BestQty := 0;
            foreach SourceNo in Sources.Keys() do
                if Sources.Get(SourceNo) > BestQty then begin
                    BestNo := SourceNo;
                    BestQty := Sources.Get(SourceNo);
                end;
            if (BestNo = 0) or (BestNo = Entry."Entry No.") then
                exit;
            if not Previous.Get(BestNo) then
                exit;
            Entry := Previous;
        end;
    end;

    // =========================================================================
    // Çekirdek
    // =========================================================================

    local procedure MoveLines(OldEntry: Record "Item Ledger Entry"; var TargetNos: List of [Integer]; var TargetCaps: List of [Decimal]; BinCode: Code[20]; AltBinCode: Code[20]; LpNo: Code[20]; ApplyChanges: Boolean; var Planned: Dictionary of [Integer, Decimal]; var Log: TextBuilder) MovedLines: Integer
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        NewEntry: Record "Item Ledger Entry";
        LineLpNos: List of [Code[20]];
        LineNos: List of [Integer];
        LineTargets: List of [Integer];
        LineQtys: List of [Decimal];
        TouchedTargets: List of [Integer];
        Excess: Decimal;
        BaseQty: Decimal;
        PlannedQty: Decimal;
        TargetIndex: Integer;
        Index: Integer;
    begin
        Excess := ExcessQuantity(OldEntry);
        if Excess <= QtyTolerance() then
            exit(0);
        LPLine.SetRange("Source Item Ledger Entry No.", OldEntry."Entry No.");
        LPLine.SetFilter(Quantity, '>0');
        if LpNo <> '' then
            LPLine.SetRange("LP No.", LpNo);
        if not LPLine.FindSet() then
            exit(0);
        // Önce planla, sonra uygula: filtre alanı değiştiği için döngü içinde yazılmaz.
        repeat
            if LineEligible(LPLine, OldEntry, BinCode, AltBinCode, LP, BaseQty) then
                if BaseQty <= Excess + QtyTolerance() then begin
                    TargetIndex := FindTarget(TargetCaps, BaseQty);
                    if TargetIndex > 0 then begin
                        LineLpNos.Add(LPLine."LP No.");
                        LineNos.Add(LPLine."Line No.");
                        LineTargets.Add(TargetNos.Get(TargetIndex));
                        LineQtys.Add(BaseQty);
                        TargetCaps.Set(TargetIndex, TargetCaps.Get(TargetIndex) - BaseQty);
                        Excess -= BaseQty;
                    end;
                end;
        until (LPLine.Next() = 0) or (Excess <= QtyTolerance());

        for Index := 1 to LineNos.Count() do
            if LP.Get(LineLpNos.Get(Index)) and LPLine.Get(LineLpNos.Get(Index), LineNos.Get(Index)) and
               NewEntry.Get(LineTargets.Get(Index))
            then begin
                AppendLog(Log, LPLine, OldEntry, NewEntry);
                if ApplyChanges then
                    RelinkLine(LP, LPLine, OldEntry, NewEntry, LineQtys.Get(Index))
                else begin
                    // Ön izlemede aynı hedef ikinci kaynak için yeniden sayılmasın.
                    if not Planned.Get(NewEntry."Entry No.", PlannedQty) then
                        PlannedQty := 0;
                    Planned.Set(NewEntry."Entry No.", PlannedQty + LineQtys.Get(Index));
                end;
                AddUnique(TouchedTargets, NewEntry."Entry No.");
                MovedLines += 1;
            end;

        if ApplyChanges and (MovedLines > 0) then begin
            // Eski giriş geçmiş LP bilgisini korur (boşaltılmaz); yeni giriş kesin listeyi alır.
            RefreshEntryReferences(OldEntry."Entry No.", false);
            foreach Index in TouchedTargets do
                RefreshEntryReferences(Index, true);
        end;
    end;

    local procedure RelinkLine(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"; OldEntry: Record "Item Ledger Entry"; NewEntry: Record "Item Ledger Entry"; BaseQty: Decimal)
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        OldEntryNo: Integer;
    begin
        OldEntryNo := LPLine."Source Item Ledger Entry No.";
        LPLine."Source Item Ledger Entry No." := NewEntry."Entry No.";
        // Elle stok bağlantısı (belgesiz satır) kaynak belge alanlarını da girişten alır.
        if (LPLine."Source Document Type" = LPLine."Source Document Type"::None) and
           (LPLine."Source Document Line No." = OldEntryNo)
        then begin
            LPLine."Source Document No." := NewEntry."Document No.";
            LPLine."Source Document Line No." := NewEntry."Entry No.";
            LPLine."Source Document Quantity" := NewEntry.Quantity;
        end;
        LPLine."Lot No." := NewEntry."Lot No.";
        LPLine."Serial No." := NewEntry."Serial No.";
        if (NewEntry."Expiration Date" <> 0D) or (OldEntry."Expiration Date" <> 0D) or (OldEntry."Entry No." = 0) then
            LPLine."Expiration Date" := NewEntry."Expiration Date";
        LPLine.Modify(true);
        LPMgt.WriteToLedger(
            LP, Enum::"DOPSWHS LP Action"::SourceLinked, LP."Bin Code", LP."Bin Code", BaseQty,
            LPLine."Item No.", LPLine."Lot No.",
            CopyStr(StrSubstNo('RECLASS:%1>%2:%3', OldEntryNo, NewEntry."Entry No.", LPLine."Line No."), 1, 40));
    end;

    local procedure LineEligible(LPLine: Record "DOPSWHS LP Line"; OldEntry: Record "Item Ledger Entry"; BinCode: Code[20]; AltBinCode: Code[20]; var LP: Record "DOPSWHS LP Header"; var BaseQty: Decimal): Boolean
    begin
        BaseQty := 0;
        if LPLine."Child LP No." <> '' then
            exit(false);
        if (LPLine."Item No." <> OldEntry."Item No.") or (LPLine."Variant Code" <> OldEntry."Variant Code") or
           (LPLine."Lot No." <> OldEntry."Lot No.") or (LPLine."Serial No." <> OldEntry."Serial No.")
        then
            exit(false);
        if not LP.Get(LPLine."LP No.") then
            exit(false);
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            exit(false);
        if LP."Pending Receipt No." <> '' then
            exit(false);
        if LP."Location Code" <> OldEntry."Location Code" then
            exit(false);
        if BinCode <> '' then
            if (LP."Bin Code" <> BinCode) and ((AltBinCode = '') or (LP."Bin Code" <> AltBinCode)) then
                exit(false);
        if not TryBaseQuantity(LPLine, BaseQty) then
            exit(false);
        exit(BaseQty > QtyTolerance());
    end;

    /// <summary>
    /// Kaynak girişin ardıl pozitif transfer girişlerini (zincir boyunca) hedef
    /// listesine ekler. Her hedefin kapasitesi: o kaynaktan gelen miktar ile
    /// hedefin LP'ye ayrılabilir kalan miktarının küçüğü.
    /// </summary>
    local procedure PlanTargets(SourceEntry: Record "Item Ledger Entry"; MaxQty: Decimal; Depth: Integer; var TargetNos: List of [Integer]; var TargetCaps: List of [Decimal]; var Planned: Dictionary of [Integer, Decimal]) PlannedTotal: Decimal
    var
        Successor: Record "Item Ledger Entry";
        SuccessorNos: List of [Integer];
        SuccessorQtys: List of [Decimal];
        Remaining: Decimal;
        Flow: Decimal;
        Own: Decimal;
        Take: Decimal;
        Sub: Decimal;
        PlannedQty: Decimal;
        Index: Integer;
        TargetIndex: Integer;
    begin
        if (MaxQty <= QtyTolerance()) or (Depth > MaxChainDepth()) then
            exit(0);
        CollectSuccessors(SourceEntry, SuccessorNos, SuccessorQtys);
        Remaining := MaxQty;
        for Index := 1 to SuccessorNos.Count() do
            if (Remaining > QtyTolerance()) and Successor.Get(SuccessorNos.Get(Index)) then begin
                Flow := SuccessorQtys.Get(Index);
                if Flow > Remaining then
                    Flow := Remaining;
                Own := AllocatableQuantity(Successor);
                if Planned.Get(Successor."Entry No.", PlannedQty) then
                    Own -= PlannedQty;
                TargetIndex := TargetNos.IndexOf(Successor."Entry No.");
                if TargetIndex > 0 then
                    Own -= TargetCaps.Get(TargetIndex);
                Take := Flow;
                if Take > Own then
                    Take := Own;
                if Take > QtyTolerance() then begin
                    if TargetIndex > 0 then
                        TargetCaps.Set(TargetIndex, TargetCaps.Get(TargetIndex) + Take)
                    else begin
                        TargetNos.Add(Successor."Entry No.");
                        TargetCaps.Add(Take);
                    end;
                    Remaining -= Take;
                    Flow -= Take;
                end;
                if Flow > QtyTolerance() then begin
                    Sub := PlanTargets(Successor, Flow, Depth + 1, TargetNos, TargetCaps, Planned);
                    Remaining -= Sub;
                end;
            end;
        exit(MaxQty - Remaining);
    end;

    /// <summary>
    /// Kaynak girişe uygulanan eksi transfer girişlerinden doğan, aynı belgedeki
    /// pozitif transfer girişleri ve kaynaktan gelen miktarları.
    /// </summary>
    local procedure CollectSuccessors(SourceEntry: Record "Item Ledger Entry"; var SuccessorNos: List of [Integer]; var SuccessorQtys: List of [Decimal])
    var
        OutAppl: Record "Item Application Entry";
        InAppl: Record "Item Application Entry";
        NegEntry: Record "Item Ledger Entry";
        NewEntry: Record "Item Ledger Entry";
        Qty: Decimal;
    begin
        OutAppl.SetRange("Inbound Item Entry No.", SourceEntry."Entry No.");
        OutAppl.SetFilter("Outbound Item Entry No.", '<>0');
        OutAppl.SetFilter(Quantity, '<0');
        if not OutAppl.FindSet() then
            exit;
        repeat
            if OutAppl."Item Ledger Entry No." = OutAppl."Outbound Item Entry No." then
                if NegEntry.Get(OutAppl."Outbound Item Entry No.") then
                    if (NegEntry."Entry Type" = NegEntry."Entry Type"::Transfer) and (NegEntry.Quantity < 0) then begin
                        InAppl.Reset();
                        InAppl.SetRange("Outbound Item Entry No.", NegEntry."Entry No.");
                        InAppl.SetFilter(Quantity, '>0');
                        if InAppl.FindSet() then
                            repeat
                                if (InAppl."Item Ledger Entry No." = InAppl."Inbound Item Entry No.") and
                                   (InAppl."Transferred-from Entry No." in [0, SourceEntry."Entry No."]) and
                                   not SuccessorNos.Contains(InAppl."Inbound Item Entry No.")
                                then
                                    if NewEntry.Get(InAppl."Inbound Item Entry No.") then
                                        if IsPositiveTransfer(NewEntry) and
                                           (NewEntry."Document No." = NegEntry."Document No.") and
                                           (NewEntry."Location Code" = SourceEntry."Location Code") and
                                           (NewEntry."Item No." = SourceEntry."Item No.") and
                                           (NewEntry."Variant Code" = SourceEntry."Variant Code")
                                        then begin
                                            if InAppl."Transferred-from Entry No." = SourceEntry."Entry No." then
                                                Qty := InAppl.Quantity
                                            else
                                                Qty := -OutAppl.Quantity; // ortalama maliyetli transfer
                                            if Qty > NewEntry.Quantity then
                                                Qty := NewEntry.Quantity;
                                            SuccessorNos.Add(NewEntry."Entry No.");
                                            SuccessorQtys.Add(Qty);
                                        end;
                            until InAppl.Next() = 0;
                    end;
        until OutAppl.Next() = 0;
    end;

    local procedure IsChainSuccessor(SourceEntry: Record "Item Ledger Entry"; TargetEntryNo: Integer; Depth: Integer): Boolean
    var
        Successor: Record "Item Ledger Entry";
        SuccessorNos: List of [Integer];
        SuccessorQtys: List of [Decimal];
        SuccessorNo: Integer;
    begin
        if Depth > MaxChainDepth() then
            exit(false);
        CollectSuccessors(SourceEntry, SuccessorNos, SuccessorQtys);
        if SuccessorNos.Contains(TargetEntryNo) then
            exit(true);
        foreach SuccessorNo in SuccessorNos do
            if Successor.Get(SuccessorNo) then
                if IsChainSuccessor(Successor, TargetEntryNo, Depth + 1) then
                    exit(true);
        exit(false);
    end;

    /// <summary>
    /// Pozitif transfer girişinin kaynak (uygulanan eski) girişleri ve her birinden
    /// gelen miktar. Normal transferde Transferred-from Entry No., ortalama
    /// maliyetli transferde eksi girişin uygulamaları kullanılır.
    /// </summary>
    procedure ResolveTransferSources(NewEntry: Record "Item Ledger Entry"; var Sources: Dictionary of [Integer, Decimal])
    var
        Appl: Record "Item Application Entry";
        OutAppl: Record "Item Application Entry";
        Qty: Decimal;
    begin
        if not IsPositiveTransfer(NewEntry) then
            exit;
        Appl.SetRange("Item Ledger Entry No.", NewEntry."Entry No.");
        Appl.SetRange("Inbound Item Entry No.", NewEntry."Entry No.");
        Appl.SetFilter(Quantity, '>0');
        if not Appl.FindFirst() then
            exit;
        if Appl."Transferred-from Entry No." <> 0 then begin
            if Appl."Transferred-from Entry No." <> NewEntry."Entry No." then
                Sources.Set(Appl."Transferred-from Entry No.", NewEntry.Quantity);
            exit;
        end;
        if Appl."Outbound Item Entry No." = 0 then
            exit;
        OutAppl.SetRange("Item Ledger Entry No.", Appl."Outbound Item Entry No.");
        OutAppl.SetRange("Outbound Item Entry No.", Appl."Outbound Item Entry No.");
        OutAppl.SetFilter("Inbound Item Entry No.", '<>0');
        OutAppl.SetFilter(Quantity, '<0');
        if OutAppl.FindSet() then
            repeat
                if OutAppl."Inbound Item Entry No." <> NewEntry."Entry No." then begin
                    if not Sources.Get(OutAppl."Inbound Item Entry No.", Qty) then
                        Qty := 0;
                    Sources.Set(OutAppl."Inbound Item Entry No.", Qty - OutAppl.Quantity);
                end;
            until OutAppl.Next() = 0;
    end;

    local procedure IsPositiveTransfer(Entry: Record "Item Ledger Entry"): Boolean
    begin
        exit((Entry."Entry No." <> 0) and (Entry."Entry Type" = Entry."Entry Type"::Transfer) and (Entry.Quantity > 0));
    end;

    /// <summary>Girişe bağlı aktif LP miktarının girişin kalan miktarını aşan kısmı.</summary>
    local procedure ExcessQuantity(Entry: Record "Item Ledger Entry"): Decimal
    var
        Remaining: Decimal;
        Excess: Decimal;
    begin
        Remaining := Entry."Remaining Quantity";
        if Remaining < 0 then
            Remaining := 0;
        Excess := ActiveAllocatedQuantity(Entry."Entry No.") - Remaining;
        if Excess < 0 then
            exit(0);
        exit(Excess);
    end;

    local procedure AllocatableQuantity(Entry: Record "Item Ledger Entry"): Decimal
    var
        Allocatable: Decimal;
    begin
        Allocatable := Entry."Remaining Quantity" - ActiveAllocatedQuantity(Entry."Entry No.");
        if Allocatable < 0 then
            exit(0);
        exit(Allocatable);
    end;

    local procedure ActiveAllocatedQuantity(EntryNo: Integer) Total: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        BaseQty: Decimal;
    begin
        if EntryNo = 0 then
            exit(0);
        LPLine.SetRange("Source Item Ledger Entry No.", EntryNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") then
                    if LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned] then begin
                        if not TryBaseQuantity(LPLine, BaseQty) then
                            BaseQty := LPLine.Quantity;
                        Total += BaseQty;
                    end;
            until LPLine.Next() = 0;
    end;

    local procedure HasActiveLpLines(EntryNo: Integer): Boolean
    begin
        exit(ActiveAllocatedQuantity(EntryNo) > QtyTolerance());
    end;

    local procedure TryBaseQuantity(LPLine: Record "DOPSWHS LP Line"; var BaseQty: Decimal): Boolean
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        BaseQty := 0;
        if not Item.Get(LPLine."Item No.") then
            exit(false);
        if (LPLine."Unit of Measure" = '') or (LPLine."Unit of Measure" = Item."Base Unit of Measure") then begin
            BaseQty := LPLine.Quantity;
            exit(true);
        end;
        if not ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
            exit(false);
        if ItemUoM."Qty. per Unit of Measure" <= 0 then
            exit(false);
        BaseQty := LPLine.Quantity * ItemUoM."Qty. per Unit of Measure";
        exit(true);
    end;

    local procedure FindTarget(var TargetCaps: List of [Decimal]; BaseQty: Decimal): Integer
    var
        Index: Integer;
    begin
        for Index := 1 to TargetCaps.Count() do
            if TargetCaps.Get(Index) + QtyTolerance() >= BaseQty then
                exit(Index);
        exit(0);
    end;

    local procedure RefreshEntryReferences(EntryNo: Integer; ClearWhenEmpty: Boolean)
    var
        Entry: Record "Item Ledger Entry";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if not Entry.Get(EntryNo) then
            exit;
        LPMgt.RefreshItemLedgerEntryLpReferences(EntryNo, ClearWhenEmpty);
    end;

    local procedure AppendLog(var Log: TextBuilder; LPLine: Record "DOPSWHS LP Line"; OldEntry: Record "Item Ledger Entry"; NewEntry: Record "Item Ledger Entry")
    begin
        if Log.Length() > 1500 then
            exit;
        Log.Append(StrSubstNo('%1/%2: %3 -> %4, lot %5 -> %6, SKT %7 -> %8\',
            LPLine."LP No.", LPLine."Line No.", OldEntry."Entry No.", NewEntry."Entry No.",
            LPLine."Lot No.", NewEntry."Lot No.", Format(LPLine."Expiration Date"), Format(NewEntry."Expiration Date")));
    end;

    local procedure SortEntryNos(var EntryNos: List of [Integer]; var SortedNos: List of [Integer])
    var
        EntryNo: Integer;
        Index: Integer;
        Inserted: Boolean;
    begin
        // Zincir sırası: eski giriş önce taşınır (P -> T1 -> T2).
        foreach EntryNo in EntryNos do begin
            Inserted := false;
            for Index := 1 to SortedNos.Count() do
                if not Inserted then
                    if EntryNo < SortedNos.Get(Index) then begin
                        SortedNos.Insert(Index, EntryNo);
                        Inserted := true;
                    end;
            if not Inserted then
                SortedNos.Add(EntryNo);
        end;
    end;

    local procedure AddUnique(var EntryNos: List of [Integer]; EntryNo: Integer)
    begin
        if not EntryNos.Contains(EntryNo) then
            EntryNos.Add(EntryNo);
    end;

    local procedure ClearPending()
    begin
        Clear(PendingEntryNos);
        Clear(PendingFromBins);
        Clear(PendingToBins);
        Clear(PendingLpNos);
    end;

    local procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
    end;

    local procedure MaxChainDepth(): Integer
    begin
        exit(10);
    end;

    local procedure MaxChainEntries(): Integer
    begin
        exit(200);
    end;
}
