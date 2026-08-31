codeunit 72446 "DOPSWHS Subcont Receipt Mgt"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS Subcontract Receipt" = RIMD,
        tabledata "Purchase Header" = RM,
        tabledata "Purchase Line" = RM,
        tabledata "Purch. Rcpt. Line" = R,
        tabledata Location = R,
        tabledata "Warehouse Receipt Header" = RM,
        tabledata "Warehouse Receipt Line" = RM;

    procedure Receive(PurchaseLine: Record "Purchase Line"; Quantity: Decimal; VendorShipmentNo: Code[35]; InboundReferenceNo: Code[50]; BinCode: Code[20]; FinishOperation: Boolean; VehiclePlateNo: Text; DriverCode: Code[20]; IdempotencyKey: Guid): Text
    var
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
        InsertPendingAudit(
            PurchaseHeader, PurchaseLine, Quantity, VendorShipmentNo, InboundReferenceNo,
            BinCode, FinishOperation, IdempotencyKey, Audit);

        if Location."Require Receive" then
            PostThroughWarehouse(
                PurchaseHeader, PurchaseLine, Quantity, VendorShipmentNo, BinCode,
                VehiclePlateNo, DriverCode, WarehouseReceiptNo)
        else
            PostDirect(PurchaseHeader);

        PostedReceiptNo := FindPostedReceiptNo(PurchaseLine."Document No.", PurchaseLine."Line No.");
        if PostedReceiptNo = '' then
            Error('%1/%2 fason kabulü post edildi ancak kayıtlı satın alma irsaliyesi bulunamadı.', PurchaseLine."Document No.", PurchaseLine."Line No.");
        Audit."Posted Purchase Receipt No." := PostedReceiptNo;
        Audit."Warehouse Receipt No." := WarehouseReceiptNo;
        Audit.Status := 'POSTED';
        Audit."Posted At" := CurrentDateTime();
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
        Audit."Created By" := CopyStr(UserId(), 1, MaxStrLen(Audit."Created By"));
        Audit."Created At" := CurrentDateTime();
        Audit.Insert(true);
    end;

    local procedure ReconcileOrReturn(PurchaseLine: Record "Purchase Line"; IdempotencyKey: Guid; var Audit: Record "DOPSWHS Subcontract Receipt"): Boolean
    var
        PostedReceiptNo: Code[20];
    begin
        Audit.SetRange("Idempotency Key", IdempotencyKey);
        if not Audit.FindFirst() then
            exit(false);
        if (Audit."Purchase Order No." <> PurchaseLine."Document No.") or
           (Audit."Purchase Line No." <> PurchaseLine."Line No.")
        then
            Error('İşlem anahtarı başka bir fason kabul satırı için kullanılmış. Ekranı yenileyip tekrar deneyin.');
        if Audit.Status = 'POSTED' then
            exit(true);
        PostedReceiptNo := FindPostedReceiptNo(Audit."Purchase Order No.", Audit."Purchase Line No.");
        if PostedReceiptNo = '' then
            Error('%1/%2 fason kabulünün önceki denemesi tamamlanmamış. BC belgesini kontrol edin; ikinci stok kaydı oluşturmadık.', Audit."Purchase Order No.", Audit."Purchase Line No.");
        Audit."Posted Purchase Receipt No." := PostedReceiptNo;
        Audit.Status := 'POSTED';
        Audit."Posted At" := CurrentDateTime();
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
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;
}
