permissionset 72095 "DOPSWHS-USER"
{
    Assignable = true;
    Caption = 'Advanced WMS User';

    Permissions =
        tabledata "DOPSWHS Setup" = R,
        tabledata "DOPSWHS Device Configuration" = R,
        tabledata "DOPSWHS Device Menu" = R,
        tabledata "DOPSWHS Device Column" = R,
        tabledata "DOPSWHS Device Registration" = RIMD,
        tabledata "DOPSWHS Barcode Rule" = R,
        tabledata "DOPSWHS Barcode Symbology" = R,
        tabledata "DOPSWHS Telemetry Buffer" = RIMD,
        table "DOPSWHS Setup" = X,
        table "DOPSWHS Device Configuration" = X,
        table "DOPSWHS Device Menu" = X,
        table "DOPSWHS Device Column" = X,
        table "DOPSWHS Device Registration" = X,
        table "DOPSWHS Barcode Rule" = X,
        table "DOPSWHS Barcode Symbology" = X,
        table "DOPSWHS Telemetry Buffer" = X,
        page "DOPSWHS Setup" = X,
        page "DOPSWHS LP Factbox Item" = X,
        page "DOPSWHS LP Factbox Bin" = X,
        page "DOPSWHS Item API" = X,
        page "DOPSWHS Bin API" = X,
        page "DOPSWHS Device API" = X,
        page "DOPSWHS Barcode Parse API" = X,
        codeunit "DOPSWHS Barcode Parser" = X,
        codeunit "DOPSWHS GS1 AI Parser" = X,
        codeunit "DOPSWHS Device Auth" = X,
        codeunit "DOPSWHS Telemetry" = X,
        codeunit "DOPSWHS Permission Helper" = X;
}
