interface "WMS Carrier Adapter"
{
    procedure RateShop(ShipmentNo: Code[20]) Rates: JsonArray;
    procedure CreateLabel(ShipmentNo: Code[20]; ServiceCode: Code[20]) LabelZpl: Text;
    procedure VoidLabel(TrackingNumber: Code[50]): Boolean;
    procedure TrackShipment(TrackingNumber: Code[50]) Status: JsonObject;
}

codeunit 50029017 "WMS Carrier Manual" implements "WMS Carrier Adapter"
{
    procedure RateShop(ShipmentNo: Code[20]) Rates: JsonArray
    var
        Rate: JsonObject;
    begin
        Rate.Add('carrier', 'MANUAL');
        Rate.Add('service', 'GROUND');
        Rate.Add('amount', 0);
        Rate.Add('currency', 'USD');
        Rate.Add('estimatedDays', 3);
        Rates.Add(Rate);
    end;

    procedure CreateLabel(ShipmentNo: Code[20]; ServiceCode: Code[20]) LabelZpl: Text
    begin
        LabelZpl := '^XA^FO50,50^A0N,36,36^FDManual shipment ' + ShipmentNo + '^FS^XZ';
    end;

    procedure VoidLabel(TrackingNumber: Code[50]): Boolean
    begin
        exit(true);
    end;

    procedure TrackShipment(TrackingNumber: Code[50]) Status: JsonObject
    begin
        Status.Add('status', 'unknown');
    end;
}
