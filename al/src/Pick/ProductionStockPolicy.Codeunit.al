codeunit 72454 "DOPSWHS Prod Stock Policy"
{
    SingleInstance = true;

    var
        Component: Record "Prod. Order Component";
        Eligible: Boolean;
        Applying: Boolean;
        PreparedLp: Boolean;
        PlanBuffer: Record "Whse. Item Tracking Line" temporary;
        PlannedBase: Decimal;
        PendingToBinCode: Code[20];

    procedure SetPreparedLp(Value: Boolean)
    begin
        PreparedLp := Value;
        Eligible := false;
    end;

    internal procedure UsesExpiration(ItemNo: Code[20]): Boolean
    begin
        exit(CopyStr(UpperCase(ItemNo), 1, 2) in ['HM', 'YM']);
    end;

    internal procedure BuildCandidates(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; var Candidate: Record "DOPSWHS Pick Stock Candidate")
    var
        Entry: Record "Item Ledger Entry";
        LotInfo: Record "Lot No. Information";
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        CheckExpiration: Boolean;
        Allowed: Boolean;
    begin
        Candidate.Reset();
        Candidate.DeleteAll();
        Item.Get(ItemNo);
        if Tracking.Get(Item."Item Tracking Code") then
            CheckExpiration := Tracking."Strict Expiration Posting";
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Variant Code", VariantCode);
        Entry.SetRange("Location Code", LocationCode);
        Entry.SetRange(Open, true);
        Entry.SetRange(Positive, true);
        Entry.SetFilter("Remaining Quantity", '>0');
        Entry.SetFilter("Lot No.", '<>%1', '');
        // Serial/package-managed stock remains on the standard BC tracking path.
        Entry.SetRange("Serial No.", '');
        Entry.SetRange("Package No.", '');
        if Entry.FindSet() then
            repeat
                Allowed := true;
                if LotInfo.Get(ItemNo, VariantCode, Entry."Lot No.") then
                    Allowed := not LotInfo.Blocked;
                if UsesExpiration(ItemNo) or CheckExpiration then
                    if (Entry."Expiration Date" <> 0D) and (Entry."Expiration Date" < WorkDate()) then
                        Allowed := false;
                if Allowed then begin
                    Candidate.Init();
                    Candidate."Entry No." := Entry."Entry No.";
                    Candidate."Posting Date" := Entry."Posting Date";
                    Candidate."Lot No." := Entry."Lot No.";
                    Candidate."Expiration Date" := Entry."Expiration Date";
                    Candidate."Remaining Quantity" := Entry."Remaining Quantity";
                    Candidate."Priority Date" := Entry."Posting Date";
                    if UsesExpiration(ItemNo) then begin
                        Candidate."Priority Date" := Entry."Expiration Date";
                        if Candidate."Priority Date" = 0D then
                            Candidate."Priority Date" := DMY2Date(31, 12, 9999);
                    end;
                    Candidate.Insert();
                end;
            until Entry.Next() = 0;
        Candidate.SetCurrentKey("Priority Date", "Posting Date", "Entry No.");
        Candidate.Ascending(true);
    end;

    // BADE (9 Eki 2026): lot planı önceden OnBeforeCalcPickBin içinden ikinci bir
    // CreateTempLine çağrısıyla uygulanıyordu. Bitmemiş hesap yeniden başladığı için
    // "Show Summary (Directed Put-away and Pick)" açıkken iki çağrı aynı özet
    // numarasını hazırlıyor, ikinci Insert "Entry No. zaten var" hatası veriyordu.
    // Artık dış hesap bu bileşeni çekmeden kapanır (özetini bir kez yazar); plan,
    // OnAfterCreateTempLine'da standart izleme tamponu üzerinden ayrı bir hesapla uygulanır.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnAfterCreateTempLineCheckReservation', '', false, false)]
    local procedure CaptureSource(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; QtyPerUnitofMeasure: Decimal; var TotalQtytoPick: Decimal; var TotalQtytoPickBase: Decimal; SourceType: Integer; SourceSubType: Option; SourceNo: Code[20]; SourceLineNo: Integer; SourceSubLineNo: Integer; var LastWhseItemTrkgLineNo: Integer; var TempWhseItemTrackingLine: Record "Whse. Item Tracking Line" temporary; var WhseShptLine: Record "Warehouse Shipment Line"; var QtyBaseMaxAvailToPick: Decimal)
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        ExistingTracking: Record "Whse. Item Tracking Line" temporary;
        Location: Record Location;
    begin
        // Planın uygulandığı iç hesap kendi izleme satırlarıyla standart yoldan geçer.
        if Applying then
            exit;
        Eligible := false;
        Clear(Component);
        Clear(PendingToBinCode);
        PlanBuffer.Reset();
        PlanBuffer.DeleteAll();
        PlannedBase := 0;
        if PreparedLp or (SourceType <> Database::"Prod. Order Component") or
           (SourceSubType <> Enum::"Production Order Status"::Released.AsInteger()) then
            exit;
        if not Component.Get(Component.Status::Released, SourceNo, SourceLineNo, SourceSubLineNo) then
            exit;
        if (Component."Item No." <> ItemNo) or (Component."Location Code" <> LocationCode) then
            exit;
        if not Location.Get(LocationCode) or not Location."Bin Mandatory" then
            exit;
        if not Item.Get(ItemNo) then
            exit;
        if not Tracking.Get(Item."Item Tracking Code") then
            exit;
        if not Tracking."Lot Warehouse Tracking" or Tracking."SN Warehouse Tracking" or Tracking."Package Warehouse Tracking" then
            exit;
        ExistingTracking.Copy(TempWhseItemTrackingLine, true);
        ExistingTracking.Reset();
        // Preserve every explicit source tracking choice, including partial choices.
        if not ExistingTracking.IsEmpty() then
            exit;
        Eligible := TotalQtytoPickBase > 0;
        // Plan, dış hesap bu bileşen için tek satır üretmeden önce hesaplanır;
        // stok durumu plan uygulanırken aynıdır.
        if Eligible then
            PlannedBase := BuildLotPlan(PlanBuffer, TotalQtytoPickBase);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeCreateTempItemTrkgLines', '', false, false)]
    local procedure DeferAutomaticFEFO(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]; var TotalQtytoPickBase: Decimal; HasExpiryDate: Boolean; var IsHandled: Boolean; var WhseItemTrackingFEFO: Codeunit "Whse. Item Tracking FEFO"; WhseShptLine: Record "Warehouse Shipment Line"; WhseWkshLine: Record "Whse. Worksheet Line")
    begin
        // Do not let the location-wide FEFO switch reorder non-HM/YM components.
        if Eligible and (Component."Item No." = ItemNo) and (Component."Location Code" = Location.Code) then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnCreateTempLineOnAfterCreateTempLineWithItemTracking', '', false, false)]
    local procedure DeferUntrackedPick(var TotalQtytoPickBase: Decimal; var HasExpiredItems: Boolean; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; QtyPerUnitofMeasure: Decimal; var TempWhseActivLine: Record "Warehouse Activity Line" temporary; var TempLineNo: Integer; var IsHandled: Boolean; var TotalItemTrackedQtyToPickBase: Decimal)
    begin
        if not Eligible or (Component."Item No." <> ItemNo) or (Component."Location Code" <> LocationCode) then
            exit;
        // Dış hesap: lotsuz çekme oluşmaz, plan hesap bitince uygulanır.
        // İç hesap: planın karşılayamadığı kalan lotsuz satıra dönüşmez.
        if not Applying then begin
            PendingToBinCode := ToBinCode;
            // Çağıran, kalan miktarı eski davranıştaki gibi görür: plan çekilecek.
            TotalQtytoPickBase -= MinQty(TotalQtytoPickBase, PlannedBase);
        end;
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnAfterCreateTempLine', '', false, false)]
    local procedure ApplyPlanAfterCalculation(var Sender: Codeunit "Create Pick"; LocationCode: Code[10]; ToBinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; QtyPerUnitofMeasure: Decimal)
    begin
        if Applying or not Eligible then
            exit;
        if (Component."Item No." <> ItemNo) or (Component."Location Code" <> LocationCode) then
            exit;
        ApplyPolicy(Sender);
    end;

    local procedure ApplyPolicy(var CreatePick: Codeunit "Create Pick")
    var
        Failure: Text;
    begin
        Applying := true;
        ClearLastError();
        if not TryApplyPolicy(CreatePick) then begin
            Failure := GetLastErrorText();
            Applying := false;
            Eligible := false;
            Error('%1', Failure);
        end;
        Applying := false;
        Eligible := false;
    end;

    [TryFunction]
    local procedure TryApplyPolicy(var CreatePick: Codeunit "Create Pick")
    var
        PlanQtyBase: Decimal;
        PlannedQty: Decimal;
    begin
        if PlannedBase <= 0 then
            exit;
        PlanQtyBase := PlannedBase;
        // Native tracking buffer: sets Create Pick's own "tracking exists" state, so
        // bin search filters by lot and every pick line carries its lot. This is a new
        // calculation started after the previous one inserted its summary row.
        CreatePick.SetTempWhseItemTrkgLineFromBuffer(PlanBuffer, Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        PlannedQty := Round(PlanQtyBase / Component."Qty. per Unit of Measure", 0.00001);
        CreatePick.CreateTempLine(Component."Location Code", Component."Item No.", Component."Variant Code", Component."Unit of Measure Code", '', PendingToBinCode, Component."Qty. per Unit of Measure", Component."Qty. Rounding Precision", Component."Qty. Rounding Precision (Base)", PlannedQty, PlanQtyBase);
    end;

    /// <summary>Ordered lot plan: HM/YM by expiry, others by posting date; blocked/expired lots excluded.</summary>
    local procedure BuildLotPlan(var Buffer: Record "Whse. Item Tracking Line" temporary; QuantityBase: Decimal): Decimal
    var
        Candidate: Record "DOPSWHS Pick Stock Candidate";
        Availability: Codeunit "Create Pick";
        AvailableBase: Decimal;
        RequestedBase: Decimal;
        PlannedRemaining: Decimal;
        LineNo: Integer;
        AllocatedByLot: Dictionary of [Code[50], Decimal];
        Allocated: Decimal;
    begin
        PlannedRemaining := QuantityBase;
        BuildCandidates(Component."Item No.", Component."Variant Code", Component."Location Code", Candidate);
        if Candidate.FindSet() then
            repeat
                Buffer.Init();
                LineNo += 1;
                Buffer."Entry No." := LineNo;
                Buffer."Source Type" := Database::"Prod. Order Component";
                Buffer."Source Subtype" := 0; // Warehouse tracking uses subtype zero, even for released components.
                Buffer."Source ID" := Component."Prod. Order No.";
                Buffer."Source Prod. Order Line" := Component."Prod. Order Line No.";
                Buffer."Source Ref. No." := Component."Line No.";
                Buffer."Location Code" := Component."Location Code";
                Buffer."Item No." := Component."Item No.";
                Buffer."Variant Code" := Component."Variant Code";
                Buffer."Lot No." := Candidate."Lot No.";
                Buffer."Expiration Date" := Candidate."Expiration Date";
                // A separate Create Pick instance only reads availability.
                AvailableBase := Availability.CalcTotalAvailQtyToPick(
                    Component."Location Code", Component."Item No.", Component."Variant Code", Buffer,
                    Database::"Prod. Order Component", Component.Status.AsInteger(), Component."Prod. Order No.",
                    Component."Prod. Order Line No.", Component."Line No.", 0, true);
                Allocated := 0;
                if AllocatedByLot.Get(Candidate."Lot No.", Allocated) then;
                AvailableBase -= Allocated;
                RequestedBase := MinQty(PlannedRemaining, MinQty(AvailableBase, Candidate."Remaining Quantity"));
                if RequestedBase > 0 then begin
                    Buffer."Qty. per Unit of Measure" := Component."Qty. per Unit of Measure";
                    Buffer."Quantity (Base)" := RequestedBase;
                    Buffer."Qty. to Handle (Base)" := RequestedBase;
                    Buffer."Qty. to Handle" := Round(RequestedBase / Component."Qty. per Unit of Measure", 0.00001);
                    Buffer.Insert();
                    PlannedRemaining -= RequestedBase;
                    AllocatedByLot.Set(Candidate."Lot No.", Allocated + RequestedBase);
                end;
            until (Candidate.Next() = 0) or (PlannedRemaining <= 0);
        exit(QuantityBase - PlannedRemaining);
    end;

    local procedure MinQty(Left: Decimal; Right: Decimal): Decimal
    begin
        if Left < Right then
            exit(Left);
        exit(Right);
    end;
}
