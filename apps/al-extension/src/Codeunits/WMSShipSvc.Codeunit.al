codeunit 50122 "WMS Ship Svc"
{
    Access = Public;

    procedure GetAdapterFor(CarrierCode: Code[20]) Adapter: Interface "WMS Carrier Adapter"
    var
        Carrier: Record "WMS Carrier";
        Manual: Codeunit "WMS Carrier Manual";
        FedEx: Codeunit "WMS Carrier FedEx";
        UPS: Codeunit "WMS Carrier UPS";
        USPS: Codeunit "WMS Carrier USPS";
        DHL: Codeunit "WMS Carrier DHL";
    begin
        if not Carrier.Get(CarrierCode) then exit(Manual);
        case Carrier.Provider of
            Carrier.Provider::FedEx: Adapter := FedEx;
            Carrier.Provider::UPS:   Adapter := UPS;
            Carrier.Provider::USPS:  Adapter := USPS;
            Carrier.Provider::DHL:   Adapter := DHL;
            else                     Adapter := Manual;
        end;
    end;

    procedure RateShopAllCarriers(ShipmentNo: Code[20]) Rates: JsonArray
    var
        Carrier: Record "WMS Carrier";
        Adapter: Interface "WMS Carrier Adapter";
        Sub: JsonArray;
        Token: JsonToken;
    begin
        Carrier.SetRange(Active, true);
        if not Carrier.FindSet() then exit;
        repeat
            Adapter := GetAdapterFor(Carrier.Code);
            Sub := Adapter.RateShop(ShipmentNo);
            foreach Token in Sub do
                Rates.Add(Token);
        until Carrier.Next() = 0;
    end;
}
