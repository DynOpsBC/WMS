page 72445 "DOPSWHS Subcont Receipt API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'subcontractReceipt';
    EntitySetName = 'subcontractReceipts';
    SourceTable = "Purchase Line";
    SourceTableView = where("Document Type" = const(Order), Type = const(Item));
    ODataKeyFields = "Document Type", "Document No.", "Line No.";
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(documentType; Rec."Document Type") { }
                field(purchaseOrderNo; Rec."Document No.") { }
                field(purchaseLineNo; Rec."Line No.") { }
                field(prodOrderNo; Rec."Prod. Order No.") { }
                field(prodOrderLineNo; Rec."Prod. Order Line No.") { }
                field(routingReferenceNo; Rec."Routing Reference No.") { }
                field(routingNo; Rec."Routing No.") { }
                field(operationNo; Rec."Operation No.") { }
                field(workCenterNo; Rec."Work Center No.") { }
                field(finished; Rec.Finished) { }
                field(itemNo; Rec."No.") { }
                field(description; Rec.Description) { }
                field(quantity; Rec.Quantity) { }
                field(outstandingQuantity; Rec."Outstanding Quantity") { }
                field(quantityReceived; Rec."Quantity Received") { }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { }
                field(locationCode; Rec."Location Code") { }
                field(binCode; Rec."Bin Code") { }
                field(vendorNo; VendorNo) { }
                field(vendorName; VendorName) { }
                field(vendorOrderNo; VendorOrderNo) { }
                field(externalDocumentNo; ExternalDocumentNo) { }
                field(vendorShipmentNo; VendorShipmentNo) { }
                field(outboundReferenceNo; OutboundReferenceNo) { }
                field(outboundTransferShipmentNo; OutboundTransferShipmentNo) { }
                field(eDespatchStatus; EDespatchStatus) { }
                field(eDespatchDocumentNo; EDespatchDocumentNo) { }
                field(canFinishOperation; CanFinishOperation) { }
            }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.SetFilter("Prod. Order No.", '<>%1', '');
        Rec.SetFilter("Outstanding Quantity", '>0');
    end;

    trigger OnAfterGetRecord()
    var
        PurchaseHeader: Record "Purchase Header";
        Vendor: Record Vendor;
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        EDespatch: Record "DOPSWHS Subcontract EDesp Out";
        DispatchFound: Boolean;
    begin
        ClearCalculatedFields();
        if PurchaseHeader.Get(Rec."Document Type", Rec."Document No.") then begin
            VendorNo := PurchaseHeader."Buy-from Vendor No.";
            VendorOrderNo := PurchaseHeader."Vendor Order No.";
            // BC 24+ satın alma başlığında "External Document No." yok;
            // karşılığı "Vendor Invoice No." / "Vendor Shipment No.".
            ExternalDocumentNo := PurchaseHeader."Vendor Invoice No.";
            VendorShipmentNo := PurchaseHeader."Vendor Shipment No.";
            if Vendor.Get(VendorNo) then
                VendorName := Vendor.Name;
        end;
        Dispatch.SetRange("Purchase Order No.", Rec."Document No.");
        Dispatch.SetRange("Prod. Order No.", Rec."Prod. Order No.");
        Dispatch.SetRange("Operation No.", Rec."Operation No.");
        Dispatch.SetRange(Status, 'POSTED');
        DispatchFound := Dispatch.FindLast();
        if not DispatchFound then begin
            Dispatch.Reset();
            Dispatch.SetRange("Prod. Order No.", Rec."Prod. Order No.");
            Dispatch.SetRange("Operation No.", Rec."Operation No.");
            Dispatch.SetRange(Status, 'POSTED');
            DispatchFound := Dispatch.FindLast();
        end;
        if DispatchFound then begin
            OutboundReferenceNo := Dispatch."Fason Reference No.";
            if OutboundReferenceNo = '' then
                OutboundReferenceNo := Rec."Document No.";
            OutboundTransferShipmentNo := Dispatch."Posted Transfer Shipment No.";
            EDespatch.SetRange("Posted Transfer Shipment No.", OutboundTransferShipmentNo);
            if EDespatch.FindFirst() then begin
                EDespatchStatus := EDespatch.Status;
                EDespatchDocumentNo := EDespatch."Provider Document No.";
            end;
        end;
        CanFinishOperation := Rec."Outstanding Quantity" > 0;
    end;

    [ServiceEnabled]
    procedure receive(quantity: Decimal; vendorShipmentNo: Code[35]; inboundReferenceNo: Code[50]; binCode: Code[20]; finishOperation: Boolean; vehiclePlateNo: Text; driverCode: Code[20]; idempotencyKey: Guid): Text
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
        ReceiptPermission: Record "DOPSWHS Subcontract Receipt";
    begin
        if not ReceiptPermission.WritePermission() then
            Error('Fason teslim alma kaydı oluşturma yetkiniz yok. Depo kullanıcı rolünü kontrol edin.');
        exit(Mgmt.Receive(
            Rec, quantity, vendorShipmentNo, inboundReferenceNo, binCode,
            finishOperation, vehiclePlateNo, driverCode, idempotencyKey));
    end;

    local procedure ClearCalculatedFields()
    begin
        Clear(VendorNo);
        Clear(VendorName);
        Clear(VendorOrderNo);
        Clear(ExternalDocumentNo);
        Clear(VendorShipmentNo);
        Clear(OutboundReferenceNo);
        Clear(OutboundTransferShipmentNo);
        Clear(EDespatchStatus);
        Clear(EDespatchDocumentNo);
        Clear(CanFinishOperation);
    end;

    var
        VendorNo: Code[20];
        VendorName: Text[100];
        VendorOrderNo: Code[35];
        ExternalDocumentNo: Code[35];
        VendorShipmentNo: Code[35];
        OutboundReferenceNo: Code[50];
        OutboundTransferShipmentNo: Code[20];
        EDespatchStatus: Code[20];
        EDespatchDocumentNo: Code[50];
        CanFinishOperation: Boolean;
}
