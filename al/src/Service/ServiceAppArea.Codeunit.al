/// <summary>
/// Turns the DOPSWHSService application area on while Service Terminal Setup is enabled.
/// Role center links to the service pages are tagged with it, because role centers cannot
/// decide visibility in code.
/// </summary>
codeunit 72104 "DOPSWHS Service App Area"
{
    Access = Internal;
    // The subscriber runs in the session of whoever resets the experience tier (often an admin
    // without BCWMS permissions); it must still see the real setup value.
    InherentEntitlements = X;
    InherentPermissions = X;
    Permissions = tabledata "DOPSWHS Service Setup" = R;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Application Area Mgmt. Facade", 'OnGetEssentialExperienceAppAreas', '', false, false)]
    local procedure EnableOnEssential(var TempApplicationAreaSetup: Record "Application Area Setup" temporary)
    begin
        // Premium includes Essential, so this covers both experiences.
        TempApplicationAreaSetup."DOPSWHS Service" := IsServiceEnabled();
    end;

    /// <summary>
    /// Recalculates the company's application areas when they no longer match the setup.
    /// Silently skipped for users who may not change the application area setup.
    /// </summary>
    procedure Sync()
    var
        ApplicationAreaSetup: Record "Application Area Setup";
        ApplicationAreaMgmtFacade: Codeunit "Application Area Mgmt. Facade";
        Active: Boolean;
    begin
        if not ApplicationAreaSetup.WritePermission() then
            exit;
        if ApplicationAreaMgmtFacade.GetApplicationAreaSetupRecFromCompany(ApplicationAreaSetup, CompanyName()) then
            Active := ApplicationAreaSetup."DOPSWHS Service";
        if Active = IsServiceEnabled() then
            exit;
        ApplicationAreaMgmtFacade.RefreshExperienceTierCurrentCompany();
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Setup", 'R')]
    local procedure IsServiceEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Service Setup";
    begin
        // An admin without a BCWMS permission set must not get an error from this subscriber.
        if not Setup.ReadPermission() then
            exit(false);
        if not Setup.Get() then
            exit(false);
        exit(Setup.Enabled);
    end;
}
