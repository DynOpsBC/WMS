codeunit 72450 "DOPSWHS Subcontract EDesp Mgt"
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS Subcontract EDesp Out" = RIMD,
        tabledata "DOPSWHS Subcontract Dispatch" = RM,
        tabledata "Transfer Shipment Header" = RM;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Shipment", 'OnAfterInsertTransShptHeader', '', false, false)]
    local procedure CopyFasonReference(var TransferHeader: Record "Transfer Header"; var TransferShipmentHeader: Record "Transfer Shipment Header")
    begin
        if TransferHeader."DOPSWHS Fason Reference No." = '' then
            exit;
        TransferShipmentHeader."DOPSWHS Fason Reference No." := TransferHeader."DOPSWHS Fason Reference No.";
        TransferShipmentHeader."DOPSWHS Fason Prod. Order No." := TransferHeader."DOPSWHS Fason Prod. Order No.";
        TransferShipmentHeader."DOPSWHS Fason Purch. Order No." := TransferHeader."DOPSWHS Fason Purch. Order No.";
        TransferShipmentHeader."DOPSWHS Fason Operation No." := TransferHeader."DOPSWHS Fason Operation No.";
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Shipment", 'OnAfterTransferOrderPostShipment', '', false, false)]
    local procedure EnqueueAfterPosted(var TransferHeader: Record "Transfer Header"; CommitIsSuppressed: Boolean; PreviewMode: Boolean; var TransferShipmentHeader: Record "Transfer Shipment Header"; InvtPickPutaway: Boolean)
    var
        Outbox: Record "DOPSWHS Subcontract EDesp Out";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        if PreviewMode or (TransferHeader."DOPSWHS Fason Reference No." = '') then
            exit;
        Outbox.SetRange("Posted Transfer Shipment No.", TransferShipmentHeader."No.");
        if Outbox.FindFirst() then
            exit;
        Outbox.Init();
        Outbox."Transfer Order No." := TransferHeader."No.";
        Outbox."Posted Transfer Shipment No." := TransferShipmentHeader."No.";
        Outbox."Reference No." := TransferHeader."DOPSWHS Fason Reference No.";
        Outbox."Prod. Order No." := TransferHeader."DOPSWHS Fason Prod. Order No.";
        Outbox."Purchase Order No." := TransferHeader."DOPSWHS Fason Purch. Order No.";
        Outbox."Operation No." := TransferHeader."DOPSWHS Fason Operation No.";
        Dispatch.SetRange("Transfer Order No.", TransferHeader."No.");
        if Dispatch.FindFirst() then
            Outbox."Subcontractor No." := Dispatch."Subcontractor No.";
        Outbox.Status := 'PENDING';
        Outbox."Created At" := CurrentDateTime();
        Outbox.Insert(true);

        TransferShipmentHeader."DOPSWHS E-Despatch Status" := Outbox.Status;
        TransferShipmentHeader.Modify(true);
        ScheduleSubmission(Outbox);
    end;

    procedure ScheduleSubmission(Outbox: Record "DOPSWHS Subcontract EDesp Out")
    begin
        if not TaskScheduler.CanCreateTask() then
            exit;
        if not TryCreateTask(Outbox) then
            ClearLastError();
    end;

    [TryFunction]
    local procedure TryCreateTask(Outbox: Record "DOPSWHS Subcontract EDesp Out")
    var
        TaskId: Guid;
    begin
        TaskId := TaskScheduler.CreateTask(
            Codeunit::"DOPSWHS Subcontract EDesp Task", 0, true, CompanyName(),
            CurrentDateTime() + 1000, Outbox.RecordId());
    end;

    procedure Submit(EntryNo: Integer)
    var
        Outbox: Record "DOPSWHS Subcontract EDesp Out";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        ProviderDocumentNo: Code[50];
        ErrorText: Text;
        Handled: Boolean;
    begin
        Outbox.LockTable();
        if not Outbox.Get(EntryNo) then
            exit;
        if Outbox.Status = 'SUBMITTED' then
            exit;
        if not TransferShipmentHeader.Get(Outbox."Posted Transfer Shipment No.") then begin
            SetFailure(Outbox, 'Kayıtlı transfer irsaliyesi bulunamadı.');
            exit;
        end;

        Outbox."Attempt Count" += 1;
        Outbox."Last Attempt At" := CurrentDateTime();
        Outbox.Modify(true);
        if not TryProviderSubmit(Outbox, TransferShipmentHeader, ProviderDocumentNo, Handled, ErrorText) then begin
            ErrorText := GetLastErrorText();
            ClearLastError();
            SetFailure(Outbox, ErrorText);
            UpdateShipmentStatus(Outbox);
            exit;
        end;
        if not Handled then begin
            Outbox.Status := 'WAITING_ADAPTER';
            Outbox."Last Error" := 'E-İrsaliye sağlayıcı adaptörü bağlı değil.';
            Outbox.Modify(true);
            UpdateShipmentStatus(Outbox);
            exit;
        end;
        if ErrorText <> '' then begin
            SetFailure(Outbox, ErrorText);
            UpdateShipmentStatus(Outbox);
            exit;
        end;
        if ProviderDocumentNo = '' then begin
            SetFailure(Outbox, 'Sağlayıcı başarılı yanıt verdi ancak E-İrsaliye belge numarası dönmedi.');
            UpdateShipmentStatus(Outbox);
            exit;
        end;

        Outbox.Status := 'SUBMITTED';
        Outbox."Provider Document No." := ProviderDocumentNo;
        Clear(Outbox."Last Error");
        Outbox."Submitted At" := CurrentDateTime();
        Outbox.Modify(true);
        UpdateShipmentStatus(Outbox);
    end;

    [TryFunction]
    local procedure TryProviderSubmit(Outbox: Record "DOPSWHS Subcontract EDesp Out"; TransferShipmentHeader: Record "Transfer Shipment Header"; var ProviderDocumentNo: Code[50]; var Handled: Boolean; var ErrorText: Text)
    begin
        OnSubmitSubcontractEDespatch(Outbox, TransferShipmentHeader, ProviderDocumentNo, Handled, ErrorText);
    end;

    local procedure SetFailure(var Outbox: Record "DOPSWHS Subcontract EDesp Out"; ErrorText: Text)
    begin
        Outbox.Status := 'ERROR';
        Outbox."Last Error" := CopyStr(ErrorText, 1, MaxStrLen(Outbox."Last Error"));
        Outbox.Modify(true);
    end;

    local procedure UpdateShipmentStatus(Outbox: Record "DOPSWHS Subcontract EDesp Out")
    var
        TransferShipmentHeader: Record "Transfer Shipment Header";
        Dispatch: Record "DOPSWHS Subcontract Dispatch";
    begin
        if not TransferShipmentHeader.Get(Outbox."Posted Transfer Shipment No.") then
            exit;
        TransferShipmentHeader."DOPSWHS E-Despatch Status" := Outbox.Status;
        TransferShipmentHeader."DOPSWHS E-Despatch Document No." := Outbox."Provider Document No.";
        TransferShipmentHeader.Modify(true);
        Dispatch.SetRange("Posted Transfer Shipment No.", Outbox."Posted Transfer Shipment No.");
        Dispatch.ModifyAll("E-Despatch Status", Outbox.Status);
        Dispatch.ModifyAll("E-Despatch Document No.", Outbox."Provider Document No.");
    end;

    [IntegrationEvent(false, false)]
    procedure OnSubmitSubcontractEDespatch(Outbox: Record "DOPSWHS Subcontract EDesp Out"; TransferShipmentHeader: Record "Transfer Shipment Header"; var ProviderDocumentNo: Code[50]; var Handled: Boolean; var ErrorText: Text)
    begin
    end;
}
