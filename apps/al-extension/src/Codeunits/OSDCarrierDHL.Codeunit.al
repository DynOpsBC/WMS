codeunit 50029021 "OSD Carrier DHL" implements "OSD Carrier Adapter"
{
    procedure RateShop(ShipmentNo: Code[20]) Rates: JsonArray begin end;
    procedure CreateLabel(ShipmentNo: Code[20]; ServiceCode: Code[20]) LabelZpl: Text begin end;
    procedure VoidLabel(TrackingNumber: Code[50]): Boolean begin exit(false); end;
    procedure TrackShipment(TrackingNumber: Code[50]) Status: JsonObject begin end;
}
