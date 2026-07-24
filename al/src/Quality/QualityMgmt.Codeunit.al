codeunit 72255 "DOPSWHS Quality Mgmt"
{
    // Quality inspection orders, managed from the mobile app. A quality order gates goods (typically
    // received or produced) until an inspector passes/fails them; failing routes to a quarantine bin.
    //
    // NOT: Bu dosyaya yapılan GKK genişletmesi bu ortamda derlenmedi (BC sembol paketi/sandbox
    // erişimi yok). Merge öncesi VS Code + AL derleyicisiyle veya bir BC sandbox'ta doğrulanmalı.
    //
    // Bu codeunit, BC v28'e özgü Microsoft Quality Management eklentisine bağımlı olan
    // (ve bu yüzden devre dışı bırakılmış — bkz. QualityMgmtBridge.Codeunit.al) yol yerine,
    // uygulamanın kendi "DOPSWHS Quality Order" tablosunu kullanır. Bu tablo ve mobil API
    // (QualityOrderApi.Page.al) zaten mevcuttu; eksik olan tek şey gerçek akışlara (mal kabul,
    // pick, movement) bağlanmasıydı.
    Access = Public;

    /// <summary>
    /// Verilen LP/Item/Bin için açık (Open veya InProgress) bir Quality Order varsa true döner.
    /// LP No. öncelikli eşleşme kriteridir (birim-bazlı blok); LP yoksa Item+Bin fallback kullanılır.
    /// </summary>
    procedure IsBlocked(LpNo: Code[20]; ItemNo: Code[20]; BinCode: Code[20]): Boolean
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        exit(FindBlockingOrder(LpNo, ItemNo, BinCode, QualityOrder));
    end;

    /// <summary>
    /// Hard guard — blok varsa Error fırlatır. Hata metni mobil/web QcErrorParser'ın
    /// yakalayabileceği formatta ("blocked by quality order QO-...").
    /// </summary>
    procedure VerifyNotBlocked(LpNo: Code[20]; ItemNo: Code[20]; BinCode: Code[20])
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        if FindBlockingOrder(LpNo, ItemNo, BinCode, QualityOrder) then
            Error(QcBlockedErr, QualityOrder."No.");
    end;

    local procedure FindBlockingOrder(LpNo: Code[20]; ItemNo: Code[20]; BinCode: Code[20]; var QualityOrder: Record "DOPSWHS Quality Order"): Boolean
    begin
        if (LpNo = '') and (ItemNo = '') then
            exit(false);

        QualityOrder.Reset();
        QualityOrder.SetFilter(Status, '%1|%2', QualityOrder.Status::Open, QualityOrder.Status::InProgress);

        if LpNo <> '' then begin
            QualityOrder.SetRange("LP No.", LpNo);
            if QualityOrder.FindFirst() then
                exit(true);
            QualityOrder.SetRange("LP No.");
        end;

        // LP yoksa (henüz LP'ye toplanmamış satır) Item+Bin fallback.
        if (ItemNo <> '') and (BinCode <> '') then begin
            QualityOrder.SetRange("Item No.", ItemNo);
            QualityOrder.SetRange("Bin Code", BinCode);
            exit(QualityOrder.FindFirst());
        end;

        exit(false);
    end;

    /// <summary>
    /// Mal kabulde Item."DOPSWHS QC Required" açıksa çağrılır: bir Quality Order açar ve
    /// Setup'ta "Default Quarantine Bin Code" tanımlıysa hedef bin'i döndürür (çağıran taraf
    /// Warehouse Receipt Line'ın Bin Code'unu buna göre günceller). Setup'ta karantina bin'i
    /// tanımlı değilse boş döner — Quality Order yine de açılır, sadece bin yönlendirmesi
    /// yapılmaz (mevcut bin'de kalır, blok yine Pick/Movement seviyesinde uygulanır).
    /// </summary>
    procedure CreateOrderForReceipt(ReceiptNo: Code[20]; ItemNo: Code[20]; Qty: Decimal; LocationCode: Code[10]; ReceivingBinCode: Code[20]; LpNo: Code[20]; var QuarantineBinCode: Code[20]): Code[20]
    var
        Setup: Record "DOPSWHS Setup";
        TargetBinCode: Code[20];
    begin
        QuarantineBinCode := '';
        TargetBinCode := ReceivingBinCode;
        if Setup.Get('') and (Setup."Default Quarantine Bin Code" <> '') then begin
            TargetBinCode := Setup."Default Quarantine Bin Code";
            QuarantineBinCode := TargetBinCode;
        end;

        exit(CreateOrder(1, ReceiptNo, ItemNo, Qty, LocationCode, TargetBinCode, LpNo));  // 1 = Source Type::Receipt
    end;

    /// <summary>Creates an open quality order and returns its No.</summary>
    procedure CreateOrder(SourceTypeOpt: Integer; SourceNo: Code[20]; ItemNo: Code[20]; Qty: Decimal; LocationCode: Code[10]; BinCode: Code[20]; LpNo: Code[20]): Code[20]
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        Item: Record Item;
    begin
        QualityOrder.Init();
        QualityOrder."No." := NextNo();
        QualityOrder."Source Type" := SourceTypeOpt;
        QualityOrder."Source No." := SourceNo;
        QualityOrder."Item No." := ItemNo;
        if Item.Get(ItemNo) then
            QualityOrder."Item Description" := CopyStr(Item.Description, 1, MaxStrLen(QualityOrder."Item Description"));
        QualityOrder."Quantity" := Qty;
        QualityOrder."Sample Size" := SampleSizeFor(Qty);
        QualityOrder."Location Code" := LocationCode;
        QualityOrder."Bin Code" := BinCode;
        QualityOrder."LP No." := LpNo;
        QualityOrder."Status" := QualityOrder."Status"::Open;
        QualityOrder."Created DateTime" := CurrentDateTime();
        QualityOrder."Due Date" := Today();
        QualityOrder.Insert(true);
        exit(QualityOrder."No.");
    end;

    /// <summary>Records a PASS result; goods are released for normal handling.</summary>
    procedure Pass(var QualityOrder: Record "DOPSWHS Quality Order"; Inspector: Code[50]; Notes: Text[250])
    begin
        QualityOrder.TestField(Status, QualityOrder.Status::Open);
        QualityOrder."Status" := QualityOrder."Status"::Passed;
        QualityOrder."Inspector" := Inspector;
        QualityOrder."Inspected DateTime" := CurrentDateTime();
        QualityOrder."Result Notes" := Notes;
        QualityOrder.Modify(true);
        LogTelemetry('AdvWMS.Quality.Passed', QualityOrder."No.");
    end;

    /// <summary>Records a FAIL result with a reason; goods are routed to the quarantine bin.</summary>
    procedure Fail(var QualityOrder: Record "DOPSWHS Quality Order"; Inspector: Code[50]; ReasonCode: Code[20]; Notes: Text[250]; QuarantineBin: Code[20])
    begin
        QualityOrder.TestField(Status, QualityOrder.Status::Open);
        QualityOrder."Status" := QualityOrder."Status"::Failed;
        QualityOrder."Inspector" := Inspector;
        QualityOrder."Inspected DateTime" := CurrentDateTime();
        QualityOrder."Reject Reason" := ReasonCode;
        QualityOrder."Result Notes" := Notes;
        QualityOrder."Quarantine Bin" := QuarantineBin;
        QualityOrder.Modify(true);
        LogTelemetry('AdvWMS.Quality.Failed', QualityOrder."No.");
    end;

    /// <summary>Seeds a couple of demo quality orders so the mobile screen is testable out of the box.</summary>
    procedure SeedDemoOrders()
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        Item: Record Item;
        Setup: Record "DOPSWHS Setup";
        LocationCode: Code[10];
    begin
        if not QualityOrder.IsEmpty() then
            exit;
        if Setup.Get('') then
            LocationCode := Setup."Default Location Code";
        Item.SetRange(Type, Item.Type::Inventory);
        Item.SetRange(Blocked, false);
        if Item.FindSet() then
            repeat
                CreateOrder(1, 'DEMO', Item."No.", 10, LocationCode, '', '');  // 1 = Source Type::Receipt
            until (Item.Next() = 0) or (QualityOrder.Count() >= 3);
    end;

    local procedure NextNo(): Code[20]
    var
        QualityOrder: Record "DOPSWHS Quality Order";
        Base: Text;
        Candidate: Code[20];
        Suffix: Integer;
    begin
        // Timestamp-based number (no No. Series dependency); add a suffix so multiple orders created in
        // the same second don't collide.
        Base := 'QO-' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>');
        Candidate := CopyStr(Base, 1, 20);
        while QualityOrder.Get(Candidate) do begin
            Suffix += 1;
            Candidate := CopyStr(Base + '-' + Format(Suffix), 1, 20);
        end;
        exit(Candidate);
    end;

    local procedure SampleSizeFor(Qty: Decimal) Sample: Decimal
    begin
        // Simple ANSI-style sampling: ~10% of the lot, min 1, capped at 20.
        if Qty <= 0 then
            exit(0);
        Sample := Round(Qty * 0.1, 1, '>');
        if Sample < 1 then Sample := 1;
        if Sample > 20 then Sample := 20;
    end;

    local procedure LogTelemetry(EventId: Text; QoNo: Code[20])
    var
        Dimensions: Dictionary of [Text, Text];
    begin
        Dimensions.Add('qualityOrderNo', QoNo);
        Session.LogMessage(EventId, StrSubstNo('Quality order %1', QoNo), Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    var
        QcBlockedErr: Label 'Bu LP/madde açık bir Quality Order (%1) tarafından bloklanıyor. blocked by quality order %1', Comment = '%1 = quality order no.';
}
