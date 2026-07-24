codeunit 72334 "DOPSWHS Pack Station Mgmt"
{
    // ELOG saha ziyareti (07.07.2026) — paketleme istasyonu motoru.
    // Akış: tote (LP) okut → tote'a bağlı siparişlerin beklenen satırları
    // oluşur → kutu okut → ürünleri tek tek okut → bir siparişin payı
    // tamamlanınca sipariş sevk+fatura edilir ve fişi basılır.
    //
    // Tek motor üç modu da karşılar:
    //  - Multi:    sipariş başına ayrı tote, siparişin tüm farklı ürünleri bitince fiş.
    //  - Bulk:     aynı ürün aynı tote'ta birden çok siparişe bölünmüş (2+2+2);
    //              her siparişin payı dolunca o siparişin fişi basılır.
    //  - Batch:    tek ürünlük siparişler; her okutma bir siparişi kapatır.
    // Beklenmeyen (yanlış) ürün okutulursa hata verilir ve işlem geri alınır.
    Access = Public;

    procedure StartOrderSession(OrderNo: Code[20]): Integer
    begin
        exit(StartOrderSession(OrderNo, ''));
    end;

    // ELOG: OperatorUserId dolu ise paketlemeyi üstlenen WMS operatörü olarak
    // kaydedilir (Started By User / Created By User). Boşsa UserId() (eski davranış).
    procedure StartOrderSession(OrderNo: Code[20]; OperatorUserId: Code[50]): Integer
    var
        PackingOrder: Record "DOPSWHS Packing Order";
        ExistingSession: Record "DOPSWHS Pack Session";
        PackSession: Record "DOPSWHS Pack Session";
        LineNo: Integer;
        Operator: Code[50];
    begin
        if OperatorUserId <> '' then
            Operator := OperatorUserId
        else
            Operator := CopyStr(UserId(), 1, MaxStrLen(Operator));

        PackingOrder.Get(OrderNo);
        if (PackingOrder.Status = PackingOrder.Status::"In Progress") and
           ExistingSession.Get(PackingOrder."Session Entry No.") and
           (ExistingSession.Status = ExistingSession.Status::Open)
        then
            exit(ExistingSession."Entry No.");
        PackingOrder.TestField(Status, PackingOrder.Status::Ready);

        PackSession.Init();
        PackSession."Pick No." := PackingOrder."Pick No.";
        PackSession."Location Code" := PackingOrder."Location Code";
        PackSession.Status := PackSession.Status::Open;
        PackSession.Mode := PackSession.Mode::Solo;
        PackSession."Direct Order Packing" := true;
        PackSession."Created By User" := CopyStr(Operator, 1, MaxStrLen(PackSession."Created By User"));
        PackSession."Created DateTime" := CurrentDateTime();
        PackSession."Orders Total" := 1;
        PackSession.Insert(true);

        BuildExpectedLines(PackSession, OrderNo, LineNo);

        PackingOrder.Status := PackingOrder.Status::"In Progress";
        PackingOrder."Session Entry No." := PackSession."Entry No.";
        PackingOrder."Started By User" := CopyStr(Operator, 1, MaxStrLen(PackingOrder."Started By User"));
        PackingOrder."Started DateTime" := CurrentDateTime();
        PackingOrder.Modify(true);
        Log('Pack.StartOrder', OrderNo);
        exit(PackSession."Entry No.");
    end;

    // ELOG "ürün-önce" paketleme: operatör bir PICK seçer, pick'in TÜM
    // siparişlerinin beklenen satırları tek session'da toplanır. Sepetten eline
    // gelen ürünü okuttukça ScanItem doğru siparişe yazar (Source Order No.
    // eşleşmesi). Bir siparişin payı bitince o sipariş için kutu istenir
    // (BoxNeededOrder batch akışı). Idempotent: pick'in In Progress bir siparişi
    // ve açık session'ı varsa onu döndürür.
    procedure StartPickSession(PickNo: Code[20]): Integer
    begin
        exit(StartPickSession(PickNo, ''));
    end;

    procedure StartPickSession(PickNo: Code[20]; OperatorUserId: Code[50]): Integer
    var
        PackingOrder: Record "DOPSWHS Packing Order";
        ExistingSession: Record "DOPSWHS Pack Session";
        PackSession: Record "DOPSWHS Pack Session";
        LineNo: Integer;
        Orders: Integer;
        Operator: Code[50];
    begin
        if OperatorUserId <> '' then
            Operator := OperatorUserId
        else
            Operator := CopyStr(UserId(), 1, MaxStrLen(Operator));

        // Bu pick için hâlihazırda açık bir session varsa onu yeniden kullan.
        PackingOrder.SetRange("Pick No.", PickNo);
        PackingOrder.SetRange(Status, PackingOrder.Status::"In Progress");
        if PackingOrder.FindFirst() and
           ExistingSession.Get(PackingOrder."Session Entry No.") and
           (ExistingSession.Status = ExistingSession.Status::Open)
        then
            exit(ExistingSession."Entry No.");

        PackSession.Init();
        PackSession."Pick No." := PickNo;
        PackSession.Status := PackSession.Status::Open;
        // Batch modu: kutu SİPARİŞ payı tamamlanınca istenir (ürün → kutu).
        PackSession.Mode := PackSession.Mode::Batch;
        PackSession."Direct Order Packing" := true;
        PackSession."Created By User" := CopyStr(Operator, 1, MaxStrLen(PackSession."Created By User"));
        PackSession."Created DateTime" := CurrentDateTime();
        PackSession.Insert(true);

        // Pick'in paketlemeye hazır TÜM siparişlerinin beklenen satırlarını tek
        // session'a inşa et (StartSession'ın 90-99 tote deseninin pick varyantı).
        LineNo := 0;
        Orders := 0;
        PackingOrder.Reset();
        PackingOrder.SetRange("Pick No.", PickNo);
        PackingOrder.SetFilter(Status, '%1|%2', PackingOrder.Status::Ready, PackingOrder.Status::"In Progress");
        if not PackingOrder.FindSet() then
            Error(NoOrdersForPickErr, PickNo);
        repeat
            if PackSession."Location Code" = '' then
                PackSession."Location Code" := PackingOrder."Location Code";
            BuildExpectedLines(PackSession, PackingOrder."Sales Order No.", LineNo);
            PackingOrder.Status := PackingOrder.Status::"In Progress";
            PackingOrder."Session Entry No." := PackSession."Entry No.";
            PackingOrder."Started By User" := CopyStr(Operator, 1, MaxStrLen(PackingOrder."Started By User"));
            PackingOrder."Started DateTime" := CurrentDateTime();
            PackingOrder.Modify(true);
            Orders += 1;
        until PackingOrder.Next() = 0;

        PackSession."Orders Total" := Orders;
        PackSession.Modify(true);
        Log('Pack.StartPickSession', PickNo);
        exit(PackSession."Entry No.");
    end;

    procedure StartSession(ToteLpNo: Code[20]; ModeTxt: Text): Integer
    var
        LP: Record "DOPSWHS LP Header";
        Assignment: Record "DOPSWHS Pick Tote Assignment";
        PackSession: Record "DOPSWHS Pack Session";
        LineNo: Integer;
        Orders: Integer;
    begin
        LP.Get(ToteLpNo);

        Assignment.SetRange("LP No.", ToteLpNo);
        Assignment.SetRange(Packed, false);
        if not Assignment.FindSet() then
            Error(NoOrdersForToteErr, ToteLpNo);

        PackSession.Init();
        PackSession."Tote LP No." := ToteLpNo;
        PackSession."Location Code" := LP."Location Code";
        PackSession.Status := PackSession.Status::Open;
        PackSession.Mode := MapMode(ModeTxt);
        PackSession."Created By User" := CopyStr(UserId(), 1, MaxStrLen(PackSession."Created By User"));
        PackSession."Created DateTime" := CurrentDateTime();
        PackSession.Insert(true);

        LineNo := 0;
        repeat
            if PackSession."Pick No." = '' then
                PackSession."Pick No." := Assignment."Pick No.";
            BuildExpectedLines(PackSession, Assignment."Source Order No.", LineNo);
            Orders += 1;
        until Assignment.Next() = 0;

        PackSession."Orders Total" := Orders;
        PackSession.Modify(true);
        Log('Pack.StartSession', PackSession."Tote LP No.");
        exit(PackSession."Entry No.");
    end;

    // Kutu SİPARİŞ başınadır: solo'da sepetteki tek siparişe, bulk'ta sıradaki
    // paya, batch'te ürünleri okutulup kutu bekleyen siparişe bağlanır. Sipariş
    // hem tam paketlenmiş hem kutulanmışsa bu çağrı siparişi kapatır (batch:
    // "ürün okuttum, kutumu okuttum, fatura kesti").
    procedure SetBoxForOrder(SessionId: Integer; OrderNo: Code[20]; BoxLpNo: Code[20]; LpTemplateCode: Code[20]): Code[20]
    var
        PackSession: Record "DOPSWHS Pack Session";
        Line: Record "DOPSWHS Pack Session Line";
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PackSession.Get(SessionId);
        PackSession.TestField(Status, PackSession.Status::Open);
        if OrderNo = '' then
            OrderNo := BoxNeededOrder(SessionId);
        if OrderNo = '' then
            OrderNo := CurrentOrder(SessionId);
        if OrderNo = '' then
            Error(NoOpenOrderErr);

        if BoxLpNo <> '' then
            LP.Get(BoxLpNo)
        else begin
            // Kutu barkodu yoksa geçici (karton) LP üret — ELOG'daki karton kutular.
            if LpTemplateCode = '' then
                LpTemplateCode := 'CARTON-S';
            LPMgt.Build(LpTemplateCode, PackSession."Location Code", '', LP);
        end;

        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Source Order No.", OrderNo);
        Line.ModifyAll("Box LP No.", LP."No.");

        PackSession."Box LP No." := LP."No.";
        PackSession.Modify(true);
        Log('Pack.SetBox', LP."No.");

        TryCompleteOrder(PackSession, OrderNo);
        exit(LP."No.");
    end;

    /// <summary>Geriye dönük sarmalayıcı: kutuyu sıradaki siparişe bağlar.</summary>
    procedure SetBox(SessionId: Integer; BoxLpNo: Code[20]; LpTemplateCode: Code[20]): Code[20]
    begin
        exit(SetBoxForOrder(SessionId, '', BoxLpNo, LpTemplateCode));
    end;

    /// <summary>Sıradaki (kapanmamış ilk) sipariş.</summary>
    procedure CurrentOrder(SessionId: Integer): Code[20]
    var
        Line: Record "DOPSWHS Pack Session Line";
    begin
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Order Completed", false);
        if Line.FindFirst() then
            exit(Line."Source Order No.");
        exit('');
    end;

    /// <summary>Şu an kutu okutulması gereken sipariş (yoksa boş):
    /// 1) tam paketlenmiş ama kutusuz sipariş (batch akışı: ürün → kutu),
    /// 2) Solo/Bulk'ta sıradaki siparişin kutusu yoksa o (kutu → ürünler).</summary>
    procedure BoxNeededOrder(SessionId: Integer): Code[20]
    var
        PackSession: Record "DOPSWHS Pack Session";
        Line: Record "DOPSWHS Pack Session Line";
        Seen: Dictionary of [Code[20], Boolean];
        OrderNo: Code[20];
    begin
        PackSession.Get(SessionId);
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Order Completed", false);
        if Line.FindSet() then
            repeat
                if not Seen.ContainsKey(Line."Source Order No.") then begin
                    Seen.Add(Line."Source Order No.", true);
                    if OrderIsComplete(SessionId, Line."Source Order No.") and
                       (not OrderHasBox(SessionId, Line."Source Order No."))
                    then
                        exit(Line."Source Order No.");
                end;
            until Line.Next() = 0;

        if PackSession.Mode <> PackSession.Mode::Batch then begin
            OrderNo := CurrentOrder(SessionId);
            if (OrderNo <> '') and (not OrderHasBox(SessionId, OrderNo)) then
                exit(OrderNo);
        end;
        exit('');
    end;

    // Ürün okutma. Okutulan miktar sipariş sırasına göre açık satırlara dolar;
    // tamamlanan siparişler sevk+fatura edilir, fişleri basılır. Dönüş: bu
    // okutmayla tamamlanan sipariş no'ları (virgülle). Beklenmeyen ürün → hata.
    procedure ScanItem(SessionId: Integer; ItemNo: Code[20]; Qty: Decimal): Text
    var
        PackSession: Record "DOPSWHS Pack Session";
        Line: Record "DOPSWHS Pack Session Line";
        CompletedOrders: Text;
        Remaining: Decimal;
        Take: Decimal;
    begin
        PackSession.Get(SessionId);
        PackSession.TestField(Status, PackSession.Status::Open);
        if Qty <= 0 then
            Qty := 1;

        // Kutu zorunluluğu sipariş kapanışında denetlenir (TryCompleteOrder):
        // batch akışında ürünler kutudan ÖNCE okutulur.
        Line.SetRange("Session Entry No.", SessionId);
        if Line.FindSet(true) then
            repeat
                if (Qty > 0) and MatchesItem(Line, ItemNo) and (Line."Qty. Packed" < Line."Qty. Expected") then begin
                    Remaining := Line."Qty. Expected" - Line."Qty. Packed";
                    Take := Qty;
                    if Take > Remaining then
                        Take := Remaining;
                    Line."Qty. Packed" += Take;
                    Line.Modify(true);
                    Qty -= Take;
                    if TryCompleteOrder(PackSession, Line."Source Order No.") then begin
                        if CompletedOrders <> '' then
                            CompletedOrders += ',';
                        CompletedOrders += Line."Source Order No.";
                    end;
                end;
            until (Line.Next() = 0) or (Qty <= 0);

        // Hiç eşleşmedi ya da beklenenden fazla okutuldu → tüm okuma geri alınır
        // (Error web servis işlemini rollback eder) — ELOG: "farklı ürün
        // okutulunca hata veriyor".
        if Qty > 0 then
            Error(UnexpectedItemErr, ItemNo, PackSession."Tote LP No.");

        Log('Pack.ScanItem', PackSession."Tote LP No.");
        exit(CompletedOrders);
    end;

    procedure CancelSession(SessionId: Integer)
    var
        PackSession: Record "DOPSWHS Pack Session";
        PackingOrder: Record "DOPSWHS Packing Order";
        PackLine: Record "DOPSWHS Pack Session Line";
        Seen: Dictionary of [Code[20], Boolean];
    begin
        PackSession.Get(SessionId);
        PackSession.TestField(Status, PackSession.Status::Open);
        PackSession.Status := PackSession.Status::Cancelled;
        PackSession.Modify(true);
        if PackSession."Direct Order Packing" then begin
            // Session'daki HER ayrı siparişi (pick session'ında birden çok olur)
            // henüz kapanmamışsa Ready'ye geri al. Kapanmış (fatura edilmiş)
            // siparişlere dokunma.
            PackLine.SetRange("Session Entry No.", SessionId);
            if PackLine.FindSet() then
                repeat
                    if (not Seen.ContainsKey(PackLine."Source Order No.")) then begin
                        Seen.Add(PackLine."Source Order No.", true);
                        if PackingOrder.Get(PackLine."Source Order No.") and
                           (PackingOrder.Status = PackingOrder.Status::"In Progress")
                        then begin
                            PackingOrder.Status := PackingOrder.Status::Ready;
                            PackingOrder."Session Entry No." := 0;
                            Clear(PackingOrder."Started By User");
                            Clear(PackingOrder."Started DateTime");
                            PackingOrder.Modify(true);
                        end;
                    end;
                until PackLine.Next() = 0;
        end;
        Log('Pack.CancelSession', PackSession."Tote LP No.");
    end;

    // ELOG'daki gibi Solo/Bulk/Batch için AYRI BC sayfaları (Pack Station
    // Solo/Bulk/Mono-SKU) var; her biri tek "Scan Here" alanına sahip ince
    // bir kabuk ve tüm orkestrasyonu buraya delege eder — iş kuralı tek
    // yerde durur, üç sayfada üç kez bakım gerekmez.
    /// <summary>Sabit modlu sayfaların tek okuma alanı motoru: oturum yoksa
    /// açar, açıksa kutu mu ürün mü beklendiğine karar verip ilgili adımı
    /// çalıştırır. Dönüş: bu okumayla tamamlanan sipariş no'su (yoksa boş).</summary>
    procedure ProcessScan(var SessionId: Integer; FixedMode: Enum "DOPSWHS Pack Mode"; ScanValue: Text): Text
    var
        PackSession: Record "DOPSWHS Pack Session";
        BoxOrder: Code[20];
        Trimmed: Code[20];
    begin
        Trimmed := CopyStr(ScanValue.Trim(), 1, MaxStrLen(Trimmed));
        if Trimmed = '' then
            exit('');

        if (SessionId = 0) or (not PackSession.Get(SessionId)) or (PackSession.Status <> PackSession.Status::Open) then begin
            SessionId := StartSession(Trimmed, Format(FixedMode));
            exit('');
        end;

        BoxOrder := BoxNeededOrder(SessionId);
        if BoxOrder <> '' then begin
            SetBoxForOrder(SessionId, BoxOrder, Trimmed, '');
            if IsOrderCompleted(SessionId, BoxOrder) then
                exit(BoxOrder);
            exit('');
        end;

        exit(ScanItem(SessionId, Trimmed, 1));
    end;

    /// <summary>Sipariş bu oturumda faturalanıp kapatılmış mı (ekranda 🧾 göstermek için).</summary>
    procedure IsOrderCompleted(SessionId: Integer; OrderNo: Code[20]): Boolean
    var
        Line: Record "DOPSWHS Pack Session Line";
    begin
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Source Order No.", OrderNo);
        Line.SetRange("Order Completed", true);
        exit(not Line.IsEmpty());
    end;

    /// <summary>Sabit modlu sayfaların Details/Next Step alanlarını doldurur —
    /// PackStation.Page.al'deki CalcUnpacked'ın paylaşılan karşılığı.</summary>
    procedure GetSessionDisplay(SessionId: Integer; var UnpackedQty: Decimal; var UnpackedLines: Integer; var CurrentOrderNo: Code[20]; var NextStep: Text)
    var
        PackSession: Record "DOPSWHS Pack Session";
        Line: Record "DOPSWHS Pack Session Line";
        BoxOrder: Code[20];
    begin
        UnpackedQty := 0;
        UnpackedLines := 0;
        CurrentOrderNo := '';
        NextStep := ScanToteTxt;
        if (SessionId = 0) or (not PackSession.Get(SessionId)) then
            exit;

        Line.SetRange("Session Entry No.", SessionId);
        if Line.FindSet() then
            repeat
                if Line."Qty. Packed" < Line."Qty. Expected" then begin
                    UnpackedLines += 1;
                    UnpackedQty += Line."Qty. Expected" - Line."Qty. Packed";
                end;
            until Line.Next() = 0;

        if PackSession.Status <> PackSession.Status::Open then
            exit;

        CurrentOrderNo := CurrentOrder(SessionId);
        BoxOrder := BoxNeededOrder(SessionId);
        if BoxOrder <> '' then
            NextStep := StrSubstNo(ScanBoxTxt, BoxOrder)
        else
            NextStep := ScanItemTxt;
    end;

    local procedure BuildExpectedLines(var PackSession: Record "DOPSWHS Pack Session"; OrderNo: Code[20]; var LineNo: Integer)
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        SalesLine: Record "Sales Line";
        Expected: Decimal;
        Inserted: Boolean;
    begin
        // Birincil kaynak: siparişin ambar sevkiyat satırları (pick sonrası
        // "Qty. Picked" tote'a konmuş miktardır).
        WhseShptLine.SetRange("Source Type", Database::"Sales Line");
        WhseShptLine.SetRange("Source Subtype", 1);
        WhseShptLine.SetRange("Source No.", OrderNo);
        if WhseShptLine.FindSet() then
            repeat
                Expected := WhseShptLine."Qty. Picked" - WhseShptLine."Qty. Shipped";
                if Expected <= 0 then
                    Expected := WhseShptLine."Qty. Outstanding";
                InsertLine(PackSession, OrderNo, WhseShptLine."Item No.", WhseShptLine."Variant Code",
                    WhseShptLine."Unit of Measure Code", WhseShptLine.Description, Expected, LineNo, Inserted);
            until WhseShptLine.Next() = 0;
        if Inserted then
            exit;

        // Yedek: ambar sevkiyatı olmayan (basit) lokasyon — satış satırı kalanları.
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        SalesLine.SetRange("Document No.", OrderNo);
        SalesLine.SetRange(Type, SalesLine.Type::Item);
        SalesLine.SetFilter("Outstanding Quantity", '>0');
        if SalesLine.FindSet() then
            repeat
                InsertLine(PackSession, OrderNo, SalesLine."No.", SalesLine."Variant Code",
                    SalesLine."Unit of Measure Code", SalesLine.Description, SalesLine."Outstanding Quantity", LineNo, Inserted);
            until SalesLine.Next() = 0;

        if not Inserted then
            Error(NoLinesForOrderErr, OrderNo);
    end;

    local procedure InsertLine(var PackSession: Record "DOPSWHS Pack Session"; OrderNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UoM: Code[10]; Desc: Text[100]; Qty: Decimal; var LineNo: Integer; var Inserted: Boolean)
    var
        Line: Record "DOPSWHS Pack Session Line";
        Item: Record Item;
    begin
        if Qty <= 0 then
            exit;
        LineNo += 10000;
        Line.Init();
        Line."Session Entry No." := PackSession."Entry No.";
        Line."Line No." := LineNo;
        Line."Source Order No." := OrderNo;
        Line."Item No." := ItemNo;
        Line."Variant Code" := VariantCode;
        Line."Unit of Measure Code" := UoM;
        Line.Description := Desc;
        if (ItemNo <> '') and Item.Get(ItemNo) then
            Line.GTIN := Item.GTIN;
        Line."Qty. Expected" := Qty;
        Line.Insert(true);
        Inserted := true;
    end;

    local procedure MatchesItem(var Line: Record "DOPSWHS Pack Session Line"; Scanned: Code[20]): Boolean
    begin
        if Line."Item No." = Scanned then
            exit(true);
        exit((Line.GTIN <> '') and (Line.GTIN = CopyStr(Scanned, 1, MaxStrLen(Line.GTIN))));
    end;

    local procedure OrderIsComplete(SessionId: Integer; OrderNo: Code[20]): Boolean
    var
        Line: Record "DOPSWHS Pack Session Line";
    begin
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Source Order No.", OrderNo);
        Line.SetRange("Order Completed", false);
        if Line.FindSet() then
            repeat
                if Line."Qty. Packed" < Line."Qty. Expected" then
                    exit(false);
            until Line.Next() = 0;
        exit(true);
    end;

    local procedure OrderHasBox(SessionId: Integer; OrderNo: Code[20]): Boolean
    var
        Line: Record "DOPSWHS Pack Session Line";
    begin
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Source Order No.", OrderNo);
        Line.SetFilter("Box LP No.", '<>%1', '');
        exit(not Line.IsEmpty());
    end;

    // Sipariş ancak (a) tüm satırları tam paketlenmiş VE (b) kutusu okutulmuşsa
    // kapanır. ELOG kutu-sonra akışı: ürünler bitse bile KUTU okutulmadan sipariş
    // kapanmaz (Direct Order Packing dahil — eskiden bu modda kutu atlan­ıyordu).
    // Zaten kapanmış sipariş yeniden post edilmez.
    local procedure TryCompleteOrder(var PackSession: Record "DOPSWHS Pack Session"; OrderNo: Code[20]): Boolean
    var
        Line: Record "DOPSWHS Pack Session Line";
    begin
        Line.SetRange("Session Entry No.", PackSession."Entry No.");
        Line.SetRange("Source Order No.", OrderNo);
        Line.SetRange("Order Completed", false);
        if Line.IsEmpty() then
            exit(false);
        if not OrderIsComplete(PackSession."Entry No.", OrderNo) then
            exit(false);
        if not OrderHasBox(PackSession."Entry No.", OrderNo) then
            exit(false);
        CompleteOrder(PackSession, OrderNo);
        exit(true);
    end;

    local procedure MapMode(ModeTxt: Text): Enum "DOPSWHS Pack Mode"
    begin
        case LowerCase(ModeTxt) of
            'bulk':
                exit(Enum::"DOPSWHS Pack Mode"::Bulk);
            'batch', 'mono', 'mono-sku':
                exit(Enum::"DOPSWHS Pack Mode"::Batch);
            else
                exit(Enum::"DOPSWHS Pack Mode"::Solo);
        end;
    end;

    local procedure CompleteOrder(var PackSession: Record "DOPSWHS Pack Session"; OrderNo: Code[20])
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
        Line: Record "DOPSWHS Pack Session Line";
        PackingOrder: Record "DOPSWHS Packing Order";
    begin
        PostOrder(PackSession, OrderNo);
        QueuePackReceiptPrint(OrderNo);

        Line.SetRange("Session Entry No.", PackSession."Entry No.");
        Line.SetRange("Source Order No.", OrderNo);
        Line.ModifyAll("Order Completed", true);

        if not PackSession."Direct Order Packing" then begin
            Assignment.SetRange("LP No.", PackSession."Tote LP No.");
            Assignment.SetRange("Source Order No.", OrderNo);
            Assignment.ModifyAll(Packed, true);
        end;

        if PackSession."Direct Order Packing" and PackingOrder.Get(OrderNo) then begin
            PackingOrder.Status := PackingOrder.Status::Completed;
            PackingOrder."Completed DateTime" := CurrentDateTime();
            PackingOrder.Modify(true);
        end;

        PackSession."Orders Completed" += 1;
        if PackSession."Orders Completed" >= PackSession."Orders Total" then begin
            PackSession.Status := PackSession.Status::Completed;
            PackSession."Completed DateTime" := CurrentDateTime();
            ReleaseTote(PackSession);
        end;
        PackSession.Modify(true);
        Log('Pack.OrderCompleted', OrderNo);
    end;

    local procedure PostOrder(var PackSession: Record "DOPSWHS Pack Session"; OrderNo: Code[20])
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        SalesHeader: Record "Sales Header";
        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
    begin
        WhseShptLine.SetRange("Source Type", Database::"Sales Line");
        WhseShptLine.SetRange("Source Subtype", 1);
        WhseShptLine.SetRange("Source No.", OrderNo);
        if WhseShptLine.FindFirst() then begin
            PostViaWhseShipment(PackSession, WhseShptLine."No.", OrderNo);
            exit;
        end;

        // Basit lokasyon: paketlenen miktarları satış satırlarına yazıp doğrudan sevk+fatura.
        SetSalesQtyToShipFromPacked(PackSession."Entry No.", OrderNo);
        SalesHeader.Get(SalesHeader."Document Type"::Order, OrderNo);
        ShipmentMgmt.PostSalesOrderShipAndInvoice(SalesHeader);
    end;

    // Çok siparişli ambar sevkiyatında yalnız tamamlanan siparişi postla:
    // tüm satırların "Qty. to Ship"i sıfırlanır, bu siparişin paketlenen
    // miktarları yazılır, sevkiyat fatura ile post edilir. Kalan siparişler
    // kendi tamamlanmalarında aynı yoldan post edilir.
    local procedure PostViaWhseShipment(var PackSession: Record "DOPSWHS Pack Session"; ShipmentNo: Code[20]; OrderNo: Code[20])
    var
        WhseShptHeader: Record "Warehouse Shipment Header";
        WhseShptLine: Record "Warehouse Shipment Line";
        OrderShptLine: Record "Warehouse Shipment Line";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        PackedByKey: Dictionary of [Text, Decimal];
        Avail: Decimal;
        Take: Decimal;
        ItemKey: Text;
    begin
        WhseShptHeader.Get(ShipmentNo);

        WhseShptLine.SetRange("No.", ShipmentNo);
        if WhseShptLine.FindSet(true) then
            repeat
                if WhseShptLine."Qty. to Ship" <> 0 then begin
                    WhseShptLine.Validate("Qty. to Ship", 0);
                    WhseShptLine.Modify(true);
                end;
            until WhseShptLine.Next() = 0;

        BuildPackedDict(PackSession."Entry No.", OrderNo, PackedByKey);

        OrderShptLine.SetRange("No.", ShipmentNo);
        OrderShptLine.SetRange("Source Type", Database::"Sales Line");
        OrderShptLine.SetRange("Source Subtype", 1);
        OrderShptLine.SetRange("Source No.", OrderNo);
        if OrderShptLine.FindSet(true) then
            repeat
                ItemKey := ItemVariantKey(OrderShptLine."Item No.", OrderShptLine."Variant Code");
                if PackedByKey.Get(ItemKey, Avail) and (Avail > 0) then begin
                    Take := OrderShptLine."Qty. Outstanding";
                    if Take > Avail then
                        Take := Avail;
                    if Take > 0 then begin
                        OrderShptLine.Validate("Qty. to Ship", Take);
                        OrderShptLine.Modify(true);
                        PackedByKey.Set(ItemKey, Avail - Take);
                    end;
                end;
            until OrderShptLine.Next() = 0;

        if WhseShptHeader.Status <> WhseShptHeader.Status::Released then begin
            WhseShipmentRelease.Release(WhseShptHeader);
            WhseShptHeader.Get(ShipmentNo);
        end;

        OrderShptLine.SetFilter("Qty. to Ship", '>0');
        if not OrderShptLine.FindFirst() then
            Error(NothingToPostErr, OrderNo);
        WhsePostShipment.SetPostingSettings(true);
        WhsePostShipment.Run(OrderShptLine);
    end;

    local procedure BuildPackedDict(SessionId: Integer; OrderNo: Code[20]; var PackedByKey: Dictionary of [Text, Decimal])
    var
        Line: Record "DOPSWHS Pack Session Line";
        Existing: Decimal;
        ItemKey: Text;
    begin
        Line.SetRange("Session Entry No.", SessionId);
        Line.SetRange("Source Order No.", OrderNo);
        if Line.FindSet() then
            repeat
                if Line."Qty. Packed" > 0 then begin
                    ItemKey := ItemVariantKey(Line."Item No.", Line."Variant Code");
                    if PackedByKey.Get(ItemKey, Existing) then
                        PackedByKey.Set(ItemKey, Existing + Line."Qty. Packed")
                    else
                        PackedByKey.Add(ItemKey, Line."Qty. Packed");
                end;
            until Line.Next() = 0;
    end;

    local procedure SetSalesQtyToShipFromPacked(SessionId: Integer; OrderNo: Code[20])
    var
        Line: Record "DOPSWHS Pack Session Line";
        SalesLine: Record "Sales Line";
        PackedByKey: Dictionary of [Text, Decimal];
        Avail: Decimal;
        Take: Decimal;
        ItemKey: Text;
    begin
        BuildPackedDict(SessionId, OrderNo, PackedByKey);
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        SalesLine.SetRange("Document No.", OrderNo);
        SalesLine.SetRange(Type, SalesLine.Type::Item);
        if SalesLine.FindSet(true) then
            repeat
                ItemKey := ItemVariantKey(SalesLine."No.", SalesLine."Variant Code");
                if PackedByKey.Get(ItemKey, Avail) and (Avail > 0) then begin
                    Take := SalesLine."Outstanding Quantity";
                    if Take > Avail then
                        Take := Avail;
                    SalesLine.Validate("Qty. to Ship", Take);
                    SalesLine.Modify(true);
                    PackedByKey.Set(ItemKey, Avail - Take);
                end else begin
                    SalesLine.Validate("Qty. to Ship", 0);
                    SalesLine.Modify(true);
                end;
            until SalesLine.Next() = 0;
    end;

    /// <summary>Pack Station "Print Last Packed Order": tamamlanmış siparişin
    /// fişini yeniden kuyruğa alır.</summary>
    procedure ReprintOrderReceipt(OrderNo: Code[20])
    begin
        if OrderNo = '' then
            exit;
        QueuePackReceiptPrint(OrderNo);
        Log('Pack.Reprint', OrderNo);
    end;

    // ELOG: "tüm ürünler okutulunca fiş çıkıyor, poşete yapıştırılıyor" —
    // faturanın fişi IWX PackReceipt seçimi (yoksa standart satış faturası)
    // ile Print Dispatcher üzerinden istasyon yazıcısına kuyruklanır.
    local procedure QueuePackReceiptPrint(OrderNo: Code[20])
    var
        SalesInvHeader: Record "Sales Invoice Header";
        ReportSelection: Record "DOPSWHS IWX Report Selection";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        ReportId: Integer;
    begin
        SalesInvHeader.SetRange("Order No.", OrderNo);
        if not SalesInvHeader.FindLast() then
            exit;
        ReportSelection.SetRange(Usage, ReportSelection.Usage::PackReceipt);
        if ReportSelection.FindFirst() then
            ReportId := ReportSelection."Report ID"
        else
            ReportId := Report::"Standard Sales - Invoice";
        PrintDispatcher.QueueReport(SalesInvHeader."No.", ReportId);
    end;

    local procedure ReleaseTote(var PackSession: Record "DOPSWHS Pack Session")
    var
        LP: Record "DOPSWHS LP Header";
        Template: Record "DOPSWHS LP Template";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if not LP.Get(PackSession."Tote LP No.") then
            exit;
        // Kalıcı (reusable) tote yeniden kullanım için serbest bırakılır;
        // geçici LP yaşam döngüsü sevkiyat post'unda Used'a döner.
        if Template.Get(LP."LP Template Code") and Template.Reusable then
            if LP.Status = LP.Status::Assigned then
                LPMgt.Release(LP);
    end;

    local procedure ItemVariantKey(ItemNo: Code[20]; VariantCode: Code[10]): Text
    begin
        exit(ItemNo + '|' + VariantCode);
    end;

    local procedure Log(Category: Text; DocNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, DocNo);
    end;

    var
        NoOrdersForToteErr: Label 'No open orders are assigned to tote %1. Assign the tote during picking first.', Comment = '%1 = LP No.';
        NoOrdersForPickErr: Label 'No packable orders found for pick %1.', Comment = '%1 = Pick No.';
        NoLinesForOrderErr: Label 'No packable lines found for order %1.', Comment = '%1 = Sales Order No.';
        NoOpenOrderErr: Label 'There is no open order to attach a box to in this session.';
        UnexpectedItemErr: Label 'Item %1 is not expected in tote %2 or its orders are already fully packed.', Comment = '%1 = Item No., %2 = LP No.';
        NothingToPostErr: Label 'Nothing to post for order %1 — no shipment line received a quantity.', Comment = '%1 = Sales Order No.';
        ScanToteTxt: Label 'Scan a tote (LP) to start';
        ScanBoxTxt: Label 'Scan a box for order %1', Comment = '%1 = Sales Order No.';
        ScanItemTxt: Label 'Scan items';
}
