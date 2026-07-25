codeunit 72002 "DOPSWHS Work Order Svc"
{
    // NOT: Bu codeunit bu ortamda derlenmedi (BC sembol paketi/sandbox erişimi yok).
    // Merge öncesi VS Code + AL derleyicisiyle veya bir BC sandbox'ta doğrulanmalı.
    //
    // SM-07: iş emri yaşam döngüsü (Create/Assign/Start/Complete/Close) + parça tüketiminin
    // Item Journal'a postalanması (Codeunit 22/23 deseni — WMS'in geri kalanıyla tutarlı,
    // bkz. DOPSWHS Movement Mgmt).

    Access = Public;

    var
        InvalidTransitionErr: Label 'Cannot transition Work Order %1 from %2 to %3.', Comment = '%1 = no., %2 = current, %3 = target';

    /// <summary>Manuel veya otomatik (Scheduler/Breakdown Svc) iş emri açar; SLA'dan hedef
    /// müdahale/kapanış zamanlarını türetir.</summary>
    procedure Create(AssetNo: Code[20]; ContractNo: Code[20]; MaintenanceTypeValue: Enum "DOPSWHS Maintenance Type"; FaultCodeValue: Code[20]; PriorityValue: Enum "DOPSWHS Fault Severity"): Code[20]
    var
        WorkOrder: Record "DOPSWHS Work Order";
        Contract: Record "DOPSWHS Service Contract";
        SLA: Record "DOPSWHS Service SLA";
    begin
        WorkOrder.Init();
        WorkOrder."Asset No." := AssetNo;
        WorkOrder."Contract No." := ContractNo;
        WorkOrder."Maintenance Type" := MaintenanceTypeValue;
        WorkOrder."Fault Code" := FaultCodeValue;
        WorkOrder.Priority := PriorityValue;
        WorkOrder.Status := WorkOrder.Status::Open;
        WorkOrder.Insert(true);

        if (ContractNo <> '') and Contract.Get(ContractNo) and (Contract."SLA Code" <> '') and SLA.Get(Contract."SLA Code") then begin
            WorkOrder."Target Response By" := WorkOrder."Opened At" + (SLA."Response Time (Hours)" * 3600000);
            WorkOrder."Target Resolution By" := WorkOrder."Opened At" + (SLA."Resolution Time (Hours)" * 3600000);
            WorkOrder.Modify(true);
        end;

        exit(WorkOrder."No.");
    end;

    procedure Assign(var WorkOrder: Record "DOPSWHS Work Order"; UserIdValue: Code[50])
    begin
        RequireStatus(WorkOrder, WorkOrder.Status::Open);
        WorkOrder."Assigned To" := UserIdValue;
        WorkOrder.Status := WorkOrder.Status::Assigned;
        WorkOrder.Modify(true);
    end;

    procedure Start(var WorkOrder: Record "DOPSWHS Work Order")
    begin
        if not (WorkOrder.Status in [WorkOrder.Status::Assigned, WorkOrder.Status::"Waiting Parts"]) then
            Error(InvalidTransitionErr, WorkOrder."No.", WorkOrder.Status, WorkOrder.Status::"In Progress");
        if WorkOrder."Responded At" = 0DT then
            WorkOrder."Responded At" := CurrentDateTime();
        WorkOrder.Status := WorkOrder.Status::"In Progress";
        WorkOrder.Modify(true);
    end;

    /// <summary>İş emrini tamamlar: bekleyen (Posted=false) parça satırlarını Item Journal'a
    /// postalar, kök neden/çözüm notlarını kaydeder.</summary>
    procedure Complete(var WorkOrder: Record "DOPSWHS Work Order"; RootCause: Text[250]; ResolutionNotes: Text[250])
    begin
        RequireStatus(WorkOrder, WorkOrder.Status::"In Progress");
        PostPartsConsumption(WorkOrder."No.");

        WorkOrder."Root Cause" := RootCause;
        WorkOrder."Resolution Notes" := ResolutionNotes;
        WorkOrder.Status := WorkOrder.Status::Completed;
        WorkOrder.Modify(true);

        UpdateAssetLastCompleted(WorkOrder);
    end;

    procedure Close(var WorkOrder: Record "DOPSWHS Work Order")
    begin
        RequireStatus(WorkOrder, WorkOrder.Status::Completed);
        WorkOrder.Status := WorkOrder.Status::Closed;
        WorkOrder."Closed At" := CurrentDateTime();
        WorkOrder.Modify(true);
    end;

    local procedure RequireStatus(var WorkOrder: Record "DOPSWHS Work Order"; ExpectedStatus: Enum "DOPSWHS Work Order Status")
    begin
        if WorkOrder.Status <> ExpectedStatus then
            Error(InvalidTransitionErr, WorkOrder."No.", WorkOrder.Status, ExpectedStatus);
    end;

    local procedure PostPartsConsumption(WorkOrderNo: Code[20])
    var
        WOLine: Record "DOPSWHS Work Order Line";
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        ItemJournalTemplate: Record "Item Journal Template";
        LineNo: Integer;
    begin
        WOLine.SetRange("Work Order No.", WorkOrderNo);
        WOLine.SetRange(Type, WOLine.Type::Part);
        WOLine.SetRange(Posted, false);
        if not WOLine.FindSet() then
            exit;

        EnsureJournalTemplate(ItemJournalTemplate);

        repeat
            LineNo += 10000;
            ItemJournalLine.Init();
            ItemJournalLine."Journal Template Name" := ItemJournalTemplate.Name;
            ItemJournalLine."Journal Batch Name" := 'DOPSWHS-WO';
            ItemJournalLine."Line No." := LineNo;
            ItemJournalLine.Validate("Posting Date", Today);
            ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::Consumption);
            ItemJournalLine.Validate("Item No.", WOLine."Item No.");
            ItemJournalLine.Validate("Location Code", WOLine."Location Code");
            ItemJournalLine.Validate(Quantity, WOLine.Quantity);
            ItemJournalLine.Description := CopyStr(StrSubstNo('WO %1 parça tüketimi', WorkOrderNo), 1, MaxStrLen(ItemJournalLine.Description));
            ItemJnlPostBatch.Run(ItemJournalLine);

            WOLine.Posted := true;
            WOLine.Modify(true);
        until WOLine.Next() = 0;
    end;

    local procedure EnsureJournalTemplate(var ItemJournalTemplate: Record "Item Journal Template")
    begin
        // Diğer WMS modülleriyle aynı desen (bkz. DOPSWHS Movement Mgmt.EnsureReclassTemplate):
        // ilgili şablon yoksa transient oluşturulur, bir batch job/API context'inde onay
        // diyaloğu tetiklemeden postalanabilsin diye.
        ItemJournalTemplate.SetRange(Type, ItemJournalTemplate.Type::Item);
        if not ItemJournalTemplate.FindFirst() then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'ITEM';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::Item;
            ItemJournalTemplate.Insert(true);
        end;
    end;

    local procedure UpdateAssetLastCompleted(WorkOrder: Record "DOPSWHS Work Order")
    var
        Plan: Record "DOPSWHS Maintenance Plan";
    begin
        if WorkOrder."Maintenance Type" <> WorkOrder."Maintenance Type"::Preventive then
            exit;
        Plan.SetRange("Asset No.", WorkOrder."Asset No.");
        Plan.SetRange(Enabled, true);
        if Plan.FindFirst() then begin
            Plan."Last Completed Date" := Today;
            Plan."Next Due Date" := CalcDate(StrSubstNo('<+%1D>', Plan."Interval (Days)"), Today);
            Plan.Modify(true);
        end;
    end;
}
