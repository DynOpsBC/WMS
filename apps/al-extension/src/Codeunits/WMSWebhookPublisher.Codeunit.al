codeunit 50123 "WMS Webhook Publisher"
{
    Access = Public;

    /// <summary>
    /// Emits a webhook event to BC subscribers. The web PWA's SignalR bridge picks
    /// it up and pushes to dashboards in real time.
    /// </summary>
    procedure Emit(EventType: Text; Body: JsonObject)
    var
        Envelope: JsonObject;
        Json: Text;
    begin
        Envelope.Add('eventType', EventType);
        Envelope.Add('emittedAt', Format(CurrentDateTime(), 0, 9));
        Envelope.Add('body', Body);
        Envelope.WriteTo(Json);
        // TODO[BC-sandbox]: write to a queue table or invoke an Azure Service Bus endpoint
        // for fan-out to web subscribers.
    end;

    procedure EmitPicked(ShipmentNo: Code[20]; Worker: Code[50]; Qty: Decimal)
    var
        Body: JsonObject;
    begin
        Body.Add('shipmentNo', ShipmentNo);
        Body.Add('worker', Worker);
        Body.Add('qty', Qty);
        Emit('shipment.picked', Body);
    end;

    procedure EmitReceived(ReceiptNo: Code[20]; Worker: Code[50]; LpNo: Code[20])
    var
        Body: JsonObject;
    begin
        Body.Add('receiptNo', ReceiptNo);
        Body.Add('worker', Worker);
        Body.Add('lpNo', LpNo);
        Emit('receipt.received', Body);
    end;
}
