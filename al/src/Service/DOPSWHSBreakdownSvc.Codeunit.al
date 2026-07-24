codeunit 72003 "DOPSWHS Breakdown Svc"
{
    // NOT: Bu codeunit bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    //
    // SM-08: mobilden/web'den gelen arıza bildirimini alıp otomatik "Corrective" tipte
    // Work Order açar. Öteki WMS servis codeunit'leriyle aynı çağrı deseni (bkz. DOPSWHS
    // Pick Mgmt/Receipt Mgmt) — ActionDispatcher benzeri bir mobil dispatcher bu repoda
    // bulunmadığından (bu app doğrudan API sayfaları kullanıyor), mobil erişim SM-09
    // kapsamında ayrı bir API page (DOPSWHS Breakdown API) ile sağlanmalı.

    Access = Public;

    procedure ReportBreakdown(AssetNo: Code[20]; FaultCodeValue: Code[20]; Notes: Text[250]): Code[20]
    var
        FaultCode: Record "DOPSWHS Fault Code";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        SeverityValue: Enum "DOPSWHS Fault Severity";
        NewWorkOrderNo: Code[20];
        WorkOrder: Record "DOPSWHS Work Order";
    begin
        SeverityValue := SeverityValue::Medium;
        if (FaultCodeValue <> '') and FaultCode.Get(FaultCodeValue) then
            SeverityValue := FaultCode."Default Severity";

        NewWorkOrderNo := WorkOrderSvc.Create(AssetNo, '', Enum::"DOPSWHS Maintenance Type"::Corrective, FaultCodeValue, SeverityValue);

        if (Notes <> '') and WorkOrder.Get(NewWorkOrderNo) then begin
            WorkOrder."Resolution Notes" := Notes;  // bildirim anındaki notlar; çözüm notu Complete()'te üzerine yazılabilir.
            WorkOrder.Modify(true);
        end;

        exit(NewWorkOrderNo);
    end;
}
