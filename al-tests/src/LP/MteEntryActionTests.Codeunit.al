codeunit 72494 "DOPSWHS MTE Action Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Item Ledger Entry" = rimd;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LpCardMteUsesOnlyCurrentLp()
    var
        LP: Record "DOPSWHS LP Header";
        Card: TestPage "DOPSWHS LP Card";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-B', 'RT137-LOT-B', 2);
        LP.Get(ExpectedLp);
        Card.OpenView();
        Card.GoToRecord(LP);
        Card.PrintMteReport.Invoke();
        Card.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LpListMteUsesOnlyFilteredLp()
    var
        ListPage: TestPage "DOPSWHS LP List";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-B', 'RT137-LOT-B', 2);
        ListPage.OpenView();
        ListPage.Filter.SetFilter("No.", ExpectedLp);
        ListPage.PrintSelectedMteReports.Invoke();
        ListPage.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LedgerMteRejectsWrongLotSourceLink()
    var
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Entries: TestPage "Item Ledger Entries";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-A', 'RT137-LOT-B', 2);
        Entry."Entry No." := 2147483000;
        Entry."Item No." := 'RT137-ITEM-A';
        Entry."Lot No." := 'RT137-LOT-A';
        Entry.Insert(false);
        Line.SetRange("LP No.", ExpectedLp);
        Line.FindFirst();
        Line."Source Item Ledger Entry No." := Entry."Entry No.";
        Line.Modify(false);
        Line.Reset();
        Line.SetRange("LP No.", ForbiddenLp);
        Line.FindFirst();
        Line."Source Item Ledger Entry No." := Entry."Entry No.";
        Line.Modify(false);
        Entries.OpenView();
        Entries.GoToRecord(Entry);
        Entries."DOPSWHS Print All LP MTE".Invoke();
        Entries.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LedgerMteRejectsWrongLotInLegacyLpStamp()
    var
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Entries: TestPage "Item Ledger Entries";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-A', 'RT137-LOT-B', 2);
        Entry."Entry No." := 2147483000;
        Entry."Item No." := 'RT137-ITEM-A';
        Entry."Lot No." := 'RT137-LOT-A';
        // A legacy receipt can retain the wrong LP stamp even after the source lookup is filtered.
        Entry."DOPSWHS LP No." := ForbiddenLp;
        Entry.Insert(false);
        Line.SetRange("LP No.", ExpectedLp);
        Line.FindFirst();
        Line."Source Item Ledger Entry No." := Entry."Entry No.";
        Line.Modify(false);
        Entries.OpenView();
        Entries.GoToRecord(Entry);
        Entries."DOPSWHS Print All LP MTE".Invoke();
        Entries.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LedgerMteRejectsWrongLotInLegacyLpList()
    var
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Entries: TestPage "Item Ledger Entries";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-A', 'RT137-LOT-B', 2);
        Entry."Entry No." := 2147483000;
        Entry."Item No." := 'RT137-ITEM-A';
        Entry."Lot No." := 'RT137-LOT-A';
        Entry."DOPSWHS LP Nos." := ExpectedLp + ', ' + ForbiddenLp;
        Entry.Insert(false);
        Line.SetRange("LP No.", ExpectedLp);
        Line.FindFirst();
        Line."Source Item Ledger Entry No." := Entry."Entry No.";
        Line.Modify(false);
        Entries.OpenView();
        Entries.GoToRecord(Entry);
        Entries."DOPSWHS Print All LP MTE".Invoke();
        Entries.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LedgerMteKeepsCorrectLegacyLpStamp()
    var
        Entry: Record "Item Ledger Entry";
        Entries: TestPage "Item Ledger Entries";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        Entry."Entry No." := 2147483000;
        Entry."Item No." := 'RT137-ITEM-A';
        Entry."Lot No." := 'RT137-LOT-A';
        Entry."DOPSWHS LP No." := ExpectedLp;
        Entry.Insert(false);
        Entries.OpenView();
        Entries.GoToRecord(Entry);
        Entries."DOPSWHS Print All LP MTE".Invoke();
        Entries.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    [HandlerFunctions('MteReportHandler')]
    procedure LedgerMteRejectsWrongVariantStamp()
    var
        Entry: Record "Item Ledger Entry";
        Line: Record "DOPSWHS LP Line";
        Entries: TestPage "Item Ledger Entries";
    begin
        ExpectedLp := 'RT137-LP-A';
        ForbiddenLp := 'RT137-LP-B';
        CreateLp(ExpectedLp, 'RT137-ITEM-A', 'RT137-LOT-A', 1);
        CreateLp(ForbiddenLp, 'RT137-ITEM-A', 'RT137-LOT-A', 2);
        Line.Get(ForbiddenLp, 10000);
        Line."Variant Code" := 'OTHER';
        Line.Modify(false);
        Entry."Entry No." := 2147483000;
        Entry."Item No." := 'RT137-ITEM-A';
        Entry."Lot No." := 'RT137-LOT-A';
        Entry."DOPSWHS LP Nos." := ExpectedLp + ',' + ForbiddenLp;
        Entry.Insert(false);
        Entries.OpenView();
        Entries.GoToRecord(Entry);
        Entries."DOPSWHS Print All LP MTE".Invoke();
        Entries.Close();
    end;

    [RequestPageHandler]
    procedure MteReportHandler(var RequestPage: TestRequestPage "DOPSWHS MTE LP Report")
    var
        LpFilter: Text;
    begin
        LpFilter := RequestPage.LicensePlate.GetFilter("No.");
        if StrPos(LpFilter, ExpectedLp) = 0 then
            Error('Expected LP %1 missing from MTE filter %2.', ExpectedLp, LpFilter);
        if StrPos(LpFilter, ForbiddenLp) > 0 then
            Error('Wrong LP %1 entered MTE filter %2.', ForbiddenLp, LpFilter);
        RequestPage.Cancel().Invoke();
    end;

    local procedure CreateLp(LpNo: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        LP: Record "DOPSWHS LP Header";
        Line: Record "DOPSWHS LP Line";
        Item: Record Item;
    begin
        if not Item.Get(ItemNo) then begin
            Item.Init();
            Item."No." := ItemNo;
            Item.Description := 'RT137 MTE action fixture';
            Item.Insert(false);
        end;
        LP."No." := LpNo;
        LP.Status := LP.Status::Built;
        LP.Insert(false);
        Line."LP No." := LpNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo;
        Line."Lot No." := LotNo;
        Line."Unit of Measure" := 'ADET';
        Line.Quantity := Qty;
        Line.Insert(false);
    end;

    var
        ExpectedLp: Code[20];
        ForbiddenLp: Code[20];
}
