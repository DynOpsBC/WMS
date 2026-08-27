codeunit 72133 "DOPSWHS Receipt With LP Tests"
{
    Subtype = Test;

    [Test]
    procedure StartScanStopPostKeepsLpOnPostedLine()
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
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 10, '', '', 0D, LpNo, 'RECEIVE');
        LPLine.SetRange("LP No.", LpNo);
        LPLine.FindFirst();
        Assert.AreEqual(30, LPLine."Source Document Quantity", 'LP line must retain the total receipt-line quantity for MTE printing.');
        Assert.AreEqual(10, LPLine.Quantity, 'LP line must retain this pallet scan quantity independently.');
        Assert.AreEqual(WhseReceiptLine."No.", LPLine."Source Document No.", 'LP line must retain its receipt reference.');
        ReceiptMgmt.StopLP(WhseReceiptHeader, LpNo, false);
        LP.Get(LpNo);
        Assert.AreEqual(Format(LP.Status::Built), Format(LP.Status), 'Stopped LP must be built.');
        ReceiptMgmt.PostReceipt(WhseReceiptHeader, false, false);

        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(LpNo, PostedWhseReceiptLine."LP No.", 'Posted receipt line must keep LP No.');
    end;

    [Test]
    procedure StartStopStartReopensTheSameLp()
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
        Assert.AreEqual(FirstLpNo, SecondLpNo, 'Restarting after close must reopen the same LP.');
        FirstLP.Get(FirstLpNo);
        Assert.AreEqual(Format(FirstLP.Status::Open), Format(FirstLP.Status), 'The receipt LP must be open again.');
        WhseReceiptHeader.Get(WhseReceiptHeader."No.");
        Assert.AreEqual(SecondLpNo, WhseReceiptHeader."DOPSWHS LP No.", 'The receipt must still point to the reopened LP.');
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
