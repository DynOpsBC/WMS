codeunit 50029022 "OSD Ship Svc"
{
    Access = Public;

    procedure GetAdapterFor(CarrierCode: Code[20]) Adapter: Interface "OSD Carrier Adapter"
    var
        Carrier: Record "OSD Carrier";
        Manual: Codeunit "OSD Carrier Manual";
        FedEx: Codeunit "OSD Carrier Fed Ex";
        UPS: Codeunit "OSD Carrier UPS";
        USPS: Codeunit "OSD Carrier USPS";
        DHL: Codeunit "OSD Carrier DHL";
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
        Carrier: Record "OSD Carrier";
        Adapter: Interface "OSD Carrier Adapter";
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
