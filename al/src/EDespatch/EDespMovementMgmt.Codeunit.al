codeunit 72461 "DOPSWHS EDesp Movement Mgmt"
{
    // Registers warehouse movements and inventory movements from the handheld and creates the e-despatch request
    // of the registered document (bin-to-bin transfers, for example into a subcontractor bin).
    Access = Public;
    Permissions =
        tabledata "DOPSWHS EDesp Request" = RIM;

    var
        UserRequiredErr: Label 'WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.';
        MovementNotFoundErr: Label 'Hareket belgesi %1 artık bulunamıyor. Listeyi yenileyin.', Comment = '%1 = movement no.';
        AssignedToOtherErr: Label 'Hareket belgesi %1, %2 kullanıcısına atanmış.', Comment = '%1 = movement no., %2 = user';
        LineNotFoundErr: Label 'Hareket satırı %1 artık bulunamıyor. Belgeyi yenileyin.', Comment = '%1 = line no.';
        QtyRangeErr: Label '%1 satırı için hareket miktarı 0 ile %2 arasında olmalıdır.', Comment = '%1 = line no., %2 = outstanding quantity';
        NotRegisteredErr: Label 'Hareket %1 kaydedildi ancak kayıtlı belge bulunamadı.', Comment = '%1 = movement no.';
        UnbalancedErr: Label 'Hareket %1 dengesiz: alınan %2, konan %3. Satırları kontrol edin.', Comment = '%1 = movement no., %2 = take quantity, %3 = place quantity';

    /// <summary>
    /// Registers a warehouse movement (Type Movement) or an inventory movement (Type Invt. Movement) and returns
    /// {activityNo, registeredNo, eDespatchRequired, eDespatch}. A retry after a lost response finds the
    /// registered document by the activity no. instead of registering again.
    /// </summary>
    procedure RegisterWithDespatch(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; OperatorUserId: Code[50]; OverridesJson: Text; IdempotencyKey: Guid): Text
    var
        WhseActivityHeader: Record "Warehouse Activity Header";
        TempRequest: Record "DOPSWHS EDesp Request" temporary;
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        RegisteredNo: Code[20];
    begin
        if OperatorUserId = '' then
            Error(UserRequiredErr);

        if not WhseActivityHeader.Get(ActivityType, ActivityNo) then begin
            // Already registered by an earlier call whose response was lost.
            RegisteredNo := FindRegisteredNo(ActivityType, ActivityNo);
            if RegisteredNo = '' then
                Error(MovementNotFoundErr, ActivityNo);
            exit(FinishRegistration(ActivityType, ActivityNo, RegisteredNo, OverridesJson, OperatorUserId, IdempotencyKey));
        end;
        if (WhseActivityHeader."Assigned User ID" <> '') and (WhseActivityHeader."Assigned User ID" <> OperatorUserId) then
            Error(AssignedToOtherErr, ActivityNo, WhseActivityHeader."Assigned User ID");

        TempRequest.Init();
        TempRequest."Location Code" := WhseActivityHeader."Location Code";
        TempRequest."To Location Code" := WhseActivityHeader."Location Code";
        TempRequest."Operator User Id" := OperatorUserId;
        TempRequest."From Bin Code" := FirstBin(WhseActivityHeader, "Warehouse Action Type"::Take);
        TempRequest."To Bin Code" := FirstBin(WhseActivityHeader, "Warehouse Action Type"::Place);
        if OverridesJson <> '' then
            RequestMgt.ApplyChangesText(TempRequest, OverridesJson);
        RequestMgt.OnBeforeRegisterMovement(WhseActivityHeader, TempRequest);
        WhseActivityHeader.Modify(true);

        if ActivityType = ActivityType::Movement then
            MovementMgmt.RegisterDirectedFor(WhseActivityHeader, OperatorUserId)
        else begin
            EnsureBalanced(WhseActivityHeader);
            MovementMgmt.RegisterDirected(WhseActivityHeader, OperatorUserId);
        end;
        Commit();

        RegisteredNo := FindRegisteredNo(ActivityType, ActivityNo);
        if RegisteredNo = '' then
            Error(NotRegisteredErr, ActivityNo);
        exit(FinishRegistration(ActivityType, ActivityNo, RegisteredNo, OverridesJson, OperatorUserId, IdempotencyKey));
    end;

    procedure ClaimInvtMovement(var WhseActivityHeader: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    var
        LockedHeader: Record "Warehouse Activity Header";
    begin
        if RequestingUserId = '' then
            Error(UserRequiredErr);
        LockedHeader.LockTable();
        if not LockedHeader.Get(LockedHeader.Type::"Invt. Movement", WhseActivityHeader."No.") then
            Error(MovementNotFoundErr, WhseActivityHeader."No.");
        if (LockedHeader."Assigned User ID" <> '') and (LockedHeader."Assigned User ID" <> RequestingUserId) then
            Error(AssignedToOtherErr, LockedHeader."No.", LockedHeader."Assigned User ID");
        if LockedHeader."Assigned User ID" <> RequestingUserId then begin
            LockedHeader."Assigned User ID" := CopyStr(RequestingUserId, 1, MaxStrLen(LockedHeader."Assigned User ID"));
            LockedHeader.Modify(true);
        end;
        WhseActivityHeader := LockedHeader;
    end;

    /// <summary>
    /// Sets Qty. to Handle on an inventory movement line and on its Take/Place companion.
    /// </summary>
    procedure ConfirmInvtMovementLine(ActivityNo: Code[20]; LineNo: Integer; QtyToHandle: Decimal; RequestingUserId: Code[50])
    var
        WhseActivityHeader: Record "Warehouse Activity Header";
        WhseActivityLine: Record "Warehouse Activity Line";
        CompanionLine: Record "Warehouse Activity Line";
    begin
        if RequestingUserId = '' then
            Error(UserRequiredErr);
        if not WhseActivityHeader.Get(WhseActivityHeader.Type::"Invt. Movement", ActivityNo) then
            Error(MovementNotFoundErr, ActivityNo);
        if (WhseActivityHeader."Assigned User ID" <> '') and (WhseActivityHeader."Assigned User ID" <> RequestingUserId) then
            Error(AssignedToOtherErr, ActivityNo, WhseActivityHeader."Assigned User ID");
        if not WhseActivityLine.Get(WhseActivityLine."Activity Type"::"Invt. Movement", ActivityNo, LineNo) then
            Error(LineNotFoundErr, LineNo);
        if (QtyToHandle < 0) or (QtyToHandle > WhseActivityLine."Qty. Outstanding") then
            Error(QtyRangeErr, LineNo, WhseActivityLine."Qty. Outstanding");
        WhseActivityLine.Validate("Qty. to Handle", QtyToHandle);
        WhseActivityLine.Modify(true);

        CompanionLine.SetRange("Activity Type", WhseActivityLine."Activity Type");
        CompanionLine.SetRange("No.", WhseActivityLine."No.");
        CompanionLine.SetFilter("Line No.", '<>%1', WhseActivityLine."Line No.");
        CompanionLine.SetRange("Source Type", WhseActivityLine."Source Type");
        CompanionLine.SetRange("Source No.", WhseActivityLine."Source No.");
        CompanionLine.SetRange("Source Line No.", WhseActivityLine."Source Line No.");
        CompanionLine.SetRange("Item No.", WhseActivityLine."Item No.");
        CompanionLine.SetRange("Variant Code", WhseActivityLine."Variant Code");
        CompanionLine.SetRange("Unit of Measure Code", WhseActivityLine."Unit of Measure Code");
        CompanionLine.SetRange("Lot No.", WhseActivityLine."Lot No.");
        CompanionLine.SetRange("Serial No.", WhseActivityLine."Serial No.");
        if WhseActivityLine."Action Type" = WhseActivityLine."Action Type"::Take then
            CompanionLine.SetRange("Action Type", CompanionLine."Action Type"::Place)
        else
            CompanionLine.SetRange("Action Type", CompanionLine."Action Type"::Take);
        if CompanionLine.FindFirst() then begin
            CompanionLine.Validate("Qty. to Handle", QtyToHandle);
            CompanionLine.Modify(true);
        end;
    end;

    local procedure FinishRegistration(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; RegisteredNo: Code[20]; OverridesJson: Text; OperatorUserId: Code[50]; IdempotencyKey: Guid): Text
    var
        Request: Record "DOPSWHS EDesp Request";
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
        Result: JsonObject;
        SourceType: Enum "DOPSWHS EDesp Source Type";
        LocationCode: Code[10];
        FromBinCode: Code[20];
        ToBinCode: Code[20];
        ResultText: Text;
    begin
        Result.Add('activityNo', ActivityNo);
        Result.Add('registeredNo', RegisteredNo);
        if not RequestMgt.IsEnabled() then begin
            Result.Add('eDespatchRequired', false);
            Result.WriteTo(ResultText);
            exit(ResultText);
        end;

        if ActivityType = ActivityType::Movement then
            SourceType := SourceType::RegisteredWhseMovement
        else
            SourceType := SourceType::RegisteredInvtMovement;
        ReadRegisteredBins(ActivityType, RegisteredNo, LocationCode, FromBinCode, ToBinCode);

        if not RequestMgt.FindForSource(SourceType, RegisteredNo, Request) then begin
            RequestMgt.CreateForSource(SourceType, RegisteredNo, LocationCode, LocationCode, OverridesJson, OperatorUserId, IdempotencyKey, Request);
            Request."From Bin Code" := FromBinCode;
            if Request."To Bin Code" = '' then
                Request."To Bin Code" := ToBinCode;
            Request.Modify(true);
            Commit();
        end;
        RequestMgt.EnsureDraft(Request);
        Request.Get(Request."Entry No.");

        Result.Add('eDespatchRequired', not (Request.Status in [Request.Status::NotRequired]));
        Result.Add('eDespatch', RequestMgt.ToJsonObject(Request));
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    local procedure FindRegisteredNo(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]): Code[20]
    var
        RegisteredWhseActivityHdr: Record "Registered Whse. Activity Hdr.";
        RegisteredInvtMovementHdr: Record "Registered Invt. Movement Hdr.";
    begin
        if ActivityType = ActivityType::Movement then begin
            RegisteredWhseActivityHdr.SetCurrentKey("Whse. Activity No.");
            RegisteredWhseActivityHdr.SetRange("Whse. Activity No.", ActivityNo);
            RegisteredWhseActivityHdr.SetRange(Type, RegisteredWhseActivityHdr.Type::Movement);
            if RegisteredWhseActivityHdr.FindLast() then
                exit(RegisteredWhseActivityHdr."No.");
            exit('');
        end;
        RegisteredInvtMovementHdr.SetCurrentKey("Invt. Movement No.");
        RegisteredInvtMovementHdr.SetRange("Invt. Movement No.", ActivityNo);
        if RegisteredInvtMovementHdr.FindLast() then
            exit(RegisteredInvtMovementHdr."No.");
        exit('');
    end;

    local procedure ReadRegisteredBins(ActivityType: Enum "Warehouse Activity Type"; RegisteredNo: Code[20]; var LocationCode: Code[10]; var FromBinCode: Code[20]; var ToBinCode: Code[20])
    var
        RegisteredWhseActivityHdr: Record "Registered Whse. Activity Hdr.";
        RegisteredWhseActivityLine: Record "Registered Whse. Activity Line";
        RegisteredInvtMovementHdr: Record "Registered Invt. Movement Hdr.";
        RegisteredInvtMovementLine: Record "Registered Invt. Movement Line";
    begin
        if ActivityType = ActivityType::Movement then begin
            if RegisteredWhseActivityHdr.Get(RegisteredWhseActivityHdr.Type::Movement, RegisteredNo) then
                LocationCode := RegisteredWhseActivityHdr."Location Code";
            RegisteredWhseActivityLine.SetRange("Activity Type", RegisteredWhseActivityLine."Activity Type"::Movement);
            RegisteredWhseActivityLine.SetRange("No.", RegisteredNo);
            RegisteredWhseActivityLine.SetRange("Action Type", RegisteredWhseActivityLine."Action Type"::Take);
            if RegisteredWhseActivityLine.FindFirst() then
                FromBinCode := RegisteredWhseActivityLine."Bin Code";
            RegisteredWhseActivityLine.SetRange("Action Type", RegisteredWhseActivityLine."Action Type"::Place);
            if RegisteredWhseActivityLine.FindFirst() then
                ToBinCode := RegisteredWhseActivityLine."Bin Code";
            exit;
        end;
        if RegisteredInvtMovementHdr.Get(RegisteredNo) then
            LocationCode := RegisteredInvtMovementHdr."Location Code";
        RegisteredInvtMovementLine.SetRange("No.", RegisteredNo);
        RegisteredInvtMovementLine.SetRange("Action Type", RegisteredInvtMovementLine."Action Type"::Take);
        if RegisteredInvtMovementLine.FindFirst() then
            FromBinCode := RegisteredInvtMovementLine."Bin Code";
        RegisteredInvtMovementLine.SetRange("Action Type", RegisteredInvtMovementLine."Action Type"::Place);
        if RegisteredInvtMovementLine.FindFirst() then
            ToBinCode := RegisteredInvtMovementLine."Bin Code";
    end;

    local procedure FirstBin(WhseActivityHeader: Record "Warehouse Activity Header"; ActionType: Enum "Warehouse Action Type"): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        WhseActivityLine.SetRange("Action Type", ActionType);
        WhseActivityLine.SetFilter("Qty. to Handle", '<>%1', 0);
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."Bin Code");
        exit('');
    end;

    local procedure EnsureBalanced(WhseActivityHeader: Record "Warehouse Activity Header")
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        TakeQty: Decimal;
        PlaceQty: Decimal;
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Take);
        WhseActivityLine.CalcSums("Qty. to Handle (Base)");
        TakeQty := WhseActivityLine."Qty. to Handle (Base)";
        WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Place);
        WhseActivityLine.CalcSums("Qty. to Handle (Base)");
        PlaceQty := WhseActivityLine."Qty. to Handle (Base)";
        if TakeQty <> PlaceQty then
            Error(UnbalancedErr, WhseActivityHeader."No.", TakeQty, PlaceQty);
    end;
}
