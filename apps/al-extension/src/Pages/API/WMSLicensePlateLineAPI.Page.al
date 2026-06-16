page 50029016 "WMS LP Line API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsLicensePlateLine';
    EntitySetName = 'wmsLicensePlateLines';
    SourceTable = "WMS License Plate Line";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(lpNumber; Rec."LP No.") { }
                field(lineNumber; Rec."Line No.") { }
                field(itemNumber; Rec."Item No.") { }
                field(variantCode; Rec."Variant Code") { }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { }
                field(quantity; Rec.Quantity) { }
                field(lotNumber; Rec."Lot No.") { }
                field(serialNumber; Rec."Serial No.") { }
                field(expirationDate; Rec."Expiration Date") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
