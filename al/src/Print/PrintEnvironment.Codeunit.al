using System.Environment;

codeunit 72377 "DOPSWHS Print Environment"
{
    Access = Internal;
    Permissions =
        tabledata "DOPSWHS Print Environment" = rimd,
        tabledata "DOPSWHS Environment Printer" = rimd,
        tabledata "DOPSWHS Environment Print Job" = rimd,
        tabledata "DOPSWHS Setup" = rimd,
        tabledata "DOPSWHS Printer" = rimd;

    procedure IsEnabled(): Boolean
    var
        Profile: Record "DOPSWHS Print Environment";
        Environment: Codeunit "Environment Information";
    begin
        if not Profile.Get('') then
            exit(false);
        // A copied Production database must never consume the live queue.
        if (Profile."Environment Name" <> Environment.GetEnvironmentName()) or
           (Profile.Production <> Environment.IsProduction())
        then
            Error('Ortak yazıcı bağlantısı başka bir BC ortamına ait. Bu ortam için ayrı Azure kurulumu yapılmalıdır.');
        exit(true);
    end;

    procedure IsStatusOwner(): Boolean
    var
        Profile: Record "DOPSWHS Print Environment";
    begin
        if not IsEnabled() then
            exit(true);
        Profile.Get('');
        exit(Profile."Status Owner Company" = CompanyName());
    end;

    procedure EnsureCanConfigure()
    var
        Auth: Codeunit "DOPSWHS Local Auth Mgmt";
        Profile: Record "DOPSWHS Print Environment";
    begin
        if not IsEnabled() then
            exit;
        Auth.EnsureCanManageLocalUsers();
        Profile.Get('');
        if not IsStatusOwner() then
            Error('Ortak yazıcı bağlantısını %1 şirketindeki WMS Kurulum sayfasından yönetin.', Profile."Status Owner Company");
    end;

    procedure Enable()
    var
        Profile: Record "DOPSWHS Print Environment";
        Setup: Record "DOPSWHS Setup";
        Auth: Codeunit "DOPSWHS Local Auth Mgmt";
        Edition: Codeunit "DOPSWHS Edition";
        Environment: Codeunit "Environment Information";
        Bridge: Codeunit "DOPSWHS Azure Print Bridge";
        Worker: Codeunit "DOPSWHS Azure Print Worker";
    begin
        Auth.EnsureCanManageLocalUsers();
        if Edition.Current() <> 'BADE' then
            Error('Ortam bazlı yazıcı kurulumu bu pakette yalnız BADE için kullanılabilir.');
        if IsEnabled() then begin
            EnsureCanConfigure();
            exit;
        end;
        Bridge.ValidateConfiguration(true);
        Setup.Get('');
        Setup.TestField("Print Channel", Setup."Print Channel"::AzureDirect);
        Profile.LockTable();
        // Credentials are copied before the shared profile exists, preserving
        // the original company credentials and current agent route unchanged.
        Bridge.CopySecretsToEnvironment();
        Profile.Init();
        Profile.TransferFields(Setup, false);
        Profile."Status Owner Company" := CopyStr(CompanyName(), 1, MaxStrLen(Profile."Status Owner Company"));
        Profile."Environment Name" := CopyStr(Environment.GetEnvironmentName(), 1, MaxStrLen(Profile."Environment Name"));
        Profile.Production := Environment.IsProduction();
        Profile.Insert();
        PublishPrinters();
        Worker.ScheduleWorkerJob();
    end;

    procedure PublishSetup()
    var
        Profile: Record "DOPSWHS Print Environment";
        Setup: Record "DOPSWHS Setup";
    begin
        if not IsEnabled() then
            exit;
        EnsureCanConfigure();
        Profile.Get('');
        Setup.Get('');
        Profile.TransferFields(Setup, false);
        Profile.Modify();
    end;

    procedure SyncCompany()
    var
        Profile: Record "DOPSWHS Print Environment";
        Setup: Record "DOPSWHS Setup";
        SharedPrinter: Record "DOPSWHS Environment Printer";
        Printer: Record "DOPSWHS Printer";
        PrinterBefore: Record "DOPSWHS Printer";
        Worker: Codeunit "DOPSWHS Azure Print Worker";
        SetupBefore: Record "DOPSWHS Setup";
        NewSetup: Boolean;
    begin
        if not IsEnabled() then
            exit;
        Profile.Get('');
        NewSetup := not Setup.Get('');
        if NewSetup then begin
            Setup.Init();
            Setup.Insert(true);
        end;
        SetupBefore := Setup;
        Setup.TransferFields(Profile, false);
        // A job queue in each company applies that company's durable results
        // and retries its jobs. Only the owner receives from Service Bus.
        if not Setup."Environment Print Linked" then begin
            Worker.ScheduleWorkerJob();
            Setup."Environment Print Linked" := true;
        end;
        if (Setup."Print Channel" <> SetupBefore."Print Channel") or
           (Setup."Azure SB Namespace" <> SetupBefore."Azure SB Namespace") or
           (Setup."Azure Print Jobs Queue" <> SetupBefore."Azure Print Jobs Queue") or
           (Setup."Azure Printer Status Queue" <> SetupBefore."Azure Printer Status Queue") or
           (Setup."Azure Jobs SAS Policy" <> SetupBefore."Azure Jobs SAS Policy") or
           (Setup."Azure Status SAS Policy" <> SetupBefore."Azure Status SAS Policy") or
           (Setup."Azure Storage Account" <> SetupBefore."Azure Storage Account") or
           (Setup."Azure Blob Container" <> SetupBefore."Azure Blob Container") or
           (Setup."Azure Blob Endpoint Suffix" <> SetupBefore."Azure Blob Endpoint Suffix") or
           (Setup."Azure SB Endpoint Suffix" <> SetupBefore."Azure SB Endpoint Suffix") or
           (Setup."Azure Dispatch Max Attempts" <> SetupBefore."Azure Dispatch Max Attempts") or
           (Setup."Azure Tenant Route ID" <> SetupBefore."Azure Tenant Route ID") or
           (Setup."Azure Company Route ID" <> SetupBefore."Azure Company Route ID") or
           (Setup."Azure Blob SAS Expires At" <> SetupBefore."Azure Blob SAS Expires At") or
           (Setup."Environment Print Linked" <> SetupBefore."Environment Print Linked")
        then
            Setup.Modify();
        if IsStatusOwner() then
            exit;
        if SharedPrinter.FindSet() then
            repeat
                if Printer.Get(SharedPrinter.Code) then begin
                    if (Printer."Station ID" <> '') and (Printer."Station ID" <> SharedPrinter."Station ID") then
                        Error('Yazıcı kodu %1 bu şirkette farklı bir istasyona bağlı. Ortak yazıcıyla çakışan kaydı düzeltin.', SharedPrinter.Code);
                    PrinterBefore := Printer;
                    Printer.TransferFields(SharedPrinter, false);
                    if Printer."Format" <> Printer."Format"::PDF then
                        Printer."Enable BC Reports" := false;
                    if (Printer.Description <> PrinterBefore.Description) or
                       (Printer."Format" <> PrinterBefore."Format") or
                       (Printer."Printer Handle" <> PrinterBefore."Printer Handle") or
                       (Printer.Hostname <> PrinterBefore.Hostname) or
                       (Printer.Port <> PrinterBefore.Port) or
                       (Printer.Active <> PrinterBefore.Active) or
                       (Printer."Last Seen At" <> PrinterBefore."Last Seen At") or
                       (Printer."Last Agent ID" <> PrinterBefore."Last Agent ID") or
                       (Printer."Station ID" <> PrinterBefore."Station ID") or
                       (Printer."Discovered by Agent" <> PrinterBefore."Discovered by Agent") or
                       (Printer."Agent Status" <> PrinterBefore."Agent Status") or
                       (Printer."Last Status At" <> PrinterBefore."Last Status At") or
                       (Printer."Last Status Message" <> PrinterBefore."Last Status Message") or
                       (Printer."Agent Version" <> PrinterBefore."Agent Version") or
                       (Printer."Agent Default Printer" <> PrinterBefore."Agent Default Printer")
                    then
                        Printer.Modify();
                end else begin
                    Printer.Init();
                    Printer.Code := SharedPrinter.Code;
                    Printer."Default Copies" := 1;
                    Printer.TransferFields(SharedPrinter, false);
                    Printer."Enable BC Reports" := Printer."Format" = Printer."Format"::PDF;
                    Printer.Insert();
                end;
            until SharedPrinter.Next() = 0;
    end;

    procedure PublishPrinters()
    var
        Printer: Record "DOPSWHS Printer";
        SharedPrinter: Record "DOPSWHS Environment Printer";
        Profile: Record "DOPSWHS Print Environment";
    begin
        if not IsEnabled() or not IsStatusOwner() then
            exit;
        Profile.Get('');
        Printer.SetFilter("Station ID", '%1', Profile."Azure Tenant Route ID" + '.' + Profile."Azure Company Route ID" + '.*');
        if Printer.FindSet() then
            repeat
                if SharedPrinter.Get(Printer.Code) then begin
                    SharedPrinter.TransferFields(Printer, false);
                    SharedPrinter.Modify();
                end else begin
                    SharedPrinter.Init();
                    SharedPrinter.Code := Printer.Code;
                    SharedPrinter.TransferFields(Printer, false);
                    SharedPrinter.Insert();
                end;
            until Printer.Next() = 0;
    end;

    procedure RegisterJob(JobId: Guid)
    var
        Route: Record "DOPSWHS Environment Print Job";
    begin
        if not IsEnabled() then
            exit;
        if IsNullGuid(JobId) then
            Error('An environment print job must have a cloud GUID.');
        if Route.Get(JobId) then begin
            if Route."Company Name" <> CompanyName() then
                Error('Cloud print job is already owned by another company.');
            exit;
        end;
        Route.Init();
        Route."Cloud Job ID" := JobId;
        Route."Company Name" := CopyStr(CompanyName(), 1, MaxStrLen(Route."Company Name"));
        Route.Created := CurrentDateTime();
        Route.Insert();
    end;

    procedure CaptureResult(Root: JsonObject): Boolean
    var
        Route: Record "DOPSWHS Environment Print Job";
        Token: JsonToken;
        JobId: Guid;
        Body: Text;
        Output: OutStream;
    begin
        if not IsEnabled() then
            exit(false);
        if not IsStatusOwner() then
            Error('Only the environment status owner can receive cloud results.');
        Root.Get('jobId', Token);
        Evaluate(JobId, Token.AsValue().AsText());
        Route.LockTable();
        if not Route.Get(JobId) then begin
            // Preserve pre-upgrade/in-flight jobs too. Their own company
            // claims the GUID from its queue when its worker next runs.
            Route.Init();
            Route."Cloud Job ID" := JobId;
            Route.Created := CurrentDateTime();
            Route.Insert();
        end;
        if Route."Result Applied" or Route."Result Pending" then
            exit(true);
        Root.WriteTo(Body);
        Route."Result Body".CreateOutStream(Output, TextEncoding::UTF8);
        Output.WriteText(Body);
        Route."Result Pending" := true;
        Route.Modify();
        // ReceiveOne commits this durable inbox before completing Azure.
        exit(true);
    end;

    procedure ApplyCompanyResults(MaxResults: Integer)
    var
        Route: Record "DOPSWHS Environment Print Job";
        Queue: Record "DOPSWHS Print Job Queue";
        Status: Codeunit "DOPSWHS Azure Print Status";
        Input: InStream;
        Body: Text;
        Processed: Integer;
    begin
        if MaxResults <= 0 then
            MaxResults := 20;
        if not IsEnabled() then
            exit;
        Route.SetRange("Result Pending", true);
        Route.SetFilter("Company Name", '%1|%2', CompanyName(), '');
        if Route.FindSet(true) then
            repeat
                Queue.SetRange("Cloud Job ID", Route."Cloud Job ID");
                if Queue.FindFirst() then begin
                    Route.CalcFields("Result Body");
                    Route."Result Body".CreateInStream(Input, TextEncoding::UTF8);
                    Input.ReadText(Body);
                    // Full job/printer/station/format validation still occurs
                    // in the originating company's normal processing context.
                    if Status.TryValidateStoredResult(Body) then begin
                        Status.ApplyStoredResult(Body);
                        Route."Company Name" := CopyStr(CompanyName(), 1, MaxStrLen(Route."Company Name"));
                        Route."Result Pending" := false;
                        Route."Result Applied" := true;
                        Route."Last Error" := '';
                        Clear(Route."Result Body");
                    end else begin
                        Route."Last Error" := CopyStr(GetLastErrorText(), 1, MaxStrLen(Route."Last Error"));
                        ClearLastError();
                    end;
                    Route.Modify();
                    Processed += 1;
                end;
            until (Route.Next() = 0) or (Processed >= MaxResults);
    end;

    procedure CleanupAppliedResults()
    var
        Route: Record "DOPSWHS Environment Print Job";
        Deleted: Integer;
        Retention: Duration;
    begin
        if not IsEnabled() or not IsStatusOwner() then
            exit;
        // Keep idempotency tombstones longer than the queue's seven-day TTL.
        // Unapplied results are deliberately retained for recovery.
        Route.SetRange("Result Applied", true);
        Retention := 24 * 60 * 60 * 1000;
        Retention := 30 * Retention;
        Route.SetFilter(Created, '<%1', CurrentDateTime() - Retention);
        if Route.FindSet(true) then
            repeat
                Route.Delete();
                Deleted += 1;
            until (Route.Next() = 0) or (Deleted >= 100);
    end;
}
