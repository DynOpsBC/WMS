enum 72098 "DOPSWHS Assigned Doc Type"
{
    Extensible = true;

    value(0; None) { Caption = 'None'; }
    value(1; WhseReceipt) { Caption = 'Warehouse Receipt'; }
    value(2; WhsePick) { Caption = 'Warehouse Pick'; }
    value(3; WhseShipment) { Caption = 'Warehouse Shipment'; }
    value(4; WhsePutaway) { Caption = 'Warehouse Put-away'; }
    value(5; WhseMovement) { Caption = 'Warehouse Movement'; }
    value(6; ProdConsumption) { Caption = 'Production Consumption'; }
    value(7; ProdOutput) { Caption = 'Production Output'; }
    value(8; Assembly) { Caption = 'Assembly'; }
    // EMU/DKÇ (15 Eyl 2026): an LP can reference any open or posted document and
    // pull that document's lines into its content (see "DOPSWHS LP Document Link").
    value(10; SalesOrder) { Caption = 'Sales Order'; }
    value(11; PurchaseOrder) { Caption = 'Purchase Order'; }
    value(12; TransferOrder) { Caption = 'Transfer Order'; }
    value(20; PostedSalesShipment) { Caption = 'Posted Sales Shipment'; }
    value(21; PostedPurchaseReceipt) { Caption = 'Posted Purchase Receipt'; }
    value(22; PostedWhseReceipt) { Caption = 'Posted Warehouse Receipt'; }
    value(23; PostedWhseShipment) { Caption = 'Posted Warehouse Shipment'; }
    value(24; PostedTransferShipment) { Caption = 'Posted Transfer Shipment'; }
    value(25; PostedTransferReceipt) { Caption = 'Posted Transfer Receipt'; }
}
