page 72380 "DOPSWHS DKC Posted Ship API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'dkcPostedSalesShipment';
    EntitySetName = 'dkcPostedSalesShipments';
    SourceTable = "Sales Shipment Header";
    ODataKeyFields = "No.";
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Shipments)
            {
                field(no; Rec."No.") { }
                field(orderNo; Rec."Order No.") { }
                field(customerNo; Rec."Sell-to Customer No.") { }
                field(customerName; Rec."Sell-to Customer Name") { }
                field(postingDate; Rec."Posting Date") { }
                field(shipmentDate; Rec."Shipment Date") { }
                field(vehiclePlateNo; VehiclePlateNo) { }
                field(trailerPlateNo; TrailerPlateNo) { }
                field(driverName; DriverName) { }
                field(eDocumentNo; EDocumentNo) { }
                field(eDocumentPdfAvailable; EDocumentPdfAvailable) { }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        SourceRef: RecordRef;
    begin
        SourceRef.GetTable(Rec);
        VehiclePlateNo := CopyStr(ReadTenantField(SourceRef, 60152, 'Vehicle Plate No.', 'DYN Vehicle Plate No.'), 1, MaxStrLen(VehiclePlateNo));
        TrailerPlateNo := CopyStr(ReadTenantField(SourceRef, 0, 'Trailer Plate No.', 'Dorse Plaka No.'), 1, MaxStrLen(TrailerPlateNo));
        DriverName := CopyStr(ReadTenantField(SourceRef, 60154, 'Driver Name', 'DYN Driver First Name'), 1, MaxStrLen(DriverName));
        EDocumentNo := CopyStr(ReadTenantField(SourceRef, 78034, 'DYN E-Document No.', 'e-Belge No.'), 1, MaxStrLen(EDocumentNo));
        EDocumentPdfAvailable := ReadTenantField(SourceRef, 78033, 'DYN E-Document PDF URL', 'e-Belge PDF URL') <> '';
    end;

    [ServiceEnabled]
    procedure printEDocument(printerId: Code[50]): Integer
    var
        SourceRef: RecordRef;
        PdfUrl: Text;
        EWaybillPrinter: Codeunit "DOPSWHS DKC EWaybill Printer";
    begin
        SourceRef.GetTable(Rec);
        PdfUrl := ReadTenantField(SourceRef, 78033, 'DYN E-Document PDF URL', 'e-Belge PDF URL');
        if PdfUrl = '' then
            Error('%1 irsaliyesine bağlı e-belge PDF dosyası yok.', Rec."No.");
        exit(EWaybillPrinter.Print(Rec."No.", PdfUrl, printerId));
    end;

    var
        VehiclePlateNo: Text[50];
        TrailerPlateNo: Text[50];
        DriverName: Text[100];
        EDocumentNo: Text[50];
        EDocumentPdfAvailable: Boolean;

    local procedure ReadTenantField(var SourceRef: RecordRef; FieldNo: Integer; NameA: Text; NameB: Text): Text
    var
        Candidate: FieldRef;
        FieldIndex: Integer;
    begin
        if (FieldNo <> 0) and SourceRef.FieldExist(FieldNo) then
            exit(Format(SourceRef.Field(FieldNo).Value));
        for FieldIndex := 1 to SourceRef.FieldCount do begin
            Candidate := SourceRef.FieldIndex(FieldIndex);
            if (Candidate.Name = NameA) or (Candidate.Caption = NameA) or
               (Candidate.Name = NameB) or (Candidate.Caption = NameB)
            then
                exit(Format(Candidate.Value));
        end;
        exit('');
    end;
}
