// NOT: Bu test codeunit'i yerel bir BC AL derleyicisi olmadan yazıldı (.NET 8 runtime /
// BC sembol paketi bu ortamda mevcut değil, bkz. al/src/Quality/QualityMgmt.Codeunit.al
// başındaki aynı uyarı). Merge öncesi VS Code + AL eklentisiyle (veya varsa bir CI AL
// derleme/test adımıyla) mutlaka derlenip çalıştırılarak doğrulanmalı.
//
// Ayrıca: bu paketteki "Assert" / "Library Assert" codeunit'leri (al-tests/src/
// TestLibraryStubs.Codeunit.al, codeunit 72490/72491) boş gövdeli stub'lardır — bütün
// paket genelinde (bu dosya dahil) Assert.* çağrıları şu an gerçek bir doğrulama YAPMAZ,
// sadece niyeti belgeler. Testlerin gerçek değeri, asserterror + doğrudan prosedür
// çağrılarının ilgili kod yollarını gerçekten tetiklemesinden geliyor (ör. VerifyNotBlocked
// gerçekten Error fırlatıyor mu). Bu, bu dosyaya özgü değil — mevcut 40+ test dosyasının
// tamamında aynı durum; burada tekrar bayraklıyoruz.
codeunit 72141 "DOPSWHS Quality Gate Tests"
{
    Subtype = Test;

    // ------------------------------------------------------------------
    // Pick / Movement blocking (VerifyNotBlocked / IsBlocked)
    // ------------------------------------------------------------------

    [Test]
    procedure PickBlockedWhileQualityOrderOpen()
    var
        Pick: Record "Warehouse Activity Header";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
        Assert: Codeunit Assert;
        QoNo: Code[20];
    begin
        // Item + Bin bloklu (LP yok), pick satırı da aynı Item+Bin ile eşleşiyor -> RegisterPick
        // Whse.-Activity-Register'a hiç ulaşmadan VerifyNotBlocked'da Error fırlatmalı.
        SeedLocationBin('BLUE', 'PICK01');
        CreateItem('ITEM-QG-1', true);
        QoNo := QualityMgmt.CreateOrder(0, 'MANUAL-QG-1', 'ITEM-QG-1', 10, 'BLUE', 'PICK01', '');  // 0 = Source Type::Manual

        CreateActivityHeader(Pick, Pick.Type::Pick, 'PICK-QG-1', 'BLUE');
        CreateActivityLine(Pick.Type::Pick, 'PICK-QG-1', 'ITEM-QG-1', 'PICK01', '');

        asserterror PickMgmt.RegisterPick(Pick);
        Assert.ExpectedError(QoNo);
    end;

    [Test]
    procedure MovementBlockedWhileQualityOrderOpen()
    var
        Movement: Record "Warehouse Activity Header";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
        Assert: Codeunit Assert;
        QoNo: Code[20];
    begin
        SeedLocationBin('BLUE', 'MOVE01');
        CreateItem('ITEM-QG-2', true);
        QoNo := QualityMgmt.CreateOrder(0, 'MANUAL-QG-2', 'ITEM-QG-2', 5, 'BLUE', 'MOVE01', '');

        CreateActivityHeader(Movement, Movement.Type::Movement, 'MOVE-QG-1', 'BLUE');
        CreateActivityLine(Movement.Type::Movement, 'MOVE-QG-1', 'ITEM-QG-2', 'MOVE01', '');

        asserterror MovementMgmt.RegisterDirected(Movement);
        Assert.ExpectedError(QoNo);
    end;

    [Test]
    procedure QualityOrderUnblocksAfterPass()
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        Assert: Codeunit Assert;
        QoNo: Code[20];
    begin
        // "Bloklar ... quality order'ı çözülene kadar" senaryosunun ikinci yarısı:
        // Pass() sonrası Status Open/InProgress dışına çıktığı için IsBlocked/VerifyNotBlocked
        // artık blok bildirmemeli. RegisterPick'in gerçek Whse.-Activity-Register çağrısı
        // (stok/ledger kurulumu gerektirir) burada bilerek devre dışı bırakılmadı; mevcut
        // suite'teki diğer Register testleri de aynı nedenle satırsız/no-op smoke test
        // kalıbını kullanıyor (bkz. PickRegisterTests.Codeunit.al) — o yüzden burada blok
        // mantığını doğrudan QualityMgmt üzerinden, entegrasyon noktasından bağımsız test
        // ediyoruz.
        SeedLocationBin('BLUE', 'PICK02');
        CreateItem('ITEM-QG-3', true);
        QoNo := QualityMgmt.CreateOrder(0, 'MANUAL-QG-3', 'ITEM-QG-3', 8, 'BLUE', 'PICK02', '');

        Assert.IsTrue(QualityMgmt.IsBlocked('', 'ITEM-QG-3', 'PICK02'), 'Open quality order must block Item+Bin before resolution.');

        QualityOrder.Get(QoNo);
        QualityMgmt.Pass(QualityOrder, 'INSPECTOR1', 'OK - sample passed');

        Assert.IsFalse(QualityMgmt.IsBlocked('', 'ITEM-QG-3', 'PICK02'), 'Passed quality order must no longer block Item+Bin.');
    end;

    [Test]
    procedure IsBlockedMatchesByLpNoRegardlessOfBin()
    var
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        Assert: Codeunit Assert;
    begin
        // Dokümantasyon: "LP No. öncelikli eşleşme kriteridir". LP eşleşiyorsa Bin farklı
        // olsa da blok uygulanmalı (LP bazlı blok, birim bazlı — LP nereye taşınırsa taşınsın).
        SeedLocationBin('BLUE', 'PICK03');
        CreateItem('ITEM-QG-4', true);
        QualityMgmt.CreateOrder(0, 'MANUAL-QG-4', 'ITEM-QG-4', 3, 'BLUE', 'PICK03', 'LP-QG-4');

        Assert.IsTrue(QualityMgmt.IsBlocked('LP-QG-4', 'ITEM-QG-4', 'SOME-OTHER-BIN'), 'LP No. match must block regardless of the bin passed in.');
    end;

    [Test]
    procedure IsBlockedFalseWhenBinDoesNotMatch()
    var
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
        Assert: Codeunit Assert;
    begin
        // FindBlockingOrder local olduğu için doğrudan çağrılamıyor (bkz. al/src/Quality/
        // QualityMgmt.Codeunit.al) — doğruluğunu IsBlocked üzerinden dolaylı test ediyoruz:
        // aynı Item ama farklı Bin (ve LP yok) eşleşmemeli.
        SeedLocationBin('BLUE', 'PICK04');
        SeedLocationBin('BLUE', 'PICK05');
        CreateItem('ITEM-QG-5', true);
        QualityMgmt.CreateOrder(0, 'MANUAL-QG-5', 'ITEM-QG-5', 4, 'BLUE', 'PICK04', '');

        Assert.IsFalse(QualityMgmt.IsBlocked('', 'ITEM-QG-5', 'PICK05'), 'Quality order for a different bin must not block an unrelated bin.');
    end;

    // ------------------------------------------------------------------
    // Receipt auto-quarantine routing (ReceiptMgmt.ConfirmLine -> CreateOrderForReceipt)
    // ------------------------------------------------------------------

    [Test]
    procedure ReceiptOfQCRequiredItemAutoRoutesToQuarantineBin()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        Setup: Record "DOPSWHS Setup";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        QualityOrder: Record "DOPSWHS Quality Order";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        Assert: Codeunit Assert;
    begin
        SeedLocationBin('BLUE', 'RECEIVE');
        SeedLocationBin('BLUE', 'QUAR01');
        Setup := TestHelper.EnsureSetup();
        Setup."Default Location Code" := 'BLUE';
        Setup."Default Quarantine Bin Code" := 'QUAR01';
        Setup.Modify(true);

        CreateItem('ITEM-QG-RCPT', true);
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-QG-1', 'ITEM-QG-RCPT', 'RECEIVE', 20);

        // LicensePlateNo boş bırakılıyor -> CreateOrderForReceipt Item+Bin fallback ile
        // bloklayan bir Quality Order açar; Setup'ta tanımlı karantina bin'i (QUAR01)
        // çağıran tarafa (ConfirmLine) döner ve satırın Bin Code'u ona göre değiştirilir.
        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 20, '', '', 0D, '', 'RECEIVE');

        WhseReceiptLine.Get(WhseReceiptHeader."No.", 10000);
        Assert.AreEqual('QUAR01', WhseReceiptLine."Bin Code", 'QC-required receipt line must be re-routed to the Setup default quarantine bin.');

        QualityOrder.SetRange("Item No.", 'ITEM-QG-RCPT');
        QualityOrder.SetRange("Source No.", WhseReceiptHeader."No.");
        Assert.IsFalse(QualityOrder.IsEmpty(), 'ConfirmLine must auto-open a quality order for a QC-required item on receipt.');
        QualityOrder.FindFirst();
        Assert.AreEqual(QualityOrder.Status::Open, QualityOrder.Status, 'Auto-opened quality order must start Open.');
        Assert.AreEqual('QUAR01', QualityOrder."Bin Code", 'Quality order must record the quarantine bin.');
    end;

    [Test]
    procedure ReceiptOfNonQCItemDoesNotCreateQualityOrderOrChangeBin()
    var
        TestHelper: Codeunit "DOPSWHS Test Helper";
        Setup: Record "DOPSWHS Setup";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        QualityOrder: Record "DOPSWHS Quality Order";
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
        Assert: Codeunit Assert;
    begin
        // Regresyon: "DOPSWHS QC Required" kapalı bir madde için mevcut mal kabul akışı
        // (bin yönlendirmesi/Quality Order açma) hiç tetiklenmemeli.
        SeedLocationBin('BLUE', 'RECEIVE');
        SeedLocationBin('BLUE', 'QUAR01');
        Setup := TestHelper.EnsureSetup();
        Setup."Default Location Code" := 'BLUE';
        Setup."Default Quarantine Bin Code" := 'QUAR01';
        Setup.Modify(true);

        CreateItem('ITEM-QG-NOQC', false);
        CreateReceipt(WhseReceiptHeader, WhseReceiptLine, 'PO-QG-2', 'ITEM-QG-NOQC', 'RECEIVE', 15);

        ReceiptMgmt.ConfirmLine(WhseReceiptLine, 15, '', '', 0D, '', 'RECEIVE');

        WhseReceiptLine.Get(WhseReceiptHeader."No.", 10000);
        Assert.AreEqual('RECEIVE', WhseReceiptLine."Bin Code", 'Non-QC item must keep its original receiving bin.');

        QualityOrder.SetRange("Item No.", 'ITEM-QG-NOQC');
        QualityOrder.SetRange("Source No.", WhseReceiptHeader."No.");
        Assert.IsTrue(QualityOrder.IsEmpty(), 'Non-QC item receipt must not auto-open a quality order.');
    end;

    // ------------------------------------------------------------------
    // Local helpers (inline test data — no dependency on production demo seeders)
    // ------------------------------------------------------------------

    local procedure CreateItem(ItemNo: Code[20]; QcRequired: Boolean)
    var
        Item: Record Item;
    begin
        if Item.Get(ItemNo) then
            Item.Delete(true);
        Item.Init();
        Item."No." := ItemNo;
        Item.Type := Item.Type::Inventory;
        Item.Description := CopyStr('GKK test item ' + ItemNo, 1, MaxStrLen(Item.Description));
        Item."DOPSWHS QC Required" := QcRequired;
        Item.Insert(true);
    end;

    local procedure SeedLocationBin(LocationCode: Code[10]; BinCode: Code[20])
    var
        Location: Record Location;
        Bin: Record Bin;
    begin
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not Bin.Get(LocationCode, BinCode) then begin
            Bin.Init();
            Bin."Location Code" := LocationCode;
            Bin.Code := BinCode;
            Bin.Insert(true);
        end;
    end;

    local procedure CreateActivityHeader(var Header: Record "Warehouse Activity Header"; TypeOpt: Integer; No: Code[20]; LocationCode: Code[10])
    begin
        // TypeOpt Integer -> "Type" Option: aynı örtük dönüşüm QualityMgmt.CreateOrder'ın
        // SourceTypeOpt -> "Source Type" ataması ile aynı kalıp (bkz. al/src/Quality/
        // QualityMgmt.Codeunit.al), yeni bir tür dönüşümü varsayımı eklemiyoruz.
        Header.Init();
        Header.Type := TypeOpt;
        Header."No." := No;
        Header."Location Code" := LocationCode;
        Header.Insert(true);
    end;

    local procedure CreateActivityLine(TypeOpt: Integer; HeaderNo: Code[20]; ItemNo: Code[20]; BinCode: Code[20]; LpNo: Code[20])
    var
        Line: Record "Warehouse Activity Line";
    begin
        Line.Init();
        Line."Activity Type" := TypeOpt;
        Line."No." := HeaderNo;
        Line."Line No." := 10000;
        Line."Item No." := ItemNo;
        Line."Bin Code" := BinCode;
        Line."LP No." := LpNo;
        Line.Quantity := 1;
        Line.Insert(true);
    end;

    local procedure CreateReceipt(var Header: Record "Warehouse Receipt Header"; var Line: Record "Warehouse Receipt Line"; SourceNo: Code[20]; ItemNo: Code[20]; BinCode: Code[20]; Qty: Decimal)
    begin
        Header.Init();
        Header."No." := SourceNo + '-RCPT';
        Header."Location Code" := 'BLUE';
        Header.Insert(true);

        Line.Init();
        Line."No." := Header."No.";
        Line."Line No." := 10000;
        Line."Source No." := SourceNo;
        Line."Item No." := ItemNo;
        Line.Description := 'GKK test receipt line';
        Line."Unit of Measure Code" := 'PCS';
        Line.Quantity := Qty;
        Line."Qty. to Receive" := Qty;
        Line."Bin Code" := BinCode;
        Line."Location Code" := 'BLUE';
        Line.Insert(true);
    end;
}
