page 50123 "WMS Count Variance API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsCountVariance';
    EntitySetName = 'wmsCountVariances';
    SourceTable = "WMS Count Variance";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(planNumber; Rec."Plan No.") { }
                field(lineNumber; Rec."Line No.") { }
                field(itemNumber; Rec."Item No.") { }
                field(variantCode; Rec."Variant Code") { }
                field(locationCode; Rec."Location Code") { }
                field(binCode; Rec."Bin Code") { }
                field(systemQuantity; Rec."System Quantity") { }
                field(countedQuantity; Rec."Counted Quantity") { }
                field(variance; Rec.Variance) { }
                field(countedBy; Rec."Counted By") { }
                field(countedAt; Rec."Counted At") { }
                field(approvedBy; Rec."Approved By") { }
                field(approvedAt; Rec."Approved At") { }
                field(recountNumber; Rec."Recount No.") { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
