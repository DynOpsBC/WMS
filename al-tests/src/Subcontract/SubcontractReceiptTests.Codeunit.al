codeunit 72497 "DOPSWHS Subcontract Rcpt Tests"
{
    Subtype = Test;

    [Test]
    procedure ZeroReceiptQuantityIsRejected()
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
    begin
        asserterror Mgmt.ValidateRequest('FINISHED', 10, 0, 'IRS-1', false);
        Assert.ExpectedError('sıfırdan büyük');
    end;

    [Test]
    procedure OverReceiptQuantityIsRejected()
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
    begin
        asserterror Mgmt.ValidateRequest('FINISHED', 10, 10.01, 'IRS-1', false);
        Assert.ExpectedError('aşıyor');
    end;

    [Test]
    procedure IncomingShipmentNumberIsMandatory()
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
    begin
        asserterror Mgmt.ValidateRequest('FINISHED', 10, 5, '', false);
        Assert.ExpectedError('irsaliye numarası zorunludur');
    end;

    [Test]
    procedure PartialReceiptCannotFinishOperation()
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
    begin
        asserterror Mgmt.ValidateRequest('FINISHED', 10, 5, 'IRS-1', true);
        Assert.ExpectedError('Parsiyel kabulde');
    end;

    [Test]
    procedure ExactFullReceiptCanFinishOperation()
    var
        Mgmt: Codeunit "DOPSWHS Subcont Receipt Mgt";
    begin
        Mgmt.ValidateRequest('FINISHED', 10, 10, 'IRS-1', true);
    end;

    [Test]
    procedure MissingProviderLeavesEDespatchVisibleForAdapter()
    var
        Outbox: Record "DOPSWHS Subcontract EDesp Out";
        TransferShipment: Record "Transfer Shipment Header";
        Mgmt: Codeunit "DOPSWHS Subcontract EDesp Mgt";
    begin
        TransferShipment.Init();
        TransferShipment."No." := CopyStr('SUB-TS-' + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20);
        TransferShipment.Insert(false);
        Outbox.Init();
        Outbox."Posted Transfer Shipment No." := TransferShipment."No.";
        Outbox."Reference No." := 'PO-FASON-1';
        Outbox.Status := 'PENDING';
        Outbox.Insert(true);

        Mgmt.Submit(Outbox."Entry No.");

        Outbox.Get(Outbox."Entry No.");
        Assert.AreEqual('WAITING_ADAPTER', Outbox.Status, 'Missing legal provider must stay visible, never look submitted.');
        Assert.AreEqual(1, Outbox."Attempt Count", 'Automatic provider attempt must be audited.');
        TransferShipment.Get(TransferShipment."No.");
        Assert.AreEqual('WAITING_ADAPTER', TransferShipment."DOPSWHS E-Despatch Status", 'Posted shipment must expose the legal submission state.');
    end;

    [Test]
    procedure SubmittedEDespatchIsIdempotent()
    var
        Outbox: Record "DOPSWHS Subcontract EDesp Out";
        Mgmt: Codeunit "DOPSWHS Subcontract EDesp Mgt";
    begin
        Outbox.Init();
        Outbox."Posted Transfer Shipment No." := CopyStr('SUB-DONE-' + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20);
        Outbox.Status := 'SUBMITTED';
        Outbox."Attempt Count" := 1;
        Outbox.Insert(true);

        Mgmt.Submit(Outbox."Entry No.");

        Outbox.Get(Outbox."Entry No.");
        Assert.AreEqual(1, Outbox."Attempt Count", 'A submitted legal document must never be sent twice.');
    end;

    var
        Assert: Codeunit Assert;
}
