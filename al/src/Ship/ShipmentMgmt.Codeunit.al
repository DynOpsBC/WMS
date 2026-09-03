codeunit 72047 "DOPSWHS Shipment Mgmt"
{
    Access = Public;
    Permissions =
        tabledata "Warehouse Entry" = r,
        tabledata "Reservation Entry" = r,
        tabledata "Whse. Item Tracking Line" = rimd;

    procedure ConfirmShipmentLine(var WhseShipmentLine: Record "Warehouse Shipment Line"; QtyToShip: Decimal; LotNo: Code[50]; LicensePlateNo: Code[20]; SSCC: Code[18])
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
    begin
        WhseShipmentLine.Validate("Qty. to Ship", QtyToShip);
        EnsureShipmentLot(WhseShipmentLine, LotNo);
        WhseShipmentLine."DOPSWHS Lot No." := LotNo;
        WhseShipmentLine."LP No." := LicensePlateNo;
        WhseShipmentLine.SSCC := SSCC;
        WhseShipmentLine.Modify(true);

        // Stamp the Whse Shipment Header with this LP (first line wins) so the header-level
        // OData query can surface the carton without drilling lines.
        if LicensePlateNo <> '' then
            if WhseShipmentHeader.Get(WhseShipmentLine."No.") then
                if WhseShipmentHeader."DOPSWHS LP No." = '' then begin
                    WhseShipmentHeader."DOPSWHS LP No." := LicensePlateNo;
                    WhseShipmentHeader.Modify(true);
                end;
    end;

    /// <summary>
    /// Returns the effective outbound lot for a warehouse shipment line. The
    /// mobile override wins; otherwise a single lot assigned on the source
    /// Sales Order Item Tracking Lines is surfaced automatically. Multiple
    /// distinct lots are deliberately left blank so the operator must choose.
    /// </summary>
    procedure GetShipmentLineLot(WhseShipmentLine: Record "Warehouse Shipment Line"; var LotNo: Code[50])
    var
        ReservationEntry: Record "Reservation Entry";
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
    begin
        Clear(LotNo);
        if WhseShipmentLine."DOPSWHS Lot No." <> '' then begin
            LotNo := WhseShipmentLine."DOPSWHS Lot No.";
            exit;
        end;

        WhseItemTrackingLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        WhseItemTrackingLine.SetRange("Source ID", WhseShipmentLine."No.");
        WhseItemTrackingLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        WhseItemTrackingLine.SetFilter("Lot No.", '<>%1', '');
        if not WhseItemTrackingLine.IsEmpty() then begin
            // Warehouse tracking is the latest operational truth. If it has
            // multiple lots, keep LotNo blank instead of falling back to an
            // older single-lot reservation from the source sales line.
            UniqueWarehouseTrackingLot(WhseItemTrackingLine, LotNo);
            exit;
        end;

        SetSourceReservationFilters(ReservationEntry, WhseShipmentLine);
        ReservationEntry.SetFilter("Lot No.", '<>%1', '');
        UniqueReservationLot(ReservationEntry, LotNo);
    end;

    procedure CreatePick(var WhseShipmentHeader: Record "Warehouse Shipment Header"): Code[20]
    begin
        exit(CreatePickForUser(WhseShipmentHeader, CopyStr(UserId(), 1, MaxStrLen(WhseShipmentHeader."Assigned User ID")), ''));
    end;

    procedure CreatePickFor(var WhseShipmentHeader: Record "Warehouse Shipment Header"; RequestingUserId: Code[50]): Code[20]
    begin
        if RequestingUserId = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');
        if WhseShipmentHeader."Assigned User ID" <> RequestingUserId then
            Error('Sevkiyat belgesi %1 bu kullanıcıya atanmış değil.', WhseShipmentHeader."No.");
        exit(CreatePickForUser(WhseShipmentHeader, RequestingUserId, ''));
    end;

    /// <summary>
    /// Operatörün SEÇTİĞİ paletten toplama oluşturur. CreatePickFor ile aynı
    /// kurallar geçerlidir; ek olarak seçilen palet doğrulanır ve raf tercihi
    /// o palete zorlanır. Palet tüm miktarı karşılamıyorsa BC kalanı başka
    /// raftan tamamlar; bu kabul edilebilir.
    /// </summary>
    procedure CreatePickFromLp(var WhseShipmentHeader: Record "Warehouse Shipment Header"; RequestingUserId: Code[50]; LpNo: Code[20]): Code[20]
    begin
        if RequestingUserId = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');
        if WhseShipmentHeader."Assigned User ID" <> RequestingUserId then
            Error('Sevkiyat belgesi %1 bu kullanıcıya atanmış değil.', WhseShipmentHeader."No.");
        if LpNo <> '' then
            ValidateForcedPickLp(WhseShipmentHeader, LpNo);
        exit(CreatePickForUser(WhseShipmentHeader, RequestingUserId, LpNo));
    end;

    /// <summary>
    /// Seçilen paletin toplama için gerçekten kullanılabilir olduğunu
    /// doğrular. Her hata paleti adıyla anar; terminal mesajı doğrudan
    /// operatöre gösterir.
    /// </summary>
    /// <summary>
    /// Create Pick raporunu hata durumunda da geri dönebilecek şekilde çalıştırır;
    /// çağıran abonelik çözümünü (UnbindSubscription) garantiler.
    /// </summary>
    [TryFunction]
    local procedure TryRunCreatePick(var CreatePickReport: Report "Whse.-Shipment - Create Pick")
    begin
        CreatePickReport.RunModal();
    end;

    local procedure ValidateForcedPickLp(WhseShipmentHeader: Record "Warehouse Shipment Header"; LpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        HasMatchingItem: Boolean;
    begin
        if not LP.Get(LpNo) then
            Error(LpNotFoundErr, LpNo);
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            Error(LpNotActiveErr, LpNo, Format(LP.Status));
        if (LP."Assigned Document No." <> '') and (LP."Assigned Document No." <> WhseShipmentHeader."No.") then
            Error(LpAssignedElsewhereErr, LpNo, LP."Assigned Document No.");
        if LP."Location Code" <> WhseShipmentHeader."Location Code" then
            Error(LpOtherLocationErr, LpNo, LP."Location Code", WhseShipmentHeader."Location Code");
        if LP."Bin Code" = '' then
            Error(LpNoBinErr, LpNo);

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        WhseShipmentLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if WhseShipmentLine.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LpNo);
                LPLine.SetRange("Item No.", WhseShipmentLine."Item No.");
                LPLine.SetRange("Variant Code", WhseShipmentLine."Variant Code");
                if WhseShipmentLine."DOPSWHS Lot No." <> '' then
                    LPLine.SetRange("Lot No.", WhseShipmentLine."DOPSWHS Lot No.");
                LPLine.SetFilter(Quantity, '>0');
                if not LPLine.IsEmpty() then
                    HasMatchingItem := true;
            until (WhseShipmentLine.Next() = 0) or HasMatchingItem;

        if not HasMatchingItem then
            Error(LpHasNoShipmentItemErr, LpNo, WhseShipmentHeader."No.");
    end;

    local procedure CreatePickForUser(var WhseShipmentHeader: Record "Warehouse Shipment Header"; AssignToUserId: Code[50]; ForcedLpNo: Code[20]): Code[20]
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseActivityLine: Record "Warehouse Activity Line";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        CreatePickReport: Report "Whse.-Shipment - Create Pick";
        LPPickPreference: Codeunit "DOPSWHS LP Pick Preference";
        PickNo: Code[20];
        ReportUserId: Code[50];
    begin
        // Aynı sevkiyat için açık pick varsa ikinci bir pick üretme; mevcut kaydı döndür.
        PickNo := FindOpenPick(WhseShipmentHeader."No.");
        if PickNo <> '' then begin
            EnsurePickAssignedTo(PickNo, AssignToUserId);
            StampShipmentLotsOnPick(WhseShipmentHeader."No.", PickNo);
            exit(PickNo);
        end;

        if WhseShipmentHeader.Status <> WhseShipmentHeader.Status::Released then begin
            WhseShipmentRelease.Release(WhseShipmentHeader);
            WhseShipmentHeader.Get(WhseShipmentHeader."No.");
        end;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if not WhseShipmentLine.FindFirst() then
            Error(NoShipmentLinesErr, WhseShipmentHeader."No.");

        // The mobile tracked-item flow deliberately lets the warehouse pick
        // split the requested quantity across the actually available lots and
        // bins. Remove only shipment-level tracking copied from an earlier
        // single-lot choice. Source sales reservations are left untouched.
        PrepareShipmentForMultiLotPick(WhseShipmentHeader."No.");
        // Kısmi posttan sonra satırın "Qty. to Ship" değeri 0'a düşebiliyor;
        // bu durumda Create Pick raporu "Nothing to handle" der ve belge
        // kilitlenir. Kalan miktarı olan satırlarda sevk miktarını geri aç.
        ReopenQtyToShipForRemainder(WhseShipmentHeader."No.");
        WhseShipmentLine.FindFirst();

        // Microsoft raporu gerçek BC/Warehouse Employee hesabıyla çalışsın;
        // oluşturulan başlığın operasyonel sahibi aşağıda yerel WMS kullanıcısı
        // olarak atomik biçimde damgalanır.
        ReportUserId := CopyStr(UserId(), 1, MaxStrLen(ReportUserId));
        CreatePickReport.SetWhseShipmentLine(WhseShipmentLine, WhseShipmentHeader);
        CreatePickReport.SetHideValidationDialog(true);
        // DoNotFillQtyToHandle = true: "Qty. to Handle" boş başlar; el terminalinde
        // raf/ürün okutulmadan satır tamamlanmış (%100/Done) görünmez.
        CreatePickReport.Initialize(ReportUserId, Enum::"Whse. Activity Sorting Method"::"Shelf or Bin", false, true, false);
        CreatePickReport.UseRequestPage(false);
        if ForcedLpNo <> '' then
            LPPickPreference.ConfigureForcedLp(WhseShipmentHeader."No.", ForcedLpNo)
        else
            LPPickPreference.Configure(WhseShipmentHeader."No.");
        BindSubscription(LPPickPreference);
        // Rapor hata verse bile abonelik MUTLAKA çözülmeli; aksi hâlde bir
        // sonraki toplama yanlış paletle üretilir. ClearLastError + rethrow
        // deseni UnbindSubscription'ı garantiler.
        ClearLastError();
        if not TryRunCreatePick(CreatePickReport) then begin
            UnbindSubscription(LPPickPreference);
            Error(GetLastErrorText());
        end;
        UnbindSubscription(LPPickPreference);

        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", WhseShipmentHeader."No.");
        if not WhseActivityLine.FindLast() then
            Error(PickNotCreatedErr, WhseShipmentHeader."No.");
        PickNo := WhseActivityLine."No.";

        LPPickPreference.StampPickLines(PickNo);
        EnsurePickAssignedTo(PickNo, AssignToUserId);

        StampShipmentLotsOnPick(WhseShipmentHeader."No.", PickNo);
        exit(PickNo);
    end;

    /// <summary>
    /// Kalan miktarı olduğu hâlde "Qty. to Ship" değeri 0'a düşmüş satırlarda
    /// sevk miktarını kalan miktara çeker. Kısmi post sonrası toplama belgesi
    /// üretilemeyip sevkiyatın kilitlenmesini önler.
    /// </summary>
    local procedure ReopenQtyToShipForRemainder(ShipmentNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        Location: Record Location;
        Remaining: Decimal;
    begin
        WhseShipmentLine.SetRange("No.", ShipmentNo);
        if not WhseShipmentLine.FindFirst() then
            exit;
        // Toplama zorunlu lokasyonda "Qty. to Ship" TOPLANAN miktardan türer;
        // elle açmak BC'de "Qty. to Ship must not be greater than 0" hatasına
        // yol açar ve toplama belgesi hiç üretilemez. Orada dokunulmaz.
        if Location.Get(WhseShipmentLine."Location Code") then
            if Location."Require Pick" then
                exit;
        WhseShipmentLine.Reset();
        WhseShipmentLine.SetRange("No.", ShipmentNo);
        WhseShipmentLine.SetRange("Qty. to Ship", 0);
        WhseShipmentLine.SetFilter("Qty. Outstanding", '>0');
        if not WhseShipmentLine.FindSet() then
            exit;
        repeat
            Remaining := WhseShipmentLine."Qty. Outstanding";
            if Remaining > 0 then begin
                WhseShipmentLine.Validate("Qty. to Ship", Remaining);
                WhseShipmentLine.Modify(true);
            end;
        until WhseShipmentLine.Next() = 0;
    end;

    local procedure EnsurePickAssignedTo(PickNo: Code[20]; AssignToUserId: Code[50])
    var
        PickHeader: Record "Warehouse Activity Header";
        ServiceUserId: Code[50];
    begin
        if AssignToUserId = '' then
            exit;
        PickHeader.Get(PickHeader.Type::Pick, PickNo);
        ServiceUserId := CopyStr(UserId(), 1, MaxStrLen(ServiceUserId));
        if (PickHeader."Assigned User ID" <> '') and
           (PickHeader."Assigned User ID" <> AssignToUserId) and
           (PickHeader."Assigned User ID" <> ServiceUserId)
        then
            Error('Ambar toplama %1, %2 kullanıcısına atanmış.', PickNo, PickHeader."Assigned User ID");
        if PickHeader."Assigned User ID" <> AssignToUserId then begin
            PickHeader."Assigned User ID" := CopyStr(AssignToUserId, 1, MaxStrLen(PickHeader."Assigned User ID"));
            PickHeader.Modify(true);
        end;
    end;

    local procedure FindOpenPick(ShipmentNo: Code[20]): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", ShipmentNo);
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."No.");
        exit('');
    end;

    local procedure StampShipmentLotsOnPick(ShipmentNo: Code[20]; PickNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("No.", PickNo);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", ShipmentNo);
        if WhseActivityLine.FindSet(true) then
            repeat
                if WhseShipmentLine.Get(ShipmentNo, WhseActivityLine."Whse. Document Line No.") then begin
                    // Never copy a source reservation lot over BC's generated
                    // multi-lot pick lines. Only an explicit mobile override
                    // may fill a still-empty activity line.
                    if (WhseActivityLine."Lot No." = '') and
                       (WhseShipmentLine."DOPSWHS Lot No." <> '')
                    then begin
                        WhseActivityLine.Validate("Lot No.", WhseShipmentLine."DOPSWHS Lot No.");
                        WhseActivityLine.Modify(true);
                    end;
                end;
            until WhseActivityLine.Next() = 0;
    end;

    local procedure PrepareShipmentForMultiLotPick(ShipmentNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
    begin
        WhseShipmentLine.SetRange("No.", ShipmentNo);
        WhseShipmentLine.SetFilter("Qty. Outstanding", '>0');
        if WhseShipmentLine.FindSet(true) then
            repeat
                if ShipmentLineRequiresLot(WhseShipmentLine) then begin
                    WhseItemTrackingLine.Reset();
                    WhseItemTrackingLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
                    WhseItemTrackingLine.SetRange("Source ID", WhseShipmentLine."No.");
                    WhseItemTrackingLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
                    // Kısmen işlenmiş (kayıtlı toplamadan gelen) izleme satırları BC
                    // tarafından silinemez ("Quantity Handled (Base) must be 0");
                    // böyle bir satırda mevcut lot dağılımı korunur, Create Pick
                    // kalan miktarı bu dağılımla toplar.
                    WhseItemTrackingLine.SetFilter("Quantity Handled (Base)", '<>0');
                    if WhseItemTrackingLine.IsEmpty() then begin
                        WhseItemTrackingLine.SetRange("Quantity Handled (Base)");
                        if not WhseItemTrackingLine.IsEmpty() then
                            WhseItemTrackingLine.DeleteAll(true);

                        if WhseShipmentLine."DOPSWHS Lot No." <> '' then begin
                            Clear(WhseShipmentLine."DOPSWHS Lot No.");
                            WhseShipmentLine.Modify(true);
                        end;
                    end;
                    // İşlenmiş izleme satırı olsun olmasın, KALAN miktar için lot
                    // dağılımı tamamlanır. Eskiden kısmen postlanmış bir sevkiyatta
                    // bu adım tümüyle atlanıyordu: geriye yalnız tamamen işlenmiş
                    // izleme satırı kalıyor, Create Pick "Nothing to handle" deyip
                    // belge kilitleniyordu (kalan 50 KG hiç toplanamıyordu).
                    CreateAutomaticMultiLotTracking(WhseShipmentLine);
                end;
            until WhseShipmentLine.Next() = 0;
    end;

    /// <summary>Sevk satırındaki henüz işlenmemiş ambar izleme miktarı (taban).</summary>
    local procedure OpenTrackingQtyBase(WhseShipmentLine: Record "Warehouse Shipment Line"): Decimal
    var
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        OpenQtyBase: Decimal;
    begin
        WhseItemTrackingLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        WhseItemTrackingLine.SetRange("Source ID", WhseShipmentLine."No.");
        WhseItemTrackingLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        if WhseItemTrackingLine.FindSet() then
            repeat
                OpenQtyBase +=
                    WhseItemTrackingLine."Quantity (Base)" - WhseItemTrackingLine."Quantity Handled (Base)";
            until WhseItemTrackingLine.Next() = 0;
        if OpenQtyBase < 0 then
            exit(0);
        exit(OpenQtyBase);
    end;

    local procedure CreateAutomaticMultiLotTracking(WhseShipmentLine: Record "Warehouse Shipment Line")
    var
        WarehouseEntry: Record "Warehouse Entry";
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        LotQtyByNo: Dictionary of [Code[50], Decimal];
        LotNos: List of [Code[50]];
        LotNo: Code[50];
        ExistingQtyBase: Decimal;
        AllocateQtyBase: Decimal;
        RemainingQtyBase: Decimal;
        EntryNo: Integer;
    begin
        WhseShipmentLine.CalcFields("Pick Qty. (Base)");
        RemainingQtyBase :=
            WhseShipmentLine."Qty. (Base)" -
            (WhseShipmentLine."Qty. Picked (Base)" + WhseShipmentLine."Pick Qty. (Base)");
        // Halihazırda açık (henüz işlenmemiş) izleme satırları kalanı zaten
        // kapatıyorsa yeni satır eklenmez; bu sayede prosedür tekrar tekrar
        // çağrılabilir ve miktar iki kez dağıtılmaz.
        RemainingQtyBase -= OpenTrackingQtyBase(WhseShipmentLine);
        if RemainingQtyBase <= 0 then
            exit;

        // Aggregate the net warehouse stock by lot across bins. Supplying one
        // tracking row per lot makes Microsoft's Create Pick report generate
        // separate Take/Place lines instead of forcing the whole shipment onto
        // the stale single lot copied from the sales document.
        WarehouseEntry.SetRange("Item No.", WhseShipmentLine."Item No.");
        WarehouseEntry.SetRange("Variant Code", WhseShipmentLine."Variant Code");
        WarehouseEntry.SetRange("Location Code", WhseShipmentLine."Location Code");
        WarehouseEntry.SetFilter("Lot No.", '<>%1', '');
        if WarehouseEntry.FindSet() then
            repeat
                LotNo := WarehouseEntry."Lot No.";
                if LotQtyByNo.Get(LotNo, ExistingQtyBase) then
                    LotQtyByNo.Set(LotNo, ExistingQtyBase + WarehouseEntry."Qty. (Base)")
                else begin
                    LotQtyByNo.Add(LotNo, WarehouseEntry."Qty. (Base)");
                    LotNos.Add(LotNo);
                end;
            until WarehouseEntry.Next() = 0;

        EntryNo := WhseItemTrackingLine.GetLastEntryNo();
        foreach LotNo in LotNos do begin
            LotQtyByNo.Get(LotNo, ExistingQtyBase);
            if (ExistingQtyBase > 0) and (RemainingQtyBase > 0) then begin
                AllocateQtyBase := ExistingQtyBase;
                if AllocateQtyBase > RemainingQtyBase then
                    AllocateQtyBase := RemainingQtyBase;

                WhseItemTrackingLine.Init();
                EntryNo += 1;
                WhseItemTrackingLine."Entry No." := EntryNo;
                WhseItemTrackingLine."Item No." := WhseShipmentLine."Item No.";
                WhseItemTrackingLine."Variant Code" := WhseShipmentLine."Variant Code";
                WhseItemTrackingLine."Location Code" := WhseShipmentLine."Location Code";
                WhseItemTrackingLine."Source Type" := Database::"Warehouse Shipment Line";
                WhseItemTrackingLine."Source ID" := WhseShipmentLine."No.";
                WhseItemTrackingLine."Source Ref. No." := WhseShipmentLine."Line No.";
                WhseItemTrackingLine."Qty. per Unit of Measure" := WhseShipmentLine."Qty. per Unit of Measure";
                WhseItemTrackingLine.Validate("Lot No.", LotNo);
                WhseItemTrackingLine.Validate("Quantity (Base)", AllocateQtyBase);
                WhseItemTrackingLine.Insert(true);
                RemainingQtyBase -= AllocateQtyBase;
            end;
        end;
    end;

    procedure PostShipment(var WhseShipmentHeader: Record "Warehouse Shipment Header"; PrintPackingSlip: Boolean; Invoice: Boolean)
    begin
        PostShipment(WhseShipmentHeader, PrintPackingSlip, Invoice, '');
    end;

    procedure PostShipment(var WhseShipmentHeader: Record "Warehouse Shipment Header"; PrintPackingSlip: Boolean; Invoice: Boolean; PrinterId: Code[50])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        PostedWhseShipmentLine: Record "Posted Whse. Shipment Line";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        LineLp: Dictionary of [Integer, Code[20]];
        LineSscc: Dictionary of [Integer, Code[18]];
        LpNo: Code[20];
        Sscc: Code[18];
        LineCount: Integer;
        LpCount: Integer;
        PostedNo: Code[20];
        WhseShipmentNo: Code[20];
    begin
        // Whse.-Post Shipment may clear the record variable passed to Run.
        // Keep the durable source number before posting; every post-processing
        // lookup must use this value, never the potentially cleared record.
        WhseShipmentNo := WhseShipmentHeader."No.";
        // Ambar sevkiyat başlığındaki acente, kaynak satış siparişinde boşsa
        // oraya taşınır (BADE Sales-Post öncesi acente kodunu zorunlu tutar).
        PropagateShippingAgentToSource(WhseShipmentNo, WhseShipmentHeader."Shipping Agent Code", WhseShipmentHeader."Shipping Agent Service Code", false);
        if PrintPackingSlip then begin
            EnsureShipmentReportConfigured();
            PrintDispatcher.EnsureDocumentPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::PostedShipment);
        end;
        // Mobile-friendly: auto-release if the shipment is still Open (e.g. a Qty. to Ship edit
        // reopened it), so the operator doesn't have to re-release in BC before posting.
        if WhseShipmentHeader.Status <> WhseShipmentHeader.Status::Released then begin
            WhseShipmentRelease.Release(WhseShipmentHeader);
            WhseShipmentHeader.Get(WhseShipmentHeader."No.");
        end;
        WhseShipmentHeader.TestField(Status, WhseShipmentHeader.Status::Released);
        // Lot dağılımı mutabakatı SERBEST BIRAKMADAN SONRA yapılmalı: BC'nin
        // release adımı "Qty. to Ship" değerini yeniden hesaplar (InitQtyToShip),
        // önce mutabakat yapılırsa release bunu geri alıyor ve post "lot dağılımı
        // (49) sevk miktarıyla (59) uyuşmuyor" hatasıyla düşüyordu.
        EnsureRequiredShipmentLots(WhseShipmentNo);

        WhseShipmentLine.SetRange("No.", WhseShipmentNo);
        if WhseShipmentLine.FindSet(true) then
            repeat
                LineCount += 1;
                if WhseShipmentLine."LP No." <> '' then begin
                    LpNo := WhseShipmentLine."LP No.";
                    EnsureLpSscc(LpNo, Sscc);
                    WhseShipmentLine.SSCC := Sscc;
                    WhseShipmentLine.Modify(true);
                    LineLp.Set(WhseShipmentLine."Line No.", LpNo);
                    LineSscc.Set(WhseShipmentLine."Line No.", Sscc);
                end;
            until WhseShipmentLine.Next() = 0;

        EnsureAssignedShipmentLpsHaveSscc(WhseShipmentNo, LpCount);

        if WhseShipmentLine.FindFirst() then
            WhsePostShipment.Run(WhseShipmentLine);

        PostedWhseShipmentHeader.SetRange("Whse. Shipment No.", WhseShipmentNo);
        if PostedWhseShipmentHeader.FindLast() then
            PostedNo := PostedWhseShipmentHeader."No.";

        PostedWhseShipmentLine.SetRange("Whse. Shipment No.", WhseShipmentNo);
        if PostedWhseShipmentLine.FindSet(true) then
            repeat
                if LineLp.Get(PostedWhseShipmentLine."Whse Shipment Line No.", LpNo) then begin
                    LineSscc.Get(PostedWhseShipmentLine."Whse Shipment Line No.", Sscc);
                    PostedWhseShipmentLine."LP No." := LpNo;
                    PostedWhseShipmentLine.SSCC := Sscc;
                    PostedWhseShipmentLine.Modify(true);
                end;
            until PostedWhseShipmentLine.Next() = 0;

        // At this point the durable posted warehouse lines contain the exact
        // LP selected by the operator. Reconcile through BC's exact posted-line
        // to item-ledger relation before returning to the terminal.
        if PostedNo <> '' then
            LpPropagation.ReconcilePostedWarehouseShipment(PostedNo);

        StampHeaders(WhseShipmentNo, PostedNo);

        if PrintPackingSlip then begin
            ClearLastError();
            if not QueuePostedShipmentPrint(PostedNo, PrinterId) then
                Telemetry.LogWarning(
                    'Print.ShipmentFailed',
                    CopyStr(StrSubstNo('Shipment %1 posted, but its print job could not be queued: %2', PostedNo, GetLastErrorText()), 1, 250),
                    WhseShipmentHeader."Assigned User ID");
        end;

        LogShipmentPosted(WhseShipmentNo, LineCount, LpCount + LineLp.Count());
    end;

    /// <summary>
    /// Sevkiyat satırındaki ürünün lot takipli olup olmadığını döndürür.
    /// Mobil uygulama alan etiketini ve Onayla butonunu bu bilgiyle yönetir;
    /// asıl zorunluluk Confirm/Post içinde sunucu tarafında da uygulanır.
    /// </summary>
    procedure ShipmentLineRequiresLot(WhseShipmentLine: Record "Warehouse Shipment Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not Item.Get(WhseShipmentLine."Item No.") then
            exit(false);
        if Item."Item Tracking Code" = '' then
            exit(false);
        if not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit(false);
        exit(
            ItemTrackingCode."Lot Specific Tracking" or
            ItemTrackingCode."Lot Warehouse Tracking" or
            ItemTrackingCode."Lot Sales Outbound Tracking");
    end;

    local procedure SetSourceReservationFilters(var ReservationEntry: Record "Reservation Entry"; WhseShipmentLine: Record "Warehouse Shipment Line")
    begin
        ReservationEntry.SetRange("Source Type", WhseShipmentLine."Source Type");
        ReservationEntry.SetRange("Source Subtype", WhseShipmentLine."Source Subtype");
        ReservationEntry.SetRange("Source ID", WhseShipmentLine."Source No.");
        ReservationEntry.SetRange("Source Ref. No.", WhseShipmentLine."Source Line No.");
        ReservationEntry.SetRange("Item No.", WhseShipmentLine."Item No.");
        ReservationEntry.SetRange("Variant Code", WhseShipmentLine."Variant Code");
    end;

    local procedure UniqueReservationLot(var ReservationEntry: Record "Reservation Entry"; var LotNo: Code[50]): Boolean
    begin
        Clear(LotNo);
        if ReservationEntry.FindSet() then
            repeat
                if LotNo = '' then
                    LotNo := ReservationEntry."Lot No."
                else
                    if LotNo <> ReservationEntry."Lot No." then begin
                        Clear(LotNo);
                        exit(false);
                    end;
            until ReservationEntry.Next() = 0;
        exit(LotNo <> '');
    end;

    local procedure UniqueWarehouseTrackingLot(var WhseItemTrackingLine: Record "Whse. Item Tracking Line"; var LotNo: Code[50]): Boolean
    begin
        Clear(LotNo);
        if WhseItemTrackingLine.FindSet() then
            repeat
                if LotNo = '' then
                    LotNo := WhseItemTrackingLine."Lot No."
                else
                    if LotNo <> WhseItemTrackingLine."Lot No." then begin
                        Clear(LotNo);
                        exit(false);
                    end;
            until WhseItemTrackingLine.Next() = 0;
        exit(LotNo <> '');
    end;

    /// <summary>
    /// Terminalin "kaynak paleti seç" ekranına aday palet listesini JSON dizi
    /// metni olarak döndürür. Aday: sevkiyat lokasyonundaki AKTİF (Open/Built/
    /// Assigned, başka belgeye atanmamış) ve sevkiyatın açık satırlarındaki
    /// ürünü — satır lot sabitliyorsa o lotu — bulunduran paletler.
    /// Sıralama: önce talebi tek başına karşılayanlar, sonra kullanılabilir
    /// miktar (azalan), sonra LP No. Aday yoksa boş dizi döner; ASLA hata
    /// vermez.
    /// </summary>
    procedure ListPickSourceOptions(WhseShipmentHeader: Record "Warehouse Shipment Header"): Text
    var
        TempOption: Record "DOPSWHS LP Line" temporary;
        Item: Record Item;
        Options: JsonArray;
        Option: JsonObject;
        Result: Text;
    begin
        CollectPickSourceOptions(WhseShipmentHeader, TempOption);

        // Sıralama alanları geçici kayda gömüldü: "Line Weight kg" = 0/1
        // (talebi karşılayan önce), "Source Document Quantity" = kullanılabilir
        // miktar. Azalan sıralama için negatiflenip anahtar üzerinden okunur.
        TempOption.Reset();
        TempOption.SetCurrentKey("Line Weight kg", "Source Document Quantity", "LP No.");
        TempOption.Ascending(true);
        if TempOption.FindSet() then
            repeat
                Clear(Option);
                Option.Add('lpNo', TempOption."LP No.");
                Option.Add('binCode', TempOption."Source Bin Code");
                Option.Add('itemNo', TempOption."Item No.");
                if Item.Get(TempOption."Item No.") then
                    Option.Add('itemDescription', Item.Description)
                else
                    Option.Add('itemDescription', '');
                Option.Add('lotNo', TempOption."Lot No.");
                Option.Add('availableQtyBase', -TempOption."Source Document Quantity");
                Option.Add('uom', TempOption."Unit of Measure");
                Option.Add('coversFullDemand', TempOption."Line Weight kg" = 0);
                Options.Add(Option);
            until TempOption.Next() = 0;

        Options.WriteTo(Result);
        exit(Result);
    end;

    local procedure CollectPickSourceOptions(WhseShipmentHeader: Record "Warehouse Shipment Header"; var TempOption: Record "DOPSWHS LP Line" temporary)
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        DemandByKey: Dictionary of [Text, Decimal];
        DemandKey: Text;
        RequiredQtyBase: Decimal;
        AvailableQtyBase: Decimal;
        EntryNo: Integer;
    begin
        TempOption.Reset();
        TempOption.DeleteAll();
        if WhseShipmentHeader."Location Code" = '' then
            exit;

        // Ürün+varyant başına açık talep (taban) — coversFullDemand için.
        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        WhseShipmentLine.SetFilter("Qty. Outstanding (Base)", '>0');
        if not WhseShipmentLine.FindSet() then
            exit;
        repeat
            DemandKey := WhseShipmentLine."Item No." + '|' + WhseShipmentLine."Variant Code";
            if DemandByKey.Get(DemandKey, RequiredQtyBase) then
                DemandByKey.Set(DemandKey, RequiredQtyBase + WhseShipmentLine."Qty. Outstanding (Base)")
            else
                DemandByKey.Add(DemandKey, WhseShipmentLine."Qty. Outstanding (Base)");
        until WhseShipmentLine.Next() = 0;

        LP.SetRange("Location Code", WhseShipmentHeader."Location Code");
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        LP.SetFilter("Bin Code", '<>%1', '');
        if not LP.FindSet() then
            exit;
        repeat
            // Başka bir belgeye ayrılmış palet operatöre teklif edilmez.
            if (LP."Assigned Document No." = '') or (LP."Assigned Document No." = WhseShipmentHeader."No.") then begin
                WhseShipmentLine.Reset();
                WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
                WhseShipmentLine.SetFilter("Qty. Outstanding (Base)", '>0');
                if WhseShipmentLine.FindSet() then
                    repeat
                        LPLine.Reset();
                        LPLine.SetRange("LP No.", LP."No.");
                        LPLine.SetRange("Item No.", WhseShipmentLine."Item No.");
                        LPLine.SetRange("Variant Code", WhseShipmentLine."Variant Code");
                        if WhseShipmentLine."DOPSWHS Lot No." <> '' then
                            LPLine.SetRange("Lot No.", WhseShipmentLine."DOPSWHS Lot No.");
                        LPLine.SetFilter(Quantity, '>0');
                        if LPLine.FindSet() then
                            repeat
                                if not OptionAlreadyListed(TempOption, LP."No.", LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.") then begin
                                    AvailableQtyBase :=
                                        LpLineAvailableQtyBase(LP, LPLine, WhseShipmentHeader."Location Code");
                                    if AvailableQtyBase > 0 then begin
                                        DemandByKey.Get(
                                            LPLine."Item No." + '|' + LPLine."Variant Code", RequiredQtyBase);
                                        EntryNo += 1;
                                        TempOption.Init();
                                        TempOption."LP No." := LP."No.";
                                        TempOption."Line No." := EntryNo;
                                        TempOption."Item No." := LPLine."Item No.";
                                        TempOption."Variant Code" := LPLine."Variant Code";
                                        TempOption."Lot No." := LPLine."Lot No.";
                                        TempOption."Unit of Measure" := LPLine."Unit of Measure";
                                        TempOption."Source Bin Code" := LP."Bin Code";
                                        // Sıralama taşıyıcıları (bkz. ListPickSourceOptions).
                                        TempOption."Source Document Quantity" := -AvailableQtyBase;
                                        if (RequiredQtyBase > 0) and (AvailableQtyBase >= RequiredQtyBase) then
                                            TempOption."Line Weight kg" := 0
                                        else
                                            TempOption."Line Weight kg" := 1;
                                        TempOption.Insert();
                                    end;
                                end;
                            until LPLine.Next() = 0;
                    until WhseShipmentLine.Next() = 0;
            end;
        until LP.Next() = 0;
    end;

    local procedure OptionAlreadyListed(var TempOption: Record "DOPSWHS LP Line" temporary; LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]): Boolean
    var
        Existing: Record "DOPSWHS LP Line" temporary;
    begin
        Existing.Copy(TempOption, true);
        Existing.Reset();
        Existing.SetRange("LP No.", LpNo);
        Existing.SetRange("Item No.", ItemNo);
        Existing.SetRange("Variant Code", VariantCode);
        Existing.SetRange("Lot No.", LotNo);
        exit(not Existing.IsEmpty());
    end;

    /// <summary>
    /// Paletin bu ürün/lot için fiilen toplanabilir taban miktarı: palet
    /// satırının taban miktarı ile rafın CalcQtyAvailToPick değerinin küçüğü
    /// (BuildPreferredBinFilter ile aynı ölçüt).
    /// </summary>
    local procedure LpLineAvailableQtyBase(LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line"; LocationCode: Code[10]): Decimal
    var
        BinContent: Record "Bin Content";
        Item: Record Item;
        ItemUOM: Record "Item Unit of Measure";
        QtyPerUOM: Decimal;
        LpQtyBase: Decimal;
        BinAvailableQtyBase: Decimal;
    begin
        if not Item.Get(LPLine."Item No.") then
            exit(0);
        QtyPerUOM := 1;
        if (LPLine."Unit of Measure" <> '') and (LPLine."Unit of Measure" <> Item."Base Unit of Measure") then
            if ItemUOM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                QtyPerUOM := ItemUOM."Qty. per Unit of Measure"
            else
                exit(0);
        LpQtyBase := LPLine.Quantity * QtyPerUOM;
        if LpQtyBase <= 0 then
            exit(0);

        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", LP."Bin Code");
        BinContent.SetRange("Item No.", LPLine."Item No.");
        BinContent.SetRange("Variant Code", LPLine."Variant Code");
        if BinContent.FindSet() then
            repeat
                BinAvailableQtyBase += BinContent.CalcQtyAvailToPick(0);
            until BinContent.Next() = 0;
        if BinAvailableQtyBase <= 0 then
            exit(0);
        if LpQtyBase < BinAvailableQtyBase then
            exit(LpQtyBase);
        exit(BinAvailableQtyBase);
    end;

    /// <summary>Terminal için sevkiyat acentesi listesi: JSON [{code,name}].</summary>
    procedure ListShippingAgents(): Text
    var
        ShippingAgent: Record "Shipping Agent";
        Agents: JsonArray;
        Agent: JsonObject;
        Result: Text;
    begin
        if ShippingAgent.FindSet() then
            repeat
                Clear(Agent);
                Agent.Add('code', ShippingAgent.Code);
                Agent.Add('name', ShippingAgent.Name);
                Agents.Add(Agent);
            until ShippingAgent.Next() = 0;
        Agents.WriteTo(Result);
        exit(Result);
    end;

    /// <summary>
    /// Sevkiyat acentesini ambar sevkiyat başlığına ve kaynak satış
    /// siparişlerine yazar. NEDEN: BADE, Sales-Post öncesi satış siparişinde
    /// acente kodunu zorunlu tutuyor ("Sevkiyat Acente Kodu zorunludur");
    /// terminalden sevk edilen belgede ofis bu alanı doldurmamış olabiliyor.
    /// Serbest bırakılmış siparişte Validate durum kontrolüne takılabileceği
    /// için satış başlığında alan doğrudan yazılır.
    /// </summary>
    procedure SetShippingAgent(var WhseShipmentHeader: Record "Warehouse Shipment Header"; AgentCode: Code[10]; ServiceCode: Code[10])
    var
        ShippingAgent: Record "Shipping Agent";
    begin
        if AgentCode = '' then
            Error(ShippingAgentRequiredErr);
        if not ShippingAgent.Get(AgentCode) then
            Error(ShippingAgentNotFoundErr, AgentCode);
        if WhseShipmentHeader."Shipping Agent Code" <> AgentCode then begin
            WhseShipmentHeader.Validate("Shipping Agent Code", AgentCode);
            WhseShipmentHeader.Modify(true);
        end;
        if (ServiceCode <> '') and (WhseShipmentHeader."Shipping Agent Service Code" <> ServiceCode) then begin
            WhseShipmentHeader.Validate("Shipping Agent Service Code", ServiceCode);
            WhseShipmentHeader.Modify(true);
        end;
        PropagateShippingAgentToSource(WhseShipmentHeader."No.", AgentCode, ServiceCode, true);
    end;

    local procedure PropagateShippingAgentToSource(WhseShipmentNo: Code[20]; AgentCode: Code[10]; ServiceCode: Code[10]; Overwrite: Boolean)
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        SalesHeader: Record "Sales Header";
        Done: List of [Code[20]];
    begin
        if AgentCode = '' then
            exit;
        WhseShipmentLine.SetRange("No.", WhseShipmentNo);
        WhseShipmentLine.SetRange("Source Type", Database::"Sales Line");
        if WhseShipmentLine.FindSet() then
            repeat
                if not Done.Contains(WhseShipmentLine."Source No.") then begin
                    Done.Add(WhseShipmentLine."Source No.");
                    if SalesHeader.Get(SalesHeader."Document Type"::Order, WhseShipmentLine."Source No.") then
                        if (SalesHeader."Shipping Agent Code" = '') or (Overwrite and (SalesHeader."Shipping Agent Code" <> AgentCode)) then begin
                            SalesHeader."Shipping Agent Code" := AgentCode;
                            if ServiceCode <> '' then
                                SalesHeader."Shipping Agent Service Code" := ServiceCode;
                            SalesHeader.Modify(true);
                        end;
                end;
            until WhseShipmentLine.Next() = 0;
    end;

    local procedure EnsureRequiredShipmentLots(ShipmentNo: Code[20])
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LotNo: Code[50];
    begin
        WhseShipmentLine.SetRange("No.", ShipmentNo);
        WhseShipmentLine.SetFilter("Qty. to Ship", '>0');
        if WhseShipmentLine.FindSet() then
            repeat
                // Kayıtlı toplama varsa önce sevk miktarı toplanan miktara
                // çekilir. ESKİDEN burada bitiyordu; lot izleme kaydı hiç
                // yazılmadığı için post "You must assign a lot number" ile
                // düşüyordu. Artık her iki adım da çalışır (UAT D-01/D-03).
                if HasRegisteredPickToShip(WhseShipmentLine) then begin
                    // Kayıtlı toplama lot/raf dağılımının TEK doğru kaynağıdır.
                    // Buraya ek lot satırı yazmak, toplamanın yazdığı dağılımın
                    // üstüne binip "izleme miktarı 130 olmalı 20" hatası üretir.
                    ReconcileQtyToShipWithRegisteredPick(WhseShipmentLine);
                    if not WhseShipmentLine.Get(WhseShipmentLine."No.", WhseShipmentLine."Line No.") then
                        exit;
                    EnsureShipmentHasCompleteLotTracking(WhseShipmentLine);
                end else begin
                    GetShipmentLineLot(WhseShipmentLine, LotNo);
                    if LotNo <> '' then
                        EnsureShipmentLot(WhseShipmentLine, LotNo)
                    else
                        EnsureShipmentHasCompleteLotTracking(WhseShipmentLine);
                end;
            until WhseShipmentLine.Next() = 0;
    end;

    local procedure HasRegisteredPickToShip(WhseShipmentLine: Record "Warehouse Shipment Line"): Boolean
    begin
        exit(
            (WhseShipmentLine."Qty. Picked (Base)" - WhseShipmentLine."Qty. Shipped (Base)") > 0);
    end;

    local procedure ReconcileQtyToShipWithRegisteredPick(var WhseShipmentLine: Record "Warehouse Shipment Line")
    var
        PickedNotShippedBase: Decimal;
        PickedNotShipped: Decimal;
    begin
        PickedNotShippedBase :=
            WhseShipmentLine."Qty. Picked (Base)" - WhseShipmentLine."Qty. Shipped (Base)";
        if (PickedNotShippedBase <= 0) or
           (Abs(WhseShipmentLine."Qty. to Ship (Base)") <= Abs(PickedNotShippedBase))
        then
            exit;

        WhseShipmentLine.TestField("Qty. per Unit of Measure");
        PickedNotShipped := Round(
            PickedNotShippedBase / WhseShipmentLine."Qty. per Unit of Measure");
        WhseShipmentLine.Validate("Qty. to Ship", PickedNotShipped);
        WhseShipmentLine.Modify(true);
    end;

    /// <summary>Sevk satırındaki toplam lotlu izleme miktarı (taban).</summary>
    local procedure TrackedQtyBaseFor(WhseShipmentLine: Record "Warehouse Shipment Line"): Decimal
    var
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        Toplam: Decimal;
    begin
        WhseItemTrackingLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        WhseItemTrackingLine.SetRange("Source ID", WhseShipmentLine."No.");
        WhseItemTrackingLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        WhseItemTrackingLine.SetFilter("Lot No.", '<>%1', '');
        if WhseItemTrackingLine.FindSet() then
            repeat
                Toplam += Abs(WhseItemTrackingLine."Quantity (Base)");
            until WhseItemTrackingLine.Next() = 0;
        exit(Toplam);
    end;

    local procedure EnsureShipmentHasCompleteLotTracking(WhseShipmentLine: Record "Warehouse Shipment Line")
    var
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        TrackedQtyBase: Decimal;
    begin
        if (WhseShipmentLine."Qty. to Ship" <= 0) or (not ShipmentLineRequiresLot(WhseShipmentLine)) then
            exit;

        WhseItemTrackingLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        WhseItemTrackingLine.SetRange("Source ID", WhseShipmentLine."No.");
        WhseItemTrackingLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        WhseItemTrackingLine.SetRange("Item No.", WhseShipmentLine."Item No.");
        WhseItemTrackingLine.SetRange("Variant Code", WhseShipmentLine."Variant Code");
        WhseItemTrackingLine.SetFilter("Lot No.", '<>%1', '');
        if WhseItemTrackingLine.FindSet() then
            repeat
                TrackedQtyBase += Abs(WhseItemTrackingLine."Quantity (Base)");
            until WhseItemTrackingLine.Next() = 0;

        if TrackedQtyBase < Abs(WhseShipmentLine."Qty. to Ship (Base)") then
            Error(
                '%1 ürününün %2 sevkiyat satırı birden fazla lot içeriyor ancak lot dağılımı eksik. Lotlanan (temel): %3, sevk edilecek (temel): %4. Önce ambar toplamayı tamamlayın.',
                WhseShipmentLine."Item No.",
                WhseShipmentLine."Line No.",
                TrackedQtyBase,
                Abs(WhseShipmentLine."Qty. to Ship (Base)"));
    end;

    local procedure EnsureShipmentLot(WhseShipmentLine: Record "Warehouse Shipment Line"; LotNo: Code[50])
    var
        WarehouseEntry: Record "Warehouse Entry";
        AvailableQtyBase: Decimal;
    begin
        if (WhseShipmentLine."Qty. to Ship" <= 0) or (not ShipmentLineRequiresLot(WhseShipmentLine)) then
            exit;

        if LotNo = '' then
            Error(
                '%1 ürününün %2 sevkiyat satırında lot numarası zorunludur. Stoktaki lotlardan birini seçin.',
                WhseShipmentLine."Item No.", WhseShipmentLine."Line No.");

        WarehouseEntry.SetCurrentKey(
            "Item No.", "Bin Code", "Location Code", "Variant Code",
            "Unit of Measure Code", "Lot No.");
        WarehouseEntry.SetRange("Item No.", WhseShipmentLine."Item No.");
        WarehouseEntry.SetRange("Variant Code", WhseShipmentLine."Variant Code");
        WarehouseEntry.SetRange("Location Code", WhseShipmentLine."Location Code");
        WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.CalcSums("Qty. (Base)");
        AvailableQtyBase := WarehouseEntry."Qty. (Base)";

        if AvailableQtyBase < WhseShipmentLine."Qty. to Ship (Base)" then
            Error(
                '%1 lotunda %2 lokasyonunda yeterli stok yok. Mevcut (temel): %3, sevk edilecek (temel): %4.',
                LotNo,
                WhseShipmentLine."Location Code",
                AvailableQtyBase,
                WhseShipmentLine."Qty. to Ship (Base)");

        // Lot yalnız DOĞRULANIYORDU; ambar izleme kaydına hiç yazılmıyordu ve
        // BC postu "You must assign a lot number" ile reddediyordu. Seçilen lot
        // sevk miktarı kadar izleme satırına yazılır (UAT D-01/D-03).
        WriteShipmentLotTracking(WhseShipmentLine, LotNo);
    end;

    /// <summary>
    /// Sevk satırı için tek lotluk ambar izleme kaydını oluşturur/günceller.
    /// İşlenmiş (kayıtlı toplamadan gelen) satırlara dokunulmaz.
    /// </summary>
    local procedure WriteShipmentLotTracking(WhseShipmentLine: Record "Warehouse Shipment Line"; LotNo: Code[50])
    var
        WhseItemTrackingLine: Record "Whse. Item Tracking Line";
        OpenLine: Record "Whse. Item Tracking Line";
        EntryNo: Integer;
        NeededQtyBase: Decimal;
    begin
        NeededQtyBase := WhseShipmentLine."Qty. to Ship (Base)";
        if NeededQtyBase <= 0 then
            exit;
        // Satırda sevk miktarını zaten karşılayan izleme varsa dokunma.
        if TrackedQtyBaseFor(WhseShipmentLine) >= NeededQtyBase then
            exit;

        OpenLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        OpenLine.SetRange("Source ID", WhseShipmentLine."No.");
        OpenLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        OpenLine.SetRange("Lot No.", LotNo);
        OpenLine.SetFilter("Quantity Handled (Base)", '%1', 0);
        if OpenLine.FindFirst() then begin
            if OpenLine."Quantity (Base)" <> NeededQtyBase then begin
                OpenLine.Validate("Quantity (Base)", NeededQtyBase);
                OpenLine.Modify(true);
            end;
            exit;
        end;

        // Aynı satırda başka lota ait, henüz işlenmemiş satır varsa temizlenir:
        // operatörün seçtiği lot geçerlidir.
        OpenLine.Reset();
        OpenLine.SetRange("Source Type", Database::"Warehouse Shipment Line");
        OpenLine.SetRange("Source ID", WhseShipmentLine."No.");
        OpenLine.SetRange("Source Ref. No.", WhseShipmentLine."Line No.");
        OpenLine.SetFilter("Quantity Handled (Base)", '%1', 0);
        if not OpenLine.IsEmpty() then
            OpenLine.DeleteAll(true);

        EntryNo := WhseItemTrackingLine.GetLastEntryNo();
        WhseItemTrackingLine.Init();
        WhseItemTrackingLine."Entry No." := EntryNo + 1;
        WhseItemTrackingLine."Item No." := WhseShipmentLine."Item No.";
        WhseItemTrackingLine."Variant Code" := WhseShipmentLine."Variant Code";
        WhseItemTrackingLine."Location Code" := WhseShipmentLine."Location Code";
        WhseItemTrackingLine."Source Type" := Database::"Warehouse Shipment Line";
        WhseItemTrackingLine."Source ID" := WhseShipmentLine."No.";
        WhseItemTrackingLine."Source Ref. No." := WhseShipmentLine."Line No.";
        WhseItemTrackingLine."Qty. per Unit of Measure" := WhseShipmentLine."Qty. per Unit of Measure";
        WhseItemTrackingLine.Validate("Lot No.", LotNo);
        WhseItemTrackingLine.Validate("Quantity (Base)", NeededQtyBase);
        WhseItemTrackingLine.Insert(true);
    end;

    local procedure StampHeaders(WhseShipmentNo: Code[20]; PostedShipmentNo: Code[20])
    var
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
    begin
        LpPropagation.StampShipmentHeader(WhseShipmentNo);
        LpPropagation.StampPostedShipmentHeader(WhseShipmentNo, PostedShipmentNo);
    end;

    procedure PostSalesOrderShipAndInvoice(var SalesHeader: Record "Sales Header")
    var
        SalesPost: Codeunit "Sales-Post";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        SalesHeader.TestField("Document Type", SalesHeader."Document Type"::Order);
        OnBeforeShipSales(SalesHeader."No.");
        SalesHeader.Ship := true;
        SalesHeader.Invoice := true;
        SalesPost.Run(SalesHeader);
        OnAfterInvoiceSales(SalesHeader."No.");
        CustomDimensions.Add('docNo', SalesHeader."No.");
        Session.LogMessage('AdvWMS.Sales.ShipAndInvoice', StrSubstNo('Sales order %1 shipped and invoiced from mobile.', SalesHeader."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    procedure PostTransferShip(var TransferHeader: Record "Transfer Header")
    var
        TransferPostShipment: Codeunit "TransferOrder-Post Shipment";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        TransferPostShipment.Run(TransferHeader);
        CustomDimensions.Add('docNo', TransferHeader."No.");
        Session.LogMessage('AdvWMS.Transfer.Shipped', StrSubstNo('Transfer order %1 shipped from mobile.', TransferHeader."No."), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    local procedure EnsureLpSscc(LpNo: Code[20]; var Sscc: Code[18])
    var
        LP: Record "DOPSWHS LP Header";
        Generator: Codeunit "DOPSWHS SSCC Generator";
    begin
        LP.Get(LpNo);
        if LP.SSCC = '' then begin
            LP.SSCC := Generator.Generate();
            LP.Modify(true);
        end;
        Sscc := LP.SSCC;
    end;

    local procedure EnsureAssignedShipmentLpsHaveSscc(ShipmentNo: Code[20]; var LpCount: Integer)
    var
        LP: Record "DOPSWHS LP Header";
        Sscc: Code[18];
    begin
        LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::WhseShipment);
        LP.SetRange("Assigned Document No.", ShipmentNo);
        if LP.FindSet(true) then
            repeat
                LpCount += 1;
                EnsureLpSscc(LP."No.", Sscc);
            until LP.Next() = 0;
    end;

    [TryFunction]
    local procedure QueuePostedShipmentPrint(PostedShipmentNo: Code[20]; PrinterId: Code[50])
    var
        PostedShipment: Record "Posted Whse. Shipment Header";
        ReportSelection: Record "DOPSWHS IWX Report Selection";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceRecord: RecordRef;
    begin
        if PostedShipmentNo = '' then
            Error('The posted warehouse shipment could not be found for printing.');
        ReportSelection.SetCurrentKey(Usage, Sequence);
        ReportSelection.SetRange(Usage, ReportSelection.Usage::PostedShipment);
        ReportSelection.SetFilter("Report ID", '<>0');
        if not ReportSelection.FindFirst() then
            Error('No report is configured for Posted Shipment printing.');
        PostedShipment.Get(PostedShipmentNo);
        PostedShipment.SetRecFilter();
        SourceRecord.GetTable(PostedShipment);
        PrintDispatcher.PrintReport(PostedShipmentNo, ReportSelection."Report ID", PrinterId, 1, ReportSelection.Usage, SourceRecord);
    end;

    local procedure EnsureShipmentReportConfigured()
    var
        ReportSelection: Record "DOPSWHS IWX Report Selection";
    begin
        ReportSelection.SetCurrentKey(Usage, Sequence);
        ReportSelection.SetRange(Usage, ReportSelection.Usage::PostedShipment);
        ReportSelection.SetFilter("Report ID", '<>0');
        if not ReportSelection.FindFirst() then
            Error('No report is configured for Posted Shipment printing.');
    end;

    local procedure LogShipmentPosted(DocNo: Code[20]; LineCount: Integer; LpCount: Integer)
    var
        CustomDimensions: Dictionary of [Text, Text];
    begin
        CustomDimensions.Add('docNo', DocNo);
        CustomDimensions.Add('lineCount', Format(LineCount));
        CustomDimensions.Add('lpCount', Format(LpCount));
        Session.LogMessage('AdvWMS.Shipment.Posted', StrSubstNo('Warehouse shipment %1 posted from mobile.', DocNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    var
        NoShipmentLinesErr: Label 'Warehouse shipment %1 has no lines.', Comment = '%1 = Warehouse Shipment No.';
        ShippingAgentRequiredErr: Label 'Sevkiyat acentesi seçin.';
        ShippingAgentNotFoundErr: Label '%1 sevkiyat acentesi bulunamadı.', Comment = '%1 agent code';
        PickNotCreatedErr: Label 'No warehouse pick was created for shipment %1. Check bin content and available quantity.', Comment = '%1 = Warehouse Shipment No.';
        LpNotFoundErr: Label '%1 numaralı taşıma kabı (LP) bulunamadı. Listeyi yenileyin.', Comment = '%1 = LP No.';
        LpNotActiveErr: Label '%1 numaralı taşıma kabı toplamaya uygun değil. Durumu: %2.', Comment = '%1 = LP No., %2 = status';
        LpAssignedElsewhereErr: Label '%1 numaralı taşıma kabı %2 belgesine atanmış.', Comment = '%1 = LP No., %2 = document no.';
        LpOtherLocationErr: Label '%1 numaralı taşıma kabı %2 lokasyonunda; sevkiyat %3 lokasyonundan yapılıyor.', Comment = '%1 = LP No., %2 = LP location, %3 = shipment location';
        LpNoBinErr: Label '%1 numaralı taşıma kabının rafı boş. Önce kabı bir rafa yerleştirin.', Comment = '%1 = LP No.';
        LpHasNoShipmentItemErr: Label '%1 numaralı taşıma kabı, %2 sevkiyatının açık satırlarındaki üründen (veya istenen lottan) bulundurmuyor.', Comment = '%1 = LP No., %2 = shipment no.';

    [BusinessEvent(false)]
    local procedure OnBeforeShipSales(SalesOrderNo: Code[20])
    begin
    end;

    [BusinessEvent(false)]
    local procedure OnAfterInvoiceSales(SalesOrderNo: Code[20])
    begin
    end;
}
