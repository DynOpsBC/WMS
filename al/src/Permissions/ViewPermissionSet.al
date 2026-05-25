permissionset 72096 "DOPSWHS-VIEW"
{
    Assignable = true;
    Caption = 'Advanced WMS View';

    Permissions =
        tabledata "DOPSWHS Setup" = R,
        tabledata "DOPSWHS Device Configuration" = R,
        tabledata "DOPSWHS Device Menu" = R,
        tabledata "DOPSWHS Device Column" = R,
        tabledata "DOPSWHS Device Registration" = R,
        tabledata "DOPSWHS Barcode Rule" = R,
        tabledata "DOPSWHS Barcode Symbology" = R,
        tabledata "DOPSWHS Telemetry Buffer" = R,
        table "DOPSWHS Setup" = X,
        table "DOPSWHS Device Configuration" = X,
        table "DOPSWHS Device Menu" = X,
        table "DOPSWHS Device Column" = X,
        table "DOPSWHS Device Registration" = X,
        table "DOPSWHS Barcode Rule" = X,
        table "DOPSWHS Barcode Symbology" = X,
        table "DOPSWHS Telemetry Buffer" = X,
        page "DOPSWHS Setup" = X,
        page "DOPSWHS Device Config Card" = X,
        page "DOPSWHS Device Config List" = X,
        page "DOPSWHS Device Menu List" = X,
        page "DOPSWHS Device Column List" = X,
        page "DOPSWHS Device Registration List" = X,
        page "DOPSWHS Barcode Rule List" = X,
        page "DOPSWHS Symbology List" = X,
        page "DOPSWHS LP Factbox Item" = X,
        page "DOPSWHS LP Factbox Bin" = X,
        page "DOPSWHS Item API" = X,
        page "DOPSWHS Bin API" = X,
        page "DOPSWHS Device API" = X,
        page "DOPSWHS Barcode Parse API" = X,
        codeunit "DOPSWHS Barcode Parser" = X,
        codeunit "DOPSWHS GS1 AI Parser" = X;
}
