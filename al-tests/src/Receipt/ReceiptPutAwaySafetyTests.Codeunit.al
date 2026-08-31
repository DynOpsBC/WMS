codeunit 72143 "DOPSWHS Rcpt PutAway Safety"
{
    Subtype = Test;

    [Test]
    procedure ReceiptOwnerIsWrittenToUnassignedPutAway()
    var
        PutAway: Record "Warehouse Activity Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreatePutAway(PutAway, 'PA-RCPT-OWNER', '');

        ReceiptMgmt.EnsurePutAwayAssigned(PutAway."No.", 'DYNOPS');

        PutAway.Get(PutAway.Type::"Put-away", PutAway."No.");
        Assert.AreEqual('DYNOPS', PutAway."Assigned User ID", 'Receipt owner must flow to the generated put-away.');
    end;

    [Test]
    procedure ReceiptOwnerReplacesUnexpectedGeneratedOwner()
    var
        PutAway: Record "Warehouse Activity Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreatePutAway(PutAway, 'PA-RCPT-REASSIGN', 'SERVICE');

        ReceiptMgmt.EnsurePutAwayAssigned(PutAway."No.", 'DYNOPS');

        PutAway.Get(PutAway.Type::"Put-away", PutAway."No.");
        Assert.AreEqual('DYNOPS', PutAway."Assigned User ID", 'Generated put-away must keep the receipt owner.');
    end;

    [Test]
    procedure ExcludingUntouchedReceiptLineZerosPostingQuantities()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        ReceiptHeader.Init();
        ReceiptHeader."No." := 'RCPT-EXCLUDE';
        ReceiptHeader.Insert(true);

        ReceiptLine.Init();
        ReceiptLine."No." := ReceiptHeader."No.";
        ReceiptLine."Line No." := 10000;
        ReceiptLine.Quantity := 25;
        ReceiptLine."Qty. to Receive" := 25;
        ReceiptLine."Qty. to Receive (Base)" := 25;
        ReceiptLine.Insert(true);

        ReceiptMgmt.ExcludeLineFromPost(ReceiptLine);

        ReceiptLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(0, ReceiptLine."Qty. to Receive", 'Untouched line must not be posted.');
        Assert.AreEqual(0, ReceiptLine."Qty. to Receive (Base)", 'Base quantity must also be excluded.');
    end;

    local procedure CreatePutAway(var PutAway: Record "Warehouse Activity Header"; PutAwayNo: Code[20]; AssignedUserId: Code[50])
    begin
        PutAway.Init();
        PutAway.Type := PutAway.Type::"Put-away";
        PutAway."No." := PutAwayNo;
        PutAway."Assigned User ID" := AssignedUserId;
        PutAway.Insert(true);
    end;

    var
        Assert: Codeunit Assert;
}
