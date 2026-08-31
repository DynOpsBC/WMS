codeunit 72290 "DOPSWHS Purch Source Mgmt"
{
    // Purchase Order doğrudan mal kabul (Warehouse Receipt zorunlu değil).
    // Yönetilmeyen lokasyonlarda (Require Receive = false) operatör mobil ekrandan
    // qtyToReceive set edip Post-Receive tetikleyebilir.
    Access = Public;

    procedure SetLineQtyToReceive(OrderNo: Code[20]; LineNo: Integer; QtyToReceive: Decimal; BinCode: Code[20])
    var
        PH: Record "Purchase Header";
        PL: Record "Purchase Line";
    begin
        if not PH.Get(PH."Document Type"::Order, OrderNo) then
            Error('Purchase order %1 not found.', OrderNo);
        EnsureDirectReceiveAllowed(PH);

        if not PL.Get(PL."Document Type"::Order, OrderNo, LineNo) then
            Error('Purchase line %1 / %2 not found.', OrderNo, LineNo);
        if BinCode <> '' then
            PL.Validate("Bin Code", BinCode);
        PL.Validate("Qty. to Receive", QtyToReceive);
        PL.Modify(true);

        Session.LogMessage('AdvWMS.PurchSource.SetQty',
            StrSubstNo('PO %1 line %2 qtyToReceive=%3', OrderNo, LineNo, QtyToReceive),
            Verbosity::Normal, DataClassification::SystemMetadata,
            TelemetryScope::ExtensionPublisher, EmptyDims());
    end;

    /// <summary>
    /// Satın alma siparişinden ambar mal kabul belgesi oluşturur (BC "Kaynak
    /// Belgeleri Al" ile aynı mekanizma). NEDEN: "Require Receive" lokasyonda
    /// terminal doğrudan kabul yapamaz; ofis belgeyi BC'de açmadıysa operatör
    /// bekliyordu. Aynı sipariş için açık bir belge varsa yenisi üretilmez,
    /// mevcut numara döner.
    /// </summary>
    procedure CreateWhseReceipt(OrderNo: Code[20]): Code[20]
    var
        PH: Record "Purchase Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        GetSourceDocInbound: Codeunit "Get Source Doc. Inbound";
        ReleasePurchDoc: Codeunit "Release Purchase Document";
    begin
        if not PH.Get(PH."Document Type"::Order, OrderNo) then
            Error(OrderNotFoundErr, OrderNo);
        WhseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WhseReceiptLine.SetRange("Source Subtype", PH."Document Type".AsInteger());
        WhseReceiptLine.SetRange("Source No.", OrderNo);
        if WhseReceiptLine.FindFirst() then
            exit(WhseReceiptLine."No.");
        if PH.Status <> PH.Status::Released then
            ReleasePurchDoc.PerformManualRelease(PH);
        GetSourceDocInbound.CreateFromPurchOrderHideDialog(PH);
        WhseReceiptLine.Reset();
        WhseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WhseReceiptLine.SetRange("Source Subtype", PH."Document Type".AsInteger());
        WhseReceiptLine.SetRange("Source No.", OrderNo);
        if not WhseReceiptLine.FindFirst() then
            Error(WhseReceiptNotCreatedErr, OrderNo);
        exit(WhseReceiptLine."No.");
    end;

    procedure ReceiveOrder(OrderNo: Code[20]; AlsoInvoice: Boolean): Code[20]
    var
        PH: Record "Purchase Header";
        PurchPost: Codeunit "Purch.-Post";
    begin
        PH.LockTable();
        if not PH.Get(PH."Document Type"::Order, OrderNo) then
            Error('Purchase order %1 not found.', OrderNo);
        EnsureDirectReceiveAllowed(PH);
        if PH.Status <> PH.Status::Released then
            PH.Validate(Status, PH.Status::Released);

        PH.Receive := true;
        PH.Invoice := AlsoInvoice;
        PH.Modify(true);

        Session.LogMessage('AdvWMS.PurchSource.PostStart',
            StrSubstNo('PO %1 Receive=%2 Invoice=%3', OrderNo, PH.Receive, PH.Invoice),
            Verbosity::Normal, DataClassification::SystemMetadata,
            TelemetryScope::ExtensionPublisher, EmptyDims());

        PurchPost.Run(PH);

        Session.LogMessage('AdvWMS.PurchSource.PostDone',
            StrSubstNo('PO %1 posted (Receive%2, Invoice=%3)', OrderNo, ' = true', AlsoInvoice),
            Verbosity::Normal, DataClassification::SystemMetadata,
            TelemetryScope::ExtensionPublisher, EmptyDims());

        exit(OrderNo);
    end;

    local procedure EnsureDirectReceiveAllowed(PurchaseHeader: Record "Purchase Header")
    var
        PurchaseLine: Record "Purchase Line";
        Location: Record Location;
    begin
        if PurchaseHeader."Location Code" <> '' then begin
            if not Location.Get(PurchaseHeader."Location Code") then
                Error(LocationMissingErr, PurchaseHeader."Location Code");
            if Location."Require Receive" then
                Error(RequiresWhseReceiptErr, PurchaseHeader."No.", PurchaseHeader."Location Code");
        end;
        // Başlık lokasyonu boş olsa da satırlar lokasyon taşıyabilir (karışık
        // sipariş): satır lokasyonu ambar kabul istiyorsa doğrudan kayıt BC'de
        // "Location Code must be equal to ''" ile düşer; boş satır lokasyonu
        // ise Item Journal'da "Location Code must have a value" üretir.
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        PurchaseLine.SetFilter("Outstanding Quantity", '>0');
        if PurchaseLine.FindSet() then
            repeat
                if PurchaseLine."Location Code" = '' then
                    Error(LineLocationMissingErr, PurchaseHeader."No.", PurchaseLine."Line No.");
                if PurchaseLine."Location Code" <> PurchaseHeader."Location Code" then
                    Error(MixedLocationErr, PurchaseHeader."No.", PurchaseLine."Line No.", PurchaseLine."Location Code", PurchaseHeader."Location Code");
                if Location.Get(PurchaseLine."Location Code") and Location."Require Receive" then
                    Error(RequiresWhseReceiptErr, PurchaseHeader."No.", PurchaseLine."Location Code");
            until PurchaseLine.Next() = 0;
    end;

    local procedure EmptyDims(): Dictionary of [Text, Text]
    var
        D: Dictionary of [Text, Text];
    begin
        exit(D);
    end;

    var
        OrderNotFoundErr: Label '%1 satın alma siparişi bulunamadı.', Comment = '%1 order no';
        LocationMissingErr: Label '%1 lokasyonu bulunamadı.', Comment = '%1 location';
        RequiresWhseReceiptErr: Label '%1 siparişinin lokasyonu (%2) ambar mal kabul belgesi gerektirir. "Ambar Kabulü Oluştur" ile belgeyi açıp Ambar Mal Kabul ekranından kaydedin.', Comment = '%1 order, %2 location';
        LineLocationMissingErr: Label '%1 siparişinin %2 no.lu satırında lokasyon boş; doğrudan kabul yapılamaz. BC''de satır lokasyonunu doldurun.', Comment = '%1 order, %2 line no';
        MixedLocationErr: Label '%1 siparişinde %2 no.lu satırın lokasyonu (%3) başlık lokasyonundan (%4) farklı; doğrudan kabul BC tarafından reddedilir. BC''de sipariş lokasyonunu eşitleyin.', Comment = '%1 order, %2 line, %3 line location, %4 header location';
        WhseReceiptNotCreatedErr: Label '%1 siparişi için ambar mal kabul belgesi oluşturulamadı. Sipariş satırlarında bu lokasyon için alınacak miktar kalmamış olabilir.', Comment = '%1 order no';
}
