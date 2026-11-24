/// <summary>
/// Saha hatası (DKC, 24 Kas 2026): bir yerleştirme LP numarası yazılmamış
/// satırlarla (ör. BC ekranından ya da tek satır halinde) kaydedildiğinde stok
/// hedef rafa geçiyor, LP'ler ise silinmiş yerleştirmeye "Atanmış" olarak giriş
/// rafında kalıyordu (PU000444/445: 51 LP). Yerleştirme belgesi hangi yoldan
/// kapanırsa kapansın, ona atanmış LP'ler kayıtlı yerleştirme satırlarından
/// bulunan hedef rafa taşınır ve ataması kaldırılır.
/// </summary>
codeunit 72486 "DOPSWHS LP Assign Reconcile"
{
    Permissions = tabledata "DOPSWHS LP Header" = rm;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Activity Header", 'OnAfterDeleteEvent', '', false, false)]
    local procedure OnAfterDeleteActivityHeader(var Rec: Record "Warehouse Activity Header"; RunTrigger: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
        LpNos: List of [Code[20]];
        LpNo: Code[20];
    begin
        if Rec.IsTemporary() then
            exit;
        if Rec.Type <> Rec.Type::"Put-away" then
            exit;
        LP.SetRange(Status, LP.Status::Assigned);
        LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::WhsePutaway);
        LP.SetRange("Assigned Document No.", Rec."No.");
        if LP.FindSet() then
            repeat
                LpNos.Add(LP."No.");
            until LP.Next() = 0;
        foreach LpNo in LpNos do
            if LP.Get(LpNo) then
                ReconcilePutAwayLp(LP, Rec."No.");
    end;

    /// <summary>
    /// API onarımı: LP'nin atandığı belge artık yoksa atamayı düzeltir.
    /// Belge hâlâ açıksa hiçbir şey yapmaz. Sonuç metni döner.
    /// </summary>
    procedure ReconcileStaleAssignment(var LP: Record "DOPSWHS LP Header"): Text
    var
        WhseActivityHeader: Record "Warehouse Activity Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        BinBefore: Code[20];
    begin
        if LP.Status <> LP.Status::Assigned then
            exit('Atanmış değil');
        case LP."Assigned Document Type" of
            LP."Assigned Document Type"::WhsePutaway:
                begin
                    if WhseActivityHeader.Get(WhseActivityHeader.Type::"Put-away", LP."Assigned Document No.") then
                        exit('Belge açık');
                    BinBefore := LP."Bin Code";
                    ReconcilePutAwayLp(LP, LP."Assigned Document No.");
                    LP.Get(LP."No.");
                    exit(StrSubstNo('%1 -> %2 (%3)', BinBefore, LP."Bin Code", Format(LP.Status)));
                end;
            LP."Assigned Document Type"::WhsePick:
                if WhseActivityHeader.Get(WhseActivityHeader.Type::Pick, LP."Assigned Document No.") then
                    exit('Belge açık');
            LP."Assigned Document Type"::WhseMovement:
                if WhseActivityHeader.Get(WhseActivityHeader.Type::Movement, LP."Assigned Document No.") then
                    exit('Belge açık');
            LP."Assigned Document Type"::WhseReceipt:
                if WhseReceiptHeader.Get(LP."Assigned Document No.") then
                    exit('Belge açık');
            LP."Assigned Document Type"::WhseShipment:
                if WhseShipmentHeader.Get(LP."Assigned Document No.") then
                    exit('Belge açık');
            else
                exit('Bu belge türü otomatik düzeltilmez');
        end;
        LPMgt.Release(LP);
        exit('Atama kaldırıldı');
    end;

    local procedure ReconcilePutAwayLp(var LP: Record "DOPSWHS LP Header"; PutAwayNo: Code[20])
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        TargetBin: Code[20];
        SourceBin: Code[20];
        TargetLocation: Code[10];
    begin
        if (LP.Status <> LP.Status::Assigned) or
           (LP."Assigned Document Type" <> LP."Assigned Document Type"::WhsePutaway) or
           (LP."Assigned Document No." <> PutAwayNo)
        then
            exit;
        if FindRegisteredPlaceBin(LP, PutAwayNo, TargetLocation, TargetBin) and
           ((LP."Bin Code" <> TargetBin) or (LP."Location Code" <> TargetLocation))
        then begin
            SourceBin := LP."Bin Code";
            LP.Validate("Location Code", TargetLocation);
            LP.Validate("Bin Code", TargetBin);
            LP.Modify(true);
            LPMgt.WriteToLedger(
                LP, Enum::"DOPSWHS LP Action"::Moved,
                SourceBin, TargetBin, 0, '', '', PutAwayNo);
        end;
        LPMgt.Release(LP);
    end;

    /// <summary>
    /// Kayıtlı yerleştirmenin Yerleştir satırlarından LP'nin hedefini bulur:
    /// önce LP numarası taşıyan satır; yoksa LP içindeki ürünlerin yerleştirildiği
    /// tek raf. Ürünler birden fazla rafa dağıtıldıysa tahmin edilmez (false).
    /// </summary>
    local procedure FindRegisteredPlaceBin(LP: Record "DOPSWHS LP Header"; PutAwayNo: Code[20]; var LocationCode: Code[10]; var BinCode: Code[20]): Boolean
    var
        RegHeader: Record "Registered Whse. Activity Hdr.";
        RegLine: Record "Registered Whse. Activity Line";
        LPLine: Record "DOPSWHS LP Line";
        Candidate: Code[20];
        Found: Boolean;
    begin
        LocationCode := '';
        BinCode := '';
        RegHeader.SetRange(Type, RegHeader.Type::"Put-away");
        RegHeader.SetRange("Whse. Activity No.", PutAwayNo);
        if not RegHeader.FindSet() then
            exit(false);
        repeat
            RegLine.SetRange("Activity Type", RegHeader.Type);
            RegLine.SetRange("No.", RegHeader."No.");
            RegLine.SetRange("Action Type", RegLine."Action Type"::Place);
            RegLine.SetRange("LP No.", LP."No.");
            if RegLine.FindLast() then begin
                LocationCode := RegLine."Location Code";
                BinCode := RegLine."Bin Code";
                exit(BinCode <> '');
            end;
        until RegHeader.Next() = 0;

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit(false);
        repeat
            RegHeader.FindSet();
            repeat
                RegLine.Reset();
                RegLine.SetRange("Activity Type", RegHeader.Type);
                RegLine.SetRange("No.", RegHeader."No.");
                RegLine.SetRange("Action Type", RegLine."Action Type"::Place);
                RegLine.SetRange("Item No.", LPLine."Item No.");
                RegLine.SetRange("Variant Code", LPLine."Variant Code");
                if RegLine.FindSet() then
                    repeat
                        if (LPLine."Lot No." = '') or (RegLine."Lot No." = '') or (RegLine."Lot No." = LPLine."Lot No.") then begin
                            Candidate := RegLine."Bin Code";
                            if not Found then begin
                                Found := true;
                                BinCode := Candidate;
                                LocationCode := RegLine."Location Code";
                            end else
                                if Candidate <> BinCode then
                                    exit(false);
                        end;
                    until RegLine.Next() = 0;
            until RegHeader.Next() = 0;
        until LPLine.Next() = 0;
        exit(Found and (BinCode <> ''));
    end;

    // =====================================================================
    // Lot fazlası (DKC, 24 Kas 2026): ambar lot izlemesi kapalı üründe lot
    // yalnız madde defterindedir. Üretim tüketimi/negatif düzeltme bir lotu
    // LP'den değil serbest raftan düşse de LP satırları o lotu taşımaya devam
    // ediyor; "LP'lere konmuş" miktar lot stokunu aşınca aynı lotla yeni LP
    // kurulamıyordu. LP'deki lot miktarı lotun kalan stokunu geçemez.
    // =====================================================================

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", 'OnAfterInsertItemLedgEntry', '', false, false)]
    local procedure OnAfterInsertItemLedgEntry(var ItemLedgerEntry: Record "Item Ledger Entry"; ItemJournalLine: Record "Item Journal Line")
    var
        PreferredLp: Code[20];
    begin
        if ItemLedgerEntry.IsTemporary() or ItemLedgerEntry.Positive or (ItemLedgerEntry."Lot No." = '') then
            exit;
        // Satış ve transferde LP'yi LP Propagation kesin olarak düşer.
        if not (ItemLedgerEntry."Entry Type" in [ItemLedgerEntry."Entry Type"::Consumption, ItemLedgerEntry."Entry Type"::"Negative Adjmt."]) then
            exit;
        PreferredLp := ItemJournalLine."DOPSWHS LP No.";
        if PreferredLp = '' then
            PreferredLp := ItemLedgerEntry."DOPSWHS LP No.";
        TrimLotOverAllocation(
            ItemLedgerEntry."Item No.", ItemLedgerEntry."Lot No.", ItemLedgerEntry."Location Code",
            PreferredLp, CopyStr(StrSubstNo('LOT%1', ItemLedgerEntry."Entry No."), 1, 20));
    end;

    /// <summary>
    /// Lotun lokasyondaki kalan stoğunu aşan LP lot miktarını düşer. Önce
    /// tercih edilen LP (tüketimin yapıldığı LP), sonra raf stoğundan fazla LP
    /// gösteren raflar, en son en eski LP'ler. Düşülen miktar döner.
    /// </summary>
    procedure TrimLotOverAllocation(ItemNo: Code[20]; LotNo: Code[50]; LocationCode: Code[10]; PreferredLpNo: Code[20]; Reference: Code[20]) Trimmed: Decimal
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        ItemLedgerEntry: Record "Item Ledger Entry";
        Excess: Decimal;
        Pass: Integer;
    begin
        if (ItemNo = '') or (LotNo = '') then
            exit(0);
        if not Item.Get(ItemNo) then
            exit(0);
        if (Item."Item Tracking Code" = '') or not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit(0);
        if ItemTrackingCode."Lot Warehouse Tracking" or not ItemTrackingCode."Lot Specific Tracking" then
            exit(0);
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange(Open, true);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.CalcSums("Remaining Quantity");
        Excess := LotOnLpBase(Item, LotNo, LocationCode) - ItemLedgerEntry."Remaining Quantity";
        for Pass := 0 to 2 do
            if Excess > 0.00001 then
                Trimmed += TrimPass(Item, LotNo, LocationCode, PreferredLpNo, Reference, Pass, Excess);
    end;

    local procedure TrimPass(Item: Record Item; LotNo: Code[50]; LocationCode: Code[10]; PreferredLpNo: Code[20]; Reference: Code[20]; Pass: Integer; var Excess: Decimal) Trimmed: Decimal
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Keys: List of [Text];
        KeyText: Text;
        LineQtyBase: Decimal;
        TakeBase: Decimal;
        BinPhantom: Decimal;
        Ordinal: Integer;
    begin
        LPLine.SetRange("Item No.", Item."No.");
        LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if (LPHeader."Location Code" = LocationCode) and
                       (LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned])
                    then
                        case Pass of
                            0:
                                if (PreferredLpNo <> '') and (LPLine."LP No." = PreferredLpNo) then
                                    Keys.Add(LPLine."LP No." + '|' + Format(LPLine."Line No."));
                            1:
                                if BinOverAllocation(Item, LocationCode, LPHeader."Bin Code") > 0.00001 then
                                    Keys.Add(LPLine."LP No." + '|' + Format(LPLine."Line No."));
                            2:
                                Keys.Add(LPLine."LP No." + '|' + Format(LPLine."Line No."));
                        end;
            until LPLine.Next() = 0;

        foreach KeyText in Keys do
            if Excess > 0.00001 then
                if LPLine.Get(CopyStr(KeyText.Split('|').Get(1), 1, 20), EvaluateInt(KeyText.Split('|').Get(2))) then begin
                    LPHeader.Get(LPLine."LP No.");
                    LineQtyBase := LineBase(Item, LPLine);
                    TakeBase := LineQtyBase;
                    if TakeBase > Excess then
                        TakeBase := Excess;
                    if Pass = 1 then begin
                        BinPhantom := BinOverAllocation(Item, LocationCode, LPHeader."Bin Code");
                        if TakeBase > BinPhantom then
                            TakeBase := BinPhantom;
                    end;
                    if TakeBase > 0.00001 then begin
                        Ordinal += 1;
                        LPMgt.ConsumeLineForShipment(
                            LPLine."LP No.", LPLine."Line No.", TakeBase,
                            CopyStr(StrSubstNo('%1-%2-%3-%4', Reference, Pass, Ordinal, LPLine."LP No."), 1, 40));
                        Excess -= TakeBase;
                        Trimmed += TakeBase;
                    end;
                end;
    end;

    local procedure EvaluateInt(Value: Text) Result: Integer
    begin
        Evaluate(Result, Value);
    end;

    local procedure LineBase(Item: Record Item; LPLine: Record "DOPSWHS LP Line"): Decimal
    var
        ItemUoM: Record "Item Unit of Measure";
    begin
        if (LPLine."Unit of Measure" <> '') and (LPLine."Unit of Measure" <> Item."Base Unit of Measure") and
           ItemUoM.Get(Item."No.", LPLine."Unit of Measure")
        then
            exit(LPLine.Quantity * ItemUoM."Qty. per Unit of Measure");
        exit(LPLine.Quantity);
    end;

    local procedure LotOnLpBase(Item: Record Item; LotNo: Code[50]; LocationCode: Code[10]) OnLp: Decimal
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("Item No.", Item."No.");
        LPLine.SetRange("Lot No.", LotNo);
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if (LPHeader."Location Code" = LocationCode) and
                       (LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned])
                    then
                        OnLp += LineBase(Item, LPLine);
            until LPLine.Next() = 0;
    end;

    /// <summary>Raftaki aktif LP'lerin bu ürün için gösterdiği miktarın raf stoğunu aşan kısmı (temel birim).</summary>
    local procedure BinOverAllocation(Item: Record Item; LocationCode: Code[10]; BinCode: Code[20]): Decimal
    var
        BinContent: Record "Bin Content";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        BinBase: Decimal;
        OnLp: Decimal;
    begin
        if BinCode = '' then
            exit(0);
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", BinCode);
        BinContent.SetRange("Item No.", Item."No.");
        if BinContent.FindSet() then
            repeat
                BinContent.CalcFields("Quantity (Base)");
                BinBase += BinContent."Quantity (Base)";
            until BinContent.Next() = 0;
        LPHeader.SetRange("Location Code", LocationCode);
        LPHeader.SetRange("Bin Code", BinCode);
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                LPLine.SetRange("LP No.", LPHeader."No.");
                LPLine.SetRange("Item No.", Item."No.");
                if LPLine.FindSet() then
                    repeat
                        OnLp += LineBase(Item, LPLine);
                    until LPLine.Next() = 0;
            until LPHeader.Next() = 0;
        exit(OnLp - BinBase);
    end;

    /// <summary>API/yükseltme: lokasyondaki tüm lotlu LP satırları için lot fazlasını düzeltir.</summary>
    procedure TrimAllLotOverAllocations(Reference: Code[20]) Trimmed: Decimal
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Seen: Dictionary of [Text, Boolean];
        Pending: List of [Text];
        KeyText: Text;
        Parts: List of [Text];
    begin
        LPLine.SetFilter("Lot No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then begin
                    KeyText := LPLine."Item No." + '\' + LPLine."Lot No." + '\' + LPHeader."Location Code";
                    if not Seen.ContainsKey(KeyText) then begin
                        Seen.Add(KeyText, true);
                        Pending.Add(KeyText);
                    end;
                end;
            until LPLine.Next() = 0;
        foreach KeyText in Pending do begin
            Parts := KeyText.Split('\');
            Trimmed += TrimLotOverAllocation(
                CopyStr(Parts.Get(1), 1, 20), CopyStr(Parts.Get(2), 1, 50), CopyStr(Parts.Get(3), 1, 10), '', Reference);
        end;
    end;
}
