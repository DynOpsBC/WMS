codeunit 72189 "DOPSWHS LP Prod Consume Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Warehouse Entry" = RIMD, tabledata "Item Tracking Code" = RIMD, tabledata "Item Ledger Entry" = RIMD;

    [Test]
    procedure ManualBinChangeIsDetectedAndPreviewMovesNothing()
    var
        Lp: Record "DOPSWHS LP Header";
        Selected: Record "DOPSWHS LP Header";
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
        Result: JsonObject;
        Token: JsonToken;
        ItemNo: Code[20];
    begin
        ItemNo := NewItem('');
        NewLp(Lp, 'PROD', 'ORD-A', ItemNo, '', 2452);   // header says PROD
        AddLedgerBin(Lp."No.", 'RAW');                 // recorded movement: RAW
        AddStock('RAW', ItemNo, '', 2452);               // stock really in RAW
        Check(Repair.LastRecordedBin(Lp."No.") = 'RAW', 'Recorded bin must be RAW.');
        Selected.SetRange("No.", Lp."No.");
        Result.ReadFrom(Repair.MoveStockToLpBin(Selected, false));
        Result.Get('moved', Token);
        Check(Token.AsValue().AsInteger() = 1, 'The LP must be eligible.');
        Check(Repair.BinBalance(Loc(), 'RAW', ItemNo, '', '', '', false, false) = 2452, 'Preview moved stock.');
    end;

    [Test]
    procedure LpWhoseStockIsAlreadyInItsBinIsSkipped()
    var
        Lp: Record "DOPSWHS LP Header";
        Selected: Record "DOPSWHS LP Header";
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
        Result: JsonObject;
        Token: JsonToken;
        ItemNo: Code[20];
    begin
        ItemNo := NewItem('');
        NewLp(Lp, 'PROD', 'ORD-A', ItemNo, '', 100);
        AddLedgerBin(Lp."No.", 'RAW');
        AddStock('PROD', ItemNo, '', 100);  // stock is where the LP is
        AddStock('RAW', ItemNo, '', 100);
        Selected.SetRange("No.", Lp."No.");
        Result.ReadFrom(Repair.MoveStockToLpBin(Selected, false));
        Result.Get('moved', Token);
        Check(Token.AsValue().AsInteger() = 0, 'An LP whose stock is in its bin must be skipped.');
    end;

    [Test]
    procedure StockClaimedByAnotherLpIsNotTaken()
    var
        Lp: Record "DOPSWHS LP Header";
        Other: Record "DOPSWHS LP Header";
        Selected: Record "DOPSWHS LP Header";
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
        Result: JsonObject;
        Token: JsonToken;
        ItemNo: Code[20];
    begin
        ItemNo := NewItem('');
        NewLp(Lp, 'PROD', 'ORD-A', ItemNo, '', 100);
        AddLedgerBin(Lp."No.", 'RAW');
        NewLp(Other, 'RAW', '', ItemNo, '', 100);  // RAW stock belongs to another LP
        AddStock('RAW', ItemNo, '', 100);
        Selected.SetRange("No.", Lp."No.");
        Result.ReadFrom(Repair.MoveStockToLpBin(Selected, false));
        Result.Get('moved', Token);
        Check(Token.AsValue().AsInteger() = 0, 'Stock of another LP must not be moved.');
    end;

    [Test]
    procedure LpWithoutManualChangeOrOutsideFilterIsSkipped()
    var
        Normal: Record "DOPSWHS LP Header";
        Outside: Record "DOPSWHS LP Header";
        Selected: Record "DOPSWHS LP Header";
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
        Result: JsonObject;
        Token: JsonToken;
        ItemNo: Code[20];
    begin
        ItemNo := NewItem('');
        NewLp(Normal, 'PROD', 'ORD-A', ItemNo, '', 50);
        AddLedgerBin(Normal."No.", 'PROD');         // moved properly
        NewLp(Outside, 'RAW', '', ItemNo, '', 50);  // not a configured bin
        AddLedgerBin(Outside."No.", 'OTHER');
        AddStock('OTHER', ItemNo, '', 50);
        Selected.SetFilter("No.", '%1|%2', Normal."No.", Outside."No.");
        Result.ReadFrom(Repair.MoveStockToLpBin(Selected, false));
        Result.Get('moved', Token);
        Check(Token.AsValue().AsInteger() = 0, 'Nothing may be moved.');
        Result.Get('skipped', Token);
        Check(Token.AsValue().AsInteger() = 2, 'Both LPs must be skipped.');
    end;

    [Test]
    procedure SameBinCodeInAnotherLocationIsNotAllowed()
    var
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
    begin
        NewItem('');
        Check(Repair.IsSyncBin(Loc(), 'PROD'), 'Configured location/bin must be allowed.');
        Check(not Repair.IsSyncBin('OTHERLOC', 'PROD'), 'The same bin code in another location must not be allowed.');
        SetSyncBins('');
        Check(not Repair.IsSyncBin(Loc(), 'PROD'), 'Empty filter must allow nothing.');
    end;

    [Test]
    procedure ReportFlagsManualBinChange()
    var
        Lp: Record "DOPSWHS LP Header";
        Selected: Record "DOPSWHS LP Header";
        Repair: Codeunit "DOPSWHS LP Prod Consumption";
        Csv: Text;
        ItemNo: Code[20];
    begin
        ItemNo := NewItem('');
        NewLp(Lp, 'PROD', 'ORD-A', ItemNo, '', 2452);
        AddLedgerBin(Lp."No.", 'RAW');
        AddStock('RAW', ItemNo, '', 2452);
        Selected.SetRange("No.", Lp."No.");
        Csv := Repair.BuildReconciliationCsv(Selected);
        Check(Csv.Contains('LP kartından göz değiştirilmiş'), 'Report must flag the manual bin change.');
        Check(Csv.Contains('RAW'), 'Report must name the recorded bin.');
    end;

    local procedure AddLedgerBin(LpNo: Code[20]; ToBin: Code[20])
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
    begin
        Ledger."LP No." := LpNo;
        Ledger.Action := Ledger.Action::Built;
        Ledger."To Bin" := ToBin;
        Ledger.DateTime := CurrentDateTime();
        Ledger.Insert(false);
    end;

    local procedure SetSyncBins(BinFilter: Text[250])
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get() then
            Setup.Insert(false);
        Setup."Prod. LP Sync Bin Filter" := BinFilter;
        Setup."Prod. LP Sync Location" := Loc();
        Setup.Modify(false);
    end;

    local procedure Loc(): Code[10]
    begin
        exit('PCLAMP');
    end;

    local procedure NewItem(TrackingCode: Code[10]): Code[20]
    var
        Item: Record Item;
    begin
        SetSyncBins('PROD');
        Item."No." := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20);
        Item."Base Unit of Measure" := 'PCS';
        Item."Item Tracking Code" := TrackingCode;
        Item.Insert(false);
        exit(Item."No.");
    end;

    local procedure LotWhseTrackingCode(): Code[10]
    var
        TrackingCode: Record "Item Tracking Code";
    begin
        if not TrackingCode.Get('PCLAMPLOT') then begin
            TrackingCode.Code := 'PCLAMPLOT';
            TrackingCode."Lot Specific Tracking" := true;
            TrackingCode."Lot Warehouse Tracking" := true;
            TrackingCode.Insert(false);
        end;
        exit(TrackingCode.Code);
    end;

    local procedure NewLp(var LP: Record "DOPSWHS LP Header"; BinCode: Code[20]; OrderNo: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    begin
        Clear(LP);
        LP."No." := CopyStr('PC' + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20);
        LP."Location Code" := Loc();
        LP."Bin Code" := BinCode;
        if OrderNo <> '' then begin
            LP.Status := LP.Status::Assigned;
            LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
            LP."Assigned Document No." := OrderNo;
        end else
            LP.Status := LP.Status::Built;
        LP.Insert(false);
        AddLine(LP, 10000, ItemNo, LotNo, Qty);
    end;

    local procedure AddLine(LP: Record "DOPSWHS LP Header"; LineNo: Integer; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        Line: Record "DOPSWHS LP Line";
    begin
        Line."LP No." := LP."No.";
        Line."Line No." := LineNo;
        Line."Item No." := ItemNo;
        Line."Lot No." := LotNo;
        Line.Quantity := Qty;
        Line."Unit of Measure" := 'PCS';
        Line.Insert(false);
    end;

    local procedure AddStock(BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    begin
        AddStockLot(BinCode, ItemNo, LotNo, Qty);
    end;

    local procedure AddStockLot(BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        Entry: Record "Warehouse Entry";
        LastEntry: Record "Warehouse Entry";
    begin
        if LastEntry.FindLast() then
            Entry."Entry No." := LastEntry."Entry No." + 1
        else
            Entry."Entry No." := 1;
        Entry."Location Code" := Loc();
        Entry."Bin Code" := BinCode;
        Entry."Item No." := ItemNo;
        Entry."Lot No." := LotNo;
        Entry.Quantity := Qty;
        Entry."Qty. (Base)" := Qty;
        Entry."Unit of Measure Code" := 'PCS';
        Entry.Insert(false);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
