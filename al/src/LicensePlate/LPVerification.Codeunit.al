codeunit 72216 "DOPSWHS LP Verification"
{
    // Fiziksel palet okutmasının sunucu tarafındaki karşılığı.
    //
    // BADE saha kuralı (9 Eyl 2026): paletin üzerinde okutulabilir tek barkod
    // Madde Tanımlama Etiketi'nin LP numarası taşıyan QR kodudur. Operatör ürün
    // barkodu okutamadığı için "doğru ürünü aldım/koydum" kanıtı yalnızca
    // okutulan LP'nin İÇERİĞİNİN ambar aktivitesi satırıyla karşılaştırılmasıyla
    // üretilebilir. Bu codeunit o karşılaştırmayı tek yerde tutar; toplama
    // (Pick) ve yerleştirme (Put-away) uçları buradan geçer.
    //
    // Yönlendirilmiş hareket (Movement) modülünde çalışan ve sahada doğrulanmış
    // eşdeğer bir doğrulama zaten var ("DOPSWHS Movement Mgmt".
    // ValidateDirectedSourceLp). Yayındaki o akışı bozmamak için bu codeunit
    // ONU DEĞİŞTİRMEZ; hareketi de buraya taşımak ayrı ve bağımsız bir iştir.

    var
        LpNotFoundErr: Label '%1 LP numarası bulunamadı. Palet etiketini tekrar okutun.', Comment = '%1 = scanned LP no.';
        LpNotUsableErr: Label '%1 LP numarası bu işlem için uygun değil. Güncel durum: %2.', Comment = '%1 = LP no., %2 = status';
        LpAssignedElsewhereErr: Label '%1 LP numarası başka bir belgeye ayrılmış: %2. Bu belgede kullanılamaz.', Comment = '%1 = LP no., %2 = assigned document no.';
        LpOtherLocationErr: Label '%1 LP numarası %2 lokasyonunda kayıtlı; satır %3 lokasyonundadır.', Comment = '%1 = LP no., %2 = LP location, %3 = line location';
        LpOtherBinErr: Label 'Yanlış raf: %1 LP numarası %2 rafında kayıtlı, satır %3 rafını istiyor.', Comment = '%1 = LP no., %2 = LP bin, %3 = line bin';
        LpWrongItemErr: Label 'Yanlış LP: satır %1 maddesini istiyor, %2 LP numarasında %3 var.', Comment = '%1 = expected item, %2 = LP no., %3 = LP contents';
        LpWrongLotErr: Label 'Yanlış lot: satır %1 lotunu istiyor, %2 LP numarasında %3 var.', Comment = '%1 = expected lot, %2 = LP no., %3 = LP lots';
        LpWrongSerialErr: Label 'Yanlış seri: satır %1 serisini istiyor, %2 LP numarasında %3 var.', Comment = '%1 = expected serial, %2 = LP no., %3 = LP serials';
        LpEmptyErr: Label '%1 LP numarasının içeriği boş görünüyor. Paleti BC''de kontrol edin.', Comment = '%1 = LP no.';
        LpNotEnoughErr: Label '%1 LP numarasında %2 maddesi için yeterli miktar yok. Palette %3, istenen %4.', Comment = '%1 = LP no., %2 = item, %3 = available, %4 = requested';
        LpScanRequiredErr: Label '%1 satırında kaynak LP okutmak zorunludur. %2 rafındaki paletin QR kodunu okutun.', Comment = '%1 = line no., %2 = bin code';
        UomMissingErr: Label '%1 maddesinin %2 ölçü birimi tanımlı değil. Palet içeriği miktara çevrilemedi.', Comment = '%1 = item, %2 = uom';
        UomInvalidErr: Label '%1 maddesinin %2 ölçü birimi dönüşümü geçersizdir.', Comment = '%1 = item, %2 = uom';
        EmptyValueTxt: Label '(boş)';

    /// <summary>
    /// Kurulum kartındaki "LP Scan Required" anahtarı. Kapalıyken (varsayılan)
    /// bu paketten önceki davranış aynen sürer: kaynak LP isteğe bağlıdır.
    /// </summary>
    procedure ScanRequired(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then
            exit(false);
        exit(Setup."LP Scan Required");
    end;

    /// <summary>
    /// Zorunluluk açıkken kaynak LP'nin boş bırakılmasını reddeder.
    /// QtyToHandle sıfır/negatifse satır zaten işlenmiyor demektir; okutma
    /// istenmez (eksik bildirimi ve iptal yolları bu yüzden etkilenmez).
    /// </summary>
    procedure RequireScannedLp(WhseActivityLine: Record "Warehouse Activity Line"; ScannedLpNo: Code[20]; QtyToHandle: Decimal)
    begin
        if QtyToHandle <= 0 then
            exit;
        if ScannedLpNo <> '' then
            exit;
        if not ScanRequired() then
            exit;
        Error(LpScanRequiredErr, WhseActivityLine."Line No.", WhseActivityLine."Bin Code");
    end;

    /// <summary>
    /// Okutulan paletin gerçekten bu satırın paleti olduğunu kanıtlar ve
    /// eşleşen ilk içerik satırını döndürür. Hata durumunda operatöre
    /// gösterilecek kesin bir mesajla durur; sessizce başka palete düşmez.
    /// </summary>
    /// <param name="ExpectedLotNo">Boş bırakılırsa lot doğrulaması atlanır ve
    /// eşleşen palet satırının lotu çağırana geri verilir (palet tek lot
    /// taşıdığında lot okutmaya gerek kalmaz).</param>
    /// <param name="CheckAssignment">Toplama için true: başka bir sevkiyata
    /// ayrılmış palet toplanamaz. Yerleştirme için false: palet fiziksel olarak
    /// operatörün elindedir ve mal kabul belgesine ayrılmış olması normaldir;
    /// orada koruma madde/lot karşılaştırmasıdır.</param>
    /// <returns>Eşleşen palet satırlarının taban ölçü birimindeki toplam miktarı.</returns>
    procedure VerifyScannedLp(ScannedLpNo: Code[20]; WhseActivityLine: Record "Warehouse Activity Line"; ExpectedLotNo: Code[50]; ExpectedSerialNo: Code[50]; CheckAssignment: Boolean; var MatchedLPLine: Record "DOPSWHS LP Line") MatchedBaseQty: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Found: Boolean;
    begin
        Clear(MatchedLPLine);
        if ScannedLpNo = '' then
            Error(LpScanRequiredErr, WhseActivityLine."Line No.", WhseActivityLine."Bin Code");
        if not LP.Get(ScannedLpNo) then
            Error(LpNotFoundErr, ScannedLpNo);
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            Error(LpNotUsableErr, ScannedLpNo, Format(LP.Status));
        if CheckAssignment and (LP.Status = LP.Status::Assigned) then
            if not AssignmentMatchesLine(LP, WhseActivityLine) then
                Error(LpAssignedElsewhereErr, ScannedLpNo, LP."Assigned Document No.");
        if (LP."Location Code" <> '') and (LP."Location Code" <> WhseActivityLine."Location Code") then
            Error(LpOtherLocationErr, ScannedLpNo, LP."Location Code", WhseActivityLine."Location Code");
        // Raf karşılaştırması yalnız paletin rafı biliniyorken yapılır. Mal
        // kabulde oluşturulan palet henüz bir rafa yazılmamış olabilir; o
        // durumda rafı zorlamak doğru paleti haksız yere reddederdi.
        if (LP."Bin Code" <> '') and (WhseActivityLine."Bin Code" <> '') and
           (LP."Bin Code" <> WhseActivityLine."Bin Code")
        then
            Error(LpOtherBinErr, ScannedLpNo, LP."Bin Code", WhseActivityLine."Bin Code");

        LPLine.SetRange("LP No.", ScannedLpNo);
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.IsEmpty() then
            Error(LpEmptyErr, ScannedLpNo);

        LPLine.SetRange("Item No.", WhseActivityLine."Item No.");
        if LPLine.IsEmpty() then
            Error(
                LpWrongItemErr, WhseActivityLine."Item No.", ScannedLpNo,
                DescribeContents(ScannedLpNo, LPLine.FieldNo("Item No.")));

        LPLine.SetRange("Variant Code", WhseActivityLine."Variant Code");
        if LPLine.IsEmpty() then
            Error(
                LpWrongItemErr, WhseActivityLine."Item No.", ScannedLpNo,
                DescribeContents(ScannedLpNo, LPLine.FieldNo("Item No.")));

        if ExpectedLotNo <> '' then begin
            LPLine.SetRange("Lot No.", ExpectedLotNo);
            if LPLine.IsEmpty() then
                Error(
                    LpWrongLotErr, ExpectedLotNo, ScannedLpNo,
                    DescribeContents(ScannedLpNo, LPLine.FieldNo("Lot No.")));
        end;
        if ExpectedSerialNo <> '' then begin
            LPLine.SetRange("Serial No.", ExpectedSerialNo);
            if LPLine.IsEmpty() then
                Error(
                    LpWrongSerialErr, ExpectedSerialNo, ScannedLpNo,
                    DescribeContents(ScannedLpNo, LPLine.FieldNo("Serial No.")));
        end;

        // Satırın kendi lot/seri damgası varsa palet onunla da uyuşmalı.
        // ExpectedLotNo boş geldiğinde tek doğrulama noktası budur.
        if WhseActivityLine."Lot No." <> '' then begin
            LPLine.SetRange("Lot No.", WhseActivityLine."Lot No.");
            if LPLine.IsEmpty() then
                Error(
                    LpWrongLotErr, WhseActivityLine."Lot No.", ScannedLpNo,
                    DescribeContents(ScannedLpNo, LPLine.FieldNo("Lot No.")));
        end;
        if WhseActivityLine."Serial No." <> '' then begin
            LPLine.SetRange("Serial No.", WhseActivityLine."Serial No.");
            if LPLine.IsEmpty() then
                Error(
                    LpWrongSerialErr, WhseActivityLine."Serial No.", ScannedLpNo,
                    DescribeContents(ScannedLpNo, LPLine.FieldNo("Serial No.")));
        end;

        LPLine.FindSet();
        repeat
            if not Found then begin
                MatchedLPLine := LPLine;
                Found := true;
            end;
            MatchedBaseQty += LineBaseQuantity(LPLine);
        until LPLine.Next() = 0;
    end;

    /// <summary>
    /// Paletin bu madde/varyant için TEK bir lot taşıdığını doğrular ve o lotu
    /// döndürür. BADE'de bir palet tek madde/lot taşır; bu sayede operatörden
    /// ayrıca lot okutması istenmez. Palet birden çok lot taşıyorsa false
    /// döner ve çağıran lotu kendi yollarıyla belirlemeye devam eder.
    /// </summary>
    procedure SingleLotForItem(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; var LotNo: Code[50]): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
        Candidate: Code[50];
        Seen: Boolean;
    begin
        if (LpNo = '') or (ItemNo = '') then
            exit(false);
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit(false);
        repeat
            if not Seen then begin
                Candidate := LPLine."Lot No.";
                Seen := true;
            end else
                if LPLine."Lot No." <> Candidate then
                    exit(false);
        until LPLine.Next() = 0;
        if Candidate = '' then
            exit(false);
        LotNo := Candidate;
        exit(true);
    end;

    /// <summary>
    /// Paletin bir madde/varyant/lot için taşıdığı taban miktar. Hata
    /// fırlatmaz; aday palet listesini kurmak için kullanılır.
    /// </summary>
    procedure AvailableBaseQtyInLp(LpNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LotNo: Code[50]; SerialNo: Code[50]) BaseQty: Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if (LpNo = '') or (ItemNo = '') then
            exit(0);
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", ItemNo);
        LPLine.SetRange("Variant Code", VariantCode);
        if LotNo <> '' then
            LPLine.SetRange("Lot No.", LotNo);
        if SerialNo <> '' then
            LPLine.SetRange("Serial No.", SerialNo);
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit(0);
        repeat
            BaseQty += LineBaseQuantity(LPLine);
        until LPLine.Next() = 0;
    end;

    /// <summary>
    /// Doğrulanmış paletin bu satır için kalan miktarı karşıladığını denetler.
    /// Kısmi toplama/yerleştirme serbest; palette olmayan miktar reddedilir.
    /// </summary>
    procedure CheckRequestedQuantity(ScannedLpNo: Code[20]; ItemNo: Code[20]; AvailableQty: Decimal; RequestedBaseQty: Decimal)
    begin
        if RequestedBaseQty <= 0 then
            exit;
        if AvailableQty + QtyTolerance() < RequestedBaseQty then
            Error(LpNotEnoughErr, ScannedLpNo, ItemNo, AvailableQty, RequestedBaseQty);
    end;

    /// <summary>
    /// Palet satırının taban ölçü birimindeki miktarı. Palet satırı ürünün
    /// temel biriminden farklı bir birimde tutulabilir (koli, palet vb.).
    /// </summary>
    procedure LineBaseQuantity(LPLine: Record "DOPSWHS LP Line"): Decimal
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        QtyPerUoM: Decimal;
    begin
        if LPLine.Quantity = 0 then
            exit(0);
        if not Item.Get(LPLine."Item No.") then
            exit(LPLine.Quantity);
        QtyPerUoM := 1;
        if (LPLine."Unit of Measure" <> '') and (LPLine."Unit of Measure" <> Item."Base Unit of Measure") then begin
            if not ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") then
                Error(UomMissingErr, LPLine."Item No.", LPLine."Unit of Measure");
            QtyPerUoM := ItemUoM."Qty. per Unit of Measure";
            if QtyPerUoM <= 0 then
                Error(UomInvalidErr, LPLine."Item No.", LPLine."Unit of Measure");
        end;
        exit(Round(LPLine.Quantity * QtyPerUoM, 0.00001));
    end;

    procedure QtyTolerance(): Decimal
    begin
        exit(0.00001);
    end;

    /// <summary>
    /// Atanmış palet yalnız BU belgeye aitse kullanılabilir. Toplamada palet
    /// ya toplama belgesine ya da onun sevkiyatına ayrılmış olmalıdır.
    /// </summary>
    local procedure AssignmentMatchesLine(LP: Record "DOPSWHS LP Header"; WhseActivityLine: Record "Warehouse Activity Line"): Boolean
    begin
        if LP."Assigned Document No." = '' then
            exit(true);
        case LP."Assigned Document Type" of
            LP."Assigned Document Type"::WhsePick,
            LP."Assigned Document Type"::WhsePutaway,
            LP."Assigned Document Type"::WhseMovement:
                exit(LP."Assigned Document No." = WhseActivityLine."No.");
            LP."Assigned Document Type"::WhseShipment,
            LP."Assigned Document Type"::WhseReceipt:
                exit(LP."Assigned Document No." = WhseActivityLine."Whse. Document No.");
        end;
        exit(false);
    end;

    /// <summary>
    /// Hata mesajında paletin gerçekte ne taşıdığını yazar; operatör yanlış
    /// paleti elinde tutarken doğru paleti aramaya çıkabilsin diye.
    /// </summary>
    local procedure DescribeContents(LpNo: Code[20]; FieldNumber: Integer): Text
    var
        LPLine: Record "DOPSWHS LP Line";
        Seen: Dictionary of [Text, Boolean];
        Value: Text;
        Result: Text;
    begin
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetFilter(Quantity, '>0');
        if not LPLine.FindSet() then
            exit(EmptyValueTxt);
        repeat
            Clear(Value);
            if FieldNumber = LPLine.FieldNo("Item No.") then
                Value := LPLine."Item No."
            else
                if FieldNumber = LPLine.FieldNo("Lot No.") then
                    Value := LPLine."Lot No."
                else
                    if FieldNumber = LPLine.FieldNo("Serial No.") then
                        Value := LPLine."Serial No.";
            if Value = '' then
                Value := EmptyValueTxt;
            if not Seen.ContainsKey(Value) then begin
                Seen.Add(Value, true);
                if Result <> '' then
                    Result += ', ';
                Result += Value;
            end;
        until (LPLine.Next() = 0) or (StrLen(Result) > 120);
        if Result = '' then
            exit(EmptyValueTxt);
        exit(Result);
    end;
}
