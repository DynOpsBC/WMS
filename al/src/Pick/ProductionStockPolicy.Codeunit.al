codeunit 72454 "DOPSWHS Prod Stock Policy"
{
    SingleInstance = true;

    var
        Component: Record "Prod. Order Component";
        Eligible: Boolean;
        Applying: Boolean;
        PreparedLp: Boolean;

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

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnAfterCreateTempLineCheckReservation', '', false, false)]
    local procedure CaptureSource(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; QtyPerUnitofMeasure: Decimal; var TotalQtytoPick: Decimal; var TotalQtytoPickBase: Decimal; SourceType: Integer; SourceSubType: Option; SourceNo: Code[20]; SourceLineNo: Integer; SourceSubLineNo: Integer; var LastWhseItemTrkgLineNo: Integer; var TempWhseItemTrackingLine: Record "Whse. Item Tracking Line" temporary; var WhseShptLine: Record "Warehouse Shipment Line"; var QtyBaseMaxAvailToPick: Decimal)
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        ExistingTracking: Record "Whse. Item Tracking Line" temporary;
        Location: Record Location;
    begin
        if Applying then
            exit;
        Eligible := false;
        Clear(Component);
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
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeCreateTempItemTrkgLines', '', false, false)]
    local procedure DeferAutomaticFEFO(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]; var TotalQtytoPickBase: Decimal; HasExpiryDate: Boolean; var IsHandled: Boolean; var WhseItemTrackingFEFO: Codeunit "Whse. Item Tracking FEFO"; WhseShptLine: Record "Warehouse Shipment Line"; WhseWkshLine: Record "Whse. Worksheet Line")
    begin
        // Do not let the location-wide FEFO switch reorder non-HM/YM components.
        if Eligible and (Component."Item No." = ItemNo) and (Component."Location Code" = Location.Code) then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeCalcPickBin', '', false, false)]
    local procedure SelectDirectedLots(var Sender: Codeunit "Create Pick"; var TempWarehouseActivityLine: Record "Warehouse Activity Line" temporary; var TotalQtytoPick: Decimal; var TotalQtytoPickBase: Decimal; var TempWhseItemTrackingLine: Record "Whse. Item Tracking Line" temporary; CrossDock: Boolean; WhseTrackingExists: Boolean; WhseSource: Option; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; ToBinCode: Code[20]; QtyPerUnitofMeasure: Decimal; var IsHandled: Boolean)
    begin
        if IsHandled or not Eligible or Applying or WhseTrackingExists then
            exit;
        if (Component."Item No." <> ItemNo) or (Component."Location Code" <> LocationCode) then
            exit;
        ApplyPolicy(Sender, ToBinCode, TotalQtytoPick, TotalQtytoPickBase);
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeCalcBWPickBin', '', false, false)]
    local procedure SelectBasicLots(var Sender: Codeunit "Create Pick"; var TotalQtyToPick: Decimal; var TotalQtytoPickBase: Decimal; var TempWhseItemTrackingLine: Record "Whse. Item Tracking Line" temporary; var TempWhseActivLine: Record "Warehouse Activity Line" temporary; WhseItemTrkgExists: Boolean; var IsHandled: Boolean)
    begin
        if IsHandled or not Eligible or Applying or WhseItemTrkgExists then
            exit;
        ApplyPolicy(Sender, Component."Bin Code", TotalQtyToPick, TotalQtytoPickBase);
        IsHandled := true;
    end;

    local procedure ApplyPolicy(var CreatePick: Codeunit "Create Pick"; ToBinCode: Code[20]; var Quantity: Decimal; var QuantityBase: Decimal)
    var
        Failure: Text;
    begin
        Applying := true;
        ClearLastError();
        if not TryApplyPolicy(CreatePick, ToBinCode, Quantity, QuantityBase) then begin
            Failure := GetLastErrorText();
            Applying := false;
            Eligible := false;
            Error('%1', Failure);
        end;
        Applying := false;
    end;

    [TryFunction]
    local procedure TryApplyPolicy(var CreatePick: Codeunit "Create Pick"; ToBinCode: Code[20]; var Quantity: Decimal; var QuantityBase: Decimal)
    var
        Candidate: Record "DOPSWHS Pick Stock Candidate";
        Buffer: Record "Whse. Item Tracking Line" temporary;
        Availability: Codeunit "Create Pick";
        AvailableBase: Decimal;
        RequestedBase: Decimal;
        RemainingBase: Decimal;
        RemainingQty: Decimal;
        PlannedRemaining: Decimal;
        PlannedBase: Decimal;
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
        PlannedBase := QuantityBase - PlannedRemaining;
        if PlannedBase <= 0 then
            exit;
        // Supply the entire ordered tracking plan in one native call. Re-entering
        // once per lot would reuse BC's per-source tracking/quantity state.
        CreatePick.SetTempWhseItemTrkgLineFromBuffer(Buffer, Component."Prod. Order No.", Database::"Prod. Order Component", '', Component."Prod. Order Line No.", Component."Line No.", Component."Location Code");
        RemainingBase := PlannedBase;
        RemainingQty := Round(PlannedBase / Component."Qty. per Unit of Measure", 0.00001);
        CreatePick.CreateTempLine(Component."Location Code", Component."Item No.", Component."Variant Code", Component."Unit of Measure Code", '', ToBinCode, Component."Qty. per Unit of Measure", Component."Qty. Rounding Precision", Component."Qty. Rounding Precision (Base)", RemainingQty, RemainingBase);
        QuantityBase -= PlannedBase - RemainingBase;
        Quantity := Round(QuantityBase / Component."Qty. per Unit of Measure", 0.00001);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnCreateTempLineOnAfterCreateTempLineWithItemTracking', '', false, false)]
    local procedure PreventUntrackedFallback(var TotalQtytoPickBase: Decimal; var HasExpiredItems: Boolean; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; QtyPerUnitofMeasure: Decimal; var TempWhseActivLine: Record "Warehouse Activity Line" temporary; var TempLineNo: Integer; var IsHandled: Boolean; var TotalItemTrackedQtyToPickBase: Decimal)
    begin
        if Applying then
            IsHandled := true;
    end;

    local procedure MinQty(Left: Decimal; Right: Decimal): Decimal
    begin
        if Left < Right then
            exit(Left);
        exit(Right);
    end;
}
