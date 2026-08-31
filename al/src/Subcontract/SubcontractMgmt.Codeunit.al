codeunit 72443 "DOPSWHS Subcontract Mgmt"
{
    Permissions =
        tabledata "DOPSWHS Subcontract Dispatch" = RIMD,
        tabledata "Transfer Header" = RIMD,
        tabledata "Transfer Line" = RIMD,
        tabledata "Transfer Shipment Header" = R,
        tabledata "Inventory Setup" = R,
        tabledata "Reservation Entry" = RIMD,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RIMD;

    procedure GetDispatchedQuantity(Component: Record "Prod. Order Component"): Decimal
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        ReconcilePendingForComponent(Component);
        Dispatch.SetRange("Prod. Order No.", Component."Prod. Order No.");
        Dispatch.SetRange("Prod. Order Line No.", Component."Prod. Order Line No.");
        Dispatch.SetRange("Component Line No.", Component."Line No.");
        Dispatch.SetRange(Status, 'POSTED');
        Dispatch.CalcSums(Quantity);
        exit(Dispatch.Quantity);
    end;

    procedure GetRemainingDispatchQuantity(Component: Record "Prod. Order Component"): Decimal
    var
        RemainingQty: Decimal;
    begin
        RemainingQty := Component."Expected Quantity" - GetDispatchedQuantity(Component);
        if RemainingQty > Component."Remaining Quantity" then
            RemainingQty := Component."Remaining Quantity";
        if RemainingQty < 0 then
            RemainingQty := 0;
        exit(RemainingQty);
    end;

    procedure GetOperationSummary(RoutingLine: Record "Prod. Order Routing Line"; var ComponentCount: Integer; var RemainingQty: Decimal)
    var
        Component: Record "Prod. Order Component";
    begin
        Component.SetRange(Status, RoutingLine.Status);
        Component.SetRange("Prod. Order No.", RoutingLine."Prod. Order No.");
        ApplyRoutingLinkFilter(RoutingLine, Component);
        if Component.FindSet() then
            repeat
                if GetRemainingDispatchQuantity(Component) > 0 then begin
                    ComponentCount += 1;
                    RemainingQty += GetRemainingDispatchQuantity(Component);
                end;
            until Component.Next() = 0;
    end;

    procedure Dispatch(RoutingLine: Record "Prod. Order Routing Line"; LinesJson: Text; IdempotencyKey: Guid): Text
    var
        TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary;
        WorkCenter: Record "Work Center";
        TransferHeader: Record "Transfer Header";
        ExistingDispatch: Record "DOPSWHS Subcontract Dispatch";
        TargetLocation: Record Location;
        TransferNo: Code[20];
        PostedShipmentNo: Code[20];
        FasonReferenceNo: Code[50];
        PurchaseOrderNo: Code[20];
    begin
        if IsNullGuid(IdempotencyKey) then
            Error('İşlem anahtarı boş olamaz. Ekranı yenileyip tekrar deneyin.');
        ExistingDispatch.LockTable();
        RoutingLine.TestField(Status, RoutingLine.Status::Released);
        RoutingLine.TestField(Type, RoutingLine.Type::"Work Center");
        WorkCenter.Get(RoutingLine."No.");
        WorkCenter.TestField("Subcontractor No.");

        if ReconcileOrReturn(IdempotencyKey, RoutingLine, TransferNo, PostedShipmentNo) then begin
            ExistingDispatch.Reset();
            ExistingDispatch.SetRange("Idempotency Key", IdempotencyKey);
            ExistingDispatch.FindFirst();
            UpdateDispatchedLps(
                IdempotencyKey, ExistingDispatch."To Location Code", ExistingDispatch."To Bin Code");
            exit(ResultJson(TransferNo, PostedShipmentNo, ExistingDispatch."Fason Reference No."));
        end;

        if WorkCenter."Location Code" = '' then
            Error('%1 iş merkezinde Fason Lokasyonu (Location Code) tanımlı değil.', WorkCenter."No.");
        TargetLocation.Get(WorkCenter."Location Code");
        if TargetLocation."Bin Mandatory" and (WorkCenter."To-Production Bin Code" = '') then
            Error('%1 fason lokasyonunda bin zorunlu. %2 iş merkezinde To-Production Bin Code tanımlayın.', TargetLocation.Code, WorkCenter."No.");
        EnsureTransferPostingSetup();

        ParseAndValidateLines(RoutingLine, WorkCenter, LinesJson, IdempotencyKey, TempDispatch);
        PurchaseOrderNo := FindSubcontractPurchaseOrder(RoutingLine, WorkCenter);
        if PurchaseOrderNo <> '' then
            FasonReferenceNo := PurchaseOrderNo
        else
            FasonReferenceNo := RoutingLine."Prod. Order No.";
        CreateTransfer(RoutingLine, WorkCenter, TempDispatch, TransferHeader, PurchaseOrderNo, FasonReferenceNo);
        TransferNo := TransferHeader."No.";
        PersistPending(TempDispatch, TransferNo, PurchaseOrderNo, FasonReferenceNo);

        ReleaseAndPost(TransferHeader);
        PostedShipmentNo := FindPostedShipmentNo(TransferNo);
        if PostedShipmentNo = '' then
            Error('%1 transferi post edildi ancak kayıtlı transfer irsaliyesi bulunamadı.', TransferNo);

        ExistingDispatch.SetRange("Idempotency Key", IdempotencyKey);
        ExistingDispatch.ModifyAll(Status, 'POSTED');
        ExistingDispatch.ModifyAll("Posted Transfer Shipment No.", PostedShipmentNo);
        ExistingDispatch.ModifyAll("Posted At", CurrentDateTime());
        UpdateDispatchedLps(
            IdempotencyKey, WorkCenter."Location Code", WorkCenter."To-Production Bin Code");
        exit(ResultJson(TransferNo, PostedShipmentNo, FasonReferenceNo));
    end;

    local procedure ParseAndValidateLines(RoutingLine: Record "Prod. Order Routing Line"; WorkCenter: Record "Work Center"; LinesJson: Text; IdempotencyKey: Guid; var TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary)
    var
        Component: Record "Prod. Order Component";
        Rows: JsonArray;
        RowToken: JsonToken;
        Row: JsonObject;
        ProdOrderLineNo: Integer;
        ComponentLineNo: Integer;
        Qty: Decimal;
        LpNo: Code[20];
        LotNo: Code[50];
        SerialNo: Code[50];
        FromBinCode: Code[20];
        SourceLocation: Code[10];
        SourceLocationRecord: Record Location;
        RemainingQty: Decimal;
        EntryNo: Integer;
    begin
        if LinesJson = '' then
            Error('Sevk edilecek malzeme satırları boş olamaz.');
        if not Rows.ReadFrom(LinesJson) then
            Error('Malzeme satırları geçerli JSON değil.');
        if Rows.Count() = 0 then
            Error('En az bir malzeme seçin.');

        foreach RowToken in Rows do begin
            Row := RowToken.AsObject();
            ProdOrderLineNo := RequireInteger(Row, 'prodOrderLineNo');
            ComponentLineNo := RequireInteger(Row, 'componentLineNo');
            Qty := RequireDecimal(Row, 'quantity');
            LpNo := CopyStr(OptionalText(Row, 'lpNo'), 1, MaxStrLen(LpNo));
            LotNo := CopyStr(OptionalText(Row, 'lotNo'), 1, MaxStrLen(LotNo));
            SerialNo := CopyStr(OptionalText(Row, 'serialNo'), 1, MaxStrLen(SerialNo));
            FromBinCode := CopyStr(OptionalText(Row, 'fromBinCode'), 1, MaxStrLen(FromBinCode));
            if Qty <= 0 then
                Error('%1 bileşeninde sevk miktarı sıfırdan büyük olmalıdır.', ComponentLineNo);
            if not Component.Get(RoutingLine.Status, RoutingLine."Prod. Order No.", ProdOrderLineNo, ComponentLineNo) then
                Error('%1/%2 üretim bileşeni artık bulunamıyor.', ProdOrderLineNo, ComponentLineNo);
            EnsureComponentBelongsToOperation(RoutingLine, Component);
            Component.TestField("Location Code");
            if Component."Location Code" = WorkCenter."Location Code" then
                Error('%1 bileşeninin kaynak ve fason lokasyonu aynı (%2).', Component."Item No.", Component."Location Code");
            if SourceLocation = '' then
                SourceLocation := Component."Location Code"
            else
                if SourceLocation <> Component."Location Code" then
                    Error('Tek sevkte yalnız bir kaynak lokasyon kullanılabilir. %1 ve %2 satırlarını ayrı gönderin.', SourceLocation, Component."Location Code");

            RemainingQty := GetRemainingDispatchQuantity(Component) - TempQuantityForComponent(TempDispatch, ProdOrderLineNo, ComponentLineNo);
            if Qty > RemainingQty then
                Error('%1 için istenen %2, fasona gönderilmemiş kalan %3 miktarını aşıyor.', Component."Item No.", Qty, RemainingQty);
            ValidateTrackingAndLp(
                Component, Qty, LpNo, LotNo, SerialNo,
                TempQuantityForLpItem(TempDispatch, LpNo, Component."Item No.", LotNo, SerialNo));

            EntryNo += 1;
            TempDispatch.Init();
            TempDispatch."Entry No." := EntryNo;
            TempDispatch."Idempotency Key" := IdempotencyKey;
            TempDispatch."Prod. Order No." := Component."Prod. Order No.";
            TempDispatch."Prod. Order Line No." := Component."Prod. Order Line No.";
            TempDispatch."Component Line No." := Component."Line No.";
            TempDispatch."Routing Reference No." := RoutingLine."Routing Reference No.";
            TempDispatch."Routing No." := RoutingLine."Routing No.";
            TempDispatch."Operation No." := RoutingLine."Operation No.";
            TempDispatch."Item No." := Component."Item No.";
            TempDispatch.Quantity := Qty;
            TempDispatch."Unit of Measure Code" := Component."Unit of Measure Code";
            TempDispatch."LP No." := LpNo;
            TempDispatch."Lot No." := LotNo;
            TempDispatch."Serial No." := SerialNo;
            TempDispatch."Subcontractor No." := WorkCenter."Subcontractor No.";
            TempDispatch."Work Center No." := WorkCenter."No.";
            TempDispatch."From Location Code" := Component."Location Code";
            TempDispatch."To Location Code" := WorkCenter."Location Code";
            if FromBinCode = '' then
                FromBinCode := Component."Bin Code";
            SourceLocationRecord.Get(Component."Location Code");
            if SourceLocationRecord."Bin Mandatory" and (FromBinCode = '') then
                Error('%1 kaynak lokasyonunda bin zorunlu. %2 bileşeni için kaynak bin girin.', Component."Location Code", Component."Item No.");
            TempDispatch."From Bin Code" := FromBinCode;
            TempDispatch."To Bin Code" := WorkCenter."To-Production Bin Code";
            TempDispatch.Insert();
        end;
    end;

    local procedure CreateTransfer(RoutingLine: Record "Prod. Order Routing Line"; WorkCenter: Record "Work Center"; var TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary; var TransferHeader: Record "Transfer Header"; PurchaseOrderNo: Code[20]; FasonReferenceNo: Code[50])
    var
        TransferLine: Record "Transfer Line";
        LineNo: Integer;
    begin
        TempDispatch.Reset();
        TempDispatch.FindFirst();
        TransferHeader.Init();
        TransferHeader.Insert(true);
        TransferHeader.Validate("Transfer-from Code", TempDispatch."From Location Code");
        TransferHeader.Validate("Transfer-to Code", WorkCenter."Location Code");
        TransferHeader.Validate("Direct Transfer", true);
        TransferHeader.Validate("Posting Date", WorkDate());
        TransferHeader.Validate("Shipment Date", WorkDate());
        TransferHeader.Validate("Receipt Date", WorkDate());
        TransferHeader."External Document No." := CopyStr(FasonReferenceNo, 1, MaxStrLen(TransferHeader."External Document No."));
        TransferHeader."DOPSWHS Fason Reference No." := FasonReferenceNo;
        TransferHeader."DOPSWHS Fason Prod. Order No." := RoutingLine."Prod. Order No.";
        TransferHeader."DOPSWHS Fason Purch. Order No." := PurchaseOrderNo;
        TransferHeader."DOPSWHS Fason Operation No." := RoutingLine."Operation No.";
        TransferHeader.Modify(true);

        TempDispatch.Reset();
        if TempDispatch.FindSet() then
            repeat
                LineNo += 10000;
                TransferLine.Init();
                TransferLine."Document No." := TransferHeader."No.";
                TransferLine."Line No." := LineNo;
                TransferLine.Insert(true);
                TransferLine.Validate("Item No.", TempDispatch."Item No.");
                TransferLine.Validate("Unit of Measure Code", TempDispatch."Unit of Measure Code");
                TransferLine.Validate(Quantity, TempDispatch.Quantity);
                if TempDispatch."From Bin Code" <> '' then
                    TransferLine.Validate("Transfer-from Bin Code", TempDispatch."From Bin Code");
                if WorkCenter."To-Production Bin Code" <> '' then
                    TransferLine.Validate("Transfer-To Bin Code", WorkCenter."To-Production Bin Code");
                TransferLine.Modify(true);
                AddItemTracking(TransferLine, TempDispatch."Lot No.", TempDispatch."Serial No.");
            until TempDispatch.Next() = 0;
    end;

    local procedure AddItemTracking(TransferLine: Record "Transfer Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        TempReservation: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        Item.Get(TransferLine."Item No.");
        if (Item."Item Tracking Code" = '') or (not TrackingCode.Get(Item."Item Tracking Code")) then
            exit;

        // Transfer Item Tracking Lines uses an outbound Surplus entry. Using
        // Transfer Line-Reserve.CreateReservation directly is not valid here:
        // that routine requires a populated source Tracking Specification and
        // is intended to bind an existing supply to the transfer demand.
        TempReservation."Lot No." := LotNo;
        TempReservation."Serial No." := SerialNo;
        CreateReservEntry.SetQtyToHandleAndInvoice(
            -TransferLine."Quantity (Base)", -TransferLine."Quantity (Base)");
        CreateReservEntry.CreateReservEntryFor(
            Database::"Transfer Line", Enum::"Transfer Direction"::Outbound.AsInteger(),
            TransferLine."Document No.", '', TransferLine."Derived From Line No.", TransferLine."Line No.",
            TransferLine."Qty. per Unit of Measure", 0, -TransferLine."Quantity (Base)", TempReservation);
        CreateReservEntry.CreateEntry(
            TransferLine."Item No.", TransferLine."Variant Code", TransferLine."Transfer-from Code",
            TransferLine.Description, TransferLine."Receipt Date", TransferLine."Shipment Date", 0,
            Enum::"Reservation Status"::Surplus);
    end;

    local procedure ReleaseAndPost(var TransferHeader: Record "Transfer Header")
    var
        ReleaseTransfer: Codeunit "Release Transfer Document";
        PostShipment: Codeunit "TransferOrder-Post Shipment";
    begin
        ReleaseTransfer.Release(TransferHeader);
        TransferHeader.Get(TransferHeader."No.");
        PostShipment.Run(TransferHeader);
    end;

    local procedure EnsureTransferPostingSetup()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        if InventorySetup."Direct Transfer Posting" <>
           InventorySetup."Direct Transfer Posting"::"Receipt and Shipment"
        then
            Error(
                'Fason sevkinde transfer irsaliyesi ve hedef stok aynı anda oluşmalıdır. Inventory Setup / Direct Transfer Posting alanını Receipt and Shipment yapın.');
    end;

    local procedure PersistPending(var TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary; TransferNo: Code[20]; PurchaseOrderNo: Code[20]; FasonReferenceNo: Code[50])
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        TempDispatch.Reset();
        if TempDispatch.FindSet() then
            repeat
                Dispatch := TempDispatch;
                Dispatch."Entry No." := 0;
                Dispatch."Transfer Order No." := TransferNo;
                Dispatch."Purchase Order No." := PurchaseOrderNo;
                Dispatch."Fason Reference No." := FasonReferenceNo;
                Dispatch.Status := 'PENDING';
                Dispatch."Created By" := CopyStr(UserId(), 1, MaxStrLen(Dispatch."Created By"));
                Dispatch."Created At" := CurrentDateTime();
                Dispatch.Insert(true);
            until TempDispatch.Next() = 0;
    end;

    local procedure FindSubcontractPurchaseOrder(RoutingLine: Record "Prod. Order Routing Line"; WorkCenter: Record "Work Center"): Code[20]
    var
        PurchaseLine: Record "Purchase Line";
        FoundOrderNo: Code[20];
    begin
        PurchaseLine.SetRange("Document Type", PurchaseLine."Document Type"::Order);
        PurchaseLine.SetRange("Prod. Order No.", RoutingLine."Prod. Order No.");
        PurchaseLine.SetRange("Routing Reference No.", RoutingLine."Routing Reference No.");
        PurchaseLine.SetRange("Routing No.", RoutingLine."Routing No.");
        PurchaseLine.SetRange("Operation No.", RoutingLine."Operation No.");
        PurchaseLine.SetRange("Work Center No.", WorkCenter."No.");
        if PurchaseLine.FindSet() then
            repeat
                if FoundOrderNo = '' then
                    FoundOrderNo := PurchaseLine."Document No."
                else
                    if FoundOrderNo <> PurchaseLine."Document No." then
                        Error(
                            '%1 üretim emri / %2 operasyonu birden fazla fason satın alma siparişine bağlı (%3 ve %4). Sevkten önce BC bağlantısını tekilleştirin.',
                            RoutingLine."Prod. Order No.", RoutingLine."Operation No.", FoundOrderNo, PurchaseLine."Document No.");
            until PurchaseLine.Next() = 0;
        exit(FoundOrderNo);
    end;

    local procedure ReconcileOrReturn(IdempotencyKey: Guid; RoutingLine: Record "Prod. Order Routing Line"; var TransferNo: Code[20]; var PostedShipmentNo: Code[20]): Boolean
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        Dispatch.SetRange("Idempotency Key", IdempotencyKey);
        if not Dispatch.FindFirst() then
            exit(false);
        if (Dispatch."Prod. Order No." <> RoutingLine."Prod. Order No.") or
           (Dispatch."Routing Reference No." <> RoutingLine."Routing Reference No.") or
           (Dispatch."Routing No." <> RoutingLine."Routing No.") or
           (Dispatch."Operation No." <> RoutingLine."Operation No.")
        then
            Error('İşlem anahtarı başka bir fason emri/operasyonu için kullanılmış. Ekranı yenileyip tekrar deneyin.');
        TransferNo := Dispatch."Transfer Order No.";
        PostedShipmentNo := Dispatch."Posted Transfer Shipment No.";
        if PostedShipmentNo = '' then
            PostedShipmentNo := FindPostedShipmentNo(TransferNo);
        if PostedShipmentNo = '' then
            Error('%1 transferinin önceki denemesi tamamlanmamış. BC transfer emrini kontrol edin; aynı işlemi yeniden oluşturmadık.', TransferNo);
        Dispatch.ModifyAll(Status, 'POSTED');
        Dispatch.ModifyAll("Posted Transfer Shipment No.", PostedShipmentNo);
        Dispatch.ModifyAll("Posted At", CurrentDateTime());
        exit(true);
    end;

    local procedure ReconcilePendingForComponent(Component: Record "Prod. Order Component")
    var
        Pending: Record "DOPSWHS Subcontract Dispatch";
        SameTransfer: Record "DOPSWHS Subcontract Dispatch";
        PostedShipmentNo: Code[20];
        TransferNo: Code[20];
        TransferNos: List of [Code[20]];
        IdempotencyKey: Guid;
        TargetLocation: Code[10];
        TargetBin: Code[20];
    begin
        Pending.SetRange("Prod. Order No.", Component."Prod. Order No.");
        Pending.SetRange("Prod. Order Line No.", Component."Prod. Order Line No.");
        Pending.SetRange("Component Line No.", Component."Line No.");
        Pending.SetRange(Status, 'PENDING');
        if Pending.FindSet() then
            repeat
                if not TransferNos.Contains(Pending."Transfer Order No.") then
                    TransferNos.Add(Pending."Transfer Order No.");
            until Pending.Next() = 0;
        foreach TransferNo in TransferNos do begin
            PostedShipmentNo := FindPostedShipmentNo(TransferNo);
            if PostedShipmentNo <> '' then begin
                SameTransfer.Reset();
                SameTransfer.SetRange("Transfer Order No.", TransferNo);
                if SameTransfer.FindFirst() then begin
                    IdempotencyKey := SameTransfer."Idempotency Key";
                    TargetLocation := SameTransfer."To Location Code";
                    TargetBin := SameTransfer."To Bin Code";
                    SameTransfer.ModifyAll(Status, 'POSTED');
                    SameTransfer.ModifyAll("Posted Transfer Shipment No.", PostedShipmentNo);
                    SameTransfer.ModifyAll("Posted At", CurrentDateTime());
                    UpdateDispatchedLps(IdempotencyKey, TargetLocation, TargetBin);
                end;
            end;
        end;
    end;

    local procedure FindPostedShipmentNo(TransferNo: Code[20]): Code[20]
    var
        PostedShipment: Record "Transfer Shipment Header";
    begin
        PostedShipment.SetRange("Transfer Order No.", TransferNo);
        if PostedShipment.FindLast() then
            exit(PostedShipment."No.");
    end;

    local procedure ValidateTrackingAndLp(Component: Record "Prod. Order Component"; Qty: Decimal; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; AlreadyRequestedQty: Decimal)
    var
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LpAvailable: Decimal;
    begin
        Item.Get(Component."Item No.");
        if (Item."Item Tracking Code" <> '') and TrackingCode.Get(Item."Item Tracking Code") then begin
            if (TrackingCode."Lot Specific Tracking" or TrackingCode."Lot Warehouse Tracking") and (LotNo = '') then
                Error('%1 ürünü için lot numarası zorunludur.', Component."Item No.");
            if (TrackingCode."SN Specific Tracking" or TrackingCode."SN Warehouse Tracking") and (SerialNo = '') then
                Error('%1 ürünü için seri numarası zorunludur.', Component."Item No.");
        end;
        if LpNo = '' then
            exit;
        LP.Get(LpNo);
        if LP."Location Code" <> Component."Location Code" then
            Error('%1 LP %2 lokasyonunda; bileşenin kaynak lokasyonu %3.', LpNo, LP."Location Code", Component."Location Code");
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", Component."Item No.");
        if LotNo <> '' then
            LPLine.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            LPLine.SetRange("Serial No.", SerialNo);
        LPLine.CalcSums(Quantity);
        LpAvailable := LPLine.Quantity;
        if Qty + AlreadyRequestedQty > LpAvailable then
            Error('%1 LP içinde %2 için kullanılabilir %3, toplam istenen %4.', LpNo, Component."Item No.", LpAvailable, Qty + AlreadyRequestedQty);
    end;

    local procedure UpdateDispatchedLps(IdempotencyKey: Guid; TargetLocation: Code[10]; TargetBin: Code[20])
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        SumDispatch: Record "DOPSWHS Subcontract Dispatch";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LpQty: Decimal;
        SentQty: Decimal;
        CurrentLpNo: Code[20];
        ProcessedLps: List of [Code[20]];
    begin
        Dispatch.SetRange("Idempotency Key", IdempotencyKey);
        Dispatch.SetFilter("LP No.", '<>%1', '');
        if Dispatch.FindSet() then
            repeat
                if (not Dispatch."LP Updated") and (not ProcessedLps.Contains(Dispatch."LP No.")) then begin
                    CurrentLpNo := Dispatch."LP No.";
                    ProcessedLps.Add(CurrentLpNo);
                    LPLine.Reset();
                    LPLine.SetRange("LP No.", CurrentLpNo);
                    LPLine.CalcSums(Quantity);
                    LpQty := LPLine.Quantity;
                    SumDispatch.SetRange("Idempotency Key", IdempotencyKey);
                    SumDispatch.SetRange("LP No.", CurrentLpNo);
                    SumDispatch.CalcSums(Quantity);
                    SentQty := SumDispatch.Quantity;
                    if LP.Get(CurrentLpNo) then
                        if SentQty = LpQty then begin
                            LP.Validate("Location Code", TargetLocation);
                            LP.Validate("Bin Code", TargetBin);
                            LP.Modify(true);
                        end else
                            ReduceLpLines(IdempotencyKey, CurrentLpNo);
                    SumDispatch.Reset();
                    SumDispatch.SetRange("Idempotency Key", IdempotencyKey);
                    SumDispatch.SetRange("LP No.", CurrentLpNo);
                    SumDispatch.ModifyAll("LP Updated", true);
                end;
            until Dispatch.Next() = 0;
    end;

    local procedure ReduceLpLines(IdempotencyKey: Guid; LpNo: Code[20])
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        LPLine: Record "DOPSWHS LP Line";
        QtyToRemove: Decimal;
    begin
        Dispatch.SetRange("Idempotency Key", IdempotencyKey);
        Dispatch.SetRange("LP No.", LpNo);
        if Dispatch.FindSet() then
            repeat
                QtyToRemove := Dispatch.Quantity;
                LPLine.Reset();
                LPLine.SetRange("LP No.", LpNo);
                LPLine.SetRange("Item No.", Dispatch."Item No.");
                if Dispatch."Lot No." <> '' then
                    LPLine.SetRange("Lot No.", Dispatch."Lot No.");
                if Dispatch."Serial No." <> '' then
                    LPLine.SetRange("Serial No.", Dispatch."Serial No.");
                if LPLine.FindSet(true) then
                    repeat
                        if QtyToRemove >= LPLine.Quantity then begin
                            QtyToRemove -= LPLine.Quantity;
                            LPLine.Delete(true);
                        end else begin
                            LPLine.Validate(Quantity, LPLine.Quantity - QtyToRemove);
                            LPLine.Modify(true);
                            QtyToRemove := 0;
                        end;
                    until (LPLine.Next() = 0) or (QtyToRemove = 0);
            until Dispatch.Next() = 0;
    end;

    local procedure EnsureComponentBelongsToOperation(RoutingLine: Record "Prod. Order Routing Line"; Component: Record "Prod. Order Component")
    begin
        if RoutingLine."Routing Link Code" <> '' then begin
            if Component."Routing Link Code" <> RoutingLine."Routing Link Code" then
                Error('%1 bileşeni %2 fason operasyonuna bağlı değil.', Component."Item No.", RoutingLine."Operation No.");
            exit;
        end;
        if Component."Routing Link Code" <> '' then
            Error('%1 bileşeninin rota bağlantısı bu fason operasyonla eşleşmiyor.', Component."Item No.");
        EnsureSingleUnlinkedSubcontractOperation(RoutingLine);
    end;

    local procedure ApplyRoutingLinkFilter(RoutingLine: Record "Prod. Order Routing Line"; var Component: Record "Prod. Order Component")
    begin
        if RoutingLine."Routing Link Code" <> '' then
            Component.SetRange("Routing Link Code", RoutingLine."Routing Link Code")
        else begin
            EnsureSingleUnlinkedSubcontractOperation(RoutingLine);
            Component.SetRange("Routing Link Code", '');
        end;
    end;

    local procedure EnsureSingleUnlinkedSubcontractOperation(RoutingLine: Record "Prod. Order Routing Line")
    var
        OtherRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: Record "Work Center";
        Count: Integer;
    begin
        OtherRoutingLine.SetRange(Status, RoutingLine.Status);
        OtherRoutingLine.SetRange("Prod. Order No.", RoutingLine."Prod. Order No.");
        OtherRoutingLine.SetRange("Routing Link Code", '');
        OtherRoutingLine.SetRange(Type, OtherRoutingLine.Type::"Work Center");
        if OtherRoutingLine.FindSet() then
            repeat
                if WorkCenter.Get(OtherRoutingLine."No.") and (WorkCenter."Subcontractor No." <> '') then
                    Count += 1;
            until OtherRoutingLine.Next() = 0;
        if Count > 1 then
            Error('%1 emrinde rota bağlantı kodu boş birden fazla fason operasyon var. Bileşen/operasyon bağlantısını BC''de tamamlayın.', RoutingLine."Prod. Order No.");
    end;

    local procedure TempQuantityForComponent(var TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary; ProdOrderLineNo: Integer; ComponentLineNo: Integer): Decimal
    begin
        TempDispatch.Reset();
        TempDispatch.SetRange("Prod. Order Line No.", ProdOrderLineNo);
        TempDispatch.SetRange("Component Line No.", ComponentLineNo);
        TempDispatch.CalcSums(Quantity);
        exit(TempDispatch.Quantity);
    end;

    local procedure TempQuantityForLpItem(var TempDispatch: Record "DOPSWHS Subcontract Dispatch" temporary; LpNo: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]): Decimal
    begin
        if LpNo = '' then
            exit(0);
        TempDispatch.Reset();
        TempDispatch.SetRange("LP No.", LpNo);
        TempDispatch.SetRange("Item No.", ItemNo);
        if LotNo <> '' then
            TempDispatch.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            TempDispatch.SetRange("Serial No.", SerialNo);
        TempDispatch.CalcSums(Quantity);
        exit(TempDispatch.Quantity);
    end;

    local procedure RequireInteger(Row: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
        Result: Integer;
    begin
        if not Row.Get(Name, Token) then
            Error('%1 alanı zorunludur.', Name);
        if not Evaluate(Result, Format(Token.AsValue())) then
            Error('%1 alanı geçerli bir tam sayı olmalıdır.', Name);
        exit(Result);
    end;

    local procedure RequireDecimal(Row: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
        Result: Decimal;
    begin
        if not Row.Get(Name, Token) then
            Error('%1 alanı zorunludur.', Name);
        if not Evaluate(Result, Format(Token.AsValue()), 9) then
            Error('%1 alanı geçerli bir miktar olmalıdır.', Name);
        exit(Result);
    end;

    local procedure OptionalText(Row: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if Row.Get(Name, Token) then
            if not Token.AsValue().IsNull() then
                exit(Token.AsValue().AsText());
    end;

    local procedure ResultJson(TransferNo: Code[20]; PostedShipmentNo: Code[20]; FasonReferenceNo: Code[50]): Text
    var
        Result: JsonObject;
        EDespatchOutbox: Record "DOPSWHS Subcontract EDesp Out";
        TextResult: Text;
    begin
        Result.Add('transferOrderNo', TransferNo);
        Result.Add('postedTransferShipmentNo', PostedShipmentNo);
        Result.Add('fasonReferenceNo', FasonReferenceNo);
        Result.Add('stockTransferred', true);
        EDespatchOutbox.SetRange("Posted Transfer Shipment No.", PostedShipmentNo);
        if EDespatchOutbox.FindFirst() then begin
            Result.Add('eDespatchStatus', EDespatchOutbox.Status);
            Result.Add('eDespatchDocumentNo', EDespatchOutbox."Provider Document No.");
        end else begin
            Result.Add('eDespatchStatus', 'NOT_QUEUED');
            Result.Add('eDespatchDocumentNo', '');
        end;
        Result.WriteTo(TextResult);
        exit(TextResult);
    end;
}
