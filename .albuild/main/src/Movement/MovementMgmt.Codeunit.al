codeunit 72045 "DOPSWHS Movement Mgmt"
{
    Access = Public;

    procedure EnsureDeviceJournalBatch(UserId: Code[50]): Code[10]
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
        BatchName: Code[10];
    begin
        BatchName := CopyStr('DOPS-' + CopyStr(DelChr(UserId, '=', ' /\.:;,*?<>|'), 1, 5), 1, 10);
        if BatchName = 'DOPS-' then
            BatchName := 'DOPS-USER';

        EnsureReclassTemplate(ItemJournalTemplate);
        if not ItemJournalBatch.Get(ItemJournalTemplate.Name, BatchName) then begin
            ItemJournalBatch.Init();
            ItemJournalBatch."Journal Template Name" := ItemJournalTemplate.Name;
            ItemJournalBatch.Name := BatchName;
            ItemJournalBatch.Description := CopyStr('DOPSWHS mobile ' + UserId, 1, MaxStrLen(ItemJournalBatch.Description));
            ItemJournalBatch.Recurring := false;
            ItemJournalBatch.Insert(true);
        end else
            if ItemJournalBatch.Recurring then begin
                ItemJournalBatch.Recurring := false;
                ItemJournalBatch.Modify(true);
            end;

        exit(BatchName);
    end;

    procedure AdHocMove(FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50])
    var
        Setup: Record "DOPSWHS Setup";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPost: Codeunit "Item Jnl.-Post";
        CustomDimensions: Dictionary of [Text, Text];
        BatchName: Code[10];
    begin
        if ItemNo = '' then
            Error('Item No. is required for ad-hoc moves.');
        if Qty <= 0 then
            Error('Quantity must be greater than zero.');

        Setup.Get('');
        Setup.TestField("Default Location Code");
        EnsureReclassTemplate(ItemJournalTemplate);
        BatchName := EnsureDeviceJournalBatch(UserId);

        CreateReclassLine(ItemJournalTemplate.Name, BatchName, Setup."Default Location Code", FromBinCode, ToBinCode, ItemNo, LpNo, Qty, ItemJournalLine);
        CustomDimensions.Add('Category', 'Movement');
        Session.LogMessage('DOPSWHS-Move-AdHoc', StrSubstNo('Ad-hoc move item %1 qty %2 from %3 to %4 lp %5', ItemNo, Qty, FromBinCode, ToBinCode, LpNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
        ItemJnlPost.Run(ItemJournalLine);
    end;

    procedure RegisterDirected(var WhseActivityHeader: Record "Warehouse Activity Header")
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('Category', 'Movement');
        Session.LogMessage('DOPSWHS-Move-RegisterDirected', StrSubstNo('Register warehouse activity %1 type %2', WhseActivityHeader."No.", Format(WhseActivityHeader.Type)), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
        WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        if WhseActivityLine.FindFirst() then
            WhseActivityRegister.Run(WhseActivityLine);
    end;

    local procedure EnsureReclassTemplate(var ItemJournalTemplate: Record "Item Journal Template")
    begin
        ItemJournalTemplate.SetRange(Type, ItemJournalTemplate.Type::Transfer);
        if not ItemJournalTemplate.FindFirst() then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'RECLASS';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::Transfer;
            ItemJournalTemplate.Description := 'Item Reclass Journal';
            ItemJournalTemplate.Insert(true);
        end;
    end;

    local procedure CreateReclassLine(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; var ItemJournalLine: Record "Item Journal Line")
    var
        ExistingLine: Record "Item Journal Line";
        NextLineNo: Integer;
    begin
        ExistingLine.SetRange("Journal Template Name", TemplateName);
        ExistingLine.SetRange("Journal Batch Name", BatchName);
        if ExistingLine.FindLast() then
            NextLineNo := ExistingLine."Line No." + 10000
        else
            NextLineNo := 10000;

        ItemJournalLine.Init();
        ItemJournalLine."Journal Template Name" := TemplateName;
        ItemJournalLine."Journal Batch Name" := BatchName;
        ItemJournalLine."Line No." := NextLineNo;
        ItemJournalLine."Posting Date" := WorkDate();
        ItemJournalLine."Document No." := CopyStr('DOPS-' + Format(Today(), 0, '<Year4><Month,2><Day,2>'), 1, MaxStrLen(ItemJournalLine."Document No."));
        ItemJournalLine."Entry Type" := ItemJournalLine."Entry Type"::Transfer;
        ItemJournalLine.Validate("Item No.", ItemNo);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate("New Location Code", LocationCode);
        ItemJournalLine.Validate("Bin Code", FromBinCode);
        ItemJournalLine.Validate("New Bin Code", ToBinCode);
        ItemJournalLine.Validate(Quantity, Qty);
        ItemJournalLine."Package No." := LpNo;
        ItemJournalLine.Insert(true);
    end;
}
