page 72094 "DOPSWHS Shipment Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouseOps';
    APIVersion = 'v2.0';
    EntityName = 'shipmentLine';
    EntitySetName = 'shipmentLines';
    SourceTable = "Warehouse Shipment Line";
    DelayedInsert = true;
    ODataKeyFields = "No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; Editable = false; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; Editable = false; }
                field(description; Rec.Description) { Caption = 'description'; Editable = false; }
                field(qtyOutstanding; Rec."Qty. Outstanding") { Caption = 'qtyOutstanding'; Editable = false; }
                field(qtyToShip; Rec."Qty. to Ship") { Caption = 'qtyToShip'; }
                field(licensePlateNo; Rec."LP No.") { Caption = 'licensePlateNo'; }
                field(sscc; Rec.SSCC) { Caption = 'sscc'; }
                field(uomCode; Rec."Unit of Measure Code") { Caption = 'uomCode'; Editable = false; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
            }
        }
    }

    trigger OnModifyRecord(): Boolean
    var
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
    begin
        ShipmentMgmt.ConfirmShipmentLine(Rec, Rec."Qty. to Ship", Rec."LP No.", Rec.SSCC);
        exit(false);
    end;
}
