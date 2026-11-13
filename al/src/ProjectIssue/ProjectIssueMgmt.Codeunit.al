codeunit 72477 "DOPSWHS Project Issue Mgmt"
{
    // Kitoko/Element4 #3338 (11 Kas 2026): el terminalinden SAHA İŞ EMRİNE malzeme çıkışı.
    //
    // Saha İş Emri "DynOps Project Management Core" uzantısındadır (tablo 75641 başlık,
    // 75643 satır). O uzantı her ortamda/şirkette kurulu olmadığından derleme bağımlılığı
    // eklenmedi: kayıtlar RecordRef ile tablo/alan numarasından okunur. Uzantı yoksa
    // liste boş döner, çıkış anlaşılır bir hatayla durur.
    //
    // Çıkış BC standardında PROJE KULLANIMI olarak kaydedilir: Proje Günlüğü satırı
    // (Tür = Madde, Proje No., Proje Görevi No., Belge No. = saha iş emri no.) "Job
    // Jnl.-Post Batch" ile onay sorulmadan işlenir. Böylece madde defteri (stok düşer),
    // proje defteri (proje bazında maliyet ve rapor) ve PROJE boyutu birlikte oluşur.
    Access = Public;
    Permissions =
        tabledata "Job Journal Template" = RIMD,
        tabledata "Job Journal Batch" = RIMD,
        tabledata "Job Journal Line" = RIMD,
        tabledata "Job Ledger Entry" = R,
        tabledata "Job Planning Line" = RIMD,
        tabledata "Warehouse Activity Header" = RIMD,
        tabledata "Warehouse Activity Line" = RIMD,
        tabledata "Reservation Entry" = RIMD,
        tabledata "Dimension Value" = R,
        tabledata "DOPSWHS Setup" = R;

    var
        WorkOrderTableNo: Integer;
        WorkLineTableNo: Integer;
        NotInstalledErr: Label 'Proje Yönetimi (Saha İş Emri) uzantısı bu şirkette kurulu değil.';
        WorkOrderNotFoundErr: Label '%1 saha iş emri bulunamadı.', Comment = '%1 = work order no.';
        WorkOrderClosedErr: Label '%1 saha iş emri kapalı (%2); çıkış yapılamaz.', Comment = '%1 = work order no., %2 = status';
        NoProjectErr: Label '%1 saha iş emrinde proje no. yok.', Comment = '%1 = work order no.';
        NoTaskErr: Label '%1 saha iş emrinde proje görevi yok. Planlama iş emrine proje görevini girmeli.', Comment = '%1 = work order no.';
        QtyErr: Label 'Çıkış miktarı 0''dan büyük olmalı.';
        ItemErr: Label 'Ürün no. girin.';
        LocationErr: Label 'Lokasyon girin.';
        DirectedErr: Label '%1 lokasyonu yönlendirilmiş (Directed Put-away and Pick); projeye çıkış bu ekrandan yapılamaz.', Comment = '%1 = location';
        PickRequiredErr: Label '%1 lokasyonunda proje tüketimi ambar toplaması zorunlu; projeye çıkış bu ekrandan yapılamaz.', Comment = '%1 = location';
        BinRequiredErr: Label '%1 lokasyonu raf zorunlu: önce rafı okutun.', Comment = '%1 = location';
        BinNotFoundErr: Label '%1 rafı %2 lokasyonunda yok.', Comment = '%1 = bin, %2 = location';
        LotRequiredErr: Label '%1 lot takipli: lot numarasını girin veya lotlu LP''yi okutun.', Comment = '%1 = item';
        SerialRequiredErr: Label '%1 seri takipli: seri numarasını girin.', Comment = '%1 = item';
        SerialQtyErr: Label '%1 seri numarası tek bir birimdir; miktar 1 olmalı.', Comment = '%1 = serial';
        NoReadPermissionErr: Label 'Saha iş emirlerini okuma yetkiniz yok. BC''de Proje Yönetimi izin kümesini kontrol edin.';
        LooseStockErr: Label '%1 ürününün %2 %3 konumundaki LP''ye atanmamış serbest stoku yetersiz. Stok: %4, LP''lerdeki: %5, istenen: %6. Palet/kutudan veriyorsanız LP''yi okutun.', Comment = '%1 item, %2 location, %3 bin, %4 stock, %5 allocated, %6 required';
        ToJobBinErr: Label '%1 lokasyonunda "Projeye Depo Gözü Kodu" tanımlı değil. Yönlendirilmiş lokasyonda projeye çıkış için Konum Kartı > Depo Gözleri > Proje alanını doldurun.', Comment = '%1 = location';
        UserRequiredErr: Label 'Ambar toplaması için terminal kullanıcısı zorunludur.';
        PickNotCreatedErr: Label '%1 için %2 rafından ambar toplaması oluşturulamadı. Rafta toplanabilir stok olduğunu kontrol edin.', Comment = '%1 item, %2 bin';
        PickShortErr: Label '%1 için %2 rafında yeterli toplanabilir stok yok (eksik temel miktar: %3).', Comment = '%1 item, %2 bin, %3 qty';
        NotPostedErr: Label 'Proje kullanımı kaydedilemedi; proje defterinde kayıt bulunamadı.';
        TemplateNameTok: Label 'WMSPROJE', Locked = true;

    procedure IsAvailable(): Boolean
    var
        AllObj: Record AllObj;
    begin
        InitIds();
        AllObj.SetRange("Object Type", AllObj."Object Type"::Table);
        AllObj.SetRange("Object ID", WorkOrderTableNo);
        if AllObj.IsEmpty() then
            exit(false);
        AllObj.SetRange("Object ID", WorkLineTableNo);
        exit(not AllObj.IsEmpty());
    end;

    /// <summary>Açık (tamamlanmamış/iptal edilmemiş) saha iş emirlerini buffer'a doldurur.</summary>
    procedure FillOpenWorkOrders(var Buffer: Record "DOPSWHS Field WO Buffer" temporary)
    var
        WorkOrder: RecordRef;
    begin
        Buffer.Reset();
        Buffer.DeleteAll();
        if not IsAvailable() then
            exit;
        WorkOrder.Open(WorkOrderTableNo);
        if not WorkOrder.ReadPermission() then
            Error(NoReadPermissionErr);
        if WorkOrder.FindSet() then
            repeat
                if not IsClosedStatus(WorkOrder.Field(10)) then
                    InsertWorkOrderBuffer(WorkOrder, Buffer);
            until WorkOrder.Next() = 0;
        WorkOrder.Close();
    end;

    /// <summary>Açık saha iş emirlerinin satırlarını buffer'a doldurur.</summary>
    procedure FillOpenWorkOrderLines(var LineBuffer: Record "DOPSWHS Field WO Line Buffer" temporary)
    var
        Orders: Record "DOPSWHS Field WO Buffer" temporary;
    begin
        LineBuffer.Reset();
        LineBuffer.DeleteAll();
        FillOpenWorkOrders(Orders);
        if Orders.FindSet() then
            repeat
                AppendLines(Orders."No.", LineBuffer);
            until Orders.Next() = 0;
    end;

    /// <summary>
    /// Saha iş emrine malzeme çıkışı. Proje kullanımı + (LP okutulduysa) LP içerik düşümü +
    /// iş emri satırının gerçekleşen miktarı tek işlemde yapılır; herhangi biri hata verirse
    /// hiçbiri kalıcı olmaz. Dönüş: terminalde gösterilecek kısa özet.
    /// </summary>
    procedure IssueItem(WorkOrderNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; Qty: Decimal; UomCode: Code[10]; LocationCode: Code[10]; BinCode: Code[20]; LpNo: Code[20]; LotNo: Code[50]; SerialNo: Code[50]; WmsUserId: Code[50]): Text
    var
        Orders: Record "DOPSWHS Field WO Buffer" temporary;
        Item: Record Item;
        Location: Record Location;
        Bin: Record Bin;
        JobJnlLine: Record "Job Journal Line";
        JobLedgerEntry: Record "Job Ledger Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        JobJnlPostBatch: Codeunit "Job Jnl.-Post Batch";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        CustomDimensions: Dictionary of [Text, Text];
        LotTracked: Boolean;
        SerialTracked: Boolean;
        BaseQty: Decimal;
        LastJobEntryNo: Integer;
        TemplateName: Code[10];
        BatchName: Code[10];
        ActualNote: Text;
        UsePick: Boolean;
        EntryNo: Integer;
        PickNo: Code[20];
    begin
        if not IsAvailable() then
            Error(NotInstalledErr);
        if ItemNo = '' then
            Error(ItemErr);
        if Qty <= 0 then
            Error(QtyErr);
        if LocationCode = '' then
            Error(LocationErr);

        GetWorkOrder(WorkOrderNo, Orders);
        if Orders."Project No." = '' then
            Error(NoProjectErr, WorkOrderNo);
        if Orders."Project Task No." = '' then
            Error(NoTaskErr, WorkOrderNo);

        Location.Get(LocationCode);
        // Yönlendirilmiş veya proje tüketiminde ambar toplaması zorunlu lokasyonda BC proje
        // günlüğünden doğrudan düşüme izin vermez: planlama satırı + ambar toplaması yolu.
        UsePick := Location."Directed Put-away and Pick" or
            (Location."Job Consump. Whse. Handling" = Location."Job Consump. Whse. Handling"::"Warehouse Pick (mandatory)");
        if UsePick and (Location."To-Job Bin Code" = '') then
            Error(ToJobBinErr, LocationCode);
        if Location."Bin Mandatory" or Location."Directed Put-away and Pick" then begin
            if BinCode = '' then
                Error(BinRequiredErr, LocationCode);
            if not Bin.Get(LocationCode, BinCode) then
                Error(BinNotFoundErr, BinCode, LocationCode);
        end else
            BinCode := '';

        Item.Get(ItemNo);
        if UomCode = '' then
            UomCode := Item."Base Unit of Measure";
        GetTracking(Item, LotTracked, SerialTracked);
        if UsePick and SerialTracked then
            Error('Seri takipli ürünün yönlendirilmiş depodan projeye çıkışını standart BC proje toplama akışından yapın.');
        if LotTracked and (LotNo = '') and (LpNo <> '') then
            LotNo := LPMgt.SingleLotOnLp(LpNo, ItemNo, VariantCode);
        if LotTracked and (LotNo = '') then
            Error(LotRequiredErr, ItemNo);
        if SerialTracked and (SerialNo = '') then
            Error(SerialRequiredErr, ItemNo);
        if (SerialNo <> '') and (Qty <> 1) then
            Error(SerialQtyErr, SerialNo);
        BaseQty := Round(Qty * QtyPerUom(Item, UomCode), 0.00001);

        // LP okutulmadıysa yalnız LP'ye atanmamış serbest stoktan çıkılır; LP içindeki
        // stok kendiliğinden bölünmez (Ad-Hoc Hareket ile aynı kural).
        if LpNo = '' then
            EnsureLooseStock(LocationCode, BinCode, ItemNo, VariantCode, LotNo, SerialNo, BaseQty);

        EnsureJournalBatch(WmsUserId, TemplateName, BatchName);
        PurgeBatch(TemplateName, BatchName);

        JobLedgerEntry.Reset();
        if JobLedgerEntry.FindLast() then
            LastJobEntryNo := JobLedgerEntry."Entry No.";

        if UsePick then begin
            EntryNo := IssueViaWarehousePick(Orders, WorkOrderNo, Item, VariantCode, UomCode, Qty, BaseQty, Location, BinCode, LpNo, LotNo,
                WmsUserId, TemplateName, BatchName, LastJobEntryNo, PickNo);
            ActualNote := AddActualQuantity(WorkOrderNo, Item, BaseQty);
            exit(StrSubstNo('%1 × %2 %3 → %4 / %5 / %6 (ambar toplama %7, proje defteri %8)%9',
                ItemNo, Format(Qty, 0, 9), UomCode, WorkOrderNo, Orders."Project No.", Orders."Project Task No.", PickNo, EntryNo, ActualNote));
        end;

        JobJnlLine.Init();
        JobJnlLine."Journal Template Name" := TemplateName;
        JobJnlLine."Journal Batch Name" := BatchName;
        JobJnlLine."Line No." := 10000;
        JobJnlLine.Validate("Posting Date", WorkDate());
        JobJnlLine."Document No." := WorkOrderNo;
        JobJnlLine.Validate("Job No.", Orders."Project No.");
        JobJnlLine.Validate("Job Task No.", Orders."Project Task No.");
        JobJnlLine.Validate(Type, JobJnlLine.Type::Item);
        JobJnlLine.Validate("No.", ItemNo);
        if VariantCode <> '' then
            JobJnlLine.Validate("Variant Code", VariantCode);
        JobJnlLine.Validate("Location Code", LocationCode);
        JobJnlLine.Validate("Unit of Measure Code", UomCode);
        if BinCode <> '' then
            JobJnlLine.Validate("Bin Code", BinCode);
        JobJnlLine.Validate(Quantity, Qty);
        JobJnlLine."External Document No." := CopyStr(WmsUserId, 1, MaxStrLen(JobJnlLine."External Document No."));
        AddProjectDimension(JobJnlLine, Orders."Project No.");
        JobJnlLine.Insert(true);
        if (LotNo <> '') or (SerialNo <> '') then
            AddTracking(JobJnlLine, LotNo, SerialNo);

        CustomDimensions.Add('Category', 'ProjectIssue');
        CustomDimensions.Add('WorkOrderNo', WorkOrderNo);
        CustomDimensions.Add('ProjectNo', Orders."Project No.");
        Telemetry.AddUserDimensions(CustomDimensions, WmsUserId);
        Session.LogMessage('DOPSWHS-ProjectIssue', StrSubstNo('Project issue item %1 qty %2 %3 from %4/%5 lp %6 work order %7 project %8',
            ItemNo, Qty, UomCode, LocationCode, BinCode, LpNo, WorkOrderNo, Orders."Project No."),
            Verbosity::Normal, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);

        JobJnlPostBatch.SetSuppressCommit(true);
        JobJnlPostBatch.Run(JobJnlLine);

        JobLedgerEntry.Reset();
        JobLedgerEntry.SetFilter("Entry No.", '>%1', LastJobEntryNo);
        JobLedgerEntry.SetRange("Job No.", Orders."Project No.");
        JobLedgerEntry.SetRange("Document No.", WorkOrderNo);
        JobLedgerEntry.SetRange(Type, JobLedgerEntry.Type::Item);
        JobLedgerEntry.SetRange("No.", ItemNo);
        if not JobLedgerEntry.FindLast() then
            Error(NotPostedErr);

        if LpNo <> '' then begin
            if (JobLedgerEntry."Ledger Entry Type" = JobLedgerEntry."Ledger Entry Type"::Item) and
               ItemLedgerEntry.Get(JobLedgerEntry."Ledger Entry No.")
            then
                LPMgt.DebitProjectIssueLp(LpNo, LocationCode, BinCode, ItemNo, VariantCode,
                    ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", -ItemLedgerEntry.Quantity,
                    CopyStr('PJ:' + Format(ItemLedgerEntry."Entry No."), 1, 40))
            else
                LPMgt.DebitProjectIssueLp(LpNo, LocationCode, BinCode, ItemNo, VariantCode, LotNo, SerialNo, BaseQty,
                    CopyStr('PJ:J' + Format(JobLedgerEntry."Entry No."), 1, 40));
        end;

        ActualNote := AddActualQuantity(WorkOrderNo, Item, BaseQty);

        exit(StrSubstNo('%1 × %2 %3 → %4 / %5 / %6 (proje defteri %7)%8',
            ItemNo, Format(Qty, 0, 9), UomCode, WorkOrderNo, Orders."Project No.", Orders."Project Task No.", JobLedgerEntry."Entry No.", ActualNote));
    end;

    /// <summary>
    /// Yönlendirilmiş lokasyon: (1) iş emrinin proje görevine bütçe planlama satırı açılır,
    /// (2) yalnız bu satır için okutulan raftan ambar toplaması oluşturulur, (3) satır terminal
    /// operatörü adına okutulan LP/lot ile onaylanıp kaydedilir (stok "Projeye Depo Gözü"ne
    /// geçer), (4) toplanan miktar proje günlüğünden kullanım olarak işlenir. Hepsi tek işlem.
    /// </summary>
    local procedure IssueViaWarehousePick(Orders: Record "DOPSWHS Field WO Buffer" temporary; WorkOrderNo: Code[20]; Item: Record Item; VariantCode: Code[10]; UomCode: Code[10]; Qty: Decimal; BaseQty: Decimal; Location: Record Location; FromBinCode: Code[20]; LpNo: Code[20]; LotNo: Code[50]; WmsUserId: Code[50]; TemplateName: Code[10]; BatchName: Code[10]; LastJobEntryNo: Integer; var PickNo: Code[20]): Integer
    var
        JobPlanningLine: Record "Job Planning Line";
        PickHeader: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        JobJnlLine: Record "Job Journal Line";
        JobLedgerEntry: Record "Job Ledger Entry";
        LP: Record "DOPSWHS LP Header";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
        JobTransferLine: Codeunit "Job Transfer Line";
        JobJnlPostBatch: Codeunit "Job Jnl.-Post Batch";
        LPMgt: Codeunit "DOPSWHS LP Management";
        UsageQty: Decimal;
    begin
        if WmsUserId = '' then
            Error(UserRequiredErr);
        CreatePlanningLine(Orders, WorkOrderNo, Item, VariantCode, UomCode, Qty, Location.Code, JobPlanningLine);
        PickNo := CreateScopedPick(JobPlanningLine, FromBinCode);

        PickHeader.Get(PickHeader.Type::Pick, PickNo);
        PickMgmt.ClaimPick(PickHeader, WmsUserId, 'Projeye çıkış (saha iş emri)');
        TakeLine.SetRange("Activity Type", TakeLine."Activity Type"::Pick);
        TakeLine.SetRange("No.", PickNo);
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        if not TakeLine.FindSet(true) then
            Error(PickNotCreatedErr, Item."No.", FromBinCode);
        repeat
            PickMgmt.ConfirmPickLineFor(TakeLine, TakeLine."Qty. Outstanding", LotNo, LpNo, WmsUserId);
        until TakeLine.Next() = 0;
        PickHeader.Get(PickHeader.Type::Pick, PickNo);
        PickMgmt.RegisterPickFor(PickHeader, WmsUserId);

        // Kayıt BC tarafından otomatik kullanıma dönüştürülmediyse toplanan miktarı işle.
        JobPlanningLine.Get(JobPlanningLine."Job No.", JobPlanningLine."Job Task No.", JobPlanningLine."Line No.");
        UsageQty := JobPlanningLine."Qty. Picked" - JobPlanningLine."Qty. Posted";
        if UsageQty > 0 then begin
            // FromPlanningLineToJnlLine satırı günlüğe kendisi ekler; burada yalnız güncellenir.
            JobTransferLine.FromPlanningLineToJnlLine(JobPlanningLine, WorkDate(), TemplateName, BatchName, JobJnlLine);
            JobJnlLine."Document No." := WorkOrderNo;
            JobJnlLine."External Document No." := CopyStr(WmsUserId, 1, MaxStrLen(JobJnlLine."External Document No."));
            if JobJnlLine."Bin Code" <> Location."To-Job Bin Code" then
                JobJnlLine.Validate("Bin Code", Location."To-Job Bin Code");
            JobJnlLine.Validate(Quantity, UsageQty);
            AddProjectDimension(JobJnlLine, Orders."Project No.");
            JobJnlLine.Modify(true);
            if LotNo <> '' then
                AddTracking(JobJnlLine, LotNo, '');
            JobJnlPostBatch.SetSuppressCommit(true);
            JobJnlPostBatch.Run(JobJnlLine);
        end;

        JobLedgerEntry.SetFilter("Entry No.", '>%1', LastJobEntryNo);
        JobLedgerEntry.SetRange("Job No.", Orders."Project No.");
        JobLedgerEntry.SetRange(Type, JobLedgerEntry.Type::Item);
        JobLedgerEntry.SetRange("No.", Item."No.");
        if not JobLedgerEntry.FindLast() then
            Error(NotPostedErr);

        // Bütün LP toplandıysa palet Projeye Depo Gözü'ne taşınmış olabilir: kullanılan
        // içerik paletten de düşülür ki LP ile raf stoku ayrışmasın.
        if (LpNo <> '') and LP.Get(LpNo) then
            if (LP."Bin Code" = Location."To-Job Bin Code") and (LP.Status in [LP.Status::Open, LP.Status::Built]) then
                LPMgt.DebitProjectIssueLp(LpNo, Location.Code, Location."To-Job Bin Code", Item."No.", VariantCode, LotNo, '', BaseQty,
                    CopyStr('PJ:J' + Format(JobLedgerEntry."Entry No."), 1, 40));
        exit(JobLedgerEntry."Entry No.");
    end;

    local procedure CreatePlanningLine(Orders: Record "DOPSWHS Field WO Buffer" temporary; WorkOrderNo: Code[20]; Item: Record Item; VariantCode: Code[10]; UomCode: Code[10]; Qty: Decimal; LocationCode: Code[10]; var JobPlanningLine: Record "Job Planning Line")
    var
        LastLine: Record "Job Planning Line";
        LineNo: Integer;
    begin
        LastLine.SetRange("Job No.", Orders."Project No.");
        LastLine.SetRange("Job Task No.", Orders."Project Task No.");
        if LastLine.FindLast() then
            LineNo := LastLine."Line No.";
        LineNo += 10000;
        JobPlanningLine.Init();
        JobPlanningLine.Validate("Job No.", Orders."Project No.");
        JobPlanningLine.Validate("Job Task No.", Orders."Project Task No.");
        JobPlanningLine."Line No." := LineNo;
        JobPlanningLine.Validate("Line Type", JobPlanningLine."Line Type"::Budget);
        JobPlanningLine.Validate("Planning Date", WorkDate());
        JobPlanningLine."Document No." := WorkOrderNo;
        JobPlanningLine.Validate(Type, JobPlanningLine.Type::Item);
        JobPlanningLine.Validate("No.", Item."No.");
        if VariantCode <> '' then
            JobPlanningLine.Validate("Variant Code", VariantCode);
        JobPlanningLine.Validate("Location Code", LocationCode);
        JobPlanningLine.Validate("Unit of Measure Code", UomCode);
        JobPlanningLine.Validate(Quantity, Qty);
        JobPlanningLine.Validate("Usage Link", true);
        JobPlanningLine.Description := CopyStr(StrSubstNo('%1 · %2', WorkOrderNo, Item.Description), 1, MaxStrLen(JobPlanningLine.Description));
        JobPlanningLine.Insert(true);
    end;

    /// <summary>Yalnız verilen planlama satırı için, yalnız okutulan raftan ambar toplaması oluşturur.</summary>
    local procedure CreateScopedPick(var JobPlanningLine: Record "Job Planning Line"; FromBinCode: Code[20]): Code[20]
    var
        CreatePickParameters: Record "Create Pick Parameters";
        CreatePick: Codeunit "Create Pick";
        FirstNo: Code[20];
        LastNo: Code[20];
        QtyToPick: Decimal;
        QtyToPickBase: Decimal;
    begin
        CreatePickParameters."Whse. Document" := CreatePickParameters."Whse. Document"::Job;
        CreatePickParameters."Whse. Document Type" := CreatePickParameters."Whse. Document Type"::Pick;
        CreatePickParameters."Sorting Method" := Enum::"Whse. Activity Sorting Method"::None;
        CreatePickParameters."Max No. of Source Doc." := 1;
        CreatePickParameters."Do Not Fill Qty. to Handle" := true;
        CreatePick.SetParameters(CreatePickParameters);
        CreatePick.SetJobPlanningLine(JobPlanningLine);
        CreatePick.SetTempWhseItemTrkgLine(JobPlanningLine."Job No.", Database::Job, '', 0,
            JobPlanningLine."Job Contract Entry No.", JobPlanningLine."Location Code");
        QtyToPick := JobPlanningLine."Remaining Qty.";
        QtyToPickBase := JobPlanningLine."Remaining Qty. (Base)";
        CreatePick.CreateTempLine(JobPlanningLine."Location Code", JobPlanningLine."No.", JobPlanningLine."Variant Code",
            JobPlanningLine."Unit of Measure Code", FromBinCode, JobPlanningLine."Bin Code", JobPlanningLine."Qty. per Unit of Measure",
            JobPlanningLine."Qty. Rounding Precision", JobPlanningLine."Qty. Rounding Precision (Base)", QtyToPick, QtyToPickBase);
        if QtyToPickBase > 0 then
            Error(PickShortErr, JobPlanningLine."No.", FromBinCode, QtyToPickBase);
        CreatePick.CreateWhseDocument(FirstNo, LastNo, true);
        if FirstNo = '' then
            Error(PickNotCreatedErr, JobPlanningLine."No.", FromBinCode);
        exit(FirstNo);
    end;

    procedure GetWorkOrder(WorkOrderNo: Code[20]; var Buffer: Record "DOPSWHS Field WO Buffer" temporary)
    var
        WorkOrder: RecordRef;
        StatusRef: FieldRef;
    begin
        if not IsAvailable() then
            Error(NotInstalledErr);
        WorkOrder.Open(WorkOrderTableNo);
        WorkOrder.Field(1).SetRange(WorkOrderNo);
        if not WorkOrder.FindFirst() then
            Error(WorkOrderNotFoundErr, WorkOrderNo);
        StatusRef := WorkOrder.Field(10);
        if IsClosedStatus(StatusRef) then
            Error(WorkOrderClosedErr, WorkOrderNo, StatusCaption(StatusRef));
        Buffer.Reset();
        Buffer.DeleteAll();
        InsertWorkOrderBuffer(WorkOrder, Buffer);
        WorkOrder.Close();
        Buffer.Get(WorkOrderNo);
    end;

    local procedure InsertWorkOrderBuffer(var WorkOrder: RecordRef; var Buffer: Record "DOPSWHS Field WO Buffer" temporary)
    var
        Job: Record Job;
        Lines: Record "DOPSWHS Field WO Line Buffer" temporary;
    begin
        Buffer.Init();
        Buffer."No." := CopyStr(Format(WorkOrder.Field(1).Value), 1, MaxStrLen(Buffer."No."));
        Buffer."Project No." := CopyStr(Format(WorkOrder.Field(2).Value), 1, MaxStrLen(Buffer."Project No."));
        Buffer."Project Task No." := CopyStr(Format(WorkOrder.Field(3).Value), 1, MaxStrLen(Buffer."Project Task No."));
        Buffer.Description := CopyStr(Format(WorkOrder.Field(4).Value), 1, MaxStrLen(Buffer.Description));
        Buffer.Team := CopyStr(Format(WorkOrder.Field(5).Value), 1, MaxStrLen(Buffer.Team));
        Buffer."Planned Start" := DateOf(WorkOrder.Field(6));
        Buffer."Planned Finish" := DateOf(WorkOrder.Field(7));
        Buffer.Status := CopyStr(StatusCaption(WorkOrder.Field(10)), 1, MaxStrLen(Buffer.Status));
        if (Buffer."Project No." <> '') and Job.Get(Buffer."Project No.") then
            Buffer."Project Description" := CopyStr(Job.Description, 1, MaxStrLen(Buffer."Project Description"));
        AppendLines(Buffer."No.", Lines);
        Lines.SetRange("Is Item", true);
        Buffer."Item Line Count" := Lines.Count();
        if Buffer."No." <> '' then
            Buffer.Insert();
    end;

    local procedure AppendLines(WorkOrderNo: Code[20]; var LineBuffer: Record "DOPSWHS Field WO Line Buffer" temporary)
    var
        WorkLine: RecordRef;
        TypeRef: FieldRef;
    begin
        WorkLine.Open(WorkLineTableNo);
        WorkLine.Field(1).SetRange(WorkOrderNo);
        if WorkLine.FindSet() then
            repeat
                TypeRef := WorkLine.Field(3);
                LineBuffer.Init();
                LineBuffer."Work Order No." := WorkOrderNo;
                LineBuffer."Line No." := IntegerOf(WorkLine.Field(2));
                LineBuffer.Type := CopyStr(StatusCaption(TypeRef), 1, MaxStrLen(LineBuffer.Type));
                LineBuffer."Is Item" := IsItemType(TypeRef);
                LineBuffer."No." := CopyStr(Format(WorkLine.Field(4).Value), 1, MaxStrLen(LineBuffer."No."));
                LineBuffer.Description := CopyStr(Format(WorkLine.Field(5).Value), 1, MaxStrLen(LineBuffer.Description));
                LineBuffer.Quantity := DecimalOf(WorkLine.Field(6));
                LineBuffer."Actual Quantity" := DecimalOf(WorkLine.Field(7));
                LineBuffer."Unit of Measure Code" := CopyStr(Format(WorkLine.Field(8).Value), 1, MaxStrLen(LineBuffer."Unit of Measure Code"));
                if not LineBuffer.Insert() then
                    LineBuffer.Modify();
            until WorkLine.Next() = 0;
        WorkLine.Close();
    end;

    /// <summary>
    /// İş emrindeki madde satırının gerçekleşen miktarını, satırın ölçü biriminde artırır. Önce
    /// kalan miktarı olan ilk satır, yoksa ilk satır güncellenir; satır yoksa ekleme yapılmaz.
    /// Dönüş: terminale eklenecek not (güncellenemediyse nedeni), güncellendiyse boş.
    /// </summary>
    local procedure AddActualQuantity(WorkOrderNo: Code[20]; Item: Record Item; BaseQty: Decimal): Text
    var
        WorkLine: RecordRef;
        ActualRef: FieldRef;
        TargetPosition: Text;
        FirstPosition: Text;
        OpenPosition: Text;
        LineUom: Code[10];
        Planned: Decimal;
        Actual: Decimal;
    begin
        WorkLine.Open(WorkLineTableNo);
        WorkLine.LockTable();
        WorkLine.Field(1).SetRange(WorkOrderNo);
        WorkLine.Field(4).SetRange(Item."No.");
        if WorkLine.FindSet() then
            repeat
                if IsItemType(WorkLine.Field(3)) then begin
                    if FirstPosition = '' then
                        FirstPosition := WorkLine.GetPosition();
                    Planned := DecimalOf(WorkLine.Field(6));
                    Actual := DecimalOf(WorkLine.Field(7));
                    if (OpenPosition = '') and (Actual < Planned) then
                        OpenPosition := WorkLine.GetPosition();
                end;
            until WorkLine.Next() = 0;
        TargetPosition := OpenPosition;
        if TargetPosition = '' then
            TargetPosition := FirstPosition;
        if TargetPosition = '' then begin
            WorkLine.Close();
            Error('İş emrinde bu madde satırı yok; önce iş emrine malzeme satırı ekleyin.');
        end;
        if not WorkLine.WritePermission() then begin
            WorkLine.Close();
            Error('İş emri satırının gerçekleşen miktarını güncelleme yetkiniz yok.');
        end;
        WorkLine.SetPosition(TargetPosition);
        WorkLine.Find('=');
        LineUom := CopyStr(Format(WorkLine.Field(8).Value), 1, MaxStrLen(LineUom));
        ActualRef := WorkLine.Field(7);
        ActualRef.Value := Round(DecimalOf(ActualRef) + BaseQty / QtyPerUom(Item, LineUom), 0.00001);
        WorkLine.Modify(true);
        WorkLine.Close();
        exit('');
    end;

    /// <summary>
    /// LP okutulmadan yapılan çıkışta yalnız LP'ye atanmamış serbest stok kullanılabilir.
    /// Raf varsa raf (ambar girişleri), yoksa lokasyon (açık madde girişleri) stoku; aktif
    /// LP'lerdeki (Açık/Oluşturuldu/Atanmış, mal kabul beklemeyen) miktar düşülür. Varyant,
    /// lot ve seri dikkate alınır.
    /// </summary>
    local procedure EnsureLooseStock(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]; RequiredBaseQty: Decimal)
    var
        WarehouseEntry: Record "Warehouse Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Verification: Codeunit "DOPSWHS LP Verification";
        StockBase: Decimal;
        AllocatedBase: Decimal;
    begin
        if BinCode <> '' then begin
            WarehouseEntry.SetRange("Location Code", LocationCode);
            WarehouseEntry.SetRange("Bin Code", BinCode);
            WarehouseEntry.SetRange("Item No.", ItemNo);
            WarehouseEntry.SetRange("Variant Code", VariantCode);
            if LotNo <> '' then
                WarehouseEntry.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                WarehouseEntry.SetRange("Serial No.", SerialNo);
            WarehouseEntry.CalcSums("Qty. (Base)");
            StockBase := WarehouseEntry."Qty. (Base)";
        end else begin
            ItemLedgerEntry.SetRange("Item No.", ItemNo);
            ItemLedgerEntry.SetRange("Variant Code", VariantCode);
            ItemLedgerEntry.SetRange("Location Code", LocationCode);
            ItemLedgerEntry.SetRange(Open, true);
            if LotNo <> '' then
                ItemLedgerEntry.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                ItemLedgerEntry.SetRange("Serial No.", SerialNo);
            ItemLedgerEntry.CalcSums("Remaining Quantity");
            StockBase := ItemLedgerEntry."Remaining Quantity";
        end;

        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetFilter(Quantity, '>0');
        if LotNo <> '' then
            LPLine.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            LPLine.SetRange("Serial No.", SerialNo);
        if LPLine.FindSet() then
            repeat
                if LPHeader."No." <> LPLine."LP No." then
                    if not LPHeader.Get(LPLine."LP No.") then
                        Clear(LPHeader);
                if (LPHeader."No." <> '') and (LPHeader."Location Code" = LocationCode) and
                   ((BinCode = '') or (LPHeader."Bin Code" = BinCode)) and
                   (LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned]) and
                   (LPHeader."Pending Receipt No." = '')
                then
                    AllocatedBase += Verification.LineBaseQuantity(LPLine);
            until LPLine.Next() = 0;

        if StockBase - AllocatedBase + Verification.QtyTolerance() < RequiredBaseQty then
            Error(LooseStockErr, ItemNo, LocationCode, BinCode, StockBase, AllocatedBase, RequiredBaseQty);
    end;

    local procedure AddProjectDimension(var JobJnlLine: Record "Job Journal Line"; JobNo: Code[20])
    var
        Setup: Record "DOPSWHS Setup";
        DimensionValue: Record "Dimension Value";
        TempDimSetEntry: Record "Dimension Set Entry" temporary;
        DimMgt: Codeunit DimensionManagement;
        DimCode: Code[20];
    begin
        DimCode := 'PROJE';
        if Setup.Get('') and (Setup."Project Dimension Code" <> '') then
            DimCode := Setup."Project Dimension Code";
        if not DimensionValue.Get(DimCode, JobNo) then
            exit;
        DimMgt.GetDimensionSet(TempDimSetEntry, JobJnlLine."Dimension Set ID");
        // Madde/lokasyon varsayılanından başka bir PROJE değeri gelmiş olabilir: kayıt hangi
        // projeye yazılıyorsa boyut da o projeyi göstermeli.
        if TempDimSetEntry.Get(JobJnlLine."Dimension Set ID", DimCode) then begin
            if TempDimSetEntry."Dimension Value Code" = JobNo then
                exit;
            TempDimSetEntry.Delete();
        end;
        TempDimSetEntry.Reset();
        TempDimSetEntry.Init();
        TempDimSetEntry."Dimension Set ID" := JobJnlLine."Dimension Set ID";
        TempDimSetEntry.Validate("Dimension Code", DimCode);
        TempDimSetEntry.Validate("Dimension Value Code", JobNo);
        TempDimSetEntry.Insert();
        JobJnlLine."Dimension Set ID" := DimMgt.GetDimensionSetID(TempDimSetEntry);
        DimMgt.UpdateGlobalDimFromDimSetID(JobJnlLine."Dimension Set ID",
            JobJnlLine."Shortcut Dimension 1 Code", JobJnlLine."Shortcut Dimension 2 Code");
    end;

    local procedure AddTracking(JobJnlLine: Record "Job Journal Line"; LotNo: Code[50]; SerialNo: Code[50])
    var
        TempReservEntry: Record "Reservation Entry" temporary;
        CreateReservEntry: Codeunit "Create Reserv. Entry";
    begin
        TempReservEntry."Lot No." := LotNo;
        TempReservEntry."Serial No." := SerialNo;
        CreateReservEntry.CreateReservEntryFor(
            Database::"Job Journal Line", JobJnlLine."Entry Type".AsInteger(),
            JobJnlLine."Journal Template Name", JobJnlLine."Journal Batch Name", 0,
            JobJnlLine."Line No.", JobJnlLine."Qty. per Unit of Measure",
            JobJnlLine.Quantity, JobJnlLine."Quantity (Base)", TempReservEntry);
        CreateReservEntry.CreateEntry(
            JobJnlLine."No.", JobJnlLine."Variant Code", JobJnlLine."Location Code",
            JobJnlLine.Description, 0D, 0D, 0, Enum::"Reservation Status"::Prospect);
    end;

    local procedure EnsureJournalBatch(WmsUserId: Code[50]; var TemplateName: Code[10]; var BatchName: Code[10])
    var
        JobJnlTemplate: Record "Job Journal Template";
        JobJnlBatch: Record "Job Journal Batch";
        SourceCodeSetup: Record "Source Code Setup";
    begin
        TemplateName := TemplateNameTok;
        if not JobJnlTemplate.Get(TemplateName) then begin
            JobJnlTemplate.Init();
            JobJnlTemplate.Name := TemplateName;
            JobJnlTemplate.Description := 'WMS terminal proje çıkışı';
            if SourceCodeSetup.Get() then
                JobJnlTemplate."Source Code" := SourceCodeSetup."Job Journal";
            JobJnlTemplate.Insert(true);
        end;
        // Kullanıcı başına batch: iki terminal aynı anda kaydederken birbirinin satırını
        // temizlemesin. Kullanıcı boşsa ortak 'TERMINAL' batch'i kullanılır.
        BatchName := CopyStr(DelChr(UpperCase(WmsUserId), '=', ' '), 1, MaxStrLen(BatchName));
        if BatchName = '' then
            BatchName := 'TERMINAL';
        if not JobJnlBatch.Get(TemplateName, BatchName) then begin
            JobJnlBatch.Init();
            JobJnlBatch."Journal Template Name" := TemplateName;
            JobJnlBatch.Name := BatchName;
            JobJnlBatch.Description := CopyStr(StrSubstNo('Terminal %1', WmsUserId), 1, MaxStrLen(JobJnlBatch.Description));
            JobJnlBatch.Insert(true);
        end;
    end;

    /// <summary>Önceki başarısız denemenin artıkları her yeni kaydı düşürmesin: batch kayıt öncesi boş olmalı.</summary>
    local procedure PurgeBatch(TemplateName: Code[10]; BatchName: Code[10])
    var
        JobJnlLine: Record "Job Journal Line";
        ReservEntry: Record "Reservation Entry";
    begin
        ReservEntry.SetRange("Source Type", Database::"Job Journal Line");
        ReservEntry.SetRange("Source ID", TemplateName);
        ReservEntry.SetRange("Source Batch Name", BatchName);
        ReservEntry.DeleteAll();
        JobJnlLine.SetRange("Journal Template Name", TemplateName);
        JobJnlLine.SetRange("Journal Batch Name", BatchName);
        JobJnlLine.DeleteAll();
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

    local procedure QtyPerUom(Item: Record Item; UomCode: Code[10]): Decimal
    var
        ItemUom: Record "Item Unit of Measure";
    begin
        if (UomCode = '') or (UomCode = Item."Base Unit of Measure") then
            exit(1);
        if not ItemUom.Get(Item."No.", UomCode) then
            exit(1);
        if ItemUom."Qty. per Unit of Measure" <= 0 then
            exit(1);
        exit(ItemUom."Qty. per Unit of Measure");
    end;

    /// <summary>Durum adı (dil bağımsız) tamamlanmış/iptal/kapalı ise true.</summary>
    /// <summary>
    /// Durum adı (dil bağımsız) tamamlanmış/iptal/kapalı ise true. LowerCase/UpperCase
    /// kullanılmaz: Türkçe oturumda "I" → "ı" dönüşür ve "Item" ile eşleşme bozulur.
    /// </summary>
    procedure IsClosedStatus(StatusRef: FieldRef): Boolean
    var
        Name: Text;
    begin
        Name := EnumName(StatusRef);
        exit(Name in ['Completed', 'Complete', 'Cancelled', 'Canceled', 'Closed', 'Finished', 'Done']);
    end;

    local procedure IsItemType(TypeRef: FieldRef): Boolean
    begin
        exit(EnumName(TypeRef) = 'Item');
    end;

    local procedure EnumName(Ref: FieldRef): Text
    var
        Value: Text;
        Ordinal: Integer;
    begin
        // Dil bağımsız değer adı (ör. Item, Completed). XML biçimi enum'da sıra numarası
        // döndürebilir; sayıysa adı FieldRef'ten çözülür. Format(Ref.Value) kullanıcı dilinde
        // başlık ("Madde") verdiği için karşılaştırmada kullanılmaz.
        Value := Format(Ref.Value, 0, 9);
        if Evaluate(Ordinal, Value) then
            exit(Ref.GetEnumValueNameFromOrdinalValue(Ordinal));
        exit(Value);
    end;

    local procedure StatusCaption(Ref: FieldRef): Text
    begin
        exit(Format(Ref.Value));
    end;

    local procedure DateOf(Ref: FieldRef): Date
    var
        Value: Date;
    begin
        if Ref.Type <> FieldType::Date then
            exit(0D);
        Value := Ref.Value;
        exit(Value);
    end;

    local procedure DecimalOf(Ref: FieldRef): Decimal
    var
        Value: Decimal;
    begin
        if not (Ref.Type in [FieldType::Decimal, FieldType::Integer]) then
            exit(0);
        Value := Ref.Value;
        exit(Value);
    end;

    local procedure IntegerOf(Ref: FieldRef): Integer
    var
        Value: Integer;
    begin
        if Ref.Type <> FieldType::Integer then
            exit(0);
        Value := Ref.Value;
        exit(Value);
    end;

    local procedure InitIds()
    begin
        WorkOrderTableNo := 75641;
        WorkLineTableNo := 75643;
    end;
}
