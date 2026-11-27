codeunit 72458 "DOPSWHS Transfer Ship Mgmt"
{
    // Handheld transfer shipping with e-despatch: ship a released transfer order, or create a new transfer
    // from scanned lines and ship it. The e-despatch request is created inside the posting transaction
    // ("DOPSWHS EDesp Post Context") and its draft is built after the commit.
    Access = Public;
    Permissions =
        tabledata "DOPSWHS EDesp Request" = RIM,
        tabledata "DOPSWHS EDesp Request Line" = RIM;

    var
        IdempotencyRequiredErr: Label 'İşlem anahtarı boş olamaz. Ekranı yenileyip tekrar deneyin.';
        TransferNotFoundErr: Label 'Transfer emri %1 bulunamadı. Listeyi yenileyin.', Comment = '%1 = transfer order no.';
        RequiresWhseShipmentErr: Label 'REQUIRES_WHSE_SHIPMENT: %1 lokasyonu ambar sevkiyatı gerektiriyor. Transferi Sevkiyat > Ambar Sevkiyatı ekranından gönderin.', Comment = '%1 = location code';
        NothingToShipErr: Label '%1 transferinde sevk edilecek miktar yok.', Comment = '%1 = transfer order no.';
        LineNotFoundErr: Label '%1 transferinde %2 numaralı satır bulunamadı.', Comment = '%1 = transfer order no., %2 = line no.';
        QtyTooHighErr: Label '%1 satırında sevk miktarı %2, kalan %3 miktarını aşıyor.', Comment = '%1 = line no., %2 = quantity, %3 = outstanding';
        NoLinesErr: Label 'En az bir satır okutun.';
        SameLocationErr: Label 'Kaynak ve hedef lokasyon aynı olamaz (%1). Aynı lokasyondaki raflar arası sevk için Taşıma ekranını kullanın.', Comment = '%1 = location code';
        DirectTransferSetupErr: Label 'Terminalden doğrudan transfer için Inventory Setup / Direct Transfer Posting alanı Receipt and Shipment olmalıdır. Ya da WMS Setup''ta transit lokasyonu kullanın.';
        InTransitRequiredErr: Label 'WMS Setup''ta Handheld Transfer In-Transit Code alanını doldurun.';
        ShipmentNotFoundErr: Label '%1 transferi post edildi ancak kayıtlı transfer irsaliyesi bulunamadı.', Comment = '%1 = transfer order no.';
        InvalidJsonErr: Label 'Gönderilen satırlar geçerli JSON değil.';

    /// <summary>
    /// Ships a released transfer order from the handheld. LinesJson: [{lineNo, quantity, lotNo, serialNo}] sets
    /// Qty. to Ship (other lines get 0); empty keeps the quantities of the order. OverridesJson carries the
    /// e-despatch receiver, vehicle and driver chosen on the handheld.
    /// </summary>
    procedure ShipTransferOrder(TransferNo: Code[20]; LinesJson: Text; OverridesJson: Text; OperatorUserId: Code[50]; IdempotencyKey: Guid): Text
    var
        TransferHeader: Record "Transfer Header";
        Location: Record Location;
        Request: Record "DOPSWHS EDesp Request";
        TempRequest: Record "DOPSWHS EDesp Request" temporary;
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        PostContext: Codeunit "DOPSWHS EDesp Post Context";
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
        ReleaseTransfer: Codeunit "Release Transfer Document";
        PostedShipmentNo: Code[20];
    begin
        if IsNullGuid(IdempotencyKey) then
            Error(IdempotencyRequiredErr);
        if RequestMgt.FindByIdempotencyKey(IdempotencyKey, Request) then
            exit(ResultJson(Request."Transfer Order No.", Request."Source No.", Request));

        if not TransferHeader.Get(TransferNo) then
            Error(TransferNotFoundErr, TransferNo);
        if Location.Get(TransferHeader."Transfer-from Code") then
            if Location."Require Shipment" then
                Error(RequiresWhseShipmentErr, Location.Code);

        if TransferHeader.Status <> TransferHeader.Status::Released then
            ReleaseTransfer.Release(TransferHeader);
        TransferHeader.Get(TransferNo);
        if LinesJson <> '' then begin
            ReleaseTransfer.Reopen(TransferHeader);
            TransferHeader.Get(TransferNo);
            ApplyQtyToShip(TransferHeader, LinesJson);
            ReleaseTransfer.Release(TransferHeader);
            TransferHeader.Get(TransferNo);
        end;
        if not HasQtyToShip(TransferNo) then
            Error(NothingToShipErr, TransferNo);

        PrepareTempRequest(TempRequest, OverridesJson, TransferHeader."Transfer-from Code", TransferHeader."Transfer-to Code", OperatorUserId);
        RequestMgt.OnBeforePostTransferShipment(TransferHeader, TempRequest);
        TransferHeader.Modify(true);

        PostContext.SetContext(IdempotencyKey, OperatorUserId, OverridesJson, FirstTargetBin(TransferNo));
        ShipmentMgmt.PostTransferShip(TransferHeader);
        PostContext.ClearContext();

        PostedShipmentNo := FindPostedShipmentNo(TransferNo);
        if PostedShipmentNo = '' then
            Error(ShipmentNotFoundErr, TransferNo);
        exit(FinishShipment(TransferNo, PostedShipmentNo, IdempotencyKey));
    end;

    /// <summary>
    /// Creates a transfer from scanned lines and ships it. RequestJson: {fromLocationCode, toLocationCode, toBinCode,
    /// lines: [{itemNo, variantCode, quantity, unitOfMeasureCode, lotNo, serialNo, fromBinCode, lpNo}], plus the
    /// e-despatch overrides (receiverType, receiverNo, vehiclePlateNo, ...)}.
    /// </summary>
    procedure CreateAndShip(RequestJson: Text; OperatorUserId: Code[50]; IdempotencyKey: Guid): Text
    var
        Setup: Record "DOPSWHS Setup";
        TransferHeader: Record "Transfer Header";
        Request: Record "DOPSWHS EDesp Request";
        TempRequest: Record "DOPSWHS EDesp Request" temporary;
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        PostContext: Codeunit "DOPSWHS EDesp Post Context";
        ReleaseTransfer: Codeunit "Release Transfer Document";
        PostShipment: Codeunit "TransferOrder-Post Shipment";
        Body: JsonObject;
        Lines: JsonArray;
        FromLocationCode: Code[10];
        ToLocationCode: Code[10];
        ToBinCode: Code[20];
        TransferNo: Code[20];
        PostedShipmentNo: Code[20];
        OverridesJson: Text;
        UseInTransit: Boolean;
    begin
        if IsNullGuid(IdempotencyKey) then
            Error(IdempotencyRequiredErr);
        if RequestMgt.FindByIdempotencyKey(IdempotencyKey, Request) then
            exit(ResultJson(Request."Transfer Order No.", Request."Source No.", Request));

        if not Body.ReadFrom(RequestJson) then
            Error(InvalidJsonErr);
        FromLocationCode := CopyStr(JsonText(Body, 'fromLocationCode'), 1, MaxStrLen(FromLocationCode));
        ToLocationCode := CopyStr(JsonText(Body, 'toLocationCode'), 1, MaxStrLen(ToLocationCode));
        ToBinCode := CopyStr(JsonText(Body, 'toBinCode'), 1, MaxStrLen(ToBinCode));
        if FromLocationCode = ToLocationCode then
            Error(SameLocationErr, FromLocationCode);
        Lines := JsonArrayValue(Body, 'lines');
        if Lines.Count() = 0 then
            Error(NoLinesErr);

        if Setup.Get('') then
            UseInTransit := Setup."Transfer Ship Use In-Transit";
        if UseInTransit then begin
            if Setup."Transfer In-Transit Code" = '' then
                Error(InTransitRequiredErr);
        end else
            EnsureDirectTransferSetup();

        TransferHeader.Init();
        TransferHeader.Insert(true);
        TransferHeader.Validate("Transfer-from Code", FromLocationCode);
        TransferHeader.Validate("Transfer-to Code", ToLocationCode);
        if UseInTransit then
            TransferHeader.Validate("In-Transit Code", Setup."Transfer In-Transit Code")
        else
            TransferHeader.Validate("Direct Transfer", true);
        TransferHeader.Validate("Posting Date", WorkDate());
        TransferHeader.Validate("Shipment Date", WorkDate());
        TransferHeader.Validate("Receipt Date", WorkDate());
        TransferHeader.Modify(true);
        TransferNo := TransferHeader."No.";
        CreateLines(TransferHeader, Lines, ToBinCode);

        OverridesJson := RequestJson;
        PrepareTempRequest(TempRequest, OverridesJson, FromLocationCode, ToLocationCode, OperatorUserId);
        TempRequest."To Bin Code" := ToBinCode;
        TransferHeader.Get(TransferNo);
        RequestMgt.OnBeforePostTransferShipment(TransferHeader, TempRequest);
        TransferHeader.Modify(true);

        ReleaseTransfer.Release(TransferHeader);
        TransferHeader.Get(TransferNo);
        PostContext.SetContext(IdempotencyKey, OperatorUserId, OverridesJson, ToBinCode);
        PostShipment.Run(TransferHeader);
        PostContext.ClearContext();

        PostedShipmentNo := FindPostedShipmentNo(TransferNo);
        if PostedShipmentNo = '' then
            Error(ShipmentNotFoundErr, TransferNo);
        exit(FinishShipment(TransferNo, PostedShipmentNo, IdempotencyKey));
    end;

    /// <summary>
    /// Returns the receiver a provider proposes for goods going to a location and bin, for the handheld card.
    /// </summary>
    procedure ResolveReceiver(FromLocationCode: Code[10]; FromBinCode: Code[20]; ToLocationCode: Code[10]; ToBinCode: Code[20]): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Result: JsonObject;
        ResultText: Text;
        Handled: Boolean;
    begin
        RequestMgt.OnResolveEDespatchReceiver(FromLocationCode, FromBinCode, ToLocationCode, ToBinCode, Result, Handled);
        if not Handled then begin
            Result.Add('providerConnected', false);
            Result.Add('eDespatchRequired', false);
        end;
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    /// <summary>
    /// Lists vendors or customers (and their order / ship-to addresses) for the receiver lookup of the handheld.
    /// </summary>
    procedure ListReceivers(ReceiverType: Text; SearchText: Text; MaxCount: Integer): Text
    var
        Vendor: Record Vendor;
        Customer: Record Customer;
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Rows: JsonArray;
        ResultText: Text;
        FilterText: Text;
    begin
        if MaxCount <= 0 then
            MaxCount := 50;
        FilterText := '@*' + DelChr(SearchText, '=', '*@&|()''') + '*';
        case RequestMgt.ParseReceiverType(ReceiverType) of
            "DOPSWHS EDesp Receiver Type"::Vendor:
                begin
                    Vendor.SetRange(Blocked, Vendor.Blocked::" ");
                    if SearchText <> '' then begin
                        Vendor.FilterGroup(-1);
                        Vendor.SetFilter("No.", FilterText);
                        Vendor.SetFilter(Name, FilterText);
                        Vendor.SetFilter("VAT Registration No.", FilterText);
                        Vendor.FilterGroup(0);
                    end;
                    if Vendor.FindSet() then
                        repeat
                            Rows.Add(ReceiverRow('vendor', Vendor."No.", Vendor.Name, Vendor."VAT Registration No.", Vendor.City, VendorAddresses(Vendor."No.")));
                        until (Vendor.Next() = 0) or (Rows.Count() >= MaxCount);
                end;
            "DOPSWHS EDesp Receiver Type"::Customer:
                begin
                    Customer.SetRange(Blocked, Customer.Blocked::" ");
                    if SearchText <> '' then begin
                        Customer.FilterGroup(-1);
                        Customer.SetFilter("No.", FilterText);
                        Customer.SetFilter(Name, FilterText);
                        Customer.SetFilter("VAT Registration No.", FilterText);
                        Customer.FilterGroup(0);
                    end;
                    if Customer.FindSet() then
                        repeat
                            Rows.Add(ReceiverRow('customer', Customer."No.", Customer.Name, Customer."VAT Registration No.", Customer.City, CustomerAddresses(Customer."No.")));
                        until (Customer.Next() = 0) or (Rows.Count() >= MaxCount);
                end;
        end;
        Rows.WriteTo(ResultText);
        exit(ResultText);
    end;

    local procedure FinishShipment(TransferNo: Code[20]; PostedShipmentNo: Code[20]; IdempotencyKey: Guid): Text
    var
        Request: Record "DOPSWHS EDesp Request";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Commit();
        if RequestMgt.FindByIdempotencyKey(IdempotencyKey, Request) then
            RequestMgt.EnsureDraft(Request)
        else
            Clear(Request);
        exit(ResultJson(TransferNo, PostedShipmentNo, Request));
    end;

    local procedure ResultJson(TransferNo: Code[20]; PostedShipmentNo: Code[20]; Request: Record "DOPSWHS EDesp Request"): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Result: JsonObject;
        ResultText: Text;
    begin
        if (PostedShipmentNo = '') and (Request."Source No." <> '') then
            PostedShipmentNo := Request."Source No.";
        Result.Add('transferOrderNo', TransferNo);
        Result.Add('postedShipmentNo', PostedShipmentNo);
        if Request."Entry No." <> 0 then begin
            Result.Add('eDespatchRequired', Request.Status <> Request.Status::NotRequired);
            Result.Add('eDespatch', RequestMgt.ToJsonObject(Request));
        end else
            Result.Add('eDespatchRequired', false);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    local procedure PrepareTempRequest(var TempRequest: Record "DOPSWHS EDesp Request" temporary; OverridesJson: Text; FromLocationCode: Code[10]; ToLocationCode: Code[10]; OperatorUserId: Code[50])
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        TempRequest.Init();
        TempRequest."Location Code" := FromLocationCode;
        TempRequest."To Location Code" := ToLocationCode;
        TempRequest."Operator User Id" := OperatorUserId;
        if OverridesJson <> '' then
            RequestMgt.ApplyChangesText(TempRequest, OverridesJson);
    end;

    local procedure ApplyQtyToShip(TransferHeader: Record "Transfer Header"; LinesJson: Text)
    var
        TransferLine: Record "Transfer Line";
        Rows: JsonArray;
        RowToken: JsonToken;
        Row: JsonObject;
        LineNo: Integer;
        Qty: Decimal;
        LotNo: Code[50];
        SerialNo: Code[50];
    begin
        if not Rows.ReadFrom(LinesJson) then
            Error(InvalidJsonErr);
        TransferLine.SetRange("Document No.", TransferHeader."No.");
        TransferLine.SetRange("Derived From Line No.", 0);
        if TransferLine.FindSet(true) then
            repeat
                if TransferLine."Qty. to Ship" <> 0 then begin
                    TransferLine.Validate("Qty. to Ship", 0);
                    TransferLine.Modify(true);
                end;
            until TransferLine.Next() = 0;

        foreach RowToken in Rows do begin
            Row := RowToken.AsObject();
            LineNo := JsonInteger(Row, 'lineNo');
            Qty := JsonDecimal(Row, 'quantity');
            LotNo := CopyStr(JsonText(Row, 'lotNo'), 1, MaxStrLen(LotNo));
            SerialNo := CopyStr(JsonText(Row, 'serialNo'), 1, MaxStrLen(SerialNo));
            if not TransferLine.Get(TransferHeader."No.", LineNo) then
                Error(LineNotFoundErr, TransferHeader."No.", LineNo);
            if Qty > TransferLine."Outstanding Quantity" then
                Error(QtyTooHighErr, LineNo, Qty, TransferLine."Outstanding Quantity");
            TransferLine.Validate("Qty. to Ship", TransferLine."Qty. to Ship" + Qty);
            TransferLine.Modify(true);
            if (LotNo <> '') or (SerialNo <> '') then
                AddItemTracking(TransferLine, LotNo, SerialNo, Qty);
        end;
    end;

    local procedure HasQtyToShip(TransferNo: Code[20]): Boolean
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.SetRange("Document No.", TransferNo);
        TransferLine.SetRange("Derived From Line No.", 0);
        TransferLine.SetFilter("Qty. to Ship", '<>%1', 0);
        exit(not TransferLine.IsEmpty());
    end;

    local procedure FirstTargetBin(TransferNo: Code[20]): Code[20]
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.SetRange("Document No.", TransferNo);
        TransferLine.SetRange("Derived From Line No.", 0);
        TransferLine.SetFilter("Transfer-To Bin Code", '<>%1', '');
        if TransferLine.FindFirst() then
            exit(TransferLine."Transfer-To Bin Code");
        exit('');
    end;

    local procedure CreateLines(TransferHeader: Record "Transfer Header"; Lines: JsonArray; ToBinCode: Code[20])
    var
        TransferLine: Record "Transfer Line";
        RowToken: JsonToken;
        Row: JsonObject;
        LineNo: Integer;
        Qty: Decimal;
        UnitOfMeasureCode: Code[10];
        VariantCode: Code[10];
        FromBinCode: Code[20];
        LotNo: Code[50];
        SerialNo: Code[50];
    begin
        foreach RowToken in Lines do begin
            Row := RowToken.AsObject();
            Qty := JsonDecimal(Row, 'quantity');
            if Qty > 0 then begin
                LineNo += 10000;
                TransferLine.Init();
                TransferLine."Document No." := TransferHeader."No.";
                TransferLine."Line No." := LineNo;
                TransferLine.Insert(true);
                TransferLine.Validate("Item No.", CopyStr(JsonText(Row, 'itemNo'), 1, MaxStrLen(TransferLine."Item No.")));
                VariantCode := CopyStr(JsonText(Row, 'variantCode'), 1, MaxStrLen(VariantCode));
                if VariantCode <> '' then
                    TransferLine.Validate("Variant Code", VariantCode);
                UnitOfMeasureCode := CopyStr(JsonText(Row, 'unitOfMeasureCode'), 1, MaxStrLen(UnitOfMeasureCode));
                if UnitOfMeasureCode <> '' then
                    TransferLine.Validate("Unit of Measure Code", UnitOfMeasureCode);
                TransferLine.Validate(Quantity, Qty);
                FromBinCode := CopyStr(JsonText(Row, 'fromBinCode'), 1, MaxStrLen(FromBinCode));
                if FromBinCode <> '' then
                    TransferLine.Validate("Transfer-from Bin Code", FromBinCode);
                if ToBinCode <> '' then
                    TransferLine.Validate("Transfer-To Bin Code", ToBinCode);
                TransferLine.Modify(true);
                LotNo := CopyStr(JsonText(Row, 'lotNo'), 1, MaxStrLen(LotNo));
                SerialNo := CopyStr(JsonText(Row, 'serialNo'), 1, MaxStrLen(SerialNo));
                if (LotNo <> '') or (SerialNo <> '') then
                    AddItemTracking(TransferLine, LotNo, SerialNo, Qty);
            end;
        end;
        if LineNo = 0 then
            Error(NoLinesErr);
    end;

    local procedure AddItemTracking(TransferLine: Record "Transfer Line"; LotNo: Code[50]; SerialNo: Code[50]; Qty: Decimal)
    var
        Item: Record Item;
        TempReservation: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
        QtyBase: Decimal;
    begin
        // Same outbound Surplus entry as Transfer Item Tracking Lines (see DOPSWHS Subcontract Mgmt).
        Item.Get(TransferLine."Item No.");
        if Item."Item Tracking Code" = '' then
            exit;
        QtyBase := Round(Qty * TransferLine."Qty. per Unit of Measure", 0.00001);
        TempReservation."Lot No." := LotNo;
        TempReservation."Serial No." := SerialNo;
        CreateReservEntry.SetQtyToHandleAndInvoice(-QtyBase, -QtyBase);
        CreateReservEntry.CreateReservEntryFor(
            Database::"Transfer Line", Enum::"Transfer Direction"::Outbound.AsInteger(),
            TransferLine."Document No.", '', TransferLine."Derived From Line No.", TransferLine."Line No.",
            TransferLine."Qty. per Unit of Measure", 0, -QtyBase, TempReservation);
        CreateReservEntry.CreateEntry(
            TransferLine."Item No.", TransferLine."Variant Code", TransferLine."Transfer-from Code",
            TransferLine.Description, TransferLine."Receipt Date", TransferLine."Shipment Date", 0,
            Enum::"Reservation Status"::Surplus);
    end;

    local procedure EnsureDirectTransferSetup()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        if InventorySetup."Direct Transfer Posting" <> InventorySetup."Direct Transfer Posting"::"Receipt and Shipment" then
            Error(DirectTransferSetupErr);
    end;

    local procedure FindPostedShipmentNo(TransferNo: Code[20]): Code[20]
    var
        TransferShipmentHeader: Record "Transfer Shipment Header";
    begin
        TransferShipmentHeader.SetRange("Transfer Order No.", TransferNo);
        if TransferShipmentHeader.FindLast() then
            exit(TransferShipmentHeader."No.");
        exit('');
    end;

    local procedure ReceiverRow(Kind: Text; No: Code[20]; Name: Text; VatRegistrationNo: Text; City: Text; Addresses: JsonArray) Row: JsonObject
    begin
        Row.Add('type', Kind);
        Row.Add('no', No);
        Row.Add('name', Name);
        Row.Add('vatRegistrationNo', VatRegistrationNo);
        Row.Add('city', City);
        Row.Add('addresses', Addresses);
    end;

    local procedure VendorAddresses(VendorNo: Code[20]) Addresses: JsonArray
    var
        OrderAddress: Record "Order Address";
        Row: JsonObject;
    begin
        OrderAddress.SetRange("Vendor No.", VendorNo);
        if OrderAddress.FindSet() then
            repeat
                Clear(Row);
                Row.Add('code', OrderAddress.Code);
                Row.Add('name', OrderAddress.Name);
                Row.Add('address', OrderAddress.Address);
                Row.Add('city', OrderAddress.City);
                Addresses.Add(Row);
            until OrderAddress.Next() = 0;
    end;

    local procedure CustomerAddresses(CustomerNo: Code[20]) Addresses: JsonArray
    var
        ShipToAddress: Record "Ship-to Address";
        Row: JsonObject;
    begin
        ShipToAddress.SetRange("Customer No.", CustomerNo);
        if ShipToAddress.FindSet() then
            repeat
                Clear(Row);
                Row.Add('code', ShipToAddress.Code);
                Row.Add('name', ShipToAddress.Name);
                Row.Add('address', ShipToAddress.Address);
                Row.Add('city', ShipToAddress.City);
                Addresses.Add(Row);
            until ShipToAddress.Next() = 0;
    end;

    local procedure JsonText(Source: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure JsonDecimal(Source: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure JsonInteger(Source: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure JsonArrayValue(Source: JsonObject; Name: Text): JsonArray
    var
        Token: JsonToken;
        EmptyArray: JsonArray;
    begin
        if not Source.Get(Name, Token) then
            exit(EmptyArray);
        if not Token.IsArray() then
            exit(EmptyArray);
        exit(Token.AsArray());
    end;
}
