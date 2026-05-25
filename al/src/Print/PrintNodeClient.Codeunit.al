codeunit 72052 "DOPSWHS PrintNode Client"
{
    Access = Public;

    procedure SendPrintJob(var Queue: Record "DOPSWHS Print Job Queue"; Copies: Integer)
    var
        Client: HttpClient;
        Content: HttpContent;
        Response: HttpResponseMessage;
        Telemetry: Codeunit "DOPSWHS Telemetry";
        ApiKey: Text;
        Payload: Text;
    begin
        ApiKey := GetApiKey();
        if ApiKey = '' then begin
            Telemetry.LogInfo('PrintNode.MissingApiKey', 'PrintNode API key is not configured. Print job remains queued.');
            Log(Queue."Job ID", 'Queued', 'Missing PrintNode API key.');
            exit;
        end;
        Payload := StrSubstNo('{"printerId": "%1", "title": "%2", "contentType": "raw_base64", "content": "", "source": "BCWMSApp", "qty": %3}', Queue."Printer ID", Queue."Source Doc", Copies);
        Content.WriteFrom(Payload);
        Content.GetHeaders().Add('Content-Type', 'application/json');
        Client.DefaultRequestHeaders().Add('Authorization', 'Basic ' + ApiKey);
        Client.Post('https://api.printnode.com/printjobs', Content, Response);
        if Response.IsSuccessStatusCode() then begin
            Queue.Status := Queue.Status::Sent;
            Queue.Sent := CurrentDateTime();
            Queue.Modify(true);
            Log(Queue."Job ID", 'Sent', 'PrintNode accepted job.');
        end else begin
            Queue.Status := Queue.Status::Failed;
            Queue.Modify(true);
            Log(Queue."Job ID", 'Failed', CopyStr(Format(Response.HttpStatusCode()), 1, 250));
        end;
    end;

    local procedure GetApiKey(): Text
    var
        ApiKey: Text;
    begin
        if IsolatedStorage.Get('DOPSWHS.PrintNode.ApiKey', DataScope::Company, ApiKey) then
            exit(ApiKey);
        exit('');
    end;

    local procedure Log(JobId: Integer; Event: Text[100]; Message: Text[250])
    var
        LogEntry: Record "DOPSWHS Print Job Log";
    begin
        LogEntry.Init();
        LogEntry."Job ID" := JobId;
        LogEntry.Event := Event;
        LogEntry.Message := Message;
        LogEntry.DateTime := CurrentDateTime();
        LogEntry.Insert(true);
    end;
}
