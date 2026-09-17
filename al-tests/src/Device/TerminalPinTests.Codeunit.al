codeunit 72145 "DOPSWHS Terminal PIN Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure ReceiptAssignmentUsesPinEmployeeIdentity()
    var
        LocalUser: Record "DOPSWHS Local User";
        Receipt: Record "Warehouse Receipt Header";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        CreateFixture(LocalUser);
        Receipt.Init();
        Receipt."No." := 'PIN-RECEIPT-TEST';
        Receipt.Insert(false);
        ReceiptMgmt.AssignUser(Receipt, LocalUser.Username, LocalUser.Username);
        Receipt.Get(Receipt."No.");
        Receipt.TestField("Assigned User ID", LocalUser.Username);
        LocalUser.Disabled := true;
        LocalUser.Modify(true);
        asserterror ReceiptMgmt.AssignUser(Receipt, LocalUser.Username, LocalUser.Username);
    end;

    [Test]
    procedure CreateWithLeadingZeroPin()
    var
        LocalUser: Record "DOPSWHS Local User";
        Profile: JsonObject;
        Value: JsonToken;
    begin
        CreateFixture(LocalUser);
        LocalUser.TestField("Display Name", 'Merve Demirci');
        LocalUser.TestField("PIN Login", true);
        Assert.AreNotEqual('0017', LocalUser."Password Hash", 'PIN must be hashed.');
        Profile.ReadFrom(Auth.VerifyTerminal('PIN-TEST-1', LocalUser.Username, '0017'));
        Assert.IsFalse(Profile.Contains('error'), 'Valid PIN must authenticate.');
        Profile.Get('userId', Value);
        Assert.AreEqual(LocalUser.Username, Value.AsValue().AsText(), 'Stable operator ID is retained.');
        Profile.Get('terminalCode', Value);
        Assert.AreEqual('PIN-TEST-1', Value.AsValue().AsText(), 'Terminal is returned.');
    end;

    [Test]
    procedure WrongTerminalAndDisabledUserAreRejected()
    var
        LocalUser: Record "DOPSWHS Local User";
    begin
        CreateFixture(LocalUser);
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-2', LocalUser.Username, '0017'));
        LocalUser.Disabled := true;
        LocalUser.Modify(true);
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-1', LocalUser.Username, '0017'));
    end;

    [Test]
    procedure DisabledTerminalIsRejected()
    var
        LocalUser: Record "DOPSWHS Local User";
        Terminal: Record "DOPSWHS WMS Terminal";
    begin
        CreateFixture(LocalUser);
        Terminal.Get('PIN-TEST-1');
        Terminal.Disabled := true;
        Terminal.Modify(true);
        AssertRejected(Auth.VerifyTerminal(Terminal.Code, LocalUser.Username, '0017'));
    end;

    [Test]
    procedure FiveFailuresLockAndResetPinUnlocks()
    var
        LocalUser: Record "DOPSWHS Local User";
        I: Integer;
        Profile: JsonObject;
    begin
        CreateFixture(LocalUser);
        for I := 1 to 5 do
            AssertRejected(Auth.VerifyTerminal('PIN-TEST-1', LocalUser.Username, '9999'));
        LocalUser.Get(LocalUser.Username);
        Assert.IsTrue(LocalUser."PIN Locked Until" > CurrentDateTime(), 'Lock must persist after failed calls.');
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-1', LocalUser.Username, '0017'));
        Auth.UpdatePassword(LocalUser.Username, '0042');
        Profile.ReadFrom(Auth.VerifyTerminal('PIN-TEST-1', LocalUser.Username, '0042'));
        Assert.IsFalse(Profile.Contains('error'), 'Resetting PIN unlocks user.');
    end;

    [Test]
    procedure InvalidPinDoesNotCreateUser()
    var
        LocalUser: Record "DOPSWHS Local User";
        BeforeCount: Integer;
    begin
        CreateFixture(LocalUser);
        BeforeCount := LocalUser.Count();
        asserterror Auth.CreateTerminalUser('PIN-TEST-1', 'Invalid', '12a4');
        Assert.AreEqual(BeforeCount, LocalUser.Count(), 'Failed creation must not leave a partial user.');
        asserterror Auth.ValidatePin('123');
        asserterror Auth.ValidatePin('12345');
    end;

    [Test]
    procedure SameNameCanBelongToSeparateTerminalsWithSeparateIdentities()
    var
        User1: Record "DOPSWHS Local User";
        User2: Record "DOPSWHS Local User";
    begin
        CreateFixture(User1);
        Auth.CreateTerminalUser('PIN-TEST-2', 'Merve Demirci', '0017');
        User2.SetRange("Terminal Code", 'PIN-TEST-2');
        User2.FindFirst();
        Assert.AreNotEqual(User1.Username, User2.Username, 'Separate records must not overwrite one another.');
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-1', User2.Username, '0017'));
    end;

    [Test]
    procedure ManagerUsesOwnPinOnBothTerminals()
    var
        Employee: Record "DOPSWHS Local User";
        Manager: Record "DOPSWHS Local User";
        Profile: JsonObject;
        Value: JsonToken;
    begin
        CreateFixture(Employee);
        Manager.SetRange("Terminal Admin", true);
        Manager.SetRange("Display Name", 'PIN-TEST-MANAGER');
        Manager.DeleteAll();
        Auth.CreateTerminalAdmin('PIN-TEST-MANAGER', '0042');
        Manager.FindFirst();
        Profile.ReadFrom(Auth.VerifyTerminal('PIN-TEST-1', Manager.Username, '0042'));
        Assert.IsFalse(Profile.Contains('error'), 'Manager must enter terminal 1.');
        Profile.Get('terminalAdmin', Value);
        Assert.IsTrue(Value.AsValue().AsBoolean(), 'Manager profile is marked.');
        Profile.ReadFrom(Auth.VerifyTerminal('PIN-TEST-2', Manager.Username, '0042'));
        Assert.IsFalse(Profile.Contains('error'), 'Same manager PIN must work on terminal 2.');
        Profile.Get('terminalCode', Value);
        Assert.AreEqual('PIN-TEST-2', Value.AsValue().AsText(), 'Selected terminal is retained.');
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-2', Manager.Username, '9999'));
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-2', Employee.Username, '0017'));
    end;

    [Test]
    procedure DisabledOrRevokedManagerCannotUseOtherTerminal()
    var
        Employee: Record "DOPSWHS Local User";
        Manager: Record "DOPSWHS Local User";
    begin
        CreateFixture(Employee);
        Manager.SetRange("Terminal Admin", true);
        Manager.SetRange("Display Name", 'PIN-TEST-MANAGER');
        Manager.DeleteAll();
        Auth.CreateTerminalAdmin('PIN-TEST-MANAGER', '0042');
        Manager.FindFirst();
        Manager.Disabled := true;
        Manager.Modify(true);
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-2', Manager.Username, '0042'));
        Manager.Disabled := false;
        Manager."Terminal Admin" := false;
        Manager."Terminal Code" := 'PIN-TEST-1';
        Manager.Modify(true);
        AssertRejected(Auth.VerifyTerminal('PIN-TEST-2', Manager.Username, '0042'));
    end;

    local procedure CreateFixture(var LocalUser: Record "DOPSWHS Local User")
    var
        Terminal: Record "DOPSWHS WMS Terminal";
    begin
        LocalUser.SetFilter("Terminal Code", 'PIN-TEST-1|PIN-TEST-2');
        LocalUser.DeleteAll();
        LocalUser.Reset();
        Terminal.SetFilter(Code, 'PIN-TEST-1|PIN-TEST-2');
        Terminal.DeleteAll();
        Terminal.Init();
        Terminal.Code := 'PIN-TEST-1';
        Terminal.Insert();
        Terminal.Code := 'PIN-TEST-2';
        Terminal.Insert();
        Auth.CreateTerminalUser('PIN-TEST-1', 'Merve Demirci', '0017');
        LocalUser.SetRange("Terminal Code", 'PIN-TEST-1');
        LocalUser.FindFirst();
        LocalUser.Reset();
    end;

    local procedure AssertRejected(Value: Text)
    var
        Profile: JsonObject;
    begin
        Profile.ReadFrom(Value);
        Assert.IsTrue(Profile.Contains('error'), 'Login must fail.');
    end;

    var
        Auth: Codeunit "DOPSWHS Local Auth Mgmt";
        Assert: Codeunit "Library Assert";
}
