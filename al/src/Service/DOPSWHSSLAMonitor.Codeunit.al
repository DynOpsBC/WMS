codeunit 72000 "DOPSWHS SLA Monitor"
{
    // NOT: Bu codeunit bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    //
    // SM-03: Job Queue ile periyodik çalışıp açık iş emirlerini SLA hedeflerine göre
    // kontrol eder, ihlal varsa "SLA Breached" işaretler ve webhook fan-out'a event basar
    // (mevcut DOPSWHS Webhook Mgmt kullanılıyor — WMS'in geri kalanıyla tutarlı).

    Subtype = Normal;
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        WebhookMgmt: Codeunit "DOPSWHS Webhook Mgmt";
        Now: DateTime;
    begin
        Now := CurrentDateTime();

        WorkOrder.SetFilter(Status, '%1|%2', WorkOrder.Status::Open, WorkOrder.Status::Assigned);
        WorkOrder.SetFilter("Target Response By", '<%1&<>%2', Now, 0DT);
        WorkOrder.SetRange("SLA Breached", false);
        if WorkOrder.FindSet(true) then
            repeat
                WorkOrder."SLA Breached" := true;
                WorkOrder.Modify(true);
                WebhookMgmt.OnWorkOrderSLABreached(WorkOrder."No.", 'response');
            until WorkOrder.Next() = 0;

        WorkOrder.Reset();
        WorkOrder.SetFilter(Status, '%1|%2|%3', WorkOrder.Status::Open, WorkOrder.Status::Assigned, WorkOrder.Status::"In Progress");
        WorkOrder.SetFilter("Target Resolution By", '<%1&<>%2', Now, 0DT);
        WorkOrder.SetRange("SLA Breached", false);
        if WorkOrder.FindSet(true) then
            repeat
                WorkOrder."SLA Breached" := true;
                WorkOrder.Modify(true);
                WebhookMgmt.OnWorkOrderSLABreached(WorkOrder."No.", 'resolution');
            until WorkOrder.Next() = 0;
    end;
}
