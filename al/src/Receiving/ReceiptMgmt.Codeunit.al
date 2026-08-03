codeunit 72043 "DOPSWHS Receipt Mgmt"
{
    Access = Public;
    Permissions =
        tabledata "Reservation Entry" = rimd,
        tabledata "Whse. Item Tracking Line" = rimd;

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
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        LpNo: Code[20];
        PostedNo: Code[20];
    begin
        Log('Receipt.Post', WhseReceiptHeader."No.", EffectiveOperator(OperatorUserId, WhseReceiptHeader."Assigned User ID"));
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        if WhseReceiptLine.FindFirst() then
            WhsePostReceipt.Run(WhseReceiptLine);

        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        if PostedWhseReceiptHeader.FindLast() then
            PostedNo := PostedWhseReceiptHeader."No.";

        LpPropagation.StampPostedReceiptHeader(WhseReceiptHeader."No.", PostedNo);
        LpPropagation.StampPostedReceiptLines(WhseReceiptHeader."No.", PostedNo);

        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        if PostedWhseReceiptLine.FindSet(true) then
            repeat
                if LpNo <> '' then
                    AssignLP(LpNo, WhseReceiptHeader."No.");
            until PostedWhseReceiptLine.Next() = 0;
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
    begin
        // LP açan operatör: belgeye atanmış kullanıcı (uç nokta ayrı kimlik taşımıyor).
        Log('Receipt.StartLP', WhseReceiptHeader."No.", WhseReceiptHeader."Assigned User ID");
        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        LPMgt.Build(EffectiveTemplateCode, WhseReceiptHeader."Location Code", '', LP);
        exit(LP."No.");
    end;

    procedure StopLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; LpNo: Code[20]; PrintLabel: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Log('Receipt.StopLP', WhseReceiptHeader."No.", WhseReceiptHeader."Assigned User ID");
        LP.Get(LpNo);
        LPMgt.Stop(LP, PrintLabel);
    end;

    /// <summary>Geriye dönük imza: operatör kimliği belgenin atamasından okunur.</summary>
    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20])
    begin
        ConfirmLine(WhseReceiptLine, QtyToReceive, LotNo, SerialNo, ExpiryDate, LicensePlateNo, BinCode, '');
    end;

    /// <summary>
    /// Satır onayı (okutma). OperatorUserId = okutmayı yapan WMS operatörü;
    /// boşsa belgeye atanmış kullanıcıya düşülür.
    /// </summary>
    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20]; OperatorUserId: Code[50])
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
        HasItemTrackingCode: Boolean;
    begin
        Log('Receipt.ConfirmLine', WhseReceiptLine."No.", EffectiveOperator(OperatorUserId, ReceiptOperator(WhseReceiptLine."No.")));
        Item.Get(WhseReceiptLine."Item No.");
        // Otomatik Lot/Seri: SADECE item lot/serial izlemeli ise ve boş bırakıldıysa üret.
        // İzlenmeyen bir item'a Item Tracking kaydı eklemek post sırasında hataya yol
        // açar, o yüzden HasTracking dışında asla lot/seri üretmiyor/yazmıyoruz.
        if Item."Item Tracking Code" <> '' then begin
            GetItemTracking(WhseReceiptLine, ExistingLotNo, ExistingSerialNo, ExistingExpiryDate);
            if LotNo = '' then
                LotNo := ExistingLotNo;
            if SerialNo = '' then
                SerialNo := ExistingSerialNo;
            if ExpiryDate = 0D then
                ExpiryDate := ExistingExpiryDate;

            HasItemTrackingCode := ItemTrackingCode.Get(Item."Item Tracking Code");
            if RequiresLotTracking(ItemTrackingCode) then begin
                if LotNo = '' then
                    LotNo := LotSerialGen.GenerateLotNo();
            end else
                LotNo := '';
            if RequiresSerialTracking(ItemTrackingCode) then begin
                if SerialNo = '' then
                    SerialNo := LotSerialGen.GenerateSerialNo();
            end else
                SerialNo := '';

            if (LotNo = '') and (SerialNo = '') and (not HasItemTrackingCode) then
                LotNo := LotSerialGen.GenerateLotNo();
        end else begin
            LotNo := '';
            SerialNo := '';
        end;
        if BinCode <> '' then
            WhseReceiptLine.Validate("Bin Code", BinCode);
        WhseReceiptLine.Validate("Qty. to Receive", QtyToReceive);
        WhseReceiptLine.Modify(true);
        // Mobilden girilen (veya otomatik üretilen) lot/seri, BC'nin Item Tracking
        // Lines mekanizmasının okuduğu Reservation Entry kayıtlarına yazılmazsa post
        // sırasında sessizce kaybolur — bu yüzden burada gerçek kalıcılığı sağlıyoruz.
        if Item."Item Tracking Code" <> '' then
            PersistItemTracking(WhseReceiptLine, LotNo, SerialNo, ExpiryDate);

        if LicensePlateNo <> '' then begin
            LP.Get(LicensePlateNo);
            LPMgt.AddLine(LP, WhseReceiptLine."Item No.", WhseReceiptLine."Unit of Measure Code", QtyToReceive, LotNo, SerialNo, ExpiryDate);

            // Stamp the Whse Receipt Header with this LP so downstream posting can carry it
            // onto Posted Whse Receipt + Item Ledger Entry. Idempotent — only first LP wins.
            if WhseReceiptHeader.Get(WhseReceiptLine."No.") then
                if WhseReceiptHeader."DOPSWHS LP No." = '' then begin
                    WhseReceiptHeader."DOPSWHS LP No." := LicensePlateNo;
                    WhseReceiptHeader.Modify(true);
                end;
        end;
    end;

    /// <summary>
    /// Warehouse Receipt Line'ın lot/seri/SKT bilgisini BC'nin Item Tracking
    /// mekanizmasına yazar. Warehouse Receipt satırında Lot No. alanı yoktur;
    /// BC'nin Item Tracking Lines ekranı kaynak Purchase Line'ın Reservation
    /// Entry kayıtlarını gösterir. Idempotent: aynı kaynak satırın önceki
    /// takip kayıtları silinip yeniden yazılır.
    /// </summary>
    local procedure PersistItemTracking(WhseReceiptLine: Record "Warehouse Receipt Line"; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date)
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
            exit;
        end;

        ReservationEntry.Reset();
        SetSourceReservationFilters(ReservationEntry, WhseReceiptLine);
        ReservationEntry.SetFilter("Serial No.", '<>%1', '');
        if ReservationEntry.FindFirst() then begin
            LotNo := ReservationEntry."Lot No.";
            SerialNo := ReservationEntry."Serial No.";
            ExpiryDate := ReservationEntry."Expiration Date";
            exit;
        end;

        WhseItemTrkgLine.SetRange("Source Type", Database::"Warehouse Receipt Line");
        WhseItemTrkgLine.SetRange("Source ID", WhseReceiptLine."No.");
        WhseItemTrkgLine.SetRange("Source Ref. No.", WhseReceiptLine."Line No.");
        if not WhseItemTrkgLine.FindFirst() then
            exit;
        LotNo := WhseItemTrkgLine."Lot No.";
        SerialNo := WhseItemTrkgLine."Serial No.";
        ExpiryDate := WhseItemTrkgLine."Expiration Date";
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

    local procedure AssignLP(LpNo: Code[20]; ReceiptNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if not LP.Get(LpNo) then
            exit;
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, ReceiptNo);
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
}
