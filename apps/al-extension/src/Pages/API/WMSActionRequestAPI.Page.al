page 50029027 "WMS Action Request API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsActionRequest';
    EntitySetName = 'wmsActionRequests';
    SourceTable = "WMS Action Request";
    DelayedInsert = true;
    ODataKeyFields = SystemId;
    Caption = 'WMS Action Request API';

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Editable = false; }
                field(requestId; Rec."Request Id") { }
                field(flowId; Rec."Flow Id") { }
                field(payload; Rec.Payload) { }
                field(workerId; Rec."Worker Id") { }
                field(deviceId; Rec."Device Id") { }
                field(status; Rec.Status) { Editable = false; }
                field(resultMessage; Rec."Result Message") { Editable = false; }
                field(resultDocumentNo; Rec."Result Document No.") { Editable = false; }
                field(processedAt; Rec."Processed At") { Editable = false; }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Editable = false; }
            }
        }
    }
}
