permissionsetextension 72002 "DOPSWHS-VIEW Inv Ctrl" extends "DOPSWHS-VIEW"
{
    // Kitoko (Kas 2026): read-only access to quality and inventory control data.
    Permissions =
        tabledata "DOPSWHS Quality Order" = R,
        tabledata "DOPSWHS Quality Rule" = R,
        table "DOPSWHS Quality Order" = X,
        table "DOPSWHS Quality Rule" = X,
        page "DOPSWHS Quality Orders" = X,
        page "DOPSWHS Quality Order Card" = X,
        page "DOPSWHS Quality Rules" = X,
        codeunit "DOPSWHS Quality Lot Hold" = X,
        codeunit "DOPSWHS Quality Decision Mgmt" = X;
}
