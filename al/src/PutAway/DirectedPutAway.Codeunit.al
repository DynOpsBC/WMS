codeunit 72044 "DOPSWHS Directed PutAway" implements "DOPSWHS PutAway Strategy"
{
    Access = Public;

    procedure SuggestBin(Item: Record Item; Qty: Decimal; LocationCode: Code[10]; var BinCode: Code[20]; var Reason: Text): Boolean
    var
        Bin: Record Bin;
        BestBin: Record Bin;
        CustomDimensions: Dictionary of [Text, Text];
        HasBestBin: Boolean;
    begin
        CustomDimensions.Add('Category', 'PutAway');
        Session.LogMessage('DOPSWHS-PutAway-SuggestBin', StrSubstNo('Suggest bin for item %1 qty %2 location %3', Item."No.", Qty, LocationCode), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);

        Clear(BinCode);
        Clear(Reason);

        Bin.SetRange("Location Code", LocationCode);
        if Bin.FindSet() then
            repeat
                if IsEligibleBin(Bin, Item, Qty) then
                    if IsPreferred(Bin, BestBin, HasBestBin) then begin
                        BestBin := Bin;
                        HasBestBin := true;
                    end;
            until Bin.Next() = 0;

        if HasBestBin then begin
            BinCode := BestBin.Code;
            Reason := StrSubstNo('Selected zone %1 rank %2, bin rank %3.', BestBin."Zone Code", ZoneRank(BestBin), BestBin."Bin Ranking");
            exit(true);
        end;

        Reason := StrSubstNo('No eligible put-away bin found for item %1 at location %2.', Item."No.", LocationCode);
        Session.LogMessage('DOPSWHS-PutAway-NoBin', Reason, Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
        exit(false);
    end;

    /// <summary>
    /// BADE (23 Eki 2026, 1.14.1.152 - Merve): yerleştirme belgesindeki her palet (LP)
    /// için BOŞ göz önerisi. LP'siz Koy satırı kendi başına bir palet sayılır; aynı LP'nin
    /// bütün Koy satırları aynı öneriyi alır. Sıra:
    ///  1. BC'nin yerleştirme şablonunun Koy satırına yazdığı göz boş ve uygunsa o göz (source BC).
    ///  2. Değilse aynı bölgedeki (Zone) boş ve uygun gözler: Bin Ranking yüksek olan önce,
    ///     eşitse göz kodu A'dan Z'ye (source EMPTY).
    ///  3. Aynı bölgede yoksa lokasyonun diğer bölgelerinde aynı sıra (source EMPTY).
    ///  4. Hiç boş göz yoksa BC'nin gözü öneri olarak kalır (source BC_FALLBACK).
    /// Uygun göz: aynı lokasyon; Block Movement boş veya yalnız Outbound; Dedicated,
    /// Adjustment Bin, Cross-Dock Bin değil; lokasyonun mal kabul/sevk/düzeltme/çapraz sevk/
    /// atölye/montaj/proje gözü değil; göz tipi varsa "Put Away" açık, "Receive" ve "Ship"
    /// kapalı (yönlendirilmiş lokasyonda göz tipi zorunlu); lokasyonda Check Whse. Class
    /// açıksa ürünle aynı ambar sınıfı.
    /// Boş göz: Bin.Empty işaretli; göz içeriğinde stok, bekleyen yerleştirme veya pozitif
    /// düzeltme yok; başka bir belgenin açık Koy satırı bu göze gitmiyor; gözde aktif LP yok;
    /// aynı çağrıda başka bir palete önerilmedi.
    /// Hiçbir kaydı değiştirmez: öneri yalnız gösterilir; operatör hedef gözü okutunca
    /// setPlacementFromLp Koy satırını günceller.
    /// </summary>
    procedure SuggestEmptyBinsJson(PutAwayNo: Code[20]): Text
    var
        PlaceLine: Record "Warehouse Activity Line";
        Location: Record Location;
        Item: Record Item;
        Found: Record Bin;
        Result: JsonArray;
        Entry: JsonObject;
        SpecialBins: List of [Code[20]];
        UsedBins: List of [Code[20]];
        BinTypeOk: Dictionary of [Code[10], Boolean];
        GroupBin: Dictionary of [Text, Code[20]];
        GroupZone: Dictionary of [Text, Code[10]];
        GroupSource: Dictionary of [Text, Text];
        GroupKey: Text;
        SuggestedBin: Code[20];
        SuggestedZone: Code[10];
        Source: Text;
        WhseClass: Code[10];
        ResultText: Text;
    begin
        PlaceLine.SetRange("Activity Type", PlaceLine."Activity Type"::"Put-away");
        PlaceLine.SetRange("No.", PutAwayNo);
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        PlaceLine.SetFilter("Qty. Outstanding", '>0');
        if PlaceLine.FindSet() then
            repeat
                if PlaceLine."LP No." <> '' then
                    GroupKey := 'LP|' + PlaceLine."LP No."
                else
                    GroupKey := 'LINE|' + Format(PlaceLine."Line No.");
                if not GroupBin.ContainsKey(GroupKey) then begin
                    if Location.Code <> PlaceLine."Location Code" then begin
                        if not Location.Get(PlaceLine."Location Code") then
                            Clear(Location);
                        CollectSpecialBins(Location, SpecialBins);
                    end;
                    WhseClass := '';
                    if Location."Check Whse. Class" and Item.Get(PlaceLine."Item No.") then
                        WhseClass := Item."Warehouse Class Code";
                    SuggestedBin := '';
                    SuggestedZone := '';
                    Source := 'BC_FALLBACK';
                    if IsSuggestableBinCode(PlaceLine."Location Code", PlaceLine."Bin Code", Location, WhseClass, PutAwayNo, SpecialBins, UsedBins, BinTypeOk, Found) then
                        Source := 'BC'
                    else
                        if FindEmptyBin(PlaceLine."Location Code", PlaceLine."Zone Code", true, Location, WhseClass, PutAwayNo, SpecialBins, UsedBins, BinTypeOk, Found) then
                            Source := 'EMPTY'
                        else
                            if FindEmptyBin(PlaceLine."Location Code", PlaceLine."Zone Code", false, Location, WhseClass, PutAwayNo, SpecialBins, UsedBins, BinTypeOk, Found) then
                                Source := 'EMPTY';
                    if Source = 'BC_FALLBACK' then begin
                        SuggestedBin := PlaceLine."Bin Code";
                        SuggestedZone := PlaceLine."Zone Code";
                    end else begin
                        SuggestedBin := Found.Code;
                        SuggestedZone := Found."Zone Code";
                        UsedBins.Add(Found.Code);
                    end;
                    GroupBin.Add(GroupKey, SuggestedBin);
                    GroupZone.Add(GroupKey, SuggestedZone);
                    GroupSource.Add(GroupKey, Source);
                end;
                Clear(Entry);
                Entry.Add('lineNo', PlaceLine."Line No.");
                Entry.Add('lpNo', PlaceLine."LP No.");
                Entry.Add('binCode', GroupBin.Get(GroupKey));
                Entry.Add('zoneCode', GroupZone.Get(GroupKey));
                Entry.Add('source', GroupSource.Get(GroupKey));
                Result.Add(Entry);
            until PlaceLine.Next() = 0;
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>
    /// Boş göz arar. SameZone = true: yalnız ZoneCode bölgesi; false: diğer bölgeler
    /// (ZoneCode boşsa tüm lokasyon). Sıra: Bin Ranking azalan, eşitse göz kodu artan.
    /// </summary>
    local procedure FindEmptyBin(LocationCode: Code[10]; ZoneCode: Code[10]; SameZone: Boolean; Location: Record Location; WhseClass: Code[10]; PutAwayNo: Code[20]; var SpecialBins: List of [Code[20]]; var UsedBins: List of [Code[20]]; var BinTypeOk: Dictionary of [Code[10], Boolean]; var Found: Record Bin): Boolean
    var
        RankBin: Record Bin;
        Bin: Record Bin;
        Level: Integer;
    begin
        if SameZone and (ZoneCode = '') then
            exit(false);
        ApplyEmptyBinFilters(RankBin, LocationCode, ZoneCode, SameZone, Location, WhseClass);
        RankBin.SetCurrentKey("Bin Ranking");
        RankBin.Ascending(false);
        if not RankBin.FindFirst() then
            exit(false);
        repeat
            Level := RankBin."Bin Ranking";
            Bin.Reset();
            ApplyEmptyBinFilters(Bin, LocationCode, ZoneCode, SameZone, Location, WhseClass);
            Bin.SetRange("Bin Ranking", Level);
            Bin.SetCurrentKey("Location Code", "Zone Code", Code);
            if Bin.FindSet() then
                repeat
                    if not UsedBins.Contains(Bin.Code) then
                        if IsEmptyPutAwayBin(Bin, Location, PutAwayNo, SpecialBins, BinTypeOk) then begin
                            Found := Bin;
                            exit(true);
                        end;
                until Bin.Next() = 0;
            RankBin.SetFilter("Bin Ranking", '<%1', Level);
        until not RankBin.FindFirst();
        exit(false);
    end;

    local procedure ApplyEmptyBinFilters(var Bin: Record Bin; LocationCode: Code[10]; ZoneCode: Code[10]; SameZone: Boolean; Location: Record Location; WhseClass: Code[10])
    begin
        Bin.SetRange("Location Code", LocationCode);
        if SameZone then
            Bin.SetRange("Zone Code", ZoneCode)
        else
            if ZoneCode <> '' then
                Bin.SetFilter("Zone Code", '<>%1', ZoneCode);
        Bin.SetRange(Empty, true);
        Bin.SetRange(Dedicated, false);
        Bin.SetRange("Adjustment Bin", false);
        Bin.SetRange("Cross-Dock Bin", false);
        Bin.SetFilter("Block Movement", '%1|%2', Bin."Block Movement"::" ", Bin."Block Movement"::Outbound);
        if Location."Check Whse. Class" then
            Bin.SetRange("Warehouse Class Code", WhseClass);
    end;

    /// <summary>BC'nin önerdiği gözün kendisi boş ve uygun mu (ApplyEmptyBinFilters ile aynı kurallar).</summary>
    local procedure IsSuggestableBinCode(LocationCode: Code[10]; BinCode: Code[20]; Location: Record Location; WhseClass: Code[10]; PutAwayNo: Code[20]; var SpecialBins: List of [Code[20]]; var UsedBins: List of [Code[20]]; var BinTypeOk: Dictionary of [Code[10], Boolean]; var Found: Record Bin): Boolean
    var
        Bin: Record Bin;
    begin
        if BinCode = '' then
            exit(false);
        if UsedBins.Contains(BinCode) then
            exit(false);
        if not Bin.Get(LocationCode, BinCode) then
            exit(false);
        if (not Bin.Empty) or Bin.Dedicated or Bin."Adjustment Bin" or Bin."Cross-Dock Bin" then
            exit(false);
        if not (Bin."Block Movement" in [Bin."Block Movement"::" ", Bin."Block Movement"::Outbound]) then
            exit(false);
        if Location."Check Whse. Class" and (Bin."Warehouse Class Code" <> WhseClass) then
            exit(false);
        if not IsEmptyPutAwayBin(Bin, Location, PutAwayNo, SpecialBins, BinTypeOk) then
            exit(false);
        Found := Bin;
        exit(true);
    end;

    local procedure IsEmptyPutAwayBin(Bin: Record Bin; Location: Record Location; PutAwayNo: Code[20]; var SpecialBins: List of [Code[20]]; var BinTypeOk: Dictionary of [Code[10], Boolean]): Boolean
    var
        BinType: Record "Bin Type";
        BinContent: Record "Bin Content";
        ActivityLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        TypeOk: Boolean;
    begin
        if SpecialBins.Contains(Bin.Code) then
            exit(false);
        if Bin."Bin Type Code" = '' then begin
            if Location."Directed Put-away and Pick" then
                exit(false);
        end else begin
            if not BinTypeOk.Get(Bin."Bin Type Code", TypeOk) then begin
                TypeOk := false;
                if BinType.Get(Bin."Bin Type Code") then
                    TypeOk := BinType."Put Away" and (not BinType.Receive) and (not BinType.Ship);
                BinTypeOk.Add(Bin."Bin Type Code", TypeOk);
            end;
            if not TypeOk then
                exit(false);
        end;

        BinContent.SetRange("Location Code", Bin."Location Code");
        BinContent.SetRange("Bin Code", Bin.Code);
        if BinContent.FindSet() then
            repeat
                // Bekleyen yerleştirmeler aşağıda Koy satırlarından (bu belge hariç) aranır;
                // "Put-away Quantity" bu belgenin kendi BC önerisini de sayardı.
                BinContent.CalcFields("Quantity (Base)", "Positive Adjmt. Qty. (Base)");
                if (BinContent."Quantity (Base)" <> 0) or (BinContent."Positive Adjmt. Qty. (Base)" <> 0) then
                    exit(false);
            until BinContent.Next() = 0;

        ActivityLine.SetRange("Location Code", Bin."Location Code");
        ActivityLine.SetRange("Bin Code", Bin.Code);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.SetFilter("Qty. Outstanding", '>0');
        if ActivityLine.FindSet() then
            repeat
                if (ActivityLine."Activity Type" <> ActivityLine."Activity Type"::"Put-away") or (ActivityLine."No." <> PutAwayNo) then
                    exit(false);
            until ActivityLine.Next() = 0;

        LP.SetRange("Location Code", Bin."Location Code");
        LP.SetRange("Bin Code", Bin.Code);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        exit(LP.IsEmpty());
    end;

    local procedure CollectSpecialBins(Location: Record Location; var SpecialBins: List of [Code[20]])
    begin
        Clear(SpecialBins);
        AddSpecialBin(SpecialBins, Location."Receipt Bin Code");
        AddSpecialBin(SpecialBins, Location."Shipment Bin Code");
        AddSpecialBin(SpecialBins, Location."Adjustment Bin Code");
        AddSpecialBin(SpecialBins, Location."Cross-Dock Bin Code");
        AddSpecialBin(SpecialBins, Location."Open Shop Floor Bin Code");
        AddSpecialBin(SpecialBins, Location."To-Assembly Bin Code");
        AddSpecialBin(SpecialBins, Location."From-Assembly Bin Code");
        AddSpecialBin(SpecialBins, Location."Asm.-to-Order Shpt. Bin Code");
        AddSpecialBin(SpecialBins, Location."To-Job Bin Code");
    end;

    local procedure AddSpecialBin(var SpecialBins: List of [Code[20]]; BinCode: Code[20])
    begin
        if (BinCode <> '') and (not SpecialBins.Contains(BinCode)) then
            SpecialBins.Add(BinCode);
    end;

    local procedure IsPreferred(Candidate: Record Bin; CurrentBest: Record Bin; HasBestBin: Boolean): Boolean
    var
        CandidateZoneRank: Integer;
        BestZoneRank: Integer;
    begin
        if not HasBestBin then
            exit(true);

        CandidateZoneRank := ZoneRank(Candidate);
        BestZoneRank := ZoneRank(CurrentBest);
        if CandidateZoneRank <> BestZoneRank then
            exit(CandidateZoneRank > BestZoneRank);
        if Candidate."Bin Ranking" <> CurrentBest."Bin Ranking" then
            exit(Candidate."Bin Ranking" > CurrentBest."Bin Ranking");
        exit(Candidate.Code < CurrentBest.Code);
    end;

    local procedure IsEligibleBin(Bin: Record Bin; Item: Record Item; Qty: Decimal): Boolean
    begin
        if not PassesCapacity(Bin, Item, Qty) then
            exit(false);
        if not PassesMixingRules(Bin, Item) then
            exit(false);
        exit(true);
    end;

    local procedure PassesCapacity(Bin: Record Bin; Item: Record Item; Qty: Decimal): Boolean
    var
        ExistingCubage: Decimal;
        RequiredCubage: Decimal;
    begin
        if Bin."Maximum Cubage" = 0 then
            exit(true);

        ExistingCubage := CalcExistingCubage(Bin);
        RequiredCubage := Item."Unit Volume" * Qty;
        exit((ExistingCubage + RequiredCubage) <= Bin."Maximum Cubage");
    end;

    local procedure CalcExistingCubage(Bin: Record Bin): Decimal
    var
        BinContent: Record "Bin Content";
        ContentItem: Record Item;
        Cubage: Decimal;
    begin
        BinContent.SetRange("Location Code", Bin."Location Code");
        BinContent.SetRange("Bin Code", Bin.Code);
        if BinContent.FindSet() then
            repeat
                if ContentItem.Get(BinContent."Item No.") then
                    Cubage += ContentItem."Unit Volume" * BinContent.Quantity;
            until BinContent.Next() = 0;
        exit(Cubage);
    end;

    local procedure PassesMixingRules(Bin: Record Bin; Item: Record Item): Boolean
    var
        BinContent: Record "Bin Content";
        ContentItem: Record Item;
        ItemCategoryCode: Code[20];
    begin
        ItemCategoryCode := Item."Item Category Code";
        BinContent.SetRange("Location Code", Bin."Location Code");
        BinContent.SetRange("Bin Code", Bin.Code);
        if BinContent.FindSet() then
            repeat
                if ContentItem.Get(BinContent."Item No.") then
                    if (ContentItem."Item Category Code" <> '') and (ItemCategoryCode <> '') and
                       (ContentItem."Item Category Code" <> ItemCategoryCode)
                    then
                        exit(false);
            until BinContent.Next() = 0;
        exit(true);
    end;

    local procedure ZoneRank(Bin: Record Bin): Integer
    var
        Zone: Record Zone;
    begin
        if Zone.Get(Bin."Location Code", Bin."Zone Code") then
            exit(Zone."Zone Ranking");
        exit(0);
    end;
}
