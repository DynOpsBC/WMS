codeunit 72460 "DOPSWHS EDesp Print Mgt"
{
    // Prints e-despatches from the handheld through the WMS print channels (ADR-TED-006).
    // A4 and 80 mm PDFs come from the provider; without a provider an A4 shipment slip report can be printed.
    Access = Public;

    var
        NoPdfErr: Label 'No e-despatch PDF is available for request %1. Connect an e-despatch provider or print the shipment slip.', Comment = '%1 = request entry no.';
        NoFallbackReportErr: Label 'No shipment slip report is set up for %1. Fill Shipment Slip Report ID on Advanced WMS Setup.', Comment = '%1 = source type';
        SourceNotFoundErr: Label '%1 %2 was not found.', Comment = '%1 = source type, %2 = source no.';
        TransferShipmentReportTok: Label '5704', Locked = true;

    procedure Print(var Request: Record "DOPSWHS EDesp Request"; PrintFormat: Enum "DOPSWHS EDesp Print Format"; PrinterId: Code[50]; Copies: Integer): Integer
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        TempBlob: Codeunit "Temp Blob";
        FileName: Text;
        ErrorText: Text;
        Handled: Boolean;
        JobId: Integer;
    begin
        Copies := ResolveCopies(Copies);
        if PrintFormat = PrintFormat::A4Fallback then
            exit(PrintFallback(Request, PrinterId, Copies));

        RequestMgt.OnGetEDespatchPdf(Request, PrintFormat, TempBlob, FileName, Handled, ErrorText);
        if ErrorText <> '' then
            Error(ErrorText);
        if not Handled or not TempBlob.HasValue() then begin
            if PrintFormat = PrintFormat::A4Official then
                exit(PrintFallback(Request, PrinterId, Copies));
            Error(NoPdfErr, Request."Entry No.");
        end;

        JobId := PrintDispatcher.PrintPdf(SourceDocFor(Request), PrinterId, Copies, UsageFor(PrintFormat), TempBlob);
        RequestMgt.MarkPrinted(Request, PrintFormat);
        exit(JobId);
    end;

    procedure UsageFor(PrintFormat: Enum "DOPSWHS EDesp Print Format"): Enum "DOPSWHS IWX Report Usage"
    begin
        if PrintFormat = PrintFormat::Thermal80 then
            exit("DOPSWHS IWX Report Usage"::EDespatchThermal);
        exit("DOPSWHS IWX Report Usage"::EDespatch);
    end;

    local procedure PrintFallback(var Request: Record "DOPSWHS EDesp Request"; PrinterId: Code[50]; Copies: Integer): Integer
    var
        Setup: Record "DOPSWHS Setup";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceRecRef: RecordRef;
        ReportId: Integer;
        JobId: Integer;
    begin
        if Setup.Get('') then
            ReportId := Setup."EDesp Fallback Report ID";
        case Request."Source Type" of
            Request."Source Type"::TransferShipment:
                begin
                    if not TransferShipmentHeader.Get(Request."Source No.") then
                        Error(SourceNotFoundErr, Request."Source Type", Request."Source No.");
                    TransferShipmentHeader.SetRecFilter();
                    SourceRecRef.GetTable(TransferShipmentHeader);
                    if ReportId = 0 then
                        Evaluate(ReportId, TransferShipmentReportTok);
                end;
            else
                // Other sources have no standard slip report; a custom report must take the request as source.
                begin
                    if ReportId = 0 then
                        Error(NoFallbackReportErr, Request."Source Type");
                    Request.SetRecFilter();
                    SourceRecRef.GetTable(Request);
                end;
        end;
        JobId := PrintDispatcher.PrintReport(SourceDocFor(Request), ReportId, PrinterId, Copies, "DOPSWHS IWX Report Usage"::EDespatch, SourceRecRef);
        RequestMgt.MarkPrinted(Request, "DOPSWHS EDesp Print Format"::A4Fallback);
        exit(JobId);
    end;

    local procedure ResolveCopies(Copies: Integer): Integer
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if Copies > 0 then
            exit(Copies);
        if Setup.Get('') then
            if Setup."EDesp Print Copies" > 0 then
                exit(Setup."EDesp Print Copies");
        exit(1);
    end;

    local procedure SourceDocFor(Request: Record "DOPSWHS EDesp Request"): Code[50]
    begin
        if Request."Provider Document No." <> '' then
            exit(Request."Provider Document No.");
        exit(Request."Source No.");
    end;
}
