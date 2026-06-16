codeunit 72081 "DOPSWHS Self-Hosted Print Client"
{
    Access = Public;

    procedure Enqueue(SourceDoc: Code[50]; PrinterCode: Code[20]; Format: Enum "DOPSWHS Print Format"; Payload: Text; Copies: Integer): Integer
    var
        Printer: Record "DOPSWHS Printer";
        Queue: Record "DOPSWHS Print Job Queue";
        OutStream: OutStream;
    begin
        if not Printer.Get(PrinterCode) then
            Error('Printer %1 is not registered.', PrinterCode);
        if not Printer.Active then
            Error('Printer %1 is inactive.', PrinterCode);
        if Copies <= 0 then
            Copies := Printer."Default Copies";
        if Copies <= 0 then
            Copies := 1;

        Queue.Init();
        Queue."Source Doc" := SourceDoc;
        Queue."Printer ID" := Printer."Code";
        Queue.Channel := Queue.Channel::SelfHosted;
        Queue."Format" := Format;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.Copies := Copies;
        Queue."Payload Size" := StrLen(Payload);
        Queue.ZPL.CreateOutStream(OutStream);
        OutStream.WriteText(Payload);
        Queue.Insert(true);
        Log(Queue."Job ID", 'Queued', StrSubstNo('SelfHosted job queued for %1 (%2 bytes).', Printer."Code", StrLen(Payload)));
        exit(Queue."Job ID");
    end;

    procedure RotateToken(PrinterCode: Code[20]): Text
    var
        Printer: Record "DOPSWHS Printer";
        TypeHelper: Codeunit "Cryptography Management";
        Random: Text;
        Hash: Text;
    begin
        Printer.Get(PrinterCode);
        Random := NewSecret();
        Hash := TypeHelper.GenerateHash(Random, 3); // 3 = HashAlgorithmType::SHA256
        Printer."Token Hash" := CopyStr(Hash, 1, MaxStrLen(Printer."Token Hash"));
        Printer."Token Issued At" := CurrentDateTime();
        Printer.Modify(true);
        // Only the hash is persisted; the plain secret returned here is shown to the caller
        // once (Card UI / API response) and then lives only in the agent's config.json.
        exit(Random);
    end;

    procedure VerifyToken(PrinterCode: Code[20]; CandidateToken: Text): Boolean
    var
        Printer: Record "DOPSWHS Printer";
        TypeHelper: Codeunit "Cryptography Management";
        Hash: Text;
    begin
        if not Printer.Get(PrinterCode) then
            exit(false);
        if Printer."Token Hash" = '' then
            exit(false);
        Hash := TypeHelper.GenerateHash(CandidateToken, 3);
        exit(Hash = Printer."Token Hash");
    end;

    procedure MarkClaimed(JobId: Integer; AgentId: Code[50]): Boolean
    var
        Queue: Record "DOPSWHS Print Job Queue";
    begin
        Queue.LockTable();
        if not Queue.Get(JobId) then
            exit(false);
        if Queue.Status <> Queue.Status::Queued then
            exit(false);
        if Queue."Agent ID" <> '' then
            exit(false);
        Queue."Agent ID" := AgentId;
        Queue."Claimed At" := CurrentDateTime();
        Queue.Modify(true);
        Log(JobId, 'Claimed', StrSubstNo('Claimed by agent %1.', AgentId));
        exit(true);
    end;

    procedure MarkStatus(JobId: Integer; Success: Boolean; Message: Text)
    var
        Queue: Record "DOPSWHS Print Job Queue";
    begin
        if not Queue.Get(JobId) then
            exit;
        if Success then begin
            Queue.Status := Queue.Status::Sent;
            Queue.Sent := CurrentDateTime();
        end else begin
            Queue.Status := Queue.Status::Failed;
            Queue."Last Error" := CopyStr(Message, 1, MaxStrLen(Queue."Last Error"));
            Queue."Retry Count" += 1;
        end;
        Queue.Modify(true);
        if Success then
            Log(JobId, 'Sent', 'Agent confirmed delivery.')
        else
            Log(JobId, 'Failed', CopyStr(Message, 1, 250));
    end;

    procedure EnqueueSelfTest(PrinterCode: Code[20]): Integer
    var
        Zpl: Text;
    begin
        Zpl := '^XA^FO50,50^A0N,40,40^FDDynOps WMS Self-Test^FS^FO50,120^A0N,30,30^FDPrinter: ' + PrinterCode + '^FS^FO50,180^BCN,80,Y,N,N^FD' + Format(CurrentDateTime(), 0, 9) + '^FS^XZ';
        exit(Enqueue('SELFTEST', PrinterCode, Enum::"DOPSWHS Print Format"::ZPL, Zpl, 1));
    end;

    procedure ResolvePrinter(DeviceId: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage"): Code[20]
    var
        Map: Record "DOPSWHS Device Printer Map";
    begin
        if DeviceId <> '' then
            if Map.Get(DeviceId, Usage) then
                exit(Map."Printer Code");
        if Map.Get('', Usage) then
            exit(Map."Printer Code");
        exit('');
    end;

    local procedure NewSecret(): Text
    var
        Guid1: Guid;
        Guid2: Guid;
        Combined: Text;
    begin
        Guid1 := CreateGuid();
        Guid2 := CreateGuid();
        Combined := DelChr(Format(Guid1), '=', '{}-') + DelChr(Format(Guid2), '=', '{}-');
        exit(Combined);
    end;

    local procedure Log(JobId: Integer; EventType: Text[100]; Message: Text[250])
    var
        LogEntry: Record "DOPSWHS Print Job Log";
    begin
        LogEntry.Init();
        LogEntry."Job ID" := JobId;
        LogEntry.EventType := EventType;
        LogEntry.Message := Message;
        LogEntry.DateTime := CurrentDateTime();
        LogEntry.Insert(true);
    end;
}
