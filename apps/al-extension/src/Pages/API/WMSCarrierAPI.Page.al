page 50124 "WMS Carrier API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsCarrier';
    EntitySetName = 'wmsCarriers';
    SourceTable = "WMS Carrier";
    DelayedInsert = true;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(code; Rec.Code) { }
                field(name; Rec.Name) { }
                field(provider; Rec.Provider) { }
                field(apiEndpoint; Rec."API Endpoint") { }
                field(accountNumber; Rec."Account Number") { }
                field(sandbox; Rec.Sandbox) { }
                field(active; Rec.Active) { }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
