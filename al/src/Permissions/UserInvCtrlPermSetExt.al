permissionsetextension 72001 "DOPSWHS-USER Inv Ctrl" extends "DOPSWHS-USER"
{
    // Kitoko (Kas 2026): warehouse users inspect (pass/fail) quality orders,
    // create them from receipts/assembly orders and run the cycle count plan.
    // Rules and the approver list are read-only for them (DOPSWHS-INV-CTRL
    // maintains them).
    Permissions =
        tabledata "DOPSWHS Quality Order" = RIM,
        tabledata "DOPSWHS Quality Rule" = R,
        tabledata "DOPSWHS Inventory Approver" = R,
        table "DOPSWHS Quality Order" = X,
        table "DOPSWHS Quality Rule" = X,
        table "DOPSWHS Inventory Approver" = X,
        page "DOPSWHS Quality Order API" = X,
        page "DOPSWHS Quality Orders" = X,
        page "DOPSWHS Quality Order Card" = X,
        page "DOPSWHS Quality Result Dialog" = X,
        page "DOPSWHS Quality Rules" = X,
        page "DOPSWHS Cycle Count Plan" = X,
        codeunit "DOPSWHS Quality Mgmt" = X,
        codeunit "DOPSWHS Quality Gate Mgmt" = X,
        codeunit "DOPSWHS Quality Lot Hold" = X,
        codeunit "DOPSWHS Quality Decision Mgmt" = X,
        codeunit "DOPSWHS Count Tolerance Mgmt" = X,
        codeunit "DOPSWHS Cycle Count Mgmt" = X,
        codeunit "DOPSWHS Reclass Control" = X;
}
