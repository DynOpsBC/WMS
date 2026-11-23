codeunit 72234 "DOPSWHS Partial Output Mgmt"
{
    // Request and ledger posting commit together. Printing is a separate action.
    Permissions = tabledata "DOPSWHS Prod Output Request" = rim,
                  tabledata "Item Journal Template" = ri,
                  tabledata "Item Journal Batch" = ri,
                  tabledata "Item Journal Line" = rimd,
                  tabledata "Lot No. Information" = ri;

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
}
