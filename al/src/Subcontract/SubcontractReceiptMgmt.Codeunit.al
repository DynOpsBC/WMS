codeunit 72446 "DOPSWHS Subcont Receipt Mgt"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS Subcontract Receipt" = RIMD,
        tabledata "Purchase Header" = RM,
        tabledata "Purchase Line" = RM,
        tabledata "Purch. Rcpt. Line" = R,
        tabledata "Reservation Entry" = RIM,
        tabledata Location = R,
        tabledata "Warehouse Receipt Header" = RM,
        tabledata "Warehouse Receipt Line" = RM,
        tabledata "DOPSWHS Subcontract Dispatch" = RM;

    procedure Receive(PurchaseLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; InboundReferenceNo: Code[50]; BinCode: Code[20]; FinishOperation: Boolean; VehiclePlateNo: Text; DriverCode: Code[20]; IdempotencyKey: Guid): Text
    begin
        // Eski terminaller lot göndermez: lotlu mamulde lot madde serisinden verilir.
        exit(Receive(PurchaseLine, Quantity, VendorShipmentNo, InboundReferenceNo, BinCode, FinishOperation, VehiclePlateNo, DriverCode, '', 0D, IdempotencyKey));
    end;

    procedure Receive(PurchaseLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; InboundReferenceNo: Code[50]; BinCode: Code[20]; FinishOperation: Boolean; VehiclePlateNo: Text; DriverCode: Code[20]; LotNo: Code[50]; ExpirationDate: Date; IdempotencyKey: Guid): Text
    var
        Consumption: Codeunit "DOPSWHS Subcont Consumption";
        Audit: Record "DOPSWHS Subcontract Receipt";
        PurchaseHeader: Record "Purchase Header";
        Location: Record Location;
        PostedReceiptNo: Code[20];
        WarehouseReceiptNo: Code[20];
    begin
        if IsNullGuid(IdempotencyKey) then
            Error('İşlem anahtarı boş olamaz. Ekranı yenileyip tekrar deneyin.');
        Audit.LockTable();
        if ReconcileOrReturn(PurchaseLine, IdempotencyKey, Audit) then
            exit(ResultJson(Audit));

        ReloadAndValidateLine(PurchaseLine, Quantity, VendorShipmentNo, FinishOperation);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");
        if PurchaseHeader."Buy-from Vendor No." = '' then
            Error('%1 fason siparişinde tedarikçi boş.', PurchaseHeader."No.");
        if not Location.Get(PurchaseLine."Location Code") then
            Error('%1 lokasyonu bulunamadı.', PurchaseLine."Location Code");

        PreparePurchaseDocument(PurchaseHeader, PurchaseLine, Quantity, VendorShipmentNo, BinCode, FinishOperation);
        AssignOutputTracking(PurchaseLine, Quantity, LotNo, ExpirationDate);
        InsertPendingAudit(
            PurchaseHeader, PurchaseLine, Quantity, VendorShipmentNo, InboundReferenceNo,
            BinCode, FinishOperation, IdempotencyKey, Audit);

        // BC fason satın alma satırını ambar mal kabulüne almaz ("alınacak miktar kalmamış");
        // fason çıktısı satın alma kabulüyle doğrudan kaydedilir. Plaka/sürücü yine zorunlu.
        if Location."Require Receive" and (PurchaseLine."Prod. Order No." = '') then
            PostThroughWarehouse(
                PurchaseHeader, PurchaseLine, Quantity, VendorShipmentNo, BinCode,
                VehiclePlateNo, DriverCode, WarehouseReceiptNo)
        else begin
            if Location."Require Receive" and ((DelChr(VehiclePlateNo, '<>', ' ') = '') or (DriverCode = '')) then
                Error('BADE ambar kabulünde araç plakası ve sürücü kodu zorunludur.');
            PostDirect(PurchaseHeader);
        end;

        PostedReceiptNo := FindPostedReceiptNo(PurchaseLine."Document No.", PurchaseLine."Line No.");
        if PostedReceiptNo = '' then
            Error('%1/%2 fason kabulü post edildi ancak kayıtlı satın alma irsaliyesi bulunamadı.', PurchaseLine."Document No.", PurchaseLine."Line No.");
        Audit."Posted Purchase Receipt No." := PostedReceiptNo;
        Audit."Warehouse Receipt No." := WarehouseReceiptNo;
        Audit.Status := 'POSTED';
        Audit."Posted At" := CurrentDateTime();
        Consumption.PostForReceipt(Audit);
        Audit.Modify(true);
        exit(ResultJson(Audit));
    end;

    local procedure ReloadAndValidateLine(var PurchaseLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; FinishOperation: Boolean)
    begin
        if not PurchaseLine.Get(PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.") then
            Error('Fason satın alma satırı artık bulunamıyor. Listeyi yenileyin.');
        PurchaseLine.TestField("Document Type", PurchaseLine."Document Type"::Order);
        PurchaseLine.TestField(Type, PurchaseLine.Type::Item);
        PurchaseLine.TestField("Prod. Order No.");
        PurchaseLine.TestField("Operation No.");
        PurchaseLine.TestField("Work Center No.");
        PurchaseLine.TestField("Location Code");
        ValidateRequest(PurchaseLine."No.", PurchaseLine."Outstanding Quantity", Quantity, VendorShipmentNo, FinishOperation);
    end;

    procedure ValidateRequest(ItemNo: Code[20]; OutstandingQuantity: Decimal; Quantity: Decimal; VendorShipmentNo: Code[35]; FinishOperation: Boolean)
    begin
        if Quantity <= 0 then
            Error('Teslim alınacak miktar sıfırdan büyük olmalıdır.');
        if Quantity > OutstandingQuantity then
            Error('%1 için istenen %2, açık fason kabul miktarı %3 değerini aşıyor.', ItemNo, Quantity, OutstandingQuantity);
        if VendorShipmentNo = '' then
            Error('Gelen irsaliye numarası zorunludur.');
        if FinishOperation and (Abs(Quantity - OutstandingQuantity) > 0.00001) then
            Error('Fason operasyonu yalnız kalan miktarın tamamı (%1) kabul edildiğinde kapatılabilir. Parsiyel kabulde kapatma seçimini kaldırın.', OutstandingQuantity);
    end;

    local procedure PreparePurchaseDocument(var PurchaseHeader: Record "Purchase Header"; var SelectedLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; BinCode: Code[20]; FinishOperation: Boolean)
    var
        PurchaseLine: Record "Purchase Line";
        ReleasePurchaseDocument: Codeunit "Release Purchase Document";
    begin
        if PurchaseHeader.Status <> PurchaseHeader.Status::Released then
            ReleasePurchaseDocument.PerformManualRelease(PurchaseHeader);
        PurchaseHeader.Get(PurchaseHeader."Document Type", PurchaseHeader."No.");
        PurchaseHeader.Validate("Vendor Shipment No.", VendorShipmentNo);
        PurchaseHeader.Modify(true);

        // BC posting defaults every outstanding purchase line to receive. A
        // terminal confirmation must never receive unrelated PO lines.
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        if PurchaseLine.FindSet(true) then
            repeat
                if PurchaseLine."Qty. to Receive" <> 0 then begin
                    PurchaseLine.Validate("Qty. to Receive", 0);
                    PurchaseLine.Modify(true);
                end;
            until PurchaseLine.Next() = 0;

        SelectedLine.Get(SelectedLine."Document Type", SelectedLine."Document No.", SelectedLine."Line No.");
        if BinCode <> '' then
            SelectedLine.Validate("Bin Code", BinCode);
        SelectedLine.Validate("Qty. to Receive", Quantity);
        SelectedLine.Validate(Finished, FinishOperation);
        SelectedLine.Modify(true);
    end;

    /// <summary>
    /// Fason son operasyonsa satın alma kabulü mamulü stoka alır; lotlu mamulde
    /// satın alma satırına lot bağlanır. Lot girilmediyse madde lot serisinden
    /// verilir. BC'de satıra zaten tam lot atanmışsa ona dokunulmaz.
    /// </summary>
    local procedure AssignOutputTracking(PurchaseLine: Record "Purchase Line"; Quantity: Decimal; LotNo: Code[50]; ExpirationDate: Date)
    var
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        ReservEntry: Record "Reservation Entry";
        TempReservation: Record "Reservation Entry" temporary;
        LotSerialGen: Codeunit "DOPSWHS Lot Serial Generator";
        CreateReservEntry: Codeunit "Create Reserv. Entry";
        UOMMgt: Codeunit "Unit of Measure Management";
        ProdOrderLine: Record "Prod. Order Line";
        QtyPerUoM: Decimal;
        QtyBase: Decimal;
    begin
        AssignedLotNo := '';
        if not Item.Get(PurchaseLine."No.") then
            exit;
        if (Item."Item Tracking Code" = '') or not TrackingCode.Get(Item."Item Tracking Code") then
            exit;
        // Fason çıktısı üretim girişidir; ayrıntılı ayarlarda "Lot Manuf. Inbound" belirleyicidir.
        if TrackingCode."SN Specific Tracking" or TrackingCode."SN Manuf. Inbound Tracking" then
            Error('%1 seri numarası izlenen bir ürün; fason teslimde seri girişi desteklenmiyor. BC satın alma satırında seri atayın.', Item."No.");
        if not (TrackingCode."Lot Specific Tracking" or TrackingCode."Lot Manuf. Inbound Tracking" or TrackingCode."Lot Purchase Inbound Tracking") then
            exit;
        PurchaseLine.Get(PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.");
        // Purch.-Post fason çıktısını Output olarak kaydeder; satırın temel miktarı 0
        // olduğu için satın alma lotu taşınmaz. Çıktı kaydı lotu üretim emri satırından
        // alır (Mfg. Item Jnl.-Post Line: TransferPOLineToItemJnlLine).
        ProdOrderLine.Get(ProdOrderLine.Status::Released, PurchaseLine."Prod. Order No.", PurchaseLine."Prod. Order Line No.");
        // Fason satın alma satırında "Qty. per Unit of Measure" 0 bırakılır (Calculate
        // Subcontracts); katsayı maddenin ölçü biriminden alınır.
        QtyPerUoM := PurchaseLine."Qty. per Unit of Measure";
        if QtyPerUoM = 0 then
            QtyPerUoM := UOMMgt.GetQtyPerUnitOfMeasure(Item, PurchaseLine."Unit of Measure Code");
        if QtyPerUoM = 0 then
            QtyPerUoM := 1;
        QtyBase := Round(Quantity * QtyPerUoM, 0.00001);
        ReservEntry.SetRange("Source Type", Database::"Prod. Order Line");
        ReservEntry.SetRange("Source Subtype", ProdOrderLine.Status.AsInteger());
        ReservEntry.SetRange("Source ID", ProdOrderLine."Prod. Order No.");
        ReservEntry.SetRange("Source Prod. Order Line", ProdOrderLine."Line No.");
        ReservEntry.SetFilter("Lot No.", '<>%1', '');
        ReservEntry.CalcSums("Qty. to Handle (Base)");
        if ReservEntry."Qty. to Handle (Base)" + 0.00001 >= QtyBase then begin
            if ReservEntry.FindFirst() then
                AssignedLotNo := ReservEntry."Lot No.";
            exit;
        end;
        if not ReservEntry.IsEmpty() then
            Error('%1 üretim emri satırında BC''de kısmi lot ataması var. Lotları BC''de tamamlayın veya silin.', ProdOrderLine."Prod. Order No.");
        if LotNo = '' then
            LotNo := LotSerialGen.GenerateLotNoForItem(Item."No.");
        if LotNo = '' then
            Error('%1 lot izlenen bir ürün. Fason firmanın lot numarasını girin (madde kartında lot no. serisi de tanımlı değil).', Item."No.");
        if TrackingCode."Man. Expir. Date Entry Reqd." and (ExpirationDate = 0D) then
            Error('%1 için son kullanma tarihi zorunlu. Fason firmanın belgesindeki SKT''yi girin.', Item."No.");
        TempReservation."Lot No." := LotNo;
        CreateReservEntry.SetDates(0D, ExpirationDate);
        CreateReservEntry.SetQtyToHandleAndInvoice(QtyBase, QtyBase);
        CreateReservEntry.CreateReservEntryFor(
            Database::"Prod. Order Line", ProdOrderLine.Status.AsInteger(), ProdOrderLine."Prod. Order No.", '',
            ProdOrderLine."Line No.", 0, ProdOrderLine."Qty. per Unit of Measure",
            Round(QtyBase / ProdOrderLine."Qty. per Unit of Measure", 0.00001), QtyBase, TempReservation);
        CreateReservEntry.CreateEntry(
            ProdOrderLine."Item No.", ProdOrderLine."Variant Code", ProdOrderLine."Location Code", ProdOrderLine.Description,
            ProdOrderLine."Due Date", 0D, 0, Enum::"Reservation Status"::Surplus);
        AssignedLotNo := LotNo;
    end;

    local procedure PostDirect(var PurchaseHeader: Record "Purchase Header")
    var
        PurchasePost: Codeunit "Purch.-Post";
    begin
        PurchaseHeader.Get(PurchaseHeader."Document Type", PurchaseHeader."No.");
        PurchaseHeader.Receive := true;
        PurchaseHeader.Invoice := false;
        PurchaseHeader.Modify(true);
        PurchasePost.SetSuppressCommit(true);
        PurchasePost.Run(PurchaseHeader);
    end;

    local procedure PostThroughWarehouse(PurchaseHeader: Record "Purchase Header"; SelectedLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; BinCode: Code[20]; VehiclePlateNo: Text; DriverCode: Code[20]; var WarehouseReceiptNo: Code[20])
    var
        PurchaseSourceMgmt: Codeunit "DOPSWHS Purch Source Mgmt";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        SelectedReceiptLine: Record "Warehouse Receipt Line";
    begin
        WarehouseReceiptNo := PurchaseSourceMgmt.CreateWhseReceipt(PurchaseHeader."No.");
        WarehouseReceiptHeader.Get(WarehouseReceiptNo);
        WarehouseReceiptHeader.Validate("Vendor Shipment No.", VendorShipmentNo);
        WarehouseReceiptHeader.Modify(true);

        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptNo);
        if WarehouseReceiptLine.FindSet(true) then
            repeat
                if (WarehouseReceiptLine."Source Type" = Database::"Purchase Line") and
                   (WarehouseReceiptLine."Source No." = SelectedLine."Document No.") and
                   (WarehouseReceiptLine."Source Line No." = SelectedLine."Line No.")
                then
                    SelectedReceiptLine := WarehouseReceiptLine;
                if WarehouseReceiptLine."Qty. to Receive" <> 0 then begin
                    WarehouseReceiptLine.Validate("Qty. to Receive", 0);
                    WarehouseReceiptLine.Modify(true);
                end;
            until WarehouseReceiptLine.Next() = 0;
        if SelectedReceiptLine."No." = '' then
            Error('%1/%2 fason satırı %3 ambar kabul belgesinde bulunamadı.', SelectedLine."Document No.", SelectedLine."Line No.", WarehouseReceiptNo);
        SelectedReceiptLine.Get(SelectedReceiptLine."No.", SelectedReceiptLine."Line No.");
        if BinCode <> '' then
            SelectedReceiptLine.Validate("Bin Code", BinCode);
        SelectedReceiptLine.Validate("Qty. to Receive", Quantity);
        SelectedReceiptLine.Modify(true);

        if ReceiptMgmt.VehicleInfoRequired(WarehouseReceiptHeader) then begin
            if (DelChr(VehiclePlateNo, '<>', ' ') = '') or (DriverCode = '') then
                Error('BADE ambar kabulünde araç plakası ve sürücü kodu zorunludur.');
            ReceiptMgmt.SetVehicleInfo(WarehouseReceiptHeader, VehiclePlateNo, DriverCode, VendorShipmentNo);
        end;
        ReceiptMgmt.PostReceipt(WarehouseReceiptHeader, false, false, CopyStr(UserId(), 1, 50), '');
    end;

    local procedure InsertPendingAudit(PurchaseHeader: Record "Purchase Header"; PurchaseLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; InboundReferenceNo: Code[50]; BinCode: Code[20]; FinishOperation: Boolean; IdempotencyKey: Guid; var Audit: Record "DOPSWHS Subcontract Receipt")
    begin
        Audit.Init();
        Audit."Idempotency Key" := IdempotencyKey;
        Audit."Purchase Order No." := PurchaseLine."Document No.";
        Audit."Purchase Line No." := PurchaseLine."Line No.";
        Audit."Prod. Order No." := PurchaseLine."Prod. Order No.";
        Audit."Prod. Order Line No." := PurchaseLine."Prod. Order Line No.";
        Audit."Routing Reference No." := PurchaseLine."Routing Reference No.";
        Audit."Routing No." := PurchaseLine."Routing No.";
        Audit."Operation No." := PurchaseLine."Operation No.";
        Audit."Work Center No." := PurchaseLine."Work Center No.";
        Audit."Item No." := PurchaseLine."No.";
        Audit.Quantity := Quantity;
        Audit."Unit of Measure Code" := PurchaseLine."Unit of Measure Code";
        Audit."Location Code" := PurchaseLine."Location Code";
        if BinCode <> '' then
            Audit."Bin Code" := BinCode
        else
            Audit."Bin Code" := PurchaseLine."Bin Code";
        Audit."Vendor No." := PurchaseHeader."Buy-from Vendor No.";
        Audit."Vendor Shipment No." := VendorShipmentNo;
        Audit."Inbound Reference No." := InboundReferenceNo;
        Audit."Operation Finished" := FinishOperation;
        Audit.Status := 'PENDING';
        Audit."Consumption Status" := 'PENDING';
        Audit."Lot No." := AssignedLotNo;
        Audit."Created By" := CopyStr(UserId(), 1, MaxStrLen(Audit."Created By"));
        Audit."Created At" := CurrentDateTime();
        Audit.Insert(true);
    end;

    local procedure ReconcileOrReturn(PurchaseLine: Record "Purchase Line"; IdempotencyKey: Guid; var Audit: Record "DOPSWHS Subcontract Receipt"): Boolean
    var
        Consumption: Codeunit "DOPSWHS Subcont Consumption";
        PostedReceiptNo: Code[20];
    begin
        Audit.SetRange("Idempotency Key", IdempotencyKey);
        if not Audit.FindFirst() then
            exit(false);
        if (Audit."Purchase Order No." <> PurchaseLine."Document No.") or
           (Audit."Purchase Line No." <> PurchaseLine."Line No.")
        then
            Error('İşlem anahtarı başka bir fason kabul satırı için kullanılmış. Ekranı yenileyip tekrar deneyin.');
        if Audit.Status = 'POSTED' then begin
            // Ambar kabulü commit ettikten sonra sarfiyat hata verdiyse aynı işlem
            // anahtarıyla tekrar denemede yalnız sarfiyat tamamlanır.
            if Audit."Consumption Status" = 'PENDING' then begin
                Consumption.PostForReceipt(Audit);
                Audit.Modify(true);
            end;
            exit(true);
        end;
        PostedReceiptNo := FindPostedReceiptNo(Audit."Purchase Order No.", Audit."Purchase Line No.");
        if PostedReceiptNo = '' then
            Error('%1/%2 fason kabulünün önceki denemesi tamamlanmamış. BC belgesini kontrol edin; ikinci stok kaydı oluşturmadık.', Audit."Purchase Order No.", Audit."Purchase Line No.");
        Audit."Posted Purchase Receipt No." := PostedReceiptNo;
        Audit.Status := 'POSTED';
        Audit."Posted At" := CurrentDateTime();
        if Audit."Consumption Status" = 'PENDING' then
            Consumption.PostForReceipt(Audit);
        Audit.Modify(true);
        exit(true);
    end;

    local procedure FindPostedReceiptNo(OrderNo: Code[20]; OrderLineNo: Integer): Code[20]
    var
        PurchaseReceiptLine: Record "Purch. Rcpt. Line";
    begin
        PurchaseReceiptLine.SetRange("Order No.", OrderNo);
        PurchaseReceiptLine.SetRange("Order Line No.", OrderLineNo);
        PurchaseReceiptLine.SetFilter(Quantity, '<>0');
        if PurchaseReceiptLine.FindLast() then
            exit(PurchaseReceiptLine."Document No.");
    end;

    local procedure ResultJson(Audit: Record "DOPSWHS Subcontract Receipt"): Text
    var
        Result: JsonObject;
        ResultText: Text;
        PurchaseLine: Record "Purchase Line";
        ServiceReceiptComplete: Boolean;
    begin
        if PurchaseLine.Get(PurchaseLine."Document Type"::Order, Audit."Purchase Order No.", Audit."Purchase Line No.") then
            ServiceReceiptComplete := PurchaseLine."Outstanding Quantity" = 0
        else
            ServiceReceiptComplete := true;
        Result.Add('postedPurchaseReceiptNo', Audit."Posted Purchase Receipt No.");
        Result.Add('warehouseReceiptNo', Audit."Warehouse Receipt No.");
        Result.Add('purchaseOrderNo', Audit."Purchase Order No.");
        Result.Add('prodOrderNo', Audit."Prod. Order No.");
        Result.Add('operationNo', Audit."Operation No.");
        Result.Add('itemNo', Audit."Item No.");
        Result.Add('quantity', Audit.Quantity);
        Result.Add('operationFinished', Audit."Operation Finished");
        Result.Add('serviceReceiptComplete', ServiceReceiptComplete);
        Result.Add('invoicePending', true);
        Result.Add('consumptionStatus', Audit."Consumption Status");
        Result.Add('lotNo', Audit."Lot No.");
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    var
        AssignedLotNo: Code[50];
}
