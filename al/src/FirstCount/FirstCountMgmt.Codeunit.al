codeunit 72000 "DOPSWHS First Count Mgmt"
{
    Access = Public;
    // İlk Sayım kaydı stok günlüğüne yazar; terminal kullanıcısının lisansı bu
    // tablolara doğrudan izin vermeyebilir (dolaylı izin, Count Mgmt ile aynı).
    Permissions =
        tabledata "Item Journal Template" = RIMD,
        tabledata "Item Journal Batch" = RIMD,
        tabledata "Item Journal Line" = RIMD,
        tabledata "Reservation Entry" = RIMD,
        tabledata "DOPSWHS First Count Header" = RIMD,
        tabledata "DOPSWHS First Count Line" = RIMD;

    var
        CountNotOpenErr: Label 'İlk Sayım %1 işlenmiş; yeni satır eklenemez.', Comment = '%1 = count no.';
        QtyErr: Label 'Sayılan miktar 0''dan büyük olmalı.';
        BinRequiredErr: Label '%1 lokasyonu raf zorunlu: önce rafı okutun.', Comment = '%1 = location';
        BinNotFoundErr: Label '%1 rafı %2 lokasyonunda yok.', Comment = '%1 = bin, %2 = location';
        LotRequiredErr: Label '%1 lot takipli: lot numarasını girin.', Comment = '%1 = item';
        SerialNotSupportedErr: Label '%1 seri takipli; İlk Sayım seri takipli maddeyi desteklemez. Sayım ekranını kullanın.', Comment = '%1 = item';
        DirectedErr: Label '%1 lokasyonu yönlendirilmiş (Directed Put-away and Pick); İlk Sayım burada kullanılamaz. Sayım ekranını kullanın.', Comment = '%1 = location';
        ScanConflictErr: Label 'Bu okutma kimliği başka bir satırda kullanılmış. Maddeyi yeniden okutun.';
        NothingToPostErr: Label 'İlk Sayım %1 içinde satır yok.', Comment = '%1 = count no.';
        BatchBusyErr: Label '%1 günlüğünde başka belgeye ait satırlar var; önce onları temizleyin.', Comment = '%1 = batch';

    procedure NextCountNo(): Code[20]
    var
        Header: Record "DOPSWHS First Count Header";
        CountNo: Code[20];
        Suffix: Integer;
    begin
        CountNo := CopyStr('IS-' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'), 1, MaxStrLen(CountNo));
        while Header.Get(CountNo) do begin
            Suffix += 1;
            CountNo := CopyStr(CopyStr(CountNo, 1, 17) + Format(Suffix), 1, MaxStrLen(CountNo));
        end;
        exit(CountNo);
    end;

    procedure CheckLocation(LocationCode: Code[10])
    var
        Location: Record Location;
    begin
        Location.Get(LocationCode);
        if Location."Directed Put-away and Pick" then
            Error(DirectedErr, LocationCode);
    end;

    procedure CreateCount(LocationCode: Code[10]; UserIdText: Code[50]): Code[20]
    var
        Header: Record "DOPSWHS First Count Header";
    begin
        Header.Init();
        Header."Location Code" := LocationCode;
        Header."Created By" := UserIdText;
        Header.Insert(true);
        exit(Header."No.");
    end;

    /// <summary>Okutulan madde + adet. Aynı ScanId tekrar gelirse yeni satır açılmaz.</summary>
    procedure AddLine(CountNo: Code[20]; ScanId: Guid; ItemNo: Code[20]; VariantCode: Code[10]; BinCode: Code[20]; LotNo: Code[50]; UomCode: Code[10]; Qty: Decimal; UserIdText: Code[50]): Integer
    var
        Header: Record "DOPSWHS First Count Header";
        Line: Record "DOPSWHS First Count Line";
        Item: Record Item;
        ItemUom: Record "Item Unit of Measure";
        Location: Record Location;
        Bin: Record Bin;
        LotTracked: Boolean;
        SerialTracked: Boolean;
        NextLineNo: Integer;
    begin
        if not IsNullGuid(ScanId) then begin
            Line.SetCurrentKey("Scan Id");
            Line.SetRange("Scan Id", ScanId);
            if Line.FindFirst() then begin
                if Line."Count No." <> CountNo then
                    Error(ScanConflictErr);
                exit(Line."Line No.");
            end;
            Line.Reset();
        end;

        Header.LockTable();
        Header.Get(CountNo);
        if Header.Status <> Header.Status::Open then
            Error(CountNotOpenErr, CountNo);
        if Qty <= 0 then
            Error(QtyErr);
        Item.Get(ItemNo);
        Location.Get(Header."Location Code");
        if Location."Bin Mandatory" then begin
            if BinCode = '' then
                Error(BinRequiredErr, Location.Code);
            if not Bin.Get(Location.Code, BinCode) then
                Error(BinNotFoundErr, BinCode, Location.Code);
        end else
            BinCode := '';
        GetTracking(Item, LotTracked, SerialTracked);
        if SerialTracked then
            Error(SerialNotSupportedErr, ItemNo);
        if LotTracked and (LotNo = '') then
            Error(LotRequiredErr, ItemNo);
        if not LotTracked then
            LotNo := '';
        if UomCode = '' then
            UomCode := Item."Base Unit of Measure";
        ItemUom.Get(ItemNo, UomCode);

        Line.SetRange("Count No.", CountNo);
        if Line.FindLast() then
            NextLineNo := Line."Line No.";
        NextLineNo += 10000;

        Line.Init();
        Line."Count No." := CountNo;
        Line."Line No." := NextLineNo;
        Line."Scan Id" := ScanId;
        Line."Item No." := ItemNo;
        Line."Variant Code" := VariantCode;
        Line."Bin Code" := BinCode;
        Line."Lot No." := LotNo;
        Line."Unit of Measure Code" := UomCode;
        Line.Quantity := Qty;
        Line."Qty. per Unit of Measure" := ItemUom."Qty. per Unit of Measure";
        if Line."Qty. per Unit of Measure" = 0 then
            Line."Qty. per Unit of Measure" := 1;
        Line."Quantity (Base)" := Round(Qty * Line."Qty. per Unit of Measure", 0.00001);
        Line.Description := Item.Description;
        Line."User ID" := UserIdText;
        Line."Created DateTime" := CurrentDateTime();
        Line.Insert(true);
        exit(Line."Line No.");
    end;

    procedure DeleteLine(CountNo: Code[20]; LineNo: Integer)
    var
        Header: Record "DOPSWHS First Count Header";
        Line: Record "DOPSWHS First Count Line";
    begin
        Header.Get(CountNo);
        if Header.Status <> Header.Status::Open then
            Error(CountNotOpenErr, CountNo);
        if Line.Get(CountNo, LineNo) then
            Line.Delete(true);
    end;

    /// <summary>
    /// Okutulan her raf/madde/varyant/lot için stok, sayılan toplam adede eşitlenir
    /// (Phys. Inventory günlüğü). Okutulmayan maddelere dokunulmaz.
    /// </summary>
    procedure PostCount(CountNo: Code[20]; UserIdText: Code[50]): Integer
    var
        Header: Record "DOPSWHS First Count Header";
        Line: Record "DOPSWHS First Count Line";
        Item: Record Item;
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        Counted: Dictionary of [Text, Decimal];
        Keys: List of [Text];
        GroupKey: Text;
        Parts: List of [Text];
        BatchName: Code[10];
        DocumentNo: Code[20];
        Calculated: Decimal;
        Physical: Decimal;
        JnlLineNo: Integer;
        Adjusted: Integer;
    begin
        Header.LockTable();
        Header.Get(CountNo);
        if Header.Status <> Header.Status::Open then
            Error(CountNotOpenErr, CountNo);
        CheckLocation(Header."Location Code");

        Line.SetRange("Count No.", CountNo);
        if not Line.FindSet() then
            Error(NothingToPostErr, CountNo);
        repeat
            GroupKey := GroupKeyOf(Line);
            if Counted.ContainsKey(GroupKey) then
                Counted.Set(GroupKey, Counted.Get(GroupKey) + Line."Quantity (Base)")
            else begin
                Counted.Add(GroupKey, Line."Quantity (Base)");
                Keys.Add(GroupKey);
            end;
        until Line.Next() = 0;

        BatchName := EnsureBatch(CountNo);
        DocumentNo := CountNo;
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetFilter("Document No.", '<>%1', DocumentNo);
        if not ItemJournalLine.IsEmpty() then
            Error(BatchBusyErr, BatchName);
        ItemJournalLine.SetRange("Document No.", DocumentNo);
        ItemJournalLine.DeleteAll(true);

        foreach GroupKey in Keys do begin
            Parts := GroupKey.Split('|');
            Item.Get(Parts.Get(2));
            Physical := Counted.Get(GroupKey);
            Calculated := CalculatedBaseQty(Header."Location Code", Parts.Get(1), Parts.Get(2), Parts.Get(3), Parts.Get(4));
            if Physical <> Calculated then begin
                JnlLineNo += 10000;
                ItemJournalLine.Init();
                ItemJournalLine.Validate("Journal Template Name", 'PHYS. INV.');
                ItemJournalLine.Validate("Journal Batch Name", BatchName);
                ItemJournalLine."Line No." := JnlLineNo;
                ItemJournalLine.Validate("Posting Date", Today());
                ItemJournalLine."Document No." := DocumentNo;
                ItemJournalLine.Validate("Item No.", Item."No.");
                ItemJournalLine.Validate("Location Code", Header."Location Code");
                ItemJournalLine.Validate("Variant Code", CopyStr(Parts.Get(3), 1, 10));
                if Parts.Get(1) <> '' then
                    ItemJournalLine.Validate("Bin Code", CopyStr(Parts.Get(1), 1, 20));
                ItemJournalLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
                ItemJournalLine.Validate("Phys. Inventory", true);
                ItemJournalLine.Validate("Qty. (Calculated)", Calculated);
                ItemJournalLine.Validate("Qty. (Phys. Inventory)", Physical);
                ItemJournalLine.Insert(true);
                AddLotTracking(ItemJournalLine, CopyStr(Parts.Get(4), 1, 50));
                Adjusted += 1;
            end;
        end;

        ItemJournalLine.Reset();
        ItemJournalLine.SetRange("Journal Template Name", 'PHYS. INV.');
        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetRange("Document No.", DocumentNo);
        if ItemJournalLine.FindFirst() then begin
            ItemJnlPostBatch.SetSuppressCommit(true);
            ItemJnlPostBatch.Run(ItemJournalLine);
        end;

        Header.Status := Header.Status::Posted;
        Header."Posted DateTime" := CurrentDateTime();
        Header."Posted By" := UserIdText;
        Header.Modify(true);
        exit(Adjusted);
    end;

    procedure GroupKeyOf(Line: Record "DOPSWHS First Count Line"): Text
    begin
        exit(Line."Bin Code" + '|' + Line."Item No." + '|' + Line."Variant Code" + '|' + Line."Lot No.");
    end;

    /// <summary>BC'deki mevcut stok (temel birim): raflı lokasyonda raf içeriği, rafsızda lokasyon toplamı.</summary>
    procedure CalculatedBaseQty(LocationCode: Code[10]; BinCode: Text; ItemNo: Text; VariantCode: Text; LotNo: Text): Decimal
    var
        BinContent: Record "Bin Content";
        ItemLedgerEntry: Record "Item Ledger Entry";
        Total: Decimal;
    begin
        if BinCode <> '' then begin
            BinContent.SetRange("Location Code", LocationCode);
            BinContent.SetRange("Bin Code", BinCode);
            BinContent.SetRange("Item No.", ItemNo);
            BinContent.SetRange("Variant Code", VariantCode);
            if LotNo <> '' then
                BinContent.SetFilter("Lot No. Filter", '%1', LotNo);
            if BinContent.FindSet() then
                repeat
                    BinContent.CalcFields("Quantity (Base)");
                    Total += BinContent."Quantity (Base)";
                until BinContent.Next() = 0;
            exit(Total);
        end;
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Variant Code", VariantCode);
        if LotNo <> '' then
            ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.CalcSums(Quantity);
        exit(ItemLedgerEntry.Quantity);
    end;

    local procedure GetTracking(Item: Record Item; var LotTracked: Boolean; var SerialTracked: Boolean)
    var
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        LotTracked := false;
        SerialTracked := false;
        if (Item."Item Tracking Code" = '') or not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit;
        LotTracked := ItemTrackingCode."Lot Specific Tracking" or ItemTrackingCode."Lot Warehouse Tracking";
        SerialTracked := ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking";
    end;

    local procedure AddLotTracking(var ItemJournalLine: Record "Item Journal Line"; LotNo: Code[50])
    var
        TempReservEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        if (LotNo = '') or (ItemJournalLine.Quantity = 0) then
            exit;
        TempReservEntry."Lot No." := LotNo;
        CreateReservEntry.CreateReservEntryFor(
            Database::"Item Journal Line", ItemJournalLine."Entry Type".AsInteger(),
            ItemJournalLine."Journal Template Name", ItemJournalLine."Journal Batch Name", 0,
            ItemJournalLine."Line No.", ItemJournalLine."Qty. per Unit of Measure",
            ItemJournalLine.Quantity, ItemJournalLine."Quantity (Base)", TempReservEntry);
        CreateReservEntry.CreateEntry(
            ItemJournalLine."Item No.", ItemJournalLine."Variant Code", ItemJournalLine."Location Code",
            ItemJournalLine.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    local procedure EnsureBatch(CountNo: Code[20]): Code[10]
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
        BatchName: Code[10];
    begin
        // 'I' + son 9 karakter: sayım belgelerinin 'C…' batch'leriyle çakışmaz.
        if StrLen(CountNo) > 9 then
            BatchName := CopyStr('I' + CopyStr(CountNo, StrLen(CountNo) - 8, 9), 1, MaxStrLen(BatchName))
        else
            BatchName := CopyStr('I' + CountNo, 1, MaxStrLen(BatchName));
        if not ItemJournalTemplate.Get('PHYS. INV.') then begin
            ItemJournalTemplate.Init();
            ItemJournalTemplate.Name := 'PHYS. INV.';
            ItemJournalTemplate.Type := ItemJournalTemplate.Type::"Phys. Inventory";
            ItemJournalTemplate.Insert(true);
        end;
        if not ItemJournalBatch.Get('PHYS. INV.', BatchName) then begin
            ItemJournalBatch.Init();
            ItemJournalBatch."Journal Template Name" := 'PHYS. INV.';
            ItemJournalBatch.Name := BatchName;
            ItemJournalBatch.Description := CopyStr(StrSubstNo('İlk Sayım %1', CountNo), 1, MaxStrLen(ItemJournalBatch.Description));
            ItemJournalBatch.Insert(true);
        end;
        exit(BatchName);
    end;
}
