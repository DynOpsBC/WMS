codeunit 72051 "DOPSWHS Print Dispatcher"
{
    Access = Public;

    procedure PrintLPLabel(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
    var
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        LabelReport: Report "DOPSWHS LP Label";
        Client: Codeunit "DOPSWHS PrintNode Client";
        OutStream: OutStream;
        Zpl: Text;
    begin
        if Copies <= 0 then
            Copies := 1;
        Setup.Get('');
        Zpl := LabelReport.BuildZpl(LP);
        Queue.Init();
        Queue."Source Doc" := LP."No.";
        Queue."Report ID" := Report::"DOPSWHS LP Label";
        Queue."Printer ID" := PrinterId;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.ZPL.CreateOutStream(OutStream);
        OutStream.WriteText(Zpl);
        Queue.Insert(true);
        if Setup."Print Channel" = Setup."Print Channel"::PrintNode then
            Client.SendPrintJob(Queue, Copies)
        else
            Report.Run(Report::"DOPSWHS LP Label", false, false, LP);
    end;
}
