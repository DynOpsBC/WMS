page 50120 "WMS Container API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsContainer';
    EntitySetName = 'wmsContainers';
    SourceTable = "WMS Container";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(number; Rec."No.") { }
                field(shipmentNumber; Rec."Shipment No.") { }
                field(containerTypeCode; Rec."Container Type Code") { }
                field(packingLocation; Rec."Packing Location") { }
                field(status; Rec.Status) { }
                field(grossWeight; Rec."Gross Weight") { }
                field(tareWeight; Rec."Tare Weight") { }
                field(length; Rec.Length) { }
                field(width; Rec.Width) { }
                field(height; Rec.Height) { }
                field(trackingNumber; Rec."Tracking Number") { }
                field(createdBy; Rec."Created By") { }
                field(closedBy; Rec."Closed By") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
