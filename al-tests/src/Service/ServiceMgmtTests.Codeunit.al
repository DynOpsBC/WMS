// NOT: Bu test codeunit'i yerel bir BC AL derleyicisi olmadan yazıldı (.NET 8 runtime /
// BC sembol paketi bu ortamda mevcut değil — al/src/Service/* altındaki her dosyanın
// başında aynı uyarı var). Merge öncesi VS Code + AL eklentisiyle (veya varsa bir CI AL
// derleme/test adımıyla) mutlaka derlenip çalıştırılarak doğrulanmalı.
//
// Ayrıca: bu paketteki "Assert" / "Library Assert" codeunit'leri (al-tests/src/
// TestLibraryStubs.Codeunit.al, codeunit 72490/72491) boş gövdeli stub'lardır — bütün
// paket genelinde (bu dosya dahil) Assert.* çağrıları şu an gerçek bir doğrulama YAPMAZ,
// sadece niyeti belgeler. Testlerin gerçek değeri asserterror + doğrudan prosedür
// çağrılarının/event subscriber'ların ilgili kod yollarını gerçekten tetiklemesinden
// geliyor. Bu, bu dosyaya özgü değil — mevcut 40+ test dosyasının tamamında aynı durum.
//
// BİLİNEN BOŞLUK (bu testler tarafından ortaya çıkarıldı, düzeltilmedi — kapsam dışı):
// "DOPSWHS Work Order Svc".PostPartsConsumption sabit 'DOPSWHS-WO' adlı bir Item Journal
// Batch kullanıyor ama uygulama hiçbir yerde bu batch'i oluşturmuyor (Setup Wizard'da da
// yok). WorkOrderCompletePostsPartsConsumptionAndMarksLinePosted testi bu yüzden batch'i
// kendi içinde (üretim kodundaki EnsureJournalTemplate ile AYNI arama mantığıyla) önceden
// oluşturuyor — gerçek bir kurulumda bu adım eksikse Complete() bir Part satırıyla
// çağrıldığında "Journal Batch DOPSWHS-WO does not exist" ile patlar.
codeunit 72142 "DOPSWHS Service Mgmt Tests"
{
    Subtype = Test;

    // ------------------------------------------------------------------
    // Work Order lifecycle (DOPSWHS Work Order Svc)
    // ------------------------------------------------------------------

    [Test]
    procedure WorkOrderLifecycleCreateAssignStartCompleteClose()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        Assert: Codeunit Assert;
        WoNo: Code[20];
    begin
        CreateAsset('ASSET-SM-1');

        WoNo := WorkOrderSvc.Create('ASSET-SM-1', '', Enum::"DOPSWHS Maintenance Type"::Corrective, '', Enum::"DOPSWHS Fault Severity"::High);
        WorkOrder.Get(WoNo);
        Assert.AreEqual(WorkOrder.Status::Open, WorkOrder.Status, 'Newly created work order must start Open.');
        Assert.AreNotEqual(0DT, WorkOrder."Opened At", 'Create must stamp Opened At.');

        WorkOrderSvc.Assign(WorkOrder, 'TECH1');
        Assert.AreEqual(WorkOrder.Status::Assigned, WorkOrder.Status, 'Assign must move status to Assigned.');
        Assert.AreEqual('TECH1', WorkOrder."Assigned To", 'Assign must stamp Assigned To.');

        WorkOrderSvc.Start(WorkOrder);
        Assert.AreEqual(WorkOrder.Status::"In Progress", WorkOrder.Status, 'Start must move status to In Progress.');
        Assert.AreNotEqual(0DT, WorkOrder."Responded At", 'Start must stamp Responded At the first time.');

        WorkOrderSvc.Complete(WorkOrder, 'Bearing worn out', 'Replaced bearing, tested OK');
        Assert.AreEqual(WorkOrder.Status::Completed, WorkOrder.Status, 'Complete must move status to Completed.');
        Assert.AreEqual('Bearing worn out', WorkOrder."Root Cause", 'Complete must persist the root cause.');

        WorkOrderSvc.Close(WorkOrder);
        Assert.AreEqual(WorkOrder.Status::Closed, WorkOrder.Status, 'Close must move status to Closed.');
        Assert.AreNotEqual(0DT, WorkOrder."Closed At", 'Close must stamp Closed At.');
    end;

    [Test]
    procedure WorkOrderCreateDerivesSLATargetsFromContract()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        Assert: Codeunit Assert;
        ContractNo: Code[20];
        WoNo: Code[20];
        ExpectedResponseBy: DateTime;
        ExpectedResolutionBy: DateTime;
    begin
        CreateAsset('ASSET-SM-2');
        ContractNo := CreateContractWithSLA('ASSET-SM-2', 4, 24);  // 4h response / 24h resolution

        WoNo := WorkOrderSvc.Create('ASSET-SM-2', ContractNo, Enum::"DOPSWHS Maintenance Type"::Corrective, '', Enum::"DOPSWHS Fault Severity"::Medium);
        WorkOrder.Get(WoNo);

        ExpectedResponseBy := WorkOrder."Opened At" + (4 * 3600000);
        ExpectedResolutionBy := WorkOrder."Opened At" + (24 * 3600000);
        Assert.AreEqual(ExpectedResponseBy, WorkOrder."Target Response By", 'Target Response By must be Opened At + SLA response hours.');
        Assert.AreEqual(ExpectedResolutionBy, WorkOrder."Target Resolution By", 'Target Resolution By must be Opened At + SLA resolution hours.');
    end;

    [Test]
    procedure WorkOrderStartFailsWhenNotAssigned()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        Assert: Codeunit Assert;
        WoNo: Code[20];
    begin
        // Start() sadece Assigned veya Waiting Parts'tan izin verir; taze bir Open iş
        // emrinde doğrudan Start çağırmak InvalidTransitionErr ile reddedilmeli.
        CreateAsset('ASSET-SM-3');
        WoNo := WorkOrderSvc.Create('ASSET-SM-3', '', Enum::"DOPSWHS Maintenance Type"::Corrective, '', Enum::"DOPSWHS Fault Severity"::Low);
        WorkOrder.Get(WoNo);

        asserterror WorkOrderSvc.Start(WorkOrder);
        Assert.ExpectedError(WoNo);
    end;

    [Test]
    procedure WorkOrderCompletePostsPartsConsumptionAndMarksLinePosted()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        WOLine: Record "DOPSWHS Work Order Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        Assert: Codeunit Assert;
        WoNo: Code[20];
    begin
        CreateAsset('ASSET-SM-4');
        SeedLocationBin('SVCLOC', 'SVCBIN');
        SeedItem('ITEM-SM-PART', 'PCS');
        EnsurePartsJournalBatchExists();

        WoNo := WorkOrderSvc.Create('ASSET-SM-4', '', Enum::"DOPSWHS Maintenance Type"::Corrective, '', Enum::"DOPSWHS Fault Severity"::Medium);
        WorkOrder.Get(WoNo);

        WOLine.Init();
        WOLine."Work Order No." := WoNo;
        WOLine."Line No." := 10000;
        WOLine.Type := WOLine.Type::Part;
        WOLine."Item No." := 'ITEM-SM-PART';
        WOLine.Quantity := 2;
        WOLine."Location Code" := 'SVCLOC';
        WOLine."Bin Code" := 'SVCBIN';
        WOLine.Posted := false;
        WOLine.Insert(true);

        WorkOrderSvc.Assign(WorkOrder, 'TECH2');
        WorkOrderSvc.Start(WorkOrder);
        WorkOrderSvc.Complete(WorkOrder, 'Consumable replaced', 'OK');

        WOLine.Get(WoNo, 10000);
        Assert.IsTrue(WOLine.Posted, 'Part line must be marked Posted after Complete posts consumption.');

        ItemLedgerEntry.SetRange("Item No.", 'ITEM-SM-PART');
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Consumption);
        Assert.IsFalse(ItemLedgerEntry.IsEmpty(), 'Completing the work order must post a consumption item ledger entry for the part.');
    end;

    // ------------------------------------------------------------------
    // SLA breach detection (DOPSWHS SLA Monitor -> WebhookMgmt.OnWorkOrderSLABreached)
    // ------------------------------------------------------------------

    [Test]
    procedure SLAMonitorFiresBreachEventForOverdueResponse()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        JobQueueEntry: Record "Job Queue Entry";
        SLAMonitor: Codeunit "DOPSWHS SLA Monitor";
        Assert: Codeunit Assert;
    begin
        ResetBreachCapture();
        CreateWorkOrderWithOverdueResponse(WorkOrder, 'ASSET-SM-5');

        SLAMonitor.Run(JobQueueEntry);

        Assert.IsTrue(BreachEventFired, 'SLA Monitor must fire OnWorkOrderSLABreached for a work order past its response target.');
        Assert.AreEqual(WorkOrder."No.", LastBreachedWorkOrderNo, 'Breach event must carry the correct work order no.');
        Assert.AreEqual('response', LastBreachType, 'Breach event must report the response breach type.');

        WorkOrder.Get(WorkOrder."No.");
        Assert.IsTrue(WorkOrder."SLA Breached", 'Work order must be flagged SLA Breached after the run.');
    end;

    [Test]
    procedure SLAMonitorFiresBreachEventForOverdueResolution()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        JobQueueEntry: Record "Job Queue Entry";
        SLAMonitor: Codeunit "DOPSWHS SLA Monitor";
        Assert: Codeunit Assert;
    begin
        ResetBreachCapture();
        CreateWorkOrderWithOverdueResolution(WorkOrder, 'ASSET-SM-6');

        SLAMonitor.Run(JobQueueEntry);

        Assert.IsTrue(BreachEventFired, 'SLA Monitor must fire OnWorkOrderSLABreached for a work order past its resolution target.');
        Assert.AreEqual(WorkOrder."No.", LastBreachedWorkOrderNo, 'Breach event must carry the correct work order no.');
        Assert.AreEqual('resolution', LastBreachType, 'Breach event must report the resolution breach type.');
    end;

    [Test]
    procedure SLAMonitorDoesNotFireWhenWithinSLA()
    var
        WorkOrder: Record "DOPSWHS Work Order";
        JobQueueEntry: Record "Job Queue Entry";
        SLAMonitor: Codeunit "DOPSWHS SLA Monitor";
        Assert: Codeunit Assert;
    begin
        ResetBreachCapture();
        CreateAsset('ASSET-SM-7');
        WorkOrder.Init();
        WorkOrder.Status := WorkOrder.Status::Open;
        WorkOrder."Asset No." := 'ASSET-SM-7';
        WorkOrder."Target Response By" := CurrentDateTime() + 3600000;    // 1h in the future
        WorkOrder."Target Resolution By" := CurrentDateTime() + 86400000; // 24h in the future
        WorkOrder.Insert(true);

        SLAMonitor.Run(JobQueueEntry);

        Assert.IsFalse(BreachEventFired, 'SLA Monitor must not fire the breach event for a work order still within its SLA targets.');
        WorkOrder.Get(WorkOrder."No.");
        Assert.IsFalse(WorkOrder."SLA Breached", 'Work order within SLA must not be flagged SLA Breached.');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"DOPSWHS Webhook Mgmt", 'OnWorkOrderSLABreached', '', false, false)]
    local procedure OnWorkOrderSLABreachedSubscriber(WorkOrderNo: Code[20]; BreachType: Text[50])
    begin
        BreachEventFired := true;
        LastBreachedWorkOrderNo := WorkOrderNo;
        LastBreachType := BreachType;
    end;

    // ------------------------------------------------------------------
    // Maintenance Scheduler (DOPSWHS Maintenance Scheduler)
    // ------------------------------------------------------------------

    [Test]
    procedure MaintenanceSchedulerCreatesPreventiveWorkOrderWhenDueDatePassed()
    var
        Plan: Record "DOPSWHS Maintenance Plan";
        WorkOrder: Record "DOPSWHS Work Order";
        JobQueueEntry: Record "Job Queue Entry";
        Scheduler: Codeunit "DOPSWHS Maintenance Scheduler";
        Assert: Codeunit Assert;
    begin
        CreateAsset('ASSET-SM-8');
        CreateMaintenancePlan(Plan, 'PLAN-SM-8', 'ASSET-SM-8', CalcDate('<-1D>', Today), 30);

        Scheduler.Run(JobQueueEntry);

        WorkOrder.SetRange("Asset No.", 'ASSET-SM-8');
        WorkOrder.SetRange("Maintenance Type", WorkOrder."Maintenance Type"::Preventive);
        Assert.IsFalse(WorkOrder.IsEmpty(), 'Scheduler must auto-create a preventive work order for a plan whose due date has passed.');
    end;

    [Test]
    procedure MaintenanceSchedulerSkipsWhenOpenPreventiveWorkOrderAlreadyExists()
    var
        Plan: Record "DOPSWHS Maintenance Plan";
        WorkOrder: Record "DOPSWHS Work Order";
        JobQueueEntry: Record "Job Queue Entry";
        WorkOrderSvc: Codeunit "DOPSWHS Work Order Svc";
        Scheduler: Codeunit "DOPSWHS Maintenance Scheduler";
        Assert: Codeunit Assert;
        ExistingCount: Integer;
    begin
        // HasOpenPreventiveWorkOrder guard'ı: aynı asset için zaten açık bir preventive iş
        // emri varsa, süresi geçmiş bir plan olsa bile ikinci bir tane açılmamalı.
        CreateAsset('ASSET-SM-9');
        WorkOrderSvc.Create('ASSET-SM-9', '', Enum::"DOPSWHS Maintenance Type"::Preventive, '', Enum::"DOPSWHS Fault Severity"::Low);
        WorkOrder.SetRange("Asset No.", 'ASSET-SM-9');
        ExistingCount := WorkOrder.Count();

        CreateMaintenancePlan(Plan, 'PLAN-SM-9', 'ASSET-SM-9', CalcDate('<-1D>', Today), 30);
        Scheduler.Run(JobQueueEntry);

        WorkOrder.SetRange("Asset No.", 'ASSET-SM-9');
        Assert.AreEqual(ExistingCount, WorkOrder.Count(), 'Scheduler must not open a second preventive work order while one is already open for the asset.');
    end;

    // ------------------------------------------------------------------
    // Local helpers (inline test data — no dependency on production demo seeders)
    // ------------------------------------------------------------------

    var
        BreachEventFired: Boolean;
        LastBreachedWorkOrderNo: Code[20];
        LastBreachType: Text[50];

    local procedure ResetBreachCapture()
    begin
        Clear(BreachEventFired);
        Clear(LastBreachedWorkOrderNo);
        Clear(LastBreachType);
    end;

    local procedure CreateAsset(AssetNo: Code[20])
    var
        Asset: Record "DOPSWHS Service Asset";
    begin
        if Asset.Get(AssetNo) then
            exit;
        Asset.Init();
        Asset."No." := AssetNo;
        Asset.Description := CopyStr('SM test asset ' + AssetNo, 1, MaxStrLen(Asset.Description));
        Asset.Insert(true);
    end;

    local procedure CreateContractWithSLA(CoveredAssetNo: Code[20]; ResponseHours: Decimal; ResolutionHours: Decimal): Code[20]
    var
        SLA: Record "DOPSWHS Service SLA";
        Contract: Record "DOPSWHS Service Contract";
        SLACode: Code[20];
        ContractNo: Code[20];
    begin
        SLACode := CopyStr('SLA-' + CoveredAssetNo, 1, 20);
        if not SLA.Get(SLACode) then begin
            SLA.Init();
            SLA."Code" := SLACode;
            SLA."Response Time (Hours)" := ResponseHours;
            SLA."Resolution Time (Hours)" := ResolutionHours;
            SLA.Insert(true);
        end;

        ContractNo := CopyStr('CTR-' + CoveredAssetNo, 1, 20);
        if not Contract.Get(ContractNo) then begin
            Contract.Init();
            Contract."No." := ContractNo;
            Contract."Covered Asset No." := CoveredAssetNo;
            Contract."SLA Code" := SLACode;
            Contract.Insert(true);
        end;
        exit(ContractNo);
    end;

    local procedure CreateMaintenancePlan(var Plan: Record "DOPSWHS Maintenance Plan"; PlanNo: Code[20]; AssetNo: Code[20]; NextDueDate: Date; IntervalDays: Integer)
    begin
        if Plan.Get(PlanNo) then
            Plan.Delete(true);
        Plan.Init();
        Plan."No." := PlanNo;
        Plan."Asset No." := AssetNo;
        Plan."Maintenance Type" := Plan."Maintenance Type"::Preventive;
        Plan."Interval (Days)" := IntervalDays;
        Plan."Next Due Date" := NextDueDate;
        Plan.Enabled := true;
        Plan.Insert(true);
    end;

    local procedure CreateWorkOrderWithOverdueResponse(var WorkOrder: Record "DOPSWHS Work Order"; AssetNo: Code[20])
    begin
        CreateAsset(AssetNo);
        WorkOrder.Init();
        WorkOrder.Status := WorkOrder.Status::Open;
        WorkOrder."Asset No." := AssetNo;
        WorkOrder."Target Response By" := CurrentDateTime() - 3600000;     // 1h overdue
        WorkOrder."Target Resolution By" := 0DT;
        WorkOrder."SLA Breached" := false;
        WorkOrder.Insert(true);
    end;

    local procedure CreateWorkOrderWithOverdueResolution(var WorkOrder: Record "DOPSWHS Work Order"; AssetNo: Code[20])
    begin
        CreateAsset(AssetNo);
        WorkOrder.Init();
        WorkOrder.Status := WorkOrder.Status::"In Progress";  // dışında Open/Assigned -> ilk (response) filtresine girmez
        WorkOrder."Asset No." := AssetNo;
        WorkOrder."Target Response By" := CurrentDateTime() - 7200000;    // zaten karşılanmış varsayılır (Responded At ile birlikte)
        WorkOrder."Responded At" := CurrentDateTime() - 7200000;
        WorkOrder."Target Resolution By" := CurrentDateTime() - 3600000;  // 1h overdue
        WorkOrder."SLA Breached" := false;
        WorkOrder.Insert(true);
    end;

    local procedure EnsurePartsJournalBatchExists()
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        // "DOPSWHS Work Order Svc".PostPartsConsumption ile AYNI arama mantığı (bkz. dosya
        // başı NOT) — hangi template'in kullanılacağını production koduyla tutarlı şekilde
        // belirleyip eksik olan 'DOPSWHS-WO' batch'ini burada tamamlıyoruz.
        ItemJournalTemplate.SetRange(Type, ItemJournalTemplate.Type::Item);
        if not ItemJournalTemplate.FindFirst() then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'ITEM';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::Item;
            ItemJournalTemplate.Insert(true);
        end;
        if not ItemJournalBatch.Get(ItemJournalTemplate.Name, 'DOPSWHS-WO') then begin
            ItemJournalBatch.Init();
            ItemJournalBatch."Journal Template Name" := ItemJournalTemplate.Name;
            ItemJournalBatch.Name := 'DOPSWHS-WO';
            ItemJournalBatch.Insert(true);
        end;
    end;

    local procedure SeedItem(ItemNo: Code[20]; UoM: Code[10])
    var
        Item: Record Item;
    begin
        if not Item.Get(ItemNo) then begin
            Item.Init();
            Item."No." := ItemNo;
            Item.Description := ItemNo;
            Item."Base Unit of Measure" := UoM;
            Item.Insert(true);
        end;
    end;

    local procedure SeedLocationBin(LocationCode: Code[10]; BinCode: Code[20])
    var
        Location: Record Location;
        Bin: Record Bin;
    begin
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not Bin.Get(LocationCode, BinCode) then begin
            Bin.Init();
            Bin."Location Code" := LocationCode;
            Bin.Code := BinCode;
            Bin.Insert(true);
        end;
    end;
}
