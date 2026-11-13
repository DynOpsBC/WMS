permissionset 72000 "DOPSWHS-INV-CTRL"
{
    // Kitoko (Kas 2026), KIT-009/010/014/015, INV-009/010: quality and
    // inventory control supervisor. Maintains the quality inspection rules and
    // the inventory control approver list, executes quality decisions. Whether
    // a user may approve count variances / post reclassification journals is
    // decided by the approver list itself (Advanced WMS Setup switches).
    Assignable = true;
    Caption = 'Advanced WMS Inventory Control';
    IncludedPermissionSets = "DOPSWHS-USER";

    Permissions =
        tabledata "DOPSWHS Quality Order" = RIMD,
        tabledata "DOPSWHS Quality Rule" = RIMD,
        tabledata "DOPSWHS Inventory Approver" = RIMD,
        table "DOPSWHS Quality Order" = X,
        table "DOPSWHS Quality Rule" = X,
        table "DOPSWHS Inventory Approver" = X,
        page "DOPSWHS Quality Orders" = X,
        page "DOPSWHS Quality Order Card" = X,
        page "DOPSWHS Quality Result Dialog" = X,
        page "DOPSWHS Quality Rules" = X,
        page "DOPSWHS Inventory Approvers" = X,
        page "DOPSWHS Cycle Count Plan" = X,
        codeunit "DOPSWHS Quality Gate Mgmt" = X,
        codeunit "DOPSWHS Quality Lot Hold" = X,
        codeunit "DOPSWHS Quality Decision Mgmt" = X,
        codeunit "DOPSWHS Count Tolerance Mgmt" = X,
        codeunit "DOPSWHS Cycle Count Mgmt" = X,
        codeunit "DOPSWHS Reclass Control" = X;
}
