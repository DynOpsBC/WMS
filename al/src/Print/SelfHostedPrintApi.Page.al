page 72299 "DOPSWHS Print Job API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'printJob';
    EntitySetName = 'printJobs';
    SourceTable = "DOPSWHS Print Job Queue";
    DelayedInsert = true;
    ODataKeyFields = "Job ID";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(jobId; Rec."Job ID") { Caption = 'jobId'; }
                field(sourceDoc; Rec."Source Doc") { Caption = 'sourceDoc'; }
                field(printerId; Rec."Printer ID") { Caption = 'printerId'; }
                field(channel; Rec.Channel) { Caption = 'channel'; }
                field(format; Rec."Format") { Caption = 'format'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(copies; Rec.Copies) { Caption = 'copies'; }
                field(payload; PayloadBase64) { Caption = 'payload'; }
                field(payloadSize; Rec."Payload Size") { Caption = 'payloadSize'; }
                field(createdAt; Rec.Created) { Caption = 'createdAt'; }
                field(sentAt; Rec.Sent) { Caption = 'sentAt'; }
                field(agentId; Rec."Agent ID") { Caption = 'agentId'; }
                field(claimedAt; Rec."Claimed At") { Caption = 'claimedAt'; }
                field(lastError; Rec."Last Error") { Caption = 'lastError'; }
                field(retryCount; Rec."Retry Count") { Caption = 'retryCount'; }
            }
        }
    }

    var
        PayloadBase64: Text;

    trigger OnAfterGetRecord()
    var
        InStream: InStream;
        RawBytes: Text;
        Base64: Codeunit "Base64 Convert";
        TempBlob: Codeunit "Temp Blob";
        TempOut: OutStream;
        TempIn: InStream;
    begin
        Clear(PayloadBase64);
        Rec.CalcFields(ZPL);
        if not Rec.ZPL.HasValue() then
            exit;
        Rec.ZPL.CreateInStream(InStream);
        InStream.ReadText(RawBytes);
        TempBlob.CreateOutStream(TempOut);
        TempOut.WriteText(RawBytes);
        TempBlob.CreateInStream(TempIn);
        PayloadBase64 := Base64.ToBase64(TempIn);
    end;

    [ServiceEnabled]
    procedure claim(agentId: Code[50]): Boolean
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
    begin
        exit(Client.MarkClaimed(Rec."Job ID", agentId));
    end;

    [ServiceEnabled]
    procedure markSuccess(message: Text[250]): Boolean
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
    begin
        Client.MarkStatus(Rec."Job ID", true, message);
        exit(true);
    end;

    [ServiceEnabled]
    procedure markFailure(message: Text[250]): Boolean
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
    begin
        Client.MarkStatus(Rec."Job ID", false, message);
        exit(true);
    end;
}
