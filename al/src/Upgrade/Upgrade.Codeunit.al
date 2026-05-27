codeunit 72034 "DOPSWHS Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerDatabase()
    var
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        if ModuleInfo.DataVersion() < Version.Create(1, 0, 0, 0) then
            RunDatabaseMigrations();
    end;

    trigger OnUpgradePerCompany()
    var
        Setup: Record "DOPSWHS Setup";
        Cue: Record "DOPSWHS Warehouse Mgr Cue";
        DemoSetup: Codeunit "DOPSWHS Demo Data Setup";
        DemoTx: Codeunit "DOPSWHS Demo Transactions";
        E2EData: Codeunit "DOPSWHS E2E Test Data";
        CatalogSeed: Codeunit "DOPSWHS Test Catalog Seed";
        Runner: Codeunit "DOPSWHS Test Runner";
        RunNo: Code[20];
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        if not Cue.Get('') then begin
            Cue.Init();
            Cue.Insert(true);
        end;
        // v1.0.4.0 upgrade auto-bootstrap: tum seed + ilk Test Run
        DemoSetup.RunFullDemoSetup();
        DemoTx.CreateAllDemoTransactions();
        E2EData.PrepareE2EData();
        CatalogSeed.RunFullSeed();
        RunNo := Runner.CreateNewRun('TEST', 'QA-TEAM', 'Auto-bootstrap on upgrade v1.0.4.0');
        Runner.StartRun(RunNo);
    end;

    local procedure RunDatabaseMigrations()
    var
        MigrationMap: Record "DOPSWHS Migration Map WI";
    begin
        MigrationMap.InsertDefaultMappings();
    end;
}
