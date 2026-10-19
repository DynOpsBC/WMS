using System.Environment;

codeunit 72180 "DOPSWHS Env Print Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure SharingIsOptIn()
    begin
        Initialize(false);
        Check(not PrintEnvironment.IsEnabled(), 'A package upgrade must not enable sharing.');
        PrintEnvironment.SyncCompany();
        Setup.Get('');
        Check(Setup."Azure SB Namespace" = 'company-original', 'Disabled sharing changed company setup.');
    end;

    [Test]
    procedure SharedConnectionPreservesWarehouseAndLocalPrinterSettings()
    begin
        Initialize(true);
        Profile."Status Owner Company" := 'OTHER COMPANY';
        Profile.Modify();
        Setup."Default Location Code" := 'LOCAL';
        Setup.Modify();
        CreatePrinter();
        Printer."Location Code" := 'LOCAL';
        Printer."Default Copies" := 3;
        Printer.Modify();
        SharedPrinter.Init();
        SharedPrinter.TransferFields(Printer);
        SharedPrinter."Printer Handle" := 'Shared Printer';
        SharedPrinter.Insert();
        PrintEnvironment.SyncCompany();
        Setup.Get('');
        Printer.Get('ENV-TEST');
        Check(Setup."Azure SB Namespace" = 'environment-test', 'Shared connection was not used.');
        Check(Setup."Default Location Code" = 'LOCAL', 'Company warehouse was overwritten.');
        Check(Printer."Printer Handle" = 'Shared Printer', 'Shared printer was not refreshed.');
        Check(Printer."Location Code" = 'LOCAL', 'Printer location was copied across companies.');
        Check(Printer."Default Copies" = 3, 'Company copy count was overwritten.');
    end;

    [Test]
    procedure CopiedEnvironmentCannotUseLiveConnection()
    begin
        Initialize(true);
        Profile."Environment Name" := 'DIFFERENT ENVIRONMENT';
        Profile.Modify();
        asserterror PrintEnvironment.SyncCompany();
        Check(StrPos(GetLastErrorText(), 'başka bir BC ortamına') > 0, 'Environment mismatch was not rejected.');
    end;

    [Test]
    procedure StationCollisionDoesNotOverwritePrinter()
    begin
        Initialize(true);
        Profile."Status Owner Company" := 'OTHER COMPANY';
        Profile.Modify();
        CreatePrinter();
        SharedPrinter.Init();
        SharedPrinter.TransferFields(Printer);
        SharedPrinter."Station ID" := 'DYNOPS.BADE.MAIN.PRINT02';
        SharedPrinter.Insert();
        asserterror PrintEnvironment.SyncCompany();
        Printer.Get('ENV-TEST');
        Check(Printer."Station ID" = 'DYNOPS.BADE.MAIN.PRINT01', 'A station collision overwrote the printer.');
    end;

    [Test]
    procedure ForeignCompanyResultCannotCompleteLocalJob()
    var
        Root: JsonObject;
    begin
        Initialize(true);
        CreateJob();
        PrintEnvironment.RegisterJob(Queue."Cloud Job ID");
        Route.Get(Queue."Cloud Job ID");
        Route."Company Name" := 'OTHER COMPANY';
        Route.Modify();
        Root := ResultFor(Queue."Cloud Job ID", 'ENV-TEST');
        Check(PrintEnvironment.CaptureResult(Root), 'Result was not durably captured.');
        PrintEnvironment.ApplyCompanyResults(20);
        Queue.Get(Queue."Job ID");
        Check(Queue.Status = Queue.Status::Dispatched, 'Another company result completed a local job.');
        Route.Get(Queue."Cloud Job ID");
        Check(Route."Result Pending", 'Another company result was removed.');
    end;

    [Test]
    procedure ResultCompletesOnlyItsGuidAndDuplicateIsHarmless()
    var
        Root: JsonObject;
        Log: Record "DOPSWHS Print Job Log";
        LogCount: Integer;
    begin
        Initialize(true);
        CreateJob();
        PrintEnvironment.RegisterJob(Queue."Cloud Job ID");
        Root := ResultFor(Queue."Cloud Job ID", 'ENV-TEST');
        PrintEnvironment.CaptureResult(Root);
        PrintEnvironment.ApplyCompanyResults(20);
        Queue.Get(Queue."Job ID");
        Check(Queue.Status = Queue.Status::Sent, 'Own result did not complete the job.');
        Route.Get(Queue."Cloud Job ID");
        Check(Route."Result Applied" and not Route."Result Pending", 'Result was not acknowledged locally.');
        Log.SetRange("Job ID", Queue."Job ID");
        LogCount := Log.Count();
        PrintEnvironment.CaptureResult(Root);
        PrintEnvironment.ApplyCompanyResults(20);
        Check(Log.Count() = LogCount, 'Duplicate result wrote a second completion event.');
    end;

    [Test]
    procedure InFlightJobBeforeEnableIsRecoveredByGuid()
    var
        Root: JsonObject;
    begin
        Initialize(true);
        CreateJob();
        // No shared registry row: this job was dispatched before migration.
        Root := ResultFor(Queue."Cloud Job ID", 'ENV-TEST');
        PrintEnvironment.CaptureResult(Root);
        PrintEnvironment.ApplyCompanyResults(20);
        Queue.Get(Queue."Job ID");
        Route.Get(Queue."Cloud Job ID");
        Check(Queue.Status = Queue.Status::Sent, 'A pre-migration result was lost.');
        Check(Route."Company Name" = CompanyName(), 'The originating company was not recorded.');
    end;

    [Test]
    procedure MismatchedPrinterRemainsPendingWithoutChangingJob()
    var
        Root: JsonObject;
    begin
        Initialize(true);
        CreateJob();
        Root := ResultFor(Queue."Cloud Job ID", 'WRONG-PRINTER');
        PrintEnvironment.CaptureResult(Root);
        PrintEnvironment.ApplyCompanyResults(20);
        Queue.Get(Queue."Job ID");
        Route.Get(Queue."Cloud Job ID");
        Check(Queue.Status = Queue.Status::Dispatched, 'A mismatched printer completed the job.');
        Check(Route."Result Pending" and (Route."Last Error" <> ''), 'Invalid result was lost instead of retained.');
    end;

    local procedure Initialize(Shared: Boolean)
    var
        Environment: Codeunit "Environment Information";
    begin
        // Run only in a disposable BC test environment with test isolation.
        Profile.DeleteAll();
        SharedPrinter.DeleteAll();
        Route.DeleteAll();
        Printer.DeleteAll();
        Queue.DeleteAll();
        if not Setup.Get('') then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        Setup."Environment Print Linked" := true; // no scheduled background tasks in tests
        Setup."Azure SB Namespace" := 'company-original';
        Setup."Azure Tenant Route ID" := 'DYNOPS';
        Setup."Azure Company Route ID" := 'BADE';
        Setup.Modify();
        if not Shared then
            exit;
        Profile.Init();
        Profile.TransferFields(Setup, false);
        Profile."Azure SB Namespace" := 'environment-test';
        Profile."Print Channel" := Profile."Print Channel"::AzureDirect;
        Profile."Status Owner Company" := CopyStr(CompanyName(), 1, MaxStrLen(Profile."Status Owner Company"));
        Profile."Environment Name" := CopyStr(Environment.GetEnvironmentName(), 1, MaxStrLen(Profile."Environment Name"));
        Profile.Production := Environment.IsProduction();
        Profile.Insert();
    end;

    local procedure CreatePrinter()
    begin
        Printer.Init();
        Printer.Code := 'ENV-TEST';
        Printer."Station ID" := 'DYNOPS.BADE.MAIN.PRINT01';
        Printer."Printer Handle" := 'Test Printer';
        Printer."Format" := Printer."Format"::ZPL;
        Printer.Active := true;
        Printer.Insert();
    end;

    local procedure CreateJob()
    begin
        CreatePrinter();
        Queue.Init();
        Queue."Job ID" := 0;
        Queue."Cloud Job ID" := CreateGuid();
        Queue."Printer ID" := Printer.Code;
        Queue."Station ID" := Printer."Station ID";
        Queue."Format" := Printer."Format";
        Queue.Channel := Queue.Channel::AzureDirect;
        Queue.Status := Queue.Status::Dispatched;
        Queue."Dispatched At" := CurrentDateTime() - 1000;
        Queue.Insert();
    end;

    local procedure ResultFor(JobId: Guid; PrinterId: Text): JsonObject
    var
        Root: JsonObject;
    begin
        Root.Add('schemaVersion', 1);
        Root.Add('messageType', 'jobResult');
        Root.Add('messageId', GuidText(CreateGuid()));
        Root.Add('tenantId', 'DYNOPS');
        Root.Add('companyId', 'BADE');
        Root.Add('stationId', 'DYNOPS.BADE.MAIN.PRINT01');
        Root.Add('agentId', GuidText(CreateGuid()));
        Root.Add('agentVersion', '1.0.0');
        Root.Add('sentAtUtc', Format(CurrentDateTime(), 0, 9));
        Root.Add('jobId', GuidText(JobId));
        Root.Add('printerId', PrinterId);
        Root.Add('printerName', 'Test Printer');
        Root.Add('format', 'ZPL');
        Root.Add('success', true);
        Root.Add('message', 'Spool accepted');
        Root.Add('completedAtUtc', Format(CurrentDateTime(), 0, 9));
        Root.Add('attempt', 1);
        exit(Root);
    end;

    local procedure GuidText(Value: Guid): Text
    begin
        exit(LowerCase(DelChr(Format(Value), '=', '{}')));
    end;

    local procedure Check(Condition: Boolean; MessageText: Text)
    begin
        if not Condition then
            Error(MessageText);
    end;

    var
        Profile: Record "DOPSWHS Print Environment";
        SharedPrinter: Record "DOPSWHS Environment Printer";
        Route: Record "DOPSWHS Environment Print Job";
        Setup: Record "DOPSWHS Setup";
        Printer: Record "DOPSWHS Printer";
        Queue: Record "DOPSWHS Print Job Queue";
        PrintEnvironment: Codeunit "DOPSWHS Print Environment";
}
