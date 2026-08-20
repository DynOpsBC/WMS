codeunit 72040 "DOPSWHS LP Management"
{
    Access = Public;

    procedure Build(TemplateCode: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; var LP: Record "DOPSWHS LP Header")
    var
        Template: Record "DOPSWHS LP Template";
    begin
        OnBeforeBuild(TemplateCode, LocationCode, BinCode, LP);
        LogMutation('LP.Build');
        LP.Init();
        LP."LP Template Code" := TemplateCode;
        LP."Location Code" := LocationCode;
        LP."Bin Code" := BinCode;
        LP.Status := LP.Status::Open;
        if Template.Get(TemplateCode) then begin
            LP."Length cm" := Template."Default Length cm";
            LP."Width cm" := Template."Default Width cm";
            LP."Height cm" := Template."Default Height cm";
        end;
        LP.Insert(true);
        WriteToLedger(LP, LPActionBuilt(), '', BinCode, 0, '', '', '');
        OnAfterBuild(LP);
    end;

    procedure Stop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean)
    begin
        Stop(LP, PrintLabel, '');
    end;

    procedure Stop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean; PrinterId: Code[50])
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Generator: Codeunit "DOPSWHS SSCC Generator";
    begin
        OnBeforeStop(LP, PrintLabel);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.Stop');
        LP.Status := LP.Status::Built;
        if LP.SSCC = '' then
            LP.SSCC := Generator.Generate();
        LP.Modify(true);
        WriteToLedger(LP, LPActionBuilt(), LP."Bin Code", LP."Bin Code", 0, '', '', '');
        if PrintLabel then
            Dispatcher.PrintLPLabel(LP, PrinterId, 1);
        OnAfterStop(LP);
    end;

    procedure Reopen(var LP: Record "DOPSWHS LP Header")
    begin
        OnBeforeReopen(LP);
        RequireStatus(LP, LP.Status::Built);
        LogMutation('LP.Reopen');
        LP.Status := LP.Status::Open;
        LP.Modify(true);
        OnAfterReopen(LP);
    end;

    procedure AddLine(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; UoM: Code[10]; Qty: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        OnBeforeAddLine(LP, ItemNo, UoM, Qty);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.AddLine');
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine.Validate("Item No.", ItemNo);
        LPLine."Unit of Measure" := UoM;
        LPLine.Validate(Quantity, Qty);
        LPLine."Lot No." := LotNo;
        LPLine."Serial No." := SerialNo;
        LPLine."Expiration Date" := ExpiryDate;
        LPLine.Insert(true);
        WriteToLedger(LP, LPActionItemAdded(), '', LP."Bin Code", Qty, ItemNo, LotNo + SerialNo, '');
        OnAfterAddLine(LP, LPLine);
    end;

    procedure RemoveLine(var LPLine: Record "DOPSWHS LP Line")
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.Get(LPLine."LP No.");
        OnBeforeRemoveLine(LPLine);
        RequireStatus(LP, LP.Status::Open);
        LogMutation('LP.RemoveLine');
        WriteToLedger(LP, LPActionItemRemoved(), LP."Bin Code", '', LPLine.Quantity, LPLine."Item No.", LPLine."Lot No." + LPLine."Serial No.", '');
        LPLine.Delete(true);
        OnAfterRemoveLine(LP);
    end;

    procedure Assign(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    begin
        OnBeforeAssign(LP, DocType, DocNo);
        RequireStatus(LP, LP.Status::Built);
        LogMutation('LP.Assign');
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := DocType;
        LP."Assigned Document No." := DocNo;
        LP.Modify(true);
        WriteToLedger(LP, LPActionAssigned(), LP."Bin Code", LP."Bin Code", 0, '', '', Format(DocType) + ':' + DocNo);
        OnAfterAssign(LP);
    end;

    procedure Release(var LP: Record "DOPSWHS LP Header")
    begin
        OnBeforeRelease(LP);
        RequireStatus(LP, LP.Status::Assigned);
        LogMutation('LP.Release');
        LP.Status := LP.Status::Built;
        Clear(LP."Assigned Document Type");
        LP."Assigned Document No." := '';
        LP.Modify(true);
        WriteToLedger(LP, LPActionReleased(), LP."Bin Code", LP."Bin Code", 0, '', '', '');
        OnAfterRelease(LP);
    end;

    procedure Transfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header"; LineSelections: List of [Integer]; QtyByLine: Dictionary of [Integer, Decimal])
    var
        SourceLine: Record "DOPSWHS LP Line";
        TargetLine: Record "DOPSWHS LP Line";
        LineNo: Integer;
        TransferQty: Decimal;
    begin
        OnBeforeTransfer(SourceLP, TargetLP);
        RequireStatus(SourceLP, SourceLP.Status::Built);
        RequireStatus(TargetLP, TargetLP.Status::Built);
        LogMutation('LP.Transfer');
        foreach LineNo in LineSelections do begin
            SourceLine.Get(SourceLP."No.", LineNo);
            if not QtyByLine.Get(LineNo, TransferQty) then
                TransferQty := SourceLine.Quantity;
            if (TransferQty <= 0) or (TransferQty > SourceLine.Quantity) then
                Error('Invalid transfer quantity for line %1.', LineNo);

            TargetLine.Init();
            TargetLine."LP No." := TargetLP."No.";
            TargetLine.Validate("Item No.", SourceLine."Item No.");
            TargetLine."Variant Code" := SourceLine."Variant Code";
            TargetLine."Unit of Measure" := SourceLine."Unit of Measure";
            TargetLine.Validate(Quantity, TransferQty);
            TargetLine."Lot No." := SourceLine."Lot No.";
            TargetLine."Serial No." := SourceLine."Serial No.";
            TargetLine."Package No." := SourceLine."Package No.";
            TargetLine."Expiration Date" := SourceLine."Expiration Date";
            TargetLine.Insert(true);

            SourceLine.Validate(Quantity, SourceLine.Quantity - TransferQty);
            if SourceLine.Quantity = 0 then
                SourceLine.Delete(true)
            else
                SourceLine.Modify(true);

            WriteToLedger(SourceLP, LPActionTransferOut(), SourceLP."Bin Code", TargetLP."Bin Code", TransferQty, SourceLine."Item No.", SourceLine."Lot No.", TargetLP."No.");
            WriteToLedger(TargetLP, LPActionTransferIn(), SourceLP."Bin Code", TargetLP."Bin Code", TransferQty, SourceLine."Item No.", SourceLine."Lot No.", SourceLP."No.");
        end;
        OnAfterTransfer(SourceLP, TargetLP);
    end;

    procedure Unbuild(var LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        OnBeforeUnbuild(LP);
        if not (LP.Status in [LP.Status::Built, LP.Status::Open]) then
            Error('Only built or open LPs can be unbuilt.');
        LogMutation('LP.Unbuild');
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.DeleteAll(true);
        WriteToLedger(LP, LPActionUnbuilt(), LP."Bin Code", '', 0, '', '', '');
        LP.Status := LP.Status::Unbuilt;
        LP.Modify(true);
        OnAfterUnbuild(LP);
    end;

    procedure SplitForPartialUse(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS Partial Use Action"; Qty: Decimal; LineNo: Integer)
    var
        LPLine: Record "DOPSWHS LP Line";
        NewLP: Record "DOPSWHS LP Header";
        Lines: List of [Integer];
        Quantities: Dictionary of [Integer, Decimal];
        ExcessQty: Decimal;
    begin
        OnBeforeSplitForPartialUse(LP, Action, Qty, LineNo);
        LogMutation('LP.PartialUse');
        LPLine.Get(LP."No.", LineNo);
        if (Qty <= 0) or (Qty > LPLine.Quantity) then
            Error('Invalid partial use quantity.');

        case Action of
            Action::CreateNewLP:
                begin
                    ExcessQty := LPLine.Quantity - Qty;
                    if ExcessQty > 0 then begin
                        Build(LP."LP Template Code", LP."Location Code", LP."Bin Code", NewLP);
                        Stop(NewLP, false);
                        Lines.Add(LineNo);
                        Quantities.Add(LineNo, ExcessQty);
                        Transfer(LP, NewLP, Lines, Quantities);
                    end;
                    LPLine.Get(LP."No.", LineNo);
                    LPLine.Validate(Quantity, Qty);
                    LPLine.Modify(true);
                end;
            Action::RemoveExcess:
                begin
                    LPLine.Validate(Quantity, Qty);
                    LPLine.Modify(true);
                end;
            Action::RemoveUsedPortion:
                begin
                    LPLine.Validate(Quantity, LPLine.Quantity - Qty);
                    if LPLine.Quantity = 0 then
                        LPLine.Delete(true)
                    else
                        LPLine.Modify(true);
                end;
            Action::Unbuild:
                Unbuild(LP);
        end;
        OnAfterSplitForPartialUse(LP);
    end;

    procedure WriteToLedger(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS LP Action"; FromBin: Code[20]; ToBin: Code[20]; Quantity: Decimal; ItemNo: Code[20]; LotSerial: Code[50]; RelatedDocument: Code[40])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger.Init();
        Ledger."LP No." := LP."No.";
        Ledger.Action := Action;
        Ledger."From Bin" := FromBin;
        Ledger."To Bin" := ToBin;
        Ledger.Quantity := Quantity;
        Ledger."Item No." := ItemNo;
        Ledger."Lot Serial" := LotSerial;
        Ledger."User ID" := CopyStr(UserId(), 1, MaxStrLen(Ledger."User ID"));
        Ledger.DateTime := CurrentDateTime();
        Ledger."Related Document" := RelatedDocument;
        Ledger.Insert(true);
    end;

    local procedure RequireStatus(var LP: Record "DOPSWHS LP Header"; RequiredStatus: Enum "DOPSWHS LP Status")
    begin
        if LP.Status <> RequiredStatus then
            Error('LP %1 must be %2. Current status is %3.', LP."No.", RequiredStatus, LP.Status);
    end;

    local procedure LogMutation(EventName: Text)
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(EventName, EventName);
    end;

    local procedure LPActionBuilt(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Built); end;
    local procedure LPActionAssigned(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Assigned); end;
    local procedure LPActionReleased(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Released); end;
    local procedure LPActionTransferIn(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::TransferIn); end;
    local procedure LPActionTransferOut(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::TransferOut); end;
    local procedure LPActionUnbuilt(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::Unbuilt); end;
    local procedure LPActionItemAdded(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::ItemAdded); end;
    local procedure LPActionItemRemoved(): Enum "DOPSWHS LP Action" begin exit(Enum::"DOPSWHS LP Action"::ItemRemoved); end;

    [IntegrationEvent(false, false)] local procedure OnBeforeBuild(TemplateCode: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterBuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeStop(var LP: Record "DOPSWHS LP Header"; PrintLabel: Boolean) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterStop(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeReopen(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterReopen(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeAddLine(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; UoM: Code[10]; Qty: Decimal) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterAddLine(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeRemoveLine(var LPLine: Record "DOPSWHS LP Line") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterRemoveLine(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeAssign(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterAssign(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeRelease(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterRelease(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeTransfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterTransfer(var SourceLP: Record "DOPSWHS LP Header"; var TargetLP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeUnbuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterUnbuild(var LP: Record "DOPSWHS LP Header") begin end;
    [IntegrationEvent(false, false)] local procedure OnBeforeSplitForPartialUse(var LP: Record "DOPSWHS LP Header"; Action: Enum "DOPSWHS Partial Use Action"; Qty: Decimal; LineNo: Integer) begin end;
    [IntegrationEvent(false, false)] local procedure OnAfterSplitForPartialUse(var LP: Record "DOPSWHS LP Header") begin end;
}
