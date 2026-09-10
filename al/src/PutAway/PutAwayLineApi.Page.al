page 72228 "DOPSWHS PutAway Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'putAwayLine';
    EntitySetName = 'putAwayLines';
    SourceTable = "Warehouse Activity Line";
    DelayedInsert = true;
    ODataKeyFields = "Activity Type", "No.", "Line No.";
    Permissions = tabledata "DOPSWHS Quality Order" = r;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(activityType; Rec."Activity Type") { Caption = 'activityType'; Editable = false; }
                field(actionType; Rec."Action Type") { Caption = 'actionType'; Editable = false; }
                field(no; Rec."No.") { Caption = 'no'; Editable = false; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; Editable = false; }
                field(sourceNo; Rec."Source No.") { Caption = 'sourceNo'; Editable = false; }
                field(sourceLineNo; Rec."Source Line No.") { Caption = 'sourceLineNo'; Editable = false; }
                field(whseDocumentNo; Rec."Whse. Document No.") { Caption = 'whseDocumentNo'; Editable = false; }
                field(whseDocumentLineNo; Rec."Whse. Document Line No.") { Caption = 'whseDocumentLineNo'; Editable = false; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; Editable = false; }
                // Ek alanlar (müşteri isteği: ürün no+isim yetmiyor).
                field(description; Rec.Description) { Caption = 'description'; Editable = false; }
                field(description2; Rec."Description 2") { Caption = 'description2'; Editable = false; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; Editable = false; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; Editable = false; }
                field(gtin; ItemGtin) { Caption = 'gtin'; Editable = false; }
                field(zoneCode; Rec."Zone Code") { Caption = 'zoneCode'; Editable = false; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                // Kısmi register görünürlüğü: toplam / kalan / konan — mobil bu
                // üçlü olmadan parçalı yerleştirmede kalan miktarı gösteremiyor.
                field(quantity; Rec.Quantity) { Caption = 'quantity'; Editable = false; }
                field(qtyOutstanding; Rec."Qty. Outstanding") { Caption = 'qtyOutstanding'; Editable = false; }
                field(qtyToHandle; Rec."Qty. to Handle") { Caption = 'qtyToHandle'; }
                field(qtyHandled; Rec."Qty. Handled") { Caption = 'qtyHandled'; Editable = false; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; Editable = false; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; Editable = false; }
                field(lpNo; Rec."LP No.") { Caption = 'lpNo'; }
                field(lpSscc; LpSscc) { Caption = 'lpSscc'; Editable = false; }
                field(lpQualityStatus; LpQualityStatus) { Caption = 'lpQualityStatus'; Editable = false; }
                field(lpQualityBin; LpQualityBin) { Caption = 'lpQualityBin'; Editable = false; }
                field(targetLpNo; Rec."Target LP No.") { Caption = 'targetLpNo'; Editable = false; }
                // Dolu olması, satırın gerçekten palet okutularak doğrulandığı
                // anlamına gelir. Mal kabulden miras kalan lpNo damgası tek
                // başına okutma kanıtı değildir; terminal ikisini ayırabilsin.
                field(sourceLpLineNo; Rec."DOPSWHS Source LP Line No.") { Caption = 'sourceLpLineNo'; Editable = false; }
            }
        }
    }
    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::PutAwayLine);
        RecRef.SetTable(Rec);
    end;

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
        LP: Record "DOPSWHS LP Header";
    begin
        Clear(ItemGtin);
        Clear(LpSscc);
        if (Rec."Item No." <> '') and Item.Get(Rec."Item No.") then
            ItemGtin := Item.GTIN;
        if (Rec."LP No." <> '') and LP.Get(Rec."LP No.") then
            LpSscc := LP.SSCC;
        LoadLpQuality();
    end;

    local procedure LoadLpQuality()
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        Clear(LpQualityStatus);
        Clear(LpQualityBin);
        if Rec."LP No." = '' then
            exit;

        QualityOrder.SetRange("LP No.", Rec."LP No.");
        if QualityOrder.FindSet() then
            repeat
                case QualityOrder.Status of
                    QualityOrder.Status::Open,
                    QualityOrder.Status::InProgress:
                        begin
                            LpQualityStatus := 'InProgress';
                            exit;
                        end;
                    QualityOrder.Status::Failed:
                        begin
                            LpQualityStatus := 'Failed';
                            LpQualityBin := QualityOrder."Quarantine Bin";
                        end;
                    QualityOrder.Status::Passed:
                        if LpQualityStatus = '' then
                            LpQualityStatus := 'Passed';
                    QualityOrder.Status::Closed:
                        if LpQualityStatus = '' then
                            LpQualityStatus := 'Closed';
                end;
            until QualityOrder.Next() = 0;
    end;

    /// <summary>
    /// Mobil yerleştirme için hedef raf ve miktarı tek işlemde doğrular ve
    /// Place satırına kalıcı olarak yazar. Genel API PATCH'i bazı BC
    /// sürümlerinde Warehouse Activity Line'ın raf doğrulamasını güvenilir
    /// biçimde çalıştırmadığı için register önerilen eski rafla devam
    /// edebiliyordu.
    /// </summary>
    [ServiceEnabled]
    procedure setPlacement(targetBinCode: Code[20]; qtyToHandle: Decimal)
    var
        LPVerification: Codeunit "DOPSWHS LP Verification";
    begin
        Rec.TestField("Action Type", Rec."Action Type"::Place);
        // Zorunluluk açıkken bu eski uç, paleti okutmamış bir terminalin
        // yerleştirmeyi tamamlamasına izin vermemeli. "Source LP Line No."
        // yalnız doğrulanmış okutmayla dolar (aşağıdaki setPlacementFromLp);
        // mal kabulden miras kalan "LP No." damgası okutma sayılmaz.
        if LPVerification.ScanRequired() and (Rec."DOPSWHS Source LP Line No." = 0) then
            Error(PlacementNeedsScanErr, Rec."No.", Rec."Line No.");
        ApplyPlacement(targetBinCode, qtyToHandle);
    end;

    /// <summary>
    /// LP okutmalı yerleştirme. Paletin üzerinde ürün barkodu bulunmadığı için
    /// "doğru ürünü koydum" kanıtı okutulan paletin İÇERİĞİNİN yerleştirme
    /// satırıyla karşılaştırılmasıyla üretilir: madde, varyant, lot, seri ve
    /// kaynak raf sunucuda denetlenir, uymayan palet reddedilir.
    /// Eski setPlacement ucu geriye dönük uyumluluk için korunur.
    /// </summary>
    [ServiceEnabled]
    procedure setPlacementFromLp(targetBinCode: Code[20]; qtyToHandle: Decimal; sourceLpNo: Code[20]; userId: Code[50])
    var
        TakeLine: Record "Warehouse Activity Line";
        MatchedLPLine: Record "DOPSWHS LP Line";
        LPVerification: Codeunit "DOPSWHS LP Verification";
        AvailableBaseQty: Decimal;
    begin
        Rec.TestField("Action Type", Rec."Action Type"::Place);
        if sourceLpNo = '' then
            Error(SourceLpRequiredErr, Rec."Line No.");
        EnsurePutAwayOperator(userId);

        // Doğrulama "Al" satırına karşı yapılır: paletin fiziksel olarak
        // durduğu kaynak raf ve alınacak madde/lot orada tanımlıdır. "Koy"
        // satırı hedef rafı taşır ve kaynak rafı bilmez.
        if not FindRelatedTakeLine(Rec, TakeLine) then
            Error(TakeLineMissingErr, Rec."No.", Rec."Line No.");

        AvailableBaseQty :=
            LPVerification.VerifyScannedLp(
                sourceLpNo, TakeLine, TakeLine."Lot No.", TakeLine."Serial No.", false, MatchedLPLine);

        ApplyPlacement(targetBinCode, qtyToHandle);

        // Miktar denetimi yerleştirme yazıldıktan SONRA yapılır; taban miktar
        // ancak standart Validate çalıştıktan sonra hesaplanır. Hata bu noktada
        // tüm işlemi geri alır, yarım yazılmış satır kalmaz.
        LPVerification.CheckRequestedQuantity(
            sourceLpNo, Rec."Item No.", AvailableBaseQty, Rec."Qty. to Handle (Base)");

        StampVerifiedLp(sourceLpNo, MatchedLPLine."Line No.");
    end;

    local procedure ApplyPlacement(TargetBinCode: Code[20]; QtyToHandle: Decimal)
    var
        TargetBin: Record Bin;
    begin
        if TargetBinCode = '' then
            Error('Hedef raf zorunludur.');
        if not TargetBin.Get(Rec."Location Code", TargetBinCode) then
            Error('%1 hedef rafı %2 lokasyonunda bulunamadı.', TargetBinCode, Rec."Location Code");
        if QtyToHandle <= 0 then
            Error('Yerleştirme miktarı sıfırdan büyük olmalıdır.');
        if QtyToHandle > Rec."Qty. Outstanding" then
            Error('Yerleştirme miktarı %1, kalan %2 miktarını aşamaz.', QtyToHandle, Rec."Qty. Outstanding");

        VerifyQualityPlacement(TargetBinCode);

        // Önerilen raftan farklı bir hedef başka zone'da olabilir. Yalnız Bin
        // Code'u doğrulamak, Place satırındaki eski öneri zone'unu korur ve BC
        // geçerli hedef rafı reddeder. Önce hedef binin gerçek zone'unu uygula;
        // standart Validate yine bin tipi/blokaj gibi depo kurallarını korur.
        Rec.Validate("Zone Code", TargetBin."Zone Code");
        Rec.Validate("Bin Code", TargetBinCode);
        Rec.Validate("Qty. to Handle", QtyToHandle);
        Rec.Modify(true);
        // Eş "Al" satırı da aynı miktara çekilmeli. Yalnız "Koy" satırı
        // güncellenirse alınan ve konan miktar farklı kalır; aradaki fark
        // ambar defterinde yoktan stok olarak görünür.
        SyncRelatedTakeLine(Rec, QtyToHandle);
    end;

    /// <summary>
    /// Belge başka bir operatördeyse yerleştirme tamamlanamaz. Atanmamış belge
    /// serbest bırakılır (terminal önce assignToMe çağırır; atama yarışını o uç
    /// kilitle çözer).
    /// </summary>
    local procedure EnsurePutAwayOperator(UserIdValue: Code[50])
    var
        PutAwayHeader: Record "Warehouse Activity Header";
    begin
        if UserIdValue = '' then
            Error('WMS kullanıcı kimliği boş olamaz. Terminal oturumunu yenileyin.');
        if not PutAwayHeader.Get(PutAwayHeader.Type::"Put-away", Rec."No.") then
            Error('Yerleştirme belgesi %1 artık bulunamıyor. Listeyi yenileyin.', Rec."No.");
        if (PutAwayHeader."Assigned User ID" <> '') and (PutAwayHeader."Assigned User ID" <> UserIdValue) then
            Error(
                'Yerleştirme belgesi %1, %2 kullanıcısına atanmış.',
                Rec."No.", PutAwayHeader."Assigned User ID");
    end;

    /// <summary>
    /// Doğrulanmış paleti hem "Koy" hem eş "Al" satırına damgalar. Satır
    /// numarası da yazılır: bu alanın dolu olması, yerleştirmenin gerçekten
    /// okutmayla doğrulandığının tek kanıtıdır.
    /// </summary>
    local procedure StampVerifiedLp(SourceLpNo: Code[20]; SourceLpLineNo: Integer)
    var
        PlaceLine: Record "Warehouse Activity Line";
        TakeLine: Record "Warehouse Activity Line";
    begin
        PlaceLine.Get(Rec."Activity Type", Rec."No.", Rec."Line No.");
        PlaceLine."LP No." := SourceLpNo;
        PlaceLine."DOPSWHS Source LP Line No." := SourceLpLineNo;
        PlaceLine.Modify(true);
        Rec := PlaceLine;

        if FindRelatedTakeLine(PlaceLine, TakeLine) then begin
            TakeLine."LP No." := SourceLpNo;
            TakeLine."DOPSWHS Source LP Line No." := SourceLpLineNo;
            TakeLine.Modify(true);
        end;
    end;

    /// <summary>Yerleştirmede "Koy" satırının eş "Al" satırını aynı miktara çeker.</summary>
    local procedure SyncRelatedTakeLine(PlaceLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal)
    var
        TakeLine: Record "Warehouse Activity Line";
    begin
        if not FindRelatedTakeLine(PlaceLine, TakeLine) then
            exit;
        if TakeLine."Qty. to Handle" = QtyToHandle then
            exit;
        TakeLine.Validate("Qty. to Handle", QtyToHandle);
        TakeLine.Modify(true);
    end;

    /// <summary>
    /// "Koy" satırının eş "Al" satırı. Miktar eşitleme ve LP doğrulaması AYNI
    /// eşleştirmeyi kullanmalıdır; iki ayrı kopya zamanla ayrışıp farklı
    /// satırları hedefleyebilirdi.
    /// Lot/seri henüz yazılmamış satırlarda yapısal eşleşme tek adaya
    /// düşüyorsa o kabul edilir (mevcut davranış korunur).
    /// </summary>
    local procedure FindRelatedTakeLine(PlaceLine: Record "Warehouse Activity Line"; var TakeLine: Record "Warehouse Activity Line"): Boolean
    begin
        TakeLine.Reset();
        TakeLine.SetRange("Activity Type", PlaceLine."Activity Type");
        TakeLine.SetRange("No.", PlaceLine."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.SetRange("Whse. Document Type", PlaceLine."Whse. Document Type");
        TakeLine.SetRange("Whse. Document No.", PlaceLine."Whse. Document No.");
        TakeLine.SetRange("Whse. Document Line No.", PlaceLine."Whse. Document Line No.");
        TakeLine.SetRange("Item No.", PlaceLine."Item No.");
        TakeLine.SetRange("Variant Code", PlaceLine."Variant Code");
        TakeLine.SetRange("Unit of Measure Code", PlaceLine."Unit of Measure Code");
        TakeLine.SetRange("Lot No.", PlaceLine."Lot No.");
        TakeLine.SetRange("Serial No.", PlaceLine."Serial No.");
        if TakeLine.FindFirst() then
            exit(true);
        TakeLine.SetRange("Lot No.");
        TakeLine.SetRange("Serial No.");
        if TakeLine.Count() <> 1 then
            exit(false);
        exit(TakeLine.FindFirst());
    end;

    local procedure VerifyQualityPlacement(TargetBinCode: Code[20])
    var
        QualityOrder: Record "DOPSWHS Quality Order";
    begin
        if Rec."LP No." = '' then
            exit;

        QualityOrder.SetRange("LP No.", Rec."LP No.");
        if QualityOrder.FindSet() then
            repeat
                case QualityOrder.Status of
                    QualityOrder.Status::Open,
                    QualityOrder.Status::InProgress:
                        Error(
                            '%1 LP numarasının kalite kontrolü henüz tamamlanmadı. LP karantina gözünde kalmalıdır.',
                            Rec."LP No.");
                    QualityOrder.Status::Failed:
                        begin
                            QualityOrder.TestField("Quarantine Bin");
                            if QualityOrder."Quarantine Bin" <> TargetBinCode then
                                Error(
                                    '%1 LP numarası kalite kontrolden reddedildi. Yalnız %2 ret/karantina gözüne yerleştirilebilir.',
                                    Rec."LP No.", QualityOrder."Quarantine Bin");
                        end;
                end;
            until QualityOrder.Next() = 0;
    end;

    var
        ItemGtin: Code[14];
        LpSscc: Code[18];
        LpQualityStatus: Text[20];
        LpQualityBin: Code[20];
        PlacementNeedsScanErr: Label 'Bu yerleştirme kaynak palet okutularak tamamlanmalıdır (%1 / %2). El terminalini güncelleyin veya kurulum kartındaki "LP Scan Required" ayarını kapatın.', Comment = '%1 = document no., %2 = line no.';
        SourceLpRequiredErr: Label '%1 satırında kaynak LP okutmak zorunludur. Paletin QR kodunu okutun.', Comment = '%1 = line no.';
        TakeLineMissingErr: Label '%1 yerleştirmesinin %2 satırı için eş "Al" satırı bulunamadı. Belgeyi BC''de kontrol edin.', Comment = '%1 = document no., %2 = line no.';
}
