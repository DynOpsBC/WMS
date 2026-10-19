page 72317 "DOPSWHS Prod Pick Candidates"
{
    Caption = 'Üretim LP Onarım Adayları';
    PageType = List;
    SourceTable = "Registered Whse. Activity Line";
    SourceTableTemporary = true;
    SourceTableView = sorting("Activity Type", "No.", "Line No.");
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            group(ScanSummary)
            {
                ShowCaption = false;
                field(ScanSummaryText; ScanSummaryText)
                {
                    ApplicationArea = All;
                    Caption = 'Tarama Özeti';
                    Editable = false;
                }
            }
            repeater(Candidates)
            {
                field(MatchState; MatchStateText)
                {
                    ApplicationArea = All;
                    Caption = 'Eşleşme';
                    ToolTip = 'Kayıtlı çekmede LP varsa kesin LP izi, yoksa mevcut stok ve LP içeriğine göre olası eşleşme gösterilir.';
                }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; Caption = 'Aday LP No.'; }
                field("No."; Rec."No.") { ApplicationArea = All; Caption = 'Kayıtlı Çekme No.'; }
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
                field("Source No."; Rec."Source No.") { ApplicationArea = All; Caption = 'Üretim Emri'; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Caption = 'Kaynak Göz'; }
                field(TargetBin; TargetBinCode) { ApplicationArea = All; Caption = 'Hedef Göz'; }
                field("Qty. (Base)"; Rec."Qty. (Base)") { ApplicationArea = All; Caption = 'Toplam Miktar (Temel)'; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field(RepairPlan; RepairPlanText)
                {
                    ApplicationArea = All;
                    Caption = 'Ön İzleme';
                    ToolTip = 'Stok ve LP miktarlarının şu an izin verdiği onarım planı. Uygulamadan önce yeniden kontrol edilir.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RefreshCandidates)
            {
                ApplicationArea = All;
                Caption = 'Adayları Yeniden Tara';
                Image = Refresh;
                trigger OnAction()
                begin
                    ScanCandidates();
                    CurrPage.Update(false);
                end;
            }
            action(RepairSelected)
            {
                ApplicationArea = All;
                Caption = 'Seçili Çekmeyi Onar';
                Image = Entries;
                AccessByPermission = codeunit "DOPSWHS LP Management" = X;
                trigger OnAction()
                var
                    LPMgt: Codeunit "DOPSWHS LP Management";
                    Preview: Text;
                    ResultText: Text;
                begin
                    if Rec."LP No." = '' then
                        Error('Bu çekmeye birden fazla LP uyuyor. Kayıtlı çekmeyi ve LP hareketlerini inceleyip LP kartından elle seçin.');
                    Preview := LPMgt.RepairHistoricalProductionPickLp(Rec."LP No.", Rec."No.", Rec."Line No.", false);
                    if not Confirm(
                        'Kayıtlı çekme %1, satır %2, üretim emri %3 ve LP %4 için:\%5\Onarımı uyguluyor musunuz?',
                        false, Rec."No.", Rec."Line No.", Rec."Source No.", Rec."LP No.", Preview)
                    then
                        exit;
                    ResultText := LPMgt.RepairHistoricalProductionPickLp(Rec."LP No.", Rec."No.", Rec."Line No.", true);
                    Rec.Delete();
                    CurrPage.Update(false);
                    Message('%1\Kalan adayları güncellemek için Adayları Yeniden Tara düğmesini kullanın.', ResultText);
                end;
            }
            action(RepairAllSafe)
            {
                ApplicationArea = All;
                Caption = 'Güvenli Adayların Tümünü Onar';
                Image = Process;
                AccessByPermission = codeunit "DOPSWHS LP Management" = X;
                ToolTip = 'Kayıtlı çekme satırında LP numarası bulunan adayları tek işlemde onarır. LP numarası sonradan tahmin edilen kayıtlar elle doğrulanır. Kontrollerden biri başarısız olursa hiçbir onarım kaydedilmez.';
                trigger OnAction()
                var
                    SafeCount: Integer;
                    ReviewCount: Integer;
                begin
                    Rec.Reset();
                    if Rec.FindSet() then
                        repeat
                            if IsRecordedLpCandidate(Rec) then
                                SafeCount += 1
                            else
                                ReviewCount += 1;
                        until Rec.Next() = 0;
                    if SafeCount = 0 then begin
                        Message('Otomatik onarılabilecek kayıtlı LP adayı yok. %1 kayıt elle doğrulama gerektiriyor.', ReviewCount);
                        exit;
                    end;
                    PreviewAllSafeCandidates();
                    if not Confirm(
                        '%1 LP numarası kayıtlı çekme grubu onarılacak. %2 kayıt elle doğrulama için atlanacak. Devam edilsin mi?',
                        false, SafeCount, ReviewCount)
                    then
                        exit;
                    ApplyAllSafeCandidates();
                    ScanCandidates();
                    CurrPage.Update(false);
                    Message('%1 LP numarası kayıtlı çekme grubu onarıldı. Kalan adaylar yeniden tarandı.', SafeCount);
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        ScanCandidates();
    end;

    trigger OnAfterGetRecord()
    var
        KeyText: Text;
    begin
        KeyText := CandidateKey(Rec);
        MatchStateText := '';
        RepairPlanText := '';
        TargetBinCode := FindTargetBin(Rec);
        MatchStates.Get(KeyText, MatchStateText);
        RepairPlans.Get(KeyText, RepairPlanText);
    end;

    procedure SetLpScope(var SelectedLPs: Record "DOPSWHS LP Header")
    begin
        LpScope.CopyFilters(SelectedLPs);
    end;

    local procedure ScanCandidates()
    var
        RegisteredTake: Record "Registered Whse. Activity Line";
        LP: Record "DOPSWHS LP Header" temporary;
        ScopedLP: Record "DOPSWHS LP Header";
        SourceLPLine: Record "DOPSWHS LP Line";
        LPLine: Record "DOPSWHS LP Line" temporary;
        LPLineCheck: Record "DOPSWHS LP Line" temporary;
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
        CheckedLPs: Dictionary of [Code[20], Boolean];
        SeenGroups: Dictionary of [Text, Boolean];
        RelevantItems: Dictionary of [Code[20], Boolean];
        SourceBalanceCache: Dictionary of [Text, Decimal];
        StockCompletionCache: Dictionary of [Code[20], Boolean];
        CandidateLpNo: Code[20];
        RelevantItemNo: Code[20];
        RelatedDocument: Code[40];
        PlanText: Text;
        KeyText: Text;
        GroupKey: Text;
        CandidateCount: Integer;
        PickBaseQty: Decimal;
        ScopedLPCount: Integer;
        ScannedTakeCount: Integer;
        FoundCandidateCount: Integer;
        StartedAt: DateTime;
    begin
        StartedAt := CurrentDateTime();
        Rec.Reset();
        Rec.DeleteAll();
        Clear(MatchStates);
        Clear(RepairPlans);
        Clear(SeenGroups);
        // Read active LP contents in the selected bin once. The old scanner
        // re-read the entire item/lot LP index for every historical Take line.
        ScopedLP.CopyFilters(LpScope);
        ScopedLP.SetCurrentKey("Location Code", "Bin Code", Status);
        ScopedLP.SetFilter(Status, '%1|%2', ScopedLP.Status::Built, ScopedLP.Status::Assigned);
        if ScopedLP.FindSet() then
            repeat
                ScopedLPCount += 1;
                LP := ScopedLP;
                LP.Insert();
                SourceLPLine.Reset();
                SourceLPLine.SetRange("LP No.", ScopedLP."No.");
                SourceLPLine.SetFilter(Quantity, '>0');
                if SourceLPLine.FindSet() then
                    repeat
                        LPLine := SourceLPLine;
                        LPLine.Insert();
                        if not RelevantItems.ContainsKey(SourceLPLine."Item No.") then
                            RelevantItems.Add(SourceLPLine."Item No.", true);
                    until SourceLPLine.Next() = 0;
            until ScopedLP.Next() = 0;
        if LP.IsEmpty() then begin
            ScanSummaryText := 'Bu depo/gözde aktif LP yok; kayıtlı çekme taranmadı.';
            exit;
        end;
        LPLineCheck.Copy(LPLine, true);
        RegisteredTake.SetCurrentKey("Source Type", "Source Subtype", "Location Code", "Bin Code", "Action Type", "Item No.");
        RegisteredTake.SetRange("Activity Type", RegisteredTake."Activity Type"::Pick);
        RegisteredTake.SetRange("Action Type", RegisteredTake."Action Type"::Take);
        RegisteredTake.SetRange("Source Type", Database::"Prod. Order Component");
        RegisteredTake.SetRange("Source Subtype", Enum::"Production Order Status"::Released.AsInteger());
        RegisteredTake.SetFilter("Qty. (Base)", '>0');
        if LpScope.GetFilter("Location Code") <> '' then
            RegisteredTake.SetFilter("Location Code", LpScope.GetFilter("Location Code"));
        if LpScope.GetFilter("Bin Code") <> '' then
            RegisteredTake.SetFilter("Bin Code", LpScope.GetFilter("Bin Code"));
        foreach RelevantItemNo in RelevantItems.Keys() do begin
            RegisteredTake.SetRange("Item No.", RelevantItemNo);
            if RegisteredTake.FindSet() then
                repeat
                    ScannedTakeCount += 1;
                    GroupKey := PickGroupKey(RegisteredTake);
                    if not SeenGroups.ContainsKey(GroupKey) then begin
                        SeenGroups.Add(GroupKey, true);
                        RelatedDocument := CopyStr('PP:' + RegisteredTake."No." + ':' + Format(RegisteredTake."Line No."), 1, MaxStrLen(RelatedDocument));
                        MovementLedger.Reset();
                        MovementLedger.SetRange(Action, MovementLedger.Action::ItemRemoved);
                        MovementLedger.SetRange("Related Document", RelatedDocument);
                    end else
                        RelatedDocument := '';
                    if (RelatedDocument <> '') and MovementLedger.IsEmpty() then begin
                    CandidateCount := 0;
                    CandidateLpNo := '';
                    PlanText := '';
                    Clear(CheckedLPs);
                    if RegisteredTake."LP No." <> '' then begin
                        if LP.Get(RegisteredTake."LP No.") then begin
                            PickBaseQty := GroupBaseQuantity(RegisteredTake);
                            if CanMatchSnapshot(LP."No.", RegisteredTake, PickBaseQty, LPLineCheck, SourceBalanceCache, StockCompletionCache) then
                                if TryPreviewRepair(LP."No.", RegisteredTake."No.", RegisteredTake."Line No.", PlanText) then begin
                                    CandidateCount := 1;
                                    CandidateLpNo := LP."No.";
                                end;
                        end;
                    end else begin
                        LPLine.Reset();
                        LPLine.SetCurrentKey("Item No.");
                        LPLine.SetRange("Item No.", RegisteredTake."Item No.");
                        LPLine.SetRange("Variant Code", RegisteredTake."Variant Code");
                        LPLine.SetFilter(Quantity, '>0');
                        if RegisteredTake."Lot No." <> '' then
                            LPLine.SetRange("Lot No.", RegisteredTake."Lot No.");
                        if RegisteredTake."Serial No." <> '' then
                            LPLine.SetRange("Serial No.", RegisteredTake."Serial No.");
                        if LPLine.FindSet() then begin
                            PickBaseQty := GroupBaseQuantity(RegisteredTake);
                            repeat
                                if not CheckedLPs.ContainsKey(LPLine."LP No.") then begin
                                    CheckedLPs.Add(LPLine."LP No.", true);
                                    if LP.Get(LPLine."LP No.") then
                                        if (LP."Location Code" = RegisteredTake."Location Code") and
                                           (LP."Bin Code" = RegisteredTake."Bin Code")
                                        then
                                            if CanMatchSnapshot(LP."No.", RegisteredTake, PickBaseQty, LPLineCheck, SourceBalanceCache, StockCompletionCache) then
                                                if TryPreviewRepair(LP."No.", RegisteredTake."No.", RegisteredTake."Line No.", PlanText) then begin
                                                    CandidateCount += 1;
                                                    if CandidateCount = 1 then
                                                        CandidateLpNo := LP."No."
                                                    else
                                                        CandidateLpNo := '';
                                                end;
                                end;
                            until (LPLine.Next() = 0) or (CandidateCount > 1);
                        end;
                    end;
                    if CandidateCount > 0 then begin
                        Rec := RegisteredTake;
                        Rec."LP No." := CandidateLpNo;
                        Rec."Qty. (Base)" := PickBaseQty;
                        Rec.Insert();
                        FoundCandidateCount += 1;
                        KeyText := CandidateKey(RegisteredTake);
                        if CandidateCount > 1 then begin
                            MatchStates.Add(KeyText, 'Birden fazla LP; elle incele');
                            RepairPlans.Add(KeyText, 'Otomatik LP seçimi yapılamaz');
                        end else begin
                            if RegisteredTake."LP No." <> '' then
                                MatchStates.Add(KeyText, 'Kayıtlı çekmede LP var')
                            else
                                MatchStates.Add(KeyText, 'Olası eşleşme; belgeyi doğrula');
                            RepairPlans.Add(KeyText, PlanText);
                        end;
                    end;
                    end;
                until RegisteredTake.Next() = 0;
        end;
        Rec.Reset();
        ScanSummaryText := StrSubstNo(
            '%1 / %2: %3 aktif LP, %4 çekme satırı incelendi, %5 aday bulundu. Süre: %6.',
            LpScope.GetFilter("Location Code"), LpScope.GetFilter("Bin Code"),
            ScopedLPCount, ScannedTakeCount, FoundCandidateCount, Format(CurrentDateTime() - StartedAt));
    end;

    [TryFunction]
    local procedure TryPreviewRepair(LpNo: Code[20]; PickNo: Code[20]; LineNo: Integer; var PlanText: Text)
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PlanText := LPMgt.RepairHistoricalProductionPickLp(LpNo, PickNo, LineNo, false);
    end;

    local procedure PreviewAllSafeCandidates()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Rec.Reset();
        if Rec.FindSet() then
            repeat
                if IsRecordedLpCandidate(Rec) then
                    LPMgt.RepairHistoricalProductionPickLp(Rec."LP No.", Rec."No.", Rec."Line No.", false);
            until Rec.Next() = 0;
    end;

    [CommitBehavior(CommitBehavior::Error)]
    local procedure ApplyAllSafeCandidates()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Rec.Reset();
        if Rec.FindSet() then
            repeat
                if IsRecordedLpCandidate(Rec) then
                    LPMgt.RepairHistoricalProductionPickLp(Rec."LP No.", Rec."No.", Rec."Line No.", true);
            until Rec.Next() = 0;
    end;

    local procedure IsRecordedLpCandidate(Candidate: Record "Registered Whse. Activity Line" temporary): Boolean
    var
        RegisteredTake: Record "Registered Whse. Activity Line";
        TakeGroup: Record "Registered Whse. Activity Line";
    begin
        if Candidate."LP No." = '' then
            exit(false);
        if not RegisteredTake.Get(Candidate."Activity Type", Candidate."No.", Candidate."Line No.") then
            exit(false);
        if RegisteredTake."LP No." <> Candidate."LP No." then
            exit(false);
        // RepairHistoricalProductionPickLp debits the complete item/lot/source
        // group. Every Take in that group must name the same LP before a
        // one-click bulk repair can treat its LP identity as recorded proof.
        TakeGroup.SetRange("Activity Type", RegisteredTake."Activity Type");
        TakeGroup.SetRange("No.", RegisteredTake."No.");
        TakeGroup.SetRange("Action Type", TakeGroup."Action Type"::Take);
        TakeGroup.SetRange("Source Type", RegisteredTake."Source Type");
        TakeGroup.SetRange("Source Subtype", RegisteredTake."Source Subtype");
        TakeGroup.SetRange("Source No.", RegisteredTake."Source No.");
        TakeGroup.SetRange("Item No.", RegisteredTake."Item No.");
        TakeGroup.SetRange("Variant Code", RegisteredTake."Variant Code");
        TakeGroup.SetRange("Location Code", RegisteredTake."Location Code");
        TakeGroup.SetRange("Bin Code", RegisteredTake."Bin Code");
        TakeGroup.SetRange("Lot No.", RegisteredTake."Lot No.");
        TakeGroup.SetRange("Serial No.", RegisteredTake."Serial No.");
        TakeGroup.SetFilter("Qty. (Base)", '>0');
        TakeGroup.SetFilter("LP No.", '<>%1', Candidate."LP No.");
        exit(TakeGroup.IsEmpty());
    end;

    local procedure CandidateKey(RegisteredTake: Record "Registered Whse. Activity Line"): Text
    begin
        exit(RegisteredTake."No." + ':' + Format(RegisteredTake."Line No."));
    end;

    local procedure PickGroupKey(RegisteredTake: Record "Registered Whse. Activity Line"): Text
    var
        Parts: JsonArray;
        ResultText: Text;
    begin
        Parts.Add(RegisteredTake."No.");
        Parts.Add(RegisteredTake."Source No.");
        Parts.Add(RegisteredTake."Item No.");
        Parts.Add(RegisteredTake."Variant Code");
        Parts.Add(RegisteredTake."Location Code");
        Parts.Add(RegisteredTake."Bin Code");
        Parts.Add(RegisteredTake."Lot No.");
        Parts.Add(RegisteredTake."Serial No.");
        Parts.WriteTo(ResultText);
        exit(ResultText);
    end;

    local procedure GroupBaseQuantity(RegisteredTake: Record "Registered Whse. Activity Line"): Decimal
    var
        TakeGroup: Record "Registered Whse. Activity Line";
        QuantityBase: Decimal;
    begin
        TakeGroup.SetRange("Activity Type", RegisteredTake."Activity Type");
        TakeGroup.SetRange("No.", RegisteredTake."No.");
        TakeGroup.SetRange("Action Type", TakeGroup."Action Type"::Take);
        TakeGroup.SetRange("Source Type", RegisteredTake."Source Type");
        TakeGroup.SetRange("Source Subtype", RegisteredTake."Source Subtype");
        TakeGroup.SetRange("Source No.", RegisteredTake."Source No.");
        TakeGroup.SetRange("Item No.", RegisteredTake."Item No.");
        TakeGroup.SetRange("Variant Code", RegisteredTake."Variant Code");
        TakeGroup.SetRange("Location Code", RegisteredTake."Location Code");
        TakeGroup.SetRange("Bin Code", RegisteredTake."Bin Code");
        TakeGroup.SetRange("Lot No.", RegisteredTake."Lot No.");
        TakeGroup.SetRange("Serial No.", RegisteredTake."Serial No.");
        TakeGroup.SetFilter("Qty. (Base)", '>0');
        if TakeGroup.FindSet() then
            repeat
                QuantityBase += TakeGroup."Qty. (Base)";
            until TakeGroup.Next() = 0;
        exit(QuantityBase);
    end;

    local procedure CanMatchSnapshot(LpNo: Code[20]; RegisteredTake: Record "Registered Whse. Activity Line"; PickBaseQty: Decimal; var LPLineCheck: Record "DOPSWHS LP Line" temporary; var SourceBalanceCache: Dictionary of [Text, Decimal]; var StockCompletionCache: Dictionary of [Code[20], Boolean]): Boolean
    var
        WarehouseEntry: Record "Warehouse Entry";
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
        Verification: Codeunit "DOPSWHS LP Verification";
        SourceKeyParts: JsonArray;
        SourceKey: Text;
        LotNo: Code[50];
        SerialNo: Code[50];
        LPBaseQty: Decimal;
        SourceBaseQty: Decimal;
        FirstLine: Boolean;
        HasStockCompletion: Boolean;
    begin
        LPLineCheck.Reset();
        LPLineCheck.SetRange("LP No.", LpNo);
        LPLineCheck.SetRange("Item No.", RegisteredTake."Item No.");
        LPLineCheck.SetRange("Variant Code", RegisteredTake."Variant Code");
        LPLineCheck.SetFilter(Quantity, '>0');
        if RegisteredTake."Lot No." <> '' then
            LPLineCheck.SetRange("Lot No.", RegisteredTake."Lot No.");
        if RegisteredTake."Serial No." <> '' then
            LPLineCheck.SetRange("Serial No.", RegisteredTake."Serial No.");
        if not LPLineCheck.FindSet() then
            exit(false);
        repeat
            if not FirstLine then begin
                LotNo := LPLineCheck."Lot No.";
                SerialNo := LPLineCheck."Serial No.";
                FirstLine := true;
            end else
                if (LotNo <> LPLineCheck."Lot No.") or (SerialNo <> LPLineCheck."Serial No.") then
                    exit(false);
            LPBaseQty += Verification.LineBaseQuantity(LPLineCheck);
        until LPLineCheck.Next() = 0;
        if LPBaseQty + Verification.QtyTolerance() < PickBaseQty then
            exit(false);

        SourceKeyParts.Add(RegisteredTake."Location Code");
        SourceKeyParts.Add(RegisteredTake."Bin Code");
        SourceKeyParts.Add(RegisteredTake."Item No.");
        SourceKeyParts.Add(RegisteredTake."Variant Code");
        SourceKeyParts.Add(LotNo);
        SourceKeyParts.Add(SerialNo);
        SourceKeyParts.WriteTo(SourceKey);
        if not SourceBalanceCache.Get(SourceKey, SourceBaseQty) then begin
            WarehouseEntry.SetCurrentKey("Item No.", "Bin Code", "Location Code", "Variant Code");
            WarehouseEntry.SetRange("Location Code", RegisteredTake."Location Code");
            WarehouseEntry.SetRange("Bin Code", RegisteredTake."Bin Code");
            WarehouseEntry.SetRange("Item No.", RegisteredTake."Item No.");
            WarehouseEntry.SetRange("Variant Code", RegisteredTake."Variant Code");
            WarehouseEntry.SetRange("Lot No.", LotNo);
            WarehouseEntry.SetRange("Serial No.", SerialNo);
            WarehouseEntry.CalcSums("Qty. (Base)");
            SourceBaseQty := WarehouseEntry."Qty. (Base)";
            SourceBalanceCache.Add(SourceKey, SourceBaseQty);
        end;
        if Abs(SourceBaseQty - LPBaseQty) <= Verification.QtyTolerance() then begin
            if not StockCompletionCache.Get(LpNo, HasStockCompletion) then begin
                MovementLedger.SetRange("LP No.", LpNo);
                MovementLedger.SetRange(Action, MovementLedger.Action::Moved);
                MovementLedger.SetRange("To Bin", RegisteredTake."Bin Code");
                MovementLedger.SetFilter("Related Document", 'LP-STOK-TAMAMLA*');
                HasStockCompletion := not MovementLedger.IsEmpty();
                StockCompletionCache.Add(LpNo, HasStockCompletion);
            end;
            exit(HasStockCompletion);
        end;
        exit(Abs(SourceBaseQty + PickBaseQty - LPBaseQty) <= Verification.QtyTolerance());
    end;

    local procedure FindTargetBin(RegisteredTake: Record "Registered Whse. Activity Line"): Code[20]
    var
        RegisteredPlace: Record "Registered Whse. Activity Line";
        TargetBinCode: Code[20];
    begin
        RegisteredPlace.SetRange("Activity Type", RegisteredPlace."Activity Type"::Pick);
        RegisteredPlace.SetRange("No.", RegisteredTake."No.");
        RegisteredPlace.SetRange("Action Type", RegisteredPlace."Action Type"::Place);
        RegisteredPlace.SetRange("Source Type", RegisteredTake."Source Type");
        RegisteredPlace.SetRange("Source Subtype", RegisteredTake."Source Subtype");
        RegisteredPlace.SetRange("Source No.", RegisteredTake."Source No.");
        RegisteredPlace.SetRange("Source Line No.", RegisteredTake."Source Line No.");
        RegisteredPlace.SetRange("Source Subline No.", RegisteredTake."Source Subline No.");
        RegisteredPlace.SetRange("Item No.", RegisteredTake."Item No.");
        RegisteredPlace.SetRange("Variant Code", RegisteredTake."Variant Code");
        RegisteredPlace.SetRange("Location Code", RegisteredTake."Location Code");
        RegisteredPlace.SetRange("Lot No.", RegisteredTake."Lot No.");
        RegisteredPlace.SetRange("Serial No.", RegisteredTake."Serial No.");
        if RegisteredPlace.FindSet() then
            repeat
                if RegisteredPlace."Bin Code" <> RegisteredTake."Bin Code" then begin
                    if (TargetBinCode <> '') and (TargetBinCode <> RegisteredPlace."Bin Code") then
                        exit('');
                    TargetBinCode := RegisteredPlace."Bin Code";
                end;
            until RegisteredPlace.Next() = 0;
        exit(TargetBinCode);
    end;

    var
        LpScope: Record "DOPSWHS LP Header";
        MatchStates: Dictionary of [Text, Text];
        RepairPlans: Dictionary of [Text, Text];
        MatchStateText: Text;
        RepairPlanText: Text;
        TargetBinCode: Code[20];
        ScanSummaryText: Text;
}
