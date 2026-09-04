codeunit 72046 "DOPSWHS Pick Mgmt"
{
    Access = Public;

    procedure AssignToMe(var Pick: Record "Warehouse Activity Header")
    var
        CurrentUserId: Code[50];
    begin
        // Terminalde WMS oturumu yoksa operatör BC hesabı olarak üstlenir.
        // İş kuralı kontrolü ClaimPick'te: pick başkasındaysa reddedilir.
        CurrentUserId := CopyStr(UserId(), 1, MaxStrLen(CurrentUserId));
        ClaimPick(Pick, CurrentUserId, SelfClaimReasonLbl);
    end;

    /// <summary>
    /// Bir toplamayı ÜSTLENME (self-claim). İş kuralı: toplama ya boşta olmalı ya
    /// da zaten aynı operatörde olmalı; başkasındaysa reddedilir. Yönetici zorla
    /// devretmek isterse ReassignPick kullanır (o yol bilerek açık bırakıldı).
    ///
    /// NEDEN kilitli yeniden okuma: sayfadan/API'den gelen Rec, karar anından
    /// önce okunmuş olabilir (stale). İki terminal aynı anda "Üzerime Al" derse
    /// ikisi de "boşta" görüp yazar ve son yazan kazanırdı. LockTable + Get ile
    /// karar GÜNCEL satır üzerinde ve kilit altında verilir; ikinci operatör
    /// hata alır. BC'nin kendi Modify çakışması bu senaryoyu yakalamaz, çünkü
    /// her iki yazma da teknik olarak geçerlidir.
    /// </summary>
    procedure ClaimPick(var Pick: Record "Warehouse Activity Header"; RequestedUserId: Code[50]; Reason: Text[250])
    var
        LockedPick: Record "Warehouse Activity Header";
        CurrentOwner: Code[50];
    begin
        EnsurePick(Pick);
        if RequestedUserId = '' then
            RequestedUserId := CopyStr(UserId(), 1, MaxStrLen(RequestedUserId));

        LockedPick.LockTable();
        if not LockedPick.Get(LockedPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");

        CurrentOwner := LockedPick."Assigned User ID";
        if (CurrentOwner <> '') and (CurrentOwner <> RequestedUserId) then
            Error(PickTakenErr, Pick."No.", OperatorLabel(CurrentOwner));

        if CurrentOwner = RequestedUserId then begin
            // Zaten kendisinde: terminal aynı butona iki kez basabilir, hata verme.
            Pick := LockedPick;
            exit;
        end;

        // Bkz. ReassignPick: WMS operatörü Warehouse Employee olmayabilir; ilişki
        // doğrulamasını tetiklemeden doğrudan yaz ki atama kalıcı olsun.
        LockedPick."Assigned User ID" := RequestedUserId;
        LockedPick.Modify(true);
        Pick := LockedPick;

        // Üstlenmeyi yapan = üstlenen operatörün kendisi; geçmiş ve telemetri
        // paylaşımlı BC hesabını değil bu kimliği göstermeli.
        LogAssignment(Pick."No.", '', RequestedUserId, Reason, RequestedUserId);
        SyncPickingOrderAssignment(Pick."No.", RequestedUserId);
        // Webhook bilerek tetiklenmiyor: bildirim "işin elinden alındı" anlamı
        // taşıyor; boştaki bir işi üstlenmek kimseyi ilgilendirmiyor.
        Log('Pick.Claim', Pick."No.", RequestedUserId);
    end;

    /// <summary>
    /// Terminalden gelen İŞLEM çağrıları için sahiplik kontrolü (satır onayı,
    /// LP başlatma, tote bağlama, register). Toplama atanmamışsa ya da doğrulanabilir
    /// biçimde başka bir kullanıcıdaysa hata verir.
    /// </summary>
    procedure EnsurePickOperator(var Pick: Record "Warehouse Activity Header")
    var
        FreshPick: Record "Warehouse Activity Header";
    begin
        EnsurePick(Pick);
        // Güncel atama veritabanından okunur: terminaldeki kopya, sorumlu belgeyi
        // devrettikten sonra da eski sahibi gösteriyor olabilir.
        if not FreshPick.Get(FreshPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");
        CheckOwnership(FreshPick."No.", FreshPick."Assigned User ID");
    end;

    /// <summary>Operatörü ekranda okunur biçimde yazar: "Ahmet Yılmaz (AHMET)".</summary>
    procedure OperatorLabel(UserIdValue: Code[50]): Text
    var
        LocalUser: Record "DOPSWHS Local User";
    begin
        if UserIdValue = '' then
            exit(UnassignedLbl);
        if StrLen(UserIdValue) <= MaxStrLen(LocalUser.Username) then
            if LocalUser.Get(CopyStr(UserIdValue, 1, MaxStrLen(LocalUser.Username))) then
                if LocalUser."Display Name" <> '' then
                    exit(StrSubstNo('%1 (%2)', LocalUser."Display Name", UserIdValue));
        exit(UserIdValue);
    end;

    /// <summary>
    /// ZORUNLU ATAMA + sahiplik kuralı. Çağıranın kimliği bilinmiyorsa (paylaşımlı
    /// BC hesabı) elde olan tek kimlik UserId()'dir.
    /// </summary>
    local procedure CheckOwnership(PickNo: Code[20]; Owner: Code[50])
    begin
        // Atanmamış toplama terminalden işlenemez: aksi halde iki operatör aynı
        // belgede paralel çalışıp aynı satırı iki kez toplayabiliyordu.
        if Owner = '' then
            Error(PickUnassignedErr, PickNo);
        if Owner = UserId() then
            exit;
        // Paylaşımlı BC hesabı gerçeği: terminal operatörleri "DOPSWHS Local User"
        // olarak oturum açar, BC'ye ise ortak bir AAD hesabıyla bağlanır. Atama bir
        // yerel kullanıcıdaysa sunucu, isteği gerçekten O operatörün gönderip
        // göndermediğini DOĞRULAYAMAZ; yanlış yere iş durdurmamak için geçilir.
        // Asıl koruma üstlenme anındadır (ClaimPick) — orada ikinci operatör
        // zaten reddedilir. Kimliği taşıyan istemciler ConfirmPickLineFor ile
        // tam (strict) kontrole girer.
        if IsLocalOperator(Owner) then
            exit;
        Error(PickOwnedByOtherErr, PickNo, OperatorLabel(Owner));
    end;

    /// <summary>Çağıranın kimliği BİLİNİYORSA uygulanan tam kontrol.</summary>
    local procedure CheckOwnershipFor(PickNo: Code[20]; Owner: Code[50]; RequestingUserId: Code[50])
    begin
        if Owner = '' then
            Error(PickUnassignedErr, PickNo);
        if Owner = RequestingUserId then
            exit;
        Error(PickOwnedByOtherErr, PickNo, OperatorLabel(Owner));
    end;

    /// <summary>Satırın bağlı olduğu toplama başlığı üzerinden sahiplik kontrolü.</summary>
    local procedure CheckLineOwnership(var PickLine: Record "Warehouse Activity Line"; RequestingUserId: Code[50])
    var
        PickHeader: Record "Warehouse Activity Header";
    begin
        if not PickHeader.Get(PickHeader.Type::Pick, PickLine."No.") then
            Error(PickGoneErr, PickLine."No.");
        if RequestingUserId = '' then
            CheckOwnership(PickHeader."No.", PickHeader."Assigned User ID")
        else
            CheckOwnershipFor(PickHeader."No.", PickHeader."Assigned User ID", RequestingUserId);
    end;

    local procedure IsLocalOperator(UserIdValue: Code[50]): Boolean
    var
        LocalUser: Record "DOPSWHS Local User";
    begin
        if UserIdValue = '' then
            exit(false);
        // Code[50] değer Username'e (Code[20]) sığmıyorsa yerel kullanıcı olamaz;
        // CopyStr ile kırpıp yanlış eşleşme üretmeyelim.
        if StrLen(UserIdValue) > MaxStrLen(LocalUser.Username) then
            exit(false);
        exit(LocalUser.Get(CopyStr(UserIdValue, 1, MaxStrLen(LocalUser.Username))));
    end;

    /// <summary>
    /// Atama geçmişi. PerformedByUserId = işlemi FİİLEN yapan kimlik; boş
    /// bırakılırsa oturumun BC hesabına düşülür.
    ///
    /// NEDEN ayrı parametre: terminalden gelen bütün çağrılar paylaşımlı servis
    /// hesabıyla geldiği için "Reassigned By" her satırda aynı hesabı (DYNOPS)
    /// yazıyordu; kimin üstlendiği geçmişten okunamıyordu.
    /// </summary>
    local procedure LogAssignment(PickNo: Code[20]; FromUserId: Code[50]; ToUserId: Code[50]; Reason: Text[250]; PerformedByUserId: Code[50])
    var
        History: Record "DOPSWHS Pick Reassign Hist";
    begin
        History.Init();
        History."Pick No." := PickNo;
        History."From User" := FromUserId;
        History."To User" := ToUserId;
        if PerformedByUserId <> '' then
            History."Reassigned By" := PerformedByUserId
        else
            History."Reassigned By" := CopyStr(UserId(), 1, MaxStrLen(History."Reassigned By"));
        History.DateTime := CurrentDateTime();
        History.Reason := Reason;
        History.Insert(true);
    end;

    /// <summary>
    /// Pick'teki atamayı, o pick'i doğuran "Toplanacak Siparişler" (Picking Order)
    /// kaydına da yazar. Terminalden "Üzerime Al" yapan operatör masadaki
    /// listede de görünsün diye — aksi halde bağ tek yönlü kalıyor ve sorumlu
    /// pick'i kimin aldığını Toplanacak Siparişler ekranından göremiyordu.
    /// </summary>
    local procedure SyncPickingOrderAssignment(PickNo: Code[20]; NewUserId: Code[50])
    var
        PickingHeader: Record "DOPSWHS Picking Order Header";
    begin
        if PickNo = '' then
            exit;
        PickingHeader.SetRange("Warehouse Pick No.", PickNo);
        if not PickingHeader.FindSet(true) then
            exit;
        repeat
            if PickingHeader."Assigned User ID" <> NewUserId then begin
                // Doğrudan yaz: alanın TableRelation'ı Warehouse Employee ve
                // WMS operatörü orada kayıtlı olmayabilir (Validate reddederdi).
                PickingHeader."Assigned User ID" := NewUserId;
                PickingHeader.Modify(true);
            end;
        until PickingHeader.Next() = 0;
    end;

    procedure StartShippingLP(var Pick: Record "Warehouse Activity Header"; TemplateCode: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        EffectiveTemplateCode: Code[20];
    begin
        EnsurePick(Pick);
        // Ağ yanıtı kaybolup terminal aynı isteği tekrar gönderirse ikinci bir
        // boş sevk LP'si üretme. Başlığı kilit altında yenileyip mevcut hedefi
        // aynen döndür; böylece pick üzerinde tek bir hedef LP kalır.
        Pick.LockTable();
        Pick.Get(Pick.Type::Pick, Pick."No.");
        if Pick."DOPSWHS Main LP No." <> '' then begin
            if not LP.Get(Pick."DOPSWHS Main LP No.") then
                Error('Toplama %1 üzerindeki sevk LP %2 bulunamadı.', Pick."No.", Pick."DOPSWHS Main LP No.");
            ValidateLPForPick(LP, Pick, true);
            exit(LP."No.");
        end;
        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        LPMgt.Build(EffectiveTemplateCode, Pick."Location Code", '', LP);
        // Üretilen sepeti belgeye BAĞLA. Bağlanmazsa mainLpNo boş kalır,
        // terminal düğmesi "LP Kapat"a dönmez ve LP hiçbir belgeye ait
        // olmayan yetim kayıt olarak kalır (UAT shipping-x04).
        Pick.Validate("DOPSWHS Main LP No.", LP."No.");
        Pick.Modify(true);
        // Operatör: belgeyi üstlenmiş kullanıcı (uç nokta EnsurePickOperator ile
        // sahipliği zaten doğruluyor), servis hesabı değil.
        Log('Pick.StartShippingLP', Pick."No.", Pick."Assigned User ID");
        exit(LP."No.");
    end;

    procedure StopShippingLP(var Pick: Record "Warehouse Activity Header"; LpNo: Code[20]; PrintLabel: Boolean): Code[18]
    begin
        exit(StopShippingLP(Pick, LpNo, PrintLabel, ''));
    end;

    procedure StopShippingLP(var Pick: Record "Warehouse Activity Header"; LpNo: Code[20]; PrintLabel: Boolean; PrinterId: Code[50]): Code[18]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        EnsurePick(Pick);
        Pick.LockTable();
        Pick.Get(Pick.Type::Pick, Pick."No.");
        if Pick."DOPSWHS Main LP No." <> LpNo then
            Error('%1 LP numarası %2 toplamasının hedef sevk LP''si değildir.', LpNo, Pick."No.");
        LP.Get(LpNo);
        ValidateLPForPick(LP, Pick, true);
        // Başarılı cevabı alamayan terminalin güvenli tekrarına izin ver.
        if LP.Status = LP.Status::Built then
            exit(LP.SSCC);
        LPMgt.Stop(LP, PrintLabel, PrinterId);
        Log('Pick.StopShippingLP', Pick."No.", Pick."Assigned User ID");
        exit(LP.SSCC);
    end;

    procedure RegisterShortPick(var PickLine: Record "Warehouse Activity Line"; ShortQty: Decimal; ReasonCode: Code[20])
    var
        Reason: Record "DOPSWHS Short Pick Reason";
        PickableQty: Decimal;
    begin
        // Eksik toplama bildirimi de bir işlemdir: belge başkasındaysa/atanmamışsa reddet.
        CheckLineOwnership(PickLine, '');
        if ShortQty < 0 then
            Error('Short quantity cannot be negative.');
        if ReasonCode <> '' then
            Reason.Get(ReasonCode);

        // ShortQty = BULUNAMAYAN miktar. Eskiden doğrudan "Qty. to Handle"
        // yazılıyordu; yani "4 eksik" bildirimi "4 tanesini işle" oluyordu ve
        // eş Place satırı güncellenmediği için Take<>Place kalıyordu — ambar
        // hareketlerinde hayalet stok üreten durum bu (UAT shipping-x04).
        if ShortQty > PickLine."Qty. Outstanding" then
            Error(
                'Eksik miktar (%1) kalan miktardan (%2) fazla olamaz.',
                ShortQty, PickLine."Qty. Outstanding");
        PickableQty := PickLine."Qty. Outstanding" - ShortQty;
        // Eksik bildirimi = kalan miktar TOPLANMAYACAK demektir. Yalnız
        // "Qty. to Handle" düşürülürse BC kaydı reddediyor ("Complete all items
        // before posting ... still has N remaining") ve toplama kaydedilemiyor.
        // Bu yüzden satırın miktarı da toplanan kadara çekilir.
        PickLine.Validate(Quantity, PickLine."Qty. Handled" + PickableQty);
        PickLine.Validate("Qty. to Handle", PickableQty);
        PickLine.Modify(true);
        // Take satırı değiştiyse eş Place satırı da aynı miktara çekilir.
        SyncRelatedShortPlaceLine(PickLine);
        // Eksik bildiren operatör = belgeyi üstlenen kullanıcı; uç nokta ayrı
        // kimlik taşımıyor, o yüzden atamadan okunur.
        Log('Pick.Short.' + ReasonCode, PickLine."No.", PickOperator(PickLine."No."));
    end;

    /// <summary>
    /// Satır onayı — çağıranın kimliği bilinmiyor (pickLines PATCH yolu).
    /// Sahiplik, oturumun BC kullanıcısı üzerinden kontrol edilir.
    /// </summary>
    procedure ConfirmPickLine(var PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50])
    begin
        ConfirmPickLineInternal(PickLine, QtyToHandle, LotNo, '', '');
    end;

    /// <summary>
    /// Satır onayı — çağıran operatör kimliğini AÇIKÇA bildirir (terminal WMS
    /// oturumu). Paylaşımlı BC hesabında sahipliği kesin doğrulayabilen tek yol
    /// budur: toplama başkasındaysa satır onaylanamaz.
    /// </summary>
    procedure ConfirmPickLineFor(var PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; RequestingUserId: Code[50])
    begin
        if RequestingUserId = '' then
            Error(RequestingUserRequiredErr);
        ConfirmPickLineInternal(PickLine, QtyToHandle, LotNo, '', RequestingUserId);
    end;

    procedure ConfirmPickLineFor(var PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; SourceLpNo: Code[20]; RequestingUserId: Code[50])
    begin
        if RequestingUserId = '' then
            Error(RequestingUserRequiredErr);
        ConfirmPickLineInternal(PickLine, QtyToHandle, LotNo, SourceLpNo, RequestingUserId);
    end;

    local procedure ConfirmPickLineInternal(var PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50]; SourceLpNo: Code[20]; RequestingUserId: Code[50])
    var
        EffectiveLpNo: Code[20];
    begin
        if PickLine."Activity Type" <> PickLine."Activity Type"::Pick then
            Error('Warehouse activity %1 must be a Pick.', PickLine."No.");

        // Belge hâlâ bu operatörde mi? Satır bazında her onayda doğrulanır;
        // sorumlu toplamayı toplama sırasında devretmiş olabilir.
        CheckLineOwnership(PickLine, RequestingUserId);

        // El terminalindeki toplama fiziksel bir raf/bin doğrulamasıdır. Kaynak
        // rafı boş bir satırın miktarını onaylamak, terminalde gerçekte hangi
        // raftan ürün alındığını kanıtsız bırakır ve yanlış stok hareketine yol
        // açar. Böyle bir pick genellikle eksik bin content/setup nedeniyle
        // oluşur; operatöre düşürmek yerine sunucuda kesin olarak reddedilir.
        EnsurePickLineHasBin(PickLine, QtyToHandle);

        PickLine.Validate("Qty. to Handle", QtyToHandle);
        EnsurePickLot(PickLine, LotNo);
        PickLine.Validate("Lot No.", LotNo);
        EffectiveLpNo := SourceLpNo;
        if EffectiveLpNo = '' then
            EffectiveLpNo := PickLine."LP No.";
        PickLine."LP No." := ResolvePickSourceLp(PickLine, EffectiveLpNo);
        PickLine.Modify(true);

        // Qty. to Handle doğrulaması Take satırını değiştirir ancak BC'nin
        // standart tablosu eş Place satırını otomatik güncellemez. Kısmi
        // toplamada Take=250, Place=300 kalırsa kayıt stoktan 250 düşüp sevkiyat
        // gözüne 300 koyarak 50 birim hayali stok üretir. Aynı kaynak+lot
        // çiftindeki Place satırını kesin olarak aynı miktara getir.
        SyncRelatedPlaceLine(PickLine);

        // Sevkiyat özet alanını açık Take satırlarının tamamına bakarak yalnız
        // tek lot varsa doldur.
        UpdateShipmentLineLotSummary(PickLine);
        UpdateShipmentLineLpSummary(PickLine);

        // Satır onayı sahadaki EN SIK işlem; "bu satırı kim okuttu" sorusu
        // ancak burada kayıt altına alınırsa cevaplanabiliyor.
        Log('Pick.ConfirmLine', PickLine."No.", EffectiveOperator(PickLine."No.", RequestingUserId));
    end;

    /// <summary>
    /// Eksik bildiriminde eş Place satırını da küçültür: hem işlenecek miktar
    /// hem satır miktarı Take satırıyla eşitlenir, aksi hâlde Take ve Place
    /// dengesiz kalır (ambar defterinde hayalet stok kaynağı).
    /// </summary>
    local procedure SyncRelatedShortPlaceLine(PickLine: Record "Warehouse Activity Line")
    var
        RelatedPlaceLine: Record "Warehouse Activity Line";
    begin
        if PickLine."Action Type" <> PickLine."Action Type"::Take then
            exit;
        RelatedPlaceLine.SetRange("Activity Type", PickLine."Activity Type");
        RelatedPlaceLine.SetRange("No.", PickLine."No.");
        RelatedPlaceLine.SetRange("Action Type", RelatedPlaceLine."Action Type"::Place);
        RelatedPlaceLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        RelatedPlaceLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        RelatedPlaceLine.SetRange("Item No.", PickLine."Item No.");
        RelatedPlaceLine.SetRange("Variant Code", PickLine."Variant Code");
        RelatedPlaceLine.SetRange("Unit of Measure Code", PickLine."Unit of Measure Code");
        if not RelatedPlaceLine.FindSet() then
            exit;
        repeat
            RelatedPlaceLine.Validate(Quantity, PickLine.Quantity);
            RelatedPlaceLine.Validate("Qty. to Handle", PickLine."Qty. to Handle");
            if RelatedPlaceLine."Lot No." <> PickLine."Lot No." then
                RelatedPlaceLine.Validate("Lot No.", PickLine."Lot No.");
            RelatedPlaceLine.Modify(true);
        until RelatedPlaceLine.Next() = 0;
    end;

    local procedure SyncRelatedPlaceLine(PickLine: Record "Warehouse Activity Line")
    var
        RelatedPlaceLine: Record "Warehouse Activity Line";
    begin
        if PickLine."Action Type" <> PickLine."Action Type"::Take then
            exit;

        RelatedPlaceLine.SetRange("Activity Type", PickLine."Activity Type");
        RelatedPlaceLine.SetRange("No.", PickLine."No.");
        RelatedPlaceLine.SetRange("Action Type", RelatedPlaceLine."Action Type"::Place);
        RelatedPlaceLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type");
        RelatedPlaceLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        RelatedPlaceLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        RelatedPlaceLine.SetRange("Source Type", PickLine."Source Type");
        RelatedPlaceLine.SetRange("Source Subtype", PickLine."Source Subtype");
        RelatedPlaceLine.SetRange("Source No.", PickLine."Source No.");
        RelatedPlaceLine.SetRange("Source Line No.", PickLine."Source Line No.");
        RelatedPlaceLine.SetRange("Source Subline No.", PickLine."Source Subline No.");
        RelatedPlaceLine.SetRange("Item No.", PickLine."Item No.");
        RelatedPlaceLine.SetRange("Variant Code", PickLine."Variant Code");
        RelatedPlaceLine.SetRange("Unit of Measure Code", PickLine."Unit of Measure Code");
        RelatedPlaceLine.SetRange("Breakbulk No.", PickLine."Breakbulk No.");
        RelatedPlaceLine.SetTrackingFilterFromWhseActivityLine(PickLine);
        if not RelatedPlaceLine.FindFirst() then begin
            // A newly-created pick can be structurally paired while its Place
            // line is still untracked. Clear only the tracking filters and
            // accept the fallback when the structural identity is unique.
            RelatedPlaceLine.SetRange("Lot No.");
            RelatedPlaceLine.SetRange("Serial No.");
            if RelatedPlaceLine.Count() <> 1 then
                Error(
                    '%1 toplamasındaki %2 lotlu %3 ürünü için eş sevkiyat gözü satırı bulunamadı. Pick kaydedilmedi; belgeyi yenileyip tekrar deneyin.',
                    PickLine."No.", PickLine."Lot No.", PickLine."Item No.");
            RelatedPlaceLine.FindFirst();
        end;

        RelatedPlaceLine.Validate("Qty. to Handle", PickLine."Qty. to Handle");
        if RelatedPlaceLine."Lot No." <> PickLine."Lot No." then
            RelatedPlaceLine.Validate("Lot No.", PickLine."Lot No.");
        if RelatedPlaceLine."Serial No." <> PickLine."Serial No." then
            RelatedPlaceLine.Validate("Serial No.", PickLine."Serial No.");
        RelatedPlaceLine."LP No." := PickLine."LP No.";
        RelatedPlaceLine.Modify(true);
    end;

    local procedure ResolvePickSourceLp(PickLine: Record "Warehouse Activity Line"; RequestedLpNo: Code[20]): Code[20]
    var
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ItemUom: Record "Item Unit of Measure";
        CandidateLpNo: Code[20];
        QtyPerUom: Decimal;
        AvailableBaseQty: Decimal;
        CandidateCount: Integer;
    begin
        if PickLine."Qty. to Handle (Base)" = 0 then
            exit('');

        Item.Get(PickLine."Item No.");
        if RequestedLpNo <> '' then
            LPHeader.SetRange("No.", RequestedLpNo);
        LPHeader.SetRange("Location Code", PickLine."Location Code");
        LPHeader.SetRange("Bin Code", PickLine."Bin Code");
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                if PickSourceLpAssignmentMatches(LPHeader, PickLine) then begin
                    AvailableBaseQty := 0;
                    LPLine.Reset();
                    LPLine.SetRange("LP No.", LPHeader."No.");
                    LPLine.SetRange("Item No.", PickLine."Item No.");
                    LPLine.SetRange("Variant Code", PickLine."Variant Code");
                    LPLine.SetRange("Lot No.", PickLine."Lot No.");
                    LPLine.SetRange("Serial No.", PickLine."Serial No.");
                    LPLine.SetFilter(Quantity, '>0');
                    if LPLine.FindSet() then
                        repeat
                            QtyPerUom := 1;
                            if (LPLine."Unit of Measure" <> '') and
                               (LPLine."Unit of Measure" <> Item."Base Unit of Measure")
                            then
                                if ItemUom.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                                    QtyPerUom := ItemUom."Qty. per Unit of Measure"
                                else
                                    QtyPerUom := 0;
                            if QtyPerUom > 0 then
                                AvailableBaseQty += Round(LPLine.Quantity * QtyPerUom, 0.00001);
                        until LPLine.Next() = 0;

                    // A manually scanned LP only selects where allocation starts;
                    // it no longer has to hold the entire Take-line quantity.
                    if (RequestedLpNo <> '') and (AvailableBaseQty > 0.00001) then
                        exit(LPHeader."No.");
                    if AvailableBaseQty + 0.00001 >= PickLine."Qty. to Handle (Base)" then begin
                        CandidateCount += 1;
                        CandidateLpNo := LPHeader."No.";
                    end;
                end;
            until LPHeader.Next() = 0;

        if RequestedLpNo <> '' then
            Error(
                '%1 LP numarasında %2 ürünü, lot %3 için sevk edilebilir stok bulunamadı.',
                RequestedLpNo, PickLine."Item No.", PickLine."Lot No.");

        // One full-cover LP can be stamped as an optimization. If none or more
        // than one can cover the line, keep the source blank: registration will
        // deterministically allocate the quantity across all LPs in the Take bin.
        if CandidateCount = 1 then
            exit(CandidateLpNo);
        exit('');
    end;

    local procedure PickSourceLpAssignmentMatches(LPHeader: Record "DOPSWHS LP Header"; PickLine: Record "Warehouse Activity Line"): Boolean
    begin
        if LPHeader.Status <> LPHeader.Status::Assigned then
            exit(true);
        exit(
            ((LPHeader."Assigned Document Type" = LPHeader."Assigned Document Type"::WhsePick) and
             (LPHeader."Assigned Document No." = PickLine."No.")) or
            ((LPHeader."Assigned Document Type" = LPHeader."Assigned Document Type"::WhseShipment) and
             (LPHeader."Assigned Document No." = PickLine."Whse. Document No.")));
    end;

    local procedure UpdateShipmentLineLotSummary(PickLine: Record "Warehouse Activity Line")
    var
        RelatedTakeLine: Record "Warehouse Activity Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        CandidateLotNo: Code[50];
        MultipleLots: Boolean;
    begin
        if PickLine."Whse. Document Type" <> PickLine."Whse. Document Type"::Shipment then
            exit;
        if not WhseShipmentLine.Get(PickLine."Whse. Document No.", PickLine."Whse. Document Line No.") then
            exit;

        RelatedTakeLine.SetRange("Activity Type", PickLine."Activity Type");
        RelatedTakeLine.SetRange("No.", PickLine."No.");
        RelatedTakeLine.SetRange("Action Type", RelatedTakeLine."Action Type"::Take);
        RelatedTakeLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type");
        RelatedTakeLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        RelatedTakeLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        RelatedTakeLine.SetFilter("Qty. to Handle", '>0');
        RelatedTakeLine.SetFilter("Lot No.", '<>%1', '');
        if RelatedTakeLine.FindSet() then
            repeat
                if CandidateLotNo = '' then
                    CandidateLotNo := RelatedTakeLine."Lot No."
                else
                    if CandidateLotNo <> RelatedTakeLine."Lot No." then
                        MultipleLots := true;
            until (RelatedTakeLine.Next() = 0) or MultipleLots;

        if MultipleLots then
            Clear(CandidateLotNo);
        if WhseShipmentLine."DOPSWHS Lot No." <> CandidateLotNo then begin
            WhseShipmentLine."DOPSWHS Lot No." := CandidateLotNo;
            WhseShipmentLine.Modify(true);
        end;
    end;

    local procedure UpdateShipmentLineLpSummary(PickLine: Record "Warehouse Activity Line")
    var
        RelatedTakeLine: Record "Warehouse Activity Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        CandidateLpNo: Code[20];
        MultipleLps: Boolean;
    begin
        if PickLine."Whse. Document Type" <> PickLine."Whse. Document Type"::Shipment then
            exit;
        if not WhseShipmentLine.Get(PickLine."Whse. Document No.", PickLine."Whse. Document Line No.") then
            exit;

        RelatedTakeLine.SetRange("Activity Type", PickLine."Activity Type");
        RelatedTakeLine.SetRange("No.", PickLine."No.");
        RelatedTakeLine.SetRange("Action Type", RelatedTakeLine."Action Type"::Take);
        RelatedTakeLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type");
        RelatedTakeLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        RelatedTakeLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        RelatedTakeLine.SetFilter("Qty. to Handle", '>0');
        RelatedTakeLine.SetFilter("LP No.", '<>%1', '');
        if RelatedTakeLine.FindSet() then
            repeat
                if CandidateLpNo = '' then
                    CandidateLpNo := RelatedTakeLine."LP No."
                else
                    if CandidateLpNo <> RelatedTakeLine."LP No." then
                        MultipleLps := true;
            until (RelatedTakeLine.Next() = 0) or MultipleLps;

        if MultipleLps then
            Clear(CandidateLpNo);
        if WhseShipmentLine."LP No." <> CandidateLpNo then begin
            WhseShipmentLine."LP No." := CandidateLpNo;
            WhseShipmentLine.Modify(true);
        end;
    end;

    /// <summary>Lot takipli toplama satırlarında mobil lot seçimini zorunlu kılar.</summary>
    procedure PickLineRequiresLot(PickLine: Record "Warehouse Activity Line"): Boolean
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if not Item.Get(PickLine."Item No.") then
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

    local procedure EnsurePickLot(PickLine: Record "Warehouse Activity Line"; LotNo: Code[50])
    begin
        if (PickLine."Qty. to Handle" <= 0) or (not PickLineRequiresLot(PickLine)) then
            exit;
        if LotNo = '' then
            Error(
                '%1 ürününün %2 toplama satırında lot numarası zorunludur. %3 rafındaki stok lotlarından birini seçin.',
                PickLine."Item No.", PickLine."Line No.", PickLine."Bin Code");
    end;

    procedure RegisterPick(var Pick: Record "Warehouse Activity Header")
    begin
        RegisterPickInternal(Pick, '');
    end;

    /// <summary>
    /// Terminal için strict register yolu. Paylaşımlı BC hesabı yerine WMS
    /// oturumundaki gerçek operatör kimliğini taşır; belge son anda başka birine
    /// devredildiyse kayıt işlemi kilit altında reddedilir.
    /// </summary>
    procedure RegisterPickFor(var Pick: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    begin
        if RequestingUserId = '' then
            Error(RequestingUserRequiredErr);
        RegisterPickInternal(Pick, RequestingUserId);
    end;

    /// <summary>
    /// Terminalden güvenli toplama iptali. Genel API DELETE bilerek kapalıdır;
    /// yalnız belge sahibi, henüz kaydedilmemiş ve fiziksel hareket üretmemiş
    /// açık bir pick'i bu işlemle iptal edebilir. Standart tablo OnDelete
    /// tetikleyicisi satırları ve bağlı depo izleme kayıtlarını temizler.
    /// </summary>
    procedure CancelPickFor(var Pick: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    var
        LockedPick: Record "Warehouse Activity Header";
        PickLine: Record "Warehouse Activity Line";
        PickingHeader: Record "DOPSWHS Picking Order Header";
        PickNo: Code[20];
    begin
        EnsurePick(Pick);
        if RequestingUserId = '' then
            Error(RequestingUserRequiredErr);

        LockedPick.LockTable();
        if not LockedPick.Get(LockedPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");
        CheckOwnershipFor(LockedPick."No.", LockedPick."Assigned User ID", RequestingUserId);

        PickLine.SetRange("Activity Type", LockedPick.Type);
        PickLine.SetRange("No.", LockedPick."No.");
        PickLine.SetFilter("Qty. Handled", '<>0');
        if not PickLine.IsEmpty() then
            Error(PickCancelHandledErr, LockedPick."No.");

        PickNo := LockedPick."No.";
        CleanupUnusedMainShippingLp(LockedPick);
        LockedPick.Delete(true);

        // Özel toplama grubu bu standart pick'e bağlıysa tekrar oluşturulabilsin.
        PickingHeader.SetRange("Warehouse Pick No.", PickNo);
        if PickingHeader.FindSet(true) then
            repeat
                PickingHeader."Warehouse Pick No." := '';
                PickingHeader.Modify(true);
            until PickingHeader.Next() = 0;

        Log('Pick.Cancel', PickNo, RequestingUserId);
        Clear(Pick);
    end;

    local procedure RegisterPickInternal(var Pick: Record "Warehouse Activity Header"; RequestingUserId: Code[50])
    var
        PickLine: Record "Warehouse Activity Line";
        PickingHeader: Record "DOPSWHS Picking Order Header";
        LockedPick: Record "Warehouse Activity Header";
        PickNo: Code[20];
        // QM (BC 28) devre dışı — bkz. QualityMgmtBridge.Codeunit.al
        // QualityBridge: Codeunit "DOPSWHS Quality Mgmt Bridge";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
    begin
        EnsurePick(Pick);
        // Eş zamanlılık: iki terminal aynı belgeyi aynı anda kaydetmeye çalışabilir.
        // Kilit alıp yeniden okuyoruz; belge artık yoksa (öteki kaydetmiş) anlaşılır
        // bir mesaj veririz — aksi halde BC'nin ham "record not found" hatası düşerdi.
        LockedPick.LockTable();
        if not LockedPick.Get(LockedPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");
        Pick := LockedPick;
        // Kaydetme de bir işlemdir: atanmamış ya da başkasındaki belge kaydedilemez.
        if RequestingUserId = '' then
            CheckOwnership(Pick."No.", Pick."Assigned User ID")
        else
            CheckOwnershipFor(Pick."No.", Pick."Assigned User ID", RequestingUserId);
        PickNo := Pick."No.";
        // Kaydeden operatör: belge sahibi (CheckOwnership hemen üstte doğruladı).
        Log('Pick.Register', Pick."No.", EffectiveOperator(Pick."No.", RequestingUserId));
        EnsurePickHasBins(Pick);
        EnsureTakeAndPlaceQuantitiesBalanced(Pick);
        if Pick."DOPSWHS Pick Mode" = Pick."DOPSWHS Pick Mode"::Multi then
            EnsureAllMultiPickLinesScanned(Pick);

        // Microsoft Quality Management block guard — QM (BC 28) devre dışı.
        // BC 28'e geçince aşağıdaki bloğun yorumunu kaldırın. Register if any
        // pick line carries a Lot/Serial currently under an open inspection.
        // Error format matches BCWMSApp.QcErrorParser so the mobile/web UI
        // renders a friendly " QC BLOCK" banner.
        // PickLine.SetRange("Activity Type", Pick.Type);
        // PickLine.SetRange("No.", Pick."No.");
        // if PickLine.FindSet() then
        //     repeat
        //         QualityBridge.VerifyNotBlocked(
        //             PickLine."Lot No.",
        //             PickLine."Serial No.",
        //             '');
        //     until PickLine.Next() = 0;

        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindFirst() then begin
            MovePickedContentsToMainLp(Pick);
            CompleteMainShippingLp(Pick);
            PreparePackingOrders(Pick);
            WhseActivityRegister.Run(PickLine);
            PickingHeader.SetRange("Warehouse Pick No.", PickNo);
            if PickingHeader.FindSet(true) then
                repeat
                    PickingHeader.Status := PickingHeader.Status::Completed;
                    PickingHeader."Completed DateTime" := CurrentDateTime();
                    PickingHeader.Modify(true);
                until PickingHeader.Next() = 0;
        end;
    end;

    /// <summary>
    /// Hedef sevk LP'si Toplamayı Kaydet işleminin aynı transaction'ında
    /// tamamlanır. Operatörün ayrıca boş LP'yi önceden kapatması gerekmez;
    /// kayıt başarısız olursa içerik ve LP durumu birlikte geri alınır.
    /// </summary>
    local procedure CompleteMainShippingLp(Pick: Record "Warehouse Activity Header")
    var
        LP: Record "DOPSWHS LP Header";
        PickLine: Record "Warehouse Activity Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if Pick."DOPSWHS Main LP No." = '' then
            exit;
        LP.Get(Pick."DOPSWHS Main LP No.");
        if LP.Status = LP.Status::Open then
            LPMgt.Stop(LP, false)
        else
            if LP.Status <> LP.Status::Built then
                Error('%1 hedef sevk LP''si tamamlanamaz. Mevcut durum: %2.', LP."No.", LP.Status);

        // İçerik aktarılırken LP henüz açık olduğundan SSCC boş olabilir.
        // Kapatıldıktan sonra ilgili bütün sevkiyat satırlarına kesin değeri yaz.
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        PickLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type"::Shipment);
        if PickLine.FindSet() then
            repeat
                if WhseShipmentLine.Get(PickLine."Whse. Document No.", PickLine."Whse. Document Line No.") then
                    if (WhseShipmentLine."LP No." <> LP."No.") or (WhseShipmentLine.SSCC <> LP.SSCC) then begin
                        WhseShipmentLine."LP No." := LP."No.";
                        WhseShipmentLine.SSCC := LP.SSCC;
                        WhseShipmentLine.Modify(true);
                    end;
            until PickLine.Next() = 0;
    end;

    /// <summary>
    /// Kaydedilmeden iptal edilen pick'in boş hedef LP'sini aktif bırakmaz.
    /// İçerik varsa veri kaybetmemek için iptali açık hatayla durdurur.
    /// </summary>
    local procedure CleanupUnusedMainShippingLp(Pick: Record "Warehouse Activity Header")
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if Pick."DOPSWHS Main LP No." = '' then
            exit;
        if not LP.Get(Pick."DOPSWHS Main LP No.") then
            exit;
        LPLine.SetRange("LP No.", LP."No.");
        if not LPLine.IsEmpty() then
            Error('%1 sevk LP''sinde ürün bulunduğu için toplama iptal edilemez.', LP."No.");
        if LP.Status in [LP.Status::Open, LP.Status::Built] then
            LPMgt.Unbuild(LP);
    end;

    /// <summary>
    /// A shipping LP is the physical result of picking, not an empty label. For
    /// every handled Take line, split the quantity from its source LP into the
    /// main/shipping LP (or add it from loose stock), then make the shipment line
    /// point to that LP. Shipment posting will therefore consume the new LP while
    /// the source pallet keeps only its unpicked remainder.
    /// </summary>
    local procedure MovePickedContentsToMainLp(Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        ShippingLP: Record "DOPSWHS LP Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if Pick."DOPSWHS Main LP No." = '' then
            exit;
        ShippingLP.Get(Pick."DOPSWHS Main LP No.");

        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        PickLine.SetFilter("Qty. to Handle (Base)", '>0');
        if not PickLine.FindSet(true) then
            exit;
        repeat
            FindRelatedPlaceLineForShippingLp(PickLine, PlaceLine);
            LPMgt.TransferPickedQuantityFromAvailableLps(
                PickLine."LP No.", ShippingLP."No.", Pick."No.", PickLine."Line No.",
                PickLine."Whse. Document No.", PickLine."Item No.", PickLine."Variant Code", PickLine."Unit of Measure Code",
                PickLine."Qty. to Handle (Base)",
                PickLine."Lot No.", PickLine."Serial No.", PickLine."Bin Code", PlaceLine."Bin Code");

            PickLine."Target LP No." := ShippingLP."No.";
            PickLine.Modify(true);
            PlaceLine."LP No." := ShippingLP."No.";
            PlaceLine."Target LP No." := ShippingLP."No.";
            PlaceLine.Modify(true);

            if (PickLine."Whse. Document Type" = PickLine."Whse. Document Type"::Shipment) and
               WhseShipmentLine.Get(PickLine."Whse. Document No.", PickLine."Whse. Document Line No.")
            then begin
                WhseShipmentLine."LP No." := ShippingLP."No.";
                WhseShipmentLine.SSCC := ShippingLP.SSCC;
                WhseShipmentLine.Modify(true);
            end;
        until PickLine.Next() = 0;
    end;

    local procedure FindRelatedPlaceLineForShippingLp(PickLine: Record "Warehouse Activity Line"; var PlaceLine: Record "Warehouse Activity Line")
    begin
        PlaceLine.Reset();
        PlaceLine.SetRange("Activity Type", PickLine."Activity Type");
        PlaceLine.SetRange("No.", PickLine."No.");
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        PlaceLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type");
        PlaceLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        PlaceLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        PlaceLine.SetRange("Source No.", PickLine."Source No.");
        PlaceLine.SetRange("Source Line No.", PickLine."Source Line No.");
        PlaceLine.SetRange("Source Subline No.", PickLine."Source Subline No.");
        PlaceLine.SetRange("Item No.", PickLine."Item No.");
        PlaceLine.SetRange("Variant Code", PickLine."Variant Code");
        PlaceLine.SetRange("Unit of Measure Code", PickLine."Unit of Measure Code");
        PlaceLine.SetRange("Breakbulk No.", PickLine."Breakbulk No.");
        PlaceLine.SetTrackingFilterFromWhseActivityLine(PickLine);
        if PlaceLine.FindFirst() then
            exit;

        PlaceLine.SetRange("Lot No.");
        PlaceLine.SetRange("Serial No.");
        if PlaceLine.Count() <> 1 then
            Error(
                '%1 toplamasındaki %2 satırı için sevk LP hedef satırı bulunamadı.',
                PickLine."No.", PickLine."Line No.");
        PlaceLine.FindFirst();
    end;

    local procedure EnsureTakeAndPlaceQuantitiesBalanced(Pick: Record "Warehouse Activity Header")
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        TakeQtyBase: Decimal;
        PlaceQtyBase: Decimal;
    begin
        TakeLine.SetRange("Activity Type", Pick.Type);
        TakeLine.SetRange("No.", Pick."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.CalcSums("Qty. to Handle (Base)");
        TakeQtyBase := TakeLine."Qty. to Handle (Base)";

        PlaceLine.SetRange("Activity Type", Pick.Type);
        PlaceLine.SetRange("No.", Pick."No.");
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        if PlaceLine.IsEmpty() then
            exit;
        PlaceLine.CalcSums("Qty. to Handle (Base)");
        PlaceQtyBase := PlaceLine."Qty. to Handle (Base)";

        if TakeQtyBase <> PlaceQtyBase then
            Error(
                '%1 toplamasında alınan miktar (%2) ile sevkiyat gözüne bırakılan miktar (%3) eşit değil. Stok bozulmaması için kayıt durduruldu; satırları yenileyip miktarı tekrar onaylayın.',
                Pick."No.", TakeQtyBase, PlaceQtyBase);
    end;

    local procedure EnsurePickLineHasBin(PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal)
    begin
        if QtyToHandle <= 0 then
            exit;
        PickLine.TestField("Location Code");
        if PickLine."Bin Code" = '' then
            Error(PickLineBinRequiredErr, PickLine."No.", PickLine."Line No.", PickLine."Item No.");
    end;

    local procedure EnsurePickHasBins(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        PickLine.SetFilter(Quantity, '>0');
        if PickLine.FindSet() then
            repeat
                EnsurePickLineHasBin(PickLine, PickLine.Quantity);
            until PickLine.Next() = 0;
    end;

    local procedure EnsureAllMultiPickLinesScanned(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        if PickLine.FindSet() then
            repeat
                if PickLine."Qty. to Handle" < PickLine.Quantity then
                    Error('Complete all items before posting. Bin %1, item %2 still has %3 remaining.',
                        PickLine."Bin Code", PickLine."Item No.", PickLine.Quantity - PickLine."Qty. to Handle");
            until PickLine.Next() = 0;
    end;

    local procedure PreparePackingOrders(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
        Handled: Dictionary of [Code[20], Boolean];
    begin
        // ELOG: register'dan ÖNCE, pick'teki her satış siparişi için paketleme
        // kaydı (DOPSWHS Packing Order) hazırlanır. Eskiden Action Type=Take +
        // Source Type=Sales Line filtreleniyordu; ancak Whse.-Shipment-Create-Pick
        // ile üretilen satırlarda bu alanlar beklenenden farklı olabildiği için
        // paketleme kuyruğu BOŞ kalıyordu. Artık tüm pick satırlarını dolaşıp
        // Source No.'yu doğrudan satış siparişi olarak deniyoruz (tekilleştirilmiş).
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindSet() then
            repeat
                if (PickLine."Source No." <> '') and (not Handled.ContainsKey(PickLine."Source No.")) then begin
                    Handled.Add(PickLine."Source No.", true);
                    UpsertPackingOrder(Pick, PickLine);
                end;
            until PickLine.Next() = 0;
    end;

    // Bir satış siparişi için paketleme kaydını oluşturur/günceller (Ready).
    // Source No. bir satış siparişi değilse sessizce atlar.
    local procedure UpsertPackingOrder(var Pick: Record "Warehouse Activity Header"; var PickLine: Record "Warehouse Activity Line")
    var
        PackingOrder: Record "DOPSWHS Packing Order";
        PickingHeader: Record "DOPSWHS Picking Order Header";
        SalesHeader: Record "Sales Header";
        PackingOrderExists: Boolean;
    begin
        if not SalesHeader.Get(SalesHeader."Document Type"::Order, PickLine."Source No.") then
            exit;

        PackingOrderExists := PackingOrder.Get(PickLine."Source No.");
        if PackingOrderExists then begin
            if PackingOrder.Status = PackingOrder.Status::"In Progress" then
                Error('Sales order %1 is already being packed.', PickLine."Source No.");
            PackingOrder.Status := PackingOrder.Status::Ready;
            PackingOrder."Session Entry No." := 0;
        end else begin
            PackingOrder.Init();
            PackingOrder."Sales Order No." := PickLine."Source No.";
        end;
        PackingOrder."Pick No." := Pick."No.";
        // Toplamada kullanılan ana sepeti paketlemeye taşı: paketleyici
        // "ürünler hangi sepette" bilgisini terminalde görsün.
        PackingOrder."Main LP No." := Pick."DOPSWHS Main LP No.";
        // Toplama grubunun akış tipini paketlemeye taşı: terminaldeki V2
        // sekmeleri (Multi / Mono / Tek SKU) listeyi bu alanla filtreliyor.
        // Pick başlığı ana kaynaktır; özel grup kaydı bazı eski/standart
        // pick'lerde bulunmadığında modu boş bırakmak V2 kuyruğundan kaydı
        // tamamen gizliyordu. Grup kaydında dolu bir mod varsa onu tercih et.
        PackingOrder."Order Flow Mode" := Pick."DOPSWHS Pick Mode";
        PickingHeader.SetRange("Warehouse Pick No.", Pick."No.");
        if PickingHeader.FindFirst() then
            if PickingHeader."Order Flow Mode" <> PickingHeader."Order Flow Mode"::" " then
                PackingOrder."Order Flow Mode" := PickingHeader."Order Flow Mode";
        PackingOrder."Warehouse Shipment No." := PickLine."Whse. Document No.";
        PackingOrder."Location Code" := Pick."Location Code";
        PackingOrder."Customer No." := SalesHeader."Sell-to Customer No.";
        PackingOrder."Customer Name" := SalesHeader."Sell-to Customer Name";
        PackingOrder."Ready DateTime" := CurrentDateTime();
        if PackingOrderExists then
            PackingOrder.Modify(true)
        else
            PackingOrder.Insert(true);
    end;

    /// <summary>
    /// YÖNETİCİ yolu: belgeyi zorla devreder. Toplama başka bir operatörde olsa
    /// bile geçer — depo sorumlusu vardiya değişiminde/arızada işi devralabilmeli.
    /// Operatörün kendi kendine üstlenmesi bu yoldan DEĞİL, ClaimPick'ten geçer.
    /// </summary>
    procedure ReassignPick(var Pick: Record "Warehouse Activity Header"; NewUserId: Code[50]; Reason: Text[250])
    var
        LockedPick: Record "Warehouse Activity Header";
        WebhookMgmt: Codeunit "DOPSWHS Webhook Mgmt";
        FromUserId: Code[50];
    begin
        EnsurePick(Pick);
        if NewUserId = '' then
            Error(NewUserRequiredErr);

        // Kilitli yeniden okuma: "kimden kime" geçmişi ekrandaki eski değerle
        // değil, güncel sahiple yazılsın; iki sorumlu aynı anda devrederse
        // ikincisi birincisinin yazdığını görerek üzerine yazar.
        LockedPick.LockTable();
        if not LockedPick.Get(LockedPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");

        FromUserId := LockedPick."Assigned User ID";
        // "Assigned User ID" TableRelation'ı Warehouse Employee'dir. WMS operatörü
        // (ör. DYNOPS) her zaman bir Warehouse Employee olmayabilir; Validate bu
        // durumda değeri reddedip alanı boş bırakabiliyordu. Atamanın her koşulda
        // kalıcı olması için ilişki doğrulamasını tetiklemeden doğrudan yazılır.
        LockedPick."Assigned User ID" := CopyStr(NewUserId, 1, MaxStrLen(LockedPick."Assigned User ID"));
        LockedPick.Modify(true);
        Pick := LockedPick;

        // Devri YAPAN kimlik bu yoldan gelmiyor (masa/Pick Board çağrısı): boş
        // geçilir ve oturumun BC kullanıcısına düşülür. Web istemcisinde bu
        // gerçek sorumludur; terminalden gelirse servis hesabı kalır.
        LogAssignment(Pick."No.", FromUserId, NewUserId, Reason, '');

        // Masadaki "Toplanacak Siparişler" listesi de aynı operatörü göstersin.
        SyncPickingOrderAssignment(Pick."No.", Pick."Assigned User ID");

        WebhookMgmt.OnPickReassigned(Pick."No.", FromUserId, NewUserId);
        // Mesaja kimden kime bilgisi konur: telemetride devir zinciri tek
        // satırdan okunabilsin (wmsUserId burada devri yapanı gösterir).
        Log('Pick.Reassign', StrSubstNo(ReassignLogTxt, Pick."No.", OperatorOrNone(FromUserId), NewUserId), '');
    end;

    /// <summary>
    /// YÖNETİCİ yolu: atamayı kaldırır, toplama terminalde yeniden üstlenilebilir
    /// hale gelir. ReassignPick boş kullanıcıyı kabul etmediği için ayrı yol.
    /// </summary>
    procedure ReleasePick(var Pick: Record "Warehouse Activity Header"; Reason: Text[250])
    var
        LockedPick: Record "Warehouse Activity Header";
        FromUserId: Code[50];
    begin
        EnsurePick(Pick);
        LockedPick.LockTable();
        if not LockedPick.Get(LockedPick.Type::Pick, Pick."No.") then
            Error(PickGoneErr, Pick."No.");
        if LockedPick."Assigned User ID" = '' then
            exit;

        FromUserId := LockedPick."Assigned User ID";
        LockedPick."Assigned User ID" := '';
        LockedPick.Modify(true);
        Pick := LockedPick;

        // Atamayı kaldıran kimlik de masa tarafından gelir (bkz. ReassignPick).
        LogAssignment(Pick."No.", FromUserId, '', Reason, '');
        SyncPickingOrderAssignment(Pick."No.", '');
        Log('Pick.Unassign', StrSubstNo(ReleaseLogTxt, Pick."No.", OperatorOrNone(FromUserId)), '');
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
        Operator: Code[50];
    begin
        // Tote bağlama toplamanın parçasıdır: belge bu operatörde olmalı.
        EnsurePickOperator(Pick);
        if SourceOrderNo = '' then
            Error(SourceOrderRequiredErr);
        LP.Get(LpNo);
        EnsureSourceOrderInPick(Pick, SourceOrderNo);
        ValidateLPForPick(LP, Pick, true);

        // Sepeti bağlayan operatör = belgeyi üstlenen kullanıcı. Eskiden bu alana
        // UserId() yazılıyordu; paylaşımlı hesap yüzünden her satır aynı kimliği
        // gösteriyor ve "sepeti kim bağladı" izlenemiyordu.
        Operator := EffectiveOperator(Pick."No.", '');
        if Operator = '' then
            Operator := CopyStr(UserId(), 1, MaxStrLen(Operator));

        OtherAssignment.SetRange("LP No.", LpNo);
        OtherAssignment.SetRange(Packed, false);
        OtherAssignment.SetFilter("Pick No.", '<>%1', Pick."No.");
        if not OtherAssignment.IsEmpty() then
            Error(ToteBusyErr, LpNo);

        if Assignment.Get(Pick."No.", SourceOrderNo) then begin
            Assignment."LP No." := LpNo;
            Assignment.Packed := false;
            Assignment."Assigned By User" := CopyStr(Operator, 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Modify(true);
        end else begin
            Assignment.Init();
            Assignment."Pick No." := Pick."No.";
            Assignment."Source Order No." := SourceOrderNo;
            Assignment."LP No." := LpNo;
            Assignment."Location Code" := Pick."Location Code";
            Assignment."Assigned By User" := CopyStr(Operator, 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Insert(true);
        end;

        // LP yaşam döngüsü: Built tote pick'e Assigned olur (Release paketlemede).
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhsePick, Pick."No.");

        Log('Pick.AssignTote', Pick."No.", Operator);
    end;

    local procedure EnsureSourceOrderInPick(Pick: Record "Warehouse Activity Header"; SourceOrderNo: Code[20])
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Source Type", Database::"Sales Line");
        PickLine.SetRange("Source No.", SourceOrderNo);
        if PickLine.IsEmpty() then
            Error('Sales order %1 is not a source order of pick %2.', SourceOrderNo, Pick."No.");
    end;

    local procedure ValidateLPForPick(LP: Record "DOPSWHS LP Header"; Pick: Record "Warehouse Activity Header"; AllowAssignedToThisPick: Boolean)
    begin
        LP.TestField("Location Code");
        Pick.TestField("Location Code");
        if LP."Location Code" <> Pick."Location Code" then
            Error(
                'LP %1 belongs to location %2, but pick %3 belongs to location %4.',
                LP."No.", LP."Location Code", Pick."No.", Pick."Location Code");
        if LP.Status in [LP.Status::Used, LP.Status::Unbuilt] then
            Error('LP %1 cannot be used for picking because its status is %2.', LP."No.", LP.Status);
        if LP.Status = LP.Status::Assigned then begin
            if not AllowAssignedToThisPick then
                Error('LP %1 is already assigned to %2 %3.', LP."No.", LP."Assigned Document Type", LP."Assigned Document No.");
            if (LP."Assigned Document Type" <> LP."Assigned Document Type"::WhsePick) or
               (LP."Assigned Document No." <> Pick."No.")
            then
                Error('LP %1 is already assigned to %2 %3.', LP."No.", LP."Assigned Document Type", LP."Assigned Document No.");
        end;
    end;

    procedure GetToteForOrder(PickNo: Code[20]; SourceOrderNo: Code[20]): Code[20]
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
    begin
        if Assignment.Get(PickNo, SourceOrderNo) then
            exit(Assignment."LP No.");
        exit('');
    end;

    /// <summary>
    /// Toplama grubunun (Picking Order) toplayıcısını değiştirir — MASA/YÖNETİCİ
    /// yolu. NewUserId boş verilirse atama kaldırılır.
    ///
    /// NEDEN buraya taşındı: aynı kodu List ve Card sayfaları ayrı ayrı yazıyor,
    /// ikisi de ekrandaki (stale) kayıt üzerinden Modify ediyordu. İki sorumlu
    /// aynı grubu aynı anda atarsa biri diğerinin yazdığını sessizce eziyordu.
    /// Burada kayıt kilit altında yeniden okunur, durum doğrulanır, sonra yazılır.
    /// </summary>
    procedure SetPickingOrderPicker(var PickingHeader: Record "DOPSWHS Picking Order Header"; NewUserId: Code[50]; Reason: Text[250])
    var
        LockedHeader: Record "DOPSWHS Picking Order Header";
        PickHeader: Record "Warehouse Activity Header";
    begin
        LockedHeader.LockTable();
        if not LockedHeader.Get(PickingHeader."Entry No.") then
            Error(PickingOrderGoneErr, PickingHeader."Entry No.");
        if LockedHeader.Status = LockedHeader.Status::Completed then
            Error(PickingOrderCompletedErr, LockedHeader."Entry No.");

        // Atama aksiyonu yerel WMS kullanıcı listesini kullanır; kilitli
        // kayıt üzerindeki değeri tek adımda kalıcı hale getiririz.
        LockedHeader."Assigned User ID" := CopyStr(NewUserId, 1, MaxStrLen(LockedHeader."Assigned User ID"));
        LockedHeader.Modify(true);
        PickingHeader := LockedHeader;

        if LockedHeader."Warehouse Pick No." = '' then
            exit;
        // Pick kaydedilmiş/silinmişse grup ataması yine de güncel kalsın: hata verme.
        if not PickHeader.Get(PickHeader.Type::Pick, LockedHeader."Warehouse Pick No.") then
            exit;

        if NewUserId <> '' then begin
            ReassignPick(PickHeader, NewUserId, Reason);
            exit;
        end;

        // Atamayı kaldırma: ReassignPick boş kullanıcıyı kabul etmez, ayrı yol.
        ReleasePick(PickHeader, Reason);
    end;

    local procedure EnsurePick(var Pick: Record "Warehouse Activity Header")
    begin
        if Pick.Type <> Pick.Type::Pick then
            Error('Warehouse activity %1 must be a Pick.', Pick."No.");
    end;

    /// <summary>
    /// İşlemi yapan operatörü belirler: çağıran kimliğini AÇIKÇA bildirdiyse o
    /// kullanılır, aksi halde belgeyi üstlenmiş kullanıcıya bakılır.
    /// NEDEN: paylaşımlı BC hesabı yüzünden UserId() operatörü göstermiyor;
    /// atama alanı elimizdeki tek güvenilir "kim çalışıyor" kaynağı.
    /// </summary>
    local procedure EffectiveOperator(PickNo: Code[20]; RequestingUserId: Code[50]): Code[50]
    begin
        if RequestingUserId <> '' then
            exit(RequestingUserId);
        exit(PickOperator(PickNo));
    end;

    /// <summary>Belgeyi üstlenmiş operatör — veritabanından GÜNCEL okunur.</summary>
    local procedure PickOperator(PickNo: Code[20]): Code[50]
    var
        PickHeader: Record "Warehouse Activity Header";
    begin
        if PickNo = '' then
            exit('');
        if not PickHeader.Get(PickHeader.Type::Pick, PickNo) then
            exit('');
        exit(PickHeader."Assigned User ID");
    end;

    /// <summary>Log mesajında boş kimliği okunur hale getirir.</summary>
    local procedure OperatorOrNone(UserIdValue: Code[50]): Text
    begin
        if UserIdValue = '' then
            exit(NoOperatorTxt);
        exit(UserIdValue);
    end;

    /// <summary>
    /// İşlemi YAPAN operatörle birlikte loglar. Operatör parametresi BİLEREK
    /// zorunlu: her çağrı yeri "kim yaptı" sorusuna cevap vermek zorunda kalsın,
    /// sessizce servis hesabına düşmesin. Bilinmiyorsa açıkça '' geçilir
    /// (telemetri bunu 'actorSource=BC' ile işaretler).
    /// </summary>
    local procedure Log(Category: Text; Message: Text; OperatorUserId: Code[50])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, Message, OperatorUserId);
    end;

    var
        SourceOrderRequiredErr: Label 'Source order no. is required to assign a tote.';
        ToteBusyErr: Label 'Tote %1 is still in use by another pick. Complete or release it first.', Comment = '%1 = LP No.';
        PickTakenErr: Label 'Toplama %1 şu anda %2 kullanıcısında. Üzerinize alamazsınız; devir için depo sorumlusundan yeniden atama isteyin.', Comment = '%1 = Pick No., %2 = operatör';
        PickOwnedByOtherErr: Label 'Toplama %1 %2 kullanıcısında. Bu belgede işlem yapamazsınız.', Comment = '%1 = Pick No., %2 = operatör';
        PickUnassignedErr: Label 'Toplama %1 kimseye atanmadı. İşleme başlamadan önce "Üzerime Al" ile toplamayı üstlenin.', Comment = '%1 = Pick No.';
        PickGoneErr: Label 'Toplama %1 artık açık değil — kaydedilmiş ya da silinmiş olabilir. Listeyi yenileyin.', Comment = '%1 = Pick No.';
        PickingOrderGoneErr: Label 'Toplama grubu %1 bulunamadı — silinmiş olabilir. Listeyi yenileyin.', Comment = '%1 = Entry No.';
        PickingOrderCompletedErr: Label 'Toplama grubu %1 tamamlandı; ataması değiştirilemez.', Comment = '%1 = Entry No.';
        NewUserRequiredErr: Label 'Atanacak kullanıcı seçilmedi.';
        RequestingUserRequiredErr: Label 'İşlemi yapan operatör kimliği gönderilmedi.';
        PickCancelHandledErr: Label 'Toplama %1 üzerinde kaydedilmiş hareket var; güvenli iptal edilemez.', Comment = '%1 = Pick No.';
        PickLineBinRequiredErr: Label '%1 toplamasının %2 satırında (%3 ürünü) kaynak raf/bin boş. Bin içeriğini düzeltip pick''i yeniden oluşturun; rafı belli olmayan satır terminalden onaylanamaz.', Comment = '%1 = Pick No., %2 = Line No., %3 = Item No.';
        SelfClaimReasonLbl: Label 'Terminalden üzerine alındı.';
        UnassignedLbl: Label 'atanmamış';
        // Telemetri mesajları çevrilmez (Locked): log sorguları dile göre değişmemeli.
        ReassignLogTxt: Label '%1: %2 -> %3', Locked = true;
        ReleaseLogTxt: Label '%1: %2 -> (none)', Locked = true;
        NoOperatorTxt: Label '(none)', Locked = true;
}
