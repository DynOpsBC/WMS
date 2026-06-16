codeunit 72051 "DOPSWHS Print Dispatcher"
{
    Access = Public;

    procedure PrintLPLabel(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50]; Copies: Integer)
    var
        Setup: Record "DOPSWHS Setup";
        Queue: Record "DOPSWHS Print Job Queue";
        LabelReport: Report "DOPSWHS LP Label";
        PrintNode: Codeunit "DOPSWHS PrintNode Client";
        SelfHosted: Codeunit "DOPSWHS Self-Hosted Print Client";
        OutStream: OutStream;
        Zpl: Text;
        ResolvedPrinter: Code[20];
    begin
        if Copies <= 0 then
            Copies := 1;
        Setup.Get('');
        Zpl := LabelReport.BuildZpl(LP);

        if Setup."Print Channel" = Setup."Print Channel"::SelfHosted then begin
            ResolvedPrinter := ResolveSelfHostedPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::LpLabel);
            if ResolvedPrinter = '' then
                Error('No Self-Hosted printer is mapped for LP label printing. Configure Device Printer Mapping or pass a Printer Code.');
            SelfHosted.Enqueue(LP."No.", ResolvedPrinter, Enum::"DOPSWHS Print Format"::ZPL, Zpl, Copies);
            exit;
        end;

        Queue.Init();
        Queue."Source Doc" := LP."No.";
        Queue."Report ID" := Report::"DOPSWHS LP Label";
        Queue."Printer ID" := PrinterId;
        Queue.Channel := Setup."Print Channel";
        Queue."Format" := Enum::"DOPSWHS Print Format"::ZPL;
        Queue.Copies := Copies;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.ZPL.CreateOutStream(OutStream);
        OutStream.WriteText(Zpl);
        Queue.Insert(true);
        if Setup."Print Channel" = Setup."Print Channel"::PrintNode then
            PrintNode.SendPrintJob(Queue, Copies)
        else begin
            Report.Run(Report::"DOPSWHS LP Label", false, false, LP);
            Queue.Status := Queue.Status::Sent;
            Queue.Sent := CurrentDateTime();
            Queue.Modify(true);
        end;
    end;

    procedure QueueReport(SourceDoc: Code[50]; ReportId: Integer)
    var
        Queue: Record "DOPSWHS Print Job Queue";
    begin
        if ReportId = 0 then
            exit;

        Queue.Init();
        Queue."Source Doc" := SourceDoc;
        Queue."Report ID" := ReportId;
        Queue.Status := Queue.Status::Queued;
        Queue.Created := CurrentDateTime();
        Queue.Insert(true);
    end;

    local procedure ResolveSelfHostedPrinter(Candidate: Code[50]; Usage: Enum "DOPSWHS IWX Report Usage"): Code[20]
    var
        Printer: Record "DOPSWHS Printer";
        SelfHosted: Codeunit "DOPSWHS Self-Hosted Print Client";
    begin
        if (Candidate <> '') and Printer.Get(CopyStr(Candidate, 1, MaxStrLen(Printer."Code"))) then
            exit(Printer."Code");
        exit(SelfHosted.ResolvePrinter(CopyStr(UserId(), 1, 50), Usage));
    end;
}
