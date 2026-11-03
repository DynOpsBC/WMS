/// <summary>
/// Fason teslim alındığında, bu fason operasyonuna transferle gönderilmiş
/// bileşenleri fason lokasyonundan, sevkteki lot/seri ile tüketir.
/// Parsiyel teslimde alınan miktar oranında; operasyon kapatılırken sevk
/// edilip henüz tüketilmemiş miktarın tamamı tüketilir. Bileşen satırının
/// kalan miktarı üst sınırdır (BC'de elle yapılmış sarfiyat iki kez düşülmez).
/// Sevk kayıtlarındaki "Consumed Quantity" tekrar düşmeyi önler.
/// </summary>
codeunit 72475 "DOPSWHS Subcont Consumption"
{
    Access = Internal;
    Permissions =
        tabledata "DOPSWHS Subcontract Dispatch" = RM,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RMD,
        tabledata "Item Ledger Entry" = R;

    procedure PostForReceipt(var Audit: Record "DOPSWHS Subcontract Receipt")
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        Component: Record "Prod. Order Component";
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
        ComponentLines: List of [Integer];
        TakenFromEntry: Dictionary of [Integer, Decimal];
        LpDebits: List of [Integer];
        LpDebitQty: Dictionary of [Integer, Decimal];
        ComponentLineNo: Integer;
        DispatchEntryNo: Integer;
        Ratio: Decimal;
        Need: Decimal;
        Consumed: Decimal;
        LinesAdded: Boolean;
    begin
        // Yolda kalmış fason transferi varsa (ör. sevk BC'den kaydedildi) önce girişi kaydet.
        PostPendingTransferReceipts(Audit);
        ReconcilePendingDispatches(Audit);
        FilterOperationDispatches(Audit, Dispatch);
        if Dispatch.FindSet() then
            repeat
                if (Dispatch.Quantity - Dispatch."Consumed Quantity" > 0) and
                   (not ComponentLines.Contains(Dispatch."Component Line No."))
                then
                    ComponentLines.Add(Dispatch."Component Line No.");
            until Dispatch.Next() = 0;
        if ComponentLines.Count() = 0 then begin
            Audit."Consumption Status" := 'NONE';
            exit;
        end;

        Ratio := ReceivedRatio(Audit);
        foreach ComponentLineNo in ComponentLines do begin
            Component.Get(
                Component.Status::Released, Audit."Prod. Order No.",
                ComponentProdOrderLineNo(Audit, ComponentLineNo), ComponentLineNo);
            if Audit."Operation Finished" then
                Need := UnconsumedQuantity(Audit, ComponentLineNo)
            else
                Need := Round(Component."Expected Quantity" * Ratio, 0.00001);
            if Need > UnconsumedQuantity(Audit, ComponentLineNo) then
                Need := UnconsumedQuantity(Audit, ComponentLineNo);
            if Need > Component."Remaining Quantity" then
                Need := Component."Remaining Quantity";
            if Need > 0 then begin
                Consumed := AddConsumptionFromFasonStock(Audit, Component, Need, TakenFromEntry, ProdMgmt);
                if Consumed > 0 then
                    LinesAdded := true;
                DistributeOverDispatches(Audit, Component, Consumed, LpDebits, LpDebitQty);
            end;
        end;

        if LinesAdded then
            ProdMgmt.PostSubcontractConsumption();
        foreach DispatchEntryNo in LpDebits do
            DebitDispatchedLp(Audit, DispatchEntryNo, LpDebitQty.Get(DispatchEntryNo));
        Audit."Consumption Status" := 'POSTED';
    end;

    /// Fason lokasyonundaki açık transfer girişlerinden (bu operasyonun sevkleri)
    /// FIFO ile tüketim satırı ekler. Lot/seri ve uygulanacak giriş kayıttan alınır;
    /// depo toplamasıyla seçilen lot da böylece doğru düşülür.
    local procedure AddConsumptionFromFasonStock(Audit: Record "DOPSWHS Subcontract Receipt"; Component: Record "Prod. Order Component"; Need: Decimal; var TakenFromEntry: Dictionary of [Integer, Decimal]; var ProdMgmt: Codeunit "DOPSWHS Prod Mgmt") Consumed: Decimal
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        ItemLedgerEntry: Record "Item Ledger Entry";
        TransferFilter: Text;
        ToLocation: Code[10];
        ToBin: Code[20];
        QtyPerUoM: Decimal;
        NeedBase: Decimal;
        AvailableBase: Decimal;
        TakeBase: Decimal;
        Taken: Decimal;
    begin
        FilterOperationDispatches(Audit, Dispatch);
        Dispatch.SetRange("Component Line No.", Component."Line No.");
        if Dispatch.FindSet() then
            repeat
                if StrPos('|' + TransferFilter + '|', '|' + Dispatch."Transfer Order No." + '|') = 0 then begin
                    if TransferFilter <> '' then
                        TransferFilter += '|';
                    TransferFilter += Dispatch."Transfer Order No.";
                end;
                ToLocation := Dispatch."To Location Code";
                ToBin := Dispatch."To Bin Code";
            until Dispatch.Next() = 0;
        if TransferFilter = '' then
            exit(0);

        QtyPerUoM := Component."Qty. per Unit of Measure";
        if QtyPerUoM = 0 then
            QtyPerUoM := 1;
        NeedBase := Round(Need * QtyPerUoM, 0.00001);
        ItemLedgerEntry.SetCurrentKey("Entry No.");
        ItemLedgerEntry.SetRange("Item No.", Component."Item No.");
        ItemLedgerEntry.SetRange("Variant Code", Component."Variant Code");
        ItemLedgerEntry.SetRange("Location Code", ToLocation);
        ItemLedgerEntry.SetRange(Open, true);
        ItemLedgerEntry.SetRange(Positive, true);
        ItemLedgerEntry.SetRange("Order Type", ItemLedgerEntry."Order Type"::Transfer);
        ItemLedgerEntry.SetFilter("Order No.", TransferFilter);
        if ItemLedgerEntry.FindSet() then
            repeat
                Taken := 0;
                if TakenFromEntry.ContainsKey(ItemLedgerEntry."Entry No.") then
                    Taken := TakenFromEntry.Get(ItemLedgerEntry."Entry No.");
                AvailableBase := ItemLedgerEntry."Remaining Quantity" - Taken;
                TakeBase := NeedBase;
                if TakeBase > AvailableBase then
                    TakeBase := AvailableBase;
                if TakeBase > 0 then begin
                    ProdMgmt.AddSubcontractConsumptionLine(
                        Component, Round(TakeBase / QtyPerUoM, 0.00001), ToLocation, ToBin,
                        ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.",
                        Audit."Posted Purchase Receipt No.", ItemLedgerEntry."Entry No.");
                    TakenFromEntry.Set(ItemLedgerEntry."Entry No.", Taken + TakeBase);
                    NeedBase -= TakeBase;
                    Consumed += Round(TakeBase / QtyPerUoM, 0.00001);
                end;
            until (ItemLedgerEntry.Next() = 0) or (NeedBase <= 0);
    end;

    /// Tüketilen miktarı sevk kayıtlarına FIFO dağıtır (tekrar düşmeyi önler) ve
    /// fason lokasyonuna bütün olarak taşınmış LP'leri düşülecekler listesine ekler.
    local procedure DistributeOverDispatches(Audit: Record "DOPSWHS Subcontract Receipt"; Component: Record "Prod. Order Component"; Consumed: Decimal; var LpDebits: List of [Integer]; var LpDebitQty: Dictionary of [Integer, Decimal])
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        Portion: Decimal;
    begin
        if Consumed <= 0 then
            exit;
        FilterOperationDispatches(Audit, Dispatch);
        Dispatch.SetRange("Component Line No.", Component."Line No.");
        if Dispatch.FindSet(true) then
            repeat
                Portion := Dispatch.Quantity - Dispatch."Consumed Quantity";
                if Portion > Consumed then
                    Portion := Consumed;
                if Portion > 0 then begin
                    Dispatch."Consumed Quantity" += Portion;
                    Dispatch.Modify();
                    Consumed -= Portion;
                    if Dispatch."LP No." <> '' then begin
                        LpDebits.Add(Dispatch."Entry No.");
                        LpDebitQty.Add(Dispatch."Entry No.", Portion * Component."Qty. per Unit of Measure");
                    end;
                end;
            until (Dispatch.Next() = 0) or (Consumed <= 0);
    end;

    local procedure PostPendingTransferReceipts(Audit: Record "DOPSWHS Subcontract Receipt")
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        SubcontractMgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Done: List of [Code[20]];
    begin
        Dispatch.SetRange("Prod. Order No.", Audit."Prod. Order No.");
        Dispatch.SetRange("Routing Reference No.", Audit."Routing Reference No.");
        Dispatch.SetRange("Routing No.", Audit."Routing No.");
        Dispatch.SetRange("Operation No.", Audit."Operation No.");
        Dispatch.SetFilter(Status, '%1|%2', 'PENDING', 'POSTED');
        if Dispatch.FindSet() then
            repeat
                if not Done.Contains(Dispatch."Transfer Order No.") then begin
                    Done.Add(Dispatch."Transfer Order No.");
                    SubcontractMgmt.PostPendingFasonTransferReceipt(Dispatch."Transfer Order No.");
                end;
            until Dispatch.Next() = 0;
    end;

    /// Depo sevkiyatıyla gönderilen talepler sevk kaydı görülünce POSTED olur.
    local procedure ReconcilePendingDispatches(Audit: Record "DOPSWHS Subcontract Receipt")
    var
        Pending: Record "DOPSWHS Subcontract Dispatch";
        Component: Record "Prod. Order Component";
        SubcontractMgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Done: List of [Integer];
    begin
        Pending.SetRange("Prod. Order No.", Audit."Prod. Order No.");
        Pending.SetRange("Routing Reference No.", Audit."Routing Reference No.");
        Pending.SetRange("Routing No.", Audit."Routing No.");
        Pending.SetRange("Operation No.", Audit."Operation No.");
        Pending.SetRange(Status, 'PENDING');
        if Pending.FindSet() then
            repeat
                if not Done.Contains(Pending."Component Line No.") then begin
                    Done.Add(Pending."Component Line No.");
                    if Component.Get(Component.Status::Released, Pending."Prod. Order No.", Pending."Prod. Order Line No.", Pending."Component Line No.") then
                        SubcontractMgmt.GetDispatchedQuantity(Component);
                end;
            until Pending.Next() = 0;
    end;

    local procedure FilterOperationDispatches(Audit: Record "DOPSWHS Subcontract Receipt"; var Dispatch: Record "DOPSWHS Subcontract Dispatch")
    begin
        Dispatch.Reset();
        Dispatch.SetCurrentKey("Entry No.");
        Dispatch.SetRange("Prod. Order No.", Audit."Prod. Order No.");
        Dispatch.SetRange("Routing Reference No.", Audit."Routing Reference No.");
        Dispatch.SetRange("Routing No.", Audit."Routing No.");
        Dispatch.SetRange("Operation No.", Audit."Operation No.");
        Dispatch.SetRange(Status, 'POSTED');
    end;

    local procedure ComponentProdOrderLineNo(Audit: Record "DOPSWHS Subcontract Receipt"; ComponentLineNo: Integer): Integer
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        FilterOperationDispatches(Audit, Dispatch);
        Dispatch.SetRange("Component Line No.", ComponentLineNo);
        Dispatch.FindFirst();
        exit(Dispatch."Prod. Order Line No.");
    end;

    local procedure UnconsumedQuantity(Audit: Record "DOPSWHS Subcontract Receipt"; ComponentLineNo: Integer): Decimal
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        FilterOperationDispatches(Audit, Dispatch);
        Dispatch.SetRange("Component Line No.", ComponentLineNo);
        Dispatch.CalcSums(Quantity, "Consumed Quantity");
        exit(Dispatch.Quantity - Dispatch."Consumed Quantity");
    end;

    /// Teslim alınan miktarın üretim emri satırı miktarına oranı (temel birimde).
    local procedure ReceivedRatio(Audit: Record "DOPSWHS Subcontract Receipt"): Decimal
    var
        PurchaseLine: Record "Purchase Line";
        ProdOrderLine: Record "Prod. Order Line";
        QtyPerUoM: Decimal;
    begin
        QtyPerUoM := 1;
        if PurchaseLine.Get(PurchaseLine."Document Type"::Order, Audit."Purchase Order No.", Audit."Purchase Line No.") then
            if PurchaseLine."Qty. per Unit of Measure" <> 0 then
                QtyPerUoM := PurchaseLine."Qty. per Unit of Measure";
        if not ProdOrderLine.Get(ProdOrderLine.Status::Released, Audit."Prod. Order No.", Audit."Prod. Order Line No.") then
            exit(0);
        if ProdOrderLine."Quantity (Base)" = 0 then
            exit(0);
        exit(Audit.Quantity * QtyPerUoM / ProdOrderLine."Quantity (Base)");
    end;

    /// Sevkte LP'nin tamamı fason lokasyonuna taşındıysa, tüketilen miktar LP içeriğinden düşülür.
    /// LP kısmen gönderildiyse sevk anında zaten düşülmüştür; burada bir şey yapılmaz.
    local procedure DebitDispatchedLp(Audit: Record "DOPSWHS Subcontract Receipt"; DispatchEntryNo: Integer; BaseQty: Decimal)
    var
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Reference: Code[40];
    begin
        if BaseQty <= 0 then
            exit;
        Dispatch.Get(DispatchEntryNo);
        if not LP.Get(Dispatch."LP No.") then
            exit;
        if LP."Location Code" <> Dispatch."To Location Code" then
            exit;
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            exit;
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetRange("Item No.", Dispatch."Item No.");
        LPLine.SetRange("Lot No.", Dispatch."Lot No.");
        LPLine.SetRange("Serial No.", Dispatch."Serial No.");
        if not LPLine.FindFirst() then
            exit;
        Reference := CopyStr(
            'FASON:' + Audit."Posted Purchase Receipt No." + '/' + Format(Audit."Entry No.") + '/' + Format(DispatchEntryNo),
            1, MaxStrLen(Reference));
        LPMgt.ConsumeLineForShipment(LP."No.", LPLine."Line No.", BaseQty, Reference);
    end;
}
