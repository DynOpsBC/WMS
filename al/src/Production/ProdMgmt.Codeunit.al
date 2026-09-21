codeunit 72048 "DOPSWHS Prod Mgmt"
{
    Access = Public;

    procedure Consume(var ProdOrderComponent: Record "Prod. Order Component"; ItemNo: Code[20]; Qty: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; BinCode: Code[20])
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        License: Codeunit "DOPSWHS License Mgmt";
        ConsumeQty: Decimal;
        ConsumeItemNo: Code[20];
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);
        OnBeforeConsume(ProdOrderComponent, ItemNo, Qty, LpNo, LotNo, SerialNo, BinCode);
        ProdOrderComponent.TestField(Status, ProdOrderComponent.Status::Released);

        ConsumeItemNo := ItemNo;
        if ConsumeItemNo = '' then
            ConsumeItemNo := ProdOrderComponent."Item No.";
        if ConsumeItemNo <> ProdOrderComponent."Item No." then
            Error('Item %1 does not match production component %2.', ConsumeItemNo, ProdOrderComponent."Item No.");

        ConsumeQty := Qty;
        if LpNo <> '' then
            ConsumeQty := ResolveLpQuantity(LpNo, ConsumeItemNo, LotNo, SerialNo);
        if ConsumeQty <= 0 then
            Error('Consumption quantity must be greater than zero.');

        CreateConsumptionLine(ProdOrderComponent, ConsumeItemNo, ConsumeQty, LpNo, LotNo, SerialNo, BinCode, ItemJournalLine);
        LogTelemetry('AdvWMS.Production.Consumed', ProdOrderComponent."Prod. Order No.");
        // Post Batch (23) avoids the "Do you want to post?" Confirm that codeunit 241 raises (API/mobile-safe).
        ItemJnlPostBatch.Run(ItemJournalLine);
        OnAfterConsume(ProdOrderComponent, ItemJournalLine);
    end;

    procedure ConsumeByProdOrder(ProdOrderNo: Code[20]; ComponentLineNo: Integer; ItemNo: Code[20]; Qty: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; BinCode: Code[20])
    var
        ProdOrderComponent: Record "Prod. Order Component";
    begin
        ProdOrderComponent.SetRange(Status, ProdOrderComponent.Status::Released);
        ProdOrderComponent.SetRange("Prod. Order No.", ProdOrderNo);
        ProdOrderComponent.SetRange("Line No.", ComponentLineNo);
        if ItemNo <> '' then
            ProdOrderComponent.SetRange("Item No.", ItemNo);
        ProdOrderComponent.FindFirst();

        if (LpNo <> '') and (ComponentLineNo = 0) then
            FindComponentForLp(ProdOrderNo, ItemNo, LpNo, ProdOrderComponent);

        Consume(ProdOrderComponent, ItemNo, Qty, LpNo, LotNo, SerialNo, BinCode);
    end;

    procedure CreateProductionPick(ProdOrderNo: Code[20]): Code[20]
    begin
        exit(CreateProductionPickFor(ProdOrderNo, CopyStr(UserId(), 1, 50)));
    end;

    procedure CreateProductionPickFor(ProdOrderNo: Code[20]; RequestingUserId: Code[50]): Code[20]
    begin
        exit(CreateProductionPickInternal(ProdOrderNo, RequestingUserId, ''));
    end;

    procedure CreateProductionPickFromLpFor(ProdOrderNo: Code[20]; LpNo: Code[20]; RequestingUserId: Code[50]): Code[20]
    begin
        if LpNo = '' then
            Error('Üretime gönderilecek hazır LP''nin QR kodunu okutun.');
        exit(CreateProductionPickInternal(ProdOrderNo, RequestingUserId, LpNo));
    end;

    local procedure CreateProductionPickInternal(ProdOrderNo: Code[20]; RequestingUserId: Code[50]; LpNo: Code[20]): Code[20]
    var
        ProductionOrder: Record "Production Order";
        PickHeader: Record "Warehouse Activity Header";
        LP: Record "DOPSWHS LP Header";
        License: Codeunit "DOPSWHS License Mgmt";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
        LPPickPreference: Codeunit "DOPSWHS LP Pick Preference";
        StockPolicy: Codeunit "DOPSWHS Prod Stock Policy";
        PickNo: Code[20];
        CreationError: Text;
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);
        if RequestingUserId = '' then
            Error('Üretim toplaması için oturumdaki operatör bilgisi zorunludur.');

        // Validate the source before looking up same-number activities. For an
        // existing pick, acquire pick ownership before the order/LP locks, as
        // registration does, so creation cannot invert that lock order.
        if not ProductionOrder.Get(ProductionOrder.Status::Released, ProdOrderNo) then
            Error('Serbest bırakılmış %1 numaralı üretim emri bulunamadı.', ProdOrderNo);

        PickNo := FindOpenProductionPick(ProdOrderNo);
        if PickNo <> '' then begin
            PickHeader.Get(PickHeader.Type::Pick, PickNo);
            PickMgmt.ClaimPick(PickHeader, RequestingUserId, 'Üretim emri toplamasını üstlen');
            EnsureProductionPickSource(ProdOrderNo, PickNo);
            ProductionOrder.LockTable();
            ProductionOrder.Get(ProductionOrder.Status::Released, ProdOrderNo);
            if LpNo <> '' then begin
                ValidateProductionSourceLp(ProdOrderNo, PickNo, LpNo, LP);
                ValidateProductionLpPick(ProdOrderNo, PickNo, LP);
                PrepareProductionLpScope(ProdOrderNo, PickNo, LP);
                ReserveProductionSourceLp(LP, ProdOrderNo, PickNo);
            end;
            exit(PickNo);
        end;

        // Hold the released order through standard creation and final checks.
        // If another request created a pick meanwhile, retry using the existing
        // pick path rather than taking a pick lock while holding the order.
        ProductionOrder.LockTable();
        ProductionOrder.Get(ProductionOrder.Status::Released, ProdOrderNo);
        if FindOpenProductionPick(ProdOrderNo) <> '' then
            Error('%1 üretim emri için başka bir oturum toplama oluşturdu. Belgeyi yenileyip tekrar açın.', ProdOrderNo);
        if LpNo <> '' then
            ValidateProductionSourceLp(ProdOrderNo, '', LpNo, LP);

        // BC must not validate a local WMS operator as a Warehouse Employee.
        // Create unassigned, then claim through the same ownership rules as
        // normal terminal picking. A ready LP gets its exact proposed quantities;
        // the ordinary flow starts at zero. Both require scans before registration.
        if LpNo <> '' then begin
            LPPickPreference.ConfigureForProduction(ProdOrderNo, LpNo);
            BindSubscription(LPPickPreference);
        end;
        StockPolicy.SetPreparedLp(LpNo <> '');
        ClearLastError();
        if not TryCreateProductionPick(ProductionOrder) then begin
            CreationError := GetLastErrorText();
            StockPolicy.SetPreparedLp(false);
            if LpNo <> '' then
                UnbindSubscription(LPPickPreference);
            Error(CreationError);
        end;
        StockPolicy.SetPreparedLp(false);
        if LpNo <> '' then
            UnbindSubscription(LPPickPreference);

        PickNo := FindOpenProductionPick(ProdOrderNo);
        if PickNo = '' then
            Error('%1 üretim emri için ambar toplaması oluşturulamadı. Bileşen lokasyonunu, üretim rafını ve ambar toplama kurulumunu kontrol edin.', ProdOrderNo);
        EnsureProductionPickSource(ProdOrderNo, PickNo);
        if LpNo <> '' then begin
            ValidateProductionLpPick(ProdOrderNo, PickNo, LP);
            PrepareProductionLpScope(ProdOrderNo, PickNo, LP);
        end;
        PickHeader.Get(PickHeader.Type::Pick, PickNo);
        PickMgmt.ClaimPick(PickHeader, RequestingUserId, 'Üretim emri toplamasını üstlen');
        if LpNo <> '' then
            ReserveProductionSourceLp(LP, ProdOrderNo, PickNo);

        exit(PickNo);
    end;

    local procedure ReserveProductionSourceLp(var LP: Record "DOPSWHS LP Header"; ProdOrderNo: Code[20]; PickNo: Code[20])
    var
        LPManagement: Codeunit "DOPSWHS LP Management";
    begin
        // The LP lock acquired during source validation is still held. Reserve
        // it before this request commits so another order cannot select the
        // same ready pallet while its first pick awaits physical registration.
        LP.Get(LP."No.");
        if (LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption) and
           (LP."Assigned Document No." = ProdOrderNo)
        then
            exit;
        if (LP.Status = LP.Status::Assigned) and
           (LP."Assigned Document Type" = LP."Assigned Document Type"::WhsePick) and
           (LP."Assigned Document No." = PickNo)
        then
            exit;
        LP.TestField(Status, LP.Status::Built);
        LP.TestField("Assigned Document Type", LP."Assigned Document Type"::None);
        LP.TestField("Assigned Document No.", '');
        LPManagement.Assign(LP, LP."Assigned Document Type"::WhsePick, PickNo);
    end;

    // Standard ProductionOrder.CreatePick and its report explicitly COMMIT.
    // Ignore those commits only in this call so source checks, pick creation,
    // operator claim and any subsequent error remain one transaction.
    [CommitBehavior(CommitBehavior::Ignore)]
    [TryFunction]
    local procedure TryCreateProductionPick(var ProductionOrder: Record "Production Order")
    var
        SortingMethod: Option "None","Item","Document","Shelf or Bin","Due Date","Bin Ranking","Action Type";
    begin
        ProductionOrder.SetHideValidationDialog(true);
        ProductionOrder.CreatePick('', SortingMethod::"Shelf or Bin", false, true, false);
    end;

    local procedure EnsureProductionPickSource(ProdOrderNo: Code[20]; PickNo: Code[20])
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.LockTable();
        PickLine.SetRange("Activity Type", PickLine."Activity Type"::Pick);
        PickLine.SetRange("No.", PickNo);
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        if PickLine.FindSet() then
            repeat
                if (PickLine."Source Type" <> Database::"Prod. Order Component") or
                   (PickLine."Source Subtype" <> Enum::"Production Order Status"::Released.AsInteger()) or
                   (PickLine."Source No." <> ProdOrderNo)
                then
                    Error('%1 toplaması başka kaynak belgeler de içeriyor. %2 üretim emri için ayrı bir ambar toplaması kullanın.', PickNo, ProdOrderNo);
            until PickLine.Next() = 0;
    end;

    local procedure ValidateProductionSourceLp(ProdOrderNo: Code[20]; PickNo: Code[20]; LpNo: Code[20]; var LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
        ChildLP: Record "DOPSWHS LP Header";
        Component: Record "Prod. Order Component";
        Item: Record Item;
        LPVerification: Codeunit "DOPSWHS LP Verification";
        RemainingByItem: Dictionary of [Text, Decimal];
        ItemKey: Text;
        RemainingBaseQty: Decimal;
        RequiredBaseQty: Decimal;
    begin
        LP.LockTable();
        LPLine.LockTable();
        if not LP.Get(LpNo) then
            Error('%1 LP numarası bulunamadı.', LpNo);
        if not (LP.Status in [LP.Status::Built, LP.Status::Assigned]) then
            Error('%1 LP''si henüz hazır değil. Depodaki LP oluşturma işlemini tamamlayıp LP''yi kapatın.', LpNo);
        if (LP.Status = LP.Status::Assigned) or
           (LP."Assigned Document Type" <> LP."Assigned Document Type"::None) or
           (LP."Assigned Document No." <> '')
        then
            if not (((LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption) and
                     (LP."Assigned Document No." = ProdOrderNo)) or
                    ((PickNo <> '') and (LP."Assigned Document Type" = LP."Assigned Document Type"::WhsePick) and
                     (LP."Assigned Document No." = PickNo)))
            then
                Error('%1 LP''si başka bir belgeye ayrılmış: %2.', LpNo, LP."Assigned Document No.");
        LP.TestField("Location Code");
        LP.TestField("Bin Code");
        LP.TestField("Pending Receipt No.", '');
        LP.TestField("Parent LP No.", '');
        ChildLP.SetRange("Parent LP No.", LpNo);
        if not ChildLP.IsEmpty() then
            Error('%1 üst LP''sinin alt paletlerini ayrı ayrı üretime hazırlayın.', LpNo);

        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetFilter("Child LP No.", '<>%1', '');
        if not LPLine.IsEmpty() then
            Error('%1 LP''sinin alt paletlerini ayrı ayrı üretime hazırlayın.', LpNo);
        LPLine.SetRange("Child LP No.");
        LPLine.SetFilter(Quantity, '<0');
        if not LPLine.IsEmpty() then
            Error('%1 LP''sinde negatif içerik var; üretime göndermeden önce LP''yi kontrol edin.', LpNo);
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            Error('%1 LP''sinde üretime gönderilecek ürün bulunamadı.', LpNo);
        repeat
            Item.Get(LPLine."Item No.");
            ItemKey := ProductionDemandKey(LPLine."Item No.", LPLine."Variant Code");
            if not RemainingByItem.Get(ItemKey, RemainingBaseQty) then begin
                RemainingBaseQty := 0;
                Component.SetRange(Status, Component.Status::Released);
                Component.SetRange("Prod. Order No.", ProdOrderNo);
                Component.SetRange("Item No.", LPLine."Item No.");
                Component.SetRange("Variant Code", LPLine."Variant Code");
                if Component.IsEmpty() then
                    Error('%1 LP''sindeki %2 ürünü %3 üretim emrinin bileşeni değildir.', LpNo, LPLine."Item No.", ProdOrderNo);
                Component.SetRange("Location Code", LP."Location Code");
                if Component.IsEmpty() then
                    Error('%1 LP''si %2 lokasyonunda; %3 üretim emrinin %4 bileşeni başka lokasyondadır. Lokasyonlar arası stok aktarımı tamamlanmadan üretim ambar toplaması yapılamaz.', LpNo, LP."Location Code", ProdOrderNo, LPLine."Item No.");
                if Component.FindSet() then
                    repeat
                        // BC picks expected demand minus quantities already
                        // registered as picked. Existing open pick quantities
                        // remain available here because they can be reused.
                        if Component."Expected Qty. (Base)" > Component."Qty. Picked (Base)" then
                            RemainingBaseQty += Component."Expected Qty. (Base)" - Component."Qty. Picked (Base)";
                    until Component.Next() = 0;
            end;
            RequiredBaseQty := LPVerification.LineBaseQuantity(LPLine);
            if RequiredBaseQty > RemainingBaseQty + LPVerification.QtyTolerance() then
                Error('%1 LP''sindeki %2 miktarı üretim emrinin kalan ihtiyacını aşıyor. LP''yi bozmadan göndermek için ihtiyaca uygun hazır palet seçin.', LpNo, LPLine."Item No.");
            RemainingByItem.Set(ItemKey, RemainingBaseQty - RequiredBaseQty);
            Component.Reset();
        until LPLine.Next() = 0;
    end;

    local procedure ProductionDemandKey(ItemNo: Text; VariantCode: Text) KeyText: Text
    var
        Parts: JsonArray;
    begin
        Parts.Add(ItemNo);
        Parts.Add(VariantCode);
        Parts.WriteTo(KeyText);
    end;

    local procedure ValidateProductionLpPick(ProdOrderNo: Code[20]; PickNo: Code[20]; LP: Record "DOPSWHS LP Header")
    var
        TempTake: Record "Warehouse Activity Line" temporary;
    begin
        BuildProductionLpAllocation(ProdOrderNo, PickNo, LP, TempTake);
    end;

    local procedure BuildProductionLpAllocation(ProdOrderNo: Code[20]; PickNo: Code[20]; LP: Record "DOPSWHS LP Header"; var TempTake: Record "Warehouse Activity Line" temporary)
    var
        PickLine: Record "Warehouse Activity Line";
        LPLine: Record "DOPSWHS LP Line";
        LPVerification: Codeunit "DOPSWHS LP Verification";
        RequiredBaseQty: Decimal;
    begin
        PickLine.SetRange("Activity Type", PickLine."Activity Type"::Pick);
        PickLine.SetRange("No.", PickNo);
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        PickLine.SetRange("Source Type", Database::"Prod. Order Component");
        PickLine.SetRange("Source Subtype", Enum::"Production Order Status"::Released.AsInteger());
        PickLine.SetRange("Source No.", ProdOrderNo);
        PickLine.SetRange("Location Code", LP."Location Code");
        PickLine.SetRange("Bin Code", LP."Bin Code");
        PickLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if PickLine.FindSet() then
            repeat
                TempTake := PickLine;
                TempTake."Qty. to Handle" := 0;
                TempTake."Qty. to Handle (Base)" := 0;
                TempTake.Insert();
            until PickLine.Next() = 0;

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                RequiredBaseQty := LPVerification.LineBaseQuantity(LPLine);
                TempTake.SetRange("Item No.", LPLine."Item No.");
                TempTake.SetRange("Variant Code", LPLine."Variant Code");
                // Allocate exact tracking first. Unspecified standard lines may
                // accept the scanned lot later; never reuse their capacity twice.
                AllocateProductionLpToPick(TempTake, LPLine, true, RequiredBaseQty);
                if RequiredBaseQty > LPVerification.QtyTolerance() then
                    AllocateProductionLpToPick(TempTake, LPLine, false, RequiredBaseQty);
                if RequiredBaseQty > LPVerification.QtyTolerance() then
                    Error('%1 toplaması %2 LP''sinin tamamını %3 rafından, ürün %4 / lot %5 / seri %6 için karşılamıyor. Yanlış raftan toplama yapılmaması için mevcut belgeyi kontrol edin.', PickNo, LP."No.", LP."Bin Code", LPLine."Item No.", LPLine."Lot No.", LPLine."Serial No.");
            until LPLine.Next() = 0;
    end;

    local procedure AllocateProductionLpToPick(var TempTake: Record "Warehouse Activity Line" temporary; LPLine: Record "DOPSWHS LP Line"; ExactTracking: Boolean; var RemainingBaseQty: Decimal)
    var
        TrackingMatches: Boolean;
        AllocatedBaseQty: Decimal;
    begin
        if not TempTake.FindSet() then
            exit;
        repeat
            TrackingMatches := (TempTake."Lot No." = LPLine."Lot No.") and (TempTake."Serial No." = LPLine."Serial No.");
            if not ExactTracking then
                TrackingMatches := ((TempTake."Lot No." = '') or (TempTake."Lot No." = LPLine."Lot No.")) and
                                   ((TempTake."Serial No." = '') or (TempTake."Serial No." = LPLine."Serial No."));
            if TempTake."Qty. to Handle (Base)" > 0 then
                TrackingMatches := (TempTake."Lot No." = LPLine."Lot No.") and (TempTake."Serial No." = LPLine."Serial No.");
            if TrackingMatches and (TempTake."Qty. Outstanding (Base)" > 0) then begin
                AllocatedBaseQty := TempTake."Qty. Outstanding (Base)";
                if AllocatedBaseQty > RemainingBaseQty then
                    AllocatedBaseQty := RemainingBaseQty;
                TempTake."Qty. Outstanding (Base)" -= AllocatedBaseQty;
                TempTake."Qty. to Handle (Base)" += AllocatedBaseQty;
                // One standard line cannot carry two tracking identities.
                TempTake."Lot No." := LPLine."Lot No.";
                TempTake."Serial No." := LPLine."Serial No.";
                TempTake.Modify();
                RemainingBaseQty -= AllocatedBaseQty;
            end;
        until (TempTake.Next() = 0) or (RemainingBaseQty <= 0.00001);
    end;

    internal procedure PrepareProductionLpScope(ProdOrderNo: Code[20]; PickNo: Code[20]; LP: Record "DOPSWHS LP Header")
    var
        Line: Record "Warehouse Activity Line";
        OriginalTake: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        TempTake: Record "Warehouse Activity Line" temporary;
        Component: Record "Prod. Order Component";
        OtherLP: Record "DOPSWHS LP Header";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
        QtyByLine: Dictionary of [Integer, Decimal];
        TrackingByPlace: Dictionary of [Integer, Text];
        PlaceTracking: Text;
        Tracking: Text;
        TargetBin: Code[20];
        Qty: Decimal;
        PlaceQty: Decimal;
        SelectedTake: Boolean;
    begin
        // Reopening the same reserved pallet must preserve scans and quantities.
        if (LP.Status = LP.Status::Assigned) and
           (LP."Assigned Document Type" = LP."Assigned Document Type"::WhsePick) and
           (LP."Assigned Document No." = PickNo)
        then
            exit;

        Line.LockTable();
        Line.SetRange("Activity Type", Line."Activity Type"::Pick);
        Line.SetRange("No.", PickNo);
        if Line.FindSet() then
            repeat
                // BC keeps Qty. Handled and the registered LP references on an
                // open production pick, then refills Qty. to Handle with the
                // remaining demand. Those values are history, not an active
                // second collection. Accept only references to an LP already
                // delivered to this production order; any partial quantity or
                // unregistered LP still protects the operator's current work.
                if ProductionPickLineHasActiveWork(Line, ProdOrderNo)
                then
                    Error('%1 çekmesinde başlanmış toplama var. Hazır LP kapsamı mevcut çalışmayı sıfırlayamaz; açık çekmeyi tamamlayın veya kontrollü olarak iptal edin.', PickNo);
            until Line.Next() = 0;
        OtherLP.SetRange("Assigned Document Type", OtherLP."Assigned Document Type"::WhsePick);
        OtherLP.SetRange("Assigned Document No.", PickNo);
        OtherLP.SetFilter("No.", '<>%1', LP."No.");
        if not OtherLP.IsEmpty() then
            Error('%1 çekmesine başka LP ayrılmış. Hazır LP kapsamı mevcut toplamayı değiştiremez.', PickNo);

        BuildProductionLpAllocation(ProdOrderNo, PickNo, LP, TempTake);
        TempTake.Reset();
        TempTake.SetFilter("Qty. to Handle (Base)", '>0');
        TempTake.FindSet();
        repeat
            OriginalTake.Get(TempTake."Activity Type", TempTake."No.", TempTake."Line No.");
            PickMgmt.FindProductionPlaceLine(OriginalTake, PlaceLine);
            Component.Get(Component.Status::Released, ProdOrderNo, TempTake."Source Line No.", TempTake."Source Subline No.");
            PlaceLine.TestField("Location Code", LP."Location Code");
            PlaceLine.TestField("Bin Code", Component."Bin Code");
            PlaceLine.TestField("Bin Code");
            if TargetBin = '' then
                TargetBin := PlaceLine."Bin Code";
            if TargetBin <> PlaceLine."Bin Code" then
                Error('%1 LP''si iki üretim rafına bölünemez. Hazır LP''nin bütün bileşenleri aynı üretim gözüne gitmelidir.', LP."No.");
            TempTake.TestField("Qty. per Unit of Measure");
            Qty := Round(TempTake."Qty. to Handle (Base)" / TempTake."Qty. per Unit of Measure", 0.00001);
            if Abs(Qty * TempTake."Qty. per Unit of Measure" - TempTake."Qty. to Handle (Base)") > 0.00001 then
                Error('%1 LP miktarı çekmenin ölçü biriminde tam karşılanamıyor.', LP."No.");
            QtyByLine.Add(TempTake."Line No.", Qty);
            if not QtyByLine.Get(PlaceLine."Line No.", PlaceQty) then
                PlaceQty := 0;
            QtyByLine.Set(PlaceLine."Line No.", PlaceQty + Qty);
            Tracking := ProductionDemandKey(TempTake."Lot No.", TempTake."Serial No.");
            if TrackingByPlace.Get(PlaceLine."Line No.", PlaceTracking) and (PlaceTracking <> Tracking) then
                Error('Birleşmiş üretim Yer satırında farklı lot/seri toplanamaz. BC''de satırları ayırın.');
            TrackingByPlace.Set(PlaceLine."Line No.", Tracking);
        until TempTake.Next() = 0;

        // This is a proposal, not physical confirmation. Android still requires
        // every source bin and LP scan; registration revalidates the entire LP.
        Line.FindSet(true);
        repeat
            if not QtyByLine.Get(Line."Line No.", Qty) then
                Qty := 0;
            Line.Validate("Qty. to Handle", Qty);
            // Remove the previous registered segment's pallet hints before
            // applying the next ready LP to the still-open production pick.
            Line."LP No." := '';
            Line."Target LP No." := '';
            Line."DOPSWHS Source LP Line No." := 0;
            SelectedTake := (Line."Action Type" = Line."Action Type"::Take) and (Qty > 0);
            if SelectedTake then
                Line."LP No." := LP."No.";
            Line.Modify(true);
        until Line.Next() = 0;
    end;

    local procedure ProductionPickLineHasActiveWork(Line: Record "Warehouse Activity Line"; ProdOrderNo: Code[20]): Boolean
    begin
        if (Line."Qty. to Handle (Base)" <> 0) and
           (Abs(Line."Qty. to Handle (Base)" - Line."Qty. Outstanding (Base)") > 0.00001)
        then
            exit(true);

        if Line."DOPSWHS Source LP Line No." <> 0 then
            exit(true);
        if (Line."LP No." <> '') and (not IsRegisteredProductionLp(Line."LP No.", ProdOrderNo)) then
            exit(true);
        if (Line."Target LP No." <> '') and (not IsRegisteredProductionLp(Line."Target LP No.", ProdOrderNo)) then
            exit(true);

        // Qty. Handled by itself is cumulative history on an open BC pick.
        // With no active pallet hint and either zero or the standard full
        // outstanding proposal, it is safe to scope the next prepared LP.
        exit(false);
    end;

    local procedure IsRegisteredProductionLp(LpNo: Code[20]; ProdOrderNo: Code[20]): Boolean
    var
        HistoricalLP: Record "DOPSWHS LP Header";
    begin
        if LpNo = '' then
            exit(true);
        if not HistoricalLP.Get(LpNo) then
            exit(false);
        exit(
            (HistoricalLP.Status = HistoricalLP.Status::Assigned) and
            (HistoricalLP."Assigned Document Type" = HistoricalLP."Assigned Document Type"::ProdConsumption) and
            (HistoricalLP."Assigned Document No." = ProdOrderNo));
    end;

    procedure FinishProductionOrder(ProdOrderNo: Code[20]; UpdateUnitCost: Boolean): Code[20]
    var
        ProductionOrder: Record "Production Order";
        FinishedProductionOrder: Record "Production Order";
        ProdOrderStatusManagement: Codeunit "Prod. Order Status Management";
        License: Codeunit "DOPSWHS License Mgmt";
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);

        if not ProductionOrder.Get(ProductionOrder.Status::Released, ProdOrderNo) then begin
            // Mobil istemci aynı isteği bağlantı kesintisinden sonra yeniden
            // gönderebilir. Emir zaten bitmişse işlem idempotent kabul edilir.
            if FinishedProductionOrder.Get(FinishedProductionOrder.Status::Finished, ProdOrderNo) then
                exit(ProdOrderNo);
            Error('Released production order %1 was not found.', ProdOrderNo);
        end;

        OnBeforeFinishProductionOrder(ProductionOrder, UpdateUnitCost);
        ProdOrderStatusManagement.ChangeProdOrderStatus(
            ProductionOrder,
            Enum::"Production Order Status"::Finished,
            WorkDate(),
            UpdateUnitCost);

        if not FinishedProductionOrder.Get(FinishedProductionOrder.Status::Finished, ProdOrderNo) then
            Error('%1 numaralı üretim emri bitirilemedi.', ProdOrderNo);

        LogTelemetry('AdvWMS.Production.Finished', ProdOrderNo);
        OnAfterFinishProductionOrder(FinishedProductionOrder);
        exit(ProdOrderNo);
    end;

    local procedure FindOpenProductionPick(ProdOrderNo: Code[20]): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Take);
        WhseActivityLine.SetRange("Source Type", Database::"Prod. Order Component");
        WhseActivityLine.SetRange("Source Subtype", Enum::"Production Order Status"::Released.AsInteger());
        WhseActivityLine.SetRange("Source No.", ProdOrderNo);
        WhseActivityLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."No.");
        exit('');
    end;

    procedure ReportOutput(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; OutputQty: Decimal; ScrapQty: Decimal; Runtime: Decimal; NewLpTemplate: Code[20]; BinCode: Code[20]): Code[20]
    var
        License: Codeunit "DOPSWHS License Mgmt";
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);
        exit(ReportOutputInternal(ProdOrderRoutingLine, OutputQty, ScrapQty, Runtime, NewLpTemplate, BinCode));
    end;

    local procedure ReportOutputInternal(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; OutputQty: Decimal; ScrapQty: Decimal; Runtime: Decimal; NewLpTemplate: Code[20]; BinCode: Code[20]): Code[20]
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        NewLpNo: Code[20];
    begin
        OnBeforeOutput(ProdOrderRoutingLine, OutputQty, ScrapQty, Runtime, NewLpTemplate, BinCode);
        ProdOrderRoutingLine.TestField(Status, ProdOrderRoutingLine.Status::Released);
        if (OutputQty <= 0) and (ScrapQty <= 0) then
            Error('Output or scrap quantity must be greater than zero.');

        CreateOutputLine(ProdOrderRoutingLine, OutputQty, ScrapQty, Runtime, BinCode, ItemJournalLine);
        LogTelemetry('AdvWMS.Production.Output', ProdOrderRoutingLine."Prod. Order No.");
        ItemJnlPostBatch.Run(ItemJournalLine);

        if NewLpTemplate <> '' then
            NewLpNo := CreateOutputLp(ProdOrderRoutingLine, OutputQty, NewLpTemplate, BinCode);

        OnAfterOutput(ProdOrderRoutingLine, ItemJournalLine, NewLpNo);
        exit(NewLpNo);
    end;

    procedure ReportOutputByProdOrder(ProdOrderNo: Code[20]; RoutingLineNo: Integer; OutputQty: Decimal; ScrapQty: Decimal; Runtime: Decimal; NewLpTemplate: Code[20]; BinCode: Code[20]): Code[20]
    var
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
    begin
        ProdOrderRoutingLine.SetRange(Status, ProdOrderRoutingLine.Status::Released);
        ProdOrderRoutingLine.SetRange("Prod. Order No.", ProdOrderNo);
        ProdOrderRoutingLine.SetRange("Routing Reference No.", RoutingLineNo);
        if not ProdOrderRoutingLine.FindFirst() then begin
            ProdOrderRoutingLine.SetRange("Routing Reference No.");
            // TODO Sprint H+ post-deploy: restore alternate routing line lookup if target symbols expose a line number.
            ProdOrderRoutingLine.FindFirst();
        end;
        exit(ReportOutputInternal(ProdOrderRoutingLine, OutputQty, ScrapQty, Runtime, NewLpTemplate, BinCode));
    end;

    procedure FindComponentForLp(ProdOrderNo: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; var ProdOrderComponent: Record "Prod. Order Component")
    var
        LPLine: Record "DOPSWHS LP Line";
        MatchedItemNo: Code[20];
        MatchCount: Integer;
    begin
        MatchedItemNo := ItemNo;
        if MatchedItemNo = '' then begin
            LPLine.SetRange("LP No.", LpNo);
            LPLine.FindFirst();
            MatchedItemNo := LPLine."Item No.";
        end;

        ProdOrderComponent.Reset();
        ProdOrderComponent.SetRange(Status, ProdOrderComponent.Status::Released);
        ProdOrderComponent.SetRange("Prod. Order No.", ProdOrderNo);
        ProdOrderComponent.SetRange("Item No.", MatchedItemNo);
        if ProdOrderComponent.FindSet() then
            repeat
                MatchCount += 1;
            until ProdOrderComponent.Next() = 0;

        if MatchCount = 0 then
            Error('No production component matches item %1 for order %2.', MatchedItemNo, ProdOrderNo);
        if MatchCount > 1 then
            Error('Multiple production components match item %1 for order %2. Select a component line.', MatchedItemNo, ProdOrderNo);

        ProdOrderComponent.FindFirst();
    end;

    local procedure CreateConsumptionLine(var ProdOrderComponent: Record "Prod. Order Component"; ItemNo: Code[20]; Qty: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; BinCode: Code[20]; var ItemJournalLine: Record "Item Journal Line")
    var
        TemplateName: Code[10];
        BatchName: Code[10];
    begin
        EnsureItemJournalBatch(TemplateName, BatchName);
        InitItemJournalLine(TemplateName, BatchName, ItemJournalLine);
        // Order context BEFORE Item No.: validating Item No. first clears the order link, leaving the
        // posting to reject the line with "Order Type must be Production".
        ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::Consumption);
        ItemJournalLine.Validate("Order Type", ItemJournalLine."Order Type"::Production);
        ItemJournalLine.Validate("Order No.", ProdOrderComponent."Prod. Order No.");
        ItemJournalLine.Validate("Order Line No.", ProdOrderComponent."Prod. Order Line No.");
        ItemJournalLine.Validate("Item No.", ItemNo);
        ItemJournalLine.Validate("Prod. Order Comp. Line No.", ProdOrderComponent."Line No.");
        ItemJournalLine.Validate("Location Code", ProdOrderComponent."Location Code");
        if BinCode <> '' then
            ItemJournalLine.Validate("Bin Code", BinCode)
        else
            if ProdOrderComponent."Bin Code" <> '' then
                ItemJournalLine.Validate("Bin Code", ProdOrderComponent."Bin Code");
        ItemJournalLine.Validate(Quantity, Qty);
        ItemJournalLine."Package No." := LpNo;
        ItemJournalLine."Lot No." := LotNo;
        ItemJournalLine."Serial No." := SerialNo;
        ItemJournalLine.Insert(true);
    end;

    local procedure CreateOutputLine(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; OutputQty: Decimal; ScrapQty: Decimal; Runtime: Decimal; BinCode: Code[20]; var ItemJournalLine: Record "Item Journal Line")
    var
        ProdOrderLine: Record "Prod. Order Line";
        TemplateName: Code[10];
        BatchName: Code[10];
    begin
        ProdOrderLine.Get(ProdOrderRoutingLine.Status, ProdOrderRoutingLine."Prod. Order No.", ProdOrderRoutingLine."Routing Reference No.");
        EnsureItemJournalBatch(TemplateName, BatchName);
        InitItemJournalLine(TemplateName, BatchName, ItemJournalLine);
        ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::Output);
        ItemJournalLine.Validate("Order Type", ItemJournalLine."Order Type"::Production);
        ItemJournalLine.Validate("Order No.", ProdOrderRoutingLine."Prod. Order No.");
        ItemJournalLine.Validate("Order Line No.", ProdOrderRoutingLine."Routing Reference No.");
        ItemJournalLine.Validate("Item No.", ProdOrderLine."Item No.");
        ItemJournalLine.Validate("Routing No.", ProdOrderRoutingLine."Routing No.");
        ItemJournalLine.Validate("Operation No.", ProdOrderRoutingLine."Operation No.");
        ItemJournalLine.Validate("Location Code", ProdOrderLine."Location Code");
        if BinCode <> '' then
            ItemJournalLine.Validate("Bin Code", BinCode)
        else
            if ProdOrderLine."Bin Code" <> '' then
                ItemJournalLine.Validate("Bin Code", ProdOrderLine."Bin Code");
        ItemJournalLine.Validate("Output Quantity", OutputQty);
        ItemJournalLine.Validate("Scrap Quantity", ScrapQty);
        ItemJournalLine.Validate("Run Time", Runtime);
        ItemJournalLine.Insert(true);
    end;

    local procedure CreateOutputLp(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; OutputQty: Decimal; NewLpTemplate: Code[20]; BinCode: Code[20]): Code[20]
    var
        ProdOrderLine: Record "Prod. Order Line";
        Setup: Record "DOPSWHS Setup";
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        LocationCode: Code[10];
        EffectiveBinCode: Code[20];
    begin
        ProdOrderLine.Get(ProdOrderRoutingLine.Status, ProdOrderRoutingLine."Prod. Order No.", ProdOrderRoutingLine."Routing Reference No.");
        LocationCode := ProdOrderLine."Location Code";
        EffectiveBinCode := BinCode;
        if EffectiveBinCode = '' then
            EffectiveBinCode := ProdOrderLine."Bin Code";
        if LocationCode = '' then
            if Setup.Get('') then
                LocationCode := Setup."Default Location Code";

        LPMgt.Build(NewLpTemplate, LocationCode, EffectiveBinCode, LP);
        LPMgt.AddLine(LP, ProdOrderLine."Item No.", ProdOrderLine."Unit of Measure Code", OutputQty, '', '', 0D);
        LPMgt.Stop(LP, false);
        exit(LP."No.");
    end;

    local procedure ResolveLpQuantity(LpNo: Code[20]; ItemNo: Code[20]; var LotNo: Code[50]; var SerialNo: Code[50]): Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
        Qty: Decimal;
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        if LPLine.FindSet() then
            repeat
                Qty += LPLine.Quantity;
                if LotNo = '' then
                    LotNo := LPLine."Lot No.";
                if SerialNo = '' then
                    SerialNo := LPLine."Serial No.";
            until LPLine.Next() = 0;
        if Qty = 0 then
            Error('LP %1 does not contain item %2.', LpNo, ItemNo);
        exit(Qty);
    end;

    local procedure EnsureItemJournalBatch(var TemplateName: Code[10]; var BatchName: Code[10])
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        ItemJournalTemplate.SetRange(Type, ItemJournalTemplate.Type::Item);
        if not ItemJournalTemplate.FindFirst() then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'ITEM';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::Item;
            ItemJournalTemplate.Description := 'Item Journal';
            ItemJournalTemplate.Insert(true);
        end;

        TemplateName := ItemJournalTemplate.Name;
        BatchName := 'DOPSPROD';
        if not ItemJournalBatch.Get(TemplateName, BatchName) then begin
            ItemJournalBatch.Init();
            ItemJournalBatch."Journal Template Name" := TemplateName;
            ItemJournalBatch.Name := BatchName;
            ItemJournalBatch.Description := 'DOPSWHS production';
            ItemJournalBatch.Insert(true);
        end;
    end;

    local procedure InitItemJournalLine(TemplateName: Code[10]; BatchName: Code[10]; var ItemJournalLine: Record "Item Journal Line")
    var
        ExistingLine: Record "Item Journal Line";
        NextLineNo: Integer;
    begin
        ExistingLine.SetRange("Journal Template Name", TemplateName);
        ExistingLine.SetRange("Journal Batch Name", BatchName);
        if ExistingLine.FindLast() then
            NextLineNo := ExistingLine."Line No." + 10000
        else
            NextLineNo := 10000;

        ItemJournalLine.Init();
        ItemJournalLine."Journal Template Name" := TemplateName;
        ItemJournalLine."Journal Batch Name" := BatchName;
        ItemJournalLine."Line No." := NextLineNo;
        ItemJournalLine."Posting Date" := WorkDate();
        ItemJournalLine."Document No." := CopyStr('DOPS-PROD-' + Format(Today(), 0, '<Year4><Month,2><Day,2>'), 1, MaxStrLen(ItemJournalLine."Document No."));
    end;

    local procedure LogTelemetry(EventName: Text; DocumentNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(EventName, DocumentNo);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConsume(var ProdOrderComponent: Record "Prod. Order Component"; ItemNo: Code[20]; Qty: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; BinCode: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterConsume(var ProdOrderComponent: Record "Prod. Order Component"; var ItemJournalLine: Record "Item Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeOutput(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; OutputQty: Decimal; ScrapQty: Decimal; Runtime: Decimal; NewLpTemplate: Code[20]; BinCode: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterOutput(var ProdOrderRoutingLine: Record "Prod. Order Routing Line"; var ItemJournalLine: Record "Item Journal Line"; NewLpNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFinishProductionOrder(var ProductionOrder: Record "Production Order"; var UpdateUnitCost: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFinishProductionOrder(var ProductionOrder: Record "Production Order")
    begin
    end;
}
