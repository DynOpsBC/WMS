codeunit 72234 "DOPSWHS Partial Output Mgmt"
{
    // Request and ledger posting commit together. Printing is a separate action.
    Permissions = tabledata "DOPSWHS Prod Output Request" = rim,
                  tabledata "Item Journal Template" = ri,
                  tabledata "Item Journal Batch" = ri,
                  tabledata "Item Journal Line" = rimd,
                  tabledata "Lot No. Information" = ri,
                  tabledata "Reservation Entry" = rimd;

    [CommitBehavior(CommitBehavior::Error)]
    procedure PrepareOutput(var Line: Record "Prod. Order Line"; Quantity: Decimal; PostingDate: Date; BinCode: Code[20]; ExpirationDate: Date; RequestId: Guid): Text
    begin
        exit(PrepareOutputWithLot(Line, Quantity, PostingDate, BinCode, ExpirationDate, RequestId, ''));
    end;

    /// <summary>
    /// DKC (23 Kas 2026): parçalı üretimde aynı lot sürer. LotNo doluysa bu lot
    /// kullanılır; boşsa ürünün lot serisinden yeni numara alınır ("Lot Ata").
    /// </summary>
    [CommitBehavior(CommitBehavior::Error)]
    procedure PrepareOutputWithLot(var Line: Record "Prod. Order Line"; Quantity: Decimal; PostingDate: Date; BinCode: Code[20]; ExpirationDate: Date; RequestId: Guid; LotNo: Code[50]): Text
    var
        Request: Record "DOPSWHS Prod Output Request";
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        LotInfo: Record "Lot No. Information";
        NoSeries: Codeunit "No. Series";
        License: Codeunit "DOPSWHS License Mgmt";
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);
        if IsNullGuid(RequestId) then
            Error('Bildirim kimliği zorunludur.');
        Request.LockTable();
        if Request.Get(RequestId) then begin
            CheckOwner(Request);
            Request.TestField("Prod. Order No.", Line."Prod. Order No.");
            Request.TestField("Prod. Order Line No.", Line."Line No.");
            Request.TestField(Quantity, Quantity);
            Request.TestField("Posting Date", PostingDate);
            Request.TestField("Requested Bin Code", BinCode);
            Request.TestField("Requested Expiration Date", ExpirationDate);
            exit(ResultJson(Request));
        end;
        Line.LockTable();
        GetReleasedLine(Line, Line."Prod. Order No.", Line."Line No.");
        ValidateQuantity(Quantity, Line."Remaining Quantity");
        if PostingDate = 0D then
            Error('Kayıt tarihi zorunludur.');
        Item.Get(Line."Item No.");
        Item.TestField(Blocked, false);
        Item.TestField("Base Unit of Measure");
        Request.Init();
        Request."Request ID" := RequestId;
        Request."Prod. Order No." := Line."Prod. Order No.";
        Request."Prod. Order Line No." := Line."Line No.";
        Request."Item No." := Line."Item No.";
        Request."Variant Code" := Line."Variant Code";
        Request."Unit of Measure Code" := Line."Unit of Measure Code";
        Request."Qty. per Unit of Measure" := Line."Qty. per Unit of Measure";
        Request."Location Code" := Line."Location Code";
        Request."Requested Bin Code" := BinCode;
        Request."Bin Code" := BinCode;
        if BinCode = '' then
            Request."Bin Code" := Line."Bin Code";
        Request.Quantity := Quantity;
        Request."Posting Date" := PostingDate;
        Request."Requested Expiration Date" := ExpirationDate;
        Request."Expiration Date" := ExpirationDate;
        Request."Base Unit of Measure" := Item."Base Unit of Measure";
        Request."Document No." := CopyStr(DelChr(Format(RequestId), '=', '{}-'), 1, 20);
        Request."Created By" := UserSecurityId();
        Request."Created At" := CurrentDateTime();
        if (Item."Item Tracking Code" <> '') and Tracking.Get(Item."Item Tracking Code") then begin
            if Tracking."SN Specific Tracking" or Tracking."SN Pos. Adjmt. Inb. Tracking" then
                Error('Seri numarası takipli ürünün çıktısını BC ürün izleme ekranından kaydedin.');
            if Tracking."Lot Specific Tracking" or Tracking."Lot Pos. Adjmt. Inb. Tracking" then begin
                if LotNo <> '' then
                    Request."Lot No." := LotNo
                else begin
                    Item.TestField("Lot Nos.");
                    Request."Lot No." := NoSeries.GetNextNo(Item."Lot Nos.", PostingDate);
                end;
                if Request."Lot No." = '' then
                    Error('BC lot numara serisinden numara alınamadı.');
                if Tracking."Lot Info. Inbound Must Exist" then
                    if not LotInfo.Get(Item."No.", Line."Variant Code", Request."Lot No.") then begin
                        LotInfo.Init();
                        LotInfo."Item No." := Item."No.";
                        LotInfo."Variant Code" := Line."Variant Code";
                        LotInfo."Lot No." := Request."Lot No.";
                        LotInfo.Description := Item.Description;
                        LotInfo.Insert(true);
                    end;
                if Tracking."Man. Expir. Date Entry Reqd." and (ExpirationDate = 0D) then
                    Error('Bu ürün için son kullanma tarihini girin.');
                if Tracking."Use Expiration Dates" and (Request."Expiration Date" = 0D) and (Format(Item."Expiration Calculation") <> '') then
                    Request."Expiration Date" := CalcDate(Item."Expiration Calculation", PostingDate);
            end;
        end;
        Request.Insert(true);
        exit(ResultJson(Request));
    end;

    procedure ValidateQuantity(Quantity: Decimal; Remaining: Decimal)
    begin
        if Quantity <= 0 then
            Error('Bildirilen miktar sıfırdan büyük olmalıdır.');
        if Quantity > Remaining then
            Error('Bildirilen %1 miktarı kalan %2 miktarını aşıyor. Emir bilgilerini yenileyin.', Quantity, Remaining);
    end;

    [CommitBehavior(CommitBehavior::Error)]
    procedure PostOutput(RequestId: Guid): Text
    var
        Request: Record "DOPSWHS Prod Output Request";
        Line: Record "Prod. Order Line";
        Journal: Record "Item Journal Line";
        Entry: Record "Item Ledger Entry";
        PostBatch: Codeunit "Item Jnl.-Post Batch";
        License: Codeunit "DOPSWHS License Mgmt";
        ExpectedBase: Decimal;
        TotalBase: Decimal;
        RemainingBeforeBase: Decimal;
    begin
        License.GuardFeature(Enum::"DOPSWHS License Feature"::Production);
        Request.LockTable();
        Request.Get(RequestId);
        CheckOwner(Request);
        if Request.Completed then
            exit(ResultJson(Request));
        Request.TestField(Cancelled, false);
        Line.LockTable();
        GetReleasedLine(Line, Request."Prod. Order No.", Request."Prod. Order Line No.");
        ValidateQuantity(Request.Quantity, Line."Remaining Quantity");
        // A stale preparation must never silently post another product/unit/location.
        Line.TestField("Item No.", Request."Item No.");
        Line.TestField("Variant Code", Request."Variant Code");
        Line.TestField("Unit of Measure Code", Request."Unit of Measure Code");
        Line.TestField("Qty. per Unit of Measure", Request."Qty. per Unit of Measure");
        Line.TestField("Location Code", Request."Location Code");
        Entry.SetRange("Document No.", Request."Document No.");
        if not Entry.IsEmpty() then
            Error('Bu bildirim belge numarası kullanılmış; işlem yinelenmedi.');
        RemainingBeforeBase := Line."Remaining Qty. (Base)";
        CreateJournal(Line, Request, Journal);
        ExpectedBase := Journal."Output Quantity (Base)";
        AddTracking(Journal, Request);
        PostBatch.SetSuppressCommit(true);
        PostBatch.Run(Journal);
        Entry.SetRange("Order No.", Request."Prod. Order No.");
        Entry.SetRange("Order Line No.", Request."Prod. Order Line No.");
        Entry.SetRange("Entry Type", Entry."Entry Type"::Output);
        Entry.SetRange("Item No.", Request."Item No.");
        Entry.SetRange("Lot No.", Request."Lot No.");
        if Entry.FindSet() then
            repeat
                TotalBase += Entry.Quantity;
                if Request."Item Ledger Entry No." = 0 then
                    Request."Item Ledger Entry No." := Entry."Entry No.";
            until Entry.Next() = 0;
        if (Request."Item Ledger Entry No." = 0) or (TotalBase <> ExpectedBase) then
            Error('Çıktı madde hareketi doğrulanamadı. Bildirim geri alındı.');
        // DKC (26 Kas 2026): bileşenler terminalden tüketilmez; toplanıp üretim
        // gözüne getirilen bileşen, bildirilen çıktı oranında aynı işlemde tüketilir.
        // Yetmezse çıktı da kaydedilmez (tek işlem).
        AutoConsumeComponents(Line, Request, ExpectedBase, RemainingBeforeBase);
        Request."Quantity (Base)" := TotalBase;
        Request.Completed := true;
        Request.Modify(true);
        exit(ResultJson(Request));
    end;

    [CommitBehavior(CommitBehavior::Error)]
    procedure CancelOutput(RequestId: Guid): Text
    var
        Request: Record "DOPSWHS Prod Output Request";
    begin
        Request.LockTable();
        Request.Get(RequestId);
        CheckOwner(Request);
        // A response lost after posting cannot be mistaken for a cancelled output.
        if not Request.Completed then begin
            Request.Cancelled := true;
            Request.Modify(true);
        end;
        exit(ResultJson(Request));
    end;

    local procedure CheckOwner(Request: Record "DOPSWHS Prod Output Request")
    begin
        Request.TestField("Created By", UserSecurityId());
    end;

    local procedure GetReleasedLine(var Line: Record "Prod. Order Line"; OrderNo: Code[20]; LineNo: Integer)
    var
        Ref: RecordRef;
        Filters: Codeunit "DOPSWHS App Role Filter Mgmt";
    begin
        Line.Reset();
        Line.LockTable();
        Line.FilterGroup(2);
        Ref.GetTable(Line);
        Filters.ApplyForCurrentUser(Ref, Enum::"DOPSWHS App Filter Entity"::ProductionOrderLine);
        Ref.SetTable(Line);
        Line.FilterGroup(0);
        Line.SetRange(Status, Line.Status::Released);
        Line.SetRange("Prod. Order No.", OrderNo);
        Line.SetRange("Line No.", LineNo);
        if not Line.FindFirst() then
            Error('Serbest bırakılmış üretim emri satırı bulunamadı veya erişilemiyor.');
    end;

    local procedure CreateJournal(Line: Record "Prod. Order Line"; Request: Record "DOPSWHS Prod Output Request"; var Journal: Record "Item Journal Line")
    var
        Template: Record "Item Journal Template";
        Batch: Record "Item Journal Batch";
        Routing: Record "Prod. Order Routing Line";
        BatchName: Code[10];
    begin
        Template.LockTable();
        if not Template.Get('DOPSOUT') then begin
            Template.Init();
            Template.Name := 'DOPSOUT';
            Template.Type := Template.Type::Output;
            Template.Description := 'WMS partial production output';
            Template.Insert(true);
        end;
        Template.TestField(Type, Template.Type::Output);
        Template.TestField(Recurring, false);
        BatchName := CopyStr(Request."Document No.", 1, 10);
        if not Batch.Get(Template.Name, BatchName) then begin
            Batch.Init();
            Batch."Journal Template Name" := Template.Name;
            Batch.Name := BatchName;
            Batch.Insert(true);
        end;
        // Never post another user's journal or silently delete an existing line.
        Journal.SetRange("Journal Template Name", Template.Name);
        Journal.SetRange("Journal Batch Name", BatchName);
        if not Journal.IsEmpty() then
            Error('Üretim bildirim günlüğünde bekleyen satır var; işlem yapılmadı.');
        Journal.Init();
        Journal."Journal Template Name" := Template.Name;
        Journal."Journal Batch Name" := BatchName;
        Journal."Line No." := 10000;
        Journal.Validate("Posting Date", Request."Posting Date");
        Journal.Validate("Entry Type", Journal."Entry Type"::Output);
        Journal.Validate("Order Type", Journal."Order Type"::Production);
        Journal.Validate("Order No.", Line."Prod. Order No.");
        Journal.Validate("Order Line No.", Line."Line No.");
        Journal.Validate("Item No.", Line."Item No.");
        Journal.Validate("Variant Code", Line."Variant Code");
        Journal.Validate("Unit of Measure Code", Line."Unit of Measure Code");
        if Line."Routing No." <> '' then begin
            Routing.SetRange(Status, Line.Status);
            Routing.SetRange("Prod. Order No.", Line."Prod. Order No.");
            Routing.SetRange("Routing Reference No.", Line."Routing Reference No.");
            Routing.SetRange("Routing No.", Line."Routing No.");
            Routing.SetRange("Next Operation No.", '');
            if Routing.Count() <> 1 then
                Error('Son üretim operasyonu tekil olarak belirlenemedi. BC rota satırlarını kontrol edin.');
            Routing.FindFirst();
            Journal.Validate("Routing No.", Routing."Routing No.");
            Journal.Validate("Operation No.", Routing."Operation No.");
        end;
        Journal.Validate("Location Code", Request."Location Code");
        Journal.Validate("Bin Code", Request."Bin Code");
        Journal.TestField("Order Line No.", Line."Line No.");
        Journal.TestField("Item No.", Request."Item No.");
        Journal.Validate("Output Quantity", Request.Quantity);
        // Order validation may replace Document No. with the production order
        // according to Manufacturing Setup. Keep this request's unique receipt
        // reference after all standard validations so replay verification is stable.
        Journal."Document No." := Request."Document No.";
        Journal.Finished := false;
        Journal.Insert(true);
    end;

    /// <summary>
    /// İleri tüketilmeyen her bileşenden, çıktının emre oranı kadar
    /// tüketim: beklenen miktar × çıktı (temel) ÷ emir miktarı (temel). Emrin son çıktısında
    /// bileşenin kalanı tüketilir (yuvarlama artığı kalmaz). Toplama zorunlu lokasyonda
    /// toplanmamış bileşen tüketilmez; lot takipli bileşende lot, lokasyondaki açık giriş
    /// kayıtlarından ilk giren ilk çıkar sırasıyla dağıtılır.
    /// </summary>
    local procedure AutoConsumeComponents(Line: Record "Prod. Order Line"; Request: Record "DOPSWHS Prod Output Request"; OutputBase: Decimal; RemainingBeforeBase: Decimal)
    var
        Comp: Record "Prod. Order Component";
        Journal: Record "Item Journal Line";
        PostBatch: Codeunit "Item Jnl.-Post Batch";
        TemplateName: Code[10];
        BatchName: Code[10];
        NeedQty: Decimal;
        NextLineNo: Integer;
    begin
        if (OutputBase <= 0) or (Line."Quantity (Base)" <= 0) then
            exit;
        Comp.SetRange(Status, Line.Status);
        Comp.SetRange("Prod. Order No.", Line."Prod. Order No.");
        Comp.SetRange("Prod. Order Line No.", Line."Line No.");
        Comp.SetFilter("Item No.", '<>%1', '');
        // İleri (Forward) tüketilenler emir serbest bırakılınca zaten tüketilmiştir. Geri
        // (Backward) tüketilenler de burada çıktı oranında tüketilir; emir bitirilirken BC
        // yalnız eksik kalan kısmı tüketir (gereken − gerçekleşen).
        Comp.SetFilter("Flushing Method", '<>%1&<>%2', Comp."Flushing Method"::Forward, Comp."Flushing Method"::"Pick + Forward");
        if not Comp.FindSet() then
            exit;
        EnsureConsumptionBatch(Request, TemplateName, BatchName);
        NextLineNo := 10000;
        repeat
            if OutputBase >= RemainingBeforeBase then
                NeedQty := Comp."Remaining Quantity"
            else
                NeedQty := Round(Comp."Expected Quantity" * OutputBase / Line."Quantity (Base)", 0.00001);
            if NeedQty > Comp."Remaining Quantity" then
                NeedQty := Comp."Remaining Quantity";
            if NeedQty > 0 then begin
                CheckPicked(Comp, NeedQty);
                AddConsumptionLines(Comp, Request, NeedQty, TemplateName, BatchName, NextLineNo);
            end;
        until Comp.Next() = 0;
        Journal.SetRange("Journal Template Name", TemplateName);
        Journal.SetRange("Journal Batch Name", BatchName);
        if not Journal.FindFirst() then
            exit;
        PostBatch.SetSuppressCommit(true);
        PostBatch.Run(Journal);
    end;

    local procedure CheckPicked(var Comp: Record "Prod. Order Component"; NeedQty: Decimal)
    var
        Location: Record Location;
        Available: Decimal;
    begin
        if not Location.Get(Comp."Location Code") then
            exit;
        if not (Location."Directed Put-away and Pick" or
                (Location."Prod. Consump. Whse. Handling" = Location."Prod. Consump. Whse. Handling"::"Warehouse Pick (mandatory)"))
        then
            exit;
        Comp.CalcFields("Act. Consumption (Qty)");
        Available := Comp."Qty. Picked" - Comp."Act. Consumption (Qty)";
        if NeedQty > Available then
            Error(NotPickedErr, Comp."Item No.", NeedQty, Comp."Unit of Measure Code", Available);
    end;

    local procedure AddConsumptionLines(Comp: Record "Prod. Order Component"; Request: Record "DOPSWHS Prod Output Request"; NeedQty: Decimal; TemplateName: Code[10]; BatchName: Code[10]; var NextLineNo: Integer)
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
        Entry: Record "Item Ledger Entry";
        NeedBase: Decimal;
        TakeBase: Decimal;
        QtyPerUoM: Decimal;
    begin
        QtyPerUoM := Comp."Qty. per Unit of Measure";
        if QtyPerUoM = 0 then
            QtyPerUoM := 1;
        Item.Get(Comp."Item No.");
        if (Item."Item Tracking Code" = '') or not Tracking.Get(Item."Item Tracking Code") or not Tracking."Lot Specific Tracking" then begin
            InsertConsumptionLine(Comp, Request, NeedQty, '', TemplateName, BatchName, NextLineNo);
            exit;
        end;
        if Tracking."SN Specific Tracking" then
            Error(SerialCompErr, Comp."Item No.");
        NeedBase := Round(NeedQty * QtyPerUoM, 0.00001);
        Entry.SetCurrentKey("Item No.", Open, "Variant Code", Positive, "Location Code", "Posting Date");
        Entry.SetRange("Item No.", Comp."Item No.");
        Entry.SetRange(Open, true);
        Entry.SetRange("Variant Code", Comp."Variant Code");
        Entry.SetRange(Positive, true);
        Entry.SetRange("Location Code", Comp."Location Code");
        Entry.SetFilter("Lot No.", '<>%1', '');
        if Entry.FindSet() then
            repeat
                TakeBase := Entry."Remaining Quantity";
                if TakeBase > NeedBase then
                    TakeBase := NeedBase;
                if TakeBase > 0 then begin
                    InsertConsumptionLine(Comp, Request, Round(TakeBase / QtyPerUoM, 0.00001), Entry."Lot No.", TemplateName, BatchName, NextLineNo);
                    NeedBase -= TakeBase;
                end;
            until (Entry.Next() = 0) or (NeedBase <= 0);
        if NeedBase > 0 then
            Error(NoLotStockErr, Comp."Item No.", Comp."Location Code", Round(NeedBase / QtyPerUoM, 0.00001), Comp."Unit of Measure Code");
    end;

    local procedure InsertConsumptionLine(Comp: Record "Prod. Order Component"; Request: Record "DOPSWHS Prod Output Request"; Qty: Decimal; LotNo: Code[50]; TemplateName: Code[10]; BatchName: Code[10]; var NextLineNo: Integer)
    var
        Journal: Record "Item Journal Line";
        TempReservEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        if Qty <= 0 then
            exit;
        Journal.Init();
        Journal."Journal Template Name" := TemplateName;
        Journal."Journal Batch Name" := BatchName;
        Journal."Line No." := NextLineNo;
        NextLineNo += 10000;
        Journal.Validate("Posting Date", Request."Posting Date");
        // Order context before Item No.: validating Item No. first clears the order link.
        Journal.Validate("Entry Type", Journal."Entry Type"::Consumption);
        Journal.Validate("Order Type", Journal."Order Type"::Production);
        Journal.Validate("Order No.", Comp."Prod. Order No.");
        Journal.Validate("Order Line No.", Comp."Prod. Order Line No.");
        Journal.Validate("Item No.", Comp."Item No.");
        Journal.Validate("Prod. Order Comp. Line No.", Comp."Line No.");
        Journal.Validate("Location Code", Comp."Location Code");
        if Comp."Bin Code" <> '' then
            Journal.Validate("Bin Code", Comp."Bin Code");
        Journal.Validate("Unit of Measure Code", Comp."Unit of Measure Code");
        Journal.Validate(Quantity, Qty);
        Journal."Document No." := Request."Document No.";
        Journal.Insert(true);
        if LotNo = '' then
            exit;
        TempReservEntry."Lot No." := LotNo;
        CreateReservEntry.CreateReservEntryFor(Database::"Item Journal Line", Journal."Entry Type".AsInteger(),
            Journal."Journal Template Name", Journal."Journal Batch Name", 0, Journal."Line No.",
            Journal."Qty. per Unit of Measure", Journal.Quantity, Journal."Quantity (Base)", TempReservEntry);
        CreateReservEntry.CreateEntry(Journal."Item No.", Journal."Variant Code", Journal."Location Code",
            Journal.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    local procedure EnsureConsumptionBatch(Request: Record "DOPSWHS Prod Output Request"; var TemplateName: Code[10]; var BatchName: Code[10])
    var
        Template: Record "Item Journal Template";
        Batch: Record "Item Journal Batch";
        Journal: Record "Item Journal Line";
    begin
        Template.LockTable();
        if not Template.Get('DOPSCON') then begin
            Template.Init();
            Template.Name := 'DOPSCON';
            Template.Type := Template.Type::Consumption;
            Template.Description := 'WMS consumption on output';
            Template.Insert(true);
        end;
        Template.TestField(Type, Template.Type::Consumption);
        Template.TestField(Recurring, false);
        TemplateName := Template.Name;
        BatchName := CopyStr(Request."Document No.", 1, 10);
        if not Batch.Get(TemplateName, BatchName) then begin
            Batch.Init();
            Batch."Journal Template Name" := TemplateName;
            Batch.Name := BatchName;
            Batch.Insert(true);
        end;
        Journal.SetRange("Journal Template Name", TemplateName);
        Journal.SetRange("Journal Batch Name", BatchName);
        if not Journal.IsEmpty() then
            Error('Tüketim günlüğünde bekleyen satır var; işlem yapılmadı.');
    end;

    local procedure AddTracking(Journal: Record "Item Journal Line"; Request: Record "DOPSWHS Prod Output Request")
    var
        Tracking: Record "Reservation Entry";
        CreateEntry: Codeunit "Create Reserv. Entry";
    begin
        if Request."Lot No." = '' then
            exit;
        Tracking."Lot No." := Request."Lot No.";
        CreateEntry.SetDates(0D, Request."Expiration Date");
        CreateEntry.CreateReservEntryFor(Database::"Item Journal Line", Journal."Entry Type".AsInteger(),
            Journal."Journal Template Name", Journal."Journal Batch Name", 0, Journal."Line No.",
            Journal."Qty. per Unit of Measure", Journal."Output Quantity", Journal."Output Quantity (Base)", Tracking);
        CreateEntry.CreateEntry(Journal."Item No.", Journal."Variant Code", Journal."Location Code", Journal.Description,
            Request."Posting Date", 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    procedure ResultJson(Request: Record "DOPSWHS Prod Output Request"): Text
    var
        Result: JsonObject;
        TextResult: Text;
    begin
        Result.Add('requestId', Request."Request ID");
        Result.Add('prodOrderNo', Request."Prod. Order No.");
        Result.Add('lineNo', Request."Prod. Order Line No.");
        Result.Add('itemNo', Request."Item No.");
        Result.Add('quantity', Request.Quantity);
        Result.Add('unitOfMeasureCode', Request."Unit of Measure Code");
        Result.Add('lotNo', Request."Lot No.");
        Result.Add('postingDate', Request."Posting Date");
        Result.Add('expirationDate', Request."Expiration Date");
        Result.Add('completed', Request.Completed);
        Result.Add('cancelled', Request.Cancelled);
        Result.Add('documentNo', Request."Document No.");
        Result.Add('entryNo', Request."Item Ledger Entry No.");
        Result.Add('quantityBase', Request."Quantity (Base)");
        Result.Add('baseUnitOfMeasure', Request."Base Unit of Measure");
        Result.WriteTo(TextResult);
        exit(TextResult);
    end;

    var
        NotPickedErr: Label '%1 bileşeni toplanmamış: bu çıktı için %2 %3 gerekiyor, üretim alanına toplanıp tüketilmemiş %4. Önce bu emrin toplamasını yapın.', Comment = '%1 = Madde, %2 = Gereken, %3 = Birim, %4 = Toplanan';
        NoLotStockErr: Label '%1 bileşeninin %2 lokasyonunda lotlu stoğu yetmiyor (%3 %4 eksik). Bileşeni toplayıp tekrar deneyin.', Comment = '%1 = Madde, %2 = Lokasyon, %3 = Eksik, %4 = Birim';
        SerialCompErr: Label '%1 bileşeni seri numarası takipli; otomatik tüketilemez. BC''de elle tüketin.', Comment = '%1 = Madde';
}
