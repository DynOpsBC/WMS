page 72467 "DOPSWHS EDesp Request API"
{
    // E-despatch requests of the handheld (review, edit, send, print).
    //   GET  eDespatchRequests?$filter=status eq 'Draft'
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.getDraft
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.updateDraft { changesJson }
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.send
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.print { format, printerId, copies }   format: 0 A4, 1 80 mm, 2 slip
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.refreshStatus
    //   POST eDespatchRequests({entryNo})/Microsoft.NAV.retry
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'eDespatchRequest';
    EntitySetName = 'eDespatchRequests';
    SourceTable = "DOPSWHS EDesp Request";
    SourceTableView = sorting("Entry No.") order(descending);
    ODataKeyFields = "Entry No.";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo'; }
                field(sourceType; Rec."Source Type") { Caption = 'sourceType'; }
                field(sourceNo; Rec."Source No.") { Caption = 'sourceNo'; }
                field(transferOrderNo; Rec."Transfer Order No.") { Caption = 'transferOrderNo'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(toLocationCode; Rec."To Location Code") { Caption = 'toLocationCode'; }
                field(toBinCode; Rec."To Bin Code") { Caption = 'toBinCode'; }
                field(receiverType; Rec."Receiver Type") { Caption = 'receiverType'; }
                field(receiverNo; Rec."Receiver No.") { Caption = 'receiverNo'; }
                field(receiverName; Rec."Receiver Name") { Caption = 'receiverName'; }
                field(purpose; Rec.Purpose) { Caption = 'purpose'; }
                field(vehiclePlateNo; Rec."Vehicle Plate No.") { Caption = 'vehiclePlateNo'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(editable; Rec.Editable) { Caption = 'editable'; }
                field(eDespatchNo; Rec."Provider Document No.") { Caption = 'eDespatchNo'; }
                field(providerStatus; Rec."Provider Status Text") { Caption = 'providerStatus'; }
                field(lastError; Rec."Last Error") { Caption = 'lastError'; }
                field(skipReason; Rec."Skip Reason") { Caption = 'skipReason'; }
                field(operatorUserId; Rec."Operator User Id") { Caption = 'operatorUserId'; }
                field(createdAt; Rec."Created At") { Caption = 'createdAt'; }
                field(sentAt; Rec."Sent At") { Caption = 'sentAt'; }
                field(printCount; Rec."Print Count") { Caption = 'printCount'; }
                field(fasonReferenceNo; Rec."Fason Reference No.") { Caption = 'fasonReferenceNo'; }
            }
        }
    }

    [ServiceEnabled]
    procedure getDraft(): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        exit(RequestMgt.GetDraftJson(Rec));
    end;

    [ServiceEnabled]
    procedure updateDraft(changesJson: Text): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequestMgt.UpdateDraft(Rec, changesJson);
        exit(RequestMgt.GetDraftJson(Rec));
    end;

    [ServiceEnabled]
    procedure send(): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequestMgt.Submit(Rec);
        exit(RequestMgt.ToJsonText(Rec));
    end;

    [ServiceEnabled]
    procedure print(format: Integer; printerId: Code[50]; copies: Integer): Text
    var
        EDespPrintMgt: Codeunit "DOPSWHS EDesp Print Mgt";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        PrintFormat: Enum "DOPSWHS EDesp Print Format";
        Result: JsonObject;
        ResultText: Text;
    begin
        PrintFormat := Enum::"DOPSWHS EDesp Print Format".FromInteger(format);
        Result.Add('printJobId', EDespPrintMgt.Print(Rec, PrintFormat, printerId, copies));
        Rec.Get(Rec."Entry No.");
        Result.Add('eDespatch', RequestMgt.ToJsonObject(Rec));
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    [ServiceEnabled]
    procedure refreshStatus(): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequestMgt.RefreshStatus(Rec);
        exit(RequestMgt.ToJsonText(Rec));
    end;

    [ServiceEnabled]
    procedure retry(): Text
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        if Rec.Status in [Rec.Status::Error, Rec.Status::WaitingAdapter] then begin
            Rec.Status := Rec.Status::Pending;
            Rec.Modify(true);
        end;
        RequestMgt.EnsureDraft(Rec);
        exit(RequestMgt.ToJsonText(Rec));
    end;
}
