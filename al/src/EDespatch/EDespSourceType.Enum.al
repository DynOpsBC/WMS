enum 72214 "DOPSWHS EDesp Source Type"
{
    Extensible = true;
    Caption = 'E-Despatch Source Type';

    value(0; TransferShipment) { Caption = 'Transfer Shipment'; }
    value(1; DirectTransfer) { Caption = 'Posted Direct Transfer'; }
    value(2; RegisteredWhseMovement) { Caption = 'Registered Warehouse Movement'; }
    value(3; RegisteredInvtMovement) { Caption = 'Registered Inventory Movement'; }
    value(4; AdHocMove) { Caption = 'Handheld Bin Move'; }
}
