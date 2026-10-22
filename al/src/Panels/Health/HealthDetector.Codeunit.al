/// <summary>
/// Depo Sağlık Paneli (Sorun Merkezi). BADE'de 22 Eki 2026'da yazıldı; Kitoko
/// hattına (22 Eki 2026) göz zorunlu OLMAYAN lokasyonlar için uyarlandı.
/// Taranan sorunlar: LP miktarı ≠ gerçek stok (göz zorunluysa göz bazında,
/// değilse lokasyon + madde/varyant/lot bazında madde girişlerinden), LP
/// satırının bağlı olduğu madde girişi yok/tükenmiş, LP lokasyon/göz
/// uyuşmazlığı, negatif/sıfır/birimi bilinmeyen LP satırı, yetim LP ataması,
/// geri alınmış mal kabulde dolu LP, bloke ürün stoğu, takılan baskı, eski
/// yazıcı eşleşmesi. Sonuç geçici "DOPSWHS Health Issue" tamponuna yazılır.
/// Tarama hiçbir kaydı değiştirmez. Düzeltmeler yalnız mevcut onarım
/// yordamlarını çağırır (DOPSWHS Panel LP Repair → LP Management).
/// Her kategori en çok MaxRowsPerCategory bulgu gösterir; fazlası sayılır.
/// OnRun: tek bulguyu düzeltir (sayfa Codeunit.Run ile yalıtarak çağırır).
/// </summary>
codeunit 72388 "DOPSWHS Health Detector"
{
    TableNo = "DOPSWHS Health Issue";

    trigger OnRun()
    begin
        Rec."Fix Result" := CopyStr(FixIssue(Rec), 1, MaxStrLen(Rec."Fix Result"));
        Rec."Fix Succeeded" := true;
    end;

    var
        Totals: Dictionary of [Integer, Integer];
        Shown: Dictionary of [Integer, Integer];
        SeverityTotals: Dictionary of [Integer, Integer];
        LimitedCategories: List of [Integer];
        QtyPerUoMCache: Dictionary of [Text, Decimal];
        LocationMatchCache: Dictionary of [Text, Boolean];
        BinMandatoryCache: Dictionary of [Code[10], Boolean];
        InventoryCache: Dictionary of [Text, Decimal];
        NextEntryNo: Integer;
        MaxRowsPerCategory: Integer;
        MaxRowsSet: Boolean;
        CachedLocationFilter: Text;
        KeySep: Label '|', Locked = true;
        NoWritePermissionTxt: Label 'Bu düzeltme için yazma yetkiniz yok. Sistem yöneticinizden "DOPSWHS-USER" veya "DOPSWHS-ADMIN" izin kümesini isteyin.';

    // ------------------------------------------------------------------
    // Genel API
    // ------------------------------------------------------------------

    /// <summary>Kategori başına tamponda tutulacak en çok bulgu (varsayılan 50).</summary>
    procedure SetMaxRowsPerCategory(MaxRows: Integer)
    begin
        if MaxRows < 1 then
            MaxRows := 1;
        MaxRowsPerCategory := MaxRows;
        MaxRowsSet := true;
    end;

    /// <summary>Tamponu temizler ve bütün dedektörleri çalıştırır.</summary>
    procedure DetectAll(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    begin
        Reset(Issues);
        DetectStockMismatch(LocationFilter, Issues);
        DetectOrphanAssignments(LocationFilter, Issues);
        DetectUndoneReceiptLps(LocationFilter, Issues);
        DetectLpSourceEntries(LocationFilter, Issues);
        DetectLpLocationMismatch(LocationFilter, Issues);
        DetectInvalidLpLines(LocationFilter, Issues);
        DetectBlockedItemStock(LocationFilter, Issues);
        DetectPrintJobs(LocationFilter, Issues);
        DetectPrinterMappings(LocationFilter, Issues);
    end;

    /// <summary>Tamponu ve sayaçları sıfırlar.</summary>
    procedure Reset(var Issues: Record "DOPSWHS Health Issue" temporary)
    begin
        Issues.Reset();
        Issues.DeleteAll();
        Clear(Totals);
        Clear(Shown);
        Clear(SeverityTotals);
        Clear(LimitedCategories);
        Clear(LocationMatchCache);
        Clear(BinMandatoryCache);
        Clear(InventoryCache);
        CachedLocationFilter := '';
        NextEntryNo := 0;
    end;

    /// <summary>Kategorideki toplam bulgu (gösterilmeyenler dahil).</summary>
    procedure CategoryTotal(Category: Integer): Integer
    begin
        if Totals.ContainsKey(Category) then
            exit(Totals.Get(Category));
        exit(0);
    end;

    /// <summary>Kategorinin taraması güvenlik sınırına takıldıysa true.</summary>
    procedure CategoryScanLimited(Category: Integer): Boolean
    begin
        exit(LimitedCategories.Contains(Category));
    end;

    // ------------------------------------------------------------------
    // 1) LP miktarı ≠ gerçek stok
    // ------------------------------------------------------------------

    /// <summary>
    /// Aktif (Açık/Oluşturuldu/Atandı) LP satırlarını temel birimde toplar ve
    /// gerçek stokla karşılaştırır:
    ///  - Göz zorunlu lokasyon: göz + madde + varyant (+ lot) bazında depo
    ///    girişi (Warehouse Entry) bakiyesi.
    ///  - Göz zorunlu olmayan lokasyon (Kitoko'nun çoğu): lokasyon + madde +
    ///    varyant (+ lot) bazında madde girişi (Item Ledger Entry) bakiyesi;
    ///    LP'deki göz kodu yok sayılır.
    /// Lotsuz LP satırı olan grupta lot ayrımı yapılmaz. Yalnız LP bulunan
    /// anahtarlar karşılaştırılır. LP'nin stoktan fazla olması kritiktir; göz
    /// zorunlu olmayan lokasyonda LP'siz stok (ör. İlk Sayım) yalnız bilgidir.
    /// Lokasyonu boş ya da göz zorunlu lokasyonda gözü boş LP'ler burada değil,
    /// "LP lokasyon/göz uyuşmazlığı" kategorisinde gösterilir.
    /// </summary>
    procedure DetectStockMismatch(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        LPLine: Record "DOPSWHS LP Line";
        Issue: Record "DOPSWHS Health Issue";
        GroupQty: Dictionary of [Text, Decimal];
        GroupHasBlankLot: Dictionary of [Text, Boolean];
        LotQty: Dictionary of [Text, Decimal];
        Parts: List of [Text];
        GroupKey: Text;
        LotKey: Text;
        BinKey: Code[20];
        BaseQty: Decimal;
        Scanned: Integer;
        Compared: Integer;
    begin
        LPLine.SetLoadFields("LP No.", "Item No.", "Variant Code", "Unit of Measure", Quantity, "Lot No.", "Child LP No.");
        LPLine.SetAutoCalcFields("LP Location Code", "LP Bin Code");
        LPLine.SetFilter("LP Status", '%1|%2|%3', LPLine."LP Status"::Open, LPLine."LP Status"::Built, LPLine."LP Status"::Assigned);
        if LocationFilter <> '' then
            LPLine.SetFilter("LP Location Code", LocationFilter)
        else
            LPLine.SetFilter("LP Location Code", '<>%1', '');
        LPLine.SetRange("Child LP No.", '');
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '<>0');
        if LPLine.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxLpLinesScanned() then begin
                    MarkLimited(Issue.Category::StockMismatch);
                    break;
                end;
                BinKey := '';
                if IsBinMandatory(LPLine."LP Location Code") then
                    BinKey := LPLine."LP Bin Code";
                if (LPLine."LP Location Code" <> '') and not (IsBinMandatory(LPLine."LP Location Code") and (BinKey = '')) then begin
                    BaseQty := BaseQuantity(LPLine."Item No.", LPLine."Unit of Measure", LPLine.Quantity);
                    GroupKey := LPLine."LP Location Code" + KeySep + BinKey + KeySep + LPLine."Item No." + KeySep + LPLine."Variant Code";
                    AddQty(GroupQty, GroupKey, BaseQty);
                    if LPLine."Lot No." = '' then begin
                        if not GroupHasBlankLot.ContainsKey(GroupKey) then
                            GroupHasBlankLot.Add(GroupKey, true);
                    end else
                        AddQty(LotQty, GroupKey + KeySep + LPLine."Lot No.", BaseQty);
                end;
            until LPLine.Next() = 0;

        // Lotsuz LP satırı olan gruplar: ürün düzeyinde (bütün lotlar) karşılaştır.
        foreach GroupKey in GroupHasBlankLot.Keys do begin
            Compared += 1;
            if Compared > MaxGroupsCompared() then begin
                MarkLimited(Issue.Category::StockMismatch);
                exit;
            end;
            Parts := GroupKey.Split(KeySep);
            CompareStockWithLp(Issues, Parts, '', false, GroupQty.Get(GroupKey));
        end;
        // Diğerleri: lot düzeyinde.
        foreach LotKey in LotQty.Keys do begin
            Parts := LotKey.Split(KeySep);
            GroupKey := Parts.Get(1) + KeySep + Parts.Get(2) + KeySep + Parts.Get(3) + KeySep + Parts.Get(4);
            if not GroupHasBlankLot.ContainsKey(GroupKey) then begin
                Compared += 1;
                if Compared > MaxGroupsCompared() then begin
                    MarkLimited(Issue.Category::StockMismatch);
                    exit;
                end;
                CompareStockWithLp(Issues, Parts, CopyStr(Parts.Get(5), 1, 50), true, LotQty.Get(LotKey));
            end;
        end;
    end;

    local procedure CompareStockWithLp(var Issues: Record "DOPSWHS Health Issue" temporary; Parts: List of [Text]; LotNo: Code[50]; LotLevel: Boolean; LpQty: Decimal)
    var
        WhseEntry: Record "Warehouse Entry";
        Issue: Record "DOPSWHS Health Issue";
        StockQty: Decimal;
        Diff: Decimal;
        LotText: Text;
        PlaceText: Text;
        BinLevel: Boolean;
    begin
        BinLevel := Parts.Get(2) <> '';
        if BinLevel then begin
            WhseEntry.SetRange("Location Code", Parts.Get(1));
            WhseEntry.SetRange("Bin Code", Parts.Get(2));
            WhseEntry.SetRange("Item No.", Parts.Get(3));
            WhseEntry.SetRange("Variant Code", Parts.Get(4));
            if LotLevel then
                WhseEntry.SetRange("Lot No.", LotNo);
            WhseEntry.CalcSums("Qty. (Base)");
            StockQty := WhseEntry."Qty. (Base)";
        end else
            StockQty := LocationInventory(
                CopyStr(Parts.Get(1), 1, 10), CopyStr(Parts.Get(3), 1, 20), CopyStr(Parts.Get(4), 1, 10), LotNo, LotLevel);
        Diff := LpQty - StockQty;
        if Abs(Diff) <= Tolerance() then
            exit;

        NewIssue(Issue, Issue.Category::StockMismatch, Issue.Severity::Warning);
        Issue."Location Code" := CopyStr(Parts.Get(1), 1, MaxStrLen(Issue."Location Code"));
        Issue."Bin Code" := CopyStr(Parts.Get(2), 1, MaxStrLen(Issue."Bin Code"));
        Issue."Item No." := CopyStr(Parts.Get(3), 1, MaxStrLen(Issue."Item No."));
        Issue."Variant Code" := CopyStr(Parts.Get(4), 1, MaxStrLen(Issue."Variant Code"));
        Issue."Lot No." := LotNo;
        Issue."Bin Qty. (Base)" := StockQty;
        Issue."LP Qty. (Base)" := LpQty;
        if LotNo <> '' then
            LotText := ' · Lot ' + LotNo;
        if BinLevel then
            PlaceText := StrSubstNo('%1 gözünde', Issue."Bin Code")
        else
            PlaceText := StrSubstNo('%1 lokasyonunda', Issue."Location Code");
        if BinLevel then
            Issue.Title := CopyStr(Issue."Bin Code" + ' · ' + ItemLabel(Issue."Item No.", Issue."Variant Code") + LotText, 1, MaxStrLen(Issue.Title))
        else
            Issue.Title := CopyStr(Issue."Location Code" + ' · ' + ItemLabel(Issue."Item No.", Issue."Variant Code") + LotText, 1, MaxStrLen(Issue.Title));
        if Diff > 0 then begin
            // LP'de görünen ama stokta olmayan miktar: terminal olmayan paleti gösterir.
            Issue.Severity := Issue.Severity::Critical;
            Issue.Detail := CopyStr(StrSubstNo(
                '%1 BC stoğu %2, aktif LP''ler ise %3 gösteriyor. LP''lerde %4 fazla görünüyor: terminal olmayan paleti önerebilir. Sayım veya LP düzeltmesi gerekir; otomatik düzeltme yapılmaz.',
                PlaceText, FormatQty(StockQty), FormatQty(LpQty), FormatQty(Diff)), 1, MaxStrLen(Issue.Detail));
        end else begin
            if not BinLevel then
                Issue.Severity := Issue.Severity::Info;
            Issue.Detail := CopyStr(StrSubstNo(
                '%1 BC stoğu %2, aktif LP''ler ise %3 gösteriyor. %4 stok hiçbir LP''de değil (LP''siz stok). Bilinçliyse (ör. İlk Sayım ile girilen stok) sorun yok; değilse LP oluşturun veya sayın.',
                PlaceText, FormatQty(StockQty), FormatQty(LpQty), FormatQty(-Diff)), 1, MaxStrLen(Issue.Detail));
        end;
        Issue."Show Caption" := 'LP''leri göster';
        StoreIssue(Issues, Issue);
    end;

    // ------------------------------------------------------------------
    // 2) Yetim LP ataması
    // ------------------------------------------------------------------

    /// <summary>Atandı durumundaki, belgesi artık bulunmayan LP'ler (LP Management.IsAssignmentOrphaned).</summary>
    procedure DetectOrphanAssignments(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        LP: Record "DOPSWHS LP Header";
        Issue: Record "DOPSWHS Health Issue";
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
        Scanned: Integer;
    begin
        LP.SetCurrentKey(Status, "Location Code");
        LP.SetRange(Status, LP.Status::Assigned);
        if LocationFilter <> '' then
            LP.SetFilter("Location Code", LocationFilter);
        if LP.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxAssignedLpsScanned() then begin
                    MarkLimited(Issue.Category::OrphanAssignment);
                    exit;
                end;
                if LPMgt.IsAssignmentOrphaned(LP) then begin
                    NewIssue(Issue, Issue.Category::OrphanAssignment, Issue.Severity::Warning);
                    Issue."LP No." := LP."No.";
                    Issue."Location Code" := LP."Location Code";
                    Issue."Bin Code" := LP."Bin Code";
                    Issue."Document No." := LP."Assigned Document No.";
                    Issue.Title := CopyStr(StrSubstNo('LP %1 · %2', LP."No.", AssignedDocLabel(LP)), 1, MaxStrLen(Issue.Title));
                    Issue.Detail := CopyStr(StrSubstNo(
                        'LP, artık bulunmayan %1 belgesine atanmış görünüyor (göz %2). Bu LP terminalde hiçbir işte kullanılamaz. Serbest bırakınca "Oluşturuldu" durumuna döner; stok ve göz değişmez.',
                        AssignedDocLabel(LP), LP."Bin Code"), 1, MaxStrLen(Issue.Detail));
                    Issue."Fix Available" := true;
                    Issue."Fix Caption" := 'Serbest bırak';
                    Issue."Fix Confirm" := CopyStr(StrSubstNo(
                        'LP %1 serbest bırakılsın mı? LP "Oluşturuldu" durumuna döner; stok ve göz değişmez.', LP."No."), 1, MaxStrLen(Issue."Fix Confirm"));
                    Issue."Show Caption" := 'LP kartını aç';
                    StoreIssue(Issues, Issue);
                end;
            until LP.Next() = 0;
    end;

    // ------------------------------------------------------------------
    // 3) Geri alınmış mal kabulde dolu kalan LP
    // ------------------------------------------------------------------

    /// <summary>
    /// Mal kabul geri alma (düzeltme) kayıtları; LP Management önizlemesi
    /// boşaltılacak LP satırı bulursa bulgudur. En yeni kayıtlardan başlar.
    /// </summary>
    procedure DetectUndoneReceiptLps(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        UndoEntry: Record "Item Ledger Entry";
        Issue: Record "DOPSWHS Health Issue";
        LineCount: Integer;
        Scanned: Integer;
        LotText: Text;
    begin
        UndoEntry.SetRange("Entry Type", UndoEntry."Entry Type"::Purchase);
        UndoEntry.SetRange("Document Type", UndoEntry."Document Type"::"Purchase Receipt");
        UndoEntry.SetRange(Correction, true);
        UndoEntry.SetRange(Positive, false);
        if LocationFilter <> '' then
            UndoEntry.SetFilter("Location Code", LocationFilter);
        UndoEntry.SetLoadFields("Entry No.", "Item No.", "Variant Code", "Lot No.", "Document No.", "Location Code", Quantity, "Posting Date");
        UndoEntry.Ascending(false);
        if UndoEntry.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxUndoEntriesScanned() then begin
                    MarkLimited(Issue.Category::UndoneReceiptLp);
                    exit;
                end;
                if UndoEntry.Quantity < 0 then
                    if TryPreviewUndoRepair(UndoEntry."Entry No.", LineCount) then
                        if LineCount > 0 then begin
                            NewIssue(Issue, Issue.Category::UndoneReceiptLp, Issue.Severity::Warning);
                            Issue."Location Code" := UndoEntry."Location Code";
                            Issue."Item No." := UndoEntry."Item No.";
                            Issue."Variant Code" := UndoEntry."Variant Code";
                            Issue."Lot No." := UndoEntry."Lot No.";
                            Issue."Document No." := UndoEntry."Document No.";
                            Issue."Entry Ref." := UndoEntry."Entry No.";
                            Issue."Affected Count" := LineCount;
                            Issue."Bin Qty. (Base)" := UndoEntry.Quantity;
                            LotText := '';
                            if UndoEntry."Lot No." <> '' then
                                LotText := ' · Lot ' + UndoEntry."Lot No.";
                            Issue.Title := CopyStr(StrSubstNo('İrsaliye %1 · %2%3', UndoEntry."Document No.", ItemLabel(UndoEntry."Item No.", UndoEntry."Variant Code"), LotText), 1, MaxStrLen(Issue.Title));
                            Issue.Detail := CopyStr(StrSubstNo(
                                'Mal kabul %1 tarihinde geri alındı (%2), stok düştü; ama bu kabulden gelen %3 LP satırı hâlâ dolu görünüyor. Onarım yalnız bu kabule bağlı ve gerçek stokla desteklenmeyen miktarı boşaltır.',
                                UndoEntry."Posting Date", FormatQty(UndoEntry.Quantity), LineCount), 1, MaxStrLen(Issue.Detail));
                            Issue."Fix Available" := true;
                            Issue."Fix Caption" := 'LP''leri boşalt';
                            Issue."Fix Confirm" := CopyStr(StrSubstNo(
                                '%1 irsaliyesinin geri alınan miktarı kadar (en çok %2) %3 LP satırı boşaltılsın mı? Gerçek stokla desteklenen LP''lere dokunulmaz; BC stoğu değişmez.',
                                UndoEntry."Document No.", FormatQty(-UndoEntry.Quantity), LineCount), 1, MaxStrLen(Issue."Fix Confirm"));
                            Issue."Show Caption" := 'Kayıtları göster';
                            StoreIssue(Issues, Issue);
                        end;
            until UndoEntry.Next() = 0;
    end;

    [TryFunction]
    local procedure TryPreviewUndoRepair(UndoEntryNo: Integer; var LineCount: Integer)
    var
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
    begin
        LineCount := LPMgt.PreviewUndoneReceiptLpRepair(UndoEntryNo);
    end;

    // ------------------------------------------------------------------
    // 4) LP satırının kaynak madde girişi yok / tükenmiş
    // ------------------------------------------------------------------

    /// <summary>
    /// Aktif LP satırlarını bağlı oldukları madde girişine (Source Item Ledger
    /// Entry No.) göre toplar. Giriş yoksa ya da madde/varyant/lot tutmuyorsa
    /// kritik; giriş aynı lokasyonda ve kalan miktarı bağlı LP miktarından azsa
    /// uyarı. Giriş tükenmiş ama lokasyonda bu madde/lot için LP'leri karşılayan
    /// stok varsa (LP başka girişe taşınmış) yalnız bilgi. LP başka lokasyona
    /// taşınmışsa kaynak girişin tükenmesi olağandır, gösterilmez.
    /// </summary>
    procedure DetectLpSourceEntries(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        LPLine: Record "DOPSWHS LP Line";
        Entry: Record "Item Ledger Entry";
        Issue: Record "DOPSWHS Health Issue";
        LinkedQty: Dictionary of [Text, Decimal];
        LineCounts: Dictionary of [Text, Integer];
        FirstLp: Dictionary of [Text, Code[20]];
        Parts: List of [Text];
        GroupKey: Text;
        EntryNo: Integer;
        Linked: Decimal;
        Inventory: Decimal;
        LotText: Text;
        Scanned: Integer;
        Compared: Integer;
        LocationCode: Code[10];
    begin
        LPLine.SetLoadFields("LP No.", "Item No.", "Variant Code", "Unit of Measure", Quantity, "Lot No.", "Child LP No.", "Source Item Ledger Entry No.");
        LPLine.SetAutoCalcFields("LP Location Code");
        LPLine.SetFilter("LP Status", '%1|%2|%3', LPLine."LP Status"::Open, LPLine."LP Status"::Built, LPLine."LP Status"::Assigned);
        if LocationFilter <> '' then
            LPLine.SetFilter("LP Location Code", LocationFilter);
        LPLine.SetFilter("Source Item Ledger Entry No.", '<>0');
        LPLine.SetRange("Child LP No.", '');
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxLpLinesScanned() then begin
                    MarkLimited(Issue.Category::LpSourceEntry);
                    break;
                end;
                GroupKey := Format(LPLine."Source Item Ledger Entry No.", 0, 9) + KeySep + LPLine."LP Location Code" + KeySep +
                    LPLine."Item No." + KeySep + LPLine."Variant Code" + KeySep + LPLine."Lot No.";
                AddQty(LinkedQty, GroupKey, BaseQuantity(LPLine."Item No.", LPLine."Unit of Measure", LPLine.Quantity));
                if LineCounts.ContainsKey(GroupKey) then
                    LineCounts.Set(GroupKey, LineCounts.Get(GroupKey) + 1)
                else begin
                    LineCounts.Add(GroupKey, 1);
                    FirstLp.Add(GroupKey, LPLine."LP No.");
                end;
            until LPLine.Next() = 0;

        foreach GroupKey in LinkedQty.Keys do begin
            Compared += 1;
            if Compared > MaxGroupsCompared() then begin
                MarkLimited(Issue.Category::LpSourceEntry);
                exit;
            end;
            Parts := GroupKey.Split(KeySep);
            Evaluate(EntryNo, Parts.Get(1));
            LocationCode := CopyStr(Parts.Get(2), 1, MaxStrLen(LocationCode));
            Linked := LinkedQty.Get(GroupKey);
            NewIssue(Issue, Issue.Category::LpSourceEntry, Issue.Severity::Warning);
            Issue."Location Code" := LocationCode;
            Issue."Item No." := CopyStr(Parts.Get(3), 1, MaxStrLen(Issue."Item No."));
            Issue."Variant Code" := CopyStr(Parts.Get(4), 1, MaxStrLen(Issue."Variant Code"));
            Issue."Lot No." := CopyStr(Parts.Get(5), 1, MaxStrLen(Issue."Lot No."));
            Issue."LP No." := FirstLp.Get(GroupKey);
            Issue."Entry Ref." := EntryNo;
            Issue."Affected Count" := LineCounts.Get(GroupKey);
            Issue."LP Qty. (Base)" := Linked;
            LotText := '';
            if Issue."Lot No." <> '' then
                LotText := ' · Lot ' + Issue."Lot No.";
            Issue.Title := CopyStr(StrSubstNo('Giriş %1 · %2%3', EntryNo, ItemLabel(Issue."Item No.", Issue."Variant Code"), LotText), 1, MaxStrLen(Issue.Title));
            Issue."Show Caption" := 'Girişi göster';
            Entry.SetLoadFields("Entry No.", "Item No.", "Variant Code", "Lot No.", "Location Code", "Remaining Quantity", Open, "Document No.");
            if not Entry.Get(EntryNo) then begin
                Issue.Severity := Issue.Severity::Critical;
                Issue.Detail := CopyStr(StrSubstNo(
                    '%1 LP satırı (ilk LP %2, toplam %3) %4 numaralı madde girişine bağlı, ama bu giriş yok. LP''nin stokla bağı kopmuş; LP İzlenebilirlik ile kontrol edin, gerekirse sayın.',
                    Issue."Affected Count", Issue."LP No.", FormatQty(Linked), EntryNo), 1, MaxStrLen(Issue.Detail));
                Issue."Show Caption" := 'LP kartını aç';
                StoreIssue(Issues, Issue);
            end else
                if (Entry."Item No." <> Issue."Item No.") or (Entry."Variant Code" <> Issue."Variant Code") or
                   ((Entry."Lot No." <> '') and (Entry."Lot No." <> Issue."Lot No."))
                then begin
                    Issue.Severity := Issue.Severity::Critical;
                    Issue."Document No." := Entry."Document No.";
                    Issue.Detail := CopyStr(StrSubstNo(
                        'LP %1 satırı %2 girişine bağlı, ama giriş başka madde/varyant/lot taşıyor (%3 %4 lot %5). LP içeriği yanlış girilmiş olabilir.',
                        Issue."LP No.", EntryNo, Entry."Item No.", Entry."Variant Code", Entry."Lot No."), 1, MaxStrLen(Issue.Detail));
                    StoreIssue(Issues, Issue);
                end else
                    if Entry."Location Code" = LocationCode then begin
                        Issue."Bin Qty. (Base)" := Entry."Remaining Quantity";
                        Issue."Document No." := Entry."Document No.";
                        if Entry."Remaining Quantity" < Linked - Tolerance() then begin
                            Inventory := LocationInventory(LocationCode, Issue."Item No.", Issue."Variant Code", Issue."Lot No.", Issue."Lot No." <> '');
                            if Inventory >= Linked - Tolerance() then begin
                                // Stok lokasyonda duruyor; yalnız LP'nin kaynak bağı eski bir girişi gösteriyor.
                                Issue.Severity := Issue.Severity::Info;
                                Issue.Detail := CopyStr(StrSubstNo(
                                    '%1 girişinde kalan %2, bu girişe bağlı LP''ler %3. Lokasyonda bu madde/lot için %4 stok var; LP büyük olasılıkla başka girişe taşındı. Bağ eski ama stok yerinde.',
                                    EntryNo, FormatQty(Entry."Remaining Quantity"), FormatQty(Linked), FormatQty(Inventory)), 1, MaxStrLen(Issue.Detail));
                            end else
                                Issue.Detail := CopyStr(StrSubstNo(
                                    '%1 girişinde kalan %2, bu girişe bağlı aktif LP''ler ise %3 gösteriyor; lokasyondaki toplam stok da (%4) LP''leri karşılamıyor. Stok LP''den düşülmeden çıkmış (satış, sarf, geri alma) olabilir.',
                                    EntryNo, FormatQty(Entry."Remaining Quantity"), FormatQty(Linked), FormatQty(Inventory)), 1, MaxStrLen(Issue.Detail));
                            StoreIssue(Issues, Issue);
                        end;
                    end;
        end;
    end;

    // ------------------------------------------------------------------
    // 5) LP lokasyon / göz uyuşmazlığı
    // ------------------------------------------------------------------

    /// <summary>
    /// İçinde stok bulunan aktif LP'lerde: lokasyonu boş ya da tanımsız, göz
    /// zorunlu lokasyonda gözü boş, gözü bu lokasyonda tanımlı değil, göz
    /// kullanmayan lokasyonda göz kodu taşıyan (bilgi) ya da üst LP'siyle farklı
    /// lokasyon/gözde duran LP'ler.
    /// </summary>
    procedure DetectLpLocationMismatch(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        LP: Record "DOPSWHS LP Header";
        Scanned: Integer;
    begin
        LP.SetLoadFields("No.", "Location Code", "Bin Code", Status, "Parent LP No.");
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        // Lokasyonu boş LP her depo filtresinde gösterilir (hangi depoya ait olduğu bilinmiyor).
        LP.SetRange("Location Code", '');
        if LP.FindSet() then
            repeat
                Scanned += 1;
                CheckLpPlacement(Issues, LP);
            until (LP.Next() = 0) or (Scanned > MaxAssignedLpsScanned());
        if LocationFilter <> '' then
            LP.SetFilter("Location Code", LocationFilter)
        else
            LP.SetFilter("Location Code", '<>%1', '');
        if LP.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxAssignedLpsScanned() * 5 then begin
                    MarkLimited(Enum_LpLocationMismatch());
                    exit;
                end;
                CheckLpPlacement(Issues, LP);
            until LP.Next() = 0;
    end;

    local procedure CheckLpPlacement(var Issues: Record "DOPSWHS Health Issue" temporary; LP: Record "DOPSWHS LP Header")
    var
        Location: Record Location;
        Bin: Record Bin;
        Parent: Record "DOPSWHS LP Header";
        Issue: Record "DOPSWHS Health Issue";
        Reason: Text;
        Severity: Integer;
    begin
        Severity := Issue.Severity::Warning;
        if LP."Location Code" = '' then begin
            Reason := 'LP''nin lokasyonu boş; stoğu hiçbir lokasyonla eşleşmez.';
            Severity := Issue.Severity::Critical;
        end else
            if not Location.Get(LP."Location Code") then begin
                Reason := StrSubstNo('LP''nin lokasyonu (%1) tanımlı değil.', LP."Location Code");
                Severity := Issue.Severity::Critical;
            end else
                if Location."Bin Mandatory" and (LP."Bin Code" = '') then
                    Reason := StrSubstNo('%1 lokasyonu göz zorunlu, ama LP''nin gözü boş. LP göz/LP karşılaştırmasına girmez; terminal LP''yi bulamayabilir.', LP."Location Code")
                else
                    if (LP."Bin Code" <> '') and not Bin.Get(LP."Location Code", LP."Bin Code") then begin
                        Reason := StrSubstNo('LP''nin gözü (%1) %2 lokasyonunda tanımlı değil.', LP."Bin Code", LP."Location Code");
                        Severity := Issue.Severity::Critical;
                    end else
                        if (not Location."Bin Mandatory") and (LP."Bin Code" <> '') then begin
                            Reason := StrSubstNo('%1 lokasyonu göz kullanmıyor, ama LP''de %2 gözü yazılı. Stok karşılaştırmasında göz yok sayılır.', LP."Location Code", LP."Bin Code");
                            Severity := Issue.Severity::Info;
                        end;
        if (Reason = '') and (LP."Parent LP No." <> '') then
            if Parent.Get(LP."Parent LP No.") then
                if (Parent."Location Code" <> LP."Location Code") or (Parent."Bin Code" <> LP."Bin Code") then
                    Reason := StrSubstNo('LP, üst LP %1 ile farklı yerde: bu LP %2 %3, üst LP %4 %5.',
                        Parent."No.", LP."Location Code", LP."Bin Code", Parent."Location Code", Parent."Bin Code");
        if Reason = '' then
            exit;
        if not LpHasStock(LP."No.") then
            exit;
        NewIssue(Issue, Issue.Category::LpLocationMismatch, Severity);
        Issue."LP No." := LP."No.";
        Issue."Location Code" := LP."Location Code";
        Issue."Bin Code" := LP."Bin Code";
        Issue.Title := CopyStr(StrSubstNo('LP %1 · %2 %3', LP."No.", LP."Location Code", LP."Bin Code"), 1, MaxStrLen(Issue.Title));
        Issue.Detail := CopyStr(Reason, 1, MaxStrLen(Issue.Detail));
        Issue."Show Caption" := 'LP kartını aç';
        StoreIssue(Issues, Issue);
    end;

    local procedure LpHasStock(LpNo: Code[20]): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetFilter(Quantity, '<>0');
        exit(not LPLine.IsEmpty());
    end;

    local procedure Enum_LpLocationMismatch(): Integer
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        exit(Issue.Category::LpLocationMismatch);
    end;

    // ------------------------------------------------------------------
    // 6) Negatif / sıfır / birimi bilinmeyen LP satırı
    // ------------------------------------------------------------------

    /// <summary>
    /// Aktif LP'lerin satırları: negatif miktar (kritik), maddesi olmayan ya da
    /// maddesi/birimi bulunamayan satır (uyarı, temel birime çevrilemez), sıfır
    /// miktarlı artık satır (bilgi).
    /// </summary>
    procedure DetectInvalidLpLines(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        LPLine: Record "DOPSWHS LP Line";
        Issue: Record "DOPSWHS Health Issue";
        Reason: Text;
        Severity: Integer;
        Scanned: Integer;
    begin
        LPLine.SetLoadFields("LP No.", "Line No.", "Item No.", "Variant Code", "Unit of Measure", Quantity, "Lot No.", "Child LP No.");
        LPLine.SetAutoCalcFields("LP Location Code", "LP Bin Code");
        LPLine.SetFilter("LP Status", '%1|%2|%3', LPLine."LP Status"::Open, LPLine."LP Status"::Built, LPLine."LP Status"::Assigned);
        if LocationFilter <> '' then
            LPLine.SetFilter("LP Location Code", LocationFilter);
        LPLine.SetRange("Child LP No.", '');
        if LPLine.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxLpLinesScanned() then begin
                    MarkLimited(Issue.Category::InvalidLpQty);
                    exit;
                end;
                Reason := '';
                Severity := Issue.Severity::Warning;
                if LPLine.Quantity < 0 then begin
                    Reason := StrSubstNo('Satır miktarı negatif (%1 %2). Negatif LP satırı stok toplamlarını bozar; satırı düzeltin veya LP''yi sayın.', FormatQty(LPLine.Quantity), LPLine."Unit of Measure");
                    Severity := Issue.Severity::Critical;
                end else
                    if LPLine."Item No." = '' then begin
                        if LPLine.Quantity <> 0 then
                            Reason := StrSubstNo('Satırda madde yok ama miktar %1. Bu miktar hiçbir stokla eşleşmez.', FormatQty(LPLine.Quantity));
                    end else
                        if not UnitKnown(LPLine."Item No.", LPLine."Unit of Measure") then
                            Reason := StrSubstNo('Madde %1 ya da birimi %2 bulunamadı; satır temel birime çevrilemiyor, karşılaştırmalarda 1:1 sayılıyor.', LPLine."Item No.", LPLine."Unit of Measure")
                        else
                            if LPLine.Quantity = 0 then begin
                                Reason := 'Satır miktarı sıfır (boşalmış satır). Zararsızdır; LP içeriğini sadeleştirmek için silinebilir.';
                                Severity := Issue.Severity::Info;
                            end;
                if Reason <> '' then begin
                    NewIssue(Issue, Issue.Category::InvalidLpQty, Severity);
                    Issue."LP No." := LPLine."LP No.";
                    Issue."Location Code" := LPLine."LP Location Code";
                    Issue."Bin Code" := LPLine."LP Bin Code";
                    Issue."Item No." := LPLine."Item No.";
                    Issue."Variant Code" := LPLine."Variant Code";
                    Issue."Lot No." := LPLine."Lot No.";
                    Issue."Entry Ref." := LPLine."Line No.";
                    Issue."LP Qty. (Base)" := LPLine.Quantity;
                    Issue.Title := CopyStr(StrSubstNo('LP %1 satır %2 · %3', LPLine."LP No.", LPLine."Line No.", ItemLabel(LPLine."Item No.", LPLine."Variant Code")), 1, MaxStrLen(Issue.Title));
                    Issue.Detail := CopyStr(Reason, 1, MaxStrLen(Issue.Detail));
                    Issue."Show Caption" := 'LP kartını aç';
                    StoreIssue(Issues, Issue);
                end;
            until LPLine.Next() = 0;
    end;

    local procedure UnitKnown(ItemNo: Code[20]; UnitOfMeasure: Code[10]): Boolean
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        Item.SetLoadFields("Base Unit of Measure");
        if not Item.Get(ItemNo) then
            exit(false);
        if (UnitOfMeasure = '') or (UnitOfMeasure = Item."Base Unit of Measure") then
            exit(true);
        ItemUoM.SetLoadFields("Qty. per Unit of Measure");
        exit(ItemUoM.Get(ItemNo, UnitOfMeasure) and (ItemUoM."Qty. per Unit of Measure" > 0));
    end;

    // ------------------------------------------------------------------
    // 7) Bloke ürünün stoğu
    // ------------------------------------------------------------------

    /// <summary>
    /// Ürün kartında Bloke olan ürünlerin lokasyon + varyant bazında stoğu
    /// (madde girişlerinden; göz zorunlu olmayan lokasyonlarda da çalışır). Bilgi.
    /// </summary>
    procedure DetectBlockedItemStock(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        Item: Record Item;
        Entry: Record "Item Ledger Entry";
        Issue: Record "DOPSWHS Health Issue";
        StockByPlace: Dictionary of [Text, Decimal];
        Parts: List of [Text];
        PlaceKey: Text;
        Qty: Decimal;
        Scanned: Integer;
    begin
        Item.SetRange(Blocked, true);
        Item.SetLoadFields("No.", Description, Blocked);
        if Item.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxBlockedItemsScanned() then begin
                    MarkLimited(Issue.Category::BlockedItemStock);
                    exit;
                end;
                Clear(StockByPlace);
                Entry.Reset();
                Entry.SetCurrentKey("Item No.", Open);
                Entry.SetRange("Item No.", Item."No.");
                Entry.SetRange(Open, true);
                if LocationFilter <> '' then
                    Entry.SetFilter("Location Code", LocationFilter);
                Entry.SetLoadFields("Location Code", "Variant Code", "Remaining Quantity");
                if Entry.FindSet() then
                    repeat
                        AddQty(StockByPlace, Entry."Location Code" + KeySep + Entry."Variant Code", Entry."Remaining Quantity");
                    until Entry.Next() = 0;
                foreach PlaceKey in StockByPlace.Keys do begin
                    Qty := StockByPlace.Get(PlaceKey);
                    if Qty > Tolerance() then begin
                        Parts := PlaceKey.Split(KeySep);
                        NewIssue(Issue, Issue.Category::BlockedItemStock, Issue.Severity::Info);
                        Issue."Location Code" := CopyStr(Parts.Get(1), 1, MaxStrLen(Issue."Location Code"));
                        Issue."Item No." := Item."No.";
                        Issue."Variant Code" := CopyStr(Parts.Get(2), 1, MaxStrLen(Issue."Variant Code"));
                        Issue."Bin Qty. (Base)" := Qty;
                        Issue.Title := CopyStr(StrSubstNo('%1 · %2', Issue."Location Code", ItemLabel(Item."No.", Issue."Variant Code")), 1, MaxStrLen(Issue.Title));
                        Issue.Detail := CopyStr(StrSubstNo(
                            'Ürün kartında bloke, ama %1 lokasyonunda %2 stok duruyor. Bu stok toplanamaz ve sevk edilemez. Bloke bilinçliyse sorun yok; değilse ürün kartını kontrol edin.',
                            Issue."Location Code", FormatQty(Qty)), 1, MaxStrLen(Issue.Detail));
                        Issue."Show Caption" := 'Ürün kartını aç';
                        StoreIssue(Issues, Issue);
                    end;
                end;
            until Item.Next() = 0;
    end;

    // ------------------------------------------------------------------
    // 8) Başarısız / takılmış baskı işleri
    // ------------------------------------------------------------------

    /// <summary>
    /// Bugün başarısız olan baskı işleri ve 10 dakikadan eski Kuyrukta/Gönderildi
    /// (Dispatched) işler. Depo filtresi yazıcı kartındaki depoya göre uygulanır;
    /// deposu bilinmeyen yazıcının işi her filtrede gösterilir.
    /// </summary>
    procedure DetectPrintJobs(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        Job: Record "DOPSWHS Print Job Queue";
        Issue: Record "DOPSWHS Health Issue";
        Scanned: Integer;
    begin
        Job.SetRange(Status, Job.Status::Failed);
        Job.SetFilter(Created, '>=%1', CreateDateTime(Today(), 0T));
        Job.SetLoadFields("Job ID", "Source Doc", "Printer ID", Status, Created, "Last Error", "Retry Count", "Dispatched At");
        Job.Ascending(false);
        if Job.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxPrintJobsScanned() then begin
                    MarkLimited(Issue.Category::PrintJob);
                    break;
                end;
                AddPrintJobIssue(Issues, Job, LocationFilter, true);
            until Job.Next() = 0;

        Job.Reset();
        Job.SetFilter(Status, '%1|%2', Job.Status::Queued, Job.Status::Dispatched);
        Job.SetFilter(Created, '<%1', CurrentDateTime() - StuckAfterMs());
        Job.SetLoadFields("Job ID", "Source Doc", "Printer ID", Status, Created, "Last Error", "Retry Count", "Dispatched At");
        Job.Ascending(false);
        Scanned := 0;
        if Job.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxPrintJobsScanned() then begin
                    MarkLimited(Issue.Category::PrintJob);
                    exit;
                end;
                AddPrintJobIssue(Issues, Job, LocationFilter, false);
            until Job.Next() = 0;
    end;

    local procedure AddPrintJobIssue(var Issues: Record "DOPSWHS Health Issue" temporary; Job: Record "DOPSWHS Print Job Queue"; LocationFilter: Text; Failed: Boolean)
    var
        Printer: Record "DOPSWHS Printer";
        Issue: Record "DOPSWHS Health Issue";
        PrinterText: Text;
        ErrorText: Text;
        PrinterLocation: Code[10];
    begin
        PrinterText := Job."Printer ID";
        if StrLen(Job."Printer ID") <= MaxStrLen(Printer.Code) then
            if Printer.Get(CopyStr(Job."Printer ID", 1, MaxStrLen(Printer.Code))) then begin
                PrinterLocation := Printer."Location Code";
                if Printer.Description <> '' then
                    PrinterText := Printer.Code + ' (' + Printer.Description + ')';
            end;
        if PrinterText = '' then
            PrinterText := '(yazıcı yok)';
        if not LocationMatches(PrinterLocation, LocationFilter) then
            exit;

        NewIssue(Issue, Issue.Category::PrintJob, Issue.Severity::Warning);
        Issue."Location Code" := PrinterLocation;
        Issue."Entry Ref." := Job."Job ID";
        Issue."Document No." := CopyStr(Job."Source Doc", 1, MaxStrLen(Issue."Document No."));
        Issue."Ref. Text" := CopyStr(PrinterText, 1, MaxStrLen(Issue."Ref. Text"));
        ErrorText := Job."Last Error";
        if ErrorText = '' then
            ErrorText := 'hata mesajı yok';
        if Failed then begin
            Issue.Severity := Issue.Severity::Critical;
            Issue.Title := CopyStr(StrSubstNo('Baskı başarısız · %1', PrinterText), 1, MaxStrLen(Issue.Title));
            Issue.Detail := CopyStr(StrSubstNo(
                '%1 belgesinin baskısı %2 tarihinde başarısız oldu (%3 deneme). Son hata: %4',
                Job."Source Doc", Job.Created, Job."Retry Count", ErrorText), 1, MaxStrLen(Issue.Detail));
        end else begin
            Issue.Title := CopyStr(StrSubstNo('Baskı bekliyor · %1', PrinterText), 1, MaxStrLen(Issue.Title));
            Issue.Detail := CopyStr(StrSubstNo(
                '%1 belgesinin baskısı %2 tarihinden beri "%3" durumunda bekliyor. Yazıcı ajanı çalışıyor mu, yazıcı açık mı kontrol edin. Son hata: %4',
                Job."Source Doc", Job.Created, Job.Status, ErrorText), 1, MaxStrLen(Issue.Detail));
        end;
        Issue."Show Caption" := 'Baskı kuyruğunu aç';
        StoreIssue(Issues, Issue);
    end;

    // ------------------------------------------------------------------
    // 9) Eski/pasif yazıcıya bağlı cihaz eşleşmeleri
    // ------------------------------------------------------------------

    /// <summary>
    /// Cihaz–yazıcı eşleşmesi silinmiş, pasif ya da 30 günden uzun süredir
    /// görülmeyen yazıcıyı gösteriyorsa bilgi bulgusu.
    /// </summary>
    procedure DetectPrinterMappings(LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary)
    var
        DeviceMap: Record "DOPSWHS Device Printer Map";
        Printer: Record "DOPSWHS Printer";
        Issue: Record "DOPSWHS Health Issue";
        DeviceText: Text;
        Reason: Text;
        Scanned: Integer;
    begin
        DeviceMap.SetFilter("Printer Code", '<>%1', '');
        DeviceMap.SetLoadFields("Device ID", Usage, "Printer Code");
        if DeviceMap.FindSet() then
            repeat
                Scanned += 1;
                if Scanned > MaxMappingsScanned() then begin
                    MarkLimited(Issue.Category::PrinterMapping);
                    exit;
                end;
                Reason := '';
                Clear(Printer);
                if not Printer.Get(DeviceMap."Printer Code") then
                    Reason := 'yazıcı kaydı silinmiş'
                else
                    if not Printer.Active then
                        Reason := 'yazıcı pasif'
                    else
                        if (Printer."Last Seen At" <> 0DT) and (Printer."Last Seen At" < CurrentDateTime() - StalePrinterMs()) then
                            Reason := StrSubstNo('yazıcı %1 tarihinden beri görülmedi', DT2Date(Printer."Last Seen At"));
                if Reason <> '' then
                    if LocationMatches(Printer."Location Code", LocationFilter) then begin
                        NewIssue(Issue, Issue.Category::PrinterMapping, Issue.Severity::Info);
                        DeviceText := DeviceMap."Device ID";
                        if DeviceText = '' then
                            DeviceText := 'Tüm cihazlar (varsayılan)';
                        Issue."Location Code" := Printer."Location Code";
                        Issue."Ref. Text" := CopyStr(DeviceMap."Device ID", 1, MaxStrLen(Issue."Ref. Text"));
                        Issue."Entry Ref." := DeviceMap.Usage.AsInteger();
                        Issue."Document No." := CopyStr(DeviceMap."Printer Code", 1, MaxStrLen(Issue."Document No."));
                        Issue.Title := CopyStr(StrSubstNo('%1 · %2 → %3', DeviceText, Format(DeviceMap.Usage), DeviceMap."Printer Code"), 1, MaxStrLen(Issue.Title));
                        Issue.Detail := CopyStr(StrSubstNo(
                            '"%1" kullanımı için seçili yazıcı %2: %3. Bu cihazdan bu baskı gitmeyebilir; eşleşmeyi güncel bir yazıcıya çevirin.',
                            Format(DeviceMap.Usage), DeviceMap."Printer Code", Reason), 1, MaxStrLen(Issue.Detail));
                        Issue."Show Caption" := 'Eşleşmeyi aç';
                        StoreIssue(Issues, Issue);
                    end;
            until DeviceMap.Next() = 0;
    end;

    // ------------------------------------------------------------------
    // Düzeltmeler
    // ------------------------------------------------------------------

    /// <summary>Kullanıcının bu kategorinin düzeltmesi için yazma izni var mı.</summary>
    procedure CanFixCategory(Category: Integer): Boolean
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Category of
            Issue.Category::OrphanAssignment:
                exit(LP.WritePermission());
            Issue.Category::UndoneReceiptLp:
                exit(LP.WritePermission() and LPLine.WritePermission());
        end;
        exit(false);
    end;

    /// <summary>
    /// Tek bulguyu düzeltir; düzeltilemiyorsa hata verir. Mevcut onarım
    /// yordamları kendi korumalarını (önizleme/sınır) yeniden uygular.
    /// Döndürür: kullanıcıya gösterilecek sonuç metni.
    /// </summary>
    procedure FixIssue(var Issue: Record "DOPSWHS Health Issue"): Text
    var
        LP: Record "DOPSWHS LP Header";
        Scope: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
        Counter: Integer;
    begin
        if not Issue."Fix Available" then
            Error('Bu bulgu için otomatik düzeltme yok.');
        if not CanFixCategory(Issue.Category) then
            Error(NoWritePermissionTxt);
        case Issue.Category of
            Issue.Category::OrphanAssignment:
                begin
                    if not LP.Get(Issue."LP No.") then
                        Error('LP %1 artık yok.', Issue."LP No.");
                    if not LPMgt.IsAssignmentOrphaned(LP) then
                        exit(StrSubstNo('LP %1 artık yetim değil; değişiklik yapılmadı.', Issue."LP No."));
                    Scope.SetRange("No.", Issue."LP No.");
                    Counter := LPMgt.ReleaseOrphanAssignments(Scope, true);
                    exit(StrSubstNo('LP %1 serbest bırakıldı (%2).', Issue."LP No.", Counter));
                end;
            Issue.Category::UndoneReceiptLp:
                begin
                    Counter := LPMgt.RepairUndoneReceiptLps(Issue."Entry Ref.");
                    if Counter = 0 then
                        exit(StrSubstNo('%1 irsaliyesi için boşaltılacak LP kalmadı; değişiklik yapılmadı.', Issue."Document No."));
                    exit(StrSubstNo('%1 irsaliyesi: %2 LP satırı boşaltıldı.', Issue."Document No.", Counter));
                end;
        end;
        Error('Bu bulgu için otomatik düzeltme yok.');
    end;

    /// <summary>
    /// Bulguyu kendi işleminde düzeltir (hata yalnız o bulguyu geri alır).
    /// Bekleyen yazma işlemini Commit eder; test kodu FixIssue'yu doğrudan çağırmalı.
    /// </summary>
    procedure RunFixIsolated(var Issue: Record "DOPSWHS Health Issue"): Boolean
    begin
        Commit();
        Issue."Fix Result" := '';
        Issue."Fix Succeeded" := false;
        ClearLastError();
        if Codeunit.Run(Codeunit::"DOPSWHS Health Detector", Issue) then
            exit(true);
        Issue."Fix Succeeded" := false;
        Issue."Fix Result" := CopyStr(GetLastErrorText(), 1, MaxStrLen(Issue."Fix Result"));
        exit(false);
    end;

    /// <summary>
    /// Kategorideki bütün düzeltilebilir bulguları sırayla (her biri yalıtılmış)
    /// düzeltir. Yetim atamalarda depo filtresindeki bütün yetim LP'ler (gösterilmeyenler
    /// dahil) tek işlemde serbest bırakılır. Döndürür: özet metin.
    /// </summary>
    procedure FixCategory(Category: Integer; LocationFilter: Text; var Issues: Record "DOPSWHS Health Issue" temporary): Text
    var
        Scope: Record "DOPSWHS LP Header";
        Work: Record "DOPSWHS Health Issue";
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
        Fixed: Integer;
        Failed: Integer;
        FirstError: Text;
    begin
        if not CanFixCategory(Category) then
            Error(NoWritePermissionTxt);
        if Category = Work.Category::OrphanAssignment then begin
            if LocationFilter <> '' then
                Scope.SetFilter("Location Code", LocationFilter);
            Fixed := LPMgt.ReleaseOrphanAssignments(Scope, true);
            exit(StrSubstNo('%1 LP serbest bırakıldı.', Fixed));
        end;
        Issues.Reset();
        Issues.SetRange(Category, Category);
        Issues.SetRange("Fix Available", true);
        if Issues.FindSet() then
            repeat
                Work := Issues;
                if RunFixIsolated(Work) then
                    Fixed += 1
                else begin
                    Failed += 1;
                    if FirstError = '' then
                        FirstError := Work.Title + ': ' + Work."Fix Result";
                end;
            until Issues.Next() = 0;
        Issues.Reset();
        if Failed = 0 then
            exit(StrSubstNo('%1 bulgu düzeltildi.', Fixed));
        exit(StrSubstNo('%1 bulgu düzeltildi, %2 bulgu düzeltilemedi. İlk hata: %3', Fixed, Failed, FirstError));
    end;

    // ------------------------------------------------------------------
    // Gezinme ("Göster")
    // ------------------------------------------------------------------

    /// <summary>
    /// Bulgunun ilgili BC kaydını/sayfasını açar. Target = 'compare': Göz ve LP
    /// Karşılaştırma (bulgunun lokasyon/göz/madde bağlamıyla); 'trace': LP
    /// İzlenebilirlik (LP no, yoksa "madde lot" ya da madde ile arama).
    /// </summary>
    procedure ShowIssue(Issue: Record "DOPSWHS Health Issue"; Target: Text)
    var
        LP: Record "DOPSWHS LP Header";
        Item: Record Item;
        ItemLedgerEntry: Record "Item Ledger Entry";
        Job: Record "DOPSWHS Print Job Queue";
        DeviceMap: Record "DOPSWHS Device Printer Map";
        LPMgt: Codeunit "DOPSWHS Panel LP Repair";
        ComparePage: Page "DOPSWHS Bin LP Compare";
        TracePage: Page "DOPSWHS LP Trace";
        EntryNos: List of [Integer];
        EntryNo: Integer;
        EntryFilter: Text;
    begin
        if (Target = 'trace') and (TraceSearchText(Issue) <> '') then begin
            TracePage.SetSearch(TraceSearchText(Issue));
            TracePage.Run();
            exit;
        end;
        if (Target = 'compare') and CompareAvailableFor(Issue) then begin
            ComparePage.SetContext(Issue."Location Code", Issue."Bin Code", Issue."Item No.");
            ComparePage.Run();
            exit;
        end;
        case Issue.Category of
            Issue.Category::StockMismatch:
                begin
                    LP.SetRange("Location Code", Issue."Location Code");
                    if Issue."Bin Code" <> '' then
                        LP.SetRange("Bin Code", Issue."Bin Code");
                    LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
                    Page.Run(Page::"DOPSWHS LP List", LP);
                end;
            Issue.Category::OrphanAssignment,
            Issue.Category::LpLocationMismatch,
            Issue.Category::InvalidLpQty:
                begin
                    LP.SetRange("No.", Issue."LP No.");
                    Page.Run(Page::"DOPSWHS LP Card", LP);
                end;
            Issue.Category::LpSourceEntry:
                if ItemLedgerEntry.Get(Issue."Entry Ref.") then begin
                    ItemLedgerEntry.SetRange("Entry No.", Issue."Entry Ref.");
                    Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
                end else begin
                    LP.SetRange("No.", Issue."LP No.");
                    Page.Run(Page::"DOPSWHS LP Card", LP);
                end;
            Issue.Category::UndoneReceiptLp:
                begin
                    // Geri alma kaydı + geri alınan mal kabul kaydı birlikte.
                    LPMgt.CollectUndoneReceiptEntries(Issue."Entry Ref.", EntryNos);
                    EntryFilter := Format(Issue."Entry Ref.");
                    ItemLedgerEntry.SetRange("Document No.", Issue."Document No.");
                    ItemLedgerEntry.SetRange("Item No.", Issue."Item No.");
                    ItemLedgerEntry.SetRange("Lot No.", Issue."Lot No.");
                    ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Purchase);
                    foreach EntryNo in EntryNos do
                        if EntryNo <> Issue."Entry Ref." then
                            EntryFilter += '|' + Format(EntryNo);
                    if ItemLedgerEntry.IsEmpty() then begin
                        ItemLedgerEntry.Reset();
                        ItemLedgerEntry.SetFilter("Entry No.", EntryFilter);
                    end;
                    Page.Run(Page::"Item Ledger Entries", ItemLedgerEntry);
                end;
            Issue.Category::BlockedItemStock:
                begin
                    Item.SetRange("No.", Issue."Item No.");
                    Page.Run(Page::"Item Card", Item);
                end;
            Issue.Category::PrintJob:
                begin
                    if Issue."Entry Ref." <> 0 then
                        Job.SetRange("Job ID", Issue."Entry Ref.");
                    Page.Run(Page::"DOPSWHS Print Job Queue", Job);
                end;
            Issue.Category::PrinterMapping:
                begin
                    DeviceMap.SetRange("Device ID", Issue."Ref. Text");
                    Page.Run(Page::"DOPSWHS Device Printer Map", DeviceMap);
                end;
        end;
    end;

    /// <summary>Göz ve LP Karşılaştırma sayfası (aynı uygulamada; geriye uyumluluk için yordam olarak kalır).</summary>
    procedure FindBinLpComparisonPage(): Integer
    begin
        exit(Page::"DOPSWHS Bin LP Compare");
    end;

    /// <summary>Bulgu karşılaştırma ekranında açılabilir mi (lokasyon ve madde bilinen stok/LP bulguları).</summary>
    procedure CompareAvailableFor(Issue: Record "DOPSWHS Health Issue"): Boolean
    begin
        if Issue."Location Code" = '' then
            exit(false);
        exit(Issue.Category in [Issue.Category::StockMismatch, Issue.Category::LpSourceEntry, Issue.Category::BlockedItemStock]);
    end;

    /// <summary>LP İzlenebilirlik araması: LP no; yoksa "madde lot"; yoksa madde.</summary>
    procedure TraceSearchText(Issue: Record "DOPSWHS Health Issue"): Text
    begin
        if Issue."LP No." <> '' then
            exit(Issue."LP No.");
        if Issue."Item No." = '' then
            exit('');
        if Issue."Lot No." <> '' then
            exit(Issue."Item No." + ' ' + Issue."Lot No.");
        exit(Issue."Item No.");
    end;

    // ------------------------------------------------------------------
    // JSON (kontrol eklentisi için)
    // ------------------------------------------------------------------

    /// <summary>Panelin SetData yükü: kategoriler, bulgular, depo listesi, özet.</summary>
    procedure BuildJson(var Issues: Record "DOPSWHS Health Issue" temporary; LocationFilter: Text): Text
    var
        Root: JsonObject;
        Summary: JsonObject;
        Categories: JsonArray;
        Result: Text;
        Category: Integer;
        CompareAvailable: Boolean;
    begin
        CompareAvailable := FindBinLpComparisonPage() <> 0;
        Root.Add('version', 1);
        Root.Add('generatedAt', Format(CurrentDateTime(), 0, 9));
        Root.Add('locationFilter', LocationFilter);
        Root.Add('locations', LocationsJson());
        Root.Add('maxRowsPerCategory', MaxRows());
        Root.Add('compareAvailable', CompareAvailable);
        Summary.Add('critical', SeverityTotal(Issues.Severity::Critical));
        Summary.Add('warning', SeverityTotal(Issues.Severity::Warning));
        Summary.Add('info', SeverityTotal(Issues.Severity::Info));
        Root.Add('summary', Summary);
        Root.Add('traceAvailable', true);
        for Category := Issues.Category::StockMismatch to Issues.Category::PrinterMapping do
            Categories.Add(CategoryJson(Issues, Category, CompareAvailable));
        Issues.Reset();
        Root.Add('categories', Categories);
        Root.WriteTo(Result);
        exit(Result);
    end;

    local procedure CategoryJson(var Issues: Record "DOPSWHS Health Issue" temporary; Category: Integer; CompareAvailable: Boolean): JsonObject
    var
        Cat: JsonObject;
        Rows: JsonArray;
        Row: JsonObject;
        CanFix: Boolean;
    begin
        CanFix := CanFixCategory(Category);
        Cat.Add('key', CategoryKey(Category));
        Cat.Add('title', CategoryTitle(Category));
        Cat.Add('description', CategoryDescription(Category));
        Cat.Add('total', CategoryTotal(Category));
        Cat.Add('scanLimited', CategoryScanLimited(Category));
        Cat.Add('fixable', CategoryFixable(Category));
        Cat.Add('canFix', CanFix);
        if CategoryFixable(Category) and not CanFix then
            Cat.Add('fixDeniedReason', NoWritePermissionTxt)
        else
            Cat.Add('fixDeniedReason', '');
        Cat.Add('fixAllCaption', CategoryFixAllCaption(Category));
        Issues.Reset();
        Issues.SetCurrentKey(Category, Severity);
        Issues.SetRange(Category, Category);
        Issues.Ascending(false);
        if Issues.FindSet() then
            repeat
                Clear(Row);
                Row.Add('id', Issues."Entry No.");
                Row.Add('severity', SeverityKey(Issues.Severity));
                Row.Add('title', Issues.Title);
                Row.Add('detail', Issues.Detail);
                Row.Add('location', Issues."Location Code");
                Row.Add('bin', Issues."Bin Code");
                Row.Add('item', Issues."Item No.");
                Row.Add('variant', Issues."Variant Code");
                Row.Add('lot', Issues."Lot No.");
                Row.Add('lpNo', Issues."LP No.");
                Row.Add('docNo', Issues."Document No.");
                Row.Add('ref', Issues."Ref. Text");
                Row.Add('qtyBin', Issues."Bin Qty. (Base)");
                Row.Add('qtyLp', Issues."LP Qty. (Base)");
                Row.Add('count', Issues."Affected Count");
                Row.Add('fixAvailable', Issues."Fix Available");
                Row.Add('canFix', Issues."Fix Available" and CanFix);
                Row.Add('fixCaption', Issues."Fix Caption");
                Row.Add('fixConfirm', Issues."Fix Confirm");
                Row.Add('showCaption', Issues."Show Caption");
                Row.Add('compareAvailable', CompareAvailable and CompareAvailableFor(Issues));
                Row.Add('traceAvailable', TraceSearchText(Issues) <> '');
                Rows.Add(Row);
            until Issues.Next() = 0;
        Cat.Add('issues', Rows);
        exit(Cat);
    end;

    local procedure LocationsJson(): JsonArray
    var
        Location: Record Location;
        Locations: JsonArray;
        Entry: JsonObject;
        Counter: Integer;
    begin
        Location.SetLoadFields(Code, Name);
        if Location.FindSet() then
            repeat
                Counter += 1;
                Clear(Entry);
                Entry.Add('code', Location.Code);
                Entry.Add('name', Location.Name);
                Locations.Add(Entry);
            until (Location.Next() = 0) or (Counter >= 200);
        exit(Locations);
    end;

    procedure CategoryKey(Category: Integer): Text
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Category of
            Issue.Category::StockMismatch:
                exit('stockMismatch');
            Issue.Category::OrphanAssignment:
                exit('orphanAssignment');
            Issue.Category::UndoneReceiptLp:
                exit('undoneReceiptLp');
            Issue.Category::LpSourceEntry:
                exit('lpSourceEntry');
            Issue.Category::LpLocationMismatch:
                exit('lpLocationMismatch');
            Issue.Category::InvalidLpQty:
                exit('invalidLpQty');
            Issue.Category::BlockedItemStock:
                exit('blockedItemStock');
            Issue.Category::PrintJob:
                exit('printJob');
            Issue.Category::PrinterMapping:
                exit('printerMapping');
        end;
        exit('');
    end;

    /// <summary>JSON anahtarından kategori numarası; bilinmeyen anahtar için -1.</summary>
    procedure CategoryFromKey(CategoryKeyText: Text): Integer
    var
        Issue: Record "DOPSWHS Health Issue";
        Category: Integer;
    begin
        for Category := Issue.Category::StockMismatch to Issue.Category::PrinterMapping do
            if CategoryKey(Category) = CategoryKeyText then
                exit(Category);
        exit(-1);
    end;

    local procedure CategoryTitle(Category: Integer): Text
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Category of
            Issue.Category::StockMismatch:
                exit('LP miktarı ile stok tutmuyor');
            Issue.Category::OrphanAssignment:
                exit('Silinmiş belgeye atanmış LP');
            Issue.Category::UndoneReceiptLp:
                exit('Geri alınan mal kabulde dolu kalan LP');
            Issue.Category::LpSourceEntry:
                exit('LP''nin bağlı olduğu madde girişi yok veya tükenmiş');
            Issue.Category::LpLocationMismatch:
                exit('LP lokasyon / göz uyuşmazlığı');
            Issue.Category::InvalidLpQty:
                exit('Negatif, sıfır veya birimi bilinmeyen LP satırı');
            Issue.Category::BlockedItemStock:
                exit('Bloke üründe stok');
            Issue.Category::PrintJob:
                exit('Başarısız veya bekleyen baskı');
            Issue.Category::PrinterMapping:
                exit('Eski veya pasif yazıcı eşleşmesi');
        end;
    end;

    local procedure CategoryDescription(Category: Integer): Text
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Category of
            Issue.Category::StockMismatch:
                exit('Aktif LP''lerin toplamı gerçek BC stoğundan farklı: göz zorunlu lokasyonda göz bazında, diğerlerinde lokasyon + madde/varyant/lot bazında. LP fazlası kritiktir (terminal olmayan paleti önerir). Otomatik düzeltme yok; sayım ya da LP düzeltmesi gerekir.');
            Issue.Category::OrphanAssignment:
                exit('LP, artık bulunmayan bir belgeye (ör. silinmiş rafa kaldırma) atanmış ve terminalde kullanılamıyor. Serbest bırakmak güvenlidir: stok ve göz değişmez.');
            Issue.Category::UndoneReceiptLp:
                exit('Mal kabul geri alındı ve stok düştü, ama o kabulden gelen LP''ler hâlâ dolu. Onarım yalnız bu kabule bağlı, gerçek stokla desteklenmeyen miktarı boşaltır.');
            Issue.Category::LpSourceEntry:
                exit('LP satırının bağlı olduğu madde girişi silinmiş, başka madde/lot taşıyor ya da kalan miktarı bağlı LP''leri karşılamıyor. Stok LP''den düşülmeden çıkmış olabilir. LP İzlenebilirlik ile inceleyin.');
            Issue.Category::LpLocationMismatch:
                exit('İçinde stok olan LP''nin lokasyonu boş/tanımsız, göz zorunlu lokasyonda gözü boş, gözü lokasyonda yok ya da üst LP''siyle farklı yerde.');
            Issue.Category::InvalidLpQty:
                exit('Aktif LP''de negatif miktarlı, maddesiz veya birimi bulunamayan satır (sıfır miktarlı artık satırlar bilgi olarak).');
            Issue.Category::BlockedItemStock:
                exit('Ürün kartında bloke olan ürünler gözde stokta duruyor. Bu stok toplanamaz ve sevk edilemez. Bilgi amaçlıdır.');
            Issue.Category::PrintJob:
                exit('Bugün başarısız olan ya da 10 dakikadan uzun süredir kuyrukta bekleyen etiket ve belge baskıları.');
            Issue.Category::PrinterMapping:
                exit('Cihaz–yazıcı eşleşmesi silinmiş, pasif ya da uzun süredir görülmeyen bir yazıcıyı gösteriyor. Bu cihazdan baskı gitmeyebilir.');
        end;
    end;

    local procedure CategoryFixable(Category: Integer): Boolean
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        exit(Category in [Issue.Category::OrphanAssignment, Issue.Category::UndoneReceiptLp]);
    end;

    local procedure CategoryFixAllCaption(Category: Integer): Text
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Category of
            Issue.Category::OrphanAssignment:
                exit('Tümünü serbest bırak');
            Issue.Category::UndoneReceiptLp:
                exit('Tümünü onar');
        end;
        exit('');
    end;

    local procedure SeverityKey(Severity: Integer): Text
    var
        Issue: Record "DOPSWHS Health Issue";
    begin
        case Severity of
            Issue.Severity::Critical:
                exit('critical');
            Issue.Severity::Warning:
                exit('warning');
        end;
        exit('info');
    end;

    local procedure SeverityTotal(Severity: Integer): Integer
    begin
        if SeverityTotals.ContainsKey(Severity) then
            exit(SeverityTotals.Get(Severity));
        exit(0);
    end;

    // ------------------------------------------------------------------
    // Yardımcılar
    // ------------------------------------------------------------------

    local procedure NewIssue(var Issue: Record "DOPSWHS Health Issue"; Category: Integer; Severity: Integer)
    begin
        Clear(Issue);
        Issue.Category := Category;
        Issue.Severity := Severity;
    end;

    local procedure StoreIssue(var Issues: Record "DOPSWHS Health Issue" temporary; var Issue: Record "DOPSWHS Health Issue")
    var
        CategoryNo: Integer;
        ShownCount: Integer;
    begin
        CategoryNo := Issue.Category;
        Increment(Totals, CategoryNo);
        Increment(SeverityTotals, Issue.Severity);
        if Shown.ContainsKey(CategoryNo) then
            ShownCount := Shown.Get(CategoryNo);
        if ShownCount >= MaxRows() then
            exit;
        Increment(Shown, CategoryNo);
        if NextEntryNo = 0 then begin
            Issues.Reset();
            if Issues.FindLast() then
                NextEntryNo := Issues."Entry No.";
        end;
        NextEntryNo += 1;
        Issue."Entry No." := NextEntryNo;
        Issues := Issue;
        Issues.Insert();
    end;

    local procedure Increment(var Counter: Dictionary of [Integer, Integer]; KeyValue: Integer)
    begin
        if Counter.ContainsKey(KeyValue) then
            Counter.Set(KeyValue, Counter.Get(KeyValue) + 1)
        else
            Counter.Add(KeyValue, 1);
    end;

    local procedure AddQty(var Sums: Dictionary of [Text, Decimal]; KeyValue: Text; Qty: Decimal)
    begin
        if Sums.ContainsKey(KeyValue) then
            Sums.Set(KeyValue, Sums.Get(KeyValue) + Qty)
        else
            Sums.Add(KeyValue, Qty);
    end;

    local procedure MarkLimited(Category: Integer)
    begin
        if not LimitedCategories.Contains(Category) then
            LimitedCategories.Add(Category);
    end;

    /// <summary>LP satırı miktarını temel birime çevirir (ürün/birim önbellekli).</summary>
    local procedure BaseQuantity(ItemNo: Code[20]; UnitOfMeasure: Code[10]; Qty: Decimal): Decimal
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        CacheKey: Text;
        QtyPer: Decimal;
    begin
        CacheKey := ItemNo + KeySep + UnitOfMeasure;
        if not QtyPerUoMCache.Get(CacheKey, QtyPer) then begin
            QtyPer := 1;
            if UnitOfMeasure <> '' then begin
                Item.SetLoadFields("Base Unit of Measure");
                if Item.Get(ItemNo) then
                    if UnitOfMeasure <> Item."Base Unit of Measure" then
                        if ItemUoM.Get(ItemNo, UnitOfMeasure) then
                            if ItemUoM."Qty. per Unit of Measure" > 0 then
                                QtyPer := ItemUoM."Qty. per Unit of Measure";
            end;
            QtyPerUoMCache.Add(CacheKey, QtyPer);
        end;
        exit(Round(Qty * QtyPer, 0.00001));
    end;

    /// <summary>Boş depo kodu (bilinmeyen) her filtreye uyar.</summary>
    local procedure LocationMatches(LocationCode: Code[10]; LocationFilter: Text): Boolean
    var
        Location: Record Location;
        Matches: Boolean;
    begin
        if (LocationFilter = '') or (LocationCode = '') then
            exit(true);
        if CachedLocationFilter <> LocationFilter then begin
            Clear(LocationMatchCache);
            CachedLocationFilter := LocationFilter;
        end;
        if LocationMatchCache.Get(LocationCode, Matches) then
            exit(Matches);
        Location.FilterGroup(2);
        Location.SetFilter(Code, LocationFilter);
        Location.FilterGroup(0);
        Location.SetRange(Code, LocationCode);
        Matches := not Location.IsEmpty();
        LocationMatchCache.Add(LocationCode, Matches);
        exit(Matches);
    end;

    local procedure IsBinMandatory(LocationCode: Code[10]) BinMandatory: Boolean
    var
        Location: Record Location;
    begin
        if LocationCode = '' then
            exit(false);
        if BinMandatoryCache.Get(LocationCode, BinMandatory) then
            exit(BinMandatory);
        Location.SetLoadFields("Bin Mandatory");
        if Location.Get(LocationCode) then
            BinMandatory := Location."Bin Mandatory";
        BinMandatoryCache.Add(LocationCode, BinMandatory);
    end;

    /// <summary>Lokasyondaki gerçek stok (madde girişleri, temel birim); LotLevel ise yalnız o lot.</summary>
    local procedure LocationInventory(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; LotLevel: Boolean) Qty: Decimal
    var
        Entry: Record "Item Ledger Entry";
        CacheKey: Text;
    begin
        CacheKey := LocationCode + KeySep + ItemNo + KeySep + VariantCode + KeySep + Format(LotLevel) + KeySep + LotNo;
        if InventoryCache.Get(CacheKey, Qty) then
            exit(Qty);
        Entry.SetCurrentKey("Item No.", Open, "Variant Code", Positive, "Location Code");
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange(Open, true);
        Entry.SetRange("Variant Code", VariantCode);
        Entry.SetRange("Location Code", LocationCode);
        if LotLevel then
            Entry.SetRange("Lot No.", LotNo);
        Entry.CalcSums("Remaining Quantity");
        Qty := Entry."Remaining Quantity";
        InventoryCache.Add(CacheKey, Qty);
    end;

    local procedure ItemLabel(ItemNo: Code[20]; VariantCode: Code[10]): Text
    var
        Item: Record Item;
        Result: Text;
    begin
        Result := ItemNo;
        if VariantCode <> '' then
            Result += ' (' + VariantCode + ')';
        Item.SetLoadFields(Description);
        if Item.Get(ItemNo) then
            if Item.Description <> '' then
                Result += ' ' + Item.Description;
        exit(Result);
    end;

    local procedure AssignedDocLabel(LP: Record "DOPSWHS LP Header"): Text
    var
        DocName: Text;
    begin
        case LP."Assigned Document Type" of
            LP."Assigned Document Type"::WhseReceipt:
                DocName := 'mal kabul';
            LP."Assigned Document Type"::WhsePick:
                DocName := 'toplama';
            LP."Assigned Document Type"::WhseShipment:
                DocName := 'sevkiyat';
            LP."Assigned Document Type"::WhsePutaway:
                DocName := 'rafa kaldırma';
            LP."Assigned Document Type"::WhseMovement:
                DocName := 'hareket';
            LP."Assigned Document Type"::ProdConsumption,
            LP."Assigned Document Type"::ProdOutput:
                DocName := 'üretim emri';
            LP."Assigned Document Type"::Assembly:
                DocName := 'montaj emri';
            else
                DocName := 'belge';
        end;
        if LP."Assigned Document No." = '' then
            exit(DocName + ' (numarasız)');
        exit(DocName + ' ' + LP."Assigned Document No.");
    end;

    local procedure FormatQty(Qty: Decimal): Text
    begin
        exit(Format(Qty, 0, '<Sign><Integer Thousand><Decimals>'));
    end;

    local procedure MaxRows(): Integer
    begin
        if not MaxRowsSet then
            exit(50);
        exit(MaxRowsPerCategory);
    end;

    local procedure Tolerance(): Decimal
    begin
        exit(0.00001);
    end;

    local procedure MaxLpLinesScanned(): Integer
    begin
        exit(100000);
    end;

    local procedure MaxGroupsCompared(): Integer
    begin
        exit(20000);
    end;

    local procedure MaxAssignedLpsScanned(): Integer
    begin
        exit(20000);
    end;

    local procedure MaxUndoEntriesScanned(): Integer
    begin
        exit(2000);
    end;

    local procedure MaxBlockedItemsScanned(): Integer
    begin
        exit(2000);
    end;

    local procedure MaxPrintJobsScanned(): Integer
    begin
        exit(1000);
    end;

    local procedure MaxMappingsScanned(): Integer
    begin
        exit(5000);
    end;

    local procedure StuckAfterMs(): BigInteger
    begin
        exit(10 * 60 * 1000);
    end;

    local procedure StalePrinterMs(): BigInteger
    begin
        exit(30 * 24 * 60 * 60 * 1000L);
    end;
}
