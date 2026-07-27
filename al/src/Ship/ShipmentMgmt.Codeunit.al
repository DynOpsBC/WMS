codeunit 72047 "DOPSWHS Shipment Mgmt"
{
    Access = Public;

    procedure ConfirmShipmentLine(var WhseShipmentLine: Record "Warehouse Shipment Line"; QtyToShip: Decimal; LotNo: Code[50]; LicensePlateNo: Code[20]; SSCC: Code[18])
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
    begin
        WhseShipmentLine.Validate("Qty. to Ship", QtyToShip);
        WhseShipmentLine."DOPSWHS Lot No." := LotNo;
        WhseShipmentLine."LP No." := LicensePlateNo;
        WhseShipmentLine.SSCC := SSCC;
        WhseShipmentLine.Modify(true);

        // Stamp the Whse Shipment Header with this LP (first line wins) so the header-level
        // OData query can surface the carton without drilling lines.
        if LicensePlateNo <> '' then
            if WhseShipmentHeader.Get(WhseShipmentLine."No.") then
                if WhseShipmentHeader."DOPSWHS LP No." = '' then begin
                    WhseShipmentHeader."DOPSWHS LP No." := LicensePlateNo;
                    WhseShipmentHeader.Modify(true);
                end;
    end;

    procedure CreatePick(var WhseShipmentHeader: Record "Warehouse Shipment Header"): Code[20]
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseActivityLine: Record "Warehouse Activity Line";
        PickHeader: Record "Warehouse Activity Header";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        CreatePickReport: Report "Whse.-Shipment - Create Pick";
        PickNo: Code[20];
        AssignToUserId: Code[50];
    begin
        // Aynı sevkiyat için açık pick varsa ikinci bir pick üretme; mevcut kaydı döndür.
        PickNo := FindOpenPick(WhseShipmentHeader."No.");
        if PickNo <> '' then begin
            StampShipmentLotsOnPick(WhseShipmentHeader."No.", PickNo);
            exit(PickNo);
        end;

        if WhseShipmentHeader.Status <> WhseShipmentHeader.Status::Released then begin
            WhseShipmentRelease.Release(WhseShipmentHeader);
            WhseShipmentHeader.Get(WhseShipmentHeader."No.");
        end;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if not WhseShipmentLine.FindFirst() then
            Error(NoShipmentLinesErr, WhseShipmentHeader."No.");

        AssignToUserId := CopyStr(UserId(), 1, MaxStrLen(AssignToUserId));
        CreatePickReport.SetWhseShipmentLine(WhseShipmentLine, WhseShipmentHeader);
        CreatePickReport.SetHideValidationDialog(true);
        CreatePickReport.Initialize(AssignToUserId, Enum::"Whse. Activity Sorting Method"::"Shelf or Bin", false, false, false);
        CreatePickReport.UseRequestPage(false);
        CreatePickReport.RunModal();

        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", WhseShipmentHeader."No.");
        if not WhseActivityLine.FindLast() then
            Error(PickNotCreatedErr, WhseShipmentHeader."No.");
        PickNo := WhseActivityLine."No.";

        // Report sürümüne göre atama başlığa taşınmayabilir; mobil "Bana atanan"
        // filtresinde görünmesi için başlıkta garanti et.
        if PickHeader.Get(PickHeader.Type::Pick, PickNo) then
            if PickHeader."Assigned User ID" <> AssignToUserId then begin
                PickHeader.Validate("Assigned User ID", AssignToUserId);
                PickHeader.Modify(true);
            end;

        StampShipmentLotsOnPick(WhseShipmentHeader."No.", PickNo);
        exit(PickNo);
    end;

    local procedure FindOpenPick(ShipmentNo: Code[20]): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", ShipmentNo);
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."No.");
        exit('');
    end;

    local procedure StampShipmentLotsOnPick(ShipmentNo: Code[20]; PickNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("No.", PickNo);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", ShipmentNo);
        if WhseActivityLine.FindSet(true) then
            repeat
                if WhseShipmentLine.Get(ShipmentNo, WhseActivityLine."Whse. Document Line No.") then
                    if WhseShipmentLine."DOPSWHS Lot No." <> '' then begin
                        WhseActivityLine.Validate("Lot No.", WhseShipmentLine."DOPSWHS Lot No.");
                        WhseActivityLine.Modify(true);
                    end;
            until WhseActivityLine.Next() = 0;
    end;

    procedure PostShipment(var WhseShipmentHeader: Record "Warehouse Shipment Header"; PrintPackingSlip: Boolean; Invoice: Boolean)
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        PostedWhseShipmentLine: Record "Posted Whse. Shipment Line";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        LineLp: Dictionary of [Integer, Code[20]];
        LineSscc: Dictionary of [Integer, Code[18]];
        LpNo: Code[20];
        Sscc: Code[18];
        LineCount: Integer;
        LpCount: Integer;
        PostedNo: Code[20];
    begin
        // Mobile-friendly: auto-release if the shipment is still Open (e.g. a Qty. to Ship edit
        // reopened it), so the operator doesn't have to re-release in BC before posting.
        if WhseShipmentHeader.Status <> WhseShipmentHeader.Status::Released then begin
            WhseShipmentRelease.Release(WhseShipmentHeader);
            WhseShipmentHeader.Get(WhseShipmentHeader."No.");
        end;
        WhseShipmentHeader.TestField(Status, WhseShipmentHeader.Status::Released);

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if WhseShipmentLine.FindSet(true) then
            repeat
                LineCount += 1;
                if WhseShipmentLine."LP No." <> '' then begin
                    LpNo := WhseShipmentLine."LP No.";
                    EnsureLpSscc(LpNo, Sscc);
                    WhseShipmentLine.SSCC := Sscc;
                    WhseShipmentLine.Modify(true);
                    LineLp.Set(WhseShipmentLine."Line No.", LpNo);
                    LineSscc.Set(WhseShipmentLine."Line No.", Sscc);
                end;
            until WhseShipmentLine.Next() = 0;

        EnsureAssignedShipmentLpsHaveSscc(WhseShipmentHeader."No.", LpCount);

        if WhseShipmentLine.FindFirst() then
            WhsePostShipment.Run(WhseShipmentLine);

        PostedWhseShipmentHeader.SetRange("Whse. Shipment No.", WhseShipmentHeader."No.");
        if PostedWhseShipmentHeader.FindLast() then
            PostedNo := PostedWhseShipmentHeader."No.";

        PostedWhseShipmentLine.SetRange("Whse. Shipment No.", WhseShipmentHeader."No.");
        if PostedWhseShipmentLine.FindSet(true) then
            repeat
                if LineLp.Get(PostedWhseShipmentLine."Whse Shipment Line No.", LpNo) then begin
                    LineSscc.Get(PostedWhseShipmentLine."Whse Shipment Line No.", Sscc);
                    PostedWhseShipmentLine."LP No." := LpNo;
                    PostedWhseShipmentLine.SSCC := Sscc;
                    PostedWhseShipmentLine.Modify(true);
                    MarkLpUsed(LpNo);
                end;
            until PostedWhseShipmentLine.Next() = 0;

        StampHeaders(WhseShipmentHeader."No.", PostedNo);

        if PrintPackingSlip then
            QueuePostedShipmentPrint(PostedNo);

        LogShipmentPosted(WhseShipmentHeader."No.", LineCount, LpCount + LineLp.Count());
    end;

    local procedure StampHeaders(WhseShipmentNo: Code[20]; PostedShipmentNo: Code[20])
    var
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
    begin
        LpPropagation.StampShipmentHeader(WhseShipmentNo);
        LpPropagation.StampPostedShipmentHeader(WhseShipmentNo, PostedShipmentNo);
    end;

    procedure PostSalesOrderShipAndInvoice(var SalesHeader: Record "Sales Header")
    var
        SalesPost: Codeunit "Sales-Post";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        SalesHeader.TestField("Document Type", SalesHeader."Document Type"::Order);
        OnBeforeShipSales(SalesHeader."No.");
        SalesHeader.Ship := true;
        SalesHeader.Invoice := true;
        SalesPost.Run(SalesHeader);
        OnAfterInvoiceSales(SalesHeader."No.");
        CustomDimensions.Add('docNo', SalesHeader."No.");
        Session.LogMessage('AdvWMS.Sales.ShipAndInvoice', StrSubstNo('Sales order %1 shipped and invoiced from mobile.', SalesHeader."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    procedure PostTransferShip(var TransferHeader: Record "Transfer Header")
    var
        TransferPostShipment: Codeunit "TransferOrder-Post Shipment";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        TransferPostShipment.Run(TransferHeader);
        CustomDimensions.Add('docNo', TransferHeader."No.");
        Session.LogMessage('AdvWMS.Transfer.Shipped', StrSubstNo('Transfer order %1 shipped from mobile.', TransferHeader."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    local procedure EnsureLpSscc(LpNo: Code[20]; var Sscc: Code[18])
    var
        LP: Record "DOPSWHS LP Header";
        Generator: Codeunit "DOPSWHS SSCC Generator";
    begin
        LP.Get(LpNo);
        if LP.SSCC = '' then begin
            LP.SSCC := Generator.Generate();
            LP.Modify(true);
        end;
        Sscc := LP.SSCC;
    end;

    local procedure EnsureAssignedShipmentLpsHaveSscc(ShipmentNo: Code[20]; var LpCount: Integer)
    var
        LP: Record "DOPSWHS LP Header";
        Sscc: Code[18];
    begin
        LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::WhseShipment);
        LP.SetRange("Assigned Document No.", ShipmentNo);
        if LP.FindSet(true) then
            repeat
                LpCount += 1;
                EnsureLpSscc(LP."No.", Sscc);
            until LP.Next() = 0;
    end;

    local procedure MarkLpUsed(LpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if not LP.Get(LpNo) then
            exit;
        LP.Status := LP.Status::Used;
        LP.Modify(true);
    end;

    local procedure QueuePostedShipmentPrint(PostedShipmentNo: Code[20])
    var
        ReportSelection: Record "DOPSWHS IWX Report Selection";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        if PostedShipmentNo = '' then
            exit;
        ReportSelection.SetRange(Usage, ReportSelection.Usage::PostedShipment);
        if ReportSelection.FindFirst() then
            PrintDispatcher.QueueReport(PostedShipmentNo, ReportSelection."Report ID");
    end;

    local procedure LogShipmentPosted(DocNo: Code[20]; LineCount: Integer; LpCount: Integer)
    var
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('docNo', DocNo);
        CustomDimensions.Add('lineCount', Format(LineCount));
        CustomDimensions.Add('lpCount', Format(LpCount));
        Session.LogMessage('AdvWMS.Shipment.Posted', StrSubstNo('Warehouse shipment %1 posted from mobile.', DocNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    var
        NoShipmentLinesErr: Label 'Warehouse shipment %1 has no lines.', Comment = '%1 = Warehouse Shipment No.';
        PickNotCreatedErr: Label 'No warehouse pick was created for shipment %1. Check bin content and available quantity.', Comment = '%1 = Warehouse Shipment No.';

    [BusinessEvent(false)]
    local procedure OnBeforeShipSales(SalesOrderNo: Code[20])
    begin
    end;

    [BusinessEvent(false)]
    local procedure OnAfterInvoiceSales(SalesOrderNo: Code[20])
    begin
    end;
}
