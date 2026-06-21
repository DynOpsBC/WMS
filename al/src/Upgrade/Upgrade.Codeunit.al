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
        AppProfileMgmt.SeedDefaults();          // seed DEFAULT app profile + install-user profile
        AppRoleSeed.Seed();                     // seed system roles + starter filter rules
        ConfigChecker.RegisterAssistedSetup();  // seed config checklist + register Assisted Setup
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
