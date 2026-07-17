codeunit 72046 "DOPSWHS Pick Mgmt"
{
    Access = Public;

    procedure AssignToMe(var Pick: Record "Warehouse Activity Header")
    begin
        EnsurePick(Pick);
        Pick.Validate("Assigned User ID", CopyStr(UserId(), 1, MaxStrLen(Pick."Assigned User ID")));
        Pick.Modify(true);
        Log('Pick.AssignToMe', Pick."No.");
    end;

    procedure StartShippingLP(var Pick: Record "Warehouse Activity Header"; TemplateCode: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        EffectiveTemplateCode: Code[20];
    begin
        EnsurePick(Pick);
        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        LPMgt.Build(EffectiveTemplateCode, Pick."Location Code", '', LP);
        Log('Pick.StartShippingLP', Pick."No.");
        exit(LP."No.");
    end;

    procedure StopShippingLP(var Pick: Record "Warehouse Activity Header"; LpNo: Code[20]; PrintLabel: Boolean): Code[18]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        EnsurePick(Pick);
        LP.Get(LpNo);
        LPMgt.Stop(LP, PrintLabel);
        Log('Pick.StopShippingLP', Pick."No.");
        exit(LP.SSCC);
    end;

    procedure RegisterShortPick(var PickLine: Record "Warehouse Activity Line"; ShortQty: Decimal; ReasonCode: Code[20])
    var
        Reason: Record "DOPSWHS Short Pick Reason";
    begin
        if ShortQty < 0 then
            Error('Short quantity cannot be negative.');
        if ReasonCode <> '' then
            Reason.Get(ReasonCode);

        PickLine.Validate("Qty. to Handle", ShortQty);
        PickLine.Modify(true);
        Log('Pick.Short.' + ReasonCode, PickLine."No.");
    end;

    procedure RegisterPick(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
        QualityBridge: Codeunit "DOPSWHS Quality Mgmt Bridge";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
    begin
        EnsurePick(Pick);
        Log('Pick.Register', Pick."No.");

        // Microsoft Quality Management block guard: refuse register if any
        // pick line carries a Lot/Serial currently under an open inspection.
        // Error format matches BCWMSApp.QcErrorParser so the mobile/web UI
        // renders a friendly "🔬 QC BLOCK" banner.
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindSet() then
            repeat
                QualityBridge.VerifyNotBlocked(
                    PickLine."Lot No.",
                    PickLine."Serial No.",
                    '');
            until PickLine.Next() = 0;

        if PickLine.FindFirst() then
            WhseActivityRegister.Run(PickLine);
    end;

    procedure ReassignPick(var Pick: Record "Warehouse Activity Header"; NewUserId: Code[50]; Reason: Text[250])
    var
        History: Record "DOPSWHS Pick Reassign Hist";
        WebhookMgmt: Codeunit "DOPSWHS Webhook Mgmt";
        FromUserId: Code[50];
    begin
        EnsurePick(Pick);
        if NewUserId = '' then
            Error('New user is required.');

        FromUserId := Pick."Assigned User ID";
        Pick.Validate("Assigned User ID", NewUserId);
        Pick.Modify(true);

        History.Init();
        History."Pick No." := Pick."No.";
        History."From User" := FromUserId;
        History."To User" := NewUserId;
        History."Reassigned By" := CopyStr(UserId(), 1, MaxStrLen(History."Reassigned By"));
        History.DateTime := CurrentDateTime();
        History.Reason := Reason;
        History.Insert(true);

        WebhookMgmt.OnPickReassigned(Pick."No.", FromUserId, NewUserId);
        Log('Pick.Reassign', Pick."No.");
    end;

    // ELOG saha ziyareti: toplama sırasında sipariş başına tote (sepet) bağlama.
    // Terminal ürün okutunca satırın kaynak siparişi için atanmış tote'u sorar;
    // yoksa okutulan yeni tote'u bu siparişe bağlar. Aynı tote aynı pick içinde
    // birden çok siparişe hizmet edebilir (bulk/batch); farklı bir pick'in
    // kapatılmamış tote'u yeniden bağlanamaz.
    procedure AssignTote(var Pick: Record "Warehouse Activity Header"; SourceOrderNo: Code[20]; LpNo: Code[20])
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
        OtherAssignment: Record "DOPSWHS Pick Tote Assignment";
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        EnsurePick(Pick);
        if SourceOrderNo = '' then
            Error(SourceOrderRequiredErr);
        LP.Get(LpNo);

        OtherAssignment.SetRange("LP No.", LpNo);
        OtherAssignment.SetRange(Packed, false);
        OtherAssignment.SetFilter("Pick No.", '<>%1', Pick."No.");
        if not OtherAssignment.IsEmpty() then
            Error(ToteBusyErr, LpNo);

        if Assignment.Get(Pick."No.", SourceOrderNo) then begin
            Assignment."LP No." := LpNo;
            Assignment.Packed := false;
            Assignment."Assigned By User" := CopyStr(UserId(), 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Modify(true);
        end else begin
            Assignment.Init();
            Assignment."Pick No." := Pick."No.";
            Assignment."Source Order No." := SourceOrderNo;
            Assignment."LP No." := LpNo;
            Assignment."Location Code" := Pick."Location Code";
            Assignment."Assigned By User" := CopyStr(UserId(), 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Insert(true);
        end;

        // LP yaşam döngüsü: Built tote pick'e Assigned olur (Release paketlemede).
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhsePick, Pick."No.");

        Log('Pick.AssignTote', Pick."No.");
    end;

    procedure GetToteForOrder(PickNo: Code[20]; SourceOrderNo: Code[20]): Code[20]
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
    begin
        if Assignment.Get(PickNo, SourceOrderNo) then
            exit(Assignment."LP No.");
        exit('');
    end;

    local procedure EnsurePick(var Pick: Record "Warehouse Activity Header")
    begin
        if Pick.Type <> Pick.Type::Pick then
            Error('Warehouse activity %1 must be a Pick.', Pick."No.");
    end;

    local procedure Log(Category: Text; DocNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, DocNo);
    end;

    var
        SourceOrderRequiredErr: Label 'Source order no. is required to assign a tote.';
        ToteBusyErr: Label 'Tote %1 is still in use by another pick. Complete or release it first.', Comment = '%1 = LP No.';
}
