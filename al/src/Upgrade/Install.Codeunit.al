codeunit 72033 "DOPSWHS Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    var
        Setup: Record "DOPSWHS Setup";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        SetupWizard.SeedSprint1Defaults();
    end;
}
