codeunit 72455 "DOPSWHS EDesp Request Mgt"
{
    // E-despatch requests of the handheld (ADR-TED-002). WMS never builds the legal document: it raises the
    // integration events below and a provider adapter (the DynOps WMS e-Despatch Connector) answers them.
    // Without an adapter a request ends in WaitingAdapter and the stock posting is never rolled back.
    Access = Public;
    Permissions =
        tabledata "DOPSWHS EDesp Request" = RIMD,
        tabledata "DOPSWHS EDesp Request Line" = RIMD;

    var
        RequestNotFoundErr: Label 'E-despatch request %1 was not found.', Comment = '%1 = entry no.';
        NotEditableErr: Label 'E-despatch %1 is %2 and can no longer be changed.', Comment = '%1 = e-despatch no., %2 = status';
        NoAdapterTxt: Label 'No e-despatch provider is connected. Install the DynOps WMS e-Despatch Connector.';
        VehicleRequiredErr: Label 'Enter the vehicle plate before sending the e-despatch.';
        DriverRequiredErr: Label 'Enter the driver first and family name, or a carrier, before sending the e-despatch.';
        InvalidJsonErr: Label 'The e-despatch data is not valid JSON.';
        ProviderCodeTok: Label 'DYNOPSETRANS', Locked = true;

    procedure IsEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then
            exit(false);
        exit(Setup."EDesp Integration Enabled");
    end;

    /// <summary>
    /// Returns the request of a posted or registered source document, creating it when needed.
    /// OverridesJson may carry receiverType, receiverNo, receiverAddressCode, purpose, toBinCode, vehiclePlateNo,
    /// trailerPlateNo, driverFirstName, driverFamilyName, driverIdentificationNo, shippingAgentCode and note.
    /// </summary>
    procedure CreateForSource(SourceType: Enum "DOPSWHS EDesp Source Type"; SourceNo: Code[20]; LocationCode: Code[10]; ToLocationCode: Code[10]; OverridesJson: Text; OperatorUserId: Code[50]; IdempotencyKey: Guid; var Request: Record "DOPSWHS EDesp Request")
    begin
        if FindForSource(SourceType, SourceNo, Request) then begin
            if (OverridesJson <> '') and IsLocalDraft(Request) then begin
                ApplyChangesText(Request, OverridesJson);
                Request.Modify(true);
            end;
            exit;
        end;

        Request.Init();
        Request."Source Type" := SourceType;
        Request."Source No." := SourceNo;
        Request."Location Code" := LocationCode;
        Request."To Location Code" := ToLocationCode;
        Request.Status := Request.Status::Pending;
        Request.Editable := true;
        Request."Created At" := CurrentDateTime();
        Request."Operator User Id" := OperatorUserId;
        Request."Idempotency Key" := IdempotencyKey;
        if OverridesJson <> '' then
            ApplyChangesText(Request, OverridesJson);
        Request.Insert(true);
    end;

    procedure FindForSource(SourceType: Enum "DOPSWHS EDesp Source Type"; SourceNo: Code[20]; var Request: Record "DOPSWHS EDesp Request"): Boolean
    begin
        Request.Reset();
        if SourceNo = '' then
            exit(false);
        Request.SetCurrentKey("Source Type", "Source No.");
        Request.SetRange("Source Type", SourceType);
        Request.SetRange("Source No.", SourceNo);
        exit(Request.FindLast());
    end;

    procedure FindByIdempotencyKey(IdempotencyKey: Guid; var Request: Record "DOPSWHS EDesp Request"): Boolean
    begin
        Request.Reset();
        if IsNullGuid(IdempotencyKey) then
            exit(false);
        Request.SetCurrentKey("Idempotency Key");
        Request.SetRange("Idempotency Key", IdempotencyKey);
        exit(Request.FindFirst());
    end;

    procedure GetRequest(EntryNo: Integer; var Request: Record "DOPSWHS EDesp Request")
    begin
        if not Request.Get(EntryNo) then
            Error(RequestNotFoundErr, EntryNo);
    end;

    /// <summary>
    /// Asks the provider to build the draft. Commits first: a provider error never undoes the posting.
    /// </summary>
    procedure EnsureDraft(var Request: Record "DOPSWHS EDesp Request")
    begin
        if Request.Status in [Request.Status::Draft, Request.Status::Sending, Request.Status::Sent, Request.Status::Accepted, Request.Status::Rejected, Request.Status::Cancelled, Request.Status::NotRequired] then
            exit;
        RunIsolated(Request, "DOPSWHS EDesp Run Mode"::CreateDraft, '');
    end;

    procedure ScheduleDraft(Request: Record "DOPSWHS EDesp Request")
    begin
        // Inside a posting transaction: the task only starts after the commit.
        if not TaskScheduler.CanCreateTask() then
            exit;
        if not TryCreateDraftTask(Request) then
            ClearLastError();
    end;

    [TryFunction]
    local procedure TryCreateDraftTask(Request: Record "DOPSWHS EDesp Request")
    var
        TaskId: Guid;
    begin
        TaskId := TaskScheduler.CreateTask(Codeunit::"DOPSWHS EDesp Request Task", 0, true, CompanyName(), CurrentDateTime() + 2000, Request.RecordId());
    end;

    procedure UpdateDraft(var Request: Record "DOPSWHS EDesp Request"; ChangesJson: Text)
    begin
        if not Request.Editable and not (Request.Status in [Request.Status::Pending, Request.Status::WaitingAdapter, Request.Status::Error]) then
            Error(NotEditableErr, Request."Provider Document No.", Request.Status);
        ApplyChangesText(Request, ChangesJson);
        Request.Modify(true);
        if Request."Provider Entry No." = 0 then
            exit;
        RunIsolated(Request, "DOPSWHS EDesp Run Mode"::UpdateDraft, ChangesJson);
    end;

    procedure Submit(var Request: Record "DOPSWHS EDesp Request")
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if Request.Status in [Request.Status::Sent, Request.Status::Accepted, Request.Status::Sending] then
            exit;
        if Setup.Get('') then
            if Setup."EDesp Require Vehicle Info" then begin
                if Request."Vehicle Plate No." = '' then
                    Error(VehicleRequiredErr);
                if (Request."Shipping Agent Code" = '') and ((Request."Driver First Name" = '') or (Request."Driver Family Name" = '')) then
                    Error(DriverRequiredErr);
            end;
        if Request."Provider Entry No." = 0 then
            EnsureDraft(Request);
        if Request.Status in [Request.Status::WaitingAdapter, Request.Status::NotRequired] then
            exit;
        RunIsolated(Request, "DOPSWHS EDesp Run Mode"::Submit, '');
    end;

    procedure RefreshStatus(var Request: Record "DOPSWHS EDesp Request")
    begin
        if Request."Provider Entry No." = 0 then begin
            EnsureDraft(Request);
            exit;
        end;
        RunIsolated(Request, "DOPSWHS EDesp Run Mode"::RefreshStatus, '');
    end;

    /// <summary>
    /// Returns the request and, when the provider answers, the full draft (receiver, addresses, carrier, lines) as JSON.
    /// </summary>
    procedure GetDraftJson(var Request: Record "DOPSWHS EDesp Request"): Text
    var
        DraftJson: JsonObject;
        ResultText: Text;
        Handled: Boolean;
    begin
        DraftJson := ToJsonObject(Request);
        OnGetEDespatchDraft(Request, DraftJson, Handled);
        DraftJson.WriteTo(ResultText);
        exit(ResultText);
    end;

    procedure ToJsonText(Request: Record "DOPSWHS EDesp Request"): Text
    var
        ResultText: Text;
    begin
        ToJsonObject(Request).WriteTo(ResultText);
        exit(ResultText);
    end;

    procedure ToJsonObject(Request: Record "DOPSWHS EDesp Request") Result: JsonObject
    begin
        Request.CalcFields("Line Count", "Total Quantity");
        Result.Add('entryNo', Request."Entry No.");
        Result.Add('sourceType', Request."Source Type".AsInteger());
        Result.Add('sourceTypeCaption', Format(Request."Source Type"));
        Result.Add('sourceNo', Request."Source No.");
        Result.Add('transferOrderNo', Request."Transfer Order No.");
        Result.Add('locationCode', Request."Location Code");
        Result.Add('toLocationCode', Request."To Location Code");
        Result.Add('fromBinCode', Request."From Bin Code");
        Result.Add('toBinCode', Request."To Bin Code");
        Result.Add('receiverType', Request."Receiver Type".AsInteger());
        Result.Add('receiverNo', Request."Receiver No.");
        Result.Add('receiverAddressCode', Request."Receiver Address Code");
        Result.Add('receiverName', Request."Receiver Name");
        Result.Add('receiverIdentificationNo', Request."Receiver Identification No.");
        Result.Add('receiverAlias', Request."Receiver Alias");
        Result.Add('receiverRegistered', Request."Receiver Registered");
        Result.Add('deliveryAddress', Request."Delivery Address");
        Result.Add('purpose', Request.Purpose.AsInteger());
        Result.Add('vehiclePlateNo', Request."Vehicle Plate No.");
        Result.Add('trailerPlateNo', Request."Trailer Plate No.");
        Result.Add('driverFirstName', Request."Driver First Name");
        Result.Add('driverFamilyName', Request."Driver Family Name");
        Result.Add('driverIdentificationNo', Request."Driver Identification No.");
        Result.Add('shippingAgentCode', Request."Shipping Agent Code");
        Result.Add('note', Request.Note);
        Result.Add('status', Request.Status.AsInteger());
        Result.Add('statusCaption', Format(Request.Status));
        Result.Add('editable', Request.Editable and IsEditableStatus(Request.Status));
        Result.Add('provider', Request."Provider Code");
        Result.Add('eDespatchNo', Request."Provider Document No.");
        if not IsNullGuid(Request.ETTN) then
            Result.Add('ettn', Format(Request.ETTN, 0, 4))
        else
            Result.Add('ettn', '');
        Result.Add('providerStatus', Request."Provider Status Text");
        Result.Add('lastError', Request."Last Error");
        Result.Add('skipReason', Request."Skip Reason");
        Result.Add('lineCount', Request."Line Count");
        Result.Add('totalQuantity', Request."Total Quantity");
        Result.Add('printCount', Request."Print Count");
        Result.Add('fasonReferenceNo', Request."Fason Reference No.");
    end;

    /// <summary>
    /// Called by a provider adapter when it created or found the e-despatch of a request.
    /// </summary>
    procedure RegisterProviderDocument(var Request: Record "DOPSWHS EDesp Request"; ProviderEntryNo: Integer; DocumentNo: Code[50]; NewEttn: Guid)
    begin
        Request."Provider Code" := ProviderCodeTok;
        Request."Provider Entry No." := ProviderEntryNo;
        Request."Provider Document No." := DocumentNo;
        Request.ETTN := NewEttn;
        if Request.Status in [Request.Status::Pending, Request.Status::WaitingAdapter, Request.Status::Error] then
            Request.Status := Request.Status::Draft;
        Request.Editable := true;
        Request."Last Error" := '';
        Request.Modify(true);
    end;

    /// <summary>
    /// Called by a provider adapter when the status of the e-despatch changed.
    /// </summary>
    procedure ApplyProviderStatus(var Request: Record "DOPSWHS EDesp Request"; NewStatus: Enum "DOPSWHS EDesp Status"; StatusText: Text; IsEditable: Boolean; DocumentNo: Code[50]; LastError: Text)
    begin
        Request.Status := NewStatus;
        Request."Provider Status Text" := CopyStr(StatusText, 1, MaxStrLen(Request."Provider Status Text"));
        Request.Editable := IsEditable;
        if DocumentNo <> '' then
            Request."Provider Document No." := DocumentNo;
        Request."Last Error" := CopyStr(LastError, 1, MaxStrLen(Request."Last Error"));
        if (NewStatus in [NewStatus::Sent, NewStatus::Accepted]) and (Request."Sent At" = 0DT) then
            Request."Sent At" := CurrentDateTime();
        Request.Modify(true);
        UpdateLegacyShipmentFields(Request);
    end;

    procedure FindByProviderEntryNo(ProviderEntryNo: Integer; var Request: Record "DOPSWHS EDesp Request"): Boolean
    begin
        Request.Reset();
        if ProviderEntryNo = 0 then
            exit(false);
        Request.SetCurrentKey("Provider Entry No.");
        Request.SetRange("Provider Entry No.", ProviderEntryNo);
        exit(Request.FindFirst());
    end;

    procedure ApplyChangesText(var Request: Record "DOPSWHS EDesp Request"; ChangesJson: Text)
    var
        Changes: JsonObject;
    begin
        if ChangesJson = '' then
            exit;
        if not Changes.ReadFrom(ChangesJson) then
            Error(InvalidJsonErr);
        ApplyChanges(Request, Changes);
    end;

    procedure ApplyChanges(var Request: Record "DOPSWHS EDesp Request"; Changes: JsonObject)
    var
        ReceiverTypeText: Text;
        PurposeText: Text;
    begin
        if Changes.Contains('receiverType') then begin
            ReceiverTypeText := JsonText(Changes, 'receiverType');
            Request."Receiver Type" := ParseReceiverType(ReceiverTypeText);
            Request."Receiver No." := '';
            Request."Receiver Address Code" := '';
            Request."Receiver Name" := '';
            Request."Receiver Identification No." := '';
            Request."Receiver Alias" := '';
        end;
        if Changes.Contains('receiverNo') then
            Request."Receiver No." := CopyStr(JsonText(Changes, 'receiverNo'), 1, MaxStrLen(Request."Receiver No."));
        if Changes.Contains('receiverAddressCode') then
            Request."Receiver Address Code" := CopyStr(JsonText(Changes, 'receiverAddressCode'), 1, MaxStrLen(Request."Receiver Address Code"));
        if Changes.Contains('purpose') then begin
            PurposeText := JsonText(Changes, 'purpose');
            Request.Purpose := ParsePurpose(PurposeText);
        end;
        if Changes.Contains('toBinCode') then
            Request."To Bin Code" := CopyStr(JsonText(Changes, 'toBinCode'), 1, MaxStrLen(Request."To Bin Code"));
        if Changes.Contains('vehiclePlateNo') then
            Request."Vehicle Plate No." := CopyStr(NormalizePlate(JsonText(Changes, 'vehiclePlateNo')), 1, MaxStrLen(Request."Vehicle Plate No."));
        if Changes.Contains('trailerPlateNo') then
            Request."Trailer Plate No." := CopyStr(NormalizePlate(JsonText(Changes, 'trailerPlateNo')), 1, MaxStrLen(Request."Trailer Plate No."));
        if Changes.Contains('driverFirstName') then
            Request."Driver First Name" := CopyStr(JsonText(Changes, 'driverFirstName'), 1, MaxStrLen(Request."Driver First Name"));
        if Changes.Contains('driverFamilyName') then
            Request."Driver Family Name" := CopyStr(JsonText(Changes, 'driverFamilyName'), 1, MaxStrLen(Request."Driver Family Name"));
        if Changes.Contains('driverIdentificationNo') then
            Request."Driver Identification No." := CopyStr(JsonText(Changes, 'driverIdentificationNo'), 1, MaxStrLen(Request."Driver Identification No."));
        if Changes.Contains('shippingAgentCode') then
            Request."Shipping Agent Code" := CopyStr(JsonText(Changes, 'shippingAgentCode'), 1, MaxStrLen(Request."Shipping Agent Code"));
        if Changes.Contains('note') then
            Request.Note := CopyStr(JsonText(Changes, 'note'), 1, MaxStrLen(Request.Note));
    end;

    procedure IsEditableStatus(Status: Enum "DOPSWHS EDesp Status"): Boolean
    begin
        exit(Status in [Status::Pending, Status::Draft, Status::Error, Status::WaitingAdapter]);
    end;

    procedure IsLocalDraft(Request: Record "DOPSWHS EDesp Request"): Boolean
    begin
        exit((Request."Provider Entry No." = 0) and IsEditableStatus(Request.Status));
    end;

    procedure ParseReceiverType(Value: Text): Enum "DOPSWHS EDesp Receiver Type"
    begin
        case LowerCase(DelChr(Value, '=', ' ')) of
            '1', 'owncompany', 'own', 'company':
                exit("DOPSWHS EDesp Receiver Type"::OwnCompany);
            '2', 'vendor', 'tedarikci', 'tedarikçi':
                exit("DOPSWHS EDesp Receiver Type"::Vendor);
            '3', 'customer', 'musteri', 'müşteri':
                exit("DOPSWHS EDesp Receiver Type"::Customer);
        end;
        exit("DOPSWHS EDesp Receiver Type"::" ");
    end;

    procedure ParsePurpose(Value: Text): Enum "DOPSWHS EDesp Purpose"
    begin
        case LowerCase(DelChr(Value, '=', ' ')) of
            '1', 'interlocation', 'transfer':
                exit("DOPSWHS EDesp Purpose"::InterLocation);
            '2', 'subcontracting', 'fason':
                exit("DOPSWHS EDesp Purpose"::Subcontracting);
            '3', 'consignment', 'konsinye':
                exit("DOPSWHS EDesp Purpose"::Consignment);
            '4', 'other':
                exit("DOPSWHS EDesp Purpose"::Other);
        end;
        exit("DOPSWHS EDesp Purpose"::" ");
    end;

    procedure MarkPrinted(var Request: Record "DOPSWHS EDesp Request"; PrintFormat: Enum "DOPSWHS EDesp Print Format")
    begin
        Request.Get(Request."Entry No.");
        if PrintFormat = PrintFormat::Thermal80 then
            Request."Printed Thermal" := true
        else
            Request."Printed A4" := true;
        Request."Print Count" += 1;
        Request."Last Printed At" := CurrentDateTime();
        Request.Modify(true);
    end;

    /// <summary>
    /// Runs one provider step in its own transaction (Commit, then Codeunit.Run) and stores the outcome.
    /// </summary>
    procedure RunIsolated(var Request: Record "DOPSWHS EDesp Request"; RunMode: Enum "DOPSWHS EDesp Run Mode"; Payload: Text)
    var
        Runner: Codeunit "DOPSWHS EDesp Request Runner";
        ErrorText: Text;
    begin
        Request.Get(Request."Entry No.");
        Request."Attempt Count" += 1;
        Request."Last Attempt At" := CurrentDateTime();
        Request.Modify(true);
        Commit();

        ClearLastError();
        Runner.SetMode(RunMode, Payload);
        if Runner.Run(Request) then begin
            Request.Get(Request."Entry No.");
            exit;
        end;

        ErrorText := GetLastErrorText();
        Request.Get(Request."Entry No.");
        if RunMode in ["DOPSWHS EDesp Run Mode"::CreateDraft, "DOPSWHS EDesp Run Mode"::Submit] then
            Request.Status := Request.Status::Error;
        Request."Last Error" := CopyStr(ErrorText, 1, MaxStrLen(Request."Last Error"));
        Request.Modify(true);
        Commit();
    end;

    /// <summary>
    /// Body of the isolated provider steps. Called by the runner codeunit only.
    /// </summary>
    procedure ExecuteMode(var Request: Record "DOPSWHS EDesp Request"; RunMode: Enum "DOPSWHS EDesp Run Mode"; Payload: Text)
    var
        Changes: JsonObject;
        Handled: Boolean;
        ErrorText: Text;
    begin
        case RunMode of
            "DOPSWHS EDesp Run Mode"::CreateDraft:
                begin
                    OnCreateEDespatchDraft(Request, Handled, ErrorText);
                    if not Handled then begin
                        Request.Get(Request."Entry No.");
                        Request.Status := Request.Status::WaitingAdapter;
                        Request."Last Error" := NoAdapterTxt;
                        Request.Modify(true);
                        exit;
                    end;
                end;
            "DOPSWHS EDesp Run Mode"::UpdateDraft:
                begin
                    if Payload <> '' then
                        if not Changes.ReadFrom(Payload) then
                            Error(InvalidJsonErr);
                    OnUpdateEDespatchDraft(Request, Changes, Handled, ErrorText);
                end;
            "DOPSWHS EDesp Run Mode"::Submit:
                begin
                    OnSubmitEDespatch(Request, Handled, ErrorText);
                    if not Handled then begin
                        Request.Get(Request."Entry No.");
                        Request.Status := Request.Status::WaitingAdapter;
                        Request."Last Error" := NoAdapterTxt;
                        Request.Modify(true);
                        exit;
                    end;
                end;
            "DOPSWHS EDesp Run Mode"::RefreshStatus:
                OnRefreshEDespatchStatus(Request, Handled);
        end;
        if ErrorText <> '' then
            Error(ErrorText);
    end;

    local procedure UpdateLegacyShipmentFields(Request: Record "DOPSWHS EDesp Request")
    var
        TransferShipmentHeader: Record "Transfer Shipment Header";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
        StatusCode: Code[20];
    begin
        // Subcontracting screens read the e-despatch status from the posted shipment and the dispatch audit rows.
        if Request."Source Type" <> Request."Source Type"::TransferShipment then
            exit;
        if not TransferShipmentHeader.Get(Request."Source No.") then
            exit;
        StatusCode := 'PENDING';
        case Request.Status of
            Request.Status::Sent, Request.Status::Accepted:
                StatusCode := 'SUBMITTED';
            Request.Status::WaitingAdapter:
                StatusCode := 'WAITING_ADAPTER';
            Request.Status::Error, Request.Status::Rejected:
                StatusCode := 'ERROR';
            Request.Status::Draft, Request.Status::Pending:
                StatusCode := 'PENDING';
        end;
        TransferShipmentHeader."DOPSWHS E-Despatch Status" := StatusCode;
        TransferShipmentHeader."DOPSWHS E-Despatch Document No." := Request."Provider Document No.";
        TransferShipmentHeader.Modify();
        Dispatch.SetRange("Posted Transfer Shipment No.", Request."Source No.");
        Dispatch.ModifyAll("E-Despatch Status", StatusCode);
        Dispatch.ModifyAll("E-Despatch Document No.", Request."Provider Document No.");
    end;

    local procedure NormalizePlate(Value: Text): Text
    begin
        Value := DelChr(Value, '=', ' ');
        exit(UpperCase(ConvertStr(Value, 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')));
    end;

    local procedure JsonText(Source: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    // ---- Integration events for e-despatch providers -------------------------------------------------------

    /// <summary>Raised before a handheld transfer is posted. Copy receiver and carrier values to the transfer header.</summary>
    [IntegrationEvent(false, false)]
    procedure OnBeforePostTransferShipment(var TransferHeader: Record "Transfer Header"; Request: Record "DOPSWHS EDesp Request")
    begin
    end;

    /// <summary>Raised before a movement is registered from the handheld. Copy receiver and carrier values to the activity header.</summary>
    [IntegrationEvent(false, false)]
    procedure OnBeforeRegisterMovement(var WarehouseActivityHeader: Record "Warehouse Activity Header"; Request: Record "DOPSWHS EDesp Request")
    begin
    end;

    /// <summary>Build (or find) the e-despatch draft of the request and call RegisterProviderDocument. Set Handled.</summary>
    [IntegrationEvent(false, false)]
    procedure OnCreateEDespatchDraft(var Request: Record "DOPSWHS EDesp Request"; var Handled: Boolean; var ErrorText: Text)
    begin
    end;

    /// <summary>Add the provider view of the draft (receiver identity, addresses, lines) to DraftJson.</summary>
    [IntegrationEvent(false, false)]
    procedure OnGetEDespatchDraft(Request: Record "DOPSWHS EDesp Request"; var DraftJson: JsonObject; var Handled: Boolean)
    begin
    end;

    /// <summary>Apply the changed values (already stored on the request) to the provider draft.</summary>
    [IntegrationEvent(false, false)]
    procedure OnUpdateEDespatchDraft(var Request: Record "DOPSWHS EDesp Request"; Changes: JsonObject; var Handled: Boolean; var ErrorText: Text)
    begin
    end;

    /// <summary>Send the e-despatch to the integrator and call ApplyProviderStatus. Set Handled.</summary>
    [IntegrationEvent(false, false)]
    procedure OnSubmitEDespatch(var Request: Record "DOPSWHS EDesp Request"; var Handled: Boolean; var ErrorText: Text)
    begin
    end;

    /// <summary>Read the current status from the integrator and call ApplyProviderStatus.</summary>
    [IntegrationEvent(false, false)]
    procedure OnRefreshEDespatchStatus(var Request: Record "DOPSWHS EDesp Request"; var Handled: Boolean)
    begin
    end;

    /// <summary>Return the PDF of the e-despatch in the asked format.</summary>
    [IntegrationEvent(false, false)]
    procedure OnGetEDespatchPdf(Request: Record "DOPSWHS EDesp Request"; PrintFormat: Enum "DOPSWHS EDesp Print Format"; var TempBlob: Codeunit "Temp Blob"; var FileName: Text; var Handled: Boolean; var ErrorText: Text)
    begin
    end;

    /// <summary>Preview the receiver of goods going to a location and bin, for the handheld before posting.</summary>
    [IntegrationEvent(false, false)]
    procedure OnResolveEDespatchReceiver(FromLocationCode: Code[10]; FromBinCode: Code[20]; ToLocationCode: Code[10]; ToBinCode: Code[20]; var ReceiverJson: JsonObject; var Handled: Boolean)
    begin
    end;
}
