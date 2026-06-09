codeunit 50118 "WMS Carrier FedEx" implements "WMS Carrier Adapter"
{
    // TODO[carrier]: real FedEx OAuth2 + rate / label endpoints.
    // https://developer.fedex.com/api/en-us/catalog.html

    procedure RateShop(ShipmentNo: Code[20]) Rates: JsonArray
    begin
        // TODO[carrier]: POST /rate/v1/rates/quotes
    end;

    procedure CreateLabel(ShipmentNo: Code[20]; ServiceCode: Code[20]) LabelZpl: Text
    begin
        // TODO[carrier]: POST /ship/v1/shipments → return base64 ZPL.
    end;

    procedure VoidLabel(TrackingNumber: Code[50]): Boolean
    begin
        exit(false);
    end;

    procedure TrackShipment(TrackingNumber: Code[50]) Status: JsonObject
    begin
    end;
}
