/// <summary>
/// BC 28'de depo yönetimli lokasyondan direkt transfer yapılamadığı için fason
/// sevki yolda lokasyonlu transferle yapılır. Depo sevkiyatı kaydedildiğinde bu
/// codeunit sevk edilen fason transferlerinin fason lokasyonuna girişini kaydeder;
/// malzeme böylece sevkle aynı anda fasonda görünür.
/// </summary>
codeunit 72476 "DOPSWHS Subcont Transfer Rcpt"
{
    Access = Internal;
    SingleInstance = true;

    var
        ShippedFasonTransfers: List of [Code[20]];

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Shipment", 'OnAfterPostSourceDocument', '', false, false)]
    local procedure CollectShippedFasonTransfer(var WarehouseShipmentLine: Record "Warehouse Shipment Line")
    var
        TransferHeader: Record "Transfer Header";
    begin
        if WarehouseShipmentLine."Source Type" <> Database::"Transfer Line" then
            exit;
        if ShippedFasonTransfers.Contains(WarehouseShipmentLine."Source No.") then
            exit;
        if not TransferHeader.Get(WarehouseShipmentLine."Source No.") then
            exit;
        if TransferHeader."DOPSWHS Fason Reference No." = '' then
            exit;
        ShippedFasonTransfers.Add(WarehouseShipmentLine."Source No.");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Shipment", 'OnAfterPostWhseShipment', '', false, false)]
    local procedure PostFasonReceipts(var WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SuppressCommit: Boolean)
    var
        SubcontractMgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        Pending: List of [Code[20]];
        TransferNo: Code[20];
    begin
        if ShippedFasonTransfers.Count() = 0 then
            exit;
        Pending := ShippedFasonTransfers;
        Clear(ShippedFasonTransfers);
        foreach TransferNo in Pending do
            SubcontractMgmt.PostPendingFasonTransferReceipt(TransferNo);
    end;
}
