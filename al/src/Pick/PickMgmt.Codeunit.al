codeunit 72046 "DOPSWHS Pick Mgmt"
{
    Access = Public;

    procedure AssignToMe(var Pick: Record "Warehouse Activity Header")
    begin
        EnsurePick(Pick);
        // Bkz. ReassignPick: WMS operatörü Warehouse Employee olmayabilir; ilişki
        // doğrulamasını tetiklemeden doğrudan yaz ki atama kalıcı olsun.
        Pick."Assigned User ID" := CopyStr(UserId(), 1, MaxStrLen(Pick."Assigned User ID"));
        Pick.Modify(true);
        Log('Pick.AssignToMe', Pick."No.");
    end;

    procedure StartShippingLP(var Pick: Record "Warehouse Activity Header"; TemplateCode: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        EffectiveTemplateCode: Code[20];
    begin
        EnsurePick(Pick);
        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        LPMgt.Build(EffectiveTemplateCode, Pick."Location Code", '', LP);
        Log('Pick.StartShippingLP', Pick."No.");
        exit(LP."No.");
    end;

    procedure StopShippingLP(var Pick: Record "Warehouse Activity Header"; LpNo: Code[20]; PrintLabel: Boolean): Code[18]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        EnsurePick(Pick);
        LP.Get(LpNo);
        LPMgt.Stop(LP, PrintLabel);
        Log('Pick.StopShippingLP', Pick."No.");
        exit(LP.SSCC);
    end;

    procedure RegisterShortPick(var PickLine: Record "Warehouse Activity Line"; ShortQty: Decimal; ReasonCode: Code[20])
    var
        Reason: Record "DOPSWHS Short Pick Reason";
    begin
        if ShortQty < 0 then
            Error('Short quantity cannot be negative.');
        if ReasonCode <> '' then
            Reason.Get(ReasonCode);

        PickLine.Validate("Qty. to Handle", ShortQty);
        PickLine.Modify(true);
        Log('Pick.Short.' + ReasonCode, PickLine."No.");
    end;

    procedure ConfirmPickLine(var PickLine: Record "Warehouse Activity Line"; QtyToHandle: Decimal; LotNo: Code[50])
    var
        CompanionLine: Record "Warehouse Activity Line";
        WhseShipmentLine: Record "Warehouse Shipment Line";
    begin
        if PickLine."Activity Type" <> PickLine."Activity Type"::Pick then
            Error('Warehouse activity %1 must be a Pick.', PickLine."No.");

        PickLine.Validate("Qty. to Handle", QtyToHandle);
        PickLine.Validate("Lot No.", LotNo);
        PickLine.Modify(true);

        // Directed pick'te aynı sevkiyat satırına bağlı Take ve Place satırları
        // aynı lotu taşımalıdır. Terminal tek satır gösterir; BC tarafında eş
        // satırları burada senkronlarız ki Register "Lot No. must have a value"
        // hatası vermesin.
        CompanionLine.SetRange("Activity Type", PickLine."Activity Type");
        CompanionLine.SetRange("No.", PickLine."No.");
        CompanionLine.SetRange("Whse. Document Type", PickLine."Whse. Document Type");
        CompanionLine.SetRange("Whse. Document No.", PickLine."Whse. Document No.");
        CompanionLine.SetRange("Whse. Document Line No.", PickLine."Whse. Document Line No.");
        CompanionLine.SetRange("Item No.", PickLine."Item No.");
        CompanionLine.SetRange("Variant Code", PickLine."Variant Code");
        CompanionLine.SetFilter("Line No.", '<>%1', PickLine."Line No.");
        if CompanionLine.FindSet(true) then
            repeat
                CompanionLine.Validate("Qty. to Handle", QtyToHandle);
                CompanionLine.Validate("Lot No.", LotNo);
                CompanionLine.Modify(true);
            until CompanionLine.Next() = 0;

        // Pick'te girilen lot bağlı Warehouse Shipment satırında da görünür.
        if (PickLine."Whse. Document Type" = PickLine."Whse. Document Type"::Shipment) and
           WhseShipmentLine.Get(PickLine."Whse. Document No.", PickLine."Whse. Document Line No.")
        then begin
            WhseShipmentLine."DOPSWHS Lot No." := LotNo;
            WhseShipmentLine.Modify(true);
        end;
    end;

    procedure RegisterPick(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
        PickingHeader: Record "DOPSWHS Picking Order Header";
        PickNo: Code[20];
        // QM (BC 28) devre dışı — bkz. QualityMgmtBridge.Codeunit.al
        // QualityBridge: Codeunit "DOPSWHS Quality Mgmt Bridge";
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
    begin
        EnsurePick(Pick);
        PickNo := Pick."No.";
        Log('Pick.Register', Pick."No.");
        if Pick."DOPSWHS Pick Mode" = Pick."DOPSWHS Pick Mode"::Multi then
            EnsureAllMultiPickLinesScanned(Pick);

        // Microsoft Quality Management block guard — QM (BC 28) devre dışı.
        // BC 28'e geçince aşağıdaki bloğun yorumunu kaldırın. Register if any
        // pick line carries a Lot/Serial currently under an open inspection.
        // Error format matches BCWMSApp.QcErrorParser so the mobile/web UI
        // renders a friendly "🔬 QC BLOCK" banner.
        // PickLine.SetRange("Activity Type", Pick.Type);
        // PickLine.SetRange("No.", Pick."No.");
        // if PickLine.FindSet() then
        //     repeat
        //         QualityBridge.VerifyNotBlocked(
        //             PickLine."Lot No.",
        //             PickLine."Serial No.",
        //             '');
        //     until PickLine.Next() = 0;

        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindFirst() then begin
            PreparePackingOrders(Pick);
            WhseActivityRegister.Run(PickLine);
            PickingHeader.SetRange("Warehouse Pick No.", PickNo);
            if PickingHeader.FindSet(true) then
                repeat
                    PickingHeader.Status := PickingHeader.Status::Completed;
                    PickingHeader."Completed DateTime" := CurrentDateTime();
                    PickingHeader.Modify(true);
                until PickingHeader.Next() = 0;
        end;
    end;

    local procedure EnsureAllMultiPickLinesScanned(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        if PickLine.FindSet() then
            repeat
                if PickLine."Qty. to Handle" < PickLine.Quantity then
                    Error('Complete all items before posting. Bin %1, item %2 still has %3 remaining.',
                        PickLine."Bin Code", PickLine."Item No.", PickLine.Quantity - PickLine."Qty. to Handle");
            until PickLine.Next() = 0;
    end;

    local procedure PreparePackingOrders(var Pick: Record "Warehouse Activity Header")
    var
        PickLine: Record "Warehouse Activity Line";
        Handled: Dictionary of [Code[20], Boolean];
    begin
        // ELOG: register'dan ÖNCE, pick'teki her satış siparişi için paketleme
        // kaydı (DOPSWHS Packing Order) hazırlanır. Eskiden Action Type=Take +
        // Source Type=Sales Line filtreleniyordu; ancak Whse.-Shipment-Create-Pick
        // ile üretilen satırlarda bu alanlar beklenenden farklı olabildiği için
        // paketleme kuyruğu BOŞ kalıyordu. Artık tüm pick satırlarını dolaşıp
        // Source No.'yu doğrudan satış siparişi olarak deniyoruz (tekilleştirilmiş).
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindSet() then
            repeat
                if (PickLine."Source No." <> '') and (not Handled.ContainsKey(PickLine."Source No.")) then begin
                    Handled.Add(PickLine."Source No.", true);
                    UpsertPackingOrder(Pick, PickLine);
                end;
            until PickLine.Next() = 0;
    end;

    // Bir satış siparişi için paketleme kaydını oluşturur/günceller (Ready).
    // Source No. bir satış siparişi değilse sessizce atlar.
    local procedure UpsertPackingOrder(var Pick: Record "Warehouse Activity Header"; var PickLine: Record "Warehouse Activity Line")
    var
        PackingOrder: Record "DOPSWHS Packing Order";
        SalesHeader: Record "Sales Header";
        PackingOrderExists: Boolean;
    begin
        if not SalesHeader.Get(SalesHeader."Document Type"::Order, PickLine."Source No.") then
            exit;

        PackingOrderExists := PackingOrder.Get(PickLine."Source No.");
        if PackingOrderExists then begin
            if PackingOrder.Status = PackingOrder.Status::"In Progress" then
                Error('Sales order %1 is already being packed.', PickLine."Source No.");
            PackingOrder.Status := PackingOrder.Status::Ready;
            PackingOrder."Session Entry No." := 0;
        end else begin
            PackingOrder.Init();
            PackingOrder."Sales Order No." := PickLine."Source No.";
        end;
        PackingOrder."Pick No." := Pick."No.";
        PackingOrder."Warehouse Shipment No." := PickLine."Whse. Document No.";
        PackingOrder."Location Code" := Pick."Location Code";
        PackingOrder."Customer No." := SalesHeader."Sell-to Customer No.";
        PackingOrder."Customer Name" := SalesHeader."Sell-to Customer Name";
        PackingOrder."Ready DateTime" := CurrentDateTime();
        if PackingOrderExists then
            PackingOrder.Modify(true)
        else
            PackingOrder.Insert(true);
    end;

    procedure ReassignPick(var Pick: Record "Warehouse Activity Header"; NewUserId: Code[50]; Reason: Text[250])
    var
        History: Record "DOPSWHS Pick Reassign Hist";
        WebhookMgmt: Codeunit "DOPSWHS Webhook Mgmt";
        FromUserId: Code[50];
    begin
        EnsurePick(Pick);
        if NewUserId = '' then
            Error('New user is required.');

        FromUserId := Pick."Assigned User ID";
        // "Assigned User ID" TableRelation'ı Warehouse Employee'dir. WMS operatörü
        // (ör. DYNOPS) her zaman bir Warehouse Employee olmayabilir; Validate bu
        // durumda değeri reddedip alanı boş bırakabiliyordu. Atamanın her koşulda
        // kalıcı olması için ilişki doğrulamasını tetiklemeden doğrudan yazılır.
        Pick."Assigned User ID" := CopyStr(NewUserId, 1, MaxStrLen(Pick."Assigned User ID"));
        Pick.Modify(true);

        History.Init();
        History."Pick No." := Pick."No.";
        History."From User" := FromUserId;
        History."To User" := NewUserId;
        History."Reassigned By" := CopyStr(UserId(), 1, MaxStrLen(History."Reassigned By"));
        History.DateTime := CurrentDateTime();
        History.Reason := Reason;
        History.Insert(true);

        WebhookMgmt.OnPickReassigned(Pick."No.", FromUserId, NewUserId);
        Log('Pick.Reassign', Pick."No.");
    end;

    // ELOG saha ziyareti: toplama sırasında sipariş başına tote (sepet) bağlama.
    // Terminal ürün okutunca satırın kaynak siparişi için atanmış tote'u sorar;
    // yoksa okutulan yeni tote'u bu siparişe bağlar. Aynı tote aynı pick içinde
    // birden çok siparişe hizmet edebilir (bulk/batch); farklı bir pick'in
    // kapatılmamış tote'u yeniden bağlanamaz.
    procedure AssignTote(var Pick: Record "Warehouse Activity Header"; SourceOrderNo: Code[20]; LpNo: Code[20])
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
        OtherAssignment: Record "DOPSWHS Pick Tote Assignment";
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        EnsurePick(Pick);
        if SourceOrderNo = '' then
            Error(SourceOrderRequiredErr);
        LP.Get(LpNo);

        OtherAssignment.SetRange("LP No.", LpNo);
        OtherAssignment.SetRange(Packed, false);
        OtherAssignment.SetFilter("Pick No.", '<>%1', Pick."No.");
        if not OtherAssignment.IsEmpty() then
            Error(ToteBusyErr, LpNo);

        if Assignment.Get(Pick."No.", SourceOrderNo) then begin
            Assignment."LP No." := LpNo;
            Assignment.Packed := false;
            Assignment."Assigned By User" := CopyStr(UserId(), 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Modify(true);
        end else begin
            Assignment.Init();
            Assignment."Pick No." := Pick."No.";
            Assignment."Source Order No." := SourceOrderNo;
            Assignment."LP No." := LpNo;
            Assignment."Location Code" := Pick."Location Code";
            Assignment."Assigned By User" := CopyStr(UserId(), 1, MaxStrLen(Assignment."Assigned By User"));
            Assignment."Assigned DateTime" := CurrentDateTime();
            Assignment.Insert(true);
        end;

        // LP yaşam döngüsü: Built tote pick'e Assigned olur (Release paketlemede).
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhsePick, Pick."No.");

        Log('Pick.AssignTote', Pick."No.");
    end;

    procedure GetToteForOrder(PickNo: Code[20]; SourceOrderNo: Code[20]): Code[20]
    var
        Assignment: Record "DOPSWHS Pick Tote Assignment";
    begin
        if Assignment.Get(PickNo, SourceOrderNo) then
            exit(Assignment."LP No.");
        exit('');
    end;

    local procedure EnsurePick(var Pick: Record "Warehouse Activity Header")
    begin
        if Pick.Type <> Pick.Type::Pick then
            Error('Warehouse activity %1 must be a Pick.', Pick."No.");
    end;

    local procedure Log(Category: Text; DocNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, DocNo);
    end;

    var
        SourceOrderRequiredErr: Label 'Source order no. is required to assign a tote.';
        ToteBusyErr: Label 'Tote %1 is still in use by another pick. Complete or release it first.', Comment = '%1 = LP No.';
}
