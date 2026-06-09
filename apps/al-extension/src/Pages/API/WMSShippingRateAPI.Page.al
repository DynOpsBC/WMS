page 50125 "WMS Shipping Rate API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsShippingRate';
    EntitySetName = 'wmsShippingRates';
    SourceTable = "WMS Shipping Rate";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(rateId; Rec."Rate ID") { }
                field(shipmentNumber; Rec."Shipment No.") { }
                field(carrierCode; Rec."Carrier Code") { }
                field(serviceCode; Rec."Service Code") { }
                field(serviceName; Rec."Service Name") { }
                field(amount; Rec.Amount) { }
                field(currency; Rec.Currency) { }
                field(estimatedDays; Rec."Estimated Days") { }
                field(quotedAt; Rec."Quoted At") { }
                field(selected; Rec.Selected) { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
