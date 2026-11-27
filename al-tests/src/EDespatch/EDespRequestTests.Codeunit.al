codeunit 72145 "DOPSWHS EDesp Request Tests"
{
    Subtype = Test;

    // These tests cover the provider-independent request contract of BCWMSApp.
    // Run them in a company where the "DynOps WMS e-Despatch Connector" is NOT installed:
    // with the connector, the provider answers the events and the WaitingAdapter assertions do not apply.

    [Test]
    procedure CreateForSourceReturnsTheSameRequestForTheSameDocument()
    var
        First: Record "DOPSWHS EDesp Request";
        Second: Record "DOPSWHS EDesp Request";
        Counter: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
        SourceNo: Code[20];
    begin
        SourceNo := UniqueNo('TS');
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, SourceNo, 'ANA', 'FASON', '', 'TERM01', CreateGuid(), First);
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, SourceNo, 'ANA', 'FASON', '', 'TERM01', CreateGuid(), Second);

        Assert.AreEqual(First."Entry No.", Second."Entry No.", 'A posted document must never get a second e-despatch request.');
        Counter.SetRange("Source Type", Counter."Source Type"::TransferShipment);
        Counter.SetRange("Source No.", SourceNo);
        Assert.AreEqual(1, Counter.Count(), 'Exactly one request per source document.');
        Assert.AreEqual(Second.Status::Pending, Second.Status, 'A new request starts as Pending.');
        Assert.IsTrue(Second.Editable, 'A new request is editable.');
    end;

    [Test]
    procedure SameNumberOfAnotherSourceTypeIsAnotherRequest()
    var
        Shipment: Record "DOPSWHS EDesp Request";
        Movement: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
        SourceNo: Code[20];
    begin
        SourceNo := UniqueNo('X');
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, SourceNo, 'ANA', 'FASON', '', '', CreateGuid(), Shipment);
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::RegisteredWhseMovement, SourceNo, 'ANA', 'ANA', '', '', CreateGuid(), Movement);

        Assert.AreNotEqual(Shipment."Entry No.", Movement."Entry No.", 'Source type is part of the document identity.');
    end;

    [Test]
    procedure OverridesFromTheHandheldAreAppliedAndNormalized()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource(
            "DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON',
            '{"receiverType":2,"receiverNo":"V001","purpose":"fason","vehiclePlateNo":"16 abc 123","trailerPlateNo":"16 d 99","driverFirstName":"Ali","driverFamilyName":"Kaya","note":"Kalıp ile birlikte"}',
            'TERM01', CreateGuid(), Request);

        Assert.AreEqual(Request."Receiver Type"::Vendor, Request."Receiver Type", 'receiverType 2 is a vendor.');
        Assert.AreEqual('V001', Request."Receiver No.", 'Receiver number must be stored.');
        Assert.AreEqual(Request.Purpose::Subcontracting, Request.Purpose, 'Turkish purpose names must be accepted.');
        Assert.AreEqual('16ABC123', Request."Vehicle Plate No.", 'Plates are stored without spaces in capitals.');
        Assert.AreEqual('16D99', Request."Trailer Plate No.", 'Trailer plates are normalized the same way.');
        Assert.AreEqual('Kalıp ile birlikte', Request.Note, 'The note is kept as typed.');
        Assert.AreEqual('TERM01', Request."Operator User Id", 'The WMS operator is audited on the request.');
    end;

    [Test]
    procedure ChangingTheReceiverTypeClearsTheOldReceiver()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource(
            "DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'KONSINYE',
            '{"receiverType":"Vendor","receiverNo":"V001","receiverAddressCode":"DEPO"}', '', CreateGuid(), Request);
        Request."Receiver Name" := 'Fason A.Ş.';
        Request.Modify();

        Mgt.UpdateDraft(Request, '{"receiverType":"Customer"}');

        Request.Get(Request."Entry No.");
        Assert.AreEqual(Request."Receiver Type"::Customer, Request."Receiver Type", 'Receiver type must change.');
        Assert.AreEqual('', Request."Receiver No.", 'A vendor number must not stay on a customer receiver.');
        Assert.AreEqual('', Request."Receiver Address Code", 'The vendor order address must be cleared too.');
        Assert.AreEqual('', Request."Receiver Name", 'The resolved name must be cleared until the provider resolves again.');
    end;

    [Test]
    procedure InvalidChangesJsonIsRejected()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);

        asserterror Mgt.UpdateDraft(Request, '{receiverType:');
        Assert.ExpectedError('not valid JSON');
    end;

    [Test]
    procedure SentDespatchCannotBeChanged()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);
        Mgt.RegisterProviderDocument(Request, 990001, 'IRS2026000000001', CreateGuid());
        Mgt.ApplyProviderStatus(Request, "DOPSWHS EDesp Status"::Sent, 'Sent', false, '', '');

        asserterror Mgt.UpdateDraft(Request, '{"vehiclePlateNo":"34XYZ01"}');
        Assert.ExpectedError('can no longer be changed');
    end;

    [Test]
    procedure WithoutProviderTheDraftWaitsForAnAdapter()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);

        Mgt.EnsureDraft(Request);

        Request.Get(Request."Entry No.");
        Assert.AreEqual(Request.Status::WaitingAdapter, Request.Status, 'Without e-transformation the request must stay visible as waiting, never look created.');
        Assert.AreEqual(1, Request."Attempt Count", 'Each provider attempt is counted.');
        Assert.AreNotEqual('', Request."Last Error", 'The operator must see why nothing was created.');
        Assert.AreEqual(0, Request."Provider Entry No.", 'No provider document may be linked.');
    end;

    [Test]
    procedure SubmitWithoutProviderDoesNotPretendToSend()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        DisableVehicleCheck();
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);

        Mgt.Submit(Request);

        Request.Get(Request."Entry No.");
        Assert.AreEqual(Request.Status::WaitingAdapter, Request.Status, 'Submit without a provider must not report Sent.');
        Assert.AreEqual(0DT, Request."Sent At", 'No send time without a provider.');
    end;

    // asserterror rolls back the whole transaction, so each vehicle rule gets its own test with its own data.
    [Test]
    procedure SubmitAsksForThePlateWhenSetupRequiresVehicleInfo()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequireVehicleInfo();
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);

        asserterror Mgt.Submit(Request);
        Assert.ExpectedError('vehicle plate');
    end;

    [Test]
    procedure SubmitAsksForTheDriverWhenThereIsNoCarrier()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequireVehicleInfo();
        Mgt.CreateForSource(
            "DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON',
            '{"vehiclePlateNo":"16ABC123","driverFirstName":"Ali"}', '', CreateGuid(), Request);

        asserterror Mgt.Submit(Request);
        Assert.ExpectedError('driver first and family name');
    end;

    [Test]
    procedure CarrierReplacesTheDriverOnSubmit()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequireVehicleInfo();
        Mgt.CreateForSource(
            "DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON',
            '{"vehiclePlateNo":"16ABC123","shippingAgentCode":"ARAS"}', '', CreateGuid(), Request);

        Mgt.Submit(Request);

        Request.Get(Request."Entry No.");
        Assert.AreEqual(Request.Status::WaitingAdapter, Request.Status, 'With plate and carrier the request goes on to the provider step.');
    end;

    [Test]
    procedure ProviderDocumentAndStatusAreMirrored()
    var
        Request: Record "DOPSWHS EDesp Request";
        Found: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Ettn: Guid;
    begin
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::DirectTransfer, UniqueNo('DT'), 'ANA', 'SUBE2', '', '', CreateGuid(), Request);
        Ettn := CreateGuid();

        Mgt.RegisterProviderDocument(Request, 990002, 'IRS2026000000002', Ettn);
        Assert.AreEqual(Request.Status::Draft, Request.Status, 'A linked provider document is a draft.');
        Assert.AreEqual('DYNOPSETRANS', Request."Provider Code", 'The provider is recorded.');
        Assert.IsTrue(Mgt.FindByProviderEntryNo(990002, Found), 'The mirror finds the request by provider entry.');
        Assert.AreEqual(Request."Entry No.", Found."Entry No.", 'Provider entry points back to this request.');

        Mgt.ApplyProviderStatus(Request, "DOPSWHS EDesp Status"::Sent, 'GİB: Gönderildi', false, '', '');
        Request.Get(Request."Entry No.");
        Assert.AreEqual(Request.Status::Sent, Request.Status, 'Status follows the provider.');
        Assert.IsFalse(Request.Editable, 'A sent e-despatch is locked.');
        Assert.AreNotEqual(0DT, Request."Sent At", 'Send time is stamped once.');
        Assert.AreEqual('IRS2026000000002', Request."Provider Document No.", 'An empty number from the provider keeps the known number.');
    end;

    [Test]
    procedure StatusIsWrittenBackToThePostedShipmentForSubcontracting()
    var
        TransferShipmentHeader: Record "Transfer Shipment Header";
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        TransferShipmentHeader.Init();
        TransferShipmentHeader."No." := UniqueNo('TS');
        TransferShipmentHeader.Insert();
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, TransferShipmentHeader."No.", 'ANA', 'FASON', '', '', CreateGuid(), Request);
        Mgt.RegisterProviderDocument(Request, 990003, 'IRS2026000000003', CreateGuid());

        Mgt.ApplyProviderStatus(Request, "DOPSWHS EDesp Status"::Sent, 'Sent', false, '', '');

        TransferShipmentHeader.Get(TransferShipmentHeader."No.");
        Assert.AreEqual('SUBMITTED', TransferShipmentHeader."DOPSWHS E-Despatch Status", 'Subcontracting screens read the legal state from the posted shipment.');
        Assert.AreEqual('IRS2026000000003', TransferShipmentHeader."DOPSWHS E-Despatch Document No.", 'The e-despatch number is shown on the posted shipment.');
    end;

    [Test]
    procedure JsonUsesEnumOrdinalsForTheHandheld()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Json: JsonObject;
        Token: JsonToken;
    begin
        Mgt.CreateForSource(
            "DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'KONSINYE',
            '{"receiverType":"3","purpose":"3"}', '', CreateGuid(), Request);
        Mgt.ApplyProviderStatus(Request, "DOPSWHS EDesp Status"::Accepted, 'Accepted', false, 'IRS2026000000004', '');

        Json.ReadFrom(Mgt.ToJsonText(Request));

        Json.Get('status', Token);
        Assert.AreEqual(4, Token.AsValue().AsInteger(), 'Android maps status by ordinal (Accepted = 4).');
        Json.Get('receiverType', Token);
        Assert.AreEqual(3, Token.AsValue().AsInteger(), 'Android maps receiver type by ordinal (Customer = 3).');
        Json.Get('purpose', Token);
        Assert.AreEqual(3, Token.AsValue().AsInteger(), 'Consignment = 3.');
        Json.Get('editable', Token);
        Assert.IsFalse(Token.AsValue().AsBoolean(), 'An accepted e-despatch is never editable on the handheld.');
        Json.Get('eDespatchNo', Token);
        Assert.AreEqual('IRS2026000000004', Token.AsValue().AsText(), 'The legal number is exposed for printing.');
    end;

    [Test]
    procedure PrintingIsAuditedPerFormat()
    var
        Request: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', CreateGuid(), Request);

        Mgt.MarkPrinted(Request, "DOPSWHS EDesp Print Format"::Thermal80);
        Mgt.MarkPrinted(Request, "DOPSWHS EDesp Print Format"::A4Official);

        Request.Get(Request."Entry No.");
        Assert.IsTrue(Request."Printed Thermal", '80 mm copy is recorded.');
        Assert.IsTrue(Request."Printed A4", 'A4 copy is recorded.');
        Assert.AreEqual(2, Request."Print Count", 'Every copy is counted.');
    end;

    [Test]
    procedure IdempotencyKeyFindsTheEarlierRequest()
    var
        Request: Record "DOPSWHS EDesp Request";
        Found: Record "DOPSWHS EDesp Request";
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
        IdempotencyKey: Guid;
        EmptyKey: Guid;
    begin
        IdempotencyKey := CreateGuid();
        Mgt.CreateForSource("DOPSWHS EDesp Source Type"::TransferShipment, UniqueNo('TS'), 'ANA', 'FASON', '', '', IdempotencyKey, Request);

        Assert.IsTrue(Mgt.FindByIdempotencyKey(IdempotencyKey, Found), 'A retried handheld call must find the first result.');
        Assert.AreEqual(Request."Entry No.", Found."Entry No.", 'Same key, same request.');
        Assert.IsFalse(Mgt.FindByIdempotencyKey(EmptyKey, Found), 'An empty key never matches.');
    end;

    [Test]
    procedure ReceiverAndPurposeAcceptNamesOrdinalsAndTurkish()
    var
        Mgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        Assert.AreEqual("DOPSWHS EDesp Receiver Type"::OwnCompany, Mgt.ParseReceiverType('OwnCompany'), 'Name');
        Assert.AreEqual("DOPSWHS EDesp Receiver Type"::Vendor, Mgt.ParseReceiverType('tedarikçi'), 'Turkish');
        Assert.AreEqual("DOPSWHS EDesp Receiver Type"::Customer, Mgt.ParseReceiverType('3'), 'Ordinal');
        Assert.AreEqual("DOPSWHS EDesp Receiver Type"::" ", Mgt.ParseReceiverType('x'), 'Unknown means use mapping');
        Assert.AreEqual("DOPSWHS EDesp Purpose"::Consignment, Mgt.ParsePurpose('konsinye'), 'Turkish');
        Assert.AreEqual("DOPSWHS EDesp Purpose"::InterLocation, Mgt.ParsePurpose('1'), 'Ordinal');
    end;

    [Test]
    procedure CreateAndShipRejectsTheSameLocation()
    var
        Mgt: Codeunit "DOPSWHS Transfer Ship Mgmt";
    begin
        asserterror Mgt.CreateAndShip('{"fromLocationCode":"ANA","toLocationCode":"ANA","lines":[{"itemNo":"X","quantity":1}]}', 'TERM01', CreateGuid());
        Assert.ExpectedError('Kaynak ve hedef lokasyon aynı olamaz');
    end;

    [Test]
    procedure CreateAndShipNeedsLinesAndAKey()
    var
        Mgt: Codeunit "DOPSWHS Transfer Ship Mgmt";
        EmptyKey: Guid;
    begin
        asserterror Mgt.CreateAndShip('{"fromLocationCode":"ANA","toLocationCode":"FASON","lines":[]}', 'TERM01', CreateGuid());
        Assert.ExpectedError('En az bir satır okutun');

        asserterror Mgt.CreateAndShip('{"fromLocationCode":"ANA","toLocationCode":"FASON","lines":[{"itemNo":"X","quantity":1}]}', 'TERM01', EmptyKey);
        Assert.ExpectedError('İşlem anahtarı boş olamaz');
    end;

    [Test]
    procedure RegisterWithDespatchNeedsTheOperator()
    var
        Mgt: Codeunit "DOPSWHS EDesp Movement Mgmt";
    begin
        asserterror Mgt.RegisterWithDespatch("Warehouse Activity Type"::Movement, 'NO-SUCH-MOVE', '', '', CreateGuid());
        Assert.ExpectedError('WMS kullanıcı kimliği boş olamaz');
    end;

    [Test]
    procedure RegisterWithDespatchReportsAMissingMovement()
    var
        Mgt: Codeunit "DOPSWHS EDesp Movement Mgmt";
    begin
        asserterror Mgt.RegisterWithDespatch("Warehouse Activity Type"::Movement, UniqueNo('NOMV'), 'TERM01', '', CreateGuid());
        Assert.ExpectedError('artık bulunamıyor');
    end;

    local procedure DisableVehicleCheck()
    var
        Setup: Record "DOPSWHS Setup";
    begin
        Setup := TestHelper.EnsureSetup();
        Setup."EDesp Require Vehicle Info" := false;
        Setup.Modify();
    end;

    local procedure RequireVehicleInfo()
    var
        Setup: Record "DOPSWHS Setup";
    begin
        Setup := TestHelper.EnsureSetup();
        Setup."EDesp Require Vehicle Info" := true;
        Setup.Modify();
    end;

    local procedure UniqueNo(Prefix: Text): Code[20]
    begin
        exit(CopyStr(Prefix + '-' + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
    end;

    var
        Assert: Codeunit Assert;
        TestHelper: Codeunit "DOPSWHS Test Helper";
}
