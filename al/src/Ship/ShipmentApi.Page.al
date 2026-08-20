page 72093 "DOPSWHS Shipment API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'shipment';
    EntitySetName = 'shipments';
    SourceTable = "Warehouse Shipment Header";
    // Show Open + Released so the mobile app can load a shipment that got reopened by a Qty edit;
    // posting auto-releases an Open shipment (see DOPSWHS Shipment Mgmt.PostShipment).
    DelayedInsert = true;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(assignedUserId; Rec."Assigned User ID") { Caption = 'assignedUserId'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(shipmentDate; Rec."Shipment Date") { Caption = 'shipmentDate'; }
                field(sourceNo; SourceNo) { Caption = 'sourceNo'; }
                field(shipTo; ShipTo) { Caption = 'shipTo'; }
                field(lineCount; LineCount) { Caption = 'lineCount'; }
                part(lines; "DOPSWHS Shipment Line API")
                {
                    Caption = 'lines';
                    EntityName = 'shipmentLine';
                    EntitySetName = 'shipmentLines';
                    SubPageLink = "No." = field("No.");
                }
            }
        }
    }

    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::Shipment);
        RecRef.SetTable(Rec);
    end;

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    [ServiceEnabled]
    procedure post(print: Boolean; invoice: Boolean)
    var
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
    begin
        ShipmentMgmt.PostShipment(Rec, print, invoice);
    end;

    [ServiceEnabled]
    procedure postToPrinter(print: Boolean; invoice: Boolean; printerId: Code[50])
    var
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
    begin
        ShipmentMgmt.PostShipment(Rec, print, invoice, printerId);
    end;

    [ServiceEnabled]
    procedure createPick(): Code[20]
    var
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
    begin
        exit(ShipmentMgmt.CreatePick(Rec));
    end;

    var
        SourceNo: Code[20];
        ShipTo: Text[100];
        LineCount: Integer;

    local procedure FillCalculatedFields()
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        SalesHeader: Record "Sales Header";
        TransferHeader: Record "Transfer Header";
    begin
        Clear(SourceNo);
        Clear(ShipTo);
        Clear(LineCount);

        WhseShipmentLine.SetRange("No.", Rec."No.");
        if WhseShipmentLine.FindSet() then
            repeat
                LineCount += 1;
                if SourceNo = '' then
                    SourceNo := WhseShipmentLine."Source No.";
            until WhseShipmentLine.Next() = 0;

        if SalesHeader.Get(SalesHeader."Document Type"::Order, SourceNo) then
            ShipTo := SalesHeader."Ship-to Name"
        else
            if TransferHeader.Get(SourceNo) then
                ShipTo := TransferHeader."Transfer-to Name";
    end;
}
