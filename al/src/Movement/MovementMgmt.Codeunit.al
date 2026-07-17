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

    /// <summary>Geriye dönük sarmalayıcı — lot izlemesiz ürünler.</summary>
    procedure AdHocMove(FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50])
    begin
        AdHocMove(FromBinCode, ToBinCode, ItemNo, LpNo, Qty, UserId, '');
    end;

    procedure AdHocMove(FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50])
    var
        Setup: Record "DOPSWHS Setup";
        Location: Record Location;
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        CustomDimensions: Dictionary of [Text, Text];
        BatchName: Code[10];
        LocationCode: Code[10];
    begin
        if ItemNo = '' then
            Error('Item No. is required for ad-hoc moves.');
        if Qty <= 0 then
            Error('Quantity must be greater than zero.');

        Setup.Get('');
        // The mobile form captures bins, not a location. Resolve the location from the source bin
        // (the bins are location-scoped) so the reclass posts where the bin actually lives, instead
        // of forcing the Setup default location (which may not own this bin).
        LocationCode := ResolveLocationForBin(FromBinCode, Setup."Default Location Code");
        if LocationCode = '' then
            Error('Cannot determine a location for bin %1. Set a Default Location Code in DOPSWHS Setup, or scan a bin that exists in a warehouse location.', FromBinCode);

        // Yönlendirilmiş (Directed Put-away and Pick) lokasyonda Item Journal
        // bin taşıyamaz — post adjustment bin'den (W-99-...) geçer ve raf
        // seviyesinde hareket OLMAZ. Doğru araç: Warehouse Reclass Journal
        // (Movement) — bin'den bin'e, ILE'ye dokunmadan.
        if Location.Get(LocationCode) and Location."Directed Put-away and Pick" then begin
            RegisterWhseMove(LocationCode, FromBinCode, ToBinCode, ItemNo, Qty, UserId, LotNo);
            CustomDimensions.Add('Category', 'Movement');
            Session.LogMessage('DOPSWHS-Move-AdHocWhse', StrSubstNo('Directed whse move item %1 qty %2 from %3 to %4 lp %5', ItemNo, Qty, FromBinCode, ToBinCode, LpNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
            exit;
        end;
        EnsureReclassTemplate(ItemJournalTemplate);
        BatchName := EnsureDeviceJournalBatch(UserId);

        CreateReclassLine(ItemJournalTemplate.Name, BatchName, LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, ItemJournalLine);
        // Lot izlemeli ürün: reclass satırına item tracking bağla — yoksa post
        // "You must assign a lot number" ile düşer.
        // DİKKAT (17 Tem saha hatası): satırın kendi "Lot No."/"New Lot No."
        // alanları DOLDURULMAZ — reservation entry (tracking spec) varken
        // codeunit 22 satır alanlarının boş olmasını şart koşar ("New Lot No.
        // must be equal to ''"). Lot yalnızca AddLotTracking'in oluşturduğu
        // reservation kaydında taşınır (Lot No. + New Lot No.).
        if LotNo <> '' then
            AddLotTracking(ItemJournalLine, LotNo);
        CustomDimensions.Add('Category', 'Movement');
        Session.LogMessage('DOPSWHS-Move-AdHoc', StrSubstNo('Ad-hoc move item %1 qty %2 from %3 to %4 lp %5', ItemNo, Qty, FromBinCode, ToBinCode, LpNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
        // Post via batch codeunit (22/23) rather than "Item Jnl.-Post" (241): the latter raises a
        // "Do you want to post?" Confirm that fails as a client callback over the API / on the handheld.
        ItemJnlPostBatch.Run(ItemJournalLine);
    end;

    procedure RegisterDirected(var WhseActivityHeader: Record "Warehouse Activity Header")
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        QualityBridge: Codeunit "DOPSWHS Quality Mgmt Bridge";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('Category', 'Movement');
        Session.LogMessage('DOPSWHS-Move-RegisterDirected', StrSubstNo('Register warehouse activity %1 type %2', WhseActivityHeader."No.", Format(WhseActivityHeader.Type)), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);

        // MS Quality Management lot/serial block guard.
        WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        if WhseActivityLine.FindSet() then
            repeat
                QualityBridge.VerifyNotBlocked(
                    WhseActivityLine."Lot No.",
                    WhseActivityLine."Serial No.",
                    '');
            until WhseActivityLine.Next() = 0;

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

    local procedure ResolveLocationForBin(FromBinCode: Code[20]; DefaultLocation: Code[10]): Code[10]
    var
        Bin: Record Bin;
    begin
        if FromBinCode = '' then
            exit(DefaultLocation);
        // Prefer the configured default location when the bin actually exists there.
        if (DefaultLocation <> '') and Bin.Get(DefaultLocation, FromBinCode) then
            exit(DefaultLocation);
        // Otherwise find the location that owns this bin code.
        Bin.SetRange(Code, FromBinCode);
        if Bin.FindFirst() then
            exit(Bin."Location Code");
        exit(DefaultLocation);
    end;

    // ---- Yönlendirilmiş lokasyon: Warehouse Reclass Journal (bin-to-bin) ----

    local procedure RegisterWhseMove(LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50])
    var
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        WhseJournalTemplate: Record "Warehouse Journal Template";
        WhseJournalLine: Record "Warehouse Journal Line";
        WhseJnlRegisterBatch: Codeunit "Whse. Jnl.-Register Batch";
        BatchName: Code[10];
    begin
        FromBin.Get(LocationCode, FromBinCode);
        ToBin.Get(LocationCode, ToBinCode);
        Item.Get(ItemNo);

        EnsureWhseReclassTemplate(WhseJournalTemplate);
        BatchName := EnsureWhseJournalBatch(WhseJournalTemplate.Name, LocationCode);

        WhseJournalLine.Init();
        WhseJournalLine.Validate("Journal Template Name", WhseJournalTemplate.Name);
        WhseJournalLine.Validate("Journal Batch Name", BatchName);
        WhseJournalLine.Validate("Location Code", LocationCode);
        WhseJournalLine."Line No." := NextWhseLineNo(WhseJournalTemplate.Name, BatchName, LocationCode);
        WhseJournalLine."Registering Date" := WorkDate();
        WhseJournalLine."User ID" := CopyStr(UserId, 1, MaxStrLen(WhseJournalLine."User ID"));
        WhseJournalLine.Validate("Entry Type", WhseJournalLine."Entry Type"::Movement);
        WhseJournalLine.Validate("Item No.", ItemNo);
        WhseJournalLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
        WhseJournalLine.Validate("From Zone Code", FromBin."Zone Code");
        WhseJournalLine.Validate("From Bin Code", FromBinCode);
        WhseJournalLine.Validate("To Zone Code", ToBin."Zone Code");
        WhseJournalLine.Validate("To Bin Code", ToBinCode);
        WhseJournalLine.Validate(Quantity, Qty);
        WhseJournalLine.Insert(true);

        // Saha hatası (17 Tem): "Item tracking lines ... must account for the
        // same quantity" — whse journal lot'u satır alanından DEĞİL, bağlı
        // "Whse. Item Tracking Line" kaydından okur (UI'daki Item Tracking
        // Lines sayfasının kod karşılığı).
        if LotNo <> '' then
            AddWhseLotTracking(WhseJournalLine, LotNo);

        // Item Jnl.-Post Batch'in ambar karşılığı — confirm diyaloğu açmadan
        // register eder (web servis bağlamı).
        WhseJnlRegisterBatch.Run(WhseJournalLine);
    end;

    local procedure AddWhseLotTracking(WhseJnlLine: Record "Warehouse Journal Line"; LotNo: Code[50])
    var
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        EntryNo: Integer;
    begin
        WhseItemTrackingLine.Reset();
        if WhseItemTrackingLine.FindLast() then
            EntryNo := WhseItemTrackingLine."Entry No.";
        WhseItemTrackingLine.Init();
        WhseItemTrackingLine."Entry No." := EntryNo + 1;
        WhseItemTrackingLine."Item No." := WhseJnlLine."Item No.";
        WhseItemTrackingLine."Variant Code" := WhseJnlLine."Variant Code";
        WhseItemTrackingLine."Location Code" := WhseJnlLine."Location Code";
        WhseItemTrackingLine."Source Type" := Database::"Warehouse Journal Line";
        // DİKKAT — BC'nin bilinen alan TERSLİĞİ (saha hatası "Tracking total: 0"):
        // whse journal için base app "Source ID"ye BATCH adını, "Source Batch
        // Name"e TEMPLATE adını yazar (ItemTrackingManagement.SplitWhseJnlLine
        // aramayı bu terslikle yapar). Düz eşleme kayıt bulunamamasına yol açar.
        WhseItemTrackingLine."Source ID" := WhseJnlLine."Journal Batch Name";
        WhseItemTrackingLine."Source Batch Name" := WhseJnlLine."Journal Template Name";
        WhseItemTrackingLine."Source Ref. No." := WhseJnlLine."Line No.";
        WhseItemTrackingLine."Qty. per Unit of Measure" := WhseJnlLine."Qty. per Unit of Measure";
        WhseItemTrackingLine.Validate("Quantity (Base)", WhseJnlLine."Qty. (Base)");
        WhseItemTrackingLine."Lot No." := LotNo;
        // Reclass: aynı lot hedef bin'e taşınır.
        WhseItemTrackingLine."New Lot No." := LotNo;
        WhseItemTrackingLine.Insert();
    end;

    local procedure EnsureWhseReclassTemplate(var WhseJournalTemplate: Record "Warehouse Journal Template")
    begin
        if WhseJournalTemplate.Get('RECLASS') then
            exit;
        WhseJournalTemplate.Init();
        WhseJournalTemplate.Name := 'RECLASS';
        WhseJournalTemplate.Description := 'BCWMS directed bin-to-bin moves';
        WhseJournalTemplate.Validate(Type, WhseJournalTemplate.Type::Reclassification);
        WhseJournalTemplate.Insert(true);
    end;

    // Warehouse Journal Batch anahtarı lokasyon içerir (template + name + location).
    local procedure EnsureWhseJournalBatch(TemplateName: Code[10]; LocationCode: Code[10]): Code[10]
    var
        WhseJournalBatch: Record "Warehouse Journal Batch";
        BatchName: Code[10];
    begin
        BatchName := 'DOPS-MOBIL';
        if not WhseJournalBatch.Get(TemplateName, BatchName, LocationCode) then begin
            WhseJournalBatch.Init();
            WhseJournalBatch."Journal Template Name" := TemplateName;
            WhseJournalBatch.Name := BatchName;
            WhseJournalBatch."Location Code" := LocationCode;
            WhseJournalBatch.Description := 'BCWMS mobil ad-hoc hareketler';
            WhseJournalBatch.Insert(true);
        end;
        exit(BatchName);
    end;

    local procedure NextWhseLineNo(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        ExistingLine: Record "Warehouse Journal Line";
    begin
        ExistingLine.SetRange("Journal Template Name", TemplateName);
        ExistingLine.SetRange("Journal Batch Name", BatchName);
        ExistingLine.SetRange("Location Code", LocationCode);
        if ExistingLine.FindLast() then
            exit(ExistingLine."Line No." + 10000);
        exit(10000);
    end;

    // Reclass satırına lot tracking: aynı lot kaynaktan düşülüp hedefe yazılır
    // ("Lot No." + "New Lot No."). Standart desen: Create Reserv. Entry ile
    // Prospect rezervasyon kaydı (item journal post bunu tracking spec olarak okur).
    local procedure AddLotTracking(var ItemJnlLine: Record "Item Journal Line"; LotNo: Code[50])
    var
        TempReservEntry: Record "Reservation Entry";
        ReservEntry: Record "Reservation Entry";
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        TempReservEntry."Lot No." := LotNo;
        TempReservEntry."New Lot No." := LotNo;
        CreateReservEntry.CreateReservEntryFor(
            Database::"Item Journal Line",
            ItemJnlLine."Entry Type".AsInteger(),
            ItemJnlLine."Journal Template Name",
            ItemJnlLine."Journal Batch Name",
            0,
            ItemJnlLine."Line No.",
            ItemJnlLine."Qty. per Unit of Measure",
            ItemJnlLine.Quantity,
            ItemJnlLine."Quantity (Base)",
            TempReservEntry);
        CreateReservEntry.CreateEntry(
            ItemJnlLine."Item No.", ItemJnlLine."Variant Code", ItemJnlLine."Location Code",
            ItemJnlLine.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);

        // Create Reserv. Entry, ForReservEntry'deki "New Lot No."yu Prospect
        // kaydına TAŞIMIYOR (saha hatası: New Lot No. boş kaldı) — oluşan
        // kayıtları bulup reclass hedef lotunu doğrudan yaz.
        ReservEntry.SetRange("Source Type", Database::"Item Journal Line");
        ReservEntry.SetRange("Source Subtype", ItemJnlLine."Entry Type".AsInteger());
        ReservEntry.SetRange("Source ID", ItemJnlLine."Journal Template Name");
        ReservEntry.SetRange("Source Batch Name", ItemJnlLine."Journal Batch Name");
        ReservEntry.SetRange("Source Ref. No.", ItemJnlLine."Line No.");
        ReservEntry.SetRange("Lot No.", LotNo);
        if ReservEntry.FindSet(true) then
            repeat
                if ReservEntry."New Lot No." = '' then begin
                    ReservEntry."New Lot No." := LotNo;
                    ReservEntry.Modify();
                end;
            until ReservEntry.Next() = 0;
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
