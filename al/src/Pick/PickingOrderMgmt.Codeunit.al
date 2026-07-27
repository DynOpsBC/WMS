codeunit 72354 "DOPSWHS Picking Order Mgmt"
{
    Access = Public;

    procedure AddSelectedOrders(var PickingHeader: Record "DOPSWHS Picking Order Header"; var SalesHeader: Record "Sales Header")
    begin
        PickingHeader.TestField(Status, PickingHeader.Status::Open);
        if SalesHeader.FindSet() then
            repeat
                AddOrder(PickingHeader, SalesHeader);
            until SalesHeader.Next() = 0;
    end;

    procedure AddOrder(var PickingHeader: Record "DOPSWHS Picking Order Header"; SalesHeader: Record "Sales Header")
    var
        PickingLine: Record "DOPSWHS Picking Order Line";
        OtherLine: Record "DOPSWHS Picking Order Line";
        OtherHeader: Record "DOPSWHS Picking Order Header";
        SalesLine: Record "Sales Line";
        LocationCode: Code[10];
        LineCount: Integer;
        NextLineNo: Integer;
        TotalQty: Decimal;
    begin
        PickingHeader.TestField(Status, PickingHeader.Status::Open);
        SalesHeader.TestField("Document Type", SalesHeader."Document Type"::Order);

        // ELOG: zaten pick'i olan (açık veya toplanmış) sipariş yeniden gruba eklenmez.
        if SalesOrderHasOpenPick(SalesHeader."No.") then
            Error('Sales order %1 already has a warehouse pick (open or completed).', SalesHeader."No.");

        PickingLine.SetRange("Header Entry No.", PickingHeader."Entry No.");
        PickingLine.SetRange("Sales Order No.", SalesHeader."No.");
        if not PickingLine.IsEmpty() then
            exit;

        OtherLine.SetRange("Sales Order No.", SalesHeader."No.");
        if OtherLine.FindSet() then
            repeat
                if (OtherLine."Header Entry No." <> PickingHeader."Entry No.") and
                   OtherHeader.Get(OtherLine."Header Entry No.") and
                   (OtherHeader.Status <> OtherHeader.Status::Completed)
                then
                    Error('Sales order %1 is already in picking order %2.', SalesHeader."No.", OtherHeader."Entry No.");
            until OtherLine.Next() = 0;

        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.SetRange(Type, SalesLine.Type::Item);
        SalesLine.SetFilter("Outstanding Quantity", '>0');
        if SalesLine.FindSet() then
            repeat
                if LocationCode = '' then
                    LocationCode := SalesLine."Location Code";
                if SalesLine."Location Code" <> LocationCode then
                    Error('Sales order %1 contains more than one location.', SalesHeader."No.");
                LineCount += 1;
                TotalQty += SalesLine."Outstanding Quantity";
            until SalesLine.Next() = 0;
        if LineCount = 0 then
            Error('Sales order %1 has no outstanding item lines.', SalesHeader."No.");

        if PickingHeader."Location Code" = '' then begin
            PickingHeader.Validate("Location Code", LocationCode);
            PickingHeader.Modify(true);
        end else
            if PickingHeader."Location Code" <> LocationCode then
                Error('Sales order %1 belongs to location %2. This picking order uses %3.', SalesHeader."No.", LocationCode, PickingHeader."Location Code");

        PickingLine.Reset();
        PickingLine.SetRange("Header Entry No.", PickingHeader."Entry No.");
        if PickingLine.FindLast() then
            NextLineNo := PickingLine."Line No." + 10000
        else
            NextLineNo := 10000;
        PickingLine.Init();
        PickingLine."Header Entry No." := PickingHeader."Entry No.";
        PickingLine."Line No." := NextLineNo;
        PickingLine."Sales Order No." := SalesHeader."No.";
        PickingLine."Sell-to Customer No." := SalesHeader."Sell-to Customer No.";
        PickingLine."Sell-to Customer Name" := SalesHeader."Sell-to Customer Name";
        PickingLine."Location Code" := LocationCode;
        PickingLine."Shipment Date" := SalesHeader."Shipment Date";
        PickingLine."Item Line Count" := LineCount;
        PickingLine."Total Quantity" := TotalQty;
        PickingLine.Insert(true);
    end;

    // Bir satış siparişinin depo toplama (pick) durumunu döndürür.
    // 0 = Pick Yok (hiç açık warehouse pick yok, register da edilmemiş),
    // 1 = Pick Açık (register edilmemiş pick satırı mevcut),
    // 2 = Toplandı (pick register edilmiş — Registered Whse. Activity Line var).
    // NOT: Register edilince açık Warehouse Activity Line silinir; tamamlanma
    // ancak Registered Whse. Activity Line'dan anlaşılır.
    // ELOG: "Toplanacak Siparişler" ekranında sipariş satırında gösterilir.
    procedure GetSalesOrderPickStatus(SalesOrderNo: Code[20]): Integer
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        RegisteredLine: Record "Registered Whse. Activity Line";
    begin
        if SalesOrderNo = '' then
            exit(0);

        // Açık (register edilmemiş) pick satırları Warehouse Activity Line'da durur.
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Source Type", Database::"Sales Line");
        WhseActivityLine.SetRange("Source Subtype", 1); // Sales Order
        WhseActivityLine.SetRange("Source No.", SalesOrderNo);
        if not WhseActivityLine.IsEmpty() then
            exit(1);

        // Açık pick yok — register edilmiş mi diye Registered satırlara bak.
        RegisteredLine.SetRange("Activity Type", RegisteredLine."Activity Type"::Pick);
        RegisteredLine.SetRange("Source Type", Database::"Sales Line");
        RegisteredLine.SetRange("Source Subtype", 1);
        RegisteredLine.SetRange("Source No.", SalesOrderNo);
        if not RegisteredLine.IsEmpty() then
            exit(2);

        exit(0);
    end;

    // Satış siparişinin zaten bir warehouse pick'i var mı (açık VEYA register edilmiş)?
    // "Satış Siparişlerini Seç" listesini filtrelemek için kullanılır
    // (Released + pick yok → yalnızca gerçekten toplanmayı bekleyenler).
    procedure SalesOrderHasOpenPick(SalesOrderNo: Code[20]): Boolean
    begin
        exit(GetSalesOrderPickStatus(SalesOrderNo) <> 0);
    end;

    // Sales Header kümesini yalnızca "toplanabilir" siparişlere daraltır:
    // pick'i (açık VEYA register edilmiş) olan siparişler hariç tutulur.
    // ÖLÇEKLENEBİLİRLİK: 5000+ satış siparişini tek tek dolaşmak yerine, PICK
    // SATIRLARINI (sayıca az) tarayıp pick'i olan sipariş No.'larını toplarız,
    // sonra tek <>...& filtresiyle eleriz. AddOrder guard'ı yine son savunma.
    procedure FilterToPickable(var SalesHeader: Record "Sales Header")
    var
        WhseActivityLine: Record "Warehouse Activity Line";
        RegisteredLine: Record "Registered Whse. Activity Line";
        PickedOrders: Dictionary of [Code[20], Boolean];
        ExcludeFilter: Text;
        OrderNo: Code[20];
    begin
        // Açık pick satırları.
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Source Type", Database::"Sales Line");
        WhseActivityLine.SetRange("Source Subtype", 1);
        WhseActivityLine.SetLoadFields("Source No.");
        if WhseActivityLine.FindSet() then
            repeat
                if not PickedOrders.ContainsKey(WhseActivityLine."Source No.") then
                    PickedOrders.Add(WhseActivityLine."Source No.", true);
            until WhseActivityLine.Next() = 0;

        // Register edilmiş pick satırları.
        RegisteredLine.SetRange("Activity Type", RegisteredLine."Activity Type"::Pick);
        RegisteredLine.SetRange("Source Type", Database::"Sales Line");
        RegisteredLine.SetRange("Source Subtype", 1);
        RegisteredLine.SetLoadFields("Source No.");
        if RegisteredLine.FindSet() then
            repeat
                if not PickedOrders.ContainsKey(RegisteredLine."Source No.") then
                    PickedOrders.Add(RegisteredLine."Source No.", true);
            until RegisteredLine.Next() = 0;

        foreach OrderNo in PickedOrders.Keys() do begin
            if ExcludeFilter <> '' then
                ExcludeFilter += '&';
            ExcludeFilter += '<>' + OrderNo;
            // BC filtre metni sınırı (~2048). Aşarsa dur; AddOrder guard'ı kalanı yakalar.
            if StrLen(ExcludeFilter) > 1900 then
                break;
        end;

        if ExcludeFilter <> '' then
            SalesHeader.SetFilter("No.", ExcludeFilter);
    end;

    // Sales Header kümesini yalnız OPS Status = 'Pending' siparişlere daraltır.
    // "OPS Status" başka bir eklentinin alanı (field 60000, Option); derleme-zamanı
    // bağımlılığı olmasın diye RecordRef/FieldRef ile ID üzerinden erişilir ve
    // 'Pending' option üyesinin ordinal'i OptionMembers'tan çözülür. Alan yoksa
    // (o eklenti kurulu değilse) filtre atlanır — hata verilmez.
    procedure ApplyOpsPendingFilter(var SalesHeader: Record "Sales Header")
    var
        RecRef: RecordRef;
        FldRef: FieldRef;
        Members: Text;
        Ordinal: Integer;
        OpsStatusFieldNo: Integer;
    begin
        OpsStatusFieldNo := 60000;
        RecRef.GetTable(SalesHeader);
        if not RecRef.FieldExist(OpsStatusFieldNo) then
            exit;

        FldRef := RecRef.Field(OpsStatusFieldNo);
        if FldRef.Type <> FieldType::Option then
            exit;

        Members := FldRef.OptionMembers();
        Ordinal := OptionOrdinal(Members, 'Pending');
        if Ordinal < 0 then
            exit; // 'Pending' üyesi bulunamadı — filtreleme yapma (güvenli taraf).

        FldRef.SetRange(Ordinal);
        RecRef.SetTable(SalesHeader);
    end;

    // Virgülle ayrılmış OptionMembers içinde verilen üyenin sıra numarasını (0-based)
    // döndürür; yoksa -1. Boş üyeler de sayılır (BC ordinal davranışı).
    local procedure OptionOrdinal(Members: Text; Target: Text): Integer
    var
        Part: Text;
        Idx: Integer;
        Remaining: Text;
        CommaPos: Integer;
    begin
        Remaining := Members;
        Idx := 0;
        while StrLen(Remaining) >= 0 do begin
            CommaPos := StrPos(Remaining, ',');
            if CommaPos = 0 then begin
                Part := Remaining;
                if Part.Trim() = Target then
                    exit(Idx);
                exit(-1);
            end;
            Part := CopyStr(Remaining, 1, CommaPos - 1);
            if Part.Trim() = Target then
                exit(Idx);
            Remaining := CopyStr(Remaining, CommaPos + 1);
            Idx += 1;
        end;
        exit(-1);
    end;

    procedure PostPickingOrder(var PickingHeader: Record "DOPSWHS Picking Order Header"): Code[20]
    var
        PickingLine: Record "DOPSWHS Picking Order Line";
        MultiOrderPick: Codeunit "DOPSWHS Multi Order Pick";
        OrderNosCsv: Text;
        ShipmentNo: Code[20];
        PickNo: Code[20];
    begin
        PickingHeader.TestField(Status, PickingHeader.Status::Open);
        PickingHeader.TestField("Location Code");

        PickingLine.SetRange("Header Entry No.", PickingHeader."Entry No.");
        if PickingLine.FindSet() then
            repeat
                if OrderNosCsv <> '' then
                    OrderNosCsv += ',';
                OrderNosCsv += PickingLine."Sales Order No.";
            until PickingLine.Next() = 0;
        if OrderNosCsv = '' then
            Error('Select at least one sales order.');

        PickNo := MultiOrderPick.CreateGroupedPick(OrderNosCsv, PickingHeader."Assigned User ID", ShipmentNo, 'multi');
        PickingHeader."Warehouse Pick No." := PickNo;
        PickingHeader."Warehouse Shipment No." := ShipmentNo;
        PickingHeader.Status := PickingHeader.Status::"Pick Created";
        PickingHeader.Modify(true);
        exit(PickNo);
    end;
}
