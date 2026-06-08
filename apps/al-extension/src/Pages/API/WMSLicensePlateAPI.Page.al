page 50111 "WMS License Plate API"
{
    PageType = API;
    APIPublisher = 'dynopsbc';
    APIGroup = 'wms';
    APIVersion = 'v1.0';
    EntityName = 'wmsLicensePlate';
    EntitySetName = 'wmsLicensePlates';
    SourceTable = "WMS License Plate";
    DelayedInsert = true;
    ODataKeyFields = SystemId;
    Caption = 'WMS License Plate API';

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(systemId; Rec.SystemId) { Caption = 'systemId'; Editable = false; }
                field(number; Rec."No.") { Caption = 'number'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(parentLpNumber; Rec."Parent LP No.") { Caption = 'parentLpNumber'; }
                field(containerTypeCode; Rec."Container Type Code") { Caption = 'containerTypeCode'; }
                field(createdAt; Rec."Created At") { Caption = 'createdAt'; }
                field(createdBy; Rec."Created By") { Caption = 'createdBy'; }
                field(closed; Rec.Closed) { Caption = 'closed'; }
                field(lastModifiedDateTime; Rec.SystemModifiedAt) { Caption = 'lastModifiedDateTime'; Editable = false; }
            }
        }
    }
}
