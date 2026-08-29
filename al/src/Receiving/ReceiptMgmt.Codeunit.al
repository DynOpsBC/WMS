codeunit 72043 "DOPSWHS Receipt Mgmt"
{
    Access = Public;
    // Kayıt sonrası put-away doğrulama/oluşturma ve LP damgalama kayıtlı
    // tablolara yazar; terminal kullanıcısının lisansı bunlara doğrudan izin
    // vermeyebilir. Dolaylı izinle akış kullanıcı lisansından bağımsız çalışır.
    Permissions =
        tabledata "Reservation Entry" = rimd,
        tabledata "Whse. Item Tracking Line" = rimd,
        tabledata "Lot No. Information" = rimd,
        tabledata "Purchase Header" = rm,
        tabledata "Purchase Line" = rim,
        tabledata "Posted Whse. Receipt Header" = rm,
        tabledata "Posted Whse. Receipt Line" = rm,
        tabledata "Warehouse Activity Header" = rim,
        tabledata "Warehouse Activity Line" = rim;

    /// <summary>Geriye dönük imza: operatör kimliği belgenin atamasından okunur.</summary>
    procedure PostReceipt(var WhseReceiptHeader: Record "Warehouse Receipt Header"; PrintReport: Boolean; Invoice: Boolean)
    begin
        PostReceipt(WhseReceiptHeader, PrintReport, Invoice, '');
    end;

    /// <summary>
    /// Mal kabul kaydı. OperatorUserId = işlemi yapan WMS operatörü; terminal
    /// kimliği taşıyorsa buradan geçirir, taşımıyorsa belgeye atanmış kullanıcıya
    /// düşülür. NEDEN: BC'ye tüm çağrılar paylaşımlı servis hesabıyla geldiği
    /// için UserId() "kim postaladı" sorusunu cevaplamıyor.
    /// </summary>
    procedure PostReceipt(var WhseReceiptHeader: Record "Warehouse Receipt Header"; PrintReport: Boolean; Invoice: Boolean; OperatorUserId: Code[50])
    begin
        PostReceipt(WhseReceiptHeader, PrintReport, Invoice, OperatorUserId, '');
    end;

    procedure PostReceipt(var WhseReceiptHeader: Record "Warehouse Receipt Header"; PrintReport: Boolean; Invoice: Boolean; OperatorUserId: Code[50]; PrinterId: Code[50])
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        LpNo: Code[20];
        ReceiptNo: Code[20];
        PostedNo: Code[20];
        PutAwayNo: Code[20];
        LocationCode: Code[10];
        AssignedUserId: Code[50];
    begin
        if PrintReport then begin
            EnsureReceiptReportConfigured();
            PrintDispatcher.EnsureDocumentPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::Receipt);
        end;
        // Posting deletes the working receipt. Preserve the keys which are
        // needed to stamp the posted document and finish the LP afterwards.
        ReceiptNo := WhseReceiptHeader."No.";
        LpNo := WhseReceiptHeader."DOPSWHS LP No.";
        LocationCode := WhseReceiptHeader."Location Code";
        AssignedUserId := WhseReceiptHeader."Assigned User ID";
        Log('Receipt.Post', ReceiptNo, EffectiveOperator(OperatorUserId, WhseReceiptHeader."Assigned User ID"));
        // BADE'nin tenant özelleştirmesi post sırasında bu DateTime alanını
        // zorunlu kılıyor. Alan başka bir PTE'ye ait olduğundan derleme-zamanı
        // bağımlılığı kurmadan RecordRef ile bulup yalnız boşsa dolduruyoruz.
        // Alanın olmadığı diğer müşterilerde işlem standart akışta devam eder.
        EnsurePostingDate(WhseReceiptHeader);
        EnsureActualReceiptDateTime(WhseReceiptHeader);
        // BADE'nin mal kabul doğrulaması ayrıca Warehouse Receipt Header
        // üzerindeki "Vendor Shipment No." alanını zorunlu tutuyor. Satın
        // alma siparişinde bir tedarikçi irsaliye numarası varsa onu, yoksa
        // izlenebilir ve benzersiz kaynak sipariş numarasını kullanıyoruz.
        // Alan BADE PTE'sine ait olduğu için bağımlılık oluşturmadan
        // dinamik olarak dolduruluyor; diğer tenant'larda no-op kalır.
        EnsureVendorShipmentNo(WhseReceiptHeader);
        // Standard BC posts one warehouse receipt line per purchase source
        // line. Bulk LP distribution therefore materializes matching technical
        // purchase lines first, then gives each LP its own source tracking.
        PrepareBulkReceiptPurchaseLines(ReceiptNo);
        PrepareLpReceiptTracking(ReceiptNo);
        // Daha eski mobil sürümler tedarikçi lotunu yalnız Lot No.
        // Information kartına yazıyordu. Hazırlanmış satırları da
        // yeniden giriş istemeden BADE takip kolonuna taşı.
        SyncSupplierLotsToReservations(WhseReceiptHeader);
        // Mobil dışından veya eski bir istemciden yazılmış takip satırları da
        // post sırasında geçmiş SKT ile stoğa girememelidir.
        EnsureReceiptExpirationDatesNotPast(WhseReceiptHeader);
        // BADE ayrıca plaka ve sürücü kodunu zorunlu tutuyor. Bunlar operatör
        // girdisidir (e-irsaliye verisi), varsayılan atanamaz. BC'nin İngilizce
        // TestField hatası yerine terminalin gösterebileceği net mesajla erken dur.
        EnsureVehicleInfoComplete(WhseReceiptHeader);
        // A terminal operator can post without first tapping "LP Kapat". An
        // open LP must be completed before the warehouse receipt disappears;
        // otherwise it cannot be assigned to the resulting put-away.
        EnsureReceiptLPsReady(ReceiptNo, LpNo);
        WhseReceiptLine.SetRange("No.", ReceiptNo);
        if WhseReceiptLine.FindFirst() then begin
            // Keep receipt posting, put-away verification and LP assignment in
            // one transaction. If the required put-away cannot be produced,
            // the API returns an error without leaving a half-posted receipt.
            WhsePostReceipt.SetSuppressCommit(true);
            WhsePostReceipt.SetHideValidationDialog(true);
            WhsePostReceipt.Run(WhseReceiptLine);
        end;

        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", ReceiptNo);
        if PostedWhseReceiptHeader.FindLast() then
            PostedNo := PostedWhseReceiptHeader."No.";

        // Resolve every posted line from its source LP line. A header carries
        // only one active LP and is therefore not a valid source for receipts
        // containing multiple pallets/lots.
        LpPropagation.StampPostedReceiptLines(ReceiptNo, PostedNo);
        LpPropagation.StampPostedReceiptHeader(ReceiptNo, PostedNo);
        // The Item Jnl. event runs before the working warehouse receipt is fully
        // traceable and can miss the LP. At this point BC has created its exact
        // Posted Whse. Receipt Line -> Item Ledger Entry relations, so persist it
        // deterministically onto Item/Value Ledger Entries.
        LpPropagation.StampPostedReceiptLedgerEntries(PostedNo, '');

        // Standard BC normally creates this activity while posting. Validate
        // the result and retry through the official posted-receipt API when a
        // tenant customization suppresses the first attempt. Never report a
        // successful LP receipt while its required put-away is missing.
        PutAwayNo := EnsurePutAwayCreated(PostedNo, LocationCode, AssignedUserId);
        if PutAwayNo <> '' then begin
            SplitPutAwayByReceiptLPs(ReceiptNo, PostedNo);
            StampPutAwayWithLP(PostedNo);
        end;

        if PrintReport then begin
            ClearLastError();
            if not QueuePostedReceiptPrint(PostedNo, PrinterId) then
                Telemetry.LogWarning(
                    'Print.ReceiptFailed',
                    CopyStr(StrSubstNo('Receipt %1 posted, but its print job could not be queued: %2', PostedNo, GetLastErrorText()), 1, 250),
                    EffectiveOperator(OperatorUserId, WhseReceiptHeader."Assigned User ID"));
        end;

        if PutAwayNo <> '' then
            AssignReceiptLPs(ReceiptNo, PostedNo, LpNo, Enum::"DOPSWHS Assigned Doc Type"::WhsePutaway, PutAwayNo)
        else
            AssignReceiptLPs(ReceiptNo, PostedNo, LpNo, Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, PostedNo);
    end;

    local procedure EnsureActualReceiptDateTime(var WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        ReceiptRef: RecordRef;
        CandidateField: FieldRef;
        ExistingValue: DateTime;
        FieldIndex: Integer;
    begin
        ReceiptRef.GetTable(WhseReceiptHeader);
        for FieldIndex := 1 to ReceiptRef.FieldCount do begin
            CandidateField := ReceiptRef.FieldIndex(FieldIndex);
            if (CandidateField.Type = FieldType::DateTime) and
               ((CandidateField.Name = 'Fiili Alış Tarihi - Saati') or
                (CandidateField.Caption = 'Fiili Alış Tarihi - Saati'))
            then begin
                ExistingValue := CandidateField.Value;
                if ExistingValue = 0DT then begin
                    CandidateField.Value := CurrentDateTime();
                    ReceiptRef.Modify(true);
                    ReceiptRef.SetTable(WhseReceiptHeader);
                end;
                exit;
            end;
        end;
    end;

    local procedure EnsureVendorShipmentNo(var WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PurchaseHeader: Record "Purchase Header";
        ReceiptRef: RecordRef;
        CandidateField: FieldRef;
        VendorShipmentNo: Code[35];
        FieldIndex: Integer;
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        if not WhseReceiptLine.FindFirst() then
            exit;

        if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, WhseReceiptLine."Source No.") then
            VendorShipmentNo := PurchaseHeader."Vendor Shipment No.";
        if VendorShipmentNo = '' then
            VendorShipmentNo := CopyStr(WhseReceiptLine."Source No.", 1, MaxStrLen(VendorShipmentNo));

        ReceiptRef.GetTable(WhseReceiptHeader);
        for FieldIndex := 1 to ReceiptRef.FieldCount do begin
            CandidateField := ReceiptRef.FieldIndex(FieldIndex);
            if (CandidateField.Type in [FieldType::Code, FieldType::Text]) and
               ((CandidateField.Name = 'Vendor Shipment No.') or
                (CandidateField.Caption = 'Vendor Shipment No.'))
            then begin
                if Format(CandidateField.Value) = '' then begin
                    CandidateField.Value := CopyStr(VendorShipmentNo, 1, CandidateField.Length);
                    ReceiptRef.Modify(true);
                    ReceiptRef.SetTable(WhseReceiptHeader);
                end;
                exit;
            end;
        end;
    end;

    local procedure EnsurePostingDate(var WhseReceiptHeader: Record "Warehouse Receipt Header")
    begin
        if WhseReceiptHeader."Posting Date" <> 0D then
            exit;
        WhseReceiptHeader.Validate("Posting Date", WorkDate());
        WhseReceiptHeader.Modify(true);
    end;

    /// <summary>
    /// Tenant özelleştirmesi (BADE) mal kabul başlığında plaka ve sürücü kodu
    /// istiyorsa bunlar terminalden girilmiş olmalı. Alanlar yoksa no-op.
    /// </summary>
    local procedure EnsureVehicleInfoComplete(WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        Missing: Text;
    begin
        if not VehicleInfoRequired(WhseReceiptHeader) then
            exit;
        if GetTenantHeaderField(WhseReceiptHeader, VehiclePlateFieldTok) = '' then
            Missing := PlateTxt;
        if GetTenantHeaderField(WhseReceiptHeader, DriverCodeFieldTok) = '' then
            if Missing = '' then
                Missing := DriverTxt
            else
                Missing := Missing + ' ' + AndTxt + ' ' + DriverTxt;
        if Missing <> '' then
            Error(VehicleInfoMissingErr, Missing);
    end;

    /// <summary>True when the tenant's receipt header carries the BADE vehicle fields.</summary>
    procedure VehicleInfoRequired(WhseReceiptHeader: Record "Warehouse Receipt Header"): Boolean
    var
        ReceiptRef: RecordRef;
        PlateField: FieldRef;
        DriverField: FieldRef;
    begin
        ReceiptRef.GetTable(WhseReceiptHeader);
        exit(FindFieldByName(ReceiptRef, VehiclePlateFieldTok, PlateField) and
             FindFieldByName(ReceiptRef, DriverCodeFieldTok, DriverField));
    end;

    /// <summary>
    /// Başka bir PTE'ye ait başlık alanını adıyla okur; alan yoksa ''. NEDEN:
    /// BCWMS, BADE uzantısına derleme-zamanı bağımlılığı kurmadan aynı kodla
    /// tüm müşterilerde çalışmalı.
    /// </summary>
    procedure GetTenantHeaderField(WhseReceiptHeader: Record "Warehouse Receipt Header"; FieldName: Text): Text
    var
        ReceiptRef: RecordRef;
        TenantField: FieldRef;
    begin
        ReceiptRef.GetTable(WhseReceiptHeader);
        if not FindFieldByName(ReceiptRef, FieldName, TenantField) then
            exit('');
        exit(Format(TenantField.Value));
    end;

    /// <summary>
    /// Terminalden gelen araç/irsaliye başlık bilgisi. Validate ile sürücü adı
    /// vb. alanlar BADE tablo uzantısının OnValidate tetikleyicisinde dolar.
    /// </summary>
    procedure SetVehicleInfo(var WhseReceiptHeader: Record "Warehouse Receipt Header"; VehiclePlateNo: Text; DriverCode: Code[20]; VendorShipmentNo: Text)
    var
        ReceiptRef: RecordRef;
        Changed: Boolean;
    begin
        if not VehicleInfoRequired(WhseReceiptHeader) then
            Error(VehicleInfoUnsupportedErr);
        ReceiptRef.GetTable(WhseReceiptHeader);
        Changed := WriteFieldByName(ReceiptRef, VehiclePlateFieldTok, UpperCase(DelChr(VehiclePlateNo, '<>', ' ')));
        Changed := WriteFieldByName(ReceiptRef, DriverCodeFieldTok, DriverCode) or Changed;
        if DelChr(VendorShipmentNo, '<>', ' ') <> '' then
            Changed := WriteFieldByName(ReceiptRef, VendorShipmentFieldTok, DelChr(VendorShipmentNo, '<>', ' ')) or Changed;
        if Changed then begin
            ReceiptRef.Modify(true);
            ReceiptRef.SetTable(WhseReceiptHeader);
        end;
        Log('Receipt.VehicleInfo', StrSubstNo(VehicleInfoLogTxt, WhseReceiptHeader."No.", VehiclePlateNo, DriverCode), WhseReceiptHeader."Assigned User ID");
    end;

    /// <summary>
    /// Sürücü ana verisi BADE PTE'sinin tablosunda; bağımlılık kurmadan tablo
    /// adıyla açılır. Tablo yoksa boş JSON dizisi döner. Çıktı: [{code,name}].
    /// </summary>
    procedure ListVehicleDrivers(): Text
    var
        AllObj: Record AllObjWithCaption;
        DriverRef: RecordRef;
        CodeField: FieldRef;
        BlockedField: FieldRef;
        Drivers: JsonArray;
        Driver: JsonObject;
        Result: Text;
    begin
        AllObj.SetRange("Object Type", AllObj."Object Type"::Table);
        AllObj.SetRange("Object Name", VehicleDriverTableTok);
        if not AllObj.FindFirst() then
            exit('[]');
        DriverRef.Open(AllObj."Object ID");
        if not FindFieldByName(DriverRef, 'Code', CodeField) then
            exit('[]');
        if FindFieldByName(DriverRef, 'Blocked', BlockedField) then
            BlockedField.SetRange(false);
        if DriverRef.FindSet() then
            repeat
                Clear(Driver);
                Driver.Add('code', Format(CodeField.Value));
                Driver.Add('name', DriverDisplayName(DriverRef));
                Drivers.Add(Driver);
            until DriverRef.Next() = 0;
        DriverRef.Close();
        Drivers.WriteTo(Result);
        exit(Result);
    end;

    local procedure DriverDisplayName(var DriverRef: RecordRef): Text
    var
        NameField: FieldRef;
        SurnameField: FieldRef;
        FullName: Text;
    begin
        if FindFieldByName(DriverRef, 'Full Name', NameField) then
            FullName := Format(NameField.Value);
        if FullName = '' then begin
            if FindFieldByName(DriverRef, 'Name', NameField) then
                FullName := Format(NameField.Value);
            if FindFieldByName(DriverRef, 'Surname', SurnameField) then
                FullName := DelChr(FullName + ' ' + Format(SurnameField.Value), '<>', ' ');
        end;
        exit(FullName);
    end;

    local procedure FindFieldByName(var RecRef: RecordRef; FieldName: Text; var Found: FieldRef): Boolean
    var
        FieldIndex: Integer;
    begin
        for FieldIndex := 1 to RecRef.FieldCount do begin
            Found := RecRef.FieldIndex(FieldIndex);
            if (Found.Name = FieldName) or (Found.Caption = FieldName) then
                exit(true);
        end;
        exit(false);
    end;

    local procedure WriteFieldByName(var RecRef: RecordRef; FieldName: Text; NewValue: Text): Boolean
    var
        Target: FieldRef;
    begin
        if not FindFieldByName(RecRef, FieldName, Target) then
            exit(false);
        if not (Target.Type in [FieldType::Code, FieldType::Text]) then
            exit(false);
        if Format(Target.Value) = NewValue then
            exit(false);
        Target.Validate(CopyStr(NewValue, 1, Target.Length));
        exit(true);
    end;

    local procedure EnsureReceiptLPsReady(ReceiptNo: Code[20]; HeaderLpNo: Code[20])
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        HeaderLP: Record "DOPSWHS LP Header";
        CheckedLPs: Dictionary of [Code[20], Boolean];
    begin
        // A receipt can survive several partial waves. Only LPs participating
        // in the current wave may be closed; earlier LPs are already assigned
        // to their put-away and must not block the next post.
        WhseReceiptLine.SetRange("No.", ReceiptNo);
        WhseReceiptLine.SetFilter("Qty. to Receive", '>0');
        WhseReceiptLine.SetFilter("DOPSWHS LP No.", '<>%1', '');
        if WhseReceiptLine.FindSet() then
            repeat
                if not CheckedLPs.ContainsKey(WhseReceiptLine."DOPSWHS LP No.") then begin
                    EnsureReceiptLPReady(WhseReceiptLine."DOPSWHS LP No.");
                    CheckedLPs.Add(WhseReceiptLine."DOPSWHS LP No.", true);
                end;
            until WhseReceiptLine.Next() = 0;

        // Legacy clients may have only the active header LP. Ignore a stale
        // Assigned/Consumed reference left by an earlier partial wave.
        if (HeaderLpNo <> '') and (not CheckedLPs.ContainsKey(HeaderLpNo)) then
            if HeaderLP.Get(HeaderLpNo) then
                if HeaderLP.Status in [HeaderLP.Status::Open, HeaderLP.Status::Built] then
                    EnsureReceiptLPReady(HeaderLpNo);
    end;

    local procedure EnsureReceiptLPReady(LpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if LpNo = '' then
            exit;
        if not LP.Get(LpNo) then
            Error('%1 LP kaydı bulunamadığı için mal kabul tamamlanamadı.', LpNo);

        if LP.Status = LP.Status::Open then
            LPMgt.Stop(LP, false);

        if LP.Status <> LP.Status::Built then
            Error('%1 LP''si mal kabul için uygun durumda değil. Mevcut durum: %2.', LpNo, Format(LP.Status));
    end;

    local procedure EnsurePutAwayCreated(PostedReceiptNo: Code[20]; LocationCode: Code[10]; AssignedUserId: Code[50]): Code[20]
    var
        Location: Record Location;
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        PutAwayNo: Code[20];
    begin
        if PostedReceiptNo = '' then
            Error('Mal kabul kaydedildi ancak oluşan kayıtlı mal kabul belgesi bulunamadı. İşlem geri alındı; tekrar deneyin.');

        if not Location.Get(LocationCode) then
            exit('');
        if not Location.RequirePutaway(LocationCode) then
            exit('');
        if Location."Use Put-away Worksheet" then
            exit('');

        PutAwayNo := FindPutAwayNo(PostedReceiptNo);
        if PutAwayNo <> '' then
            exit(PutAwayNo);

        PostedWhseReceiptLine.SetRange("No.", PostedReceiptNo);
        PostedWhseReceiptLine.SetFilter(Quantity, '>0');
        PostedWhseReceiptLine.SetFilter(Status, '<>%1', PostedWhseReceiptLine.Status::"Completely Put Away");
        if PostedWhseReceiptLine.IsEmpty() then
            exit('');

        PostedWhseReceiptLine.SetHideValidationDialog(true);
        PostedWhseReceiptLine.CreatePutAwayDoc(PostedWhseReceiptLine, AssignedUserId);

        PutAwayNo := FindPutAwayNo(PostedReceiptNo);
        if PutAwayNo = '' then
            Error(
                '%1 kayıtlı mal kabulü oluştu ancak zorunlu yerleştirme belgesi üretilemedi. Lokasyonun yerleştirme şablonu ve hedef raf kapasitesini kontrol edin; işlem geri alındı.',
                PostedReceiptNo);
        exit(PutAwayNo);
    end;

    local procedure FindPutAwayNo(PostedReceiptNo: Code[20]): Code[20]
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::"Put-away");
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Receipt);
        WhseActivityLine.SetRange("Whse. Document No.", PostedReceiptNo);
        if WhseActivityLine.FindFirst() then
            exit(WhseActivityLine."No.");
        exit('');
    end;

    local procedure StampPutAwayWithLP(PostedReceiptNo: Code[20])
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        ResolvedLpNo: Code[20];
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::"Put-away");
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Receipt);
        WhseActivityLine.SetRange("Whse. Document No.", PostedReceiptNo);
        if WhseActivityLine.FindSet(true) then
            repeat
                ResolvedLpNo := ResolvePutAwayLineLp(PostedReceiptNo, WhseActivityLine);
                if (ResolvedLpNo <> '') and (WhseActivityLine."LP No." <> ResolvedLpNo) then begin
                    // Direct assignment is intentional: validating one activity
                    // line recursively updates companions and may overwrite an
                    // LP belonging to a different receipt line.
                    WhseActivityLine."LP No." := ResolvedLpNo;
                    WhseActivityLine.Modify(true);
                end;
            until WhseActivityLine.Next() = 0;
    end;

    /// <summary>
    /// Standard BC creates one aggregated put-away pair for a posted receipt line. A bulk
    /// receipt may represent many physical LPs on that same line, so split the Take/Place
    /// pair into one pair per LP before the operator sees the document.
    /// </summary>
    procedure SplitPutAwayByReceiptLPs(ReceiptNo: Code[20]; PostedReceiptNo: Code[20])
    var
        PlaceLine: Record "Warehouse Activity Line";
        PlaceLineNos: List of [Integer];
        PlaceLineNo: Integer;
    begin
        PlaceLine.SetRange("Activity Type", PlaceLine."Activity Type"::"Put-away");
        PlaceLine.SetRange("Whse. Document Type", PlaceLine."Whse. Document Type"::Receipt);
        PlaceLine.SetRange("Whse. Document No.", PostedReceiptNo);
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        PlaceLine.SetRange("Breakbulk No.", 0);
        if PlaceLine.FindSet() then
            repeat
                PlaceLineNos.Add(PlaceLine."Line No.");
            until PlaceLine.Next() = 0;

        foreach PlaceLineNo in PlaceLineNos do begin
            PlaceLine.Reset();
            if PlaceLine.Get(PlaceLine."Activity Type"::"Put-away", FindPutAwayNo(PostedReceiptNo), PlaceLineNo) then
                if PlaceLine."LP No." = '' then
                    SplitOnePutAwayPairByReceiptLPs(ReceiptNo, PostedReceiptNo, PlaceLine);
        end;
    end;

    local procedure SplitOnePutAwayPairByReceiptLPs(ReceiptNo: Code[20]; PostedReceiptNo: Code[20]; var PlaceLine: Record "Warehouse Activity Line")
    var
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        SourceLPLine: Record "DOPSWHS LP Line";
        TakeLine: Record "Warehouse Activity Line";
        OriginalPlaceLine: Record "Warehouse Activity Line";
        OriginalTakeLine: Record "Warehouse Activity Line";
        NewLine: Record "Warehouse Activity Line";
        LPQuantities: Dictionary of [Code[20], Decimal];
        LpNo: Code[20];
        ExistingQty: Decimal;
        LpQty: Decimal;
        TotalLpQty: Decimal;
        FirstLp: Boolean;
        HasTakeLine: Boolean;
        ReceiptLineNo: Integer;
    begin
        // Historical repair must not reshape a pallet that an operator has
        // already started placing. New documents always enter with zero handled.
        if PlaceLine."Qty. Handled" <> 0 then
            exit;
        if not PostedReceiptLine.Get(PostedReceiptNo, PlaceLine."Whse. Document Line No.") then
            exit;

        ReceiptLineNo := PostedReceiptLine."Whse Receipt Line No.";
        if ReceiptLineNo = 0 then
            ReceiptLineNo := PostedReceiptLine."Line No.";

        SourceLPLine.SetRange("Source Document Type", SourceLPLine."Source Document Type"::WhseReceipt);
        SourceLPLine.SetRange("Source Document No.", ReceiptNo);
        SourceLPLine.SetRange("Source Document Line No.", ReceiptLineNo);
        SourceLPLine.SetRange("Item No.", PlaceLine."Item No.");
        SourceLPLine.SetRange("Variant Code", PlaceLine."Variant Code");
        SourceLPLine.SetRange("Lot No.", PlaceLine."Lot No.");
        SourceLPLine.SetRange("Serial No.", PlaceLine."Serial No.");
        SourceLPLine.SetFilter(Quantity, '>0');
        if SourceLPLine.FindSet() then
            repeat
                if (SourceLPLine."Unit of Measure" = '') or
                   (SourceLPLine."Unit of Measure" = PlaceLine."Unit of Measure Code")
                then begin
                    if LPQuantities.Get(SourceLPLine."LP No.", ExistingQty) then
                        LPQuantities.Set(SourceLPLine."LP No.", ExistingQty + SourceLPLine.Quantity)
                    else
                        LPQuantities.Add(SourceLPLine."LP No.", SourceLPLine.Quantity);
                    TotalLpQty += SourceLPLine.Quantity;
                end;
            until SourceLPLine.Next() = 0;

        if LPQuantities.Count() = 0 then
            exit;
        if Abs(TotalLpQty - PlaceLine.Quantity) > 0.00001 then
            Error(
                '%1 ürünü, lot %2 için LP toplamı (%3) yerleştirme miktarına (%4) eşit değil. İşlem geri alındı.',
                PlaceLine."Item No.", PlaceLine."Lot No.", TotalLpQty, PlaceLine.Quantity);

        FindRelatedPutAwayTakeLine(PlaceLine, TakeLine, HasTakeLine);
        OriginalPlaceLine := PlaceLine;
        if HasTakeLine then
            OriginalTakeLine := TakeLine;

        FirstLp := true;
        foreach LpNo in LPQuantities.Keys do begin
            LPQuantities.Get(LpNo, LpQty);
            if FirstLp then begin
                ApplyPutAwayLpQuantity(PlaceLine, LpNo, LpQty);
                PlaceLine.Modify(true);
                if HasTakeLine then begin
                    ApplyPutAwayLpQuantity(TakeLine, LpNo, LpQty);
                    TakeLine.Modify(true);
                end;
                FirstLp := false;
            end else begin
                InsertPutAwayLpLine(OriginalPlaceLine, LpNo, LpQty, NewLine);
                if HasTakeLine then
                    InsertPutAwayLpLine(OriginalTakeLine, LpNo, LpQty, NewLine);
            end;
        end;
    end;

    local procedure FindRelatedPutAwayTakeLine(PlaceLine: Record "Warehouse Activity Line"; var TakeLine: Record "Warehouse Activity Line"; var Found: Boolean)
    begin
        Clear(Found);
        TakeLine.SetRange("Activity Type", PlaceLine."Activity Type");
        TakeLine.SetRange("No.", PlaceLine."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.SetRange("Whse. Document Type", PlaceLine."Whse. Document Type");
        TakeLine.SetRange("Whse. Document No.", PlaceLine."Whse. Document No.");
        TakeLine.SetRange("Whse. Document Line No.", PlaceLine."Whse. Document Line No.");
        TakeLine.SetRange("Item No.", PlaceLine."Item No.");
        TakeLine.SetRange("Variant Code", PlaceLine."Variant Code");
        TakeLine.SetRange("Lot No.", PlaceLine."Lot No.");
        TakeLine.SetRange("Serial No.", PlaceLine."Serial No.");
        TakeLine.SetRange("Breakbulk No.", PlaceLine."Breakbulk No.");
        Found := TakeLine.FindFirst();
    end;

    local procedure ApplyPutAwayLpQuantity(var ActivityLine: Record "Warehouse Activity Line"; LpNo: Code[20]; Quantity: Decimal)
    begin
        ActivityLine.Validate(Quantity, Quantity);
        ActivityLine."LP No." := LpNo;
    end;

    local procedure InsertPutAwayLpLine(TemplateLine: Record "Warehouse Activity Line"; LpNo: Code[20]; Quantity: Decimal; var NewLine: Record "Warehouse Activity Line")
    begin
        NewLine.Init();
        NewLine.TransferFields(TemplateLine, false);
        // TransferFields(false) deliberately avoids reusing the complete primary
        // key, but the new line must still belong to the template's document.
        NewLine."Activity Type" := TemplateLine."Activity Type";
        NewLine."No." := TemplateLine."No.";
        NewLine."Line No." := NextPutAwayLineNo(TemplateLine."Activity Type", TemplateLine."No.");
        ApplyPutAwayLpQuantity(NewLine, LpNo, Quantity);
        NewLine.Insert(true);
    end;

    local procedure NextPutAwayLineNo(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityType);
        ActivityLine.SetRange("No.", ActivityNo);
        if ActivityLine.FindLast() then
            exit(ActivityLine."Line No." + 10000);
        exit(10000);
    end;

    local procedure ResolvePutAwayLineLp(PostedReceiptNo: Code[20]; WhseActivityLine: Record "Warehouse Activity Line"): Code[20]
    var
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        CandidateLpNo: Code[20];
    begin
        // Normal path: the activity line points to the posted receipt line.
        if PostedReceiptLine.Get(PostedReceiptNo, WhseActivityLine."Whse. Document Line No.") then
            if (PostedReceiptLine."LP No." <> '') and
               (PostedReceiptLine."Item No." = WhseActivityLine."Item No.") and
               (PostedReceiptLine."Variant Code" = WhseActivityLine."Variant Code")
            then
                exit(PostedReceiptLine."LP No.");

        // Tenant customizations can renumber activity document lines. Fall back
        // to the tracking identity, but only when it resolves to one physical LP.
        CandidateLpNo := ResolveUniquePostedReceiptLp(PostedReceiptNo, WhseActivityLine, true);
        if CandidateLpNo <> '' then
            exit(CandidateLpNo);
        exit(ResolveUniquePostedReceiptLp(PostedReceiptNo, WhseActivityLine, false));
    end;

    local procedure ResolveUniquePostedReceiptLp(PostedReceiptNo: Code[20]; WhseActivityLine: Record "Warehouse Activity Line"; MatchTracking: Boolean): Code[20]
    var
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        CandidateLpNo: Code[20];
    begin
        PostedReceiptLine.Reset();
        PostedReceiptLine.SetRange("No.", PostedReceiptNo);
        PostedReceiptLine.SetRange("Item No.", WhseActivityLine."Item No.");
        PostedReceiptLine.SetRange("Variant Code", WhseActivityLine."Variant Code");
        if MatchTracking then begin
            PostedReceiptLine.SetRange("Lot No.", WhseActivityLine."Lot No.");
            PostedReceiptLine.SetRange("Serial No.", WhseActivityLine."Serial No.");
        end;
        PostedReceiptLine.SetFilter("LP No.", '<>%1', '');
        if PostedReceiptLine.FindSet() then
            repeat
                if CandidateLpNo = '' then
                    CandidateLpNo := PostedReceiptLine."LP No."
                else
                    if CandidateLpNo <> PostedReceiptLine."LP No." then
                        exit('');
            until PostedReceiptLine.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure EnsureRequiredSupplierLots(WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LotNo: Code[50];
        SerialNo: Code[50];
        ExpiryDate: Date;
        SupplierLotNo: Code[50];
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.SetFilter("Qty. to Receive", '>0');
        if WhseReceiptLine.FindSet() then
            repeat
                if ReceiptLineRequiresSupplierLot(WhseReceiptLine) then begin
                    GetItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate);
                    GetSupplierLot(WhseReceiptLine, LotNo, SupplierLotNo);
                    if SupplierLotNo = '' then
                        Error(
                            'Mal kabul kaydedilemez. %1 ürününün %2 satırında tedarikçi lotu eksik.',
                            WhseReceiptLine."Item No.", WhseReceiptLine."Line No.");
                end;
            until WhseReceiptLine.Next() = 0;
    end;

    [TryFunction]
    local procedure QueuePostedReceiptPrint(PostedReceiptNo: Code[20]; PrinterId: Code[50])
    var
        PostedReceipt: Record "Posted Whse. Receipt Header";
        ReportSelection: Record "DOPSWHS IWX Report Selection";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceRecord: RecordRef;
    begin
        if PostedReceiptNo = '' then
            Error('The posted warehouse receipt could not be found for printing.');
        ReportSelection.SetCurrentKey(Usage, Sequence);
        ReportSelection.SetRange(Usage, ReportSelection.Usage::Receipt);
        ReportSelection.SetFilter("Report ID", '<>0');
        if not ReportSelection.FindFirst() then
            Error('No report is configured for Receipt printing.');
        PostedReceipt.Get(PostedReceiptNo);
        PostedReceipt.SetRecFilter();
        SourceRecord.GetTable(PostedReceipt);
        PrintDispatcher.PrintReport(PostedReceiptNo, ReportSelection."Report ID", PrinterId, 1, ReportSelection.Usage, SourceRecord);
    end;

    local procedure EnsureReceiptReportConfigured()
    var
        ReportSelection: Record "DOPSWHS IWX Report Selection";
    begin
        ReportSelection.SetCurrentKey(Usage, Sequence);
        ReportSelection.SetRange(Usage, ReportSelection.Usage::Receipt);
        ReportSelection.SetFilter("Report ID", '<>0');
        if not ReportSelection.FindFirst() then
            Error('No report is configured for Receipt printing.');
    end;

    /// <summary>Geriye dönük imza: atamayı yapan kimlik bilinmiyor.</summary>
    procedure AssignUser(var WhseReceiptHeader: Record "Warehouse Receipt Header"; AssignedUserId: Code[50])
    begin
        AssignUser(WhseReceiptHeader, AssignedUserId, '');
    end;

    /// <summary>
    /// Belgeyi bir operatöre atar. PerformedByUserId = atamayı YAPAN kimlik
    /// (masadan başkası atayabilir); boşsa oturumun BC hesabına düşülür.
    /// Atanan kullanıcı log mesajına yazılır ki devir zinciri okunabilsin.
    /// </summary>
    procedure AssignUser(var WhseReceiptHeader: Record "Warehouse Receipt Header"; AssignedUserId: Code[50]; PerformedByUserId: Code[50])
    begin
        Log('Receipt.AssignUser', StrSubstNo(AssignLogTxt, WhseReceiptHeader."No.", OperatorOrNone(AssignedUserId)), PerformedByUserId);
        WhseReceiptHeader.Validate("Assigned User ID", AssignedUserId);
        WhseReceiptHeader.Modify(true);
    end;

    procedure StartLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; TemplateCode: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        EffectiveTemplateCode: Code[20];
        ReceiptBinCode: Code[20];
    begin
        // LP açan operatör: belgeye atanmış kullanıcı (uç nokta ayrı kimlik taşımıyor).
        Log('Receipt.StartLP', WhseReceiptHeader."No.", WhseReceiptHeader."Assigned User ID");
        // Ağ gecikmesi/tekrar dokunma aynı belge için sahipsiz ikinci bir LP
        // üretmesin. Başlıkta halen açık LP varsa idempotent olarak onu dön.
        if (WhseReceiptHeader."DOPSWHS LP No." <> '') and
           LP.Get(WhseReceiptHeader."DOPSWHS LP No.")
        then begin
            if LP.Status = LP.Status::Open then
                exit(LP."No.");
            // Built means the pallet was physically closed. Starting again in
            // the same receipt must create the next pallet, not reopen and mix
            // the new lot/quantity into the previous LP.
        end;

        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        ReceiptBinCode := GetSingleReceiptBin(WhseReceiptHeader."No.");
        LPMgt.Build(EffectiveTemplateCode, WhseReceiptHeader."Location Code", ReceiptBinCode, LP);
        // Aktif LP yalnız Android belleğinde kalırsa ekran yenilenince
        // "LP Başlat" geri gelir ve ConfirmLine ürünü LP'siz kaydeder.
        WhseReceiptHeader."DOPSWHS LP No." := LP."No.";
        WhseReceiptHeader.Modify(true);
        exit(LP."No.");
    end;

    procedure StopLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; LpNo: Code[20]; PrintLabel: Boolean)
    begin
        StopLP(WhseReceiptHeader, LpNo, PrintLabel, '');
    end;

    procedure StopLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; LpNo: Code[20]; PrintLabel: Boolean; PrinterId: Code[50])
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Log('Receipt.StopLP', WhseReceiptHeader."No.", WhseReceiptHeader."Assigned User ID");
        LP.Get(LpNo);
        // Closing the LP is the warehouse transaction; the combined MTE/LP label
        // is best-effort output and must not reopen the LP when a printer is
        // unavailable. No mobile/API contract changes are required.
        LPMgt.Stop(LP, false, PrinterId);
        if PrintLabel then begin
            ClearLastError();
            if not TryPrintCombinedMteLabel(LP, PrinterId) then
                Telemetry.LogWarning(
                    'Print.ReceiptLpLabelsFailed',
                    CopyStr(
                        StrSubstNo(
                            'Receipt LP %1 completed, but its combined MTE/LP label could not be printed: %2',
                            LP."No.", GetLastErrorText()),
                        1, 250),
                    WhseReceiptHeader."Assigned User ID");
        end;
    end;

    /// <summary>
    /// Distributes one receipt-line quantity over multiple newly generated LPs. All validation,
    /// item tracking and LP creation is completed before label output starts, so a data error
    /// cannot leave a partially distributed receipt.
    /// </summary>
    procedure CreateBulkLPDistribution(var WhseReceiptHeader: Record "Warehouse Receipt Header"; LineNo: Integer; ExpectedQty: Decimal; DistributionJson: Text; TemplateCode: Code[20]; PrintLabels: Boolean; PrinterId: Code[50]): Text
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        ExistingLPLine: Record "DOPSWHS LP Line";
        LP: Record "DOPSWHS LP Header";
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        LPMgt: Codeunit "DOPSWHS LP Management";
        LotSerialGen: Codeunit "DOPSWHS Lot Serial Generator";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        Rows: JsonArray;
        CreatedLPsJson: JsonArray;
        Response: JsonObject;
        RowToken: JsonToken;
        RowObject: JsonObject;
        QuantityToken: JsonToken;
        CreatedLPObject: JsonObject;
        RowQuantities: Dictionary of [Integer, Decimal];
        RowLots: Dictionary of [Integer, Code[50]];
        RowSupplierLots: Dictionary of [Integer, Code[50]];
        RowExpiryDates: Dictionary of [Integer, Date];
        RowLpNos: Dictionary of [Integer, Code[20]];
        RowReceiptLineNos: Dictionary of [Integer, Integer];
        GroupLots: Dictionary of [Text, Code[50]];
        CreatedLPNos: List of [Code[20]];
        EffectiveTemplateCode: Code[20];
        GroupId: Text;
        LotNo: Code[50];
        ExistingGroupLot: Code[50];
        SupplierLotNo: Code[50];
        ExpiryDateText: Text;
        ExpiryDate: Date;
        RowQuantity: Decimal;
        DistributionTotal: Decimal;
        OutstandingQty: Decimal;
        RowIndex: Integer;
        LotRequired: Boolean;
        ExpiryRequired: Boolean;
        CreatedLPNo: Code[20];
        ResponseText: Text;
        DistributedReceiptLine: Record "Warehouse Receipt Line";
        DistributedReceiptLineNo: Integer;
        OriginalLineNo: Integer;
    begin
        OriginalLineNo := LineNo;
        if not WhseReceiptLine.Get(WhseReceiptHeader."No.", LineNo) then
            Error('%1 mal kabul belgesinde %2 satırı bulunamadı.', WhseReceiptHeader."No.", LineNo);
        if ExpectedQty <= 0 then
            Error('Toplam kabul miktarı sıfırdan büyük olmalıdır.');
        if DistributionJson = '' then
            Error('LP dağıtım listesi boş olamaz.');
        Rows.ReadFrom(DistributionJson);
        if Rows.Count = 0 then
            Error('En az bir LP miktarı girilmelidir.');
        if Rows.Count > 200 then
            Error('Tek işlemde en fazla 200 LP oluşturulabilir.');

        OutstandingQty := WhseReceiptLine.Quantity - WhseReceiptLine."Qty. Received";
        if ExpectedQty > (OutstandingQty + 0.00001) then
            Error(
                'Toplam kabul miktarı satırın kalan miktarını aşamaz. Kalan: %1, girilen: %2.',
                OutstandingQty, ExpectedQty);

        ExistingLPLine.SetRange("Source Document Type", ExistingLPLine."Source Document Type"::WhseReceipt);
        ExistingLPLine.SetRange("Source Document No.", WhseReceiptHeader."No.");
        ExistingLPLine.SetRange("Source Document Line No.", LineNo);
        ExistingLPLine.SetFilter(Quantity, '>0');
        if (not ExistingLPLine.IsEmpty()) and (WhseReceiptLine."Qty. Received" = 0) then
            Error(
                '%1 satırı için daha önce LP dağıtımı yapılmış. Çift LP oluşmaması için mevcut LP''leri kontrol edin.',
                LineNo);

        Item.Get(WhseReceiptLine."Item No.");
        if Item."Item Tracking Code" <> '' then begin
            ItemTrackingCode.Get(Item."Item Tracking Code");
            LotRequired := RequiresLotTracking(ItemTrackingCode);
            ExpiryRequired := ItemTrackingCode."Man. Expir. Date Entry Reqd.";
            if RequiresSerialTracking(ItemTrackingCode) then
                Error(
                    '%1 ürünü seri takipli olduğu için toplu LP dağıtımı kullanılamaz; seri numaralarını tek tek okutun.',
                    WhseReceiptLine."Item No.");
        end;

        RowIndex := 0;
        foreach RowToken in Rows do begin
            RowIndex += 1;
            RowObject := RowToken.AsObject();
            if not RowObject.Get('quantity', QuantityToken) then
                Error('%1. LP satırında miktar bulunamadı.', RowIndex);
            RowQuantity := QuantityToken.AsValue().AsDecimal();
            if RowQuantity <= 0 then
                Error('%1. LP satırının miktarı sıfırdan büyük olmalıdır.', RowIndex);

            GroupId := BulkJsonText(RowObject, 'groupId');
            if GroupId = '' then
                GroupId := Format(RowIndex);
            LotNo := CopyStr(BulkJsonText(RowObject, 'lotNo'), 1, MaxStrLen(LotNo));
            SupplierLotNo := CopyStr(BulkJsonText(RowObject, 'supplierLotNo'), 1, MaxStrLen(SupplierLotNo));
            ExpiryDateText := BulkJsonText(RowObject, 'expiryDate');
            Clear(ExpiryDate);
            if ExpiryDateText <> '' then
                if not Evaluate(ExpiryDate, ExpiryDateText, 9) then
                    Error('%1. LP satırının SKT değeri geçersizdir: %2.', RowIndex, ExpiryDateText);

            if LotRequired then begin
                if LotNo = '' then begin
                    if not GroupLots.Get(GroupId, LotNo) then begin
                        LotNo := LotSerialGen.GenerateLotNoForItem(WhseReceiptLine."Item No.");
                        if LotNo = '' then
                            Error(
                                '%1 ürünü için iç lot numara serisi tanımlı değil.',
                                WhseReceiptLine."Item No.");
                        GroupLots.Add(GroupId, LotNo);
                    end;
                end else
                    if GroupLots.Get(GroupId, ExistingGroupLot) then begin
                        if ExistingGroupLot <> LotNo then
                            Error('%1 lot grubunda birden fazla iç lot kullanılamaz.', GroupId);
                    end else
                        GroupLots.Add(GroupId, LotNo);
            end else begin
                LotNo := '';
                SupplierLotNo := '';
            end;

            if ExpiryRequired and (ExpiryDate = 0D) then
                Error('%1. LP satırında son kullanma tarihi zorunludur.', RowIndex);
            if (ExpiryDate <> 0D) and (ExpiryDate < Today) then
                Error('%1. LP satırında geçmiş son kullanma tarihi kullanılamaz: %2.', RowIndex, ExpiryDate);
            if (SupplierLotNo <> '') and (LotNo = '') then
                Error('%1. LP satırında tedarikçi lotu için iç lot zorunludur.', RowIndex);

            RowQuantities.Add(RowIndex, RowQuantity);
            RowLots.Add(RowIndex, LotNo);
            RowSupplierLots.Add(RowIndex, SupplierLotNo);
            RowExpiryDates.Add(RowIndex, ExpiryDate);
            DistributionTotal += RowQuantity;
        end;

        if Abs(DistributionTotal - ExpectedQty) > 0.00001 then
            Error(
                'LP miktarları toplam kabul miktarına eşit olmalıdır. Kabul: %1, LP toplamı: %2, fark: %3.',
                ExpectedQty, DistributionTotal, ExpectedQty - DistributionTotal);

        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        DeleteSourceReservationTracking(WhseReceiptLine);
        DeleteWarehouseItemTracking(WhseReceiptLine);

        // Önce fiziksel LP'leri oluştur. Aşağıda aynı mal kabul belgesi içinde
        // her LP için ayrı teknik Warehouse Receipt Line üretilecek; böylece BC
        // postu tek bir toplu hareket yerine LP bazında izlenebilir hareketler yazar.
        for RowIndex := 1 to Rows.Count do begin
            RowQuantities.Get(RowIndex, RowQuantity);
            RowLots.Get(RowIndex, LotNo);
            RowSupplierLots.Get(RowIndex, SupplierLotNo);
            RowExpiryDates.Get(RowIndex, ExpiryDate);

            Clear(LP);
            LPMgt.Build(
                EffectiveTemplateCode, WhseReceiptHeader."Location Code",
                WhseReceiptLine."Bin Code", LP);
            LPMgt.AddLine(
                LP, WhseReceiptLine."Item No.", WhseReceiptLine."Unit of Measure Code",
                RowQuantity, LotNo, '', ExpiryDate);
            LPMgt.Stop(LP, false, PrinterId);

            CreatedLPNo := LP."No.";
            CreatedLPNos.Add(CreatedLPNo);
            RowLpNos.Add(RowIndex, CreatedLPNo);
            Clear(CreatedLPObject);
            CreatedLPObject.Add('lpNo', CreatedLPNo);
            CreatedLPObject.Add('quantity', RowQuantity);
            CreatedLPObject.Add('lotNo', LotNo);
            CreatedLPsJson.Add(CreatedLPObject);
            if WhseReceiptHeader."DOPSWHS LP No." = '' then
                WhseReceiptHeader."DOPSWHS LP No." := CreatedLPNo;
        end;

        MaterializeBulkReceiptLines(
            WhseReceiptLine, ExpectedQty, RowQuantities, RowLpNos, RowReceiptLineNos);
        PrepareBulkReceiptPurchaseLines(WhseReceiptHeader."No.");

        // İzleme ve LP kaynak ilişkisini artık her LP'nin kendi mal kabul
        // satırına yaz. Bu kimlik Warehouse Entry, Item Ledger Entry ve
        // yerleştirme satırlarında aynı LP'nin korunmasını sağlar.
        for RowIndex := 1 to Rows.Count do begin
            RowReceiptLineNos.Get(RowIndex, DistributedReceiptLineNo);
            DistributedReceiptLine.Get(WhseReceiptHeader."No.", DistributedReceiptLineNo);
            RowQuantities.Get(RowIndex, RowQuantity);
            RowLots.Get(RowIndex, LotNo);
            RowSupplierLots.Get(RowIndex, SupplierLotNo);
            RowExpiryDates.Get(RowIndex, ExpiryDate);
            RowLpNos.Get(RowIndex, CreatedLPNo);
            if Item."Item Tracking Code" <> '' then
                PersistItemTrackingEntry(
                    DistributedReceiptLine, RowQuantity, LotNo, '', ExpiryDate, SupplierLotNo);
            if SupplierLotNo <> '' then
                PersistSupplierLot(
                    DistributedReceiptLine."Item No.", DistributedReceiptLine."Variant Code", LotNo, SupplierLotNo);
            StampReceiptSourceOnLastLpLine(CreatedLPNo, DistributedReceiptLine);
        end;

        WhseReceiptHeader.Modify(true);

        if PrintLabels then
            foreach CreatedLPNo in CreatedLPNos do
                if LP.Get(CreatedLPNo) then begin
                    ClearLastError();
                    if not TryPrintCombinedMteLabel(LP, PrinterId) then
                        Telemetry.LogWarning(
                            'Print.BulkReceiptLpLabelFailed',
                            CopyStr(
                                StrSubstNo('%1 LP etiketi yazdırılamadı: %2', CreatedLPNo, GetLastErrorText()),
                                1, 250),
                            WhseReceiptHeader."Assigned User ID");
                end;

        Log(
            'Receipt.BulkLPDistribution',
            StrSubstNo('%1 line=%2 lpCount=%3 qty=%4', WhseReceiptHeader."No.", OriginalLineNo, Rows.Count, ExpectedQty),
            WhseReceiptHeader."Assigned User ID");
        Response.Add('count', Rows.Count);
        Response.Add('totalQty', ExpectedQty);
        Response.Add('lpNos', CreatedLPsJson);
        Response.WriteTo(ResponseText);
        exit(ResponseText);
    end;

    local procedure MaterializeBulkReceiptLines(var SourceLine: Record "Warehouse Receipt Line"; ExpectedQty: Decimal; RowQuantities: Dictionary of [Integer, Decimal]; RowLpNos: Dictionary of [Integer, Code[20]]; var RowReceiptLineNos: Dictionary of [Integer, Integer])
    var
        TemplateLine: Record "Warehouse Receipt Line";
        DistributedLine: Record "Warehouse Receipt Line";
        ExistingLine: Record "Warehouse Receipt Line";
        RowQuantity: Decimal;
        RowLpNo: Code[20];
        RemainderQty: Decimal;
        OriginalOutstandingQty: Decimal;
        NextLineNo: Integer;
        RowIndex: Integer;
        ReuseSourceLine: Boolean;
    begin
        TemplateLine := SourceLine;
        OriginalOutstandingQty := SourceLine.Quantity - SourceLine."Qty. Received";
        RemainderQty := OriginalOutstandingQty - ExpectedQty;

        ExistingLine.SetRange("No.", SourceLine."No.");
        if ExistingLine.FindLast() then
            NextLineNo := ExistingLine."Line No.";

        // Önceki kısmi kabulden miktar taşıyan eski satırı geçmiş kaydıyla
        // bırak; yeni LP'ler yeni satırlarda oluşur. İlk dalgada ise özgün satır
        // ilk LP için yeniden kullanılır.
        ReuseSourceLine := SourceLine."Qty. Received" = 0;
        if not ReuseSourceLine then begin
            SourceLine.Validate(Quantity, SourceLine."Qty. Received");
            SourceLine.Validate("Qty. to Receive", 0);
            Clear(SourceLine."DOPSWHS Pending Lot No.");
            Clear(SourceLine."DOPSWHS LP No.");
            SourceLine.Modify(true);
        end;

        for RowIndex := 1 to RowQuantities.Count() do begin
            RowQuantities.Get(RowIndex, RowQuantity);
            RowLpNos.Get(RowIndex, RowLpNo);
            if ReuseSourceLine and (RowIndex = 1) then begin
                ConfigureBulkReceiptLine(SourceLine, RowQuantity, RowQuantity, RowLpNo);
                SourceLine.Modify(true);
                RowReceiptLineNos.Add(RowIndex, SourceLine."Line No.");
            end else begin
                NextLineNo := NextBulkReceiptLineNo(SourceLine."No.", NextLineNo);
                InsertBulkReceiptLine(TemplateLine, DistributedLine, NextLineNo, RowQuantity, RowQuantity, RowLpNo);
                RowReceiptLineNos.Add(RowIndex, DistributedLine."Line No.");
            end;
        end;

        if RemainderQty > 0.00001 then begin
            NextLineNo := NextBulkReceiptLineNo(SourceLine."No.", NextLineNo);
            InsertBulkReceiptLine(TemplateLine, DistributedLine, NextLineNo, RemainderQty, 0, '');
        end;
    end;

    local procedure InsertBulkReceiptLine(TemplateLine: Record "Warehouse Receipt Line"; var NewLine: Record "Warehouse Receipt Line"; LineNo: Integer; Quantity: Decimal; QtyToReceive: Decimal; LpNo: Code[20])
    begin
        Clear(NewLine);
        NewLine.Init();
        NewLine.TransferFields(TemplateLine, false);
        NewLine."No." := TemplateLine."No.";
        NewLine."Line No." := LineNo;
        NewLine."Qty. Received" := 0;
        NewLine."Qty. Received (Base)" := 0;
        ConfigureBulkReceiptLine(NewLine, Quantity, QtyToReceive, LpNo);
        NewLine.Insert(true);
    end;

    local procedure ConfigureBulkReceiptLine(var ReceiptLine: Record "Warehouse Receipt Line"; Quantity: Decimal; QtyToReceive: Decimal; LpNo: Code[20])
    begin
        ReceiptLine.Validate(Quantity, Quantity);
        ReceiptLine.Validate("Qty. to Receive", QtyToReceive);
        ReceiptLine."DOPSWHS LP No." := LpNo;
        Clear(ReceiptLine."DOPSWHS Pending Lot No.");
    end;

    local procedure NextBulkReceiptLineNo(ReceiptNo: Code[20]; CurrentLineNo: Integer): Integer
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        CandidateLineNo: Integer;
    begin
        CandidateLineNo := CurrentLineNo + 10000;
        while ReceiptLine.Get(ReceiptNo, CandidateLineNo) do
            CandidateLineNo += 10000;
        exit(CandidateLineNo);
    end;

    /// <summary>Geriye dönük imza: operatör kimliği belgenin atamasından okunur.</summary>
    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20])
    begin
        ConfirmLine(WhseReceiptLine, QtyToReceive, LotNo, SerialNo, ExpiryDate, LicensePlateNo, BinCode, '', '');
    end;

    /// <summary>
    /// Satır onayı (okutma). OperatorUserId = okutmayı yapan WMS operatörü;
    /// boşsa belgeye atanmış kullanıcıya düşülür.
    /// </summary>
    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20]; OperatorUserId: Code[50])
    begin
        ConfirmLine(WhseReceiptLine, QtyToReceive, LotNo, SerialNo, ExpiryDate, LicensePlateNo, BinCode, '', OperatorUserId);
    end;

    /// <summary>
    /// Mal kabul satırını iç lot/seri ve isteğe bağlı tedarikçi lotuyla birlikte onaylar.
    /// Girilmişse tedarikçi lotu Lot No. Information kartına yazılır.
    /// </summary>
    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20]; SupplierLotNo: Code[50]; OperatorUserId: Code[50])
    var
        LP: Record "DOPSWHS LP Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        LotSerialGen: Codeunit "DOPSWHS Lot Serial Generator";
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        ExistingLotNo: Code[50];
        ExistingSerialNo: Code[50];
        ExistingExpiryDate: Date;
    begin
        Log('Receipt.ConfirmLine', WhseReceiptLine."No.", EffectiveOperator(OperatorUserId, ReceiptOperator(WhseReceiptLine."No.")));
        Item.Get(WhseReceiptLine."Item No.");
        // Mevcut BC takip bilgisi korunur. İç lot yalnız terminaldeki açık
        // "Lot No Ata" komutuyla üretilir; ConfirmLine boş lotu tamamlamaz.
        // Seri numarası için mevcut geriye uyumlu otomatik üretim korunur.
        if Item."Item Tracking Code" <> '' then begin
            GetItemTracking(WhseReceiptLine, ExistingLotNo, ExistingSerialNo, ExistingExpiryDate);
            if LotNo = '' then
                LotNo := ExistingLotNo;
            if SerialNo = '' then
                SerialNo := ExistingSerialNo;
            if ExpiryDate = 0D then
                ExpiryDate := ExistingExpiryDate;

            if not ItemTrackingCode.Get(Item."Item Tracking Code") then
                Error('%1 takip kodu bulunamadı.', Item."Item Tracking Code");
            if RequiresLotTracking(ItemTrackingCode) then begin
                if LotNo = '' then
                    Error(
                        'İç lot numarası zorunludur. %1 ürünü için el terminalinde Lot No Ata düğmesine basın.',
                        WhseReceiptLine."Item No.");
            end else
                LotNo := '';
            if ItemTrackingCode."Man. Expir. Date Entry Reqd." and (ExpiryDate = 0D) then
                Error(
                    'Son kullanma tarihi zorunludur. %1 ürünü için el terminalinden son kullanma tarihini girin.',
                    WhseReceiptLine."Item No.");
            if (ExpiryDate <> 0D) and (ExpiryDate < Today) then
                Error(
                    'Geçmiş son kullanma tarihli ürün mal kabul edilemez. Ürün: %1, SKT: %2.',
                    WhseReceiptLine."Item No.", ExpiryDate);
            if RequiresSerialTracking(ItemTrackingCode) then begin
                if SerialNo = '' then
                    SerialNo := LotSerialGen.GenerateSerialNo();
            end else
                SerialNo := '';

        end else begin
            LotNo := '';
            SerialNo := '';
        end;
        if BinCode <> '' then
            WhseReceiptLine.Validate("Bin Code", BinCode);
        WhseReceiptLine.Validate("Qty. to Receive", QtyToReceive);
        WhseReceiptLine."DOPSWHS LP No." := LicensePlateNo;
        WhseReceiptLine.Modify(true);
        // Mobilden girilen lot/seri, BC'nin Item Tracking
        // Lines mekanizmasının okuduğu Reservation Entry kayıtlarına yazılmazsa post
        // sırasında sessizce kaybolur — bu yüzden burada gerçek kalıcılığı sağlıyoruz.
        if Item."Item Tracking Code" <> '' then
            PersistItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate, SupplierLotNo);
        if SupplierLotNo <> '' then
            PersistSupplierLot(
                WhseReceiptLine."Item No.", WhseReceiptLine."Variant Code", LotNo, SupplierLotNo);

        if LicensePlateNo <> '' then begin
            LP.Get(LicensePlateNo);
            BindLpToReceiptBin(LP, WhseReceiptLine);
            EnsureReceiptLpIdentity(LP, WhseReceiptLine, LotNo, SerialNo);
            LPMgt.AddLine(LP, WhseReceiptLine."Item No.", WhseReceiptLine."Unit of Measure Code", QtyToReceive, LotNo, SerialNo, ExpiryDate);
            StampReceiptSourceOnLastLpLine(LicensePlateNo, WhseReceiptLine);

            // Stamp the Whse Receipt Header with this LP so downstream posting can carry it
            // onto Posted Whse Receipt + Item Ledger Entry. Idempotent — only first LP wins.
            if WhseReceiptHeader.Get(WhseReceiptLine."No.") then
                if WhseReceiptHeader."DOPSWHS LP No." = '' then begin
                    WhseReceiptHeader."DOPSWHS LP No." := LicensePlateNo;
                    WhseReceiptHeader.Modify(true);
                end;
        end;

        // "Lot No Ata" ile ayrılan numara, satırın takip kaydı ve varsa LP
        // satırı tamamen başarıyla yazıldıktan sonra artık bekleyen değildir.
        // Bu noktadan önce oluşacak herhangi bir Error tüm transaction'ı geri
        // alır; böylece aynı lot tekrar açılan miktar ekranında korunur.
        if WhseReceiptLine."DOPSWHS Pending Lot No." <> '' then begin
            Clear(WhseReceiptLine."DOPSWHS Pending Lot No.");
            WhseReceiptLine.Modify(true);
        end;
    end;

    local procedure StampReceiptSourceOnLastLpLine(LpNo: Code[20]; WhseReceiptLine: Record "Warehouse Receipt Line")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        if not LPLine.FindLast() then
            Error('%1 LP satırı oluşturulamadı.', LpNo);
        LPLine."Source Document Type" := LPLine."Source Document Type"::WhseReceipt;
        LPLine."Source Document No." := WhseReceiptLine."No.";
        LPLine."Source Document Line No." := WhseReceiptLine."Line No.";
        LPLine."Source Bin Code" := WhseReceiptLine."Bin Code";
        LPLine."Variant Code" := WhseReceiptLine."Variant Code";
        // Quantity is the original receipt-line total (for example 500), while
        // LP Line.Quantity remains this pallet's amount (for example 250).
        LPLine."Source Document Quantity" := WhseReceiptLine.Quantity;
        LPLine.Modify(true);
    end;

    local procedure GetSingleReceiptBin(ReceiptNo: Code[20]): Code[20]
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        CandidateBin: Code[20];
    begin
        WhseReceiptLine.SetRange("No.", ReceiptNo);
        WhseReceiptLine.SetFilter("Bin Code", '<>%1', '');
        if WhseReceiptLine.FindSet() then
            repeat
                if CandidateBin = '' then
                    CandidateBin := WhseReceiptLine."Bin Code"
                else
                    if CandidateBin <> WhseReceiptLine."Bin Code" then
                        exit('');
            until WhseReceiptLine.Next() = 0;
        exit(CandidateBin);
    end;

    local procedure BindLpToReceiptBin(var LP: Record "DOPSWHS LP Header"; WhseReceiptLine: Record "Warehouse Receipt Line")
    var
        Location: Record Location;
    begin
        if LP."Location Code" <> WhseReceiptLine."Location Code" then
            Error(
                '%1 LP''si %2 lokasyonundadır; %3 lokasyonundaki mal kabul satırına eklenemez.',
                LP."No.", LP."Location Code", WhseReceiptLine."Location Code");

        if WhseReceiptLine."Bin Code" = '' then begin
            if Location.Get(WhseReceiptLine."Location Code") and Location."Bin Mandatory" then
                Error(
                    '%1 LP''sini mal kabulde kullanmak için önce depo gözünü okutun veya satırdaki Depo Gözü alanını doldurun.',
                    LP."No.");
            exit;
        end;

        if LP."Bin Code" = '' then begin
            LP.Validate("Bin Code", WhseReceiptLine."Bin Code");
            LP.Modify(true);
            exit;
        end;

        if LP."Bin Code" <> WhseReceiptLine."Bin Code" then
            Error(
                '%1 LP''si %2 gözündedir; %3 gözündeki mal kabul satırı aynı LP''ye eklenemez.',
                LP."No.", LP."Bin Code", WhseReceiptLine."Bin Code");
    end;

    /// <summary>
    /// Mal kabul paleti tek ürün + varyant + lot/seri kimliği taşır. Böylece
    /// farklı ürün veya lotlar aynı aktif LP'ye sessizce karışmaz; operatör
    /// mevcut LP'yi kapatıp sonraki fiziksel paleti başlatır.
    /// </summary>
    local procedure EnsureReceiptLpIdentity(LP: Record "DOPSWHS LP Header"; WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if (LPLine."Item No." <> WhseReceiptLine."Item No.") or
                   (LPLine."Variant Code" <> WhseReceiptLine."Variant Code") or
                   (LPLine."Lot No." <> LotNo) or
                   (LPLine."Serial No." <> SerialNo)
                then
                    Error(
                        '%1 LP''si %2 ürünü / %3 lotu için açılmıştır. Farklı ürün veya lot için LP''yi kapatıp yeni LP başlatın.',
                        LP."No.", LPLine."Item No.", LPLine."Lot No.");
            until LPLine.Next() = 0;
    end;

    local procedure EnsureReceiptExpirationDatesNotPast(WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LotNo: Code[50];
        SerialNo: Code[50];
        ExpiryDate: Date;
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.SetFilter("Qty. to Receive", '>0');
        if WhseReceiptLine.FindSet() then
            repeat
                if ReceiptLineUsesExpirationDates(WhseReceiptLine) then begin
                    GetItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate);
                    if (ExpiryDate <> 0D) and (ExpiryDate < Today) then
                        Error(
                            'Mal kabul kaydedilemez. %1 ürününün %2 lotu geçmiş son kullanma tarihlidir: %3.',
                            WhseReceiptLine."Item No.", LotNo, ExpiryDate);
                end;
            until WhseReceiptLine.Next() = 0;
    end;

    [TryFunction]
    local procedure TryPrintCombinedMteLabel(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50])
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintPalletItemLabels(LP, PrinterId, 1);
    end;

    /// <summary>
    /// Operatörün açık "Lot No Ata" komutuyla Item kartındaki Lot Nos.
    /// serisinden yeni bir iç lot üretir. Satırı okumak veya miktarı açmak bu
    /// metodu çağırmaz. Var olan BC item-tracking lotu varsa aynen döndürülür.
    /// Takip kaydı miktar/SKT/tedarikçi lotu birlikte onaylanana kadar yazılmaz.
    /// Üretilen numara ise satırda bekleyen lot olarak tutulur; ekran kapanır
    /// veya sonraki işlem hata verirse aynı numara yeniden döndürülür.
    /// </summary>
    procedure AssignInboundLotNo(WhseReceiptLine: Record "Warehouse Receipt Line"): Text
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        LotSerialGen: Codeunit "DOPSWHS Lot Serial Generator";
        LotNo: Code[50];
        SerialNo: Code[50];
        ExpiryDate: Date;
    begin
        GetItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate);
        if LotNo <> '' then
            exit(LotNo);

        Item.Get(WhseReceiptLine."Item No.");
        if (Item."Item Tracking Code" = '') or
           (not ItemTrackingCode.Get(Item."Item Tracking Code")) or
           (not RequiresLotTracking(ItemTrackingCode))
        then
            Error('%1 ürünü lot takipli değildir.', WhseReceiptLine."Item No.");

        LotNo := LotSerialGen.GenerateLotNoForItem(WhseReceiptLine."Item No.");
        if LotNo = '' then
            Error(
                '%1 ürünü için Lot Nos. numara serisi tanımlı değildir. Ürün kartındaki Lot Nos. alanını kontrol edin.',
                WhseReceiptLine."Item No.");
        WhseReceiptLine."DOPSWHS Pending Lot No." := LotNo;
        WhseReceiptLine.Modify(true);
        exit(LotNo);
    end;

    /// <summary>Tedarikçi lotu isteğe bağlıdır; girilmişse iç lotla ilişkilendirilir.</summary>
    procedure ReceiptLineRequiresSupplierLot(WhseReceiptLine: Record "Warehouse Receipt Line"): Boolean
    begin
        exit(false);
    end;

    /// <summary>Satırdaki ürünün lot takibi gerektirip gerektirmediğini döndürür.</summary>
    procedure ReceiptLineRequiresLot(WhseReceiptLine: Record "Warehouse Receipt Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not GetReceiptLineTrackingCode(WhseReceiptLine, Item, ItemTrackingCode) then
            exit(false);
        exit(RequiresLotTracking(ItemTrackingCode));
    end;

    /// <summary>Satırdaki ürünün seri takibi gerektirip gerektirmediğini döndürür.</summary>
    procedure ReceiptLineRequiresSerial(WhseReceiptLine: Record "Warehouse Receipt Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not GetReceiptLineTrackingCode(WhseReceiptLine, Item, ItemTrackingCode) then
            exit(false);
        exit(RequiresSerialTracking(ItemTrackingCode));
    end;

    /// <summary>Satırdaki takip kodunda son kullanma tarihinin kullanıldığını döndürür.</summary>
    procedure ReceiptLineUsesExpirationDates(WhseReceiptLine: Record "Warehouse Receipt Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not GetReceiptLineTrackingCode(WhseReceiptLine, Item, ItemTrackingCode) then
            exit(false);
        exit(ItemTrackingCode."Use Expiration Dates");
    end;

    /// <summary>Satırdaki takip kodunda SKT girişinin zorunlu olduğunu döndürür.</summary>
    procedure ReceiptLineRequiresExpirationDate(WhseReceiptLine: Record "Warehouse Receipt Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not GetReceiptLineTrackingCode(WhseReceiptLine, Item, ItemTrackingCode) then
            exit(false);
        exit(ItemTrackingCode."Man. Expir. Date Entry Reqd.");
    end;

    /// <summary>
    /// İç lot numarasına bağlı tedarikçi lotunu Lot No. Information
    /// Description alanından okur. BadeProduction mevcut Tedarikçi Lotu alanı
    /// olarak bu standart alanı kullanır; mobil istemci de aynı kaynağı kullanmalıdır.
    /// </summary>
    procedure GetSupplierLot(WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; var SupplierLotNo: Code[50])
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        Clear(SupplierLotNo);
        if LotNo = '' then
            exit;
        // BADE'nin Madde İzleme Satırlarındaki Tedarikçi Lotu kolonu
        // Reservation Entry uzantısından beslenir. İki ekranın aynı
        // değeri göstermesi için önce gerçek takip kaydını oku.
        GetSupplierLotFromReservation(WhseReceiptLine, LotNo, SupplierLotNo);
        if SupplierLotNo <> '' then
            exit;
        if LotNoInformation.Get(WhseReceiptLine."Item No.", WhseReceiptLine."Variant Code", LotNo) then
            SupplierLotNo := CopyStr(LotNoInformation.Description, 1, MaxStrLen(SupplierLotNo));
    end;

    local procedure GetSupplierLotFromReservation(WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; var SupplierLotNo: Code[50])
    var
        ReservationEntry: Record "Reservation Entry";
        ReservationRef: RecordRef;
        CandidateField: FieldRef;
        FieldIndex: Integer;
    begin
        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        ReservationEntry.SetRange("Lot No.", LotNo);
        if not ReservationEntry.FindFirst() then
            exit;

        ReservationRef.GetTable(ReservationEntry);
        for FieldIndex := 1 to ReservationRef.FieldCount do begin
            CandidateField := ReservationRef.FieldIndex(FieldIndex);
            if IsSupplierLotField(CandidateField) then begin
                SupplierLotNo := CopyStr(Format(CandidateField.Value), 1, MaxStrLen(SupplierLotNo));
                exit;
            end;
        end;
    end;

    local procedure PersistSupplierLot(ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SupplierLotNo: Code[50])
    var
        LotNoInformation: Record "Lot No. Information";
    begin
        if LotNo = '' then
            Error('Tedarikçi lotu %1 kaydedilemedi; iç lot numarası boş.', SupplierLotNo);

        if not LotNoInformation.Get(ItemNo, VariantCode, LotNo) then begin
            LotNoInformation.Init();
            LotNoInformation."Item No." := ItemNo;
            LotNoInformation."Variant Code" := VariantCode;
            LotNoInformation."Lot No." := LotNo;
            LotNoInformation.Insert(true);
        end;

        if (LotNoInformation.Description <> '') and
           (LotNoInformation.Description <> SupplierLotNo)
        then
            Error(
                '%1 iç lotu daha önce %2 tedarikçi lotuyla eşleştirilmiş. Girilen değer: %3.',
                LotNo, LotNoInformation.Description, SupplierLotNo);

        if LotNoInformation.Description <> SupplierLotNo then begin
            LotNoInformation.Validate(Description, SupplierLotNo);
            LotNoInformation.Modify(true);
        end;
    end;

    /// <summary>
    /// Warehouse Receipt Line'ın lot/seri/SKT bilgisini BC'nin Item Tracking
    /// mekanizmasına yazar. Warehouse Receipt satırında Lot No. alanı yoktur;
    /// BC'nin Item Tracking Lines ekranı kaynak Purchase Line'ın Reservation
    /// Entry kayıtlarını gösterir. Idempotent: aynı kaynak satırın önceki
    /// takip kayıtları silinip yeniden yazılır.
    /// </summary>
    local procedure PersistItemTracking(WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; SupplierLotNo: Code[50])
    var
        CreateReservEntry: Codeunit "Create Reserv. Entry";
        ReservationEntry: Record "Reservation Entry";
        SourceSubtype: Integer;
    begin
        DeleteSourceReservationTracking(WhseReceiptLine);
        DeleteWarehouseItemTracking(WhseReceiptLine);

        if (LotNo = '') and (SerialNo = '') then
            exit;
        if WhseReceiptLine."Qty. to Receive" = 0 then
            exit;

        SourceSubtype := WhseReceiptLine."Source Subtype";
        ReservationEntry.Init();
        ReservationEntry."Lot No." := LotNo;
        ReservationEntry."Serial No." := SerialNo;
        CreateReservEntry.SetDates(0D, ExpiryDate);
        CreateReservEntry.SetQtyToHandleAndInvoice(WhseReceiptLine."Qty. to Receive (Base)", WhseReceiptLine."Qty. to Receive (Base)");
        CreateReservEntry.CreateReservEntryFor(
            WhseReceiptLine."Source Type",
            SourceSubtype,
            WhseReceiptLine."Source No.",
            '',
            0,
            WhseReceiptLine."Source Line No.",
            WhseReceiptLine."Qty. per Unit of Measure",
            WhseReceiptLine."Qty. to Receive",
            WhseReceiptLine."Qty. to Receive (Base)",
            ReservationEntry);
        CreateReservEntry.CreateEntry(
            WhseReceiptLine."Item No.",
            WhseReceiptLine."Variant Code",
            WhseReceiptLine."Location Code",
            WhseReceiptLine.Description,
            WhseReceiptLine."Due Date",
            0D,
            0,
            Enum::"Reservation Status"::Surplus);

        if SupplierLotNo <> '' then
            PersistSupplierLotOnReservation(WhseReceiptLine, LotNo, SerialNo, SupplierLotNo);
    end;

    /// <summary>Adds one purchase-source tracking allocation without deleting the other lots.</summary>
    local procedure PersistItemTrackingEntry(WhseReceiptLine: Record "Warehouse Receipt Line"; Quantity: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; SupplierLotNo: Code[50])
    var
        CreateReservEntry: Codeunit "Create Reserv. Entry";
        ReservationEntry: Record "Reservation Entry";
        QuantityBase: Decimal;
        SourceSubtype: Integer;
    begin
        if (LotNo = '') and (SerialNo = '') then
            exit;
        QuantityBase := Round(Quantity * WhseReceiptLine."Qty. per Unit of Measure", 0.00001);
        SourceSubtype := WhseReceiptLine."Source Subtype";
        ReservationEntry.Init();
        ReservationEntry."Lot No." := LotNo;
        ReservationEntry."Serial No." := SerialNo;
        CreateReservEntry.SetDates(0D, ExpiryDate);
        CreateReservEntry.SetQtyToHandleAndInvoice(QuantityBase, QuantityBase);
        CreateReservEntry.CreateReservEntryFor(
            WhseReceiptLine."Source Type",
            SourceSubtype,
            WhseReceiptLine."Source No.",
            '',
            0,
            WhseReceiptLine."Source Line No.",
            WhseReceiptLine."Qty. per Unit of Measure",
            Quantity,
            QuantityBase,
            ReservationEntry);
        CreateReservEntry.CreateEntry(
            WhseReceiptLine."Item No.",
            WhseReceiptLine."Variant Code",
            WhseReceiptLine."Location Code",
            WhseReceiptLine.Description,
            WhseReceiptLine."Due Date",
            0D,
            0,
            Enum::"Reservation Status"::Surplus);

        if SupplierLotNo <> '' then
            PersistSupplierLotOnReservation(WhseReceiptLine, LotNo, SerialNo, SupplierLotNo);
    end;

    /// <summary>
    /// BC's warehouse posting selects only the first receipt line for a purchase
    /// source line. A bulk LP receipt must therefore have a matching technical
    /// purchase line for every technical warehouse line. They all remain under
    /// the same purchase order and are posted in one warehouse receipt action.
    /// </summary>
    local procedure PrepareBulkReceiptPurchaseLines(ReceiptNo: Code[20])
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ProcessedGroups: Dictionary of [Text, Boolean];
        GroupKey: Text;
    begin
        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        if ReceiptLine.FindSet() then
            repeat
                GroupKey := ReceiptLine."Source No." + '|' + Format(ReceiptLine."Source Line No.");
                if not ProcessedGroups.ContainsKey(GroupKey) then begin
                    ProcessedGroups.Add(GroupKey, true);
                    if IsBulkReceiptSourceGroup(
                        ReceiptNo, ReceiptLine."Source No.", ReceiptLine."Source Line No.")
                    then
                        SplitBulkReceiptPurchaseSource(
                            ReceiptNo, ReceiptLine."Source No.", ReceiptLine."Source Line No.");
                end;
            until ReceiptLine.Next() = 0;
    end;

    local procedure IsBulkReceiptSourceGroup(ReceiptNo: Code[20]; SourceNo: Code[20]; SourceLineNo: Integer): Boolean
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        LineCount: Integer;
        HasLp: Boolean;
    begin
        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        ReceiptLine.SetRange("Source No.", SourceNo);
        ReceiptLine.SetRange("Source Line No.", SourceLineNo);
        if ReceiptLine.FindSet() then
            repeat
                LineCount += 1;
                HasLp := HasLp or (ReceiptLine."DOPSWHS LP No." <> '');
            until ReceiptLine.Next() = 0;
        exit(HasLp and (LineCount > 1));
    end;

    local procedure SplitBulkReceiptPurchaseSource(ReceiptNo: Code[20]; SourceNo: Code[20]; SourceLineNo: Integer)
    var
        PurchaseHeader: Record "Purchase Header";
        SourcePurchaseLine: Record "Purchase Line";
        TemplatePurchaseLine: Record "Purchase Line";
        NewPurchaseLine: Record "Purchase Line";
        ReceiptLine: Record "Warehouse Receipt Line";
        AnchorReceiptLine: Record "Warehouse Receipt Line";
        PurchaseRelease: Codeunit "Release Purchase Document";
        NewSourceLineNo: Integer;
    begin
        SourcePurchaseLine.Get(SourcePurchaseLine."Document Type"::Order, SourceNo, SourceLineNo);
        TemplatePurchaseLine := SourcePurchaseLine;
        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, SourceNo);

        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        ReceiptLine.SetRange("Source No.", SourceNo);
        ReceiptLine.SetRange("Source Line No.", SourceLineNo);
        if not ReceiptLine.FindFirst() then
            exit;
        AnchorReceiptLine := ReceiptLine;

        // Remove the old aggregate tracking before shrinking the source line.
        DeleteSourceReservationTracking(AnchorReceiptLine);
        if PurchaseHeader.Status <> PurchaseHeader.Status::Open then begin
            PurchaseRelease.Reopen(PurchaseHeader);
        end;

        SourcePurchaseLine.Validate(Quantity, AnchorReceiptLine.Quantity);
        SourcePurchaseLine.Validate("Qty. to Receive", 0);
        SourcePurchaseLine.Modify(true);

        if ReceiptLine.FindSet(true) then
            repeat
                if ReceiptLine."Line No." <> AnchorReceiptLine."Line No." then begin
                    NewSourceLineNo := AvailablePurchaseLineNo(
                        SourcePurchaseLine."Document Type", SourceNo, ReceiptLine."Line No.");
                    InsertBulkPurchaseLine(
                        TemplatePurchaseLine, NewPurchaseLine, NewSourceLineNo,
                        ReceiptLine.Quantity);
                    ReceiptLine."Source Line No." := NewSourceLineNo;
                    ReceiptLine.Modify(true);
                end;
            until ReceiptLine.Next() = 0;

        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, SourceNo);
        PurchaseRelease.ReleasePurchaseHeader(PurchaseHeader, false);
    end;

    local procedure AvailablePurchaseLineNo(DocumentType: Enum "Purchase Document Type"; DocumentNo: Code[20]; PreferredLineNo: Integer): Integer
    var
        PurchaseLine: Record "Purchase Line";
    begin
        if (PreferredLineNo > 0) and
           (not PurchaseLine.Get(DocumentType, DocumentNo, PreferredLineNo))
        then
            exit(PreferredLineNo);

        PurchaseLine.Reset();
        PurchaseLine.SetRange("Document Type", DocumentType);
        PurchaseLine.SetRange("Document No.", DocumentNo);
        if PurchaseLine.FindLast() then
            exit(PurchaseLine."Line No." + 10000);
        exit(10000);
    end;

    local procedure InsertBulkPurchaseLine(TemplateLine: Record "Purchase Line"; var NewLine: Record "Purchase Line"; LineNo: Integer; Quantity: Decimal)
    begin
        Clear(NewLine);
        NewLine.Init();
        NewLine."Document Type" := TemplateLine."Document Type";
        NewLine."Document No." := TemplateLine."Document No.";
        NewLine."Line No." := LineNo;
        NewLine.Insert(true);
        NewLine.Validate(Type, TemplateLine.Type);
        NewLine.Validate("No.", TemplateLine."No.");
        if TemplateLine."Variant Code" <> '' then
            NewLine.Validate("Variant Code", TemplateLine."Variant Code");
        if TemplateLine."Location Code" <> '' then
            NewLine.Validate("Location Code", TemplateLine."Location Code");
        if TemplateLine."Bin Code" <> '' then
            // Bin validation checks for an already-linked warehouse receipt.
            // The matching receipt line is linked immediately after this helper,
            // so copy the source bin now and let posting perform the final check.
            NewLine."Bin Code" := TemplateLine."Bin Code";
        if (TemplateLine."Unit of Measure Code" <> '') and
           (NewLine."Unit of Measure Code" <> TemplateLine."Unit of Measure Code")
        then
            NewLine.Validate("Unit of Measure Code", TemplateLine."Unit of Measure Code");
        NewLine.Validate(Quantity, Quantity);
        NewLine.Validate("Direct Unit Cost", TemplateLine."Direct Unit Cost");
        NewLine.Validate("Line Discount %", TemplateLine."Line Discount %");
        NewLine."Dimension Set ID" := TemplateLine."Dimension Set ID";
        NewLine."Shortcut Dimension 1 Code" := TemplateLine."Shortcut Dimension 1 Code";
        NewLine."Shortcut Dimension 2 Code" := TemplateLine."Shortcut Dimension 2 Code";
        NewLine."Expected Receipt Date" := TemplateLine."Expected Receipt Date";
        NewLine."Requested Receipt Date" := TemplateLine."Requested Receipt Date";
        NewLine."Promised Receipt Date" := TemplateLine."Promised Receipt Date";
        NewLine.Modify(true);
    end;

    /// <summary>
    /// Repairs both newly-created and pre-upgrade LP receipt lines just before
    /// posting by rebuilding each purchase-source tracking entry from its LP.
    /// </summary>
    local procedure PrepareLpReceiptTracking(ReceiptNo: Code[20])
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        LPLine: Record "DOPSWHS LP Line";
        SupplierLotNo: Code[50];
    begin
        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetFilter("Qty. to Receive", '>0');
        ReceiptLine.SetFilter("DOPSWHS LP No.", '<>%1', '');
        if ReceiptLine.FindSet() then
            repeat
                DeleteSourceReservationTracking(ReceiptLine);
            until ReceiptLine.Next() = 0;

        ReceiptLine.Reset();
        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetFilter("Qty. to Receive", '>0');
        if ReceiptLine.FindSet() then
            repeat
                if ReceiptLine."DOPSWHS LP No." <> '' then begin
                    LPLine.Reset();
                    LPLine.SetRange("LP No.", ReceiptLine."DOPSWHS LP No.");
                    LPLine.SetRange("Item No.", ReceiptLine."Item No.");
                    LPLine.SetRange("Variant Code", ReceiptLine."Variant Code");
                    LPLine.SetFilter(Quantity, '>0');
                    if not LPLine.FindFirst() then
                        Error(
                            '%1 LP''sinde %2 ürünü için kabul miktarı bulunamadı.',
                            ReceiptLine."DOPSWHS LP No.", ReceiptLine."Item No.");
                    if Abs(LPLine.Quantity - ReceiptLine."Qty. to Receive") > 0.00001 then
                        Error(
                            '%1 LP miktarı (%2), mal kabul satırı miktarına (%3) eşit değil.',
                            ReceiptLine."DOPSWHS LP No.", LPLine.Quantity, ReceiptLine."Qty. to Receive");
                    GetSupplierLot(ReceiptLine, LPLine."Lot No.", SupplierLotNo);
                    PersistItemTrackingEntry(
                        ReceiptLine, ReceiptLine."Qty. to Receive", LPLine."Lot No.",
                        LPLine."Serial No.", LPLine."Expiration Date", SupplierLotNo);
                end;
            until ReceiptLine.Next() = 0;
    end;

    local procedure BulkJsonText(RowObject: JsonObject; PropertyName: Text): Text
    var
        ValueToken: JsonToken;
    begin
        if not RowObject.Get(PropertyName, ValueToken) then
            exit('');
        if ValueToken.AsValue().IsNull() then
            exit('');
        exit(ValueToken.AsValue().AsText());
    end;

    local procedure PersistSupplierLotOnReservation(WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; SerialNo: Code[50]; SupplierLotNo: Code[50])
    var
        ReservationEntry: Record "Reservation Entry";
    begin
        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        if LotNo <> '' then
            ReservationEntry.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            ReservationEntry.SetRange("Serial No.", SerialNo);
        if ReservationEntry.FindSet(true) then
            repeat
                SetSupplierLotField(ReservationEntry, SupplierLotNo);
            until ReservationEntry.Next() = 0;
    end;

    local procedure SyncSupplierLotsToReservations(WhseReceiptHeader: Record "Warehouse Receipt Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        LotNo: Code[50];
        SerialNo: Code[50];
        SupplierLotNo: Code[50];
        ExpiryDate: Date;
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.SetFilter("Qty. to Receive", '>0');
        if WhseReceiptLine.FindSet() then
            repeat
                GetItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate);
                GetSupplierLot(WhseReceiptLine, LotNo, SupplierLotNo);
                if (LotNo <> '') and (SupplierLotNo <> '') then
                    PersistSupplierLotOnReservation(WhseReceiptLine, LotNo, SerialNo, SupplierLotNo);
            until WhseReceiptLine.Next() = 0;
    end;

    local procedure SetSupplierLotField(var ReservationEntry: Record "Reservation Entry"; SupplierLotNo: Code[50])
    var
        ReservationRef: RecordRef;
        CandidateField: FieldRef;
        ExistingValue: Text;
        FieldIndex: Integer;
    begin
        ReservationRef.GetTable(ReservationEntry);
        for FieldIndex := 1 to ReservationRef.FieldCount do begin
            CandidateField := ReservationRef.FieldIndex(FieldIndex);
            if IsSupplierLotField(CandidateField) then begin
                ExistingValue := Format(CandidateField.Value);
                if (ExistingValue <> '') and (ExistingValue <> SupplierLotNo) then
                    Error(
                        'Tedarikçi lotu takip satırında zaten %1 olarak kayıtlı. Girilen değer: %2.',
                        ExistingValue, SupplierLotNo);
                if ExistingValue = '' then begin
                    CandidateField.Validate(CopyStr(SupplierLotNo, 1, CandidateField.Length));
                    ReservationRef.Modify(true);
                    ReservationRef.SetTable(ReservationEntry);
                end;
                exit;
            end;
        end;
    end;

    local procedure IsSupplierLotField(CandidateField: FieldRef): Boolean
    begin
        if not (CandidateField.Type in [FieldType::Code, FieldType::Text]) then
            exit(false);
        exit(
            (CandidateField.Name = 'Tedarikçi Lotu') or
            (CandidateField.Caption = 'Tedarikçi Lotu') or
            (CandidateField.Name = 'Tedarikci Lotu') or
            (CandidateField.Caption = 'Tedarikci Lotu') or
            (CandidateField.Name = 'Supplier Lot') or
            (CandidateField.Caption = 'Supplier Lot') or
            (CandidateField.Name = 'Supplier Lot No.') or
            (CandidateField.Caption = 'Supplier Lot No.') or
            (CandidateField.Name = 'Vendor Lot No.') or
            (CandidateField.Caption = 'Vendor Lot No.'));
    end;

    /// <summary>
    /// BC UI'dan (veya önceki bir mobil kayıttan) satıra zaten atanmış lot/seri/SKT
    /// varsa okur — mobil GET çağrısında bu bilgi boş dönmesin diye.
    /// </summary>
    procedure GetItemTracking(WhseReceiptLine: Record "Warehouse Receipt Line"; var LotNo: Code[50]; var SerialNo: Code[50]; var ExpiryDate: Date)
    var
        ReservationEntry: Record "Reservation Entry";
        WhseItemTrkgLine: Record "Whse. Item Tracking Line";
    begin
        Clear(LotNo);
        Clear(SerialNo);
        Clear(ExpiryDate);

        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        ReservationEntry.SetFilter("Lot No.", '<>%1', '');
        if ReservationEntry.FindFirst() then begin
            LotNo := ReservationEntry."Lot No.";
            SerialNo := ReservationEntry."Serial No.";
            ExpiryDate := ReservationEntry."Expiration Date";
        end else begin
            ReservationEntry.Reset();
            SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
            ReservationEntry.SetFilter("Serial No.", '<>%1', '');
            if ReservationEntry.FindFirst() then begin
                LotNo := ReservationEntry."Lot No.";
                SerialNo := ReservationEntry."Serial No.";
                ExpiryDate := ReservationEntry."Expiration Date";
            end else begin
                WhseItemTrkgLine.SetRange("Source Type", Database::"Warehouse Receipt Line");
                WhseItemTrkgLine.SetRange("Source ID", WhseReceiptLine."No.");
                WhseItemTrkgLine.SetRange("Source Ref. No.", WhseReceiptLine."Line No.");
                if WhseItemTrkgLine.FindFirst() then begin
                    LotNo := WhseItemTrkgLine."Lot No.";
                    SerialNo := WhseItemTrkgLine."Serial No.";
                    ExpiryDate := WhseItemTrkgLine."Expiration Date";
                end;
            end;
        end;

        // Gerçek takip kaydı henüz oluşmadıysa, operatörün daha önce ayırdığı
        // lotu döndür. Bu sayede miktar penceresini kapatıp açmak veya başarısız
        // bir kayıttan sonra tekrar "Lot No Ata" demek yeni seri tüketmez.
        if LotNo = '' then
            LotNo := WhseReceiptLine."DOPSWHS Pending Lot No.";
    end;

    local procedure DeleteSourceReservationTracking(WhseReceiptLine: Record "Warehouse Receipt Line")
    var
        ReservationEntry: Record "Reservation Entry";
    begin
        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        ReservationEntry.SetFilter("Lot No.", '<>%1', '');
        ReservationEntry.DeleteAll(true);

        ReservationEntry.Reset();
        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        ReservationEntry.SetFilter("Serial No.", '<>%1', '');
        ReservationEntry.DeleteAll(true);
    end;

    local procedure SetSourceReservationFilters(var ReservationEntry: Record "Reservation Entry"; WhseReceiptLine: Record "Warehouse Receipt Line")
    begin
        ReservationEntry.SetRange("Source Type", WhseReceiptLine."Source Type");
        ReservationEntry.SetRange("Source Subtype", WhseReceiptLine."Source Subtype");
        ReservationEntry.SetRange("Source ID", WhseReceiptLine."Source No.");
        ReservationEntry.SetRange("Source Ref. No.", WhseReceiptLine."Source Line No.");
        ReservationEntry.SetRange("Item No.", WhseReceiptLine."Item No.");
    end;

    local procedure DeleteWarehouseItemTracking(WhseReceiptLine: Record "Warehouse Receipt Line")
    var
        WhseItemTrkgLine: Record "Whse. Item Tracking Line";
    begin
        WhseItemTrkgLine.SetRange("Source Type", Database::"Warehouse Receipt Line");
        WhseItemTrkgLine.SetRange("Source ID", WhseReceiptLine."No.");
        WhseItemTrkgLine.SetRange("Source Ref. No.", WhseReceiptLine."Line No.");
        WhseItemTrkgLine.DeleteAll(true);
    end;

    local procedure RequiresLotTracking(ItemTrackingCode: Record "Item Tracking Code"): Boolean
    begin
        exit(ItemTrackingCode."Lot Specific Tracking" or ItemTrackingCode."Lot Warehouse Tracking" or ItemTrackingCode."Lot Purchase Inbound Tracking");
    end;

    local procedure RequiresSerialTracking(ItemTrackingCode: Record "Item Tracking Code"): Boolean
    begin
        exit(ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking" or ItemTrackingCode."SN Purchase Inbound Tracking");
    end;

    local procedure GetReceiptLineTrackingCode(WhseReceiptLine: Record "Warehouse Receipt Line"; var Item: Record Item; var ItemTrackingCode: Record "Item Tracking Code"): Boolean
    begin
        if not Item.Get(WhseReceiptLine."Item No.") then
            exit(false);
        if Item."Item Tracking Code" = '' then
            exit(false);
        exit(ItemTrackingCode.Get(Item."Item Tracking Code"));
    end;

    local procedure AssignReceiptLPs(ReceiptNo: Code[20]; PostedReceiptNo: Code[20]; HeaderLpNo: Code[20]; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        ReceiptLPLine: Record "DOPSWHS LP Line";
        AssignedLPs: Dictionary of [Code[20], Boolean];
    begin
        // Source metadata is the authoritative many-LP relation. A posted receipt line has
        // only one LP field and cannot represent ten pallets of the same item/lot.
        ReceiptLPLine.SetRange("Source Document Type", ReceiptLPLine."Source Document Type"::WhseReceipt);
        ReceiptLPLine.SetRange("Source Document No.", ReceiptNo);
        ReceiptLPLine.SetFilter(Quantity, '>0');
        if ReceiptLPLine.FindSet() then
            repeat
                if not AssignedLPs.ContainsKey(ReceiptLPLine."LP No.") then begin
                    AssignLP(ReceiptLPLine."LP No.", DocType, DocNo);
                    AssignedLPs.Add(ReceiptLPLine."LP No.", true);
                end;
            until ReceiptLPLine.Next() = 0;

        PostedReceiptLine.SetRange("No.", PostedReceiptNo);
        PostedReceiptLine.SetFilter("LP No.", '<>%1', '');
        if PostedReceiptLine.FindSet() then
            repeat
                // Repeated LP numbers are harmless: AssignLP acts only while
                // the pallet is Built, so the first matching line wins.
                if not AssignedLPs.ContainsKey(PostedReceiptLine."LP No.") then begin
                    AssignLP(PostedReceiptLine."LP No.", DocType, DocNo);
                    AssignedLPs.Add(PostedReceiptLine."LP No.", true);
                end;
            until PostedReceiptLine.Next() = 0;

        // Legacy receipts without line-level LP metadata still retain the
        // active header LP and follow the previous single-pallet behavior.
        if HeaderLpNo <> '' then
            AssignLP(HeaderLpNo, DocType, DocNo);
    end;

    local procedure AssignLP(LpNo: Code[20]; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if not LP.Get(LpNo) then
            exit;
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, DocType, DocNo);
    end;

    /// <summary>
    /// İşlemi yapan operatörü belirler: çağıran kimliğini AÇIKÇA bildirdiyse o,
    /// aksi halde belgeye atanmış kullanıcı. NEDEN: paylaşımlı BC hesabı yüzünden
    /// UserId() operatörü göstermiyor; atama tek güvenilir kaynak.
    /// </summary>
    local procedure EffectiveOperator(OperatorUserId: Code[50]; AssignedUserId: Code[50]): Code[50]
    begin
        if OperatorUserId <> '' then
            exit(OperatorUserId);
        exit(AssignedUserId);
    end;

    /// <summary>Belgeye atanmış operatör — satırdan başlığa GÜNCEL okunur.</summary>
    local procedure ReceiptOperator(ReceiptNo: Code[20]): Code[50]
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
    begin
        if ReceiptNo = '' then
            exit('');
        if not WhseReceiptHeader.Get(ReceiptNo) then
            exit('');
        exit(WhseReceiptHeader."Assigned User ID");
    end;

    local procedure OperatorOrNone(UserIdValue: Code[50]): Text
    begin
        if UserIdValue = '' then
            exit(NoOperatorTxt);
        exit(UserIdValue);
    end;

    /// <summary>
    /// İşlemi YAPAN operatörle birlikte loglar. Operatör parametresi BİLEREK
    /// zorunlu: her çağrı yeri "kim yaptı" sorusuna cevap vermek zorunda kalsın.
    /// Bilinmiyorsa açıkça '' geçilir (telemetri 'actorSource=BC' yazar).
    /// </summary>
    local procedure Log(Category: Text; Message: Text; OperatorUserId: Code[50])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, Message, OperatorUserId);
    end;

    var
        // Telemetri mesajları çevrilmez (Locked): log sorguları dile göre değişmemeli.
        AssignLogTxt: Label '%1 -> %2', Locked = true;
        NoOperatorTxt: Label '(none)', Locked = true;
        VehicleInfoLogTxt: Label '%1 plate=%2 driver=%3', Locked = true;
        VehiclePlateFieldTok: Label 'Vehicle Plate No', Locked = true;
        DriverCodeFieldTok: Label 'Driver Code', Locked = true;
        VendorShipmentFieldTok: Label 'Vendor Shipment No.', Locked = true;
        VehicleDriverTableTok: Label 'BADE Vehicle Driver', Locked = true;
        PlateTxt: Label 'plaka';
        DriverTxt: Label 'sürücü';
        AndTxt: Label 've';
        VehicleInfoMissingErr: Label 'Araç bilgileri eksik (%1). Terminalde "Araç / Sürücü" kartından girip tekrar kaydedin.', Comment = '%1 = eksik alanlar';
        VehicleInfoUnsupportedErr: Label 'Bu şirkette mal kabul başlığında araç alanları tanımlı değil.';
}
