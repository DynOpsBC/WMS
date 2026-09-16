/// <summary>
/// Which customer line this package was built for. The lines (BASE on main,
/// BADE on customer/bade, EMU on customer/emu) share one app id and name, so
/// Business Central would happily "upgrade" a BADE tenant with an EMU package
/// (1.14.2.x > 1.14.1.x) and silently replace the customer's code. The upgrade
/// codeunit refuses when the company was stamped with a different edition.
/// Only the value returned by Current() differs between branches (16 Eyl 2026).
/// </summary>
codeunit 72322 "DOPSWHS Edition"
{
    Access = Public;
    Permissions = tabledata "DOPSWHS Setup" = RM;

    var
        WrongEditionErr: Label 'Bu ortamda BCWMS %1 sürümü kurulu; %2 paketi yüklenemez (şirket: %3). Her müşterinin kendi paketi vardır: BASE 1.14.0.x, BADE 1.14.1.x, EMU/DKÇ 1.14.2.x.', Comment = '%1 installed edition, %2 edition of this package, %3 company name';

    /// <summary>Edition compiled into this package.</summary>
    procedure Current(): Code[10]
    begin
        exit('BASE');
    end;

    /// <summary>Edition stamped on the company's Setup record ('' before the 16 Sep 2026 packages).</summary>
    procedure Installed(): Code[10]
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if Setup.Get('') then
            exit(Setup."Installed Edition");
        exit('');
    end;

    /// <summary>
    /// Raises an error when this package would replace another customer's
    /// edition. A blank stamp (older package) or BASE (uncustomised install)
    /// may be upgraded by any edition.
    /// </summary>
    procedure AssertCompatible()
    var
        InstalledEdition: Code[10];
    begin
        InstalledEdition := Installed();
        if (InstalledEdition = '') or (InstalledEdition = 'BASE') or (InstalledEdition = Current()) then
            exit;
        Error(WrongEditionErr, InstalledEdition, Current(), CompanyName());
    end;

    procedure Stamp(var Setup: Record "DOPSWHS Setup")
    begin
        if Setup."Installed Edition" = Current() then
            exit;
        Setup."Installed Edition" := Current();
        Setup.Modify();
    end;
}
