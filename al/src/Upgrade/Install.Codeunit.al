codeunit 72033 "DOPSWHS Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    var
        Setup: Record "DOPSWHS Setup";
        Cue: Record "DOPSWHS Warehouse Mgr Cue";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        DemoSetup: Codeunit "DOPSWHS Demo Data Setup";
        DemoTx: Codeunit "DOPSWHS Demo Transactions";
        E2EData: Codeunit "DOPSWHS E2E Test Data";
        CatalogSeed: Codeunit "DOPSWHS Test Catalog Seed";
        PostingSmokeTest: Codeunit "DOPSWHS Posting Smoke Test";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        WebSvcPublisher: Codeunit "DOPSWHS Web Svc Publisher";
        ConfigChecker: Codeunit "DOPSWHS Config Checker";
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        if not Cue.Get('') then begin
            Cue.Init();
            Cue.Insert(true);
        end;
        SetupWizard.SeedSprint1Defaults();
        SetupWizard.SeedDefaultLPTemplates();
        // Fresh-install self-provisioning so a brand-new environment (e.g. SandboxUS) is test-ready.
        DemoSetup.RunFullDemoSetup();
        DemoTx.CreateAllDemoTransactions();
        E2EData.PrepareE2EData();
        CatalogSeed.RunFullSeed();
        PostingSmokeTest.EnsureRows();
        QualityMgmt.SeedDemoOrders();
        WebSvcPublisher.PublishAll();  // expose standard pages as web services for no-API operations
        ConfigChecker.RegisterAssistedSetup();  // seed config checklist + register Assisted Setup
    end;
}
