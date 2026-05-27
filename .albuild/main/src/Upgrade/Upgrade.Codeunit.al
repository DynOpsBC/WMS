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
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        if not Cue.Get('') then begin
            Cue.Init();
            Cue.Insert(true);
        end;
    end;

    local procedure RunDatabaseMigrations()
    var
        MigrationMap: Record "DOPSWHS Migration Map WI";
    begin
        MigrationMap.InsertDefaultMappings();
    end;
}
