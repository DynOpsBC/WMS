/// <summary>
/// DKC (24 Kas 2026): üretim çıktısı kutu LP'leri ve palet.
///
/// 1) Her parçalı çıktı için BC ayrı bir yerleştirme (Al: çıktı gözü, Koy: depo
///    rafı) açar; satırlar LP'sizdir. Kutu LP'si çıktı gözünde kurulunca kutunun
///    miktarı açık çıktı yerleştirmesinden kendi Al/Koy çiftine ayrılır, çifte LP
///    numarası yazılır ve LP o yerleştirmeye atanır. Yerleştirme kaydedilince ambar
///    girişleri her kutunun LP numarasını taşır, LP hedef rafa geçer.
/// 2) "Palete koy": bir üretim emri satırının çıktı gözündeki tüm kutu LP'leri tek
///    palet LP'sine bağlanır. Palet taşındığında (Hareket/Yerleştirme) her kutunun
///    açık yerleştirmesi aynı hedef rafa kaydedilir, kutusuz kalan LP'ler ve palet
///    başlığı da oraya geçer.
/// </summary>
codeunit 72487 "DOPSWHS Output Pallet Mgmt"
{
    Permissions = tabledata "Warehouse Activity Line" = rimd,
                  tabledata "Warehouse Activity Header" = rm,
                  tabledata "DOPSWHS LP Header" = rimd;

    // ---------------------------------------------------------------
    // 1) Kutu LP'si -> açık çıktı yerleştirmesi
    // ---------------------------------------------------------------

    /// <summary>
    /// LP'nin henüz bağlanmamış miktarını, LP'nin durduğu gözden alan açık bir
    /// üretim çıktısı yerleştirmesine bağlar (Al/Koy çiftine LP numarası yazılır).
    /// AssignToPutAway: LP ayrıca yerleştirmeye atanır (palete koyarken). Satır
    /// eklerken atanmaz; LP açık kalır, sonradan ürün eklenebilir. Bağlanan satır
    /// sayısını döner; uygun yerleştirme yoksa hiçbir şey yapmaz.
    /// </summary>
    procedure LinkLpToOutputPutAway(LpNo: Code[20]; AssignToPutAway: Boolean): Integer
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        AlreadyLinked: Dictionary of [Code[20], Decimal];
        PutAwayNo: Code[20];
        DocNo: Code[20];
        LinkedQty: Decimal;
        LineBase: Decimal;
        Unlinked: Decimal;
        Linked: Integer;
    begin
        if not LP.Get(LpNo) then
            exit(0);
        if (LP."Location Code" = '') or (LP."Bin Code" = '') then
            exit(0);
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            exit(0);
        // Başka bir belgeye (toplama, sevk...) atanmış LP'ye dokunulmaz.
        if (LP.Status = LP.Status::Assigned) and
           (LP."Assigned Document Type" <> LP."Assigned Document Type"::WhsePutaway)
        then
            exit(0);

        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit(0);
        repeat
            // Daha önce bağlanmış miktar (ör. ilk satır eklenirken) satırlardan düşülür;
            // sonradan eklenen miktar ayrıca bağlanır.
            if not AlreadyLinked.Get(LPLine."Item No.", LinkedQty) then begin
                LinkedQty := LinkedBaseQty(LP, LPLine."Item No.", DocNo);
                AlreadyLinked.Add(LPLine."Item No.", LinkedQty);
                if (DocNo <> '') and (PutAwayNo = '') then
                    PutAwayNo := DocNo;
            end;
            LineBase := LpLineBaseQty(LPLine);
            Unlinked := LineBase - LinkedQty;
            if Unlinked > 0.00001 then begin
                AlreadyLinked.Set(LPLine."Item No.", 0);
                DocNo := '';
                if LinkLine(LP, LPLine, Unlinked, DocNo) then
                    Linked += 1;
                if (DocNo <> '') and (PutAwayNo = '') then
                    PutAwayNo := DocNo;
            end else
                AlreadyLinked.Set(LPLine."Item No.", LinkedQty - LineBase);
        until LPLine.Next() = 0;

        // Palete koyarken LP yerleştirmeye atanır: BC ekranından kaydedilse bile
        // "LP Assign Reconcile" LP'yi hedef rafa taşır.
        if AssignToPutAway and (PutAwayNo <> '') then begin
            LP.Get(LP."No.");
            if LP.Status = LP.Status::Open then
                LPMgt.Stop(LP, false);
            if LP.Status = LP.Status::Built then
                LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, PutAwayNo);
        end;
        exit(Linked);
    end;

    /// <summary>LP'ye bağlı açık yerleştirme Al satırlarının toplam taban miktarı.</summary>
    local procedure LinkedBaseQty(LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; var PutAwayNo: Code[20]): Decimal
    var
        TakeLine: Record "Warehouse Activity Line";
    begin
        PutAwayNo := '';
        TakeLine.SetRange("Activity Type", TakeLine."Activity Type"::"Put-away");
        TakeLine.SetRange("Location Code", LP."Location Code");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.SetRange("LP No.", LP."No.");
        TakeLine.SetRange("Item No.", ItemNo);
        TakeLine.SetFilter("Qty. Outstanding", '>0');
        if not TakeLine.FindFirst() then
            exit(0);
        PutAwayNo := TakeLine."No.";
        TakeLine.CalcSums("Qty. Outstanding (Base)");
        exit(TakeLine."Qty. Outstanding (Base)");
    end;

    /// <summary>LP'nin açık yerleştirme satırı var mı (Hareket ekranı bu LP'yi taşıyamaz).</summary>
    procedure HasOpenPutAwayLines(LpNo: Code[20]; var PutAwayNo: Code[20]): Boolean
    var
        TakeLine: Record "Warehouse Activity Line";
    begin
        PutAwayNo := '';
        if LpNo = '' then
            exit(false);
        TakeLine.SetRange("Activity Type", TakeLine."Activity Type"::"Put-away");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.SetRange("LP No.", LpNo);
        TakeLine.SetFilter("Qty. Outstanding", '>0');
        if not TakeLine.FindFirst() then
            exit(false);
        PutAwayNo := TakeLine."No.";
        exit(true);
    end;

    local procedure LinkLine(LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line"; BaseQty: Decimal; var PutAwayNo: Code[20]): Boolean
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        NewLine: Record "Warehouse Activity Line";
        OriginalTake: Record "Warehouse Activity Line";
        OriginalPlace: Record "Warehouse Activity Line";
        PreferredOrderNo: Code[20];
        LineQty: Decimal;
    begin
        if BaseQty <= 0 then
            exit(false);

        TakeLine.SetRange("Activity Type", TakeLine."Activity Type"::"Put-away");
        TakeLine.SetRange("Location Code", LP."Location Code");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.SetRange("Bin Code", LP."Bin Code");
        TakeLine.SetRange("Source Type", Database::"Prod. Order Line");
        TakeLine.SetRange("Item No.", LPLine."Item No.");
        TakeLine.SetRange("Variant Code", LPLine."Variant Code");
        TakeLine.SetRange("LP No.", '');
        TakeLine.SetRange("Qty. Handled", 0);
        TakeLine.SetRange("Breakbulk No.", 0);
        // DKC: ambar lot izlemesi kapalı; yerleştirme satırı lotsuz, LP satırı lotlu.
        if LPLine."Lot No." <> '' then
            TakeLine.SetFilter("Lot No.", '%1|%2', '', LPLine."Lot No.")
        else
            TakeLine.SetRange("Lot No.", '');
        if LPLine."Serial No." <> '' then
            exit(false);

        // Önce kutunun lotunu üreten emrin yerleştirmesi, sonra aynı ürünün diğer
        // çıktı yerleştirmeleri; her birinde önce tam tutan (bir çıktı = bir kutu).
        PreferredOrderNo := OutputOrderForLot(LPLine."Item No.", LPLine."Lot No.");
        if not FindTakeForQty(TakeLine, PlaceLine, BaseQty, PreferredOrderNo) then
            if (PreferredOrderNo = '') or not FindTakeForQty(TakeLine, PlaceLine, BaseQty, '') then
                exit(false);

        PutAwayNo := TakeLine."No.";
        if Abs(TakeLine."Qty. Outstanding (Base)" - BaseQty) <= 0.00001 then begin
            TakeLine."LP No." := LP."No.";
            TakeLine.Modify(true);
            PlaceLine."LP No." := LP."No.";
            PlaceLine.Modify(true);
            exit(true);
        end;

        // Kutunun miktarı ayrı bir Al/Koy çiftine alınır, kalan LP'siz çiftte durur.
        LineQty := Round(BaseQty / QtyPerOf(TakeLine), 0.00001);
        if (LineQty <= 0) or (LineQty >= TakeLine.Quantity) then
            exit(false);
        OriginalTake := TakeLine;
        OriginalPlace := PlaceLine;
        TakeLine.Validate(Quantity, TakeLine.Quantity - LineQty);
        TakeLine.Modify(true);
        PlaceLine.Validate(Quantity, PlaceLine.Quantity - LineQty);
        PlaceLine.Modify(true);
        InsertLpLine(OriginalTake, LP."No.", LineQty, NewLine);
        InsertLpLine(OriginalPlace, LP."No.", LineQty, NewLine);
        exit(true);
    end;

    local procedure FindTakeForQty(var TakeLine: Record "Warehouse Activity Line"; var PlaceLine: Record "Warehouse Activity Line"; BaseQty: Decimal; OrderNo: Code[20]): Boolean
    begin
        if OrderNo <> '' then
            TakeLine.SetRange("Source No.", OrderNo)
        else
            TakeLine.SetRange("Source No.");
        TakeLine.SetRange("Qty. Outstanding (Base)", BaseQty);
        if FindTakeWithPlace(TakeLine, PlaceLine) then
            exit(true);
        TakeLine.SetFilter("Qty. Outstanding (Base)", '>%1', BaseQty);
        exit(FindTakeWithPlace(TakeLine, PlaceLine));
    end;

    local procedure OutputOrderForLot(ItemNo: Code[20]; LotNo: Code[50]): Code[20]
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if LotNo = '' then
            exit('');
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.SetRange("Order Type", ItemLedgerEntry."Order Type"::Production);
        ItemLedgerEntry.SetRange(Positive, true);
        if ItemLedgerEntry.FindLast() then
            exit(ItemLedgerEntry."Order No.");
        exit('');
    end;

    local procedure FindTakeWithPlace(var TakeLine: Record "Warehouse Activity Line"; var PlaceLine: Record "Warehouse Activity Line"): Boolean
    begin
        // En yeni yerleştirme önce: kutu genellikle son parçalı çıktıdan kurulur.
        TakeLine.Ascending(false);
        if TakeLine.FindSet() then
            repeat
                if FindPlacePair(TakeLine, PlaceLine) then
                    exit(true);
            until TakeLine.Next() = 0;
        exit(false);
    end;

    local procedure FindPlacePair(TakeLine: Record "Warehouse Activity Line"; var PlaceLine: Record "Warehouse Activity Line"): Boolean
    begin
        PlaceLine.Reset();
        PlaceLine.SetRange("Activity Type", TakeLine."Activity Type");
        PlaceLine.SetRange("No.", TakeLine."No.");
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        PlaceLine.SetRange("Source Type", TakeLine."Source Type");
        PlaceLine.SetRange("Source No.", TakeLine."Source No.");
        PlaceLine.SetRange("Source Line No.", TakeLine."Source Line No.");
        PlaceLine.SetRange("Item No.", TakeLine."Item No.");
        PlaceLine.SetRange("Variant Code", TakeLine."Variant Code");
        PlaceLine.SetRange("Lot No.", TakeLine."Lot No.");
        PlaceLine.SetRange("LP No.", '');
        PlaceLine.SetRange("Qty. Handled", 0);
        PlaceLine.SetRange("Breakbulk No.", 0);
        PlaceLine.SetRange("Qty. Outstanding (Base)", TakeLine."Qty. Outstanding (Base)");
        PlaceLine.SetFilter("Line No.", '>%1', TakeLine."Line No.");
        if PlaceLine.FindFirst() then
            exit(true);
        PlaceLine.SetRange("Line No.");
        exit(PlaceLine.FindFirst());
    end;

    local procedure InsertLpLine(TemplateLine: Record "Warehouse Activity Line"; LpNo: Code[20]; Quantity: Decimal; var NewLine: Record "Warehouse Activity Line")
    var
        LastLine: Record "Warehouse Activity Line";
    begin
        NewLine.Init();
        NewLine.TransferFields(TemplateLine, false);
        NewLine."Activity Type" := TemplateLine."Activity Type";
        NewLine."No." := TemplateLine."No.";
        LastLine.SetRange("Activity Type", TemplateLine."Activity Type");
        LastLine.SetRange("No.", TemplateLine."No.");
        if LastLine.FindLast() then
            NewLine."Line No." := LastLine."Line No." + 10000
        else
            NewLine."Line No." := 10000;
        NewLine.Validate(Quantity, Quantity);
        NewLine."LP No." := LpNo;
        NewLine.Insert(true);
    end;

    local procedure QtyPerOf(ActivityLine: Record "Warehouse Activity Line"): Decimal
    begin
        if ActivityLine."Qty. per Unit of Measure" > 0 then
            exit(ActivityLine."Qty. per Unit of Measure");
        exit(1);
    end;

    local procedure LpLineBaseQty(LPLine: Record "DOPSWHS LP Line"): Decimal
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        if not Item.Get(LPLine."Item No.") then
            exit(0);
        if (LPLine."Unit of Measure" = '') or (LPLine."Unit of Measure" = Item."Base Unit of Measure") then
            exit(LPLine.Quantity);
        if ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") and (ItemUoM."Qty. per Unit of Measure" > 0) then
            exit(LPLine.Quantity * ItemUoM."Qty. per Unit of Measure");
        exit(0);
    end;

    // ---------------------------------------------------------------
    // 2) Palete koy
    // ---------------------------------------------------------------

    /// <summary>
    /// Üretim emri satırının çıktı gözündeki, henüz palete bağlanmamış kutu
    /// LP'lerini bir palet LP'sine bağlar. PalletLpNo boşsa TemplateCode ile yeni
    /// palet kurulur; doluysa o palete eklenir. Sonuç JSON döner.
    /// </summary>
    procedure PalletizeOutput(ProdOrderLine: Record "Prod. Order Line"; TemplateCode: Code[20]; PalletLpNo: Code[20]): Text
    begin
        exit(PalletizeOutputBoxes(ProdOrderLine, TemplateCode, PalletLpNo, ''));
    end;

    /// <summary>
    /// Emrin palete konabilecek kutu LP'leri (JSON dizi): lpNo, binCode, quantity,
    /// unit, lotNo. Operatör terminalde hangilerini palete koyacağını buradan seçer.
    /// </summary>
    procedure ListOutputBoxes(ProdOrderLine: Record "Prod. Order Line"): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Lots: List of [Code[50]];
        Bins: List of [Code[20]];
        Boxes: List of [Code[20]];
        NoSelection: List of [Code[20]];
        BoxNo: Code[20];
        Box: JsonObject;
        Result: JsonArray;
        Qty: Decimal;
        Unit: Code[10];
        LotText: Text;
    begin
        ProdOrderLine.TestField(Status, ProdOrderLine.Status::Released);
        CollectOutputLotsAndBins(ProdOrderLine, Lots, Bins);
        CollectCandidates(ProdOrderLine, Lots, Bins, '', NoSelection, Boxes);
        foreach BoxNo in Boxes do begin
            LP.Get(BoxNo);
            Qty := 0;
            Unit := '';
            LotText := '';
            LPLine.SetRange("LP No.", BoxNo);
            LPLine.SetFilter(Quantity, '>0');
            if LPLine.FindSet() then
                repeat
                    Qty += LPLine.Quantity;
                    Unit := LPLine."Unit of Measure";
                    if (LPLine."Lot No." <> '') and (StrPos(LotText, LPLine."Lot No.") = 0) then begin
                        if LotText <> '' then
                            LotText += ', ';
                        LotText += LPLine."Lot No.";
                    end;
                until LPLine.Next() = 0;
            Clear(Box);
            Box.Add('lpNo', BoxNo);
            Box.Add('binCode', LP."Bin Code");
            Box.Add('quantity', Qty);
            Box.Add('unit', Unit);
            Box.Add('lotNo', LotText);
            Result.Add(Box);
        end;
        exit(Format(Result));
    end;

    /// <summary>
    /// BoxLpNos boşsa emrin bütün uygun kutuları, doluysa yalnız virgülle ayrılmış
    /// bu LP'ler palete konur. Seçilen her LP emrin uygun kutularından biri olmalı.
    /// </summary>
    procedure PalletizeOutputBoxes(ProdOrderLine: Record "Prod. Order Line"; TemplateCode: Code[20]; PalletLpNo: Code[20]; BoxLpNos: Text): Text
    var
        Pallet: Record "DOPSWHS LP Header";
        Child: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        NestMgr: Codeunit "DOPSWHS LP Nest Manager";
        Lots: List of [Code[50]];
        Bins: List of [Code[20]];
        Boxes: List of [Code[20]];
        Selected: List of [Code[20]];
        BoxNo: Code[20];
        BinCode: Code[20];
        PutAwayNo: Code[20];
        Result: JsonObject;
        BoxArray: JsonArray;
    begin
        ProdOrderLine.TestField(Status, ProdOrderLine.Status::Released);
        CollectOutputLotsAndBins(ProdOrderLine, Lots, Bins);
        ParseSelection(BoxLpNos, Selected);
        CollectBoxes(ProdOrderLine, Lots, Bins, PalletLpNo, Selected, Boxes, BinCode);
        if Boxes.Count() = 0 then
            Error(
                '%1 üretim emri için palete konacak kutu LP bulunamadı. Kutular çıktı gözünde (%2) olmalı ve başka bir palete bağlı olmamalı.',
                ProdOrderLine."Prod. Order No.", JoinCodes(Bins));

        Pallet.LockTable();
        if PalletLpNo <> '' then begin
            if not Pallet.Get(PalletLpNo) then
                Error('%1 palet LP''si bulunamadı.', PalletLpNo);
            if Pallet."Location Code" <> ProdOrderLine."Location Code" then
                Error('%1 paleti %2 lokasyonunda; kutular %3 lokasyonunda.', Pallet."No.", Pallet."Location Code", ProdOrderLine."Location Code");
            if Pallet."Bin Code" <> BinCode then
                Error('%1 paleti %2 rafında; kutular %3 rafında. Paleti kutuların yanına getirin ya da yeni palet kurun.', Pallet."No.", Pallet."Bin Code", BinCode);
            if Pallet."Parent LP No." <> '' then
                Error('%1 LP''si başka bir palete (%2) bağlı; palet olarak kullanılamaz.', Pallet."No.", Pallet."Parent LP No.");
            if not (Pallet.Status in [Pallet.Status::Open, Pallet.Status::Built]) then
                Error('%1 paleti %2 durumunda; kutu eklenemez.', Pallet."No.", Format(Pallet.Status));
        end else begin
            if TemplateCode = '' then
                Error('Palet için LP şablonu seçin.');
            LPMgt.Build(TemplateCode, ProdOrderLine."Location Code", BinCode, Pallet);
        end;
        if Pallet.Status = Pallet.Status::Open then
            LPMgt.Stop(Pallet, false);

        foreach BoxNo in Boxes do begin
            LinkLpToOutputPutAway(BoxNo, true);
            Child.Get(BoxNo);
            // Nest yalnız "Built" LP'yi kabul eder; yerleştirme ataması korunur.
            PutAwayNo := '';
            if (Child.Status = Child.Status::Assigned) and
               (Child."Assigned Document Type" = Child."Assigned Document Type"::WhsePutaway)
            then begin
                PutAwayNo := Child."Assigned Document No.";
                LPMgt.Release(Child);
            end;
            if Child.Status = Child.Status::Open then
                LPMgt.Stop(Child, false);
            NestMgr.Nest(Child, Pallet);
            if PutAwayNo <> '' then begin
                Child.Get(BoxNo);
                LPMgt.Assign(Child, Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, PutAwayNo);
            end;
            BoxArray.Add(BoxNo);
        end;

        Result.Add('palletLpNo', Pallet."No.");
        Result.Add('binCode', BinCode);
        Result.Add('boxCount', Boxes.Count());
        Result.Add('totalBoxCount', CountChildren(Pallet."No."));
        Result.Add('boxes', BoxArray);
        exit(Format(Result));
    end;

    local procedure CollectOutputLotsAndBins(ProdOrderLine: Record "Prod. Order Line"; var Lots: List of [Code[50]]; var Bins: List of [Code[20]])
    var
        Request: Record "DOPSWHS Prod Output Request";
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        Request.SetRange("Prod. Order No.", ProdOrderLine."Prod. Order No.");
        Request.SetRange("Prod. Order Line No.", ProdOrderLine."Line No.");
        Request.SetRange(Completed, true);
        Request.SetRange(Cancelled, false);
        if Request.FindSet() then
            repeat
                if (Request."Bin Code" <> '') and not Bins.Contains(Request."Bin Code") then
                    Bins.Add(Request."Bin Code");
            until Request.Next() = 0;

        ItemLedgerEntry.SetRange("Order Type", ItemLedgerEntry."Order Type"::Production);
        ItemLedgerEntry.SetRange("Order No.", ProdOrderLine."Prod. Order No.");
        ItemLedgerEntry.SetRange("Order Line No.", ProdOrderLine."Line No.");
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.SetRange("Item No.", ProdOrderLine."Item No.");
        ItemLedgerEntry.SetRange(Positive, true);
        // Geri alınmış ya da tamamen tüketilmiş çıktı lotunun kutusu palete alınmaz.
        ItemLedgerEntry.SetFilter("Remaining Quantity", '>0');
        ItemLedgerEntry.SetFilter("Lot No.", '<>%1', '');
        if ItemLedgerEntry.FindSet() then
            repeat
                if not Lots.Contains(ItemLedgerEntry."Lot No.") then
                    Lots.Add(ItemLedgerEntry."Lot No.");
            until ItemLedgerEntry.Next() = 0;

        if (ProdOrderLine."Bin Code" <> '') and not Bins.Contains(ProdOrderLine."Bin Code") then
            Bins.Add(ProdOrderLine."Bin Code");
    end;

    local procedure ParseSelection(BoxLpNos: Text; var Selected: List of [Code[20]])
    var
        Part: Text;
        No: Code[20];
    begin
        foreach Part in BoxLpNos.Split(',', ';', ' ') do begin
            Part := Part.Trim();
            if Part <> '' then begin
                No := CopyStr(UpperCase(Part), 1, MaxStrLen(No));
                if not Selected.Contains(No) then
                    Selected.Add(No);
            end;
        end;
    end;

    /// <summary>Emrin uygun kutuları; Selected doluysa yalnız onlar.</summary>
    local procedure CollectCandidates(ProdOrderLine: Record "Prod. Order Line"; Lots: List of [Code[50]]; Bins: List of [Code[20]]; PalletLpNo: Code[20]; Selected: List of [Code[20]]; var Boxes: List of [Code[20]])
    var
        LPLine: Record "DOPSWHS LP Line";
        LP: Record "DOPSWHS LP Header";
        LotTracked: Boolean;
    begin
        LotTracked := IsLotTracked(ProdOrderLine."Item No.");
        LPLine.SetRange("Item No.", ProdOrderLine."Item No.");
        LPLine.SetRange("Variant Code", ProdOrderLine."Variant Code");
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if not Boxes.Contains(LPLine."LP No.") and (LPLine."LP No." <> PalletLpNo) then
                    if (Selected.Count() = 0) or Selected.Contains(LPLine."LP No.") then
                        if (not LotTracked) or Lots.Contains(LPLine."Lot No.") then
                            if LP.Get(LPLine."LP No.") then
                                if IsEligibleBox(LP, ProdOrderLine, Bins) then
                                    Boxes.Add(LP."No.");
            until LPLine.Next() = 0;
    end;

    local procedure CollectBoxes(ProdOrderLine: Record "Prod. Order Line"; Lots: List of [Code[50]]; Bins: List of [Code[20]]; PalletLpNo: Code[20]; Selected: List of [Code[20]]; var Boxes: List of [Code[20]]; var BinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        BinsFound: List of [Code[20]];
        BoxNo: Code[20];
    begin
        CollectCandidates(ProdOrderLine, Lots, Bins, PalletLpNo, Selected, Boxes);
        foreach BoxNo in Selected do
            if not Boxes.Contains(BoxNo) then
                Error('%1 LP''si %2 üretim emrinin palete konabilecek kutularından biri değil (başka bir palete bağlı, başka üründen ya da çıktı gözünde değil).',
                    BoxNo, ProdOrderLine."Prod. Order No.");
        foreach BoxNo in Boxes do begin
            LP.Get(BoxNo);
            if not BinsFound.Contains(LP."Bin Code") then
                BinsFound.Add(LP."Bin Code");
        end;

        if BinsFound.Count() > 1 then
            Error(
                '%1 üretim emrinin kutuları birden fazla rafta (%2). Tek palete yalnız aynı raftaki kutular konur; kutuları önce aynı rafa toplayın.',
                ProdOrderLine."Prod. Order No.", JoinCodes(BinsFound));
        if BinsFound.Count() = 1 then
            BinCode := BinsFound.Get(1);
    end;

    local procedure IsLotTracked(ItemNo: Code[20]): Boolean
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
    begin
        if not Item.Get(ItemNo) then
            exit(false);
        if (Item."Item Tracking Code" = '') or not Tracking.Get(Item."Item Tracking Code") then
            exit(false);
        exit(Tracking."Lot Specific Tracking" or Tracking."Lot Warehouse Tracking");
    end;

    local procedure IsEligibleBox(LP: Record "DOPSWHS LP Header"; ProdOrderLine: Record "Prod. Order Line"; Bins: List of [Code[20]]): Boolean
    var
        OtherLine: Record "DOPSWHS LP Line";
        Child: Record "DOPSWHS LP Header";
    begin
        if LP."Location Code" <> ProdOrderLine."Location Code" then
            exit(false);
        if not Bins.Contains(LP."Bin Code") then
            exit(false);
        if LP."Parent LP No." <> '' then
            exit(false);
        case LP.Status of
            LP.Status::Open, LP.Status::Built:
                ;
            LP.Status::Assigned:
                if LP."Assigned Document Type" <> LP."Assigned Document Type"::WhsePutaway then
                    exit(false);
            else
                exit(false);
        end;
        // Karışık LP (başka ürün de içeren) kutu sayılmaz.
        OtherLine.SetRange("LP No.", LP."No.");
        OtherLine.SetFilter(Quantity, '>0');
        OtherLine.SetFilter("Item No.", '<>%1', ProdOrderLine."Item No.");
        if not OtherLine.IsEmpty() then
            exit(false);
        // Kendisi palet olan LP kutu sayılmaz.
        Child.SetRange("Parent LP No.", LP."No.");
        exit(Child.IsEmpty());
    end;

    // ---------------------------------------------------------------
    // 3) Paleti taşı / yerleştir
    // ---------------------------------------------------------------

    procedure HasChildren(LpNo: Code[20]): Boolean
    var
        Child: Record "DOPSWHS LP Header";
    begin
        if LpNo = '' then
            exit(false);
        Child.SetRange("Parent LP No.", LpNo);
        exit(not Child.IsEmpty());
    end;

    /// <summary>
    /// Paleti hedef rafa taşır. Her kutunun açık yerleştirme satırları hedef rafa
    /// kaydedilir (ambar girişleri kutunun LP numarasını taşır); yerleştirmesi
    /// olmayan kutular serbest taşımayla gider; en son palet başlığı taşınır.
    /// </summary>
    /// <summary>API girişi: LP Management.MoveToBin ile aynı ön denetimler, sonra MovePallet.</summary>
    procedure MovePalletChecked(var Pallet: Record "DOPSWHS LP Header"; TargetBinCode: Code[20]; OperatorUserId: Code[50]): Text
    begin
        Pallet.LockTable();
        Pallet.Get(Pallet."No.");
        if Pallet."Pending Receipt No." <> '' then
            Error('%1 paleti %2 mal kabulünü bekliyor; önce mal kabulü tamamlayın.', Pallet."No.", Pallet."Pending Receipt No.");
        if Pallet.Status = Pallet.Status::Assigned then
            Error('%1 paleti %2 %3 belgesine atanmış. Bu paleti o belgenin ekranından taşıyın.', Pallet."No.", Format(Pallet."Assigned Document Type"), Pallet."Assigned Document No.");
        if not (Pallet.Status in [Pallet.Status::Open, Pallet.Status::Built]) then
            Error('%1 paleti %2 durumundayken taşınamaz.', Pallet."No.", Format(Pallet.Status));
        if Pallet."Bin Code" = TargetBinCode then
            Error('%1 paleti zaten %2 rafındadır.', Pallet."No.", TargetBinCode);
        exit(MovePallet(Pallet, TargetBinCode, OperatorUserId));
    end;

    // Whse.-Activity-Register kendi içinde Commit çağırır. Palet tek işlem olarak
    // kaydedilir: bir kutuda hata olursa hiçbir yerleştirme yarım kalmaz.
    [CommitBehavior(CommitBehavior::Ignore)]
    procedure MovePallet(var Pallet: Record "DOPSWHS LP Header"; TargetBinCode: Code[20]; OperatorUserId: Code[50]): Text
    var
        Child: Record "DOPSWHS LP Header";
        OwnLine: Record "DOPSWHS LP Line";
        TargetBin: Record Bin;
        PlaceLine: Record "Warehouse Activity Line";
        WhseActivityHeader: Record "Warehouse Activity Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Reconcile: Codeunit "DOPSWHS LP Assign Reconcile";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Children: List of [Code[20]];
        PutAwayNos: List of [Code[20]];
        ChildNo: Code[20];
        PutAwayNo: Code[20];
        SourceBin: Code[20];
        MovedLoose: Integer;
        Result: JsonObject;
    begin
        if OperatorUserId = '' then
            Error('%1 paletini taşımak için operatör kullanıcı kimliği zorunludur.', Pallet."No.");
        if TargetBinCode = '' then
            Error('%1 paletini taşımak için hedef raf zorunludur.', Pallet."No.");
        if not TargetBin.Get(Pallet."Location Code", TargetBinCode) then
            Error('%1 hedef rafı %2 lokasyonunda bulunamadı.', TargetBinCode, Pallet."Location Code");
        OwnLine.SetRange("LP No.", Pallet."No.");
        OwnLine.SetFilter(Quantity, '>0');
        if not OwnLine.IsEmpty() then
            Error('%1 paletinin üzerinde kutuya konmamış ürün var. Ürünü bir kutu LP''sine alın ya da kutuları paletten ayırın.', Pallet."No.");

        Child.SetRange("Parent LP No.", Pallet."No.");
        if Child.FindSet() then
            repeat
                Children.Add(Child."No.");
            until Child.Next() = 0;

        // Kutuların yerleştirmelerini topla (atama belgesi silinmişse önce düzelt).
        foreach ChildNo in Children do begin
            Child.Get(ChildNo);
            if Child.Status = Child.Status::Assigned then
                if Child."Assigned Document Type" = Child."Assigned Document Type"::WhsePutaway then begin
                    if not WhseActivityHeader.Get(WhseActivityHeader.Type::"Put-away", Child."Assigned Document No.") then
                        Reconcile.ReconcileStaleAssignment(Child);
                end else
                    Error('%1 kutusu %2 %3 belgesine atanmış; palet taşınamaz.', Child."No.", Format(Child."Assigned Document Type"), Child."Assigned Document No.");
            LinkLpToOutputPutAway(ChildNo, false);
            PlaceLine.Reset();
            PlaceLine.SetRange("Activity Type", PlaceLine."Activity Type"::"Put-away");
            PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
            PlaceLine.SetRange("LP No.", ChildNo);
            PlaceLine.SetFilter("Qty. Outstanding", '>0');
            if PlaceLine.FindSet() then
                repeat
                    if not PutAwayNos.Contains(PlaceLine."No.") then
                        PutAwayNos.Add(PlaceLine."No.");
                until PlaceLine.Next() = 0;
        end;

        foreach PutAwayNo in PutAwayNos do begin
            PreparePutAwayForPallet(PutAwayNo, Children, TargetBin, OperatorUserId);
            WhseActivityHeader.Get(WhseActivityHeader.Type::"Put-away", PutAwayNo);
            MovementMgmt.RegisterDirected(WhseActivityHeader, OperatorUserId);
        end;

        // Yerleştirmesi olmayan (ya da kaydedildiği halde başka rafta kalan) kutular.
        foreach ChildNo in Children do begin
            Child.Get(ChildNo);
            if Child."Bin Code" <> TargetBinCode then begin
                if Child.Status = Child.Status::Assigned then
                    Error('%1 kutusu hâlâ %2 belgesine atanmış; önce o belgeyi tamamlayın.', Child."No.", Child."Assigned Document No.");
                LPMgt.MoveToBin(Child, TargetBinCode, OperatorUserId);
                MovedLoose += 1;
            end;
        end;

        Pallet.Get(Pallet."No.");
        SourceBin := Pallet."Bin Code";
        if SourceBin <> TargetBinCode then begin
            Pallet.Validate("Bin Code", TargetBinCode);
            Pallet.Modify(true);
            LPMgt.WriteToLedger(Pallet, Enum::"DOPSWHS LP Action"::Moved, SourceBin, TargetBinCode, 0, '', '', 'PALLET-MOVE');
        end;

        Result.Add('palletLpNo', Pallet."No.");
        Result.Add('targetBinCode', TargetBinCode);
        Result.Add('boxCount', Children.Count());
        Result.Add('putAwayCount', PutAwayNos.Count());
        Result.Add('movedWithoutPutAway', MovedLoose);
        exit(Format(Result));
    end;

    local procedure PreparePutAwayForPallet(PutAwayNo: Code[20]; Children: List of [Code[20]]; TargetBin: Record Bin; OperatorUserId: Code[50])
    var
        Header: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        Header.LockTable();
        Header.Get(Header.Type::"Put-away", PutAwayNo);
        if (Header."Assigned User ID" <> '') and (Header."Assigned User ID" <> OperatorUserId) then
            Error('Yerleştirme belgesi %1, %2 kullanıcısına atanmış; palet taşınamaz.', PutAwayNo, Header."Assigned User ID");
        if Header."Assigned User ID" = '' then begin
            Header."Assigned User ID" := CopyStr(OperatorUserId, 1, MaxStrLen(Header."Assigned User ID"));
            Header.Modify(true);
        end;

        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", PutAwayNo);
        if ActivityLine.FindSet() then
            repeat
                if (ActivityLine."LP No." <> '') and Children.Contains(ActivityLine."LP No.") and (ActivityLine."Qty. Outstanding" > 0) then begin
                    if ActivityLine."Action Type" = ActivityLine."Action Type"::Place then begin
                        ActivityLine.Validate("Zone Code", TargetBin."Zone Code");
                        ActivityLine.Validate("Bin Code", TargetBin.Code);
                    end;
                    ActivityLine.Validate("Qty. to Handle", ActivityLine."Qty. Outstanding");
                    ActivityLine.Modify(true);
                end else
                    // Bu belgede palete ait olmayan satırlar bu kayıtta işlenmez.
                    if ActivityLine."Qty. to Handle" <> 0 then begin
                        ActivityLine.Validate("Qty. to Handle", 0);
                        ActivityLine.Modify(true);
                    end;
            until ActivityLine.Next() = 0;
    end;

    local procedure CountChildren(LpNo: Code[20]): Integer
    var
        Child: Record "DOPSWHS LP Header";
    begin
        Child.SetRange("Parent LP No.", LpNo);
        exit(Child.Count());
    end;

    local procedure JoinCodes(Codes: List of [Code[20]]): Text
    var
        Value: Code[20];
        Joined: Text;
    begin
        foreach Value in Codes do begin
            if Joined <> '' then
                Joined += ', ';
            Joined += Value;
        end;
        exit(Joined);
    end;

    // ---------------------------------------------------------------
    // 4) BC ekranından kaydedilen yerleştirme
    // ---------------------------------------------------------------

    /// <summary>
    /// Yerleştirme BC ekranından kaydedildiğinde terminal yolu (FinalizePutAwayLp)
    /// çalışmaz. Kayıtlı Koy satırında LP numarası olan, atanmamış (açık/hazır)
    /// LP'ler hâlâ Al rafındaysa hedef rafa taşınır. Atanmış LP'leri "LP Assign
    /// Reconcile" taşır.
    /// </summary>
    [EventSubscriber(ObjectType::Table, Database::"Warehouse Activity Header", 'OnAfterDeleteEvent', '', false, false)]
    local procedure OnAfterDeletePutAway(var Rec: Record "Warehouse Activity Header"; RunTrigger: Boolean)
    var
        RegHeader: Record "Registered Whse. Activity Hdr.";
        RegLine: Record "Registered Whse. Activity Line";
        TakeLine: Record "Registered Whse. Activity Line";
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Done: List of [Code[20]];
        SourceBin: Code[20];
    begin
        if Rec.IsTemporary() or (Rec.Type <> Rec.Type::"Put-away") then
            exit;
        RegHeader.SetRange(Type, RegHeader.Type::"Put-away");
        RegHeader.SetRange("Whse. Activity No.", Rec."No.");
        if not RegHeader.FindSet() then
            exit;
        repeat
            RegLine.SetRange("Activity Type", RegHeader.Type);
            RegLine.SetRange("No.", RegHeader."No.");
            RegLine.SetRange("Action Type", RegLine."Action Type"::Place);
            RegLine.SetFilter("LP No.", '<>%1', '');
            if RegLine.FindSet() then
                repeat
                    if not Done.Contains(RegLine."LP No.") then begin
                        Done.Add(RegLine."LP No.");
                        if LP.Get(RegLine."LP No.") then
                            if (LP.Status in [LP.Status::Open, LP.Status::Built]) and
                               (LP."Location Code" = RegLine."Location Code") and
                               (LP."Bin Code" <> RegLine."Bin Code")
                            then begin
                                TakeLine.SetRange("Activity Type", RegHeader.Type);
                                TakeLine.SetRange("No.", RegHeader."No.");
                                TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
                                TakeLine.SetRange("LP No.", LP."No.");
                                TakeLine.SetRange("Bin Code", LP."Bin Code");
                                if not TakeLine.IsEmpty() then begin
                                    SourceBin := LP."Bin Code";
                                    LP.Validate("Bin Code", RegLine."Bin Code");
                                    LP.Modify(true);
                                    LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::Moved, SourceBin, RegLine."Bin Code", 0, '', '', Rec."No.");
                                end;
                            end;
                    end;
                until RegLine.Next() = 0;
        until RegHeader.Next() = 0;
    end;
}
