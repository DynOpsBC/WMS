codeunit 72045 "DOPSWHS Movement Mgmt"
{
    Access = Public;
    Permissions =
        tabledata Item = R,
        tabledata "Item Tracking Code" = R,
        tabledata Location = R,
        tabledata Bin = R,
        tabledata "Item Journal Template" = RIMD,
        tabledata "Item Journal Batch" = RIMD,
        tabledata "Item Journal Line" = RIMD,
        tabledata "Warehouse Journal Template" = RIMD,
        tabledata "Warehouse Journal Batch" = RIMD,
        tabledata "Warehouse Journal Line" = RIMD,
        tabledata "Reservation Entry" = RIMD,
        tabledata "Whse. Item Tracking Line" = RIMD,
        // Bakım onarımı ("Qty. (Base)" tutarsızlığı) ambar hareketini günceller.
        tabledata "Warehouse Entry" = RMD,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = R;

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
        LocationCode: Code[10];
    begin
        Setup.Get('');
        // The mobile form captures bins, not a location. Resolve the location from the source bin
        // (the bins are location-scoped) so the reclass posts where the bin actually lives, instead
        // of forcing the Setup default location (which may not own this bin).
        LocationCode := ResolveLocationForBin(FromBinCode, Setup."Default Location Code");
        ExecuteAdHocMove(LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, UserId, LotNo, '');
    end;

    /// <summary>
    /// Posts a bin-to-bin move in an explicitly known location. LP operations use this overload so
    /// an identically named bin in another location can never receive the stock accidentally.
    /// </summary>
    procedure AdHocMoveAtLocation(LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50])
    begin
        ExecuteAdHocMove(LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, UserId, LotNo, '');
    end;

    /// <summary>
    /// Posts a lot/serial tracked bin move in an explicitly known location.
    /// Serial quantity is expressed in the item's base unit and must be one.
    /// </summary>
    procedure AdHocMoveTrackedAtLocation(LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50]; SerialNo: Code[50])
    begin
        ExecuteAdHocMove(LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, UserId, LotNo, SerialNo);
    end;

    local procedure ExecuteAdHocMove(LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50]; SerialNo: Code[50])
    var
        Location: Record Location;
        FromBin: Record Bin;
        ToBin: Record Bin;
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostBatch: Codeunit "Item Jnl.-Post Batch";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        CustomDimensions: Dictionary of [Text, Text];
        BatchName: Code[10];
    begin
        if ItemNo = '' then
            Error('Item No. is required for ad-hoc moves.');
        if Qty <= 0 then
            Error('Quantity must be greater than zero.');
        if LocationCode = '' then
            Error('Cannot determine a location for bin %1. Set a Default Location Code in DOPSWHS Setup, or scan a bin that exists in a warehouse location.', FromBinCode);
        if FromBinCode = '' then
            Error('Source bin is required.');
        if ToBinCode = '' then
            Error('Target bin is required.');
        if FromBinCode = ToBinCode then
            Error('Source bin and target bin must be different.');
        if not Location.Get(LocationCode) then
            Error('Location %1 does not exist.', LocationCode);
        if not FromBin.Get(LocationCode, FromBinCode) then
            Error('Source bin %1 does not exist in location %2.', FromBinCode, LocationCode);
        if not ToBin.Get(LocationCode, ToBinCode) then
            Error('Target bin %1 does not exist in location %2.', ToBinCode, LocationCode);
        Item.Get(ItemNo);
        if (Item."Item Tracking Code" <> '') and ItemTrackingCode.Get(Item."Item Tracking Code") then begin
            if (ItemTrackingCode."Lot Specific Tracking" or ItemTrackingCode."Lot Warehouse Tracking") and (LotNo = '') then
                Error('%1 lot takipli maddesi için lot numarası zorunludur.', ItemNo);
            if (ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking") and (SerialNo = '') then
                Error('%1 seri takipli maddesi için seri numarası zorunludur.', ItemNo);
        end;
        if (SerialNo <> '') and (Qty <> 1) then
            Error('%1 seri numarası tek bir temel birimi temsil eder; hareket miktarı 1 olmalıdır.', SerialNo);

        // Ürün bazlı ad-hoc hareket hangi fiziksel LP'nin seçildiğini söylemez.
        // Bu nedenle yalnız LP'ye atanmamış serbest stok taşınabilir. Aksi halde
        // BC raf miktarını düşürürken LP başlığı kaynak rafta kalır ve palet
        // kendiliğinden bölünmüş gibi tutarsız bir görünüm oluşur.
        if LpNo = '' then
            LPMgt.EnsureLooseStockAvailable(
                LocationCode, FromBinCode, ItemNo, LotNo, SerialNo, Qty);

        // Yönlendirilmiş (Directed Put-away and Pick) lokasyonda Item Journal
        // bin taşıyamaz — post adjustment bin'den (W-99-...) geçer ve raf
        // seviyesinde hareket OLMAZ. Doğru araç: Warehouse Reclass Journal
        // (Movement) — bin'den bin'e, ILE'ye dokunmadan.
        if Location."Directed Put-away and Pick" then begin
            RegisterWhseMove(LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, UserId, LotNo, SerialNo);
            CustomDimensions.Add('Category', 'Movement');
            // Hareketi yapan operatör terminalden parametre olarak geliyor
            // (UserId parametresi). Paylaşımlı BC hesabı ile ayırt edilemezdi;
            // log satırına operatör alanları da yazılır.
            Telemetry.AddUserDimensions(CustomDimensions, UserId);
            Session.LogMessage('DOPSWHS-Move-AdHocWhse', StrSubstNo('Directed whse move item %1 qty %2 from %3 to %4 lp %5', ItemNo, Qty, FromBinCode, ToBinCode, LpNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
            exit;
        end;
        EnsureReclassTemplate(ItemJournalTemplate);
        BatchName := EnsureDeviceJournalBatch(UserId);

        // Takılı satır koruması (whse yolundakiyle aynı gerekçe): post tüm
        // sayfayı işler; önceki başarısız denemenin artığı her yeni hareketi
        // düşürür. Bizim sayfamızda post öncesi ne varsa artıktır — temizle.
        PurgeStaleItemLines(ItemJournalTemplate.Name, BatchName);

        CreateReclassLine(ItemJournalTemplate.Name, BatchName, LocationCode, FromBinCode, ToBinCode, ItemNo, LpNo, Qty, ItemJournalLine);
        // Lot/seri izlemeli ürün: reclass satırına item tracking bağla — yoksa
        // post zorunlu izleme bilgisi eksik hatasıyla düşer.
        // DİKKAT (17 Tem saha hatası): satırın kendi "Lot No."/"New Lot No."
        // alanları DOLDURULMAZ — reservation entry (tracking spec) varken
        // codeunit 22 satır alanlarının boş olmasını şart koşar ("New Lot No.
        // must be equal to ''"). İzleme yalnızca AddItemTracking'in oluşturduğu
        // reservation kaydında taşınır (lot/seri + yeni lot/seri).
        if (LotNo <> '') or (SerialNo <> '') then
            AddItemTracking(ItemJournalLine, LotNo, SerialNo);
        CustomDimensions.Add('Category', 'Movement');
        Telemetry.AddUserDimensions(CustomDimensions, UserId);
        Session.LogMessage('DOPSWHS-Move-AdHoc', StrSubstNo('Ad-hoc move item %1 qty %2 from %3 to %4 lp %5', ItemNo, Qty, FromBinCode, ToBinCode, LpNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
        // Post via batch codeunit (22/23) rather than "Item Jnl.-Post" (241): the latter raises a
        // "Do you want to post?" Confirm that fails as a client callback over the API / on the handheld.
        ItemJnlPostBatch.SetSuppressCommit(true);
        ItemJnlPostBatch.Run(ItemJournalLine);
    end;

    /// <summary>Geriye dönük imza: operatör kimliği belgenin atamasından okunur.</summary>
    procedure RegisterDirected(var WhseActivityHeader: Record "Warehouse Activity Header")
    begin
        RegisterDirected(WhseActivityHeader, '');
    end;

    /// <summary>
    /// Ambar aktivitesini kaydeder. OperatorUserId = işlemi yapan WMS operatörü;
    /// boşsa belgeye atanmış kullanıcıya düşülür. NEDEN: tüm çağrılar paylaşımlı
    /// servis hesabıyla geldiği için UserId() "kim kaydetti" sorusunu cevaplamıyor.
    /// </summary>
    procedure RegisterDirected(var WhseActivityHeader: Record "Warehouse Activity Header"; OperatorUserId: Code[50])
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        // QM (BC 28) devre dışı — bkz. QualityMgmtBridge.Codeunit.al
        // QualityBridge: Codeunit "DOPSWHS Quality Mgmt Bridge";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        CustomDimensions: Dictionary of [Text, Text];
        Operator: Code[50];
        PutAwayLpNo: Code[20];
        PutAwayTargetBin: Code[20];
        PutAwayDestinations: Dictionary of [Code[20], Code[20]];
        DirectedLpNos: List of [Code[20]];
        DirectedLpLineNos: List of [Integer];
        DirectedMovementLineNos: List of [Integer];
        DirectedBaseQuantities: List of [Decimal];
        DirectedIndex: Integer;
        DirectedReference: Code[40];
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if OperatorUserId <> '' then
            Operator := OperatorUserId
        else
            Operator := WhseActivityHeader."Assigned User ID";

        // Alınan ve konan miktar eşit değilse kayıt durdurulur. Dengesiz kayıt
        // ambar defterinde yoktan stok üretir (toplamada aynı koruma var; burada
        // yerleştirme ve hareket belgeleri için de uygulanır).
        EnsureActivityTakePlaceBalanced(WhseActivityHeader);

        CustomDimensions.Add('Category', 'Movement');
        Telemetry.AddUserDimensions(CustomDimensions, Operator);
        Session.LogMessage('DOPSWHS-Move-RegisterDirected', StrSubstNo('Register warehouse activity %1 type %2', WhseActivityHeader."No.", Format(WhseActivityHeader.Type)), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);

        // MS Quality Management lot/serial block guard — QM (BC 28) devre dışı.
        // BC 28'e geçince aşağıdaki bloğun yorumunu kaldırın.
        // WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        // WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        // if WhseActivityLine.FindSet() then
        //     repeat
        //         QualityBridge.VerifyNotBlocked(
        //             WhseActivityLine."Lot No.",
        //             WhseActivityLine."Serial No.",
        //             '');
        //     until WhseActivityLine.Next() = 0;

        // Register deletes the activity lines. Preserve the LP + final Place bin
        // first, then move the LP header after BC has successfully registered the
        // physical warehouse movement. Without this, stock reaches the put-away
        // bin while the LP remains attached to the receipt bin and Bin Contents
        // shows Quantity in Active LPs as zero.
        if WhseActivityHeader.Type = WhseActivityHeader.Type::"Put-away" then
            CollectPutAwayLpDestinations(WhseActivityHeader, PutAwayDestinations);
        if WhseActivityHeader.Type = WhseActivityHeader.Type::Movement then
            CollectDirectedLpConsumption(
                WhseActivityHeader, DirectedLpNos, DirectedLpLineNos,
                DirectedMovementLineNos, DirectedBaseQuantities);

        WhseActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        WhseActivityLine.SetRange("No.", WhseActivityHeader."No.");
        if WhseActivityLine.FindFirst() then begin
            WhseActivityRegister.Run(WhseActivityLine);
            foreach PutAwayLpNo in PutAwayDestinations.Keys do begin
                PutAwayDestinations.Get(PutAwayLpNo, PutAwayTargetBin);
                FinalizePutAwayLp(
                    PutAwayLpNo, WhseActivityHeader."No.",
                    WhseActivityHeader."Location Code", PutAwayTargetBin);
            end;
            for DirectedIndex := 1 to DirectedLpNos.Count() do begin
                DirectedReference := CopyStr(
                    'MOVE:' + WhseActivityHeader."No." + ':' +
                    Format(DirectedMovementLineNos.Get(DirectedIndex)),
                    1, MaxStrLen(DirectedReference));
                LPMgt.ConsumeLineForWarehouseMovement(
                    DirectedLpNos.Get(DirectedIndex),
                    DirectedLpLineNos.Get(DirectedIndex),
                    DirectedBaseQuantities.Get(DirectedIndex),
                    DirectedReference);
            end;
        end;
    end;

    /// <summary>
    /// Snapshot exact LP quantities before standard movement registration
    /// deletes its activity lines. Only lines confirmed through the guarded
    /// raf + LP endpoint carry Source LP Line No.; legacy/desktop movements
    /// therefore keep their existing behavior.
    /// </summary>
    local procedure CollectDirectedLpConsumption(WhseActivityHeader: Record "Warehouse Activity Header"; var LpNos: List of [Code[20]]; var LpLineNos: List of [Integer]; var MovementLineNos: List of [Integer]; var BaseQuantities: List of [Decimal])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        ActivityLine.SetRange("No.", WhseActivityHeader."No.");
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        ActivityLine.SetFilter("Qty. to Handle (Base)", '>0');
        ActivityLine.SetFilter("LP No.", '<>%1', '');
        if ActivityLine.FindSet() then
            repeat
                if ActivityLine."DOPSWHS Source LP Line No." <= 0 then
                    Error(
                        '%1 hareketinin %2 Al satırında kaynak LP içeriği doğrulanmadı. Terminalde önce rafı, sonra LP''yi okutun.',
                        ActivityLine."No.", ActivityLine."Line No.");
                ValidateDirectedSourceLp(
                    ActivityLine, ActivityLine."Bin Code", ActivityLine."LP No.",
                    ActivityLine."DOPSWHS Source LP Line No.", ActivityLine."Lot No.",
                    ActivityLine."Serial No.");
                LpNos.Add(ActivityLine."LP No.");
                LpLineNos.Add(ActivityLine."DOPSWHS Source LP Line No.");
                MovementLineNos.Add(ActivityLine."Line No.");
                BaseQuantities.Add(ActivityLine."Qty. to Handle (Base)");
            until ActivityLine.Next() = 0;
    end;

    /// <summary>
    /// Preserves every LP destination before standard registration deletes the activity lines.
    /// One put-away may contain many products and many LPs; treating the whole document as one
    /// LP caused every LP header to remain in the receipt bin as soon as a second LP was present.
    /// </summary>
    local procedure CollectPutAwayLpDestinations(WhseActivityHeader: Record "Warehouse Activity Header"; var Destinations: Dictionary of [Code[20], Code[20]])
    var
        ActivityLine: Record "Warehouse Activity Line";
        ExistingTargetBin: Code[20];
    begin
        Clear(Destinations);
        ActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        ActivityLine.SetRange("No.", WhseActivityHeader."No.");
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.SetFilter("LP No.", '<>%1', '');
        if ActivityLine.FindSet() then
            repeat
                if ActivityLine."Qty. to Handle" > 0 then begin
                    ActivityLine.TestField("Bin Code");
                    if Abs(ActivityLine."Qty. to Handle" - ActivityLine."Qty. Outstanding") > 0.00001 then
                        Error(
                            '%1 LP numarasındaki %2 ürünü kısmi taşınamaz. LP''nin tamamını yerleştirin veya ürünü ayrı LP''ye ayırın.',
                            ActivityLine."LP No.", ActivityLine."Item No.");
                    if Destinations.Get(ActivityLine."LP No.", ExistingTargetBin) then begin
                        if ExistingTargetBin <> ActivityLine."Bin Code" then
                            Error(
                                '%1 LP numarası aynı yerleştirmede hem %2 hem %3 rafına konamaz. LP içindeki tüm ürünler için aynı hedef rafı seçin.',
                                ActivityLine."LP No.", ExistingTargetBin, ActivityLine."Bin Code");
                    end else
                        Destinations.Add(ActivityLine."LP No.", ActivityLine."Bin Code");
                end;
            until ActivityLine.Next() = 0;

        // A physical LP moves as one unit. When one product on that LP is selected,
        // every other outstanding product on the same LP must be registered too.
        ActivityLine.Reset();
        ActivityLine.SetRange("Activity Type", WhseActivityHeader.Type);
        ActivityLine.SetRange("No.", WhseActivityHeader."No.");
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.SetFilter("LP No.", '<>%1', '');
        ActivityLine.SetFilter("Qty. Outstanding", '>0');
        if ActivityLine.FindSet() then
            repeat
                if Destinations.ContainsKey(ActivityLine."LP No.") and
                   (ActivityLine."Qty. to Handle" <= 0)
                then
                    Error(
                        '%1 LP numarasındaki tüm ürünleri birlikte yerleştirin. %2 ürünü henüz seçilmedi.',
                        ActivityLine."LP No.", ActivityLine."Item No.");
            until ActivityLine.Next() = 0;
    end;

    local procedure FinalizePutAwayLp(LpNo: Code[20]; PutAwayNo: Code[20]; LocationCode: Code[10]; TargetBinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        RemainingLine: Record "Warehouse Activity Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        SourceBinCode: Code[20];
    begin
        if not LP.Get(LpNo) then
            exit;
        SourceBinCode := LP."Bin Code";
        if (LP."Location Code" <> LocationCode) or (LP."Bin Code" <> TargetBinCode) then begin
            LP.Validate("Location Code", LocationCode);
            LP.Validate("Bin Code", TargetBinCode);
            LP.Modify(true);
            LPMgt.WriteToLedger(
                LP, Enum::"DOPSWHS LP Action"::Moved,
                SourceBinCode, TargetBinCode, 0, '', '', PutAwayNo);
        end;

        RemainingLine.SetRange("Activity Type", RemainingLine."Activity Type"::"Put-away");
        RemainingLine.SetRange("No.", PutAwayNo);
        RemainingLine.SetRange("LP No.", LpNo);
        RemainingLine.SetFilter("Qty. Outstanding", '>0');
        if RemainingLine.IsEmpty() and
           (LP.Status = LP.Status::Assigned) and
           (LP."Assigned Document Type" = LP."Assigned Document Type"::WhsePutaway) and
           (LP."Assigned Document No." = PutAwayNo)
        then
            LPMgt.Release(LP);
    end;

    /// <summary>
    /// Claims an unassigned directed movement for the local WMS user. The
    /// shared Business Central service account is deliberately not used as the
    /// warehouse operator identity.
    /// </summary>
    procedure ClaimDirected(var WhseActivityHeader: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    var
        LockedHeader: Record "Warehouse Activity Header";
    begin
        if RequestingUserId = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');

        LockedHeader.LockTable();
        if not LockedHeader.Get(LockedHeader.Type::Movement, WhseActivityHeader."No.") then
            Error('Hareket belgesi %1 artık bulunamıyor. Listeyi yenileyin.', WhseActivityHeader."No.");
        if (LockedHeader."Assigned User ID" <> '') and
           (LockedHeader."Assigned User ID" <> RequestingUserId)
        then
            Error('Hareket belgesi %1, %2 kullanıcısına atanmış.', LockedHeader."No.", LockedHeader."Assigned User ID");

        if LockedHeader."Assigned User ID" <> RequestingUserId then begin
            LockedHeader."Assigned User ID" := CopyStr(RequestingUserId, 1, MaxStrLen(LockedHeader."Assigned User ID"));
            LockedHeader.Modify(true);
        end;
        WhseActivityHeader := LockedHeader;
    end;

    /// <summary>
    /// Updates a movement Take/Place pair together. Writing only the tapped
    /// row leaves its companion at zero and prevents warehouse registration.
    /// </summary>
    procedure ConfirmDirectedLineFor(var WhseActivityLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; SerialNo: Code[50]; RequestingUserId: Code[50])
    begin
        ConfirmDirectedLineInternal(
            WhseActivityLine, QtyToHandle, LotNo, SerialNo,
            '', '', 0, RequestingUserId);
    end;

    /// <summary>
    /// Confirms a directed-movement Take line only after the physical source
    /// bin and one exact LP content line have been identified. The legacy
    /// confirmation entry point remains available for older clients.
    /// </summary>
    procedure ConfirmDirectedLineFromLpFor(var WhseActivityLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; SourceBinCode: Code[20]; SourceLpNo: Code[20]; SourceLpLineNo: Integer; LotNo: Code[50]; SerialNo: Code[50]; RequestingUserId: Code[50])
    begin
        if SourceBinCode = '' then
            Error('Kaynak raf barkodu zorunludur. Önce %1 rafını okutun.', WhseActivityLine."Bin Code");
        if SourceLpNo = '' then
            Error('Kaynak LP barkodu zorunludur.');
        if SourceLpLineNo <= 0 then
            Error('%1 LP numarasında doğrulanmış bir içerik satırı seçilmedi.', SourceLpNo);

        ConfirmDirectedLineInternal(
            WhseActivityLine, QtyToHandle, LotNo, SerialNo,
            SourceBinCode, SourceLpNo, SourceLpLineNo, RequestingUserId);
    end;

    local procedure ConfirmDirectedLineInternal(var WhseActivityLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; SerialNo: Code[50]; SourceBinCode: Code[20]; SourceLpNo: Code[20]; SourceLpLineNo: Integer; RequestingUserId: Code[50])
    var
        WhseActivityHeader: Record "Warehouse Activity Header";
        CompanionLine: Record "Warehouse Activity Line";
        SourceLP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        PreviousLpNo: Code[20];
    begin
        if RequestingUserId = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');
        if WhseActivityLine."Activity Type" <> WhseActivityLine."Activity Type"::Movement then
            Error('%1 ambar aktivitesi yönlendirilmiş hareket değildir.', WhseActivityLine."No.");
        if not WhseActivityHeader.Get(WhseActivityHeader.Type::Movement, WhseActivityLine."No.") then
            Error('Hareket belgesi %1 artık bulunamıyor. Listeyi yenileyin.', WhseActivityLine."No.");
        if WhseActivityHeader."Assigned User ID" <> RequestingUserId then
            Error('Hareket belgesi %1 bu kullanıcıya atanmış değil.', WhseActivityLine."No.");
        // Eş satırı, kullanıcının seçtiği yeni lotu yazmadan önce mevcut
        // satır anahtarlarıyla bul. Aksi halde lotu boş oluşturulmuş Place satırı,
        // lot girilen Take satırıyla artık eşleşmez.
        WhseActivityLine.LockTable();
        if not WhseActivityLine.Get(
             WhseActivityLine."Activity Type", WhseActivityLine."No.", WhseActivityLine."Line No.")
        then
            Error('Hareket satırı %1 artık bulunamıyor. Belgeyi yenileyin.', WhseActivityLine."Line No.");
        if (QtyToHandle <= 0) or (QtyToHandle > WhseActivityLine."Qty. Outstanding") then
            Error('%1 satırı için hareket miktarı 0 ile %2 arasında olmalıdır.', WhseActivityLine."Line No.", WhseActivityLine."Qty. Outstanding");

        // Validate first so Qty. to Handle (Base), used by the LP capacity
        // check, is calculated with standard Business Central UOM rules.
        WhseActivityLine.Validate("Qty. to Handle", QtyToHandle);

        CompanionLine.SetRange("Activity Type", WhseActivityLine."Activity Type");
        CompanionLine.SetRange("No.", WhseActivityLine."No.");
        CompanionLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type");
        CompanionLine.SetRange("Whse. Document No.", WhseActivityLine."Whse. Document No.");
        CompanionLine.SetRange("Whse. Document Line No.", WhseActivityLine."Whse. Document Line No.");
        CompanionLine.SetRange("Item No.", WhseActivityLine."Item No.");
        CompanionLine.SetRange("Variant Code", WhseActivityLine."Variant Code");
        CompanionLine.SetRange("Unit of Measure Code", WhseActivityLine."Unit of Measure Code");
        CompanionLine.SetRange("Lot No.", WhseActivityLine."Lot No.");
        CompanionLine.SetRange("Serial No.", WhseActivityLine."Serial No.");
        CompanionLine.SetRange("Package No.", WhseActivityLine."Package No.");
        CompanionLine.SetRange("LP No.", WhseActivityLine."LP No.");
        if WhseActivityLine."Action Type" = WhseActivityLine."Action Type"::Take then
            CompanionLine.SetRange("Action Type", CompanionLine."Action Type"::Place)
        else
            CompanionLine.SetRange("Action Type", CompanionLine."Action Type"::Take);
        if CompanionLine.Count() <> 1 then
            Error(
                '%1 hareket satırı için lot/seri/LP bilgileriyle eşleşen tek bir karşı satır bulunamadı. Belgeyi BC''de yeniden oluşturun.',
                WhseActivityLine."Line No.");
        CompanionLine.FindFirst();

        EnsureDirectedMovementTracking(WhseActivityLine, QtyToHandle, LotNo, SerialNo);
        PreviousLpNo := WhseActivityLine."LP No.";
        if SourceLpNo <> '' then begin
            ValidateDirectedSourceLp(
                WhseActivityLine, SourceBinCode, SourceLpNo, SourceLpLineNo,
                LotNo, SerialNo);
            SourceLP.Get(SourceLpNo);
            if SourceLP.Status = SourceLP.Status::Built then
                LPMgt.Assign(
                    SourceLP, Enum::"DOPSWHS Assigned Doc Type"::WhseMovement,
                    WhseActivityLine."No.");
        end;

        WhseActivityLine.Validate("Lot No.", LotNo);
        WhseActivityLine.Validate("Serial No.", SerialNo);
        if SourceLpNo <> '' then begin
            WhseActivityLine."LP No." := SourceLpNo;
            WhseActivityLine."DOPSWHS Source LP Line No." := SourceLpLineNo;
        end;
        WhseActivityLine.Modify(true);
        CompanionLine.Validate("Lot No.", LotNo);
        CompanionLine.Validate("Serial No.", SerialNo);
        CompanionLine.Validate("Qty. to Handle", QtyToHandle);
        if SourceLpNo <> '' then begin
            CompanionLine."LP No." := SourceLpNo;
            CompanionLine."DOPSWHS Source LP Line No." := SourceLpLineNo;
        end;
        CompanionLine.Modify(true);

        if (SourceLpNo <> '') and (PreviousLpNo <> '') and (PreviousLpNo <> SourceLpNo) then
            ReleasePreviousDirectedLpIfUnused(
                WhseActivityLine."No.", WhseActivityLine."Line No.", PreviousLpNo);
    end;

    local procedure ValidateDirectedSourceLp(WhseActivityLine: Record "Warehouse Activity Line"; SourceBinCode: Code[20]; SourceLpNo: Code[20]; SourceLpLineNo: Integer; LotNo: Code[50]; SerialNo: Code[50])
    var
        SourceLP: Record "DOPSWHS LP Header";
        SourceLPLine: Record "DOPSWHS LP Line";
        OtherActivityLine: Record "Warehouse Activity Line";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        EffectiveUoM: Code[10];
        QtyPerUoM: Decimal;
        AvailableBaseQty: Decimal;
        SelectedBaseQty: Decimal;
    begin
        if WhseActivityLine."Action Type" <> WhseActivityLine."Action Type"::Take then
            Error('LP doğrulaması yalnız Al satırında yapılabilir.');
        if SourceBinCode <> WhseActivityLine."Bin Code" then
            Error(
                'Yanlış kaynak raf okutuldu. Beklenen: %1, okutulan: %2.',
                WhseActivityLine."Bin Code", SourceBinCode);
        if not SourceLP.Get(SourceLpNo) then
            Error('%1 kaynak LP numarası bulunamadı.', SourceLpNo);
        if not (SourceLP.Status in [SourceLP.Status::Built, SourceLP.Status::Assigned]) then
            Error(
                '%1 LP numarası harekete uygun değil. Güncel durum: %2.',
                SourceLpNo, SourceLP.Status);
        if (SourceLP.Status = SourceLP.Status::Assigned) and
           ((SourceLP."Assigned Document Type" <> SourceLP."Assigned Document Type"::WhseMovement) or
            (SourceLP."Assigned Document No." <> WhseActivityLine."No."))
        then
            Error(
                '%1 LP numarası başka bir belgeye atanmış: %2.',
                SourceLpNo, SourceLP."Assigned Document No.");
        if SourceLP."Location Code" <> WhseActivityLine."Location Code" then
            Error(
                '%1 LP numarası %2 lokasyonunda; hareket satırı %3 lokasyonundadır.',
                SourceLpNo, SourceLP."Location Code", WhseActivityLine."Location Code");
        if SourceLP."Bin Code" <> SourceBinCode then
            Error(
                '%1 LP numarası %2 rafında kayıtlı; okutulan kaynak raf %3.',
                SourceLpNo, SourceLP."Bin Code", SourceBinCode);
        if not SourceLPLine.Get(SourceLpNo, SourceLpLineNo) then
            Error('%1 LP numarasının %2 içerik satırı bulunamadı.', SourceLpNo, SourceLpLineNo);
        if SourceLPLine."Item No." <> WhseActivityLine."Item No." then
            Error(
                'Yanlış LP: hareket %1 maddesini istiyor, %2 LP satırında %3 var.',
                WhseActivityLine."Item No.", SourceLpNo, SourceLPLine."Item No.");
        if SourceLPLine."Variant Code" <> WhseActivityLine."Variant Code" then
            Error(
                'Yanlış varyant: hareket %1, %2 LP satırı %3 varyantını içeriyor.',
                WhseActivityLine."Variant Code", SourceLpNo, SourceLPLine."Variant Code");
        if SourceLPLine."Lot No." <> LotNo then
            Error(
                'Yanlış lot: %1 LP satırındaki lot %2, doğrulanan lot %3.',
                SourceLpNo, SourceLPLine."Lot No.", LotNo);
        if SourceLPLine."Serial No." <> SerialNo then
            Error(
                'Yanlış seri: %1 LP satırındaki seri %2, doğrulanan seri %3.',
                SourceLpNo, SourceLPLine."Serial No.", SerialNo);
        if (WhseActivityLine."Lot No." <> '') and
           (WhseActivityLine."Lot No." <> SourceLPLine."Lot No.")
        then
            Error(
                'Yanlış LP: hareket satırındaki lot %1, %2 LP numarasındaki lot %3.',
                WhseActivityLine."Lot No.", SourceLpNo, SourceLPLine."Lot No.");
        if (WhseActivityLine."Serial No." <> '') and
           (WhseActivityLine."Serial No." <> SourceLPLine."Serial No.")
        then
            Error(
                'Yanlış LP: hareket satırındaki seri %1, %2 LP numarasındaki seri %3.',
                WhseActivityLine."Serial No.", SourceLpNo, SourceLPLine."Serial No.");

        Item.Get(SourceLPLine."Item No.");
        EffectiveUoM := SourceLPLine."Unit of Measure";
        if EffectiveUoM = '' then
            EffectiveUoM := Item."Base Unit of Measure";
        QtyPerUoM := 1;
        if EffectiveUoM <> Item."Base Unit of Measure" then begin
            if not ItemUoM.Get(SourceLPLine."Item No.", EffectiveUoM) then
                Error('%1 maddesinin %2 ölçü birimi bulunamadı.', SourceLPLine."Item No.", EffectiveUoM);
            QtyPerUoM := ItemUoM."Qty. per Unit of Measure";
            if QtyPerUoM <= 0 then
                Error('%1 maddesinin %2 ölçü birimi dönüşümü geçersizdir.', SourceLPLine."Item No.", EffectiveUoM);
        end;
        AvailableBaseQty := Round(SourceLPLine.Quantity * QtyPerUoM, 0.00001);
        SelectedBaseQty := WhseActivityLine."Qty. to Handle (Base)";
        OtherActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type");
        OtherActivityLine.SetRange("No.", WhseActivityLine."No.");
        OtherActivityLine.SetRange("Action Type", OtherActivityLine."Action Type"::Take);
        OtherActivityLine.SetRange("LP No.", SourceLpNo);
        OtherActivityLine.SetRange("DOPSWHS Source LP Line No.", SourceLpLineNo);
        OtherActivityLine.SetFilter("Line No.", '<>%1', WhseActivityLine."Line No.");
        OtherActivityLine.SetFilter("Qty. to Handle (Base)", '>0');
        if OtherActivityLine.FindSet() then
            repeat
                SelectedBaseQty += OtherActivityLine."Qty. to Handle (Base)";
            until OtherActivityLine.Next() = 0;
        if AvailableBaseQty + 0.00001 < SelectedBaseQty then
            Error(
                '%1 LP numarasında %2 maddesi ve %3 lotu için yeterli miktar yok. LP: %4, bu harekette seçilen: %5.',
                SourceLpNo, SourceLPLine."Item No.", SourceLPLine."Lot No.",
                AvailableBaseQty, SelectedBaseQty);
    end;

    local procedure ReleasePreviousDirectedLpIfUnused(MovementNo: Code[20]; CurrentLineNo: Integer; PreviousLpNo: Code[20])
    var
        OtherLine: Record "Warehouse Activity Line";
        PreviousLP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        OtherLine.SetRange("Activity Type", OtherLine."Activity Type"::Movement);
        OtherLine.SetRange("No.", MovementNo);
        OtherLine.SetRange("Action Type", OtherLine."Action Type"::Take);
        OtherLine.SetRange("LP No.", PreviousLpNo);
        OtherLine.SetFilter("Line No.", '<>%1', CurrentLineNo);
        OtherLine.SetFilter("Qty. to Handle", '>0');
        if not OtherLine.IsEmpty() then
            exit;
        if PreviousLP.Get(PreviousLpNo) and
           (PreviousLP.Status = PreviousLP.Status::Assigned) and
           (PreviousLP."Assigned Document Type" = PreviousLP."Assigned Document Type"::WhseMovement) and
           (PreviousLP."Assigned Document No." = MovementNo)
        then
            LPMgt.Release(PreviousLP);
    end;

    local procedure EnsureDirectedMovementTracking(WhseActivityLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; SerialNo: Code[50])
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if QtyToHandle <= 0 then
            exit;
        if not Item.Get(WhseActivityLine."Item No.") then
            exit;
        if (Item."Item Tracking Code" = '') or (not ItemTrackingCode.Get(Item."Item Tracking Code")) then
            exit;
        if (ItemTrackingCode."Lot Specific Tracking" or ItemTrackingCode."Lot Warehouse Tracking") and (LotNo = '') then
            Error(
                '%1 ürününün %2 hareket satırında lot numarası zorunludur. %3 rafındaki stok lotlarından birini seçin.',
                WhseActivityLine."Item No.", WhseActivityLine."Line No.", WhseActivityLine."Bin Code");
        if (ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking") and (SerialNo = '') then
            Error(
                '%1 ürününün %2 hareket satırında seri numarası zorunludur. %3 rafındaki stok serisini okutun.',
                WhseActivityLine."Item No.", WhseActivityLine."Line No.", WhseActivityLine."Bin Code");
    end;

    procedure RegisterDirectedFor(var WhseActivityHeader: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    var
        LockedHeader: Record "Warehouse Activity Header";
    begin
        if RequestingUserId = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');
        LockedHeader.LockTable();
        if not LockedHeader.Get(LockedHeader.Type::Movement, WhseActivityHeader."No.") then
            Error('Hareket belgesi %1 artık bulunamıyor. Listeyi yenileyin.', WhseActivityHeader."No.");
        if LockedHeader."Assigned User ID" <> RequestingUserId then
            Error('Hareket belgesi %1 bu kullanıcıya atanmış değil.', LockedHeader."No.");
        WhseActivityHeader := LockedHeader;
        RegisterDirected(WhseActivityHeader, RequestingUserId);
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

    local procedure RegisterWhseMove(LocationCode: Code[10]; FromBinCode: Code[20]; ToBinCode: Code[20]; ItemNo: Code[20]; LpNo: Code[20]; Qty: Decimal; UserId: Code[50]; LotNo: Code[50]; SerialNo: Code[50])
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

        // Saha hatası ("The Item does not exist. No.=''"): register TÜM sayfayı
        // postalar; önceki başarısız denemeden takılı (yarım/bozuk) satır varsa
        // her yeni hareketi düşürür. DOPS-MOBIL bizim özel sayfamız — başarılı
        // post satırları zaten siler, burada ne varsa artıktır: temizle.
        PurgeStaleWhseLines(WhseJournalTemplate.Name, BatchName, LocationCode);

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
        // The ad-hoc LP move has no Warehouse Activity Line from which the
        // propagation subscriber can infer an LP. Carry the exact LP on the
        // posting line so both generated Warehouse Entries keep their source
        // pallet. Without this, the stock moves correctly but Ambar
        // Hareketleri shows the movement without an LP number.
        WhseJournalLine."DOPSWHS LP No." := LpNo;
        WhseJournalLine.Insert(true);

        // Saha hatası (17 Tem): "Item tracking lines ... must account for the
        // same quantity" — whse journal izlemeyi satır alanından DEĞİL, bağlı
        // "Whse. Item Tracking Line" kaydından okur (UI'daki Item Tracking
        // Lines sayfasının kod karşılığı).
        if (LotNo <> '') or (SerialNo <> '') then
            AddWhseItemTracking(WhseJournalLine, LotNo, SerialNo);

        // Item Jnl.-Post Batch'in ambar karşılığı — confirm diyaloğu açmadan
        // register eder (web servis bağlamı).
        WhseJnlRegisterBatch.SetSuppressCommit(true);
        WhseJnlRegisterBatch.Run(WhseJournalLine);
    end;

    local procedure AddWhseItemTracking(WhseJnlLine: Record "Warehouse Journal Line"; LotNo: Code[50]; SerialNo: Code[50])
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
        WhseItemTrackingLine."Serial No." := SerialNo;
        // Reclass: aynı lot/seri hedef bin'e taşınır.
        WhseItemTrackingLine."New Lot No." := LotNo;
        WhseItemTrackingLine."New Serial No." := SerialNo;
        WhseItemTrackingLine.Insert();
    end;

    /// <summary>
    /// AMBAR-SEVİYESİ raf düzeltmesi: bir rafın (raf/ürün/varyant/birim/lot/seri)
    /// ambar bakiyesini hedef miktara çeker. Madde defterine DOKUNMAZ — bu yüzden
    /// yalnız ambar defteri ile madde defteri arasında oluşmuş sapmaları (ör. eski
    /// bir hatalı toplama kaydının bıraktığı hayalet miktar) düzeltmek içindir.
    /// Ambar Fiziksel Sayım Günlüğü ile register edilir; sayımın kullandığı
    /// kanıtlanmış yolun aynısıdır. Yalnız API'den (yönetici) çağrılır.
    /// </summary>
    procedure AdjustBinToQuantity(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; TargetQty: Decimal; Reference: Text[50]): Decimal
    var
        Location: Record Location;
        Bin: Record Bin;
        Item: Record Item;
        WarehouseEntry: Record "Warehouse Entry";
        WhseJournalTemplate: Record "Warehouse Journal Template";
        WhseJournalBatch: Record "Warehouse Journal Batch";
        WhseJournalLine: Record "Warehouse Journal Line";
        StaleLine: Record "Warehouse Journal Line";
        WhseJnlRegisterBatch: Codeunit "Whse. Jnl.-Register Batch";
        UomMgt: Codeunit "Unit of Measure Management";
        CurrentQty: Decimal;
        ExpirationDate: Date;
        EffectiveUom: Code[10];
    begin
        if not Location.Get(LocationCode) then
            Error(BinAdjustLocationErr, LocationCode);
        if not Bin.Get(LocationCode, BinCode) then
            Error(BinAdjustBinErr, BinCode, LocationCode);
        if not Item.Get(ItemNo) then
            Error(BinAdjustItemErr, ItemNo);
        if TargetQty < 0 then
            Error(BinAdjustNegativeErr);

        EffectiveUom := UomCode;
        if EffectiveUom = '' then
            EffectiveUom := Item."Base Unit of Measure";

        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Bin Code", BinCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", VariantCode);
        WarehouseEntry.SetRange("Unit of Measure Code", EffectiveUom);
        WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.SetRange("Serial No.", SerialNo);
        WarehouseEntry.CalcSums(Quantity);
        CurrentQty := WarehouseEntry.Quantity;
        if CurrentQty = TargetQty then
            exit(0);

        if not WhseJournalTemplate.Get(WhsePhysInvTemplateTok) then begin
            WhseJournalTemplate.Init();
            WhseJournalTemplate.Name := WhsePhysInvTemplateTok;
            WhseJournalTemplate.Description := 'BCWMS ambar düzeltme';
            WhseJournalTemplate.Validate(Type, WhseJournalTemplate.Type::"Physical Inventory");
            WhseJournalTemplate.Insert(true);
        end;
        if not WhseJournalBatch.Get(WhsePhysInvTemplateTok, WhseAdjustBatchTok, LocationCode) then begin
            WhseJournalBatch.Init();
            WhseJournalBatch."Journal Template Name" := WhsePhysInvTemplateTok;
            WhseJournalBatch.Name := WhseAdjustBatchTok;
            WhseJournalBatch."Location Code" := LocationCode;
            WhseJournalBatch.Description := 'BCWMS raf düzeltme';
            WhseJournalBatch.Insert(true);
        end;
        StaleLine.SetRange("Journal Template Name", WhsePhysInvTemplateTok);
        StaleLine.SetRange("Journal Batch Name", WhseAdjustBatchTok);
        StaleLine.SetRange("Location Code", LocationCode);
        if not StaleLine.IsEmpty() then
            StaleLine.DeleteAll(true);

        WhseJournalLine.Init();
        WhseJournalLine.Validate("Journal Template Name", WhsePhysInvTemplateTok);
        WhseJournalLine.Validate("Journal Batch Name", WhseAdjustBatchTok);
        WhseJournalLine.Validate("Location Code", LocationCode);
        WhseJournalLine."Line No." := 10000;
        WhseJournalLine."Registering Date" := WorkDate();
        WhseJournalLine."Whse. Document No." := CopyStr(Reference, 1, MaxStrLen(WhseJournalLine."Whse. Document No."));
        WhseJournalLine.Validate("Item No.", ItemNo);
        WhseJournalLine.Validate("Variant Code", VariantCode);
        WhseJournalLine.Validate("Unit of Measure Code", EffectiveUom);
        WhseJournalLine.Validate("Zone Code", Bin."Zone Code");
        WhseJournalLine.Validate("Bin Code", BinCode);
        WhseJournalLine.Validate("Phys. Inventory", true);
        if LotNo <> '' then
            WhseJournalLine.Validate("Lot No.", LotNo);
        if SerialNo <> '' then
            WhseJournalLine.Validate("Serial No.", SerialNo);
        // BC "Qty. (Base)" hesabı: Qty. (Phys. Inventory) (Base) - Qty. (Calculated) (Base).
        // "Qty. (Calculated) (Base)" alanının OnValidate'i yoktur; doldurulmazsa taban
        // miktar fark yerine hedef miktar olur, hedef 0 iken de Qty. (Absolute, Base)
        // sıfır kalıp BC'nin Sign hesabı sıfıra bölme hatası verir.
        WhseJournalLine.Validate("Qty. (Calculated)", CurrentQty);
        WhseJournalLine."Qty. (Calculated) (Base)" :=
            Round(CurrentQty * WhseJournalLine."Qty. per Unit of Measure", UomMgt.QtyRndPrecision());
        ExpirationDate := ExpirationDateForTracking(LocationCode, ItemNo, VariantCode, LotNo, SerialNo);
        if ExpirationDate <> 0D then
            WhseJournalLine."Expiration Date" := ExpirationDate;
        WhseJournalLine.Validate("Qty. (Phys. Inventory)", TargetQty);
        WhseJournalLine.Insert(true);

        WhseJournalLine.Reset();
        WhseJournalLine.SetRange("Journal Template Name", WhsePhysInvTemplateTok);
        WhseJournalLine.SetRange("Journal Batch Name", WhseAdjustBatchTok);
        WhseJournalLine.SetRange("Location Code", LocationCode);
        WhseJournalLine.FindFirst();
        WhseJnlRegisterBatch.SetSuppressCommit(true);
        WhseJnlRegisterBatch.Run(WhseJournalLine);
        exit(TargetQty - CurrentQty);
    end;

    /// <summary>
    /// Bakım: taban miktarı ("Qty. (Base)") ile miktarı tutarsız kalmış ambar
    /// hareketlerini onarır. 1.14.0.95 öncesi sayım/raf düzeltme kaydı
    /// "Qty. (Calculated) (Base)" alanını doldurmadığı için BC farkın yerine
    /// sayılan miktarın tamamını taban miktar olarak yazıyordu; bu da raf
    /// bakiyesinin (Bin Content "Quantity (Base)") yanlış görünmesine yol
    /// açıyor. Dönen değer onarılan hareket sayısıdır.
    /// </summary>
    procedure RepairWarehouseEntryBaseQty(LocationCode: Code[10]; ItemNo: Code[20]): Integer
    var
        WarehouseEntry: Record "Warehouse Entry";
        ExpectedBase: Decimal;
        Repaired: Integer;
    begin
        if LocationCode <> '' then
            WarehouseEntry.SetRange("Location Code", LocationCode);
        if ItemNo <> '' then
            WarehouseEntry.SetRange("Item No.", ItemNo);
        if not WarehouseEntry.FindSet() then
            exit(0);
        repeat
            if WarehouseEntry."Qty. per Unit of Measure" <> 0 then begin
                ExpectedBase := Round(WarehouseEntry.Quantity * WarehouseEntry."Qty. per Unit of Measure", 0.00001);
                if WarehouseEntry."Qty. (Base)" <> ExpectedBase then begin
                    WarehouseEntry."Qty. (Base)" := ExpectedBase;
                    WarehouseEntry.Modify(false);
                    Repaired += 1;
                end;
            end;
        until WarehouseEntry.Next() = 0;
        exit(Repaired);
    end;

    /// <summary>
    /// Bakım: dengesiz kalmış TEK bir ambar hareketinin miktarını düzeltir
    /// (ör. Take -250 / Place +300 gibi eşleşmeyen yerleştirme). NewQuantity = 0
    /// verilirse hareket silinir. Madde defterine dokunmaz; ambar defteri ile
    /// madde defteri arasındaki sapmayı kaynağından kapatmak içindir.
    /// </summary>
    procedure FixWarehouseEntryQuantity(EntryNo: Integer; NewQuantity: Decimal): Boolean
    var
        WarehouseEntry: Record "Warehouse Entry";
    begin
        if not WarehouseEntry.Get(EntryNo) then
            Error(WhseEntryMissingErr, EntryNo);
        if NewQuantity = 0 then begin
            WarehouseEntry.Delete(false);
            exit(true);
        end;
        if WarehouseEntry."Qty. per Unit of Measure" = 0 then
            WarehouseEntry."Qty. per Unit of Measure" := 1;
        WarehouseEntry.Quantity := NewQuantity;
        WarehouseEntry."Qty. (Base)" := Round(NewQuantity * WarehouseEntry."Qty. per Unit of Measure", 0.00001);
        WarehouseEntry.Modify(false);
        exit(true);
    end;

    /// <summary>Lot/seri için ambar hareketlerinde kayıtlı son kullanma tarihi.</summary>
    local procedure ExpirationDateForTracking(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]): Date
    var
        WarehouseEntry: Record "Warehouse Entry";
    begin
        if (LotNo = '') and (SerialNo = '') then
            exit(0D);
        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        WarehouseEntry.SetRange("Variant Code", VariantCode);
        WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.SetRange("Serial No.", SerialNo);
        WarehouseEntry.SetFilter("Expiration Date", '<>%1', 0D);
        if WarehouseEntry.FindLast() then
            exit(WarehouseEntry."Expiration Date");
        exit(0D);
    end;

    /// <summary>
    /// Ambar belgesinde "Al" ve "Koy" satırlarının işlenecek miktarları eşit mi?
    /// Değilse kayıt engellenir: fark, ambar defterinde karşılığı olmayan stok
    /// olarak kalır ve raf bakiyesini bozar.
    /// </summary>
    local procedure EnsureActivityTakePlaceBalanced(WhseActivityHeader: Record "Warehouse Activity Header")
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        TakeQtyBase: Decimal;
        PlaceQtyBase: Decimal;
    begin
        TakeLine.SetRange("Activity Type", WhseActivityHeader.Type);
        TakeLine.SetRange("No.", WhseActivityHeader."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        if TakeLine.IsEmpty() then
            exit;
        TakeLine.CalcSums("Qty. to Handle (Base)");
        TakeQtyBase := TakeLine."Qty. to Handle (Base)";

        PlaceLine.SetRange("Activity Type", WhseActivityHeader.Type);
        PlaceLine.SetRange("No.", WhseActivityHeader."No.");
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        if PlaceLine.IsEmpty() then
            exit;
        PlaceLine.CalcSums("Qty. to Handle (Base)");
        PlaceQtyBase := PlaceLine."Qty. to Handle (Base)";

        if TakeQtyBase <> PlaceQtyBase then
            Error(ActivityUnbalancedErr, WhseActivityHeader."No.", TakeQtyBase, PlaceQtyBase);
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

    local procedure PurgeStaleItemLines(TemplateName: Code[10]; BatchName: Code[10])
    var
        StaleLine: Record "Item Journal Line";
        StaleReservEntry: Record "Reservation Entry";
    begin
        StaleLine.SetRange("Journal Template Name", TemplateName);
        StaleLine.SetRange("Journal Batch Name", BatchName);
        if not StaleLine.IsEmpty() then
            StaleLine.DeleteAll(true);
        StaleReservEntry.SetRange("Source Type", Database::"Item Journal Line");
        StaleReservEntry.SetRange("Source ID", TemplateName);
        StaleReservEntry.SetRange("Source Batch Name", BatchName);
        if not StaleReservEntry.IsEmpty() then
            StaleReservEntry.DeleteAll(true);
    end;

    local procedure PurgeStaleWhseLines(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        StaleLine: Record "Warehouse Journal Line";
        StaleTracking: Record "Whse. Item Tracking Line";
    begin
        StaleLine.SetRange("Journal Template Name", TemplateName);
        StaleLine.SetRange("Journal Batch Name", BatchName);
        StaleLine.SetRange("Location Code", LocationCode);
        if not StaleLine.IsEmpty() then
            StaleLine.DeleteAll(true);
        // Takılı satırların tracking kayıtları da temizlenir (ters alan
        // eşlemesiyle: Source ID = batch, Source Batch Name = template).
        StaleTracking.SetRange("Source Type", Database::"Warehouse Journal Line");
        StaleTracking.SetRange("Source ID", BatchName);
        StaleTracking.SetRange("Source Batch Name", TemplateName);
        StaleTracking.SetRange("Location Code", LocationCode);
        if not StaleTracking.IsEmpty() then
            StaleTracking.DeleteAll(true);
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

    // Reclass satırına item tracking: aynı lot/seri kaynaktan düşülüp hedefe
    // yazılır. Standart desen: Create Reserv. Entry ile
    // Prospect rezervasyon kaydı (item journal post bunu tracking spec olarak okur).
    local procedure AddItemTracking(var ItemJnlLine: Record "Item Journal Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        TempReservEntry: Record "Reservation Entry";
        ReservEntry: Record "Reservation Entry";
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        TempReservEntry."Lot No." := LotNo;
        TempReservEntry."New Lot No." := LotNo;
        TempReservEntry."Serial No." := SerialNo;
        TempReservEntry."New Serial No." := SerialNo;
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
        if LotNo <> '' then
            ReservEntry.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            ReservEntry.SetRange("Serial No.", SerialNo);
        if ReservEntry.FindSet(true) then
            repeat
                if ReservEntry."New Lot No." = '' then begin
                    ReservEntry."New Lot No." := LotNo;
                end;
                if ReservEntry."New Serial No." = '' then
                    ReservEntry."New Serial No." := SerialNo;
                ReservEntry.Modify();
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
        // Non-directed locations post through Item Journal instead of the
        // Warehouse Journal. Preserve the same explicit LP context there too.
        ItemJournalLine."DOPSWHS LP No." := LpNo;
        ItemJournalLine."Package No." := LpNo;
        ItemJournalLine.Insert(true);
    end;

    var
        WhsePhysInvTemplateTok: Label 'PHYSINV', Locked = true;
        WhseAdjustBatchTok: Label 'DOPS-ADJ', Locked = true;
        BinAdjustLocationErr: Label '%1 lokasyonu bulunamadı.', Comment = '%1 location';
        BinAdjustBinErr: Label '%1 rafı %2 lokasyonunda bulunamadı.', Comment = '%1 bin, %2 location';
        BinAdjustItemErr: Label '%1 ürünü bulunamadı.', Comment = '%1 item';
        BinAdjustNegativeErr: Label 'Hedef raf miktarı negatif olamaz.';
        ActivityUnbalancedErr: Label '%1 belgesinde alınan miktar (%2) ile konan miktar (%3) eşit değil. Stok bozulmaması için kayıt durduruldu; satırları yenileyip miktarı tekrar onaylayın.', Comment = '%1 doc no, %2 take qty, %3 place qty';
        WhseEntryMissingErr: Label '%1 numaralı ambar hareketi bulunamadı.', Comment = '%1 entry no';
}
