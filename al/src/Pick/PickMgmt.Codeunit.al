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
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
    begin
        EnsurePick(Pick);
        Log('Pick.Register', Pick."No.");
        WhseActivityRegister.Run(Pick);
    end;

    procedure ReassignPick(var Pick: Record "Warehouse Activity Header"; NewUserId: Code[50]; Reason: Text[250])
    var
        History: Record "DOPSWHS Pick Reassignment History";
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
}
