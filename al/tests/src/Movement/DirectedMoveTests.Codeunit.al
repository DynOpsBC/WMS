codeunit 72118 "DOPSWHS Directed Move Tests"
{
    Subtype = Test;

    [Test]
    procedure RegisterDirectedMovementCreatesWarehouseEntries()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        WhseActivityHeader: Record "Warehouse Activity Header";
        WarehouseEntry: Record "Warehouse Entry";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
    begin
        TestHelper.EnsureSetup();
        WhseActivityHeader.Init();
        WhseActivityHeader.Type := WhseActivityHeader.Type::Movement;
        WhseActivityHeader."No." := 'MV-S4-001';
        WhseActivityHeader."Location Code" := 'BLUE';
        WhseActivityHeader.Insert(true);

        MovementMgmt.RegisterDirected(WhseActivityHeader);

        WarehouseEntry.SetRange("Reference No.", WhseActivityHeader."No.");
        Assert.IsFalse(WarehouseEntry.IsEmpty(), 'Registering a directed movement must create warehouse entries.');
    end;

    var
        Assert: Codeunit Assert;
        LibraryWarehouse: Codeunit "Library - Warehouse";
        LibraryInventory: Codeunit "Library - Inventory";
}
