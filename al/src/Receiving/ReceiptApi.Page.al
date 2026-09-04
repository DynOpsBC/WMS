page 72090 "DOPSWHS Receipt API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'receipt';
    EntitySetName = 'receipts';
    SourceTable = "Warehouse Receipt Header";
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
                field(sourceNo; SourceNo) { Caption = 'sourceNo'; }
                field(sourceType; SourceType) { Caption = 'sourceType'; }
                field(vendorSourceName; VendorSourceName) { Caption = 'vendorSourceName'; }
                field(dueDate; DueDate) { Caption = 'dueDate'; }
                field(percentComplete; PercentComplete) { Caption = 'percentComplete'; }
                field(vendorShipmentNo; VendorShipmentNo) { Caption = 'vendorShipmentNo'; }
                field(vehicleInfoRequired; VehicleInfoRequired) { Caption = 'vehicleInfoRequired'; }
                field(vehiclePlateNo; VehiclePlateNo) { Caption = 'vehiclePlateNo'; }
                field(driverCode; DriverCode) { Caption = 'driverCode'; }
                field(driverName; DriverName) { Caption = 'driverName'; }
                field(lpNo; Rec."DOPSWHS LP No.") { Caption = 'lpNo'; }
                field(lpOpen; LpOpen) { Caption = 'lpOpen'; }
                part(lines; "DOPSWHS Receipt Line API")
                {
                    Caption = 'lines';
                    EntityName = 'receiptLine';
                    EntitySetName = 'receiptLines';
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
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::Receipt);
        RecRef.SetTable(Rec);
    end;

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    [ServiceEnabled]
    procedure assignToUser(userId: Code[50])
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        ReceiptMgmt.AssignUser(Rec, userId);
    end;

    [ServiceEnabled]
    procedure startLP(lpTemplateCode: Code[20]): Text
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
        LpNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        LpNo := ReceiptMgmt.StartLP(Rec, lpTemplateCode);
        exit(LpNo);
    end;

    [ServiceEnabled]
    procedure stopLP(lpNo: Code[20]; printLabel: Boolean)
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        ReceiptMgmt.StopLP(Rec, lpNo, printLabel);
    end;

    [ServiceEnabled]
    procedure stopLPToPrinter(lpNo: Code[20]; printLabel: Boolean; printerId: Code[50])
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        ReceiptMgmt.StopLP(Rec, lpNo, printLabel, printerId);
    end;

    /// <summary>
    /// Creates and closes every pallet for one receipt line in a single transaction.
    /// distributionJson is a flat array: groupId, quantity, lotNo, supplierLotNo, expiryDate.
    /// Every pallet uses one common tracking identity; a blank lotNo is generated once.
    /// </summary>
    [ServiceEnabled]
    procedure createBulkLPDistribution(lineNo: Integer; expectedQty: Decimal; distributionJson: Text; lpTemplateCode: Code[20]; printLabels: Boolean; printerId: Code[50]): Text
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        exit(ReceiptMgmt.CreateBulkLPDistribution(
            Rec, lineNo, expectedQty, distributionJson, lpTemplateCode, printLabels, printerId));
    end;

    [ServiceEnabled]
    procedure post(print: Boolean; invoice: Boolean)
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        ReceiptMgmt.PostReceipt(Rec, print, invoice);
    end;

    [ServiceEnabled]
    procedure postToPrinter(print: Boolean; invoice: Boolean; printerId: Code[50])
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LegacyWI: Codeunit "DOPSWHS Legacy WI Publisher";
        DocNo: Code[20];
    begin
        DocNo := Rec."No.";
        LegacyWI.FireGetReceiptDocument(DocNo);
        ReceiptMgmt.PostReceipt(Rec, print, invoice, '', printerId);
    end;

    /// <summary>
    /// BADE gibi tenant'larda mal kabul postu plaka + sürücü ister. Terminal bu
    /// aksiyonla başlığı doldurur; alanlar yoksa BC anlaşılır hata döner.
    /// </summary>
    [ServiceEnabled]
    procedure setVehicleInfo(vehiclePlateNo: Text; driverCode: Code[20]; vendorShipmentNo: Text)
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        ReceiptMgmt.SetVehicleInfo(Rec, vehiclePlateNo, driverCode, vendorShipmentNo);
    end;

    /// <summary>JSON dizisi [{code,name}] — tenant'ta sürücü tablosu yoksa [].</summary>
    [ServiceEnabled]
    procedure listVehicleDrivers(): Text
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        exit(ReceiptMgmt.ListVehicleDrivers());
    end;

    var
        SourceNo: Code[20];
        SourceType: Text[30];
        VendorSourceName: Text[100];
        DueDate: Date;
        PercentComplete: Decimal;
        VendorShipmentNo: Text[35];
        VehicleInfoRequired: Boolean;
        VehiclePlateNo: Text[50];
        DriverCode: Code[20];
        DriverName: Text[200];
        LpOpen: Boolean;

    local procedure FillCalculatedFields()
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PurchaseHeader: Record "Purchase Header";
        TransferHeader: Record "Transfer Header";
        LPHeader: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        TotalQty: Decimal;
        HandledQty: Decimal;
    begin
        Clear(SourceNo);
        Clear(SourceType);
        Clear(VendorSourceName);
        Clear(DueDate);
        Clear(PercentComplete);
        Clear(VendorShipmentNo);
        Clear(VehicleInfoRequired);
        Clear(VehiclePlateNo);
        Clear(DriverCode);
        Clear(DriverName);
        Clear(LpOpen);

        // Terminal yeniden açıldığında açık LP'yi bulabilsin; aksi halde ikinci
        // bir LP başlatılıyor. StopLP başlıktaki LP No.'yu silmez, o yüzden
        // "açık mı" ayrıca bildirilir.
        if Rec."DOPSWHS LP No." <> '' then
            if LPHeader.Get(Rec."DOPSWHS LP No.") then
                LpOpen := LPHeader.Status = LPHeader.Status::Open;

        VendorShipmentNo := CopyStr(ReceiptMgmt.GetTenantHeaderField(Rec, 'Vendor Shipment No.'), 1, MaxStrLen(VendorShipmentNo));
        VehicleInfoRequired := ReceiptMgmt.VehicleInfoRequired(Rec);
        if VehicleInfoRequired then begin
            VehiclePlateNo := CopyStr(ReceiptMgmt.GetTenantHeaderField(Rec, 'Vehicle Plate No'), 1, MaxStrLen(VehiclePlateNo));
            DriverCode := CopyStr(ReceiptMgmt.GetTenantHeaderField(Rec, 'Driver Code'), 1, MaxStrLen(DriverCode));
            DriverName := CopyStr(
                DelChr(ReceiptMgmt.GetTenantHeaderField(Rec, 'Driver Name') + ' ' + ReceiptMgmt.GetTenantHeaderField(Rec, 'Driver Surname'), '<>', ' '),
                1, MaxStrLen(DriverName));
        end;

        WhseReceiptLine.SetRange("No.", Rec."No.");
        if WhseReceiptLine.FindSet() then
            repeat
                if SourceNo = '' then begin
                    SourceNo := WhseReceiptLine."Source No.";
                    SourceType := Format(WhseReceiptLine."Source Type");
                    DueDate := WhseReceiptLine."Due Date";
                end;
                TotalQty += WhseReceiptLine.Quantity;
                HandledQty += WhseReceiptLine."Qty. Received";
            until WhseReceiptLine.Next() = 0;

        if SourceType = Format(Database::"Purchase Line") then
            if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, SourceNo) then
                VendorSourceName := PurchaseHeader."Buy-from Vendor Name";
        if SourceType = Format(Database::"Transfer Line") then
            if TransferHeader.Get(SourceNo) then
                VendorSourceName := TransferHeader."Transfer-from Name";

        if TotalQty <> 0 then
            PercentComplete := Round(HandledQty / TotalQty * 100, 1);
    end;
}
