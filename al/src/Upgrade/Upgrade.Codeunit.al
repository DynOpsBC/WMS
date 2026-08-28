codeunit 72034 "DOPSWHS Upgrade"
{
    Subtype = Upgrade;
    Permissions =
        tabledata "Lot No. Information" = rm,
        tabledata "DOPSWHS LP Header" = rm,
        tabledata "DOPSWHS LP Line" = r,
        tabledata "Warehouse Receipt Line" = r,
        tabledata "Posted Whse. Receipt Line" = rm,
        tabledata "Posted Whse. Receipt Header" = r,
        tabledata "Warehouse Activity Line" = r,
        tabledata "Warehouse Entry" = rm,
        tabledata "Item Ledger Entry" = rm,
        tabledata "Value Entry" = rm;

    trigger OnUpgradePerDatabase()
    var
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        if ModuleInfo.DataVersion() < Version.Create(1, 0, 0, 0) then
            RunDatabaseMigrations();
    end;

    /// <summary>
    /// Upgrade trigger now only refreshes singleton master rows, default
    /// roles, assisted-setup checklist, and v1.10 print-channel migration.
    /// Demo data, smoke test rows, quality demo orders and the auto-test-run
    /// (`Runner.CreateNewRun('TEST'...) / StartRun`) were removed in v1.10
    /// because they leaked into production tenants and polluted customer
    /// environments. Sandbox bootstrap is now an explicit action on the
    /// Setup card.
    /// </summary>
    trigger OnUpgradePerCompany()
    var
        Setup: Record "DOPSWHS Setup";
        Cue: Record "DOPSWHS Warehouse Mgr Cue";
        AppProfileMgmt: Codeunit "DOPSWHS App Profile Mgmt";
        AppRoleSeed: Codeunit "DOPSWHS App Role Seed";
        ConfigChecker: Codeunit "DOPSWHS Config Checker";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        PrintCleanup: Codeunit "DOPSWHS Print Queue Cleanup";
        AzurePrintWorker: Codeunit "DOPSWHS Azure Print Worker";
        ModuleInfo: ModuleInfo;
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        if not Cue.Get('') then begin
            Cue.Init();
            Cue.Insert(true);
        end;
        MigratePrintChannelDefault(Setup);
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        if ModuleInfo.DataVersion() < Version.Create(1, 13, 0, 0) then
            EnableExistingPrintersForBcReports();
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 0) then
            ApplyAzureDirectDefaults(Setup);
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 9) then
            RepairPackingOrderFlowModes();
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 22) then
            MigrateSupplierLotToDescription();
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 54) then
            RepairReceiptLpBins();
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 83) then begin
            RepairReceiptLpAssignments();
            RepairReceiptLpCurrentBins();
        end;
        if ModuleInfo.DataVersion() < Version.Create(1, 14, 0, 85) then
            RepairOpenPutAwaysByReceiptLps();
        AppProfileMgmt.SeedDefaults();          // seed DEFAULT app profile + install-user profile
        AppRoleSeed.Seed();                     // seed system roles + starter filter rules
        SetupWizard.SeedReportSelections();     // repair legacy empty/wrong document print routes
        ConfigChecker.RegisterAssistedSetup();  // seed config checklist + register Assisted Setup
        ScheduleLicenseVerify();                // seed/refresh the hourly /verify job
        PrintCleanup.ScheduleCleanupJob();      // seed daily print payload retention cleanup
        AzurePrintWorker.ScheduleWorkerJob();  // instant tasks use this as durable fallback/status pump
    end;

    /// <summary>
    /// v1.14.0.84 and earlier created one aggregated put-away movement even when
    /// the receipt had been distributed over several physical LPs. Reshape only
    /// still-open, untouched receipt put-aways; failures are isolated per document
    /// so one manually changed legacy activity cannot block the app upgrade.
    /// </summary>
    local procedure RepairOpenPutAwaysByReceiptLps()
    var
        ActivityLine: Record "Warehouse Activity Line";
        PostedReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedReceipts: Dictionary of [Code[20], Boolean];
        PostedReceiptNo: Code[20];
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type"::Receipt);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.SetRange("Qty. Handled", 0);
        ActivityLine.SetRange("LP No.", '');
        if ActivityLine.FindSet() then
            repeat
                if (ActivityLine."Whse. Document No." <> '') and
                   (not PostedReceipts.ContainsKey(ActivityLine."Whse. Document No."))
                then
                    PostedReceipts.Add(ActivityLine."Whse. Document No.", true);
            until ActivityLine.Next() = 0;

        foreach PostedReceiptNo in PostedReceipts.Keys do
            if PostedReceiptHeader.Get(PostedReceiptNo) then
                if PostedReceiptHeader."Whse. Receipt No." <> '' then
                    TrySplitOpenPutAway(
                        PostedReceiptHeader."Whse. Receipt No.",
                        PostedReceiptHeader."No.");
    end;

    [TryFunction]
    local procedure TrySplitOpenPutAway(ReceiptNo: Code[20]; PostedReceiptNo: Code[20])
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        ReceiptMgmt.SplitPutAwayByReceiptLPs(ReceiptNo, PostedReceiptNo);
    end;

    /// <summary>
    /// Older builds copied the receipt header's first LP onto every posted
    /// lot. Re-run the deterministic source-line + lot/serial resolver so
    /// existing posted receipt, warehouse, item and value entries are repaired.
    /// Ambiguous matches are never guessed.
    /// </summary>
    local procedure RepairReceiptLpAssignments()
    var
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        ReceiptByPostedNo: Dictionary of [Code[20], Code[20]];
        PostedReceiptNo: Code[20];
        WhseReceiptNo: Code[20];
    begin
        PostedReceiptLine.SetFilter("Whse. Receipt No.", '<>%1', '');
        if PostedReceiptLine.FindSet() then
            repeat
                if not ReceiptByPostedNo.ContainsKey(PostedReceiptLine."No.") then
                    ReceiptByPostedNo.Add(PostedReceiptLine."No.", PostedReceiptLine."Whse. Receipt No.");
            until PostedReceiptLine.Next() = 0;

        foreach PostedReceiptNo in ReceiptByPostedNo.Keys do begin
            ReceiptByPostedNo.Get(PostedReceiptNo, WhseReceiptNo);
            LpPropagation.StampPostedReceiptLines(WhseReceiptNo, PostedReceiptNo);
            LpPropagation.StampPostedReceiptHeader(WhseReceiptNo, PostedReceiptNo);
            LpPropagation.StampPostedReceiptLedgerEntries(PostedReceiptNo, '');
        end;
    end;

    /// <summary>
    /// After receipt/put-away entry LP fields are repaired, derive each physical
    /// LP's current bin from the net warehouse-entry balance. Source receipt bins
    /// net to zero after put-away; exactly one positive bin is therefore safe.
    /// </summary>
    local procedure RepairReceiptLpCurrentBins()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ProcessedLps: Dictionary of [Code[20], Boolean];
        CurrentBinCode: Code[20];
    begin
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if not ProcessedLps.ContainsKey(LPLine."LP No.") then begin
                    ProcessedLps.Add(LPLine."LP No.", true);
                    LP.Get(LPLine."LP No.");
                    CurrentBinCode := ResolveWarehouseLpCurrentBin(LP."No.");
                    if (CurrentBinCode <> '') and (LP."Bin Code" <> CurrentBinCode) then begin
                        LP.Validate("Bin Code", CurrentBinCode);
                        LP.Modify(true);
                    end;
                end;
            until LPLine.Next() = 0;
    end;

    local procedure ResolveWarehouseLpCurrentBin(LpNo: Code[20]): Code[20]
    var
        WarehouseEntry: Record "Warehouse Entry";
        QuantityByBin: Dictionary of [Code[20], Decimal];
        ExistingQuantity: Decimal;
        BinCode: Code[20];
        CandidateBinCode: Code[20];
    begin
        WarehouseEntry.SetRange("DOPSWHS LP No.", LpNo);
        WarehouseEntry.SetFilter("Bin Code", '<>%1', '');
        if WarehouseEntry.FindSet() then
            repeat
                Clear(ExistingQuantity);
                if QuantityByBin.Get(WarehouseEntry."Bin Code", ExistingQuantity) then
                    QuantityByBin.Set(
                        WarehouseEntry."Bin Code",
                        ExistingQuantity + WarehouseEntry."Qty. (Base)")
                else
                    QuantityByBin.Add(WarehouseEntry."Bin Code", WarehouseEntry."Qty. (Base)");
            until WarehouseEntry.Next() = 0;

        foreach BinCode in QuantityByBin.Keys do begin
            QuantityByBin.Get(BinCode, ExistingQuantity);
            if ExistingQuantity > 0.00001 then begin
                if CandidateBinCode <> '' then
                    exit('');
                CandidateBinCode := BinCode;
            end;
        end;
        exit(CandidateBinCode);
    end;

    /// <summary>
    /// Older mobile receipt builds created the LP before a bin was known and
    /// never copied the receipt-line bin afterwards. Repair only records for
    /// which one unambiguous bin can be proved; ambiguous LPs remain untouched.
    /// </summary>
    local procedure RepairReceiptLpBins()
    var
        LP: Record "DOPSWHS LP Header";
        BinCode: Code[20];
    begin
        LP.SetRange("Bin Code", '');
        if LP.FindSet(true) then
            repeat
                BinCode := ResolveReceiptLpBin(LP."No.");
                if BinCode <> '' then begin
                    LP.Validate("Bin Code", BinCode);
                    LP.Modify(true);
                end;
            until LP.Next() = 0;
    end;

    local procedure ResolveReceiptLpBin(LpNo: Code[20]): Code[20]
    var
        LPLine: Record "DOPSWHS LP Line";
        ReceiptLine: Record "Warehouse Receipt Line";
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        WarehouseEntry: Record "Warehouse Entry";
        CandidateBin: Code[20];
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Source Document Type", LPLine."Source Document Type"::WhseReceipt);
        if LPLine.FindSet() then
            repeat
                if LPLine."Source Bin Code" <> '' then
                    if not AddUniqueBin(CandidateBin, LPLine."Source Bin Code") then
                        exit('');
                if ReceiptLine.Get(LPLine."Source Document No.", LPLine."Source Document Line No.") then
                    if not AddUniqueBin(CandidateBin, ReceiptLine."Bin Code") then
                        exit('');
            until LPLine.Next() = 0;
        if CandidateBin <> '' then
            exit(CandidateBin);

        PostedReceiptLine.SetRange("LP No.", LpNo);
        PostedReceiptLine.SetFilter("Bin Code", '<>%1', '');
        if PostedReceiptLine.FindSet() then
            repeat
                if not AddUniqueBin(CandidateBin, PostedReceiptLine."Bin Code") then
                    exit('');
            until PostedReceiptLine.Next() = 0;
        if CandidateBin <> '' then
            exit(CandidateBin);

        WarehouseEntry.SetRange("DOPSWHS LP No.", LpNo);
        WarehouseEntry.SetFilter("Bin Code", '<>%1', '');
        if WarehouseEntry.FindSet() then
            repeat
                if not AddUniqueBin(CandidateBin, WarehouseEntry."Bin Code") then
                    exit('');
            until WarehouseEntry.Next() = 0;
        exit(CandidateBin);
    end;

    local procedure AddUniqueBin(var CandidateBin: Code[20]; NewBin: Code[20]): Boolean
    begin
        if NewBin = '' then
            exit(true);
        if CandidateBin = '' then begin
            CandidateBin := NewBin;
            exit(true);
        end;
        exit(CandidateBin = NewBin);
    end;

    /// <summary>
    /// v1.14.0.21 ve öncesinde terminal tedarikçi lotunu ayrı bir BCWMS
    /// alanına yazıyordu. BadeProduction'ın mevcut alanı Lot No.
    /// Information.Description olduğundan, yalnızca hedef boşken eski mobil
    /// değerini taşı. Her iki alan dolu ve farklıysa mevcut Bade değeri
    /// korunur; sessiz veri ezilmez. Eski alan geri dönüş için tabloda kalır.
    /// </summary>
    local procedure MigrateSupplierLotToDescription()
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        LotNoInformation.SetRange(Description, '');
        LotNoInformation.SetFilter("DOPSWHS Supplier Lot No.", '<>%1', '');
        if LotNoInformation.FindSet(true) then
            repeat
                LotNoInformation.Validate(
                    Description,
                    CopyStr(
                        LotNoInformation."DOPSWHS Supplier Lot No.",
                        1,
                        MaxStrLen(LotNoInformation.Description)));
                LotNoInformation.Modify(true);
            until LotNoInformation.Next() = 0;
    end;

    local procedure ApplyAzureDirectDefaults(var Setup: Record "DOPSWHS Setup")
    begin
        Setup.ApplyAzureDefaults();
        Setup.Modify(true);
    end;

    local procedure EnableExistingPrintersForBcReports()
    var
        Printer: Record "DOPSWHS Printer";
    begin
        Printer.SetRange(Active, true);
        Printer.SetRange("Format", Printer."Format"::PDF);
        if not Printer.IsEmpty() then
            Printer.ModifyAll("Enable BC Reports", true, false);
    end;

    // V2 paketleme listeleri akış moduna göre filtrelenir. Eski sürümlerde
    // bazı paketleme satırlarının modu boş kaldığı için bu satırlar klasik
    // listede görünüyor, V2'de kayboluyordu. Tamamlanmış toplama grubu
    // kaydından modu geri doldur; kaynağı bulunamayan standart pick'lere
    // tahmini bir mod atama.
    local procedure RepairPackingOrderFlowModes()
    var
        PackingOrder: Record "DOPSWHS Packing Order";
        PickingHeader: Record "DOPSWHS Picking Order Header";
    begin
        PackingOrder.SetRange("Order Flow Mode", PackingOrder."Order Flow Mode"::" ");
        if PackingOrder.FindSet(true) then
            repeat
                PickingHeader.Reset();
                PickingHeader.SetRange("Warehouse Pick No.", PackingOrder."Pick No.");
                if PickingHeader.FindFirst() then begin
                    // Eski genel "Toplanacak Siparişler" ekranı grubu mod
                    // damgası olmadan oluşturabiliyor, fakat warehouse pick'i
                    // her durumda Multi olarak damgalıyordu. Bu nedenle grup
                    // var + mod boş kombinasyonunun geriye dönük karşılığı Multi.
                    if PickingHeader."Order Flow Mode" = PickingHeader."Order Flow Mode"::" " then
                        PackingOrder."Order Flow Mode" := PackingOrder."Order Flow Mode"::Multi
                    else
                        PackingOrder."Order Flow Mode" := PickingHeader."Order Flow Mode";
                    PackingOrder.Modify(false);
                end;
            until PackingOrder.Next() = 0;
    end;

    local procedure ScheduleLicenseVerify()
    var
        License: Codeunit "DOPSWHS License Mgmt";
    begin
        License.ScheduleVerifyJob();
    end;

    /// <summary>
    /// Pre-v1.10 tenants that never explicitly set a Print Channel default to
    /// enum value 0 (PrintNode), but they never configured a PrintNode API
    /// key so jobs piled up un-sent. Map the still-default 0 to BCNative on
    /// the v1.10 upgrade — the old SaaS behaviour was to fall through to
    /// Report.Run anyway. Customers who explicitly switched to PrintNode or
    /// SelfHosted keep their choice.
    /// </summary>
    local procedure MigratePrintChannelDefault(var Setup: Record "DOPSWHS Setup")
    begin
        if Setup."Print Channel" <> Setup."Print Channel"::PrintNode then exit;
        if Setup."PrintNode API Key Set" then exit;
        Setup."Print Channel" := Setup."Print Channel"::BCNative;
        Setup.Modify(true);
    end;

    local procedure RunDatabaseMigrations()
    var
        MigrationMap: Record "DOPSWHS Migration Map WI";
    begin
        MigrationMap.InsertDefaultMappings();
    end;
}
