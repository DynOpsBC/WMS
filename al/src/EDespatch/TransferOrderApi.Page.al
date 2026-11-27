page 72462 "DOPSWHS Transfer Order API"
{
    // Released transfer orders for the handheld "Transfer Sevk" screen.
    //   GET  transferOrders?$filter=transferFromCode eq 'ANA'
    //   POST transferOrders('{no}')/Microsoft.NAV.ship  { linesJson, overridesJson, userId, idempotencyKey }
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'transferOrder';
    EntitySetName = 'transferOrders';
    SourceTable = "Transfer Header";
    SourceTableView = where(Status = const(Released));
    ODataKeyFields = "No.";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(transferFromCode; Rec."Transfer-from Code") { Caption = 'transferFromCode'; }
                field(transferFromName; Rec."Transfer-from Name") { Caption = 'transferFromName'; }
                field(transferToCode; Rec."Transfer-to Code") { Caption = 'transferToCode'; }
                field(transferToName; Rec."Transfer-to Name") { Caption = 'transferToName'; }
                field(inTransitCode; Rec."In-Transit Code") { Caption = 'inTransitCode'; }
                field(directTransfer; Rec."Direct Transfer") { Caption = 'directTransfer'; }
                field(shipmentDate; Rec."Shipment Date") { Caption = 'shipmentDate'; }
                field(postingDate; Rec."Posting Date") { Caption = 'postingDate'; }
                field(externalDocumentNo; Rec."External Document No.") { Caption = 'externalDocumentNo'; }
                field(fasonReferenceNo; Rec."DOPSWHS Fason Reference No.") { Caption = 'fasonReferenceNo'; }
                field(requiresWhseShipment; RequiresWhseShipment) { Caption = 'requiresWhseShipment'; }
                field(outstandingQuantity; OutstandingQuantity) { Caption = 'outstandingQuantity'; }
                field(lineCount; LineCount) { Caption = 'lineCount'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Location: Record Location;
        TransferLine: Record "Transfer Line";
    begin
        RequiresWhseShipment := false;
        if Location.Get(Rec."Transfer-from Code") then
            RequiresWhseShipment := Location."Require Shipment";
        TransferLine.SetRange("Document No.", Rec."No.");
        TransferLine.SetRange("Derived From Line No.", 0);
        TransferLine.SetFilter("Item No.", '<>%1', '');
        LineCount := TransferLine.Count();
        TransferLine.CalcSums("Outstanding Quantity");
        OutstandingQuantity := TransferLine."Outstanding Quantity";
    end;

    [ServiceEnabled]
    procedure ship(linesJson: Text; overridesJson: Text; userId: Code[50]; idempotencyKey: Guid): Text
    var
        TransferShipMgmt: Codeunit "DOPSWHS Transfer Ship Mgmt";
    begin
        exit(TransferShipMgmt.ShipTransferOrder(Rec."No.", linesJson, overridesJson, userId, idempotencyKey));
    end;

    var
        RequiresWhseShipment: Boolean;
        OutstandingQuantity: Decimal;
        LineCount: Integer;
}
