page 50114 "WMS Item Barcode API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsItemBarcode';
    EntitySetName = 'wmsItemBarcodes';
    SourceTable = "WMS Item Barcode";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(barcode; Rec.Barcode) { }
                field(itemNumber; Rec."Item No.") { }
                field(variantCode; Rec."Variant Code") { }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { }
                field(quantityPerUoM; Rec."Quantity per UoM") { }
                field(symbology; Rec.Symbology) { }
                field(primary; Rec.Primary) { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
