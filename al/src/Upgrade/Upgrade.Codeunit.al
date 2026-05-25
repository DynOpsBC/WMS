codeunit 72034 "DOPSWHS Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerDatabase()
    begin
    end;

    trigger OnUpgradePerCompany()
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
    end;
}

