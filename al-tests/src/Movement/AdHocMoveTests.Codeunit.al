codeunit 72117 "DOPSWHS AdHoc Move Tests"
{
    Subtype = Test;

    [Test]
    procedure BinToBinMoveUsesDeviceBatch()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        Setup: Record "DOPSWHS Setup";
        ItemJournalBatch: Record "Item Journal Batch";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        BatchName: Code[10];
    begin
        Setup := TestHelper.EnsureSetup();
        Setup."Default Location Code" := 'BLUE';
        Setup.Modify(true);

        BatchName := MovementMgmt.EnsureDeviceJournalBatch('USER1');

        ItemJournalBatch.SetRange(Name, BatchName);
        Assert.IsFalse(ItemJournalBatch.IsEmpty(), 'Ad-hoc move must create or reuse the user-specific reclass journal batch.');
    end;

    [Test]
    procedure LpMoveSetsPackageNoOnJournalLine()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        Setup: Record "DOPSWHS Setup";
        ItemJournalLine: Record "Item Journal Line";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        BatchName: Code[10];
    begin
        Setup := TestHelper.EnsureSetup();
        Setup."Default Location Code" := 'BLUE';
        Setup.Modify(true);

        BatchName := MovementMgmt.EnsureDeviceJournalBatch('LPUSER');
        MovementMgmt.AdHocMove('RECEIVE', 'PUT-01', 'ITEM-S4-MOVE', 'LP-S4-MOVE', 1, 'LPUSER');

        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetRange("Package No.", 'LP-S4-MOVE');
        Assert.IsFalse(ItemJournalLine.IsEmpty(), 'LP No. must be carried to the item reclass journal line package field.');
    end;

    [Test]
    procedure SalesOrderReferenceUsesOrderAndLogsSeparateNumber()
    var
        SalesHeader: Record "Sales Header";
        Entry: Record "DOPSWHS Project Move Entry";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
    begin
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := 'E4-WMS-TEST.R1';
        SalesHeader.Insert(false);
        MovementMgmt.CheckMoveSalesOrder(SalesHeader."No.");

        MovementMgmt.LogSalesOrderMove('TEST', 'FROM', 'TO', 'TEST-ITEM', '', 'LOT1', '', 2, SalesHeader."No.", 'WMS-TEST', '');
        Entry.SetRange("Sales Order No.", SalesHeader."No.");
        Entry.SetRange("User ID", 'WMS-TEST');
        Assert.IsTrue(Entry.FindLast(), 'The history must be searchable by sales order number.');
        Assert.AreEqual('', Entry."Project No.", 'A sales order number must have its own field.');
        Assert.AreEqual(2, Entry.Quantity, 'The movement quantity must be preserved.');
        Assert.AreEqual('LOT1', Entry."Lot No.", 'The movement lot must be preserved.');
    end;

    [Test]
    procedure SalesOrderMovementRejectsQuoteAndNonE4Number()
    var
        SalesHeader: Record "Sales Header";
        Ops: Page "DOPSWHS Movement Ops API";
    begin
        SalesHeader."Document Type" := SalesHeader."Document Type"::Quote;
        SalesHeader."No." := 'E4-WMS-QUOTE';
        SalesHeader.Insert(false);

        asserterror Ops.adHocSalesOrder('', '', '', '', 1, 'WMS-TEST', '', SalesHeader."No.");
        Assert.ExpectedError('bağlı Business Central şirketinde bulunamadı');
        asserterror Ops.adHocSalesOrder('', '', '', '', 1, 'WMS-TEST', '', 'SO-WMS-TEST');
        Assert.ExpectedError('E4 ile başlayan');
    end;

    var
        Assert: Codeunit Assert;
        LibraryWarehouse: Codeunit "Library - Warehouse";
        LibraryInventory: Codeunit "Library - Inventory";
}
