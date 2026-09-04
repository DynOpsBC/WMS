codeunit 72439 "DOPSWHS LP Pick Preference"
{
    // Bound only while a DOPSWHS pick is being created. Standard BC ranks Bin
    // Content without knowing which stock is held by a completed LP.
    EventSubscriberInstance = Manual;

    procedure Configure(ShipmentNo: Code[20])
    begin
        ConfiguredShipmentNo := ShipmentNo;
        ForcedLpNo := '';
        ForcedLpBinCode := '';
        Clear(PreferredFilterByItem);
    end;

    /// <summary>
    /// Operatörün seçtiği paleti zorlar. Configure'dan SONRA çağrılır.
    /// Bu modda raf süzgeci, palet tüm talebi karşılasa da karşılamasa da
    /// yalnız seçilen paletin rafına daraltılır; BC kalanı gerekirse başka
    /// raftan toplar ama önce bu palet kullanılır. StampPickLines de üretilen
    /// Take satırlarına bu paleti damgalar.
    /// </summary>
    procedure ConfigureForcedLp(ShipmentNo: Code[20]; LpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        Configure(ShipmentNo);
        if LpNo = '' then
            exit;
        if not LP.Get(LpNo) then
            Error(ForcedLpNotFoundErr, LpNo);
        ForcedLpNo := LP."No.";
        ForcedLpBinCode := LP."Bin Code";
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
                // Zorlanmış palet modunda, o paletin rafından gelen Take
                // satırları doğrudan seçilen paletle damgalanır; rafta birden
                // fazla palet durduğu için FindUniqueSourceLP boş dönse bile
                // operatörün seçimi kaybolmaz.
                if (ForcedLpNo <> '') and (ForcedLpBinCode <> '') and
                   (PickLine."Bin Code" = ForcedLpBinCode) and
                   LpHoldsPickLineItem(ForcedLpNo, PickLine)
                then
                    LPNo := ForcedLpNo
                else
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
        // Zorlanmış palet modunda (temel ambar) raf süzgeci yalnız paletin
        // tüm talebi karşıladığı durumda daraltılır; yetmiyorsa daraltmak
        // toplamanın hiç üretilememesine yol açar. Seçim o durumda da
        // StampPickLines ile damgalanır.
        if ForcedLpNo <> '' then
            if not ForcedLpCoversDemand(LocationCode, ItemNo, VariantCode) then
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
        // GetBinContent normally leaves the temporary buffer in bin-ranking
        // order.  The terminal promise is explicitly bin CODE order.
        TempBinContent.SetCurrentKey("Location Code", "Bin Code", "Item No.", "Variant Code", "Unit of Measure Code");
        TempBinContent.Ascending(true);
        Result := TempBinContent.FindFirst();
        if not Result then begin
            // Reservation/tracking can invalidate an LP candidate. Fall back to
            // standard BC instead of producing an incomplete pick.
            TempBinContent.Reset();
            TempBinContent.DeleteAll();
            exit;
        end;

        // Zorlanmış palet modunda seçilen raf tüm miktarı karşılamıyorsa
        // buffer'ı o rafa kilitlemek eksik toplama üretir. Bu yüzden yalnız
        // raf TAMAMEN yeterliyse aday listesi daraltılır; yetmiyorsa BC'nin
        // tam aday listesi korunur (seçilen raf zaten içinde) ve kalan miktar
        // standart sıralamayla tamamlanır.
        if ForcedLpNo <> '' then
            if BinFilterAvailableQtyBase(TempBinContent, PreferredFilter) + QtyTolerance() < TotalQtytoPickBase then begin
                TempBinContent.Reset();
                exit;
            end;
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Pick", 'OnBeforeFindBWPickBin', '', false, false)]
    local procedure SortBasicWarehousePickBinsByCode(var BinContent: Record "Bin Content"; var IsSetCurrentKeyHandled: Boolean)
    begin
        if ConfiguredShipmentNo = '' then
            exit;
        // Standard basic-warehouse picking can use bin ranking/default first.
        // Override only while this manual subscriber is bound for a DOPSWHS
        // shipment, so source quantity is consumed from the lowest bin code.
        BinContent.SetCurrentKey("Location Code", "Bin Code", "Item No.", "Variant Code", "Unit of Measure Code");
        BinContent.Ascending(true);
        IsSetCurrentKeyHandled := true;
    end;

    /// <summary>Süzgeçteki rafların toplanabilir taban miktarı.</summary>
    local procedure BinFilterAvailableQtyBase(var TempBinContent: Record "Bin Content" temporary; PreferredFilter: Text) AvailableQtyBase: Decimal
    var
        BinContent: Record "Bin Content";
    begin
        TempBinContent.SetFilter("Bin Code", PreferredFilter);
        if TempBinContent.FindSet() then
            repeat
                if BinContent.Get(
                    TempBinContent."Location Code", TempBinContent."Bin Code",
                    TempBinContent."Item No.", TempBinContent."Variant Code",
                    TempBinContent."Unit of Measure Code")
                then
                    AvailableQtyBase += BinContent.CalcQtyAvailToPick(0);
            until TempBinContent.Next() = 0;
        exit(AvailableQtyBase);
    end;

    local procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
    end;

    /// <summary>Seçilen paletin rafı bu ürün için sevkiyatın açık talebini
    /// tek başına karşılıyor mu?</summary>
    local procedure ForcedLpCoversDemand(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]): Boolean
    var
        BinContent: Record "Bin Content";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        RequiredQtyBase: Decimal;
        AvailableQtyBase: Decimal;
    begin
        if ForcedLpBinCode = '' then
            exit(false);
        WhseShipmentLine.SetRange("No.", ConfiguredShipmentNo);
        WhseShipmentLine.SetRange("Location Code", LocationCode);
        WhseShipmentLine.SetRange("Item No.", ItemNo);
        WhseShipmentLine.SetRange("Variant Code", VariantCode);
        WhseShipmentLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if WhseShipmentLine.FindSet() then
            repeat
                RequiredQtyBase += WhseShipmentLine."Qty. Outstanding (Base)";
            until WhseShipmentLine.Next() = 0;
        if RequiredQtyBase <= 0 then
            exit(false);

        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", ForcedLpBinCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        if BinContent.FindSet() then
            repeat
                AvailableQtyBase += BinContent.CalcQtyAvailToPick(0);
            until BinContent.Next() = 0;
        exit(AvailableQtyBase + QtyTolerance() >= RequiredQtyBase);
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
        Bin: Record Bin;
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

        // Operatör paleti seçtiyse tam talebi karşılama şartı UYGULANMAZ:
        // seçilen paletin rafı tek aday olur, kalan miktarı BC standart
        // sıralamasıyla başka raftan tamamlar.
        if ForcedLpNo <> '' then begin
            if ForcedLpBinCode = '' then
                exit('');
            if (ToBinCode <> '') and (ForcedLpBinCode = ToBinCode) then
                exit('');
            if not LpHoldsItem(ForcedLpNo, ItemNo, VariantCode) then
                exit('');
            exit(ForcedLpBinCode);
        end;

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

        // Dictionary key order is undefined.  Passing every eligible bin to
        // Create Pick therefore let BC choose any combination (for example
        // 1,880 from A.A01.12 + 4,000 from A.A02.11 although A.A01.11 alone
        // held 5,880).  Walk the real Bin table by code and stop as soon as
        // the shipment demand is covered.  The report is then physically
        // unable to skip an earlier eligible LP bin for a later one.
        Bin.SetRange("Location Code", LocationCode);
        if ToBinCode <> '' then
            Bin.SetFilter(Code, '<>%1', ToBinCode);
        if Bin.FindSet() then
            repeat
                BinCodeText := Bin.Code;
                if LPQtyByBin.ContainsKey(BinCodeText) then begin
            Clear(AvailableQtyBase);
            BinContent.Reset();
            BinContent.SetRange("Location Code", LocationCode);
                    BinContent.SetRange("Bin Code", Bin.Code);
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
            until (Bin.Next() = 0) or (EligibleTotalBase + QtyTolerance() >= RequiredQtyBase);
        // Do not prefer LP bins unless they cover the full shipment demand.
        if EligibleTotalBase + QtyTolerance() < RequiredQtyBase then
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

    local procedure LpHoldsItem(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetFilter(Quantity, '>0');
        exit(not LPLine.IsEmpty());
    end;

    local procedure LpHoldsPickLineItem(LpNo: Code[20]; PickLine: Record "Warehouse Activity Line"): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", PickLine."Item No.");
        LPLine.SetRange("Variant Code", PickLine."Variant Code");
        if PickLine."Lot No." <> '' then
            LPLine.SetRange("Lot No.", PickLine."Lot No.");
        if PickLine."Serial No." <> '' then
            LPLine.SetRange("Serial No.", PickLine."Serial No.");
        LPLine.SetFilter(Quantity, '>0');
        exit(not LPLine.IsEmpty());
    end;

    local procedure Minimum(LeftValue: Decimal; RightValue: Decimal): Decimal
    begin
        if LeftValue < RightValue then
            exit(LeftValue);
        exit(RightValue);
    end;

    var
        ConfiguredShipmentNo: Code[20];
        ForcedLpNo: Code[20];
        ForcedLpBinCode: Code[20];
        PreferredFilterByItem: Dictionary of [Text, Text];
        ForcedLpNotFoundErr: Label '%1 numaralı taşıma kabı (LP) bulunamadı.', Comment = '%1 = LP No.';
}
