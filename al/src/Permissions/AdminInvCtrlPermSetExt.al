permissionsetextension 72000 "DOPSWHS-ADMIN Inv Ctrl" extends "DOPSWHS-ADMIN"
{
    // Kitoko (Kas 2026) quality & inventory control objects (IDs 72000-72010).
    Permissions =
        tabledata "DOPSWHS Quality Rule" = RIMD,
        table "DOPSWHS Quality Rule" = X,
        page "DOPSWHS Quality Orders" = X,
        page "DOPSWHS Quality Order Card" = X,
        page "DOPSWHS Quality Result Dialog" = X,
        page "DOPSWHS Quality Rules" = X,
        codeunit "DOPSWHS Quality Gate Mgmt" = X,
        codeunit "DOPSWHS Quality Lot Hold" = X,
        codeunit "DOPSWHS Quality Decision Mgmt" = X;
}
