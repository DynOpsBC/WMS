codeunit 72439 "DOPSWHS LP Pick Preference"
{
    // Bound only while a DOPSWHS pick is being created. Standard BC ranks Bin
    // Content without knowing which stock is held by a completed LP.
    EventSubscriberInstance = Manual;

    procedure Configure(ShipmentNo: Code[20])
    begin
        ConfiguredShipmentNo := ShipmentNo;
        Clear(PreferredFilterByItem);
    end;

    procedure StampPickLines(PickNo: Code[20])
    var
        PickLine: Record "Warehouse Activity Line";
        LPNo: Code[20];
    begin
        if PickNo = '' then
            exit;
        PickLine.SetRange("Activity Type", PickLine."Activity Type"::Pick);
        PickLine.SetRange("No.", PickNo);
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        PickLine.SetFilter("Item No.", '<>%1', '');
        if PickLine.FindSet(true) then
            repeat
                LPNo := FindUniqueSourceLP(PickLine);
                if (LPNo <> '') and (PickLine."LP No." <> LPNo) then begin
                    // Validate would copy the LP to every same-item line and
                    // could mix different pallets/lots.
                    PickLine."LP No." := LPNo;
                    PickLine.Modify(true);
                end;
            until PickLine.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeSetBinCodeFilter', '', false, false)]
    local procedure PreferLPBinsForBasicWarehouse(var BinCodeFilterText: Text[250]; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; ToBinCode: Code[20]; var IsHandled: Boolean; SourceType: Integer; SourceSubType: Option; SourceNo: Code[20]; SourceLineNo: Integer; SourceSubLineNo: Integer)
    var
        PreferredFilter: Text;
    begin
        if SourceType <> Database::"Sales Line" then
            exit;
        if not IsConfiguredShipmentSource(SourceNo, SourceLineNo) then
            exit;
        if not GetPreferredBinFilter(LocationCode, ItemNo, VariantCode, ToBinCode, PreferredFilter) then
            exit;
        if BinCodeFilterText = '' then
            BinCodeFilterText := CopyStr(PreferredFilter, 1, MaxStrLen(BinCodeFilterText))
        else
            BinCodeFilterText := CopyStr(BinCodeFilterText + '&(' + PreferredFilter + ')', 1, MaxStrLen(BinCodeFilterText));
        // Keep IsHandled=false so BC still applies document and tracking rules.
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeGetBinContent', '', false, false)]
    local procedure PreferLPBinsForDirectedWarehouse(var TempBinContent: Record "Bin Content" temporary; ItemNo: Code[20]; VariantCode: Code[10]; UnitofMeasureCode: Code[10]; LocationCode: Code[10]; ToBinCode: Code[20]; CrossDock: Boolean; IsMovementWorksheet: Boolean; WhseItemTrkgExists: Boolean; BreakbulkBins: Boolean; SmallerUOMBins: Boolean; WhseItemTrackingSetup: Record "Item Tracking Setup"; TotalQtytoPick: Decimal; TotalQtytoPickBase: Decimal; var Result: Boolean; var IsHandled: Boolean)
    var
        PreferredFilter: Text;
    begin
        if ConfiguredShipmentNo = '' then
            exit;
        if not GetPreferredBinFilter(LocationCode, ItemNo, VariantCode, ToBinCode, PreferredFilter) then
            exit;
        // Let Microsoft's candidate builder enforce bin type, UOM and tracking;
        // only narrow its valid result to completed-LP bins.
        Result := TempBinContent.GetBinContent(
            ItemNo, VariantCode, UnitofMeasureCode, LocationCode, ToBinCode,
            CrossDock, IsMovementWorksheet, WhseItemTrkgExists, WhseItemTrackingSetup);
        if not Result then
            exit;
        TempBinContent.SetFilter("Bin Code", PreferredFilter);
        Result := TempBinContent.FindFirst();
        if Result then
            IsHandled := true
        else begin
            // Reservation/tracking can invalidate an LP candidate. Fall back to
            // standard BC instead of producing an incomplete pick.
            TempBinContent.Reset();
            TempBinContent.DeleteAll();
        end;
    end;

    local procedure GetPreferredBinFilter(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; ToBinCode: Code[20]; var PreferredFilter: Text): Boolean
    var
        CacheKey: Text;
    begin
        Clear(PreferredFilter);
        if (ConfiguredShipmentNo = '') or (LocationCode = '') or (ItemNo = '') then
            exit(false);
        CacheKey := LocationCode + '|' + ItemNo + '|' + VariantCode + '|' + ToBinCode;
        if PreferredFilterByItem.Get(CacheKey, PreferredFilter) then
            exit(PreferredFilter <> '');
        PreferredFilter := BuildPreferredBinFilter(LocationCode, ItemNo, VariantCode, ToBinCode);
        PreferredFilterByItem.Add(CacheKey, PreferredFilter);
        exit(PreferredFilter <> '');
    end;

    local procedure BuildPreferredBinFilter(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; ToBinCode: Code[20]): Text
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        BinContent: Record "Bin Content";
        Item: Record Item;
        ItemUOM: Record "Item Unit of Measure";
        LPQtyByBin: Dictionary of [Text, Decimal];
        RequiredQtyBase: Decimal;
        EligibleTotalBase: Decimal;
        ExistingQty: Decimal;
        LPQtyBase: Decimal;
        AvailableQtyBase: Decimal;
        EligibleQtyBase: Decimal;
        QtyPerUOM: Decimal;
        BinCodeText: Text;
        FilterText: Text;
    begin
        WhseShipmentLine.SetRange("No.", ConfiguredShipmentNo);
        WhseShipmentLine.SetRange("Source Type", Database::"Sales Line");
        WhseShipmentLine.SetRange("Location Code", LocationCode);
        WhseShipmentLine.SetRange("Item No.", ItemNo);
        WhseShipmentLine.SetRange("Variant Code", VariantCode);
        WhseShipmentLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if WhseShipmentLine.FindSet() then
            repeat
                RequiredQtyBase += WhseShipmentLine."Qty. Outstanding (Base)";
            until WhseShipmentLine.Next() = 0;
        if RequiredQtyBase <= 0 then
            exit('');
        if not Item.Get(ItemNo) then
            exit('');

        LP.SetRange("Location Code", LocationCode);
        LP.SetRange(Status, LP.Status::Built);
        if ToBinCode = '' then
            LP.SetFilter("Bin Code", '<>%1', '')
        else
            LP.SetFilter("Bin Code", '<>%1&<>%2', '', ToBinCode);
        if LP.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetRange("Item No.", ItemNo);
                LPLine.SetRange("Variant Code", VariantCode);
                LPLine.SetFilter(Quantity, '>0');
                if LPLine.FindSet() then
                    repeat
                        QtyPerUOM := 1;
                        if (LPLine."Unit of Measure" <> '') and
                           (LPLine."Unit of Measure" <> Item."Base Unit of Measure")
                        then
                            if not ItemUOM.Get(ItemNo, LPLine."Unit of Measure") then
                                QtyPerUOM := 0
                            else
                                QtyPerUOM := ItemUOM."Qty. per Unit of Measure";
                        LPQtyBase := LPLine.Quantity * QtyPerUOM;
                        if LPQtyBase > 0 then
                            if LPQtyByBin.Get(LP."Bin Code", ExistingQty) then
                                LPQtyByBin.Set(LP."Bin Code", ExistingQty + LPQtyBase)
                            else
                                LPQtyByBin.Add(LP."Bin Code", LPQtyBase);
                    until LPLine.Next() = 0;
            until LP.Next() = 0;

        foreach BinCodeText in LPQtyByBin.Keys() do begin
            Clear(AvailableQtyBase);
            BinContent.Reset();
            BinContent.SetRange("Location Code", LocationCode);
            BinContent.SetRange("Bin Code", CopyStr(BinCodeText, 1, MaxStrLen(BinContent."Bin Code")));
            BinContent.SetRange("Item No.", ItemNo);
            BinContent.SetRange("Variant Code", VariantCode);
            if BinContent.FindSet() then
                repeat
                    AvailableQtyBase += BinContent.CalcQtyAvailToPick(0);
                until BinContent.Next() = 0;
            LPQtyByBin.Get(BinCodeText, LPQtyBase);
            EligibleQtyBase := Minimum(LPQtyBase, AvailableQtyBase);
            if EligibleQtyBase > 0 then begin
                if FilterText <> '' then
                    FilterText += '|';
                FilterText += BinCodeText;
                if StrLen(FilterText) > 250 then
                    exit('');
                EligibleTotalBase += EligibleQtyBase;
            end;
        end;
        // Do not prefer LP bins unless they cover the full shipment demand.
        if EligibleTotalBase < RequiredQtyBase then
            exit('');
        exit(FilterText);
    end;

    local procedure IsConfiguredShipmentSource(SourceNo: Code[20]; SourceLineNo: Integer): Boolean
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
    begin
        if (ConfiguredShipmentNo = '') or (SourceNo = '') then
            exit(false);
        WhseShipmentLine.SetRange("No.", ConfiguredShipmentNo);
        WhseShipmentLine.SetRange("Source Type", Database::"Sales Line");
        WhseShipmentLine.SetRange("Source No.", SourceNo);
        WhseShipmentLine.SetRange("Source Line No.", SourceLineNo);
        exit(not WhseShipmentLine.IsEmpty());
    end;

    local procedure FindUniqueSourceLP(PickLine: Record "Warehouse Activity Line"): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        CandidateLPNo: Code[20];
    begin
        LP.SetRange("Location Code", PickLine."Location Code");
        LP.SetRange("Bin Code", PickLine."Bin Code");
        LP.SetRange(Status, LP.Status::Built);
        if LP.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetRange("Item No.", PickLine."Item No.");
                LPLine.SetRange("Variant Code", PickLine."Variant Code");
                if PickLine."Lot No." <> '' then
                    LPLine.SetRange("Lot No.", PickLine."Lot No.");
                if PickLine."Serial No." <> '' then
                    LPLine.SetRange("Serial No.", PickLine."Serial No.");
                LPLine.SetFilter(Quantity, '>0');
                if not LPLine.IsEmpty() then begin
                    if (CandidateLPNo <> '') and (CandidateLPNo <> LP."No.") then
                        exit('');
                    CandidateLPNo := LP."No.";
                end;
            until LP.Next() = 0;
        exit(CandidateLPNo);
    end;

    local procedure Minimum(LeftValue: Decimal; RightValue: Decimal): Decimal
    begin
        if LeftValue < RightValue then
            exit(LeftValue);
        exit(RightValue);
    end;

    var
        ConfiguredShipmentNo: Code[20];
        PreferredFilterByItem: Dictionary of [Text, Text];
}
