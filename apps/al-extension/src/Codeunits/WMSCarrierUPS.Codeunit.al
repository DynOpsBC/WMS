codeunit 50029019 "WMS Carrier UPS" implements "WMS Carrier Adapter"
{
    // TODO[carrier]: UPS OAuth2 + Rating + Shipping API.
    procedure RateShop(ShipmentNo: Code[20]) Rates: JsonArray begin end;
    procedure CreateLabel(ShipmentNo: Code[20]; ServiceCode: Code[20]) LabelZpl: Text begin end;
    procedure VoidLabel(TrackingNumber: Code[50]): Boolean begin exit(false); end;
    procedure TrackShipment(TrackingNumber: Code[50]) Status: JsonObject begin end;
}
