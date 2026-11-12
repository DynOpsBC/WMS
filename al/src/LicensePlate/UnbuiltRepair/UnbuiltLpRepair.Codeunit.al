codeunit 72204 "DOPSWHS Unbuilt LP Repair"
{
    // BADE 1.14.1.186 — bozulan LP'lerin onarımı.
    //
    // Kök neden: 1.14.1.185 ve öncesinde, kısmen nakledilmiş bir ambar alış irsaliyesinin
    // kalanı BC'den silinince "CleanupCanceledReceiptLPs" o irsaliyeden gelmiş, nakledilip
    // rafa kaldırılmış LP'leri de bozuyor (satırlarını siliyor) ve stok LP'siz kalıyordu.
    //
    // Onarım: LP satırları silindiği için içerik LP hareket geçmişinden çıkarılır
    // (Item Added / Transfer In eksi Item Removed / Transfer Out; raf taşıma kayıtları
    // içerik değildir). Geçmiş her içerik değişikliğini kaydetmediğinden sonuç tek başına
    // kanıt sayılmaz. Bir LP yalnız şu koşulların hepsi tutarsa "Onarılabilir" olur:
    //  - durduğu raftaki aynı madde/lot LP'siz stoku, o raf için listelenen bozuk LP'lerin
    //    geçmişteki toplamına TAM eşittir (rafta açıklanamayan fazla ya da eksik yok);
    //  - LP'nin son raf taşıma kaydındaki toplam miktar (varsa) geçmişten çıkan içerikle aynıdır;
    //  - madde varyantsız, seri takipsiz ve tek ölçü birimlidir.
    // Aksi hâlde satır "Stok Yetersiz" / "Elle İncele" olarak listelenir ve dokunulmaz. Onarım aynı LP numarasını geri getirir (etiket
    // palette durduğu için) ve geçmişe 'REPAIR-UNBUILT-186' iziyle yazılır.
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = RIM,
        tabledata "DOPSWHS LP Movement Ledger" = RI,
        tabledata "Warehouse Entry" = R,
        tabledata "Item Ledger Entry" = R;

    var
        RepairMarkerTok: Label 'REPAIR-UNBUILT-186', Locked = true;
        EmptiedMarkerTok: Label 'EMPTIED', Locked = true;
        BinMoveMarkerTok: Label 'BIN-MOVE', Locked = true;

    /// <summary>Bozulmuş, satırsız LP'lerin geçmişten çıkarılan içeriğini ve stok karşılaştırmasını listeler. Veri değiştirmez.</summary>
    procedure Analyze(var Buffer: Record "DOPSWHS Unbuilt LP Repair Buf." temporary)
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Claimed: Dictionary of [Text, Decimal];
        NextEntryNo: Integer;
    begin
        Buffer.Reset();
        Buffer.DeleteAll();
        LP.SetRange(Status, LP.Status::Unbuilt);
        LP.SetRange("Pending Receipt No.", '');
        if LP.FindSet() then
            repeat
                LPLine.SetRange("LP No.", LP."No.");
                if LPLine.IsEmpty() then
                    AnalyzeLp(LP, Buffer, Claimed, NextEntryNo);
            until LP.Next() = 0;
        ApplyExactMatchRule(Buffer, Claimed);
    end;

    /// <summary>
    /// Raftaki LP'siz stok, o raf/madde/lot için onarılabilir görünen LP'lerin toplamından
    /// FAZLAYSA geçmişten çıkan miktar tek başına güvenilir değildir (ör. geçmişe yazılmamış bir
    /// miktar azaltması): bu LP'ler toplu onarımdan çıkarılır, yalnız elle onayla onarılabilir.
    /// </summary>
    local procedure ApplyExactMatchRule(var Buffer: Record "DOPSWHS Unbuilt LP Repair Buf." temporary; var Claimed: Dictionary of [Text, Decimal])
    var
        SurplusLps: List of [Code[20]];
        LpNo: Code[20];
        ClaimedBase: Decimal;
        StockKey: Text;
    begin
        Buffer.Reset();
        Buffer.SetRange("LP Ready", true);
        if Buffer.FindSet() then
            repeat
                StockKey := Buffer."Location Code" + '|' + Buffer."Bin Code" + '|' + Buffer."Item No." + '|' + Buffer."Lot No.";
                ClaimedBase := 0;
                if Claimed.ContainsKey(StockKey) then
                    ClaimedBase := Claimed.Get(StockKey);
                if Buffer."Loose Qty. (Base)" - ClaimedBase > 0.00001 then
                    if not SurplusLps.Contains(Buffer."LP No.") then
                        SurplusLps.Add(Buffer."LP No.");
            until Buffer.Next() = 0;
        Buffer.Reset();
        foreach LpNo in SurplusLps do begin
            Buffer.SetRange("LP No.", LpNo);
            if Buffer.FindSet() then
                repeat
                    Buffer."LP Ready" := false;
                    if Buffer.Result = Buffer.Result::Ready then begin
                        Buffer.Result := Buffer.Result::Review;
                        Buffer."Surplus Only" := true;
                        Buffer.Note := 'Rafta bu listedeki LP''lerle açıklanmayan fazla LP''siz stok var; paleti fiziksel doğrulayıp tek tek onarın.';
                    end;
                    Buffer.Modify();
                until Buffer.Next() = 0;
        end;
        Buffer.Reset();
    end;

    /// <summary>
    /// Tek LP'yi onarır. Kontroller işlem anında yeniden yapılır (liste eskimiş olabilir);
    /// koşullar tutmuyorsa hata verir ve hiçbir şey değişmez.
    /// </summary>
    procedure RepairLp(LpNo: Code[20])
    begin
        RepairLp(LpNo, false);
    end;

    /// <summary>
    /// AllowSurplusStock = true: rafta listedeki LP'lerle açıklanmayan FAZLA LP'siz stok olsa da
    /// (durum "Elle İncele", not "fazla stok") onarır; yine de stok geçmişteki miktardan az olamaz.
    /// Yalnız kullanıcı fiziksel paleti doğruladıktan sonra, tek LP için kullanılır.
    /// </summary>
    procedure RepairLp(LpNo: Code[20]; AllowSurplusStock: Boolean)
    var
        Scope: Record "DOPSWHS LP Header";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Fresh: Record "DOPSWHS Unbuilt LP Repair Buf." temporary;
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LP.LockTable();
        LP.Get(LpNo);
        if LP.Status <> LP.Status::Unbuilt then
            Error('%1 LP''si bozulmuş durumda değil (%2).', LpNo, LP.Status);
        if LP."Pending Receipt No." <> '' then
            Error('%1 LP''si %2 mal kabulünü bekliyor.', LpNo, LP."Pending Receipt No.");
        LPLine.SetRange("LP No.", LpNo);
        if not LPLine.IsEmpty() then
            Error('%1 LP''sinde satır var; onarım yalnız satırsız LP içindir.', LpNo);

        // Liste eskimiş olabilir: bütün kurallar (rafın tam eşleşmesi dahil) işlem anında,
        // güncel veriyle yeniden değerlendirilir.
        Analyze(Fresh);
        Fresh.SetRange("LP No.", LpNo);
        if not Fresh.FindSet() then
            Error('%1 LP''sinin geçmişinden onarılacak içerik çıkarılamadı.', LpNo);
        repeat
            if not (Fresh."LP Ready" and (Fresh.Result = Fresh.Result::Ready)) then
                if not (AllowSurplusStock and Fresh."Surplus Only") then
                    Error('%1 LP''si onarılamaz: %2 %3 — %4', LpNo, Fresh."Item No.", Fresh."Lot No.", Fresh.Note);
        until Fresh.Next() = 0;

        // Durum yalnız bu onarımda Unbuilt → Open yapılır; satırlar ve kapanış standart
        // LP yollarından (AddLine / Stop) geçer.
        LP.Status := LP.Status::Open;
        LP.Modify(true);
        LPMgt.WriteToLedger(LP, Enum::"DOPSWHS LP Action"::SourceLinked, LP."Bin Code", LP."Bin Code", 0, '', '', RepairMarkerTok);
        Fresh.FindSet();
        repeat
            LPMgt.AddLine(LP, Fresh."Item No.", Fresh."Unit of Measure", Fresh.Quantity, Fresh."Lot No.", '',
                ExpirationDateOf(Fresh."Item No.", Fresh."Lot No.", LP."Location Code"));
            LPLine.Reset();
            LPLine.SetRange("LP No.", LpNo);
            if LPLine.FindLast() then begin
                LPLine."Source Bin Code" := LP."Bin Code";
                LPLine.Modify(true);
            end;
        until Fresh.Next() = 0;
        LP.Get(LpNo);
        LPMgt.Stop(LP, false);
        // Satırların kaynak madde defteri bağlantısı (mal kabul geri alma vb. için) mevcut
        // "Eksik Kaynakları Toplu Bağla" kuralıyla kurulur: yalnız tek aday giriş varsa bağlar.
        Scope.SetRange("No.", LpNo);
        LPMgt.RepairMissingStockSources(Scope, true);
    end;

    local procedure AnalyzeLp(LP: Record "DOPSWHS LP Header"; var Buffer: Record "DOPSWHS Unbuilt LP Repair Buf." temporary; var Claimed: Dictionary of [Text, Decimal]; var NextEntryNo: Integer)
    var
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Item: Record Item;
        Content: Dictionary of [Text, Decimal];
        ContentKey: Text;
        Parts: List of [Text];
        ItemNo: Code[20];
        LotNo: Code[50];
        Qty: Decimal;
        LooseBase: Decimal;
        ClaimedBase: Decimal;
        UnbuiltEntryNo: Integer;
        UnbuiltAt: DateTime;
        UnbuiltBy: Code[50];
        FirstRowNo: Integer;
        LastMoveTotal: Decimal;
        ContentTotal: Decimal;
        MoveMismatch: Boolean;
        AllReady: Boolean;
        Result: Option Ready,"Insufficient Stock",Review,Repaired;
        Note: Text;
    begin
        // Son hareket "Unbuilt" olmalı; sonrasında başka hareket varsa LP'ye dokunulmaz.
        Ledger.SetRange("LP No.", LP."No.");
        if not Ledger.FindLast() then
            exit;
        if Ledger.Action <> Ledger.Action::Unbuilt then
            exit;
        UnbuiltEntryNo := Ledger."Entry No.";
        UnbuiltAt := Ledger.DateTime;
        UnbuiltBy := Ledger."User ID";

        LastMoveTotal := -1;
        Ledger.SetFilter("Entry No.", '<%1', UnbuiltEntryNo);
        if Ledger.FindSet() then
            repeat
                case Ledger.Action of
                    Ledger.Action::Unbuilt:
                        begin
                            Clear(Content);
                            LastMoveTotal := -1;
                        end;
                    Ledger.Action::ItemAdded, Ledger.Action::TransferIn:
                        if Ledger."Item No." <> '' then begin
                            AddContent(Content, Ledger."Item No.", Ledger."Lot Serial", Ledger.Quantity);
                            LastMoveTotal := -1;
                        end;
                    Ledger.Action::TransferOut:
                        // Madde no'suz Transfer Out raf taşımadır (BIN-MOVE / BIN-ASSIGN), içerik değil.
                        // BIN-MOVE o andaki LP toplamını taşır; sonrasında içerik değişmediyse
                        // geçmişten çıkan toplamla aynı olmalıdır (bağımsız doğrulama).
                        if Ledger."Item No." <> '' then begin
                            AddContent(Content, Ledger."Item No.", Ledger."Lot Serial", -Ledger.Quantity);
                            LastMoveTotal := -1;
                        end else
                            if Ledger."Related Document" = BinMoveMarkerTok then
                                LastMoveTotal := Ledger.Quantity;
                    Ledger.Action::ItemRemoved:
                        begin
                            if Ledger."Item No." <> '' then
                                AddContent(Content, Ledger."Item No.", Ledger."Lot Serial", -Ledger.Quantity)
                            else
                                if Ledger."Related Document" = EmptiedMarkerTok then
                                    Clear(Content);
                            LastMoveTotal := -1;
                        end;
                end;
            until Ledger.Next() = 0;

        foreach ContentKey in Content.Keys() do
            ContentTotal += Round(Content.Get(ContentKey), 0.00001);
        MoveMismatch := (LastMoveTotal >= 0) and (Abs(LastMoveTotal - ContentTotal) > 0.00001);

        AllReady := true;
        FirstRowNo := NextEntryNo + 1;
        foreach ContentKey in Content.Keys() do begin
            Qty := Round(Content.Get(ContentKey), 0.00001);
            if Qty <> 0 then begin
                Parts := ContentKey.Split('|');
                ItemNo := CopyStr(Parts.Get(1), 1, MaxStrLen(ItemNo));
                LotNo := CopyStr(Parts.Get(2), 1, MaxStrLen(LotNo));
                Result := Result::Ready;
                Note := '';
                LooseBase := 0;
                if MoveMismatch then begin
                    Result := Result::Review;
                    Note := StrSubstNo('Son raf taşıma kaydındaki LP toplamı %1, geçmişten çıkan içerik %2; uyuşmuyor.', LastMoveTotal, ContentTotal);
                end else
                if Qty < 0 then begin
                    Result := Result::Review;
                    Note := 'Geçmişte çıkan miktar girenden fazla; içerik güvenle çıkarılamıyor.';
                end else
                    if not Item.Get(ItemNo) then begin
                        Result := Result::Review;
                        Note := 'Madde bulunamadı.';
                    end else
                        if LP."Bin Code" = '' then begin
                            Result := Result::Review;
                            Note := 'LP''nin rafı boş.';
                        end else
                            if IsSerialTracked(Item) then begin
                                Result := Result::Review;
                                Note := 'Seri takipli madde; elle onarılmalı.';
                            end else
                                if HasAlternativeUom(Item) then begin
                                    Result := Result::Review;
                                    Note := 'Maddenin birden çok ölçü birimi var; geçmişteki miktarın birimi belirsiz.';
                                end else begin
                                    LooseBase := LooseStockBase(LP."Location Code", LP."Bin Code", ItemNo, LotNo);
                                    ClaimedBase := 0;
                                    if Claimed.ContainsKey(ClaimKey(LP, ItemNo, LotNo)) then
                                        ClaimedBase := Claimed.Get(ClaimKey(LP, ItemNo, LotNo));
                                    if LooseBase - ClaimedBase + 0.00001 < Qty then begin
                                        Result := Result::"Insufficient Stock";
                                        Note := StrSubstNo('Rafta LP''siz stok %1, bu listede önceki LP''lere ayrılan %2, gereken %3.', LooseBase, ClaimedBase, Qty);
                                    end;
                                end;
                if Result <> Result::Ready then
                    AllReady := false;

                NextEntryNo += 1;
                Buffer.Init();
                Buffer."Entry No." := NextEntryNo;
                Buffer."LP No." := LP."No.";
                Buffer."Location Code" := LP."Location Code";
                Buffer."Bin Code" := LP."Bin Code";
                Buffer."Unbuilt At" := UnbuiltAt;
                Buffer."Unbuilt By" := UnbuiltBy;
                Buffer."Unbuilt Ledger Entry No." := UnbuiltEntryNo;
                Buffer."Item No." := ItemNo;
                Buffer."Lot No." := LotNo;
                Buffer.Quantity := Qty;
                if Item."No." = ItemNo then
                    Buffer."Unit of Measure" := Item."Base Unit of Measure";
                Buffer."Loose Qty. (Base)" := LooseBase;
                Buffer.Result := Result;
                Buffer.Note := CopyStr(Note, 1, MaxStrLen(Buffer.Note));
                Buffer.Insert();
            end;
        end;
        if NextEntryNo < FirstRowNo then
            exit; // Geçmişe göre LP boşken bozulmuş: onarılacak içerik yok.

        // LP ancak bütün satırları onarılabilirse onarılır; o zaman stoku bu listede ayrılır.
        Buffer.SetRange("Entry No.", FirstRowNo, NextEntryNo);
        Buffer.ModifyAll("LP Ready", AllReady);
        if AllReady then
            if Buffer.FindSet() then
                repeat
                    ClaimedBase := 0;
                    if Claimed.ContainsKey(ClaimKey(LP, Buffer."Item No.", Buffer."Lot No.")) then
                        ClaimedBase := Claimed.Get(ClaimKey(LP, Buffer."Item No.", Buffer."Lot No."));
                    Claimed.Set(ClaimKey(LP, Buffer."Item No.", Buffer."Lot No."), ClaimedBase + Buffer.Quantity);
                until Buffer.Next() = 0;
        Buffer.SetRange("Entry No.");
    end;

    local procedure AddContent(var Content: Dictionary of [Text, Decimal]; ItemNo: Code[20]; LotSerial: Code[50]; Qty: Decimal)
    var
        ContentKey: Text;
        Existing: Decimal;
    begin
        ContentKey := ItemNo + '|' + LotSerial;
        if Content.Get(ContentKey, Existing) then
            Content.Set(ContentKey, Existing + Qty)
        else
            Content.Add(ContentKey, Qty);
    end;

    local procedure ClaimKey(LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; LotNo: Code[50]): Text
    begin
        exit(LP."Location Code" + '|' + LP."Bin Code" + '|' + ItemNo + '|' + LotNo);
    end;

    /// <summary>Raftaki madde/lot stoku eksi aynı raftaki aktif LP'lerin (Açık/Oluşturuldu/Atanmış) içeriği.</summary>
    local procedure LooseStockBase(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]): Decimal
    var
        WarehouseEntry: Record "Warehouse Entry";
        LPHeader: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Verification: Codeunit "DOPSWHS LP Verification";
        Allocated: Decimal;
    begin
        WarehouseEntry.SetRange("Location Code", LocationCode);
        WarehouseEntry.SetRange("Bin Code", BinCode);
        WarehouseEntry.SetRange("Item No.", ItemNo);
        // LP geçmişi varyant tutmaz: yalnız varyantsız stok sayılır; varyantlı stok
        // onarımı karşılamaz ("Stok Yetersiz" kalır, elle ele alınır).
        WarehouseEntry.SetRange("Variant Code", '');
        WarehouseEntry.SetRange("Lot No.", LotNo);
        WarehouseEntry.CalcSums("Qty. (Base)");

        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", '');
        LPLine.SetRange("Lot No.", LotNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                if LPHeader.Get(LPLine."LP No.") then
                    if (LPHeader."Location Code" = LocationCode) and (LPHeader."Bin Code" = BinCode) and
                       (LPHeader.Status in [LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned]) and
                       (LPHeader."Pending Receipt No." = '')
                    then
                        Allocated += Verification.LineBaseQuantity(LPLine);
            until LPLine.Next() = 0;
        exit(WarehouseEntry."Qty. (Base)" - Allocated);
    end;

    local procedure IsSerialTracked(Item: Record Item): Boolean
    var
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        if (Item."Item Tracking Code" = '') or not ItemTrackingCode.Get(Item."Item Tracking Code") then
            exit(false);
        exit(ItemTrackingCode."SN Specific Tracking" or ItemTrackingCode."SN Warehouse Tracking");
    end;

    local procedure HasAlternativeUom(Item: Record Item): Boolean
    var
        ItemUoM: Record "Item Unit of Measure";
    begin
        ItemUoM.SetRange("Item No.", Item."No.");
        ItemUoM.SetFilter(Code, '<>%1', Item."Base Unit of Measure");
        exit(not ItemUoM.IsEmpty());
    end;

    local procedure ExpirationDateOf(ItemNo: Code[20]; LotNo: Code[50]; LocationCode: Code[10]): Date
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if LotNo = '' then
            exit(0D);
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetFilter("Expiration Date", '<>%1', 0D);
        if ItemLedgerEntry.FindLast() then
            exit(ItemLedgerEntry."Expiration Date");
        ItemLedgerEntry.SetRange("Location Code");
        if ItemLedgerEntry.FindLast() then
            exit(ItemLedgerEntry."Expiration Date");
        exit(0D);
    end;
}
