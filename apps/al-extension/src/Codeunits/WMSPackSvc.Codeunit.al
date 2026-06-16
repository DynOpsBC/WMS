codeunit 50029013 "WMS Pack Svc"
{
    Access = Public;

    procedure CreateContainer(ContainerNo: Code[20]; ShipmentNo: Code[20]; ContainerType: Code[20]; PackingLoc: Code[20]; CreatedBy: Code[50]): Boolean
    var
        C: Record "WMS Container";
    begin
        if C.Get(ContainerNo) then exit(false);
        C.Init();
        C."No." := ContainerNo;
        C."Shipment No." := ShipmentNo;
        C."Container Type Code" := ContainerType;
        C."Packing Location" := PackingLoc;
        C.Status := C.Status::Open;
        C."Created At" := CurrentDateTime();
        C."Created By" := CreatedBy;
        C.Insert();
        exit(true);
    end;

    procedure AddLine(ContainerNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; Qty: Decimal; UoM: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; PackedBy: Code[50]): Boolean
    var
        L: Record "WMS Container Line";
        NextLineNo: Integer;
    begin
        L.SetRange("Container No.", ContainerNo);
        if L.FindLast() then NextLineNo := L."Line No." + 10000 else NextLineNo := 10000;
        L.Init();
        L."Container No." := ContainerNo;
        L."Line No." := NextLineNo;
        L."Item No." := ItemNo;
        L."Variant Code" := VariantCode;
        L.Quantity := Qty;
        L."Unit of Measure Code" := UoM;
        L."Lot No." := LotNo;
        L."Serial No." := SerialNo;
        L."Packed By" := PackedBy;
        L."Packed At" := CurrentDateTime();
        L.Insert();
        exit(true);
    end;

    procedure CloseContainer(ContainerNo: Code[20]; ClosedBy: Code[50]): Boolean
    var
        C: Record "WMS Container";
    begin
        if not C.Get(ContainerNo) then exit(false);
        C.Status := C.Status::Closed;
        C."Closed At" := CurrentDateTime();
        C."Closed By" := ClosedBy;
        C.Modify();
        exit(true);
    end;
}
