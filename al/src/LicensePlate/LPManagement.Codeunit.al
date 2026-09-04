codeunit 72040 "DOPSWHS LP Management"
{
    Access = Public;
    Permissions =
        tabledata Item = R,
        tabledata "Item Unit of Measure" = R,
        tabledata "Item Tracking Code" = R,
        tabledata "Item Ledger Entry" = RM,
        tabledata Location = R,
        tabledata Bin = R,
        tabledata "Bin Content" = R,
        tabledata "Warehouse Entry" = R,
        tabledata "DOPSWHS LP Bulk Request" = RIM,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RMD,
        tabledata "DOPSWHS LP Movement Ledger" = I;

    procedure Build(TemplateCode: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; var LP: Record "DOPSWHS LP Header")
    var
        Template: Record "DOPSWHS LP Template";
        Location: Record Location;
        Bin: Record Bin;
    begin
        OnBeforeBuild(TemplateCode, LocationCode, BinCode, LP);
        if TemplateCode = '' then
            Error('LP şablon kodu zorunludur.');
        if not Template.Get(TemplateCode) then
            Error('%1 LP şablonu bulunamadı.', TemplateCode);
        if LocationCode = '' then
            Error('LP oluşturmak için lokasyon kodu zorunludur.');
        if not Location.Get(LocationCode) then
            Error('%1 lokasyonu bulunamadı.', LocationCode);
        if (BinCode <> '') and (not Bin.Get(LocationCode, BinCode)) then
            Error('%1 rafı %2 lokasyonunda bulunamadı.', BinCode, LocationCode);

        LogMutation('LP.Build');
        // Record.Init() deliberately keeps primary-key fields in AL. StartLP
        // may have used this same variable to inspect a previously assigned LP;
        // without Clear(), the old No. survives Init() and Insert attempts to
        // create that LP again instead of requesting a new number-series value.
        Clear(LP);
        LP.Init();
        LP."LP Template Code" := TemplateCode;
        LP."Location Code" := LocationCode;
        LP."Bin Code" := BinCode;
        LP.Status := LP.Status::Open;
        LP."Length cm" := Template."Default Length cm";
        LP."Width cm" := Template."Default Width cm";
        LP."Height cm" := Template."Default Height cm";
        LP.Insert(true);
        WriteToLedger(LP, LPActionBuilt(), '', BinCode, 0, '', '', '');
        OnAfterBuild(LP);
    end;

    procedure Stop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean)
    begin
        Stop(LP, PrintLabel, '');
    end;

    procedure Stop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean; PrinterId: Code[50])
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Generator: Codeunit "DOPSWHS SSCC Generator";
    begin
        OnBeforeStop(LP, PrintLabel);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.Stop');
        LP.Status := LP.Status::Built;
        if LP.SSCC = '' then
            LP.SSCC := Generator.Generate();
        LP.Modify(true);
        WriteToLedger(LP, LPActionBuilt(), LP."Bin Code", LP."Bin Code", 0, '', '', '');
        if PrintLabel then
            Dispatcher.PrintLPLabel(LP, PrinterId, 1);
        OnAfterStop(LP);
    end;

    procedure Reopen(var LP: Record "DOPSWHS LP Header")
    begin
        OnBeforeReopen(LP);
        RequireStatus(LP, LP.Status::Built);
        LogMutation('LP.Reopen');
        LP.Status := LP.Status::Open;
        LP.Modify(true);
        OnAfterReopen(LP);
    end;

    procedure AddLine(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; UoM: Code[10]; Qty: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        OnBeforeAddLine(LP, ItemNo, UoM, Qty);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.AddLine');
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine.Validate("Item No.", ItemNo);
        LPLine."Unit of Measure" := UoM;
        LPLine.Validate(Quantity, Qty);
        LPLine."Lot No." := LotNo;
        LPLine."Serial No." := SerialNo;
        LPLine."Expiration Date" := ExpiryDate;
        LPLine.Insert(true);
        WriteToLedger(LP, LPActionItemAdded(), '', LP."Bin Code", Qty, ItemNo, LotNo + SerialNo, '');
        OnAfterAddLine(LP, LPLine);
    end;

    /// <summary>
    /// Creates multiple physical LPs from one existing Item Ledger Entry.
    /// The ledger entry remains one unchanged row; each LP line only keeps its
    /// Entry No. as a source reference.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure BuildManyFromItemLedgerEntry(ItemLedgerEntryNo: Integer; TemplateCode: Code[20]; BinCode: Code[20]; LpCount: Integer; QuantityPerLp: Decimal; var CreatedLpNos: List of [Code[20]])
    var
        EmptyRequestId: Guid;
        Replayed: Boolean;
    begin
        BuildManyFromItemLedgerEntryCore(
            ItemLedgerEntryNo, TemplateCode, BinCode, LpCount, QuantityPerLp,
            EmptyRequestId, false, CreatedLpNos, Replayed);
    end;

    /// <summary>
    /// Retry-safe variant used by terminals. Replaying the same RequestId
    /// returns the original LP numbers and never allocates the stock twice.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure BuildManyFromItemLedgerEntryIdempotent(ItemLedgerEntryNo: Integer; TemplateCode: Code[20]; BinCode: Code[20]; LpCount: Integer; QuantityPerLp: Decimal; RequestId: Guid; var CreatedLpNos: List of [Code[20]]; var Replayed: Boolean)
    begin
        if IsNullGuid(RequestId) then
            Error('Toplu LP işlem kimliği zorunludur.');
        BuildManyFromItemLedgerEntryCore(
            ItemLedgerEntryNo, TemplateCode, BinCode, LpCount, QuantityPerLp,
            RequestId, true, CreatedLpNos, Replayed);
    end;

    [CommitBehavior(CommitBehavior::Error)]
    local procedure BuildManyFromItemLedgerEntryCore(ItemLedgerEntryNo: Integer; TemplateCode: Code[20]; BinCode: Code[20]; LpCount: Integer; QuantityPerLp: Decimal; RequestId: Guid; UseIdempotency: Boolean; var CreatedLpNos: List of [Code[20]]; var Replayed: Boolean)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        Item: Record Item;
        WarehouseEntry: Record "Warehouse Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        AllocatedQuantity: Decimal;
        RequestedQuantity: Decimal;
        AvailableQuantity: Decimal;
        SourceBinCode: Code[20];
        CheckedBinCodes: List of [Code[20]];
        Index: Integer;
    begin
        Clear(CreatedLpNos);
        Replayed := false;
        if LpCount <= 0 then
            Error('Oluşturulacak LP adedi sıfırdan büyük olmalıdır.');
        if LpCount > 100 then
            Error('Tek işlemde en fazla 100 LP oluşturulabilir.');
        if QuantityPerLp <= 0 then
            Error('LP başına miktar sıfırdan büyük olmalıdır.');

        // Keep the source balance stable until the complete LP set exists. A
        // shipment/consumption posting must not reduce Remaining Quantity
        // between validation and the last LP line being linked.
        ItemLedgerEntry.LockTable();
        ItemLedgerEntry.Get(ItemLedgerEntryNo);
        if ItemLedgerEntry."Location Code" = '' then
            Error('%1 numaralı Madde Defter Girişinde lokasyon kodu yoktur.', ItemLedgerEntryNo);
        if ItemLedgerEntry."Variant Code" <> '' then
            Error(
                '%1 numaralı Madde Defter Girişi %2 varyantını içeriyor. Varyantlı stok için toplu LP oluşturma desteklenmiyor.',
                ItemLedgerEntryNo, ItemLedgerEntry."Variant Code");

        // Both tables stay locked until every LP line is inserted. Two
        // terminals therefore cannot allocate the same loose quantity.
        LPHeader.LockTable();
        // LP satırları da işlem sonuna kadar kilitli kalır; aynı stok iki
        // terminal tarafından aynı anda LP'lere ayrılamaz.
        LPLine.LockTable();
        if UseIdempotency then
            if LoadExistingBulkBuildRequest(
                RequestId, ItemLedgerEntryNo, TemplateCode, BinCode, LpCount,
                QuantityPerLp, CreatedLpNos)
            then begin
                // A request created by an older package may already have the
                // exact LP-line source link but no visible ILE LP reference.
                RefreshItemLedgerEntryLpReferences(ItemLedgerEntryNo);
                Replayed := true;
                exit;
            end;

        if ItemLedgerEntry."Remaining Quantity" <= 0 then
            Error('%1 numaralı Madde Defter Girişinde kullanılabilir miktar yoktur.', ItemLedgerEntryNo);
        Item.Get(ItemLedgerEntry."Item No.");
        if (ItemLedgerEntry."Serial No." <> '') and ((LpCount <> 1) or (QuantityPerLp <> 1)) then
            Error('Seri takipli %1 maddesi yalnız 1 adetlik tek LP olarak oluşturulabilir.', ItemLedgerEntry."Item No.");

        AllocatedQuantity := AllocatedQuantityForItemLedgerEntry(ItemLedgerEntryNo);
        AvailableQuantity := ItemLedgerEntry."Remaining Quantity" - AllocatedQuantity;
        RequestedQuantity := LpCount * QuantityPerLp;
        if RequestedQuantity > AvailableQuantity then
            Error(
                '%1 numaralı Madde Defter Girişinde LP''ye ayrılabilir miktar %2, istenen miktar %3''tür.',
                ItemLedgerEntryNo, AvailableQuantity, RequestedQuantity);

        // Raf seçildiyse tüm miktar o raftan gelmelidir. Raf boş bırakıldıysa
        // aynı ürün/lotun serbest miktarı bütün raflardan birlikte kullanılır.
        // Bir LP birkaç raftan dolarsa ürünler gerçek ambar hareketleriyle o
        // LP'nin seçilen hedef rafında birleştirilir.
        WarehouseEntry.LockTable();
        if BinCode <> '' then begin
            EnsureLooseStockAvailable(
                ItemLedgerEntry."Location Code", BinCode, ItemLedgerEntry."Item No.",
                ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", RequestedQuantity);
        end else begin
            AvailableQuantity := TotalLooseStockAvailable(
                ItemLedgerEntry."Location Code", ItemLedgerEntry."Item No.",
                ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.");
            if AvailableQuantity < RequestedQuantity then
                Error(
                    '%1 ürününün raflardaki LP''ye atanmamış toplam stoku %2, istenen miktar %3''tür.',
                    ItemLedgerEntry."Item No.", AvailableQuantity, RequestedQuantity);
        end;

        if UseIdempotency then
            InsertBulkBuildRequest(
                RequestId, ItemLedgerEntryNo, TemplateCode,
                ItemLedgerEntry."Location Code", BinCode, LpCount, QuantityPerLp);

        for Index := 1 to LpCount do begin
            BuildOneFromItemLedgerEntry(
                ItemLedgerEntry, Item, TemplateCode, BinCode, QuantityPerLp,
                RequestId, UseIdempotency, CheckedBinCodes, LPHeader);
            CreatedLpNos.Add(LPHeader."No.");
        end;

        // A pure bin movement can change Warehouse Entry without changing the
        // source ILE. Take an update lock for the final balance read and prove
        // that all active LP allocations still fit the current bin stock. A
        // concurrent move that consumed too much loose stock rolls this entire
        // LP batch back; later app-mediated moves see the committed LPs and are
        // rejected by the same loose-stock rule.
        foreach SourceBinCode in CheckedBinCodes do
            EnsureLooseStockAvailable(
                ItemLedgerEntry."Location Code", SourceBinCode, ItemLedgerEntry."Item No.",
                ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", 0);

        // Keep the standard Item Ledger Entry as exactly one unchanged stock
        // movement.  Only our reference fields are refreshed: one active LP
        // is shown in "LP No."; several LPs are shown in "LP No.leri".
        RefreshItemLedgerEntryLpReferences(ItemLedgerEntryNo);

        if UseIdempotency then
            CompleteBulkBuildRequest(RequestId);
    end;

    local procedure BuildOneFromItemLedgerEntry(var ItemLedgerEntry: Record "Item Ledger Entry"; Item: Record Item; TemplateCode: Code[20]; ExplicitBinCode: Code[20]; QuantityPerLp: Decimal; RequestId: Guid; UseIdempotency: Boolean; var CheckedBinCodes: List of [Code[20]]; var LPHeader: Record "DOPSWHS LP Header")
    var
        Bin: Record Bin;
        TargetBinCode: Code[20];
        SourceBinCode: Code[20];
        AvailableInBin: Decimal;
        QuantityFromBin: Decimal;
        RemainingToFill: Decimal;
    begin
        TargetBinCode := ExplicitBinCode;
        if TargetBinCode = '' then begin
            Bin.SetRange("Location Code", ItemLedgerEntry."Location Code");
            if Bin.FindSet() then
                repeat
                    if LooseStockAvailableInBin(
                        ItemLedgerEntry."Location Code", Bin.Code, ItemLedgerEntry."Item No.",
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.") > 0
                    then
                        TargetBinCode := Bin.Code;
                until (Bin.Next() = 0) or (TargetBinCode <> '');
        end;
        if TargetBinCode = '' then
            Error('%1 ürünü için LP''ye atanabilecek raf stoku bulunamadı.', ItemLedgerEntry."Item No.");

        EnsureBinReadyForStockLp(ItemLedgerEntry."Location Code", TargetBinCode, CheckedBinCodes);
        Build(TemplateCode, ItemLedgerEntry."Location Code", TargetBinCode, LPHeader);
        if UseIdempotency then
            LPHeader."Bulk Build Request ID" := RequestId;
        LPHeader."Bulk Source ILE No." := ItemLedgerEntry."Entry No.";
        LPHeader."Bulk Source Bin Code" := TargetBinCode;
        LPHeader.Modify(true);

        if ExplicitBinCode <> '' then begin
            AddItemLedgerEntryPartToLp(
                LPHeader, ItemLedgerEntry, Item, ExplicitBinCode, QuantityPerLp);
        end else begin
            RemainingToFill := QuantityPerLp;
            Bin.Reset();
            Bin.SetRange("Location Code", ItemLedgerEntry."Location Code");
            if Bin.FindSet() then
                repeat
                    SourceBinCode := Bin.Code;
                    AvailableInBin := LooseStockAvailableInBin(
                        ItemLedgerEntry."Location Code", SourceBinCode, ItemLedgerEntry."Item No.",
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.");
                    if AvailableInBin > 0 then begin
                        QuantityFromBin := AvailableInBin;
                        if QuantityFromBin > RemainingToFill then
                            QuantityFromBin := RemainingToFill;
                        EnsureBinReadyForStockLp(
                            ItemLedgerEntry."Location Code", SourceBinCode, CheckedBinCodes);
                        AddItemLedgerEntryPartToLp(
                            LPHeader, ItemLedgerEntry, Item, SourceBinCode, QuantityFromBin);
                        RemainingToFill -= QuantityFromBin;
                    end;
                until (Bin.Next() = 0) or (RemainingToFill <= 0.00001);
            if RemainingToFill > 0.00001 then
                Error(
                    '%1 LP''si doldurulamadı. Eksik miktar: %2.',
                    LPHeader."No.", RemainingToFill);
        end;

        LPHeader."Planned Quantity" := QuantityPerLp;
        LPHeader.Modify(true);
        Stop(LPHeader, false);
    end;

    local procedure AddItemLedgerEntryPartToLp(var LPHeader: Record "DOPSWHS LP Header"; ItemLedgerEntry: Record "Item Ledger Entry"; Item: Record Item; SourceBinCode: Code[20]; Quantity: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        AddLineFromBin(
            LPHeader,
            ItemLedgerEntry."Item No.",
            Item."Base Unit of Measure",
            Quantity,
            ItemLedgerEntry."Lot No.",
            ItemLedgerEntry."Serial No.",
            SourceBinCode,
            CopyStr(UserId(), 1, 50));

        LPLine.SetRange("LP No.", LPHeader."No.");
        if not LPLine.FindLast() then
            Error('%1 LP satırı oluşturulamadı.', LPHeader."No.");
        LPLine."Source Document No." := ItemLedgerEntry."Document No.";
        LPLine."Source Document Line No." := ItemLedgerEntry."Entry No.";
        LPLine."Source Document Quantity" := ItemLedgerEntry.Quantity;
        LPLine."Source Item Ledger Entry No." := ItemLedgerEntry."Entry No.";
        LPLine.Modify(true);
    end;

    local procedure EnsureBinReadyForStockLp(LocationCode: Code[10]; BinCode: Code[20]; var CheckedBinCodes: List of [Code[20]])
    begin
        if CheckedBinCodes.Contains(BinCode) then
            exit;
        EnsureNoUnresolvedPlannedLPs(LocationCode, BinCode);
        CheckedBinCodes.Add(BinCode);
    end;

    /// <summary>
    /// Adds an item to an open LP and, when the source bin differs from the LP bin, posts the real
    /// Business Central bin-to-bin movement first. This keeps Bin Content and LP contents aligned.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure AddLineFromBin(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; UoM: Code[10]; Qty: Decimal; LotNo: Code[50]; SerialNo: Code[50]; SourceBinCode: Code[20]; OperatorUserId: Code[50])
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        ItemTrackingCode: Record "Item Tracking Code";
        SourceBin: Record Bin;
        SourceBinInOtherLocation: Record Bin;
        TargetBin: Record Bin;
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        EffectiveUoM: Code[10];
        MovementQty: Decimal;
    begin
        LP.LockTable();
        LP.Get(LP."No.");
        OnBeforeAddLine(LP, ItemNo, UoM, Qty);
        RequireStatus(LP, LP.Status::Open);
        if ItemNo = '' then
            Error('Madde numarası zorunludur.');
        if Qty <= 0 then
            Error('Miktar sıfırdan büyük olmalıdır.');
        LP.TestField("Location Code");
        LP.TestField("Bin Code");
        if SourceBinCode = '' then
            Error('Kaynak raf zorunludur.');

        Item.Get(ItemNo);
        if (Item."Item Tracking Code" <> '') and ItemTrackingCode.Get(Item."Item Tracking Code") then begin
            if (ItemTrackingCode."Lot Specific Tracking" or ItemTrackingCode."Lot Warehouse Tracking") and (LotNo = '') then
                Error('%1 lot takipli maddesi için lot numarası zorunludur. Stoktaki lotlardan birini seçin.', ItemNo);
            if (ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking") and (SerialNo = '') then
                Error('%1 seri takipli maddesi için seri numarası zorunludur. Stoktaki seri numarasını okutun.', ItemNo);
        end;
        EffectiveUoM := UoM;
        if EffectiveUoM = '' then
            EffectiveUoM := Item."Base Unit of Measure";
        MovementQty := Qty;
        if EffectiveUoM <> Item."Base Unit of Measure" then begin
            ItemUoM.Get(ItemNo, EffectiveUoM);
            if ItemUoM."Qty. per Unit of Measure" <= 0 then
                Error('%1 maddesinin %2 birimi için birim başına miktar sıfırdan büyük olmalıdır.', ItemNo, EffectiveUoM);
            MovementQty := Qty * ItemUoM."Qty. per Unit of Measure";
        end;
        if (SerialNo <> '') and (MovementQty <> 1) then
            Error('%1 seri numarası tek bir temel birimi temsil eder; miktar 1 olmalıdır.', SerialNo);

        if not SourceBin.Get(LP."Location Code", SourceBinCode) then begin
            SourceBinInOtherLocation.SetRange(Code, SourceBinCode);
            if SourceBinInOtherLocation.FindFirst() then
                Error(
                    'Source bin %1 belongs to location %2 but LP %3 belongs to location %4. Cross-location LP line assignment is not allowed.',
                    SourceBinCode, SourceBinInOtherLocation."Location Code", LP."No.", LP."Location Code");
            Error('%1 kaynak rafı %2 lokasyonunda bulunamadı.', SourceBinCode, LP."Location Code");
        end;
        if not TargetBin.Get(LP."Location Code", LP."Bin Code") then
            Error('%1 LP hedef rafı %2 lokasyonunda bulunamadı.', LP."Bin Code", LP."Location Code");

        EnsureLooseStockAvailable(LP."Location Code", SourceBinCode, ItemNo, LotNo, SerialNo, MovementQty);

        LogMutation('LP.AddLineFromBin');
        if SourceBinCode <> LP."Bin Code" then
            MovementMgmt.AdHocMoveTrackedAtLocation(
                LP."Location Code", SourceBinCode, LP."Bin Code", ItemNo, LP."No.",
                MovementQty, OperatorUserId, LotNo, SerialNo);

        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine.Validate("Item No.", ItemNo);
        LPLine."Unit of Measure" := EffectiveUoM;
        LPLine.Validate(Quantity, Qty);
        LPLine."Lot No." := LotNo;
        LPLine."Serial No." := SerialNo;
        LPLine."Source Bin Code" := SourceBinCode;
        LPLine.Insert(true);
        WriteToLedger(LP, LPActionItemAdded(), SourceBinCode, LP."Bin Code", Qty, ItemNo, LotNo + SerialNo, '');
        OnAfterAddLine(LP, LPLine);
    end;

    /// <summary>
    /// Moves every item line carried by an LP to another bin and updates the LP header in the same
    /// server transaction. The mobile client must never post one movement per HTTP request and then
    /// patch the header: a later failure would leave Bin Content and the LP card out of sync.
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure MoveToBin(var LP: Record "DOPSWHS LP Header"; TargetBinCode: Code[20]; OperatorUserId: Code[50])
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        SourceBin: Record Bin;
        TargetBin: Record Bin;
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        SourceBinCode: Code[20];
        EffectiveUoM: Code[10];
        MovementQty: Decimal;
        TotalQty: Decimal;
    begin
        LP.LockTable();
        LP.Get(LP."No.");

        if OperatorUserId = '' then
            Error('%1 LP numarasını taşımak için operatör kullanıcı kimliği zorunludur.', LP."No.");
        if not (LP.Status in [LP.Status::Open, LP.Status::Built]) then
            Error('%1 LP numarası %2 durumundayken taşınamaz. Önce belge atamasını kaldırın.', LP."No.", LP.Status);
        LP.TestField("Location Code");
        if TargetBinCode = '' then
            Error('%1 LP numarasını taşımak için hedef raf zorunludur.', LP."No.");

        // Toplu üretimde LP fiziksel bir rafa yerleştirilmeden hazırlanabilir.
        // İlk raf atamasında taşınacak stok bulunmadığı için depo hareketi
        // üretme; yalnız boş LP başlığını ve hareket izini atomik güncelle.
        if LP."Bin Code" = '' then begin
            if not TargetBin.Get(LP."Location Code", TargetBinCode) then
                Error('%1 hedef rafı %2 lokasyonunda bulunamadı.', TargetBinCode, LP."Location Code");
            LPLine.SetRange("LP No.", LP."No.");
            if not LPLine.IsEmpty() then
                Error('%1 LP numarasında satır bulunduğu için ilk raf ataması yapılamaz.', LP."No.");

            LogMutation('LP.AssignInitialBin');
            LP.Validate("Bin Code", TargetBinCode);
            LP.Modify(true);
            WriteToLedger(LP, LPActionTransferOut(), '', TargetBinCode, 0, '', '', 'BIN-ASSIGN');
            exit;
        end;

        SourceBinCode := LP."Bin Code";
        if SourceBinCode = TargetBinCode then
            Error('%1 LP numarası zaten %2 rafındadır.', LP."No.", TargetBinCode);
        if not SourceBin.Get(LP."Location Code", SourceBinCode) then
            Error('%1 kaynak rafı %2 lokasyonunda bulunamadı.', SourceBinCode, LP."Location Code");
        if not TargetBin.Get(LP."Location Code", TargetBinCode) then
            Error('%1 hedef rafı %2 lokasyonunda bulunamadı.', TargetBinCode, LP."Location Code");

        LPLine.SetRange("LP No.", LP."No.");
        if LPLine.FindSet() then
            repeat
                if LPLine."Child LP No." <> '' then
                    Error('%1 LP numarası iç içe %2 LP numarasını içeriyor. Ana LP taşınmadan önce bağlantıyı kaldırın.', LP."No.", LPLine."Child LP No.");
                if LPLine."Item No." = '' then
                    Error('%1 LP numarasının %2 satırında madde bulunmadığı için taşınamaz.', LP."No.", LPLine."Line No.");
                if LPLine."Variant Code" <> '' then
                    Error('%1 maddesinin %2 varyantı için LP hareketi desteklenmiyor. Standart depo hareketini kullanın.', LPLine."Item No.", LPLine."Variant Code");
                if LPLine.Quantity <= 0 then
                    Error('%1 LP numarasının %2 satırındaki miktar sıfırdan büyük olmalıdır.', LP."No.", LPLine."Line No.");

                Item.Get(LPLine."Item No.");
                EffectiveUoM := LPLine."Unit of Measure";
                if EffectiveUoM = '' then
                    EffectiveUoM := Item."Base Unit of Measure";
                MovementQty := LPLine.Quantity;
                if EffectiveUoM <> Item."Base Unit of Measure" then begin
                    ItemUoM.Get(LPLine."Item No.", EffectiveUoM);
                    if ItemUoM."Qty. per Unit of Measure" <= 0 then
                        Error('%1 maddesinin %2 birimi için birim başına miktar sıfırdan büyük olmalıdır.', LPLine."Item No.", EffectiveUoM);
                    MovementQty := LPLine.Quantity * ItemUoM."Qty. per Unit of Measure";
                end;
                if (LPLine."Serial No." <> '') and (MovementQty <> 1) then
                    Error('%1 seri numarası tek bir temel birimi temsil eder; miktar 1 olmalıdır.', LPLine."Serial No.");

                MovementMgmt.AdHocMoveTrackedAtLocation(
                    LP."Location Code", SourceBinCode, TargetBinCode, LPLine."Item No.", LP."No.",
                    MovementQty, OperatorUserId, LPLine."Lot No.", LPLine."Serial No.");
                TotalQty += LPLine.Quantity;
            until LPLine.Next() = 0;

        LogMutation('LP.MoveToBin');
        LP.Validate("Bin Code", TargetBinCode);
        LP.Modify(true);
        WriteToLedger(LP, LPActionTransferOut(), SourceBinCode, TargetBinCode, TotalQty, '', '', 'BIN-MOVE');
    end;

    procedure RemoveLine(var LPLine: Record "DOPSWHS LP Line")
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LPLine."LP No.");
        OnBeforeRemoveLine(LPLine);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.RemoveLine');
        WriteToLedger(LP, LPActionItemRemoved(), LP."Bin Code", '', LPLine.Quantity, LPLine."Item No.", LPLine."Lot No." + LPLine."Serial No.", '');
        LPLine.Delete(true);
        OnAfterRemoveLine(LP);
    end;

    procedure Assign(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    begin
        OnBeforeAssign(LP, DocType, DocNo);
        RequireStatus(LP, LP.Status::Built);
        LogMutation('LP.Assign');
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := DocType;
        LP."Assigned Document No." := DocNo;
        LP.Modify(true);
        WriteToLedger(LP, LPActionAssigned(), LP."Bin Code", LP."Bin Code", 0, '', '', Format(DocType) + ':' + DocNo);
        OnAfterAssign(LP);
    end;

    procedure Release(var LP: Record "DOPSWHS LP Header")
    begin
        OnBeforeRelease(LP);
        RequireStatus(LP, LP.Status::Assigned);
        LogMutation('LP.Release');
        LP.Status := LP.Status::Built;
        Clear(LP."Assigned Document Type");
        LP."Assigned Document No." := '';
        LP.Modify(true);
        WriteToLedger(LP, LPActionReleased(), LP."Bin Code", LP."Bin Code", 0, '', '', '');
        OnAfterRelease(LP);
    end;

    procedure Transfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header"; LineSelections: List of [Integer]; QtyByLine: Dictionary of [Integer, Decimal])
    var
        SourceLine: Record "DOPSWHS LP Line";
        TargetLine: Record "DOPSWHS LP Line";
        LineNo: Integer;
        TransferQty: Decimal;
    begin
        OnBeforeTransfer(SourceLP, TargetLP);
        if SourceLP."No." = TargetLP."No." then
            Error('Kaynak ve hedef LP aynı olamaz: %1.', SourceLP."No.");
        if not (SourceLP.Status in [SourceLP.Status::Open, SourceLP.Status::Built]) then
            Error('Kaynak LP %1 açık veya tamamlanmış durumda olmalıdır. Mevcut durum: %2.', SourceLP."No.", SourceLP.Status);
        if not (TargetLP.Status in [TargetLP.Status::Open, TargetLP.Status::Built]) then
            Error('Hedef LP %1 açık veya tamamlanmış durumda olmalıdır. Mevcut durum: %2.', TargetLP."No.", TargetLP.Status);
        SourceLP.TestField("Location Code");
        TargetLP.TestField("Location Code");
        if SourceLP."Location Code" <> TargetLP."Location Code" then
            Error(
                'LP transferi lokasyonlar arasında yapılamaz. Kaynak LP %1, %2; hedef LP %3, %4 lokasyonundadır.',
                SourceLP."No.", SourceLP."Location Code", TargetLP."No.", TargetLP."Location Code");
        if SourceLP."Bin Code" <> TargetLP."Bin Code" then
            Error(
                'LP içerik transferi için iki LP aynı rafta olmalıdır. Önce depo hareketiyle LP''yi taşıyın (%1 -> %2).',
                SourceLP."Bin Code", TargetLP."Bin Code");
        LogMutation('LP.Transfer');
        foreach LineNo in LineSelections do begin
            SourceLine.Get(SourceLP."No.", LineNo);
            if not QtyByLine.Get(LineNo, TransferQty) then
                TransferQty := SourceLine.Quantity;
            if (TransferQty <= 0) or (TransferQty > SourceLine.Quantity) then
                Error('%1 satırı için transfer miktarı geçersizdir.', LineNo);

            TargetLine.Init();
            TargetLine."LP No." := TargetLP."No.";
            TargetLine.Validate("Item No.", SourceLine."Item No.");
            TargetLine."Variant Code" := SourceLine."Variant Code";
            TargetLine."Unit of Measure" := SourceLine."Unit of Measure";
            TargetLine.Validate(Quantity, TransferQty);
            TargetLine."Lot No." := SourceLine."Lot No.";
            TargetLine."Serial No." := SourceLine."Serial No.";
            TargetLine."Package No." := SourceLine."Package No.";
            TargetLine."Expiration Date" := SourceLine."Expiration Date";
            TargetLine."Source Bin Code" := SourceLine."Source Bin Code";
            TargetLine."Source Document Type" := SourceLine."Source Document Type";
            TargetLine."Source Document No." := SourceLine."Source Document No.";
            TargetLine."Source Document Line No." := SourceLine."Source Document Line No.";
            TargetLine."Source Document Quantity" := SourceLine."Source Document Quantity";
            TargetLine."Source Item Ledger Entry No." := SourceLine."Source Item Ledger Entry No.";
            TargetLine.Insert(true);

            SourceLine.Validate(Quantity, SourceLine.Quantity - TransferQty);
            if SourceLine.Quantity = 0 then
                SourceLine.Delete(true)
            else
                SourceLine.Modify(true);

            WriteToLedger(SourceLP, LPActionTransferOut(), SourceLP."Bin Code", TargetLP."Bin Code", TransferQty, SourceLine."Item No.", SourceLine."Lot No.", TargetLP."No.");
            WriteToLedger(TargetLP, LPActionTransferIn(), SourceLP."Bin Code", TargetLP."Bin Code", TransferQty, SourceLine."Item No.", SourceLine."Lot No.", SourceLP."No.");
        end;
        OnAfterTransfer(SourceLP, TargetLP);
    end;

    /// <summary>
    /// Moves the quantity physically picked from a source LP into the shipping LP.
    /// The standard warehouse pick posts the real bin movement; this procedure only
    /// keeps the two LP contents in step with that movement, so it must run in the
    /// same transaction as pick registration.
    /// </summary>
    procedure TransferPickedQuantity(SourceLpNo: Code[20]; TargetLpNo: Code[20]; PickNo: Code[20]; PickLineNo: Integer; WhseDocumentNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; PickUom: Code[10]; PickQty: Decimal; PickQtyBase: Decimal; LotNo: Code[50]; SerialNo: Code[50]; SourceBinCode: Code[20]; TargetBinCode: Code[20])
    var
        SourceLP: Record "DOPSWHS LP Header";
        TargetLP: Record "DOPSWHS LP Header";
        SourceLine: Record "DOPSWHS LP Line";
        TargetLine: Record "DOPSWHS LP Line";
        TargetBin: Record Bin;
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        QtyPerUoM: Decimal;
        AvailableBaseQty: Decimal;
        TransferBaseQty: Decimal;
        TransferQty: Decimal;
        RemainingBaseQty: Decimal;
        RelatedDocument: Code[40];
    begin
        if TargetLpNo = '' then
            Error('Sevk LP numarası zorunludur.');
        if PickQtyBase <= 0 then
            exit;

        TargetLP.LockTable();
        TargetLP.Get(TargetLpNo);
        if not (TargetLP.Status in [TargetLP.Status::Open, TargetLP.Status::Built, TargetLP.Status::Assigned]) then
            Error('%1 sevk LP numarası aktif değildir. Mevcut durum: %2.', TargetLP."No.", TargetLP.Status);
        if (TargetLP.Status = TargetLP.Status::Assigned) and
           ((TargetLP."Assigned Document Type" <> TargetLP."Assigned Document Type"::WhsePick) or
            (TargetLP."Assigned Document No." <> PickNo))
        then
            Error('%1 sevk LP numarası başka bir belgeye atanmıştır.', TargetLP."No.");
        TargetLP.TestField("Location Code");
        if TargetBinCode = '' then
            Error('%1 sevk LP numarası için hedef raf bulunamadı.', TargetLP."No.");
        if not TargetBin.Get(TargetLP."Location Code", TargetBinCode) then
            Error('%1 hedef rafı %2 lokasyonunda bulunamadı.', TargetBinCode, TargetLP."Location Code");
        if TargetLP."Bin Code" = '' then begin
            TargetLP.Validate("Bin Code", TargetBinCode);
            TargetLP.Modify(true);
        end else
            if TargetLP."Bin Code" <> TargetBinCode then
                Error(
                    '%1 sevk LP numarası %2 rafındadır; aynı LP %3 rafına da yerleştirilemez.',
                    TargetLP."No.", TargetLP."Bin Code", TargetBinCode);

        RelatedDocument := CopyStr('PICK:' + PickNo + ':' + Format(PickLineNo), 1, MaxStrLen(RelatedDocument));

        // Loose stock has no source LP to split. It still has to be recorded in
        // the shipping LP so shipment posting consumes the container actually sent.
        if SourceLpNo = '' then begin
            TargetLine.Init();
            TargetLine."LP No." := TargetLP."No.";
            TargetLine.Validate("Item No.", ItemNo);
            TargetLine."Variant Code" := VariantCode;
            TargetLine."Unit of Measure" := PickUom;
            TargetLine.Validate(Quantity, PickQty);
            TargetLine."Lot No." := LotNo;
            TargetLine."Serial No." := SerialNo;
            TargetLine."Source Bin Code" := SourceBinCode;
            TargetLine."Source Document Type" := TargetLine."Source Document Type"::WhsePick;
            TargetLine."Source Document No." := PickNo;
            TargetLine."Source Document Line No." := PickLineNo;
            TargetLine."Source Document Quantity" := PickQty;
            TargetLine.Insert(true);
            WriteToLedger(TargetLP, LPActionTransferIn(), SourceBinCode, TargetBinCode, PickQty, ItemNo, LotNo + SerialNo, RelatedDocument);
            exit;
        end;

        if SourceLpNo = TargetLpNo then
            Error('Kaynak LP ile sevk LP aynı olamaz: %1.', SourceLpNo);
        SourceLP.Get(SourceLpNo);
        if not (SourceLP.Status in [SourceLP.Status::Open, SourceLP.Status::Built, SourceLP.Status::Assigned]) then
            Error('%1 kaynak LP numarası aktif değildir. Mevcut durum: %2.', SourceLP."No.", SourceLP.Status);
        if (SourceLP.Status = SourceLP.Status::Assigned) and
           not (((SourceLP."Assigned Document Type" = SourceLP."Assigned Document Type"::WhsePick) and
                 (SourceLP."Assigned Document No." = PickNo)) or
                ((SourceLP."Assigned Document Type" = SourceLP."Assigned Document Type"::WhseShipment) and
                 (SourceLP."Assigned Document No." = WhseDocumentNo)))
        then
            Error('%1 kaynak LP numarası başka bir belgeye atanmıştır.', SourceLP."No.");
        if SourceLP."Location Code" <> TargetLP."Location Code" then
            Error(
                'Kaynak LP %1 ile sevk LP %2 aynı lokasyonda olmalıdır.',
                SourceLP."No.", TargetLP."No.");
        if SourceLP."Bin Code" <> SourceBinCode then
            Error(
                '%1 kaynak LP numarası artık %2 rafındadır; pick satırındaki %3 rafından bölünemez.',
                SourceLP."No.", SourceLP."Bin Code", SourceBinCode);

        Item.Get(ItemNo);
        RemainingBaseQty := PickQtyBase;
        SourceLine.SetRange("LP No.", SourceLP."No.");
        SourceLine.SetRange("Item No.", ItemNo);
        SourceLine.SetRange("Variant Code", VariantCode);
        SourceLine.SetRange("Lot No.", LotNo);
        SourceLine.SetRange("Serial No.", SerialNo);
        SourceLine.SetFilter(Quantity, '>0');
        if SourceLine.FindSet(true) then
            repeat
                QtyPerUoM := 1;
                if (SourceLine."Unit of Measure" <> '') and
                   (SourceLine."Unit of Measure" <> Item."Base Unit of Measure")
                then begin
                    if not ItemUoM.Get(ItemNo, SourceLine."Unit of Measure") then
                        Error('%1 maddesinin %2 ölçü birimi bulunamadı.', ItemNo, SourceLine."Unit of Measure");
                    QtyPerUoM := ItemUoM."Qty. per Unit of Measure";
                    if QtyPerUoM <= 0 then
                        Error('%1 maddesinin %2 ölçü birimi dönüşümü geçersizdir.', ItemNo, SourceLine."Unit of Measure");
                end;

                AvailableBaseQty := Round(SourceLine.Quantity * QtyPerUoM, 0.00001);
                TransferBaseQty := AvailableBaseQty;
                if TransferBaseQty > RemainingBaseQty then
                    TransferBaseQty := RemainingBaseQty;
                TransferQty := Round(TransferBaseQty / QtyPerUoM, 0.00001);
                if TransferQty > 0 then begin
                    TargetLine.Init();
                    TargetLine."LP No." := TargetLP."No.";
                    TargetLine.Validate("Item No.", SourceLine."Item No.");
                    TargetLine."Variant Code" := SourceLine."Variant Code";
                    TargetLine."Unit of Measure" := SourceLine."Unit of Measure";
                    TargetLine.Validate(Quantity, TransferQty);
                    TargetLine."Lot No." := SourceLine."Lot No.";
                    TargetLine."Serial No." := SourceLine."Serial No.";
                    TargetLine."Package No." := SourceLine."Package No.";
                    TargetLine."Expiration Date" := SourceLine."Expiration Date";
                    TargetLine."Source Bin Code" := SourceLP."Bin Code";
                    TargetLine."Source Document Type" := TargetLine."Source Document Type"::WhsePick;
                        TargetLine."Source Document No." := PickNo;
                        TargetLine."Source Document Line No." := PickLineNo;
                        TargetLine."Source Document Quantity" := TransferQty;
                        TargetLine."Source Item Ledger Entry No." := SourceLine."Source Item Ledger Entry No.";
                        TargetLine.Insert(true);

                    SourceLine.Validate(Quantity, Round(SourceLine.Quantity - TransferQty, 0.00001));
                    if SourceLine.Quantity = 0 then
                        SourceLine.Delete(true)
                    else
                        SourceLine.Modify(true);

                    WriteToLedger(SourceLP, LPActionTransferOut(), SourceBinCode, TargetBinCode, TransferQty, ItemNo, LotNo + SerialNo, RelatedDocument);
                    WriteToLedger(TargetLP, LPActionTransferIn(), SourceBinCode, TargetBinCode, TransferQty, ItemNo, LotNo + SerialNo, RelatedDocument);
                    RemainingBaseQty := Round(RemainingBaseQty - TransferBaseQty, 0.00001);
                end;
            until (SourceLine.Next() = 0) or (RemainingBaseQty <= 0.00001);

        if RemainingBaseQty > 0.00001 then
            Error(
                '%1 kaynak LP numarasında %2 ürünü ve lot %3 için toplanan %4 miktar bulunamadı.',
                SourceLP."No.", ItemNo, LotNo, PickQty);

        // The shipment now owns the newly created shipping LP. Any remainder on
        // the source pallet must be free for the next operation instead of
        // staying reserved to the pick/shipment that already removed its share.
        if SourceLP.Status = SourceLP.Status::Assigned then
            Release(SourceLP);
    end;

    /// <summary>
    /// Splits one handled warehouse-pick quantity across every eligible source
    /// LP in the Take bin. A scanned/preferred LP is consumed first; the
    /// remainder follows LP number order inside that bin. Quantity not represented
    /// by an active LP is recorded as loose stock in the shipping LP.
    ///
    /// The standard Warehouse Activity lines are deliberately left untouched:
    /// this is only the LP-content side of the same atomic pick registration.
    /// </summary>
    procedure TransferPickedQuantityFromAvailableLps(PreferredSourceLpNo: Code[20]; TargetLpNo: Code[20]; PickNo: Code[20]; PickLineNo: Integer; WhseDocumentNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; PickUom: Code[10]; PickQtyBase: Decimal; LotNo: Code[50]; SerialNo: Code[50]; SourceBinCode: Code[20]; TargetBinCode: Code[20]) SourceLpCount: Integer
    var
        SourceLP: Record "DOPSWHS LP Header";
        TargetLP: Record "DOPSWHS LP Header";
        AvailableBaseQty: Decimal;
        TransferBaseQty: Decimal;
        RemainingBaseQty: Decimal;
        PickQtyPerUom: Decimal;
        LooseAvailableBaseQty: Decimal;
    begin
        if PickQtyBase <= QtyTolerance() then
            exit(0);
        if TargetLpNo = '' then
            Error('Sevk LP numarası zorunludur.');
        TargetLP.Get(TargetLpNo);
        PickQtyPerUom := QtyPerUnitOfMeasure(ItemNo, PickUom);
        RemainingBaseQty := PickQtyBase;
        // Snapshot before LP metadata is moved. Otherwise the just-transferred
        // source quantity would temporarily look loose until standard BC posts
        // the warehouse activity in the same transaction.
        LooseAvailableBaseQty := LoosePickBaseQtyAvailable(
            TargetLP."Location Code", SourceBinCode, ItemNo, VariantCode, LotNo, SerialNo,
            TargetLpNo, PickNo);

        // An explicitly scanned LP is a starting preference, not a promise that
        // one pallet can satisfy the whole sales quantity.
        if PreferredSourceLpNo <> '' then begin
            AvailableBaseQty := AvailablePickBaseQtyInLp(
                PreferredSourceLpNo, ItemNo, VariantCode, LotNo, SerialNo);
            if AvailableBaseQty <= QtyTolerance() then
                Error(
                    '%1 kaynak LP numarasında %2 ürünü ve lot %3 için toplanabilir miktar bulunamadı.',
                    PreferredSourceLpNo, ItemNo, LotNo);
            TransferBaseQty := MinimumDecimal(AvailableBaseQty, RemainingBaseQty);
            TransferPickedQuantity(
                PreferredSourceLpNo, TargetLpNo, PickNo, PickLineNo, WhseDocumentNo,
                ItemNo, VariantCode, PickUom,
                Round(TransferBaseQty / PickQtyPerUom, 0.00001), TransferBaseQty,
                LotNo, SerialNo, SourceBinCode, TargetBinCode);
            RemainingBaseQty := Round(RemainingBaseQty - TransferBaseQty, 0.00001);
            SourceLpCount += 1;
        end;

        // The Take line already fixes the physical source bin. LP No. order is
        // deterministic inside that bin; the pick lines themselves are produced
        // and displayed in Shelf/Bin (warehouse walking) order.
        SourceLP.SetRange("Location Code", TargetLP."Location Code");
        SourceLP.SetRange("Bin Code", SourceBinCode);
        SourceLP.SetFilter(Status, '%1|%2|%3', SourceLP.Status::Open, SourceLP.Status::Built, SourceLP.Status::Assigned);
        if SourceLP.FindSet() then
            repeat
                if (RemainingBaseQty > QtyTolerance()) and
                   (SourceLP."No." <> TargetLpNo) and
                   (SourceLP."No." <> PreferredSourceLpNo) and
                   SourceLpMaySupplyPick(SourceLP, PickNo, WhseDocumentNo)
                then begin
                    AvailableBaseQty := AvailablePickBaseQtyInLp(
                        SourceLP."No.", ItemNo, VariantCode, LotNo, SerialNo);
                    if AvailableBaseQty > QtyTolerance() then begin
                        TransferBaseQty := MinimumDecimal(AvailableBaseQty, RemainingBaseQty);
                        TransferPickedQuantity(
                            SourceLP."No.", TargetLpNo, PickNo, PickLineNo, WhseDocumentNo,
                            ItemNo, VariantCode, PickUom,
                            Round(TransferBaseQty / PickQtyPerUom, 0.00001), TransferBaseQty,
                            LotNo, SerialNo, SourceBinCode, TargetBinCode);
                        RemainingBaseQty := Round(RemainingBaseQty - TransferBaseQty, 0.00001);
                        SourceLpCount += 1;
                    end;
                end;
            until (SourceLP.Next() = 0) or (RemainingBaseQty <= QtyTolerance());

        // A warehouse bin may legitimately contain stock that has never been put
        // in an LP. Keep that residual in the shipping LP as loose stock; never
        // invent a source pallet for it.
        if RemainingBaseQty > LooseAvailableBaseQty + QtyTolerance() then
            Error(
                '%1 ürününün %2 rafındaki uygun kaynak LP ve serbest stok toplamı yetersizdir. Eksik taban miktar: %3. Başka belgeye ayrılmış LP miktarı kullanılmadı.',
                ItemNo, SourceBinCode, RemainingBaseQty - LooseAvailableBaseQty);
        if RemainingBaseQty > QtyTolerance() then
            TransferPickedQuantity(
                '', TargetLpNo, PickNo, PickLineNo, WhseDocumentNo,
                ItemNo, VariantCode, PickUom,
                Round(RemainingBaseQty / PickQtyPerUom, 0.00001), RemainingBaseQty,
                LotNo, SerialNo, SourceBinCode, TargetBinCode);
    end;

    local procedure AvailablePickBaseQtyInLp(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]) AvailableBaseQty: Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetRange("Serial No.", SerialNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                AvailableBaseQty += Round(
                    LPLine.Quantity * QtyPerUnitOfMeasure(ItemNo, LPLine."Unit of Measure"),
                    0.00001);
            until LPLine.Next() = 0;
    end;

    local procedure QtyPerUnitOfMeasure(ItemNo: Code[20]; UomCode: Code[10]): Decimal
    var
        Item: Record Item;
        ItemUom: Record "Item Unit of Measure";
    begin
        Item.Get(ItemNo);
        if (UomCode = '') or (UomCode = Item."Base Unit of Measure") then
            exit(1);
        if not ItemUom.Get(ItemNo, UomCode) then
            Error('%1 maddesinin %2 ölçü birimi bulunamadı.', ItemNo, UomCode);
        if ItemUom."Qty. per Unit of Measure" <= 0 then
            Error('%1 maddesinin %2 ölçü birimi dönüşümü geçersizdir.', ItemNo, UomCode);
        exit(ItemUom."Qty. per Unit of Measure");
    end;

    local procedure LoosePickBaseQtyAvailable(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; TargetLpNo: Code[20]; PickNo: Code[20]) LooseBaseQty: Decimal
    var
        BinContent: Record "Bin Content";
        WarehouseEntry: Record "Warehouse Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        TargetLP: Record "DOPSWHS LP Header";
        TargetLine: Record "DOPSWHS LP Line";
        PhysicalBaseQty: Decimal;
        AllocatedBaseQty: Decimal;
        PendingPickBaseQty: Decimal;
    begin
        if (LotNo <> '') or (SerialNo <> '') then begin
            WarehouseEntry.SetRange("Location Code", LocationCode);
            WarehouseEntry.SetRange("Bin Code", BinCode);
            WarehouseEntry.SetRange("Item No.", ItemNo);
            WarehouseEntry.SetRange("Variant Code", VariantCode);
            if LotNo <> '' then
                WarehouseEntry.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                WarehouseEntry.SetRange("Serial No.", SerialNo);
            if WarehouseEntry.FindSet() then
                repeat
                    PhysicalBaseQty += WarehouseEntry."Qty. (Base)";
                until WarehouseEntry.Next() = 0;
        end else begin
            BinContent.SetRange("Location Code", LocationCode);
            BinContent.SetRange("Bin Code", BinCode);
            BinContent.SetRange("Item No.", ItemNo);
            BinContent.SetRange("Variant Code", VariantCode);
            if BinContent.FindSet() then
                repeat
                    BinContent.CalcFields("Quantity (Base)");
                    PhysicalBaseQty += BinContent."Quantity (Base)";
                until BinContent.Next() = 0;
        end;

        // Every active LP is subtracted, including LPs assigned to other
        // documents. Their quantity can therefore never masquerade as loose
        // stock for the current shipment.
        LPHeader.SetRange("Location Code", LocationCode);
        LPHeader.SetRange("Bin Code", BinCode);
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LPHeader."No.");
                LPLine.SetRange("Item No.", ItemNo);
                LPLine.SetRange("Variant Code", VariantCode);
                if LotNo <> '' then
                    LPLine.SetRange("Lot No.", LotNo);
                if SerialNo <> '' then
                    LPLine.SetRange("Serial No.", SerialNo);
                LPLine.SetFilter(Quantity, '>0');
                if LPLine.FindSet() then
                    repeat
                        AllocatedBaseQty += Round(
                            LPLine.Quantity * QtyPerUnitOfMeasure(ItemNo, LPLine."Unit of Measure"),
                            0.00001);
                    until LPLine.Next() = 0;
            until LPHeader.Next() = 0;

        // Earlier Take lines of the same not-yet-registered pick have already
        // moved LP metadata to the shipping LP, while Warehouse Entry still
        // shows their quantity in the source bin. Subtract those staged lines
        // as well so they cannot be counted a second time as loose stock.
        if TargetLP.Get(TargetLpNo) and (TargetLP."Bin Code" <> BinCode) then begin
            TargetLine.SetRange("LP No.", TargetLpNo);
            TargetLine.SetRange("Item No.", ItemNo);
            TargetLine.SetRange("Variant Code", VariantCode);
            TargetLine.SetRange("Source Bin Code", BinCode);
            TargetLine.SetRange("Source Document Type", TargetLine."Source Document Type"::WhsePick);
            TargetLine.SetRange("Source Document No.", PickNo);
            if LotNo <> '' then
                TargetLine.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                TargetLine.SetRange("Serial No.", SerialNo);
            TargetLine.SetFilter(Quantity, '>0');
            if TargetLine.FindSet() then
                repeat
                    PendingPickBaseQty += Round(
                        TargetLine.Quantity * QtyPerUnitOfMeasure(ItemNo, TargetLine."Unit of Measure"),
                        0.00001);
                until TargetLine.Next() = 0;
        end;

        LooseBaseQty := PhysicalBaseQty - AllocatedBaseQty - PendingPickBaseQty;
        if LooseBaseQty < 0 then
            LooseBaseQty := 0;
    end;

    local procedure SourceLpMaySupplyPick(SourceLP: Record "DOPSWHS LP Header"; PickNo: Code[20]; WhseDocumentNo: Code[20]): Boolean
    begin
        if SourceLP.Status <> SourceLP.Status::Assigned then
            exit(true);
        exit(
            ((SourceLP."Assigned Document Type" = SourceLP."Assigned Document Type"::WhsePick) and
             (SourceLP."Assigned Document No." = PickNo)) or
            ((SourceLP."Assigned Document Type" = SourceLP."Assigned Document Type"::WhseShipment) and
             (SourceLP."Assigned Document No." = WhseDocumentNo)));
    end;

    local procedure MinimumDecimal(LeftValue: Decimal; RightValue: Decimal): Decimal
    begin
        if LeftValue < RightValue then
            exit(LeftValue);
        exit(RightValue);
    end;

    local procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
    end;

    procedure Unbuild(var LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        OnBeforeUnbuild(LP);
        if not (LP.Status in [LP.Status::Built, LP.Status::Open]) then
            Error('Yalnız açık veya tamamlanmış LP bozulabilir.');
        LogMutation('LP.Unbuild');
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.DeleteAll(true);
        WriteToLedger(LP, LPActionUnbuilt(), LP."Bin Code", '', 0, '', '', '');
        LP.Status := LP.Status::Unbuilt;
        LP.Modify(true);
        OnAfterUnbuild(LP);
    end;

    procedure SplitForPartialUse(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS Partial Use Action"; Qty: Decimal; LineNo: Integer)
    var
        LPLine: Record "DOPSWHS LP Line";
        NewLP: Record "DOPSWHS LP Header";
        Lines: List of [Integer];
        Quantities: Dictionary of [Integer, Decimal];
        ExcessQty: Decimal;
    begin
        OnBeforeSplitForPartialUse(LP, Action, Qty, LineNo);
        LogMutation('LP.PartialUse');
        LPLine.Get(LP."No.", LineNo);
        if (Qty <= 0) or (Qty > LPLine.Quantity) then
            Error('Kısmi kullanım miktarı geçersizdir.');

        case Action of
            Action::CreateNewLP:
                begin
                    ExcessQty := LPLine.Quantity - Qty;
                    if ExcessQty > 0 then begin
                        Build(LP."LP Template Code", LP."Location Code", LP."Bin Code", NewLP);
                        Stop(NewLP, false);
                        Lines.Add(LineNo);
                        Quantities.Add(LineNo, ExcessQty);
                        Transfer(LP, NewLP, Lines, Quantities);
                        NewLP."Planned Quantity" := ExcessQty;
                        NewLP.Modify(true);
                    end;
                    LPLine.Get(LP."No.", LineNo);
                    LPLine.Validate(Quantity, Qty);
                    LPLine.Modify(true);
                    LP."Planned Quantity" := Qty;
                    LP.Modify(true);
                end;
            Action::RemoveExcess:
                begin
                    LPLine.Validate(Quantity, Qty);
                    LPLine.Modify(true);
                    LP."Planned Quantity" := Qty;
                    LP.Modify(true);
                end;
            Action::RemoveUsedPortion:
                begin
                    LPLine.Validate(Quantity, LPLine.Quantity - Qty);
                    if LPLine.Quantity = 0 then
                        LPLine.Delete(true)
                    else
                        LPLine.Modify(true);
                    LP."Planned Quantity" := LPLine.Quantity;
                    LP.Modify(true);
                end;
            Action::Unbuild:
                Unbuild(LP);
        end;
        OnAfterSplitForPartialUse(LP);
    end;

    /// <summary>
    /// Backwards-compatible entry point retained for callers compiled against older versions.
    /// </summary>
    procedure ConsumeLineForPostedSale(LpNo: Code[20]; LineNo: Integer; BaseQty: Decimal; PostedShipmentNo: Code[40])
    begin
        ConsumeLineForShipment(LpNo, LineNo, BaseQty, PostedShipmentNo);
    end;

    /// <summary>
    /// A directed warehouse movement can take part of an LP and place that
    /// quantity as loose stock in the target bin. Reuse the same exact-line,
    /// base-UOM and idempotency rules as shipment consumption; the standard
    /// warehouse activity remains the sole writer of Warehouse Entries.
    /// </summary>
    procedure ConsumeLineForWarehouseMovement(LpNo: Code[20]; LineNo: Integer; BaseQty: Decimal; MovementReference: Code[40])
    begin
        ConsumeLineForShipment(LpNo, LineNo, BaseQty, MovementReference);
    end;

    /// <summary>
    /// Reduces one exact LP line after a posted sales shipment. The quantity received
    /// from the item ledger is always in the item's base unit; the LP line may use another UOM.
    /// Works for both direct sales posting and warehouse shipment posting.
    /// PostedShipmentNo is the movement-ledger reference (Code[40] like "Related
    /// Document"): LP Propagation passes "&lt;posted shipment no.&gt;#&lt;entry no.&gt;"
    /// plus a per-LP line ordinal, which exceeds 20 characters; a narrower
    /// parameter raised an English runtime error inside Sales-Post.
    /// </summary>
    procedure ConsumeLineForShipment(LpNo: Code[20]; LineNo: Integer; BaseQty: Decimal; PostedShipmentNo: Code[40])
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        RemainingLPLine: Record "DOPSWHS LP Line";
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        QtyPerUoM: Decimal;
        QtyInLineUoM: Decimal;
        RemainingQty: Decimal;
        ItemNo: Code[20];
        LotSerial: Code[50];
    begin
        if BaseQty <= 0 then
            Error('LP kullanım miktarı sıfırdan büyük olmalıdır.');

        LPLine.LockTable();
        LP.Get(LpNo);
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            Error('%1 LP numarası sevkiyatta kullanılamaz. Güncel durum: %2.', LpNo, LP.Status);
        LPLine.Get(LpNo, LineNo);

        // Reconciliation runs both from Sales-Post events and from the durable
        // posted warehouse shipment relation. The ILE-qualified reference
        // makes those two paths idempotent without suppressing two legitimate
        // ledger entries from the same posted shipment.
        if PostedShipmentNo <> '' then begin
            MovementLedger.SetRange("LP No.", LpNo);
            MovementLedger.SetRange(Action, MovementLedger.Action::ItemRemoved);
            MovementLedger.SetRange("Related Document", PostedShipmentNo);
            if not MovementLedger.IsEmpty() then
                exit;
        end;

        Item.Get(LPLine."Item No.");
        QtyPerUoM := 1;
        if (LPLine."Unit of Measure" <> '') and
           (LPLine."Unit of Measure" <> Item."Base Unit of Measure")
        then begin
            if not ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                Error('%1 maddesinin %2 ölçü birimi bulunamadı.', LPLine."Item No.", LPLine."Unit of Measure");
            QtyPerUoM := ItemUoM."Qty. per Unit of Measure";
            if QtyPerUoM <= 0 then
                Error('%1 maddesinin %2 ölçü birimi dönüşümü geçersizdir.', LPLine."Item No.", LPLine."Unit of Measure");
        end;

        QtyInLineUoM := Round(BaseQty / QtyPerUoM, 0.00001);
        if QtyInLineUoM > (LPLine.Quantity + 0.00001) then
            Error(
                '%1 LP satırında yeterli miktar yoktur. Mevcut: %2 %3, sevk edilen: %4 %3.',
                LpNo, LPLine.Quantity, LPLine."Unit of Measure", QtyInLineUoM);

        ItemNo := LPLine."Item No.";
        LotSerial := CopyStr(LPLine."Lot No." + LPLine."Serial No.", 1, MaxStrLen(LotSerial));
        RemainingQty := Round(LPLine.Quantity - QtyInLineUoM, 0.00001);
        if Abs(RemainingQty) < 0.00001 then
            RemainingQty := 0;

        if RemainingQty = 0 then
            LPLine.Delete(true)
        else begin
            LPLine.Validate(Quantity, RemainingQty);
            LPLine.Modify(true);
        end;

        WriteToLedger(
            LP, LPActionItemRemoved(), LP."Bin Code", '', QtyInLineUoM,
            ItemNo, LotSerial, CopyStr(PostedShipmentNo, 1, 40));

        RemainingLPLine.SetRange("LP No.", LpNo);
        if RemainingLPLine.IsEmpty() then begin
            LP.Status := LP.Status::Used;
            Clear(LP."Assigned Document Type");
            LP."Assigned Document No." := '';
            LP.Modify(true);
        end else
            // A posted shipment no longer has a live document to which the
            // remaining physical LP can stay assigned. Release the remainder
            // for the next movement instead of leaving a stale assignment.
            if LP.Status = LP.Status::Assigned then begin
                LP.Status := LP.Status::Built;
                Clear(LP."Assigned Document Type");
                LP."Assigned Document No." := '';
                LP.Modify(true);
            end;
    end;

    procedure WriteToLedger(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS LP Action"; FromBin: Code[20]; ToBin: Code[20]; Quantity: Decimal; ItemNo: Code[20]; LotSerial: Code[50]; RelatedDocument: Code[40])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger.Init();
        Ledger."LP No." := LP."No.";
        Ledger.Action := Action;
        Ledger."From Bin" := FromBin;
        Ledger."To Bin" := ToBin;
        Ledger.Quantity := Quantity;
        Ledger."Item No." := ItemNo;
        Ledger."Lot Serial" := LotSerial;
        Ledger."User ID" := CopyStr(UserId(), 1, MaxStrLen(Ledger."User ID"));
        Ledger.DateTime := CurrentDateTime();
        Ledger."Related Document" := RelatedDocument;
        Ledger.Insert(true);
    end;

    /// <summary>
    /// Verifies that a quantity belongs to loose bin stock rather than an active LP.
    /// Product-based ad-hoc moves call this before posting so an unspecified pallet
    /// can never be split implicitly. Explicit LP moves use MoveToBin instead.
    /// </summary>
    procedure EnsureLooseStockAvailable(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; RequiredBaseQty: Decimal)
    var
        BinQtyBase: Decimal;
        AllocatedQtyBase: Decimal;
        AllocatedTrackedQtyBase: Decimal;
        TrackedQtyBase: Decimal;
    begin
        CalculateLooseStockInBin(
            LocationCode, BinCode, ItemNo, LotNo, SerialNo,
            BinQtyBase, AllocatedQtyBase, TrackedQtyBase, AllocatedTrackedQtyBase);

        if ((LotNo <> '') or (SerialNo <> '')) and
           ((TrackedQtyBase - AllocatedTrackedQtyBase) < RequiredBaseQty)
        then
            Error(
                '%1 ürününün %2 rafındaki izlemeli serbest stoku yetersizdir (lot %3, seri %4). İzlemeli stok: %5, aktif LP miktarı: %6, istenen: %7. LP içindeki stok kendiliğinden bölünemez; ilgili LP''yi açıkça seçin.',
                ItemNo, BinCode, LotNo, SerialNo, TrackedQtyBase, AllocatedTrackedQtyBase, RequiredBaseQty);

        if BinQtyBase - AllocatedQtyBase < RequiredBaseQty then
            Error(
                '%1 ürününün %2 rafındaki LP''ye atanmamış serbest stoku yetersizdir. Raf stoku: %3, aktif LP miktarı: %4, istenen: %5. LP içindeki stok kendiliğinden bölünemez; terminalde "LP ile" modunu kullanıp taşınacak LP''yi seçin.',
                ItemNo, BinCode, BinQtyBase, AllocatedQtyBase, RequiredBaseQty);
    end;

    local procedure CalculateLooseStockInBin(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; var BinQtyBase: Decimal; var AllocatedQtyBase: Decimal; var TrackedQtyBase: Decimal; var AllocatedTrackedQtyBase: Decimal)
    var
        BinContent: Record "Bin Content";
        WarehouseEntry: Record "Warehouse Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        LineQtyBase: Decimal;
    begin
        Clear(BinQtyBase);
        Clear(AllocatedQtyBase);
        Clear(TrackedQtyBase);
        Clear(AllocatedTrackedQtyBase);
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", BinCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", '');
        if BinContent.FindSet() then
            repeat
                BinContent.CalcFields("Quantity (Base)");
                BinQtyBase += BinContent."Quantity (Base)";
            until BinContent.Next() = 0;

        if (LotNo <> '') or (SerialNo <> '') then begin
            WarehouseEntry.SetRange("Location Code", LocationCode);
            WarehouseEntry.SetRange("Bin Code", BinCode);
            WarehouseEntry.SetRange("Item No.", ItemNo);
            WarehouseEntry.SetRange("Variant Code", '');
            if LotNo <> '' then
                WarehouseEntry.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                WarehouseEntry.SetRange("Serial No.", SerialNo);
            if WarehouseEntry.FindSet() then
                repeat
                    TrackedQtyBase += WarehouseEntry."Qty. (Base)";
                until WarehouseEntry.Next() = 0;
        end;

        Item.Get(ItemNo);
        LPHeader.SetRange("Location Code", LocationCode);
        LPHeader.SetRange("Bin Code", BinCode);
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LPHeader."No.");
                LPLine.SetRange("Item No.", ItemNo);
                LPLine.SetRange("Variant Code", '');
                if LPLine.FindSet() then
                    repeat
                        LineQtyBase := LPLine.Quantity;
                        if (LPLine."Unit of Measure" <> '') and
                           (LPLine."Unit of Measure" <> Item."Base Unit of Measure") and
                           ItemUoM.Get(ItemNo, LPLine."Unit of Measure")
                        then
                            LineQtyBase *= ItemUoM."Qty. per Unit of Measure";
                        AllocatedQtyBase += LineQtyBase;
                        if ((LotNo = '') or (LPLine."Lot No." = LotNo)) and
                           ((SerialNo = '') or (LPLine."Serial No." = SerialNo))
                        then
                            AllocatedTrackedQtyBase += LineQtyBase;
                    until LPLine.Next() = 0;
            until LPHeader.Next() = 0;

    end;

    local procedure LooseStockAvailableInBin(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]): Decimal
    var
        BinQtyBase: Decimal;
        AllocatedQtyBase: Decimal;
        TrackedQtyBase: Decimal;
        AllocatedTrackedQtyBase: Decimal;
        AvailableQtyBase: Decimal;
        TrackedAvailableQtyBase: Decimal;
    begin
        CalculateLooseStockInBin(
            LocationCode, BinCode, ItemNo, LotNo, SerialNo,
            BinQtyBase, AllocatedQtyBase, TrackedQtyBase, AllocatedTrackedQtyBase);
        AvailableQtyBase := BinQtyBase - AllocatedQtyBase;
        if (LotNo <> '') or (SerialNo <> '') then begin
            TrackedAvailableQtyBase := TrackedQtyBase - AllocatedTrackedQtyBase;
            if TrackedAvailableQtyBase < AvailableQtyBase then
                AvailableQtyBase := TrackedAvailableQtyBase;
        end;
        if AvailableQtyBase < 0 then
            exit(0);
        exit(AvailableQtyBase);
    end;

    local procedure TotalLooseStockAvailable(LocationCode: Code[10]; ItemNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]): Decimal
    var
        Bin: Record Bin;
        TotalAvailableQty: Decimal;
    begin
        Bin.SetRange("Location Code", LocationCode);
        if Bin.FindSet() then
            repeat
                TotalAvailableQty += LooseStockAvailableInBin(
                    LocationCode, Bin.Code, ItemNo, LotNo, SerialNo);
            until Bin.Next() = 0;
        exit(TotalAvailableQty);
    end;

    procedure AllocatedQuantityForItemLedgerEntry(ItemLedgerEntryNo: Integer): Decimal
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        AllocatedQuantity: Decimal;
    begin
        LPLine.SetRange("Source Item Ledger Entry No.", ItemLedgerEntryNo);
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned] then
                        AllocatedQuantity += LPLine.Quantity;
            until LPLine.Next() = 0;
        exit(AllocatedQuantity);
    end;

    procedure AllocatableQuantityForItemLedgerEntry(ItemLedgerEntryNo: Integer): Decimal
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        AllocatableQuantity: Decimal;
    begin
        if not ItemLedgerEntry.Get(ItemLedgerEntryNo) then
            exit(0);
        AllocatableQuantity :=
            ItemLedgerEntry."Remaining Quantity" - AllocatedQuantityForItemLedgerEntry(ItemLedgerEntryNo);
        if AllocatableQuantity < 0 then
            exit(0);
        exit(AllocatableQuantity);
    end;

    procedure RefreshItemLedgerEntryLpReferences(ItemLedgerEntryNo: Integer)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        SeenLpNos: Dictionary of [Code[20], Boolean];
        LpNo: Code[20];
        LpNosText: Text;
        NewLpNo: Code[20];
        NewLpNos: Text[250];
    begin
        ItemLedgerEntry.Get(ItemLedgerEntryNo);
        LPLine.SetRange("Source Item Ledger Entry No.", ItemLedgerEntryNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned] then
                        if not SeenLpNos.ContainsKey(LPHeader."No.") then
                            SeenLpNos.Add(LPHeader."No.", true);
            until LPLine.Next() = 0;

        if SeenLpNos.Count() = 1 then
            foreach LpNo in SeenLpNos.Keys() do
                NewLpNo := LpNo
        else
            if SeenLpNos.Count() > 1 then begin
                foreach LpNo in SeenLpNos.Keys() do begin
                    if LpNosText <> '' then
                        LpNosText += ', ';
                    LpNosText += LpNo;
                end;
                NewLpNos := CopyStr(LpNosText, 1, MaxStrLen(NewLpNos));
            end;

        if (ItemLedgerEntry."DOPSWHS LP No." = NewLpNo) and
           (ItemLedgerEntry."DOPSWHS LP Nos." = NewLpNos)
        then
            exit;
        ItemLedgerEntry."DOPSWHS LP No." := NewLpNo;
        ItemLedgerEntry."DOPSWHS LP Nos." := NewLpNos;
        ItemLedgerEntry.Modify(false);
    end;

    local procedure LoadExistingBulkBuildRequest(RequestId: Guid; ItemLedgerEntryNo: Integer; TemplateCode: Code[20]; BinCode: Code[20]; LpCount: Integer; QuantityPerLp: Decimal; var CreatedLpNos: List of [Code[20]]): Boolean
    var
        BulkRequest: Record "DOPSWHS LP Bulk Request";
        LPHeader: Record "DOPSWHS LP Header";
        ExistingCount: Integer;
    begin
        BulkRequest.LockTable();
        if not BulkRequest.Get(RequestId) then
            exit(false);

        if (BulkRequest."Source ILE No." <> ItemLedgerEntryNo) or
           (BulkRequest."Template Code" <> TemplateCode) or
           (BulkRequest."Bin Code" <> BinCode) or
           (BulkRequest."LP Count" <> LpCount) or
           (BulkRequest."Quantity per LP" <> QuantityPerLp)
        then
            Error(
                '%1 toplu LP işlem kimliği farklı bir plan için daha önce kullanılmıştır. LP listesini yenileyin.',
                Format(RequestId));
        if not BulkRequest.Completed then
            Error(
                '%1 toplu LP işlemi tamamlanmamış görünüyor. İkinci bir LP seti oluşturulmadı; kayıtları kontrol edin.',
                Format(RequestId));

        LPHeader.SetCurrentKey("Bulk Build Request ID");
        LPHeader.SetRange("Bulk Build Request ID", RequestId);
        if not LPHeader.FindSet() then
            Error(
                '%1 toplu LP işlemi tamamlanmış ancak LP kayıtları bulunamadı. İkinci bir LP seti oluşturulmadı; kayıtları kontrol edin.',
                Format(RequestId));

        repeat
            if (LPHeader."Bulk Source ILE No." <> ItemLedgerEntryNo) or
               (LPHeader."Bulk Source Bin Code" = '') or
               ((BinCode <> '') and (LPHeader."Bulk Source Bin Code" <> BinCode))
            then
                Error(
                    '%1 toplu LP işleminin LP kaynak bilgileri tutarsızdır. Yeniden oluşturmayın; kayıtları kontrol edin.',
                    Format(RequestId));
            ExistingCount += 1;
            CreatedLpNos.Add(LPHeader."No.");
        until LPHeader.Next() = 0;

        if ExistingCount <> LpCount then
            Error(
                '%1 toplu LP işlemi %2 LP istemiştir ancak %3 kayıt bulundu. Yeniden oluşturmayın; kayıtları kontrol edin.',
                Format(RequestId), LpCount, ExistingCount);
        exit(true);
    end;

    local procedure InsertBulkBuildRequest(RequestId: Guid; ItemLedgerEntryNo: Integer; TemplateCode: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; LpCount: Integer; QuantityPerLp: Decimal)
    var
        BulkRequest: Record "DOPSWHS LP Bulk Request";
    begin
        BulkRequest.Init();
        BulkRequest."Request ID" := RequestId;
        BulkRequest."Source ILE No." := ItemLedgerEntryNo;
        BulkRequest."Template Code" := TemplateCode;
        BulkRequest."Location Code" := LocationCode;
        BulkRequest."Bin Code" := BinCode;
        BulkRequest."LP Count" := LpCount;
        BulkRequest."Quantity per LP" := QuantityPerLp;
        BulkRequest.Insert(true);
    end;

    local procedure CompleteBulkBuildRequest(RequestId: Guid)
    var
        BulkRequest: Record "DOPSWHS LP Bulk Request";
    begin
        BulkRequest.Get(RequestId);
        if BulkRequest.Completed then
            Error('%1 toplu LP işlem kaydı zaten tamamlanmıştır.', Format(RequestId));
        BulkRequest.Completed := true;
        // Bu alan yalnız yönetim codeunit'i tarafından false -> true yapılır.
        // Tablo OnModify koruması bazı BC çalışma zamanlarında aynı transaction
        // içindeki eski değeri göremediği için geçerli işlemi reddediyordu.
        BulkRequest.Modify(false);
    end;

    local procedure EnsureNoUnresolvedPlannedLPs(LocationCode: Code[10]; BinCode: Code[20])
    var
        LPHeader: Record "DOPSWHS LP Header";
    begin
        LPHeader.SetRange("Location Code", LocationCode);
        LPHeader.SetRange("Bin Code", BinCode);
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        LPHeader.SetFilter("Planned Quantity", '>%1', 0);
        if LPHeader.FindSet() then
            repeat
                LPHeader.CalcFields("Line Count");
                if LPHeader."Line Count" = 0 then
                    Error(
                        '%1 rafında miktarı %2 olan eski/boş %3 LP kaydı bulundu. Aynı stoka ikinci LP etiketi üretmemek için önce bu LP''yi doğrulayın, içeriğini tamamlayın veya kontrollü olarak kaldırın.',
                        BinCode, LPHeader."Planned Quantity", LPHeader."No.");
            until LPHeader.Next() = 0;
    end;

    local procedure RequireStatus(var LP: Record "DOPSWHS LP Header"; RequiredStatus: Enum "DOPSWHS LP Status")
    begin
        if LP.Status <> RequiredStatus then
            Error('%1 LP numarasının durumu %2 olmalıdır. Güncel durum: %3.', LP."No.", RequiredStatus, LP.Status);
    end;

    local procedure LogMutation(EventName: Text)
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(EventName, EventName);
    end;

    local procedure LPActionBuilt(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Built); end;
    local procedure LPActionAssigned(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Assigned); end;
    local procedure LPActionReleased(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Released); end;
    local procedure LPActionTransferIn(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::TransferIn); end;
    local procedure LPActionTransferOut(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::TransferOut); end;
    local procedure LPActionUnbuilt(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Unbuilt); end;
    local procedure LPActionItemAdded(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::ItemAdded); end;
    local procedure LPActionItemRemoved(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::ItemRemoved); end;

    [IntegrationEvent(false, false)] local procedure OnBeforeBuild(TemplateCode: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterBuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeStop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterStop(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeReopen(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterReopen(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeAddLine(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; UoM: Code[10]; Qty: Decimal) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterAddLine(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeRemoveLine(var LPLine: Record "DOPSWHS LP Line") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterRemoveLine(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeAssign(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterAssign(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeRelease(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterRelease(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeTransfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterTransfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeUnbuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterUnbuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeSplitForPartialUse(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS Partial Use Action"; Qty: Decimal; LineNo: Integer) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterSplitForPartialUse(var LP: Record "DOPSWHS LP Header") begin end;
}
