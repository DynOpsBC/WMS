codeunit 72001 "DOPSWHS Maintenance Scheduler"
{
    // NOT: Bu codeunit bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    // SM-05: Job Queue ile periyodik çalışıp süresi gelen (Next Due Date <= bugün)
    // etkin bakım planları için otomatik Work Order açar.

    Subtype = Normal;
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        Plan: Record "DOPSWHS Maintenance Plan";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        CustomDimensions: Dictionary of [Text, Text];
        NewWorkOrderNo: Code[20];
    begin
        Plan.SetRange(Enabled, true);
        Plan.SetFilter("Next Due Date", '<=%1&<>%2', Today, 0D);
        if not Plan.FindSet() then
            exit;

        repeat
            if not HasOpenPreventiveWorkOrder(Plan."Asset No.") then begin
                NewWorkOrderNo := WorkOrderSvc.Create(
                    Plan."Asset No.", '', Plan."Maintenance Type", '', Enum::"DOPSWHS Fault Severity"::Medium);
                Session.LogMessage('DOPSWHS-Maint-AutoWO', StrSubstNo('Auto-created %1 for asset %2 from plan %3', NewWorkOrderNo, Plan."Asset No.", Plan."No."),
                    Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
            end;
        until Plan.Next() = 0;
    end;

    local procedure HasOpenPreventiveWorkOrder(AssetNo: Code[20]): Boolean
    var
        WorkOrder: Record "DOPSWHS Work Order";
    begin
        WorkOrder.SetRange("Asset No.", AssetNo);
        WorkOrder.SetRange("Maintenance Type", WorkOrder."Maintenance Type"::Preventive);
        WorkOrder.SetFilter(Status, '%1|%2|%3|%4', WorkOrder.Status::Open, WorkOrder.Status::Assigned, WorkOrder.Status::"In Progress", WorkOrder.Status::"Waiting Parts");
        exit(not WorkOrder.IsEmpty());
    end;
}
