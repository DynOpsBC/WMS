codeunit 72133 "DOPSWHS Receipt With LP Tests"
{
    Subtype = Test;

    [Test]
    procedure ReceiptLpContentIsCreatedOnlyBySuccessfulPost()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        LpNo: Code[20];
    begin
        TestHelper.EnsureSetup();
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-S3-LP', 30);

        LpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(LpNo, WhseReceiptHeader."DOPSWHS LP No.", 'Started LP must immediately be linked to the receipt header.');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        // Same PATCH is retried and then edited. Before posting, the LP must
        // remain an empty draft carrying only the final planned quantity.
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 5, '', '', 0D, LpNo, 'RECEIVE');
        LPLine.SetRange("LP No.", LpNo);
        Assert.IsTrue(LPLine.IsEmpty(), 'Confirming a draft receipt must not put item, lot or quantity inside the LP.');
        LP.Get(LpNo);
        Assert.AreEqual(5, LP."Planned Quantity", 'The empty draft LP must retain only its final planned quantity.');
        Assert.AreEqual(WhseReceiptLine."No.", LP."Pending Receipt No.", 'The empty LP must remain linked to its pending receipt.');
        asserterror ReceiptMgmt.StopLP(WhseReceiptHeader, LpNo, false);
        Assert.ExpectedError('Mal Kabulü Kaydet');

        ReceiptMgmt.PostReceipt(WhseReceiptHeader, false, false);

        LPLine.Reset();
        LPLine.SetRange("LP No.", LpNo);
        LPLine.FindFirst();
        Assert.AreEqual(30, LPLine."Source Document Quantity", 'Posted LP line must retain the total receipt-line quantity for MTE printing.');
        Assert.AreEqual(5, LPLine.Quantity, 'Successful posting must materialize the final receipt quantity once.');
        Assert.AreEqual(1, LPLine.Count(), 'Successful posting must create exactly one physical LP line.');
        Assert.AreEqual(WhseReceiptLine."No.", LPLine."Source Document No.", 'Posted LP line must retain its receipt reference.');
        LP.Get(LpNo);
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Successful posting must close the materialized LP.');
        Assert.AreEqual('', LP."Pending Receipt No.", 'A posted LP must no longer be pending.');
        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(LpNo, PostedWhseReceiptLine."LP No.", 'Posted receipt line must keep LP No.');
    end;

    [Test]
    procedure StartAfterClosingEmptyLpCreatesNextLp()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        FirstLP: Record "DOPSWHS LP Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        FirstLpNo: Code[20];
        SecondLpNo: Code[20];
    begin
        TestHelper.EnsureSetup();
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-LP-RESTART', 20);

        FirstLpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        ReceiptMgmt.StopLP(WhseReceiptHeader, FirstLpNo, false);
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(FirstLpNo, WhseReceiptHeader."DOPSWHS LP No.", 'Closing an LP must preserve the receipt LP pointer for reopening.');

        SecondLpNo := ReceiptMgmt.StartLP(WhseReceiptHeader, 'PALLET-EUR');
        Assert.AreNotEqual(FirstLpNo, SecondLpNo, 'Starting after a physically closed LP must create the next LP.');
        FirstLP.Get(FirstLpNo);
        Assert.AreEqual(Format(FirstLP.Status::Built), Format(FirstLP.Status), 'The physically closed LP must stay built.');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(SecondLpNo, WhseReceiptHeader."DOPSWHS LP No.", 'The receipt must point to the newly opened LP.');
    end;

    [Test]
    procedure BulkReceiptCountsOnlyCurrentBuiltPalletsOnTheSingleSourceLine()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-BULK-ONE-LINE', 100);
        CreateReceiptLP('LP-BULK-01', WhseReceiptLine, 50, true);
        CreateReceiptLP('LP-BULK-02', WhseReceiptLine, 50, true);
        // Önceki kısmi kabulden kalan atanmış LP yeni dalgaya katılmamalı.
        CreateReceiptLP('LP-BULK-OLD', WhseReceiptLine, 25, false);

        Assert.AreEqual(
            2,
            ReceiptMgmt.BulkLpCountForReceiptLine(WhseReceiptLine),
            'Two physical LPs must stay attached to one unchanged receipt line.');
    end;

    [Test]
    procedure CancelledReceiptRemovesItsUnpostedLpQuantity()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-LP', 50);
        CreateReceiptLP('LP-CANCEL-01', WhseReceiptLine, 50, true);

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-01');
        Assert.AreEqual(Format(LP.Status::Unbuilt), Format(LP.Status), 'Cancelled receipt LP must be unbuilt.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'Cancelled receipt must not leave quantity inside its LP.');
    end;

    [Test]
    procedure CancelledReceiptClearsItsEmptyPendingLp()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-DRAFT', 50);
        LP.Init();
        LP."No." := 'LP-CANCEL-DRAFT';
        LP.Status := LP.Status::Open;
        LP."Planned Quantity" := 50;
        LP."Pending Receipt No." := WhseReceiptHeader."No.";
        LP."Pending Receipt Line No." := WhseReceiptLine."Line No.";
        LP.Insert();

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-DRAFT');
        Assert.AreEqual(Format(LP.Status::Unbuilt), Format(LP.Status), 'Cancelled draft LP must be unbuilt.');
        Assert.AreEqual(0, LP."Planned Quantity", 'Cancelled draft LP must not retain a planned stock quantity.');
        Assert.AreEqual('', LP."Pending Receipt No.", 'Cancelled draft LP must not retain a receipt reference.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsTrue(LPLine.IsEmpty(), 'Cancelled draft LP must remain empty.');
    end;

    [Test]
    procedure CancelledReceiptNeverChangesAssignedLp()
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-CANCEL-SAFE', 50);
        CreateReceiptLP('LP-CANCEL-02', WhseReceiptLine, 50, false);

        ReceiptMgmt.CleanupCanceledReceiptLPs(WhseReceiptHeader."No.");

        LP.Get('LP-CANCEL-02');
        Assert.AreEqual(Format(LP.Status::Assigned), Format(LP.Status), 'Posted or assigned LP must never be changed by receipt cancellation.');
        LPLine.SetRange("LP No.", LP."No.");
        Assert.IsFalse(LPLine.IsEmpty(), 'Assigned LP quantity must remain intact.');
    end;

    local procedure CreateReceiptLP(LpNo: Code[20]; ReceiptLine: Record "Warehouse Receipt Line"; Qty: Decimal; IsCurrent: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
    begin
        LP.Init();
        LP."No." := LpNo;
        if IsCurrent then
            LP.Status := LP.Status::Built
        else
            LP.Status := LP.Status::Assigned;
        LP.Insert();

        LPLine.Init();
        LPLine."LP No." := LpNo;
        LPLine."Line No." := 10000;
        LPLine."Item No." := ReceiptLine."Item No.";
        LPLine."Variant Code" := ReceiptLine."Variant Code";
        LPLine."Unit of Measure" := ReceiptLine."Unit of Measure Code";
        LPLine.Quantity := Qty;
        LPLine."Source Document Type" := LPLine."Source Document Type"::WhseReceipt;
        LPLine."Source Document No." := ReceiptLine."No.";
        LPLine."Source Document Line No." := ReceiptLine."Line No.";
        LPLine.Insert();
    end;

    local procedure CreateReceipt(var Header: Record "Warehouse Receipt Header"; var Line: Record "Warehouse Receipt Line"; SourceNo: Code[20]; Qty: Decimal)
    begin
        Header.Init();
        Header."No." := SourceNo + '-RCPT';
        Header."Location Code" := 'BLUE';
        Header.Insert(true);

        Line.Init();
        Line."No." := Header."No.";
        Line."Line No." := 10000;
        Line."Source No." := SourceNo;
        Line."Item No." := 'ITEM-S3';
        Line.Description := 'Sprint 3 LP receipt item';
        Line."Unit of Measure Code" := 'PCS';
        Line.Quantity := Qty;
        Line."Qty. to Receive" := Qty;
        Line."Bin Code" := 'RECEIVE';
        Line.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
