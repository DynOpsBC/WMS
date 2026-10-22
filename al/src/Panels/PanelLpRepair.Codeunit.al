/// <summary>
/// Kitoko (22 Eki 2026): panellerin (Depo Sağlık, Göz/LP Karşılaştırma, LP
/// İzlenebilirlik) LP onarım/teşhis yardımcıları. BADE hattında bu yordamlar
/// LP Management içinde (1.14.1.148); Kitoko hattında çekirdek koda dokunmamak
/// için burada, aynı kurallarla tutulur. Yazan yordamlar yalnız mevcut genel LP
/// Management yordamlarını (Release, ConsumeLineForShipment,
/// RefreshItemLedgerEntryLpReferences) çağırır.
/// </summary>
codeunit 72400 "DOPSWHS Panel LP Repair"
{
    var
        LPManagement: Codeunit "DOPSWHS LP Management";

    // ------------------------------------------------------------------
    // Yetim LP ataması
    // ------------------------------------------------------------------

    /// <summary>
    /// LP "Atandı" durumunda ama atandığı belge artık yoksa true. Belge herhangi
    /// bir biçimde (açık, kayıtlı, nakledilmiş) duruyorsa ya da belge türü
    /// bilinmiyorsa yetim sayılmaz.
    /// </summary>
    procedure IsAssignmentOrphaned(LP: Record "DOPSWHS LP Header"): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredActivityHeader: Record "Registered Whse. Activity Hdr.";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        ProductionOrder: Record "Production Order";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
        DocNo: Code[20];
    begin
        if LP.Status <> LP.Status::Assigned then
            exit(false);
        if LP."Pending Receipt No." <> '' then
            exit(false);
        DocNo := LP."Assigned Document No.";
        if DocNo = '' then
            exit(true);
        case LP."Assigned Document Type" of
            LP."Assigned Document Type"::WhsePutaway:
                exit(not ActivityHeader.Get(ActivityHeader.Type::"Put-away", DocNo));
            LP."Assigned Document Type"::WhseMovement:
                exit(not ActivityHeader.Get(ActivityHeader.Type::Movement, DocNo));
            LP."Assigned Document Type"::WhsePick:
                begin
                    if ActivityHeader.Get(ActivityHeader.Type::Pick, DocNo) then
                        exit(false);
                    RegisteredActivityHeader.SetRange(Type, RegisteredActivityHeader.Type::Pick);
                    RegisteredActivityHeader.SetRange("Whse. Activity No.", DocNo);
                    exit(RegisteredActivityHeader.IsEmpty());
                end;
            LP."Assigned Document Type"::WhseReceipt:
                begin
                    if WhseReceiptHeader.Get(DocNo) or PostedWhseReceiptHeader.Get(DocNo) then
                        exit(false);
                    PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", DocNo);
                    exit(PostedWhseReceiptHeader.IsEmpty());
                end;
            LP."Assigned Document Type"::WhseShipment:
                begin
                    if WhseShipmentHeader.Get(DocNo) then
                        exit(false);
                    PostedWhseShipmentHeader.SetRange("Whse. Shipment No.", DocNo);
                    exit(PostedWhseShipmentHeader.IsEmpty());
                end;
            LP."Assigned Document Type"::ProdConsumption,
            LP."Assigned Document Type"::ProdOutput:
                begin
                    ProductionOrder.SetRange("No.", DocNo);
                    exit(ProductionOrder.IsEmpty());
                end;
            LP."Assigned Document Type"::Assembly:
                begin
                    if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then
                        exit(false);
                    PostedAssemblyHeader.SetRange("Order No.", DocNo);
                    exit(PostedAssemblyHeader.IsEmpty());
                end;
        end;
        exit(false);
    end;

    /// <summary>
    /// Scope filtrelerindeki yetim atanmış LP'leri serbest bırakır (Atandı →
    /// Oluşturuldu, LP hareket kaydıyla). ApplyRelease = false: yalnız sayar.
    /// </summary>
    procedure ReleaseOrphanAssignments(var Scope: Record "DOPSWHS LP Header"; ApplyRelease: Boolean): Integer
    var
        LP: Record "DOPSWHS LP Header";
        OrphanLP: Record "DOPSWHS LP Header";
        OrphanLpNos: List of [Code[20]];
        LpNo: Code[20];
        ReleasedCount: Integer;
    begin
        LP.CopyFilters(Scope);
        LP.SetRange(Status, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                if IsAssignmentOrphaned(LP) then
                    OrphanLpNos.Add(LP."No.");
            until LP.Next() = 0;
        if not ApplyRelease then
            exit(OrphanLpNos.Count());

        foreach LpNo in OrphanLpNos do
            if OrphanLP.Get(LpNo) then
                if IsAssignmentOrphaned(OrphanLP) then begin
                    LPManagement.Release(OrphanLP);
                    ReleasedCount += 1;
                end;
        exit(ReleasedCount);
    end;

    // ------------------------------------------------------------------
    // Geri alınmış mal kabulde dolu kalan LP
    // ------------------------------------------------------------------

    /// <summary>
    /// Geri alma kaydının orijinal mal kabul girişine kesin bağlı (Source Item
    /// Ledger Entry No.) aktif LP satırlarını, en çok geri alınan miktar kadar ve
    /// yalnız orijinal girişin kalan miktarı bağlı LP miktarından azken boşaltır.
    /// Döndürür: boşaltılan LP satırı sayısı.
    /// </summary>
    procedure RepairUndoneReceiptLps(UndoEntryNo: Integer): Integer
    begin
        exit(RunUndoneReceiptLpRepair(UndoEntryNo, true));
    end;

    /// <summary>RepairUndoneReceiptLps'in değişiklik yapmayan ön izlemesi.</summary>
    procedure PreviewUndoneReceiptLpRepair(UndoEntryNo: Integer): Integer
    begin
        exit(RunUndoneReceiptLpRepair(UndoEntryNo, false));
    end;

    /// <summary>
    /// Seçilen giriş geri alma kaydıysa onu, geri alınmış bir mal kabul
    /// kaydıysa onu geri alan düzeltme kayıtlarını listeye (tekrarsız) ekler.
    /// </summary>
    procedure CollectUndoneReceiptEntries(EntryNo: Integer; var UndoEntryNos: List of [Integer])
    var
        Entry: Record "Item Ledger Entry";
        UndoEntry: Record "Item Ledger Entry";
        OriginalEntry: Record "Item Ledger Entry";
    begin
        if not Entry.Get(EntryNo) then
            exit;
        if IsUndoneReceiptEntry(Entry) then begin
            if not UndoEntryNos.Contains(Entry."Entry No.") then
                UndoEntryNos.Add(Entry."Entry No.");
            exit;
        end;
        if (Entry."Entry Type" <> Entry."Entry Type"::Purchase) or (Entry.Quantity <= 0) or Entry.Correction then
            exit;
        UndoEntry.SetRange("Document No.", Entry."Document No.");
        UndoEntry.SetRange("Document Type", UndoEntry."Document Type"::"Purchase Receipt");
        UndoEntry.SetRange("Entry Type", UndoEntry."Entry Type"::Purchase);
        UndoEntry.SetRange("Item No.", Entry."Item No.");
        UndoEntry.SetRange("Variant Code", Entry."Variant Code");
        UndoEntry.SetRange("Lot No.", Entry."Lot No.");
        UndoEntry.SetRange("Serial No.", Entry."Serial No.");
        UndoEntry.SetRange(Correction, true);
        UndoEntry.SetFilter(Quantity, '<0');
        UndoEntry.SetFilter("Entry No.", '>%1', Entry."Entry No.");
        if UndoEntry.FindSet() then
            repeat
                if FindUndoneReceiptOriginalEntry(UndoEntry, OriginalEntry) then
                    if (OriginalEntry."Entry No." = Entry."Entry No.") and not UndoEntryNos.Contains(UndoEntry."Entry No.") then
                        UndoEntryNos.Add(UndoEntry."Entry No.");
            until UndoEntry.Next() = 0;
    end;

    local procedure RunUndoneReceiptLpRepair(UndoEntryNo: Integer; ApplyChanges: Boolean): Integer
    var
        UndoEntry: Record "Item Ledger Entry";
        OriginalEntry: Record "Item Ledger Entry";
        LPLine: Record "DOPSWHS LP Line";
        Verification: Codeunit "DOPSWHS LP Verification";
        UndoneLpNo: Code[20];
        UndoneLpNos: Text[250];
        ExcessQty: Decimal;
        RepairQty: Decimal;
        LineCount: Integer;
    begin
        if not UndoEntry.Get(UndoEntryNo) then
            exit(0);
        if not IsUndoneReceiptEntry(UndoEntry) then
            exit(0);
        if not FindUndoneReceiptOriginalEntry(UndoEntry, OriginalEntry) then
            exit(0);
        FilterUndoneReceiptLpLines(LPLine, OriginalEntry);
        LPLine.SetRange("Source Item Ledger Entry No.", OriginalEntry."Entry No.");
        ExcessQty := ActiveUndoLpBaseQuantity(LPLine) - OriginalEntry."Remaining Quantity";
        RepairQty := -UndoEntry.Quantity;
        if ExcessQty < RepairQty then
            RepairQty := ExcessQty;
        if RepairQty <= Verification.QtyTolerance() then
            exit(0);
        if ApplyChanges then begin
            LPManagement.RefreshItemLedgerEntryLpReferences(OriginalEntry."Entry No.", false);
            OriginalEntry.Get(OriginalEntry."Entry No.");
            UndoneLpNo := OriginalEntry."DOPSWHS LP No.";
            UndoneLpNos := OriginalEntry."DOPSWHS LP Nos.";
        end;
        LineCount := DebitUndoneReceiptLpLines(LPLine, UndoEntry."Entry No.", RepairQty, ApplyChanges);
        if ApplyChanges and (LineCount > 0) then begin
            LPManagement.RefreshItemLedgerEntryLpReferences(OriginalEntry."Entry No.", false);
            UndoEntry.Get(UndoEntry."Entry No.");
            if (UndoEntry."DOPSWHS LP No." <> UndoneLpNo) or (UndoEntry."DOPSWHS LP Nos." <> UndoneLpNos) then begin
                UndoEntry."DOPSWHS LP No." := UndoneLpNo;
                UndoEntry."DOPSWHS LP Nos." := UndoneLpNos;
                UndoEntry.Modify(false);
            end;
        end;
        exit(LineCount);
    end;

    /// <summary>Geri alma kaydı: negatif, düzeltme işaretli Alış İrsaliyesi girişi.</summary>
    procedure IsUndoneReceiptEntry(Entry: Record "Item Ledger Entry"): Boolean
    begin
        exit(
            (Entry."Entry Type" = Entry."Entry Type"::Purchase) and (Entry.Quantity < 0) and
            (Entry."Document Type" = Entry."Document Type"::"Purchase Receipt") and Entry.Correction);
    end;

    local procedure FindUndoneReceiptOriginalEntry(UndoEntry: Record "Item Ledger Entry"; var OriginalEntry: Record "Item Ledger Entry"): Boolean
    var
        Candidate: Record "Item Ledger Entry";
    begin
        if IsUndoneReceiptOriginal(UndoEntry, UndoEntry."Applies-to Entry", OriginalEntry) then
            exit(true);
        if UndoEntry."Document No." = '' then
            exit(false);
        Candidate.SetRange("Document No.", UndoEntry."Document No.");
        Candidate.SetRange("Document Type", Candidate."Document Type"::"Purchase Receipt");
        Candidate.SetRange("Entry Type", Candidate."Entry Type"::Purchase);
        Candidate.SetRange("Item No.", UndoEntry."Item No.");
        Candidate.SetRange("Variant Code", UndoEntry."Variant Code");
        Candidate.SetRange("Lot No.", UndoEntry."Lot No.");
        Candidate.SetRange("Serial No.", UndoEntry."Serial No.");
        Candidate.SetRange("Location Code", UndoEntry."Location Code");
        Candidate.SetRange(Quantity, -UndoEntry.Quantity);
        Candidate.SetRange(Correction, false);
        Candidate.SetFilter("Entry No.", '<%1', UndoEntry."Entry No.");
        if not Candidate.FindLast() then
            exit(false);
        OriginalEntry := Candidate;
        exit(true);
    end;

    local procedure IsUndoneReceiptOriginal(UndoEntry: Record "Item Ledger Entry"; EntryNo: Integer; var OriginalEntry: Record "Item Ledger Entry"): Boolean
    begin
        if (EntryNo = 0) or (EntryNo = UndoEntry."Entry No.") then
            exit(false);
        if not OriginalEntry.Get(EntryNo) then
            exit(false);
        exit(
            (OriginalEntry."Entry Type" = OriginalEntry."Entry Type"::Purchase) and (OriginalEntry.Quantity > 0) and
            (OriginalEntry."Item No." = UndoEntry."Item No.") and (OriginalEntry."Variant Code" = UndoEntry."Variant Code") and
            (OriginalEntry."Lot No." = UndoEntry."Lot No.") and (OriginalEntry."Serial No." = UndoEntry."Serial No."));
    end;

    local procedure DebitUndoneReceiptLpLines(var LPLine: Record "DOPSWHS LP Line"; UndoEntryNo: Integer; UndoneQty: Decimal; ApplyChanges: Boolean) DebitedLines: Integer
    var
        LP: Record "DOPSWHS LP Header";
        Verification: Codeunit "DOPSWHS LP Verification";
        Reference: Code[40];
        Remaining: Decimal;
        Take: Decimal;
    begin
        Remaining := UndoneQty;
        if Remaining <= Verification.QtyTolerance() then
            exit(0);
        if not LPLine.FindSet() then
            exit(0);
        repeat
            if LP.Get(LPLine."LP No.") and (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) and
               UndoLineUnitKnown(LPLine)
            then begin
                Reference := CopyStr(StrSubstNo('UNDO-RCPT:%1:%2', UndoEntryNo, LPLine."Line No."), 1, MaxStrLen(Reference));
                if not UndoReceiptLineDebited(LPLine."LP No.", Reference) then begin
                    Take := Verification.LineBaseQuantity(LPLine);
                    if Take > Remaining then
                        Take := Remaining;
                    if Take > Verification.QtyTolerance() then begin
                        if ApplyChanges then
                            LPManagement.ConsumeLineForShipment(LPLine."LP No.", LPLine."Line No.", Take, Reference);
                        DebitedLines += 1;
                        Remaining -= Take;
                    end;
                end;
            end;
        until (LPLine.Next() = 0) or (Remaining <= Verification.QtyTolerance());
    end;

    local procedure ActiveUndoLpBaseQuantity(var LPLine: Record "DOPSWHS LP Line") Total: Decimal
    var
        LP: Record "DOPSWHS LP Header";
        Verification: Codeunit "DOPSWHS LP Verification";
    begin
        if LPLine.FindSet() then
            repeat
                if LP.Get(LPLine."LP No.") and (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) and
                   UndoLineUnitKnown(LPLine)
                then
                    Total += Verification.LineBaseQuantity(LPLine);
            until LPLine.Next() = 0;
    end;

    local procedure UndoReceiptLineDebited(LpNo: Code[20]; Reference: Code[40]): Boolean
    var
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
    begin
        MovementLedger.SetRange("LP No.", LpNo);
        MovementLedger.SetRange(Action, MovementLedger.Action::ItemRemoved);
        MovementLedger.SetRange("Related Document", Reference);
        exit(not MovementLedger.IsEmpty());
    end;

    local procedure FilterUndoneReceiptLpLines(var LPLine: Record "DOPSWHS LP Line"; ItemLedgerEntry: Record "Item Ledger Entry")
    begin
        LPLine.Reset();
        LPLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        LPLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        if ItemLedgerEntry."Lot No." <> '' then
            LPLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
        if ItemLedgerEntry."Serial No." <> '' then
            LPLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        LPLine.SetFilter(Quantity, '>0');
    end;

    local procedure UndoLineUnitKnown(LPLine: Record "DOPSWHS LP Line"): Boolean
    var
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
    begin
        if not Item.Get(LPLine."Item No.") then
            exit(false);
        if (LPLine."Unit of Measure" = '') or (LPLine."Unit of Measure" = Item."Base Unit of Measure") then
            exit(true);
        exit(ItemUoM.Get(LPLine."Item No.", LPLine."Unit of Measure") and (ItemUoM."Qty. per Unit of Measure" > 0));
    end;
}
