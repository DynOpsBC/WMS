codeunit 72402 "DOPSWHS Bin LP Index"
{
    Permissions = tabledata "Bin Content" = rim;

    // Bin Contents is based on Bin Content, so an LP item without a matching
    // record cannot appear in its main grid. Add only the missing bin/item/UOM
    // definition; warehouse quantity still comes solely from Warehouse Entries.
    procedure EnsureLPItemRows(LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            exit;
        if (LP."Location Code" = '') or (LP."Bin Code" = '') then
            exit;
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                EnsureLPItemRow(LP, LPLine);
            until LPLine.Next() = 0;
    end;

    // One-time backfill for production-assigned LPs and BADE's A.URETIM bin.
    // Some older production pallets were moved there while remaining Built.
    // No Warehouse Entries are changed.
    procedure EnsureProductionAssignedRows()
    var
        LP: Record "DOPSWHS LP Header";
    begin
        LP.SetRange(Status, LP.Status::Assigned);
        LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::ProdConsumption);
        if LP.FindSet() then
            repeat
                EnsureLPItemRows(LP);
            until LP.Next() = 0;
        LP.Reset();
        LP.SetRange("Bin Code", 'A.URETIM');
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                EnsureLPItemRows(LP);
            until LP.Next() = 0;
    end;

    procedure EnsureBinItemRows(LocationCode: Code[10]; BinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if (LocationCode = '') or (BinCode = '') then
            exit;
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                EnsureLPItemRows(LP);
            until LP.Next() = 0;
    end;

    local procedure EnsureLPItemRow(LP: Record "DOPSWHS LP Header"; LPLine: Record "DOPSWHS LP Line")
    var
        BinContent: Record "Bin Content";
    begin
        if (LPLine."Item No." = '') or (LPLine.Quantity <= 0) then
            exit;
        if not (LP.Status in [LP.Status::Open, LP.Status::Built, LP.Status::Assigned]) then
            exit;
        if (LP."Location Code" = '') or (LP."Bin Code" = '') then
            exit;
        // Preserve the exact UOM: a blank-UOM aggregate is hidden by the
        // operator's ADET filter and cannot stand in for the LP item row.
        if BinContent.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
            LPLine."Variant Code", LPLine."Unit of Measure") then
            exit;
        BinContent.Init();
        BinContent.Validate("Location Code", LP."Location Code");
        BinContent.Validate("Bin Code", LP."Bin Code");
        BinContent.SetUpNewLine();
        BinContent.Validate("Item No.", LPLine."Item No.");
        BinContent.Validate("Variant Code", LPLine."Variant Code");
        BinContent.Validate("Unit of Measure Code", LPLine."Unit of Measure");
        if not BinContent.Insert(true) then
            BinContent.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                LPLine."Variant Code", LPLine."Unit of Measure");
        RefreshBinContent(BinContent);
    end;

    // The Bin Contents column must be a stored table field for BC's native
    // column sorting and filtering. Keep its value in the LP transaction.
    [EventSubscriber(ObjectType::Table, Database::"DOPSWHS LP Header", 'OnAfterInsertEvent', '', false, false)]
    local procedure AfterLPHeaderInsert(var Rec: Record "DOPSWHS LP Header"; RunTrigger: Boolean)
    begin
        if IsProductionVisible(Rec) then
            EnsureLPItemRows(Rec);
        RefreshHeader(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"DOPSWHS LP Header", 'OnAfterModifyEvent', '', false, false)]
    local procedure AfterLPHeaderModify(var Rec: Record "DOPSWHS LP Header"; var xRec: Record "DOPSWHS LP Header"; RunTrigger: Boolean)
    begin
        if (Rec."Location Code" = xRec."Location Code") and
           (Rec."Bin Code" = xRec."Bin Code") and (Rec.Status = xRec.Status) and
           (Rec."Assigned Document Type" = xRec."Assigned Document Type") and
           (Rec."Assigned Document No." = xRec."Assigned Document No.") then
            exit;
        RefreshHeader(xRec);
        if IsProductionVisible(Rec) then
            EnsureLPItemRows(Rec);
        RefreshHeader(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"DOPSWHS LP Line", 'OnAfterInsertEvent', '', false, false)]
    local procedure AfterLPLineInsert(var Rec: Record "DOPSWHS LP Line"; RunTrigger: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if LP.Get(Rec."LP No.") and IsProductionVisible(LP) then
            EnsureLPItemRow(LP, Rec);
        RefreshLine(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"DOPSWHS LP Line", 'OnAfterModifyEvent', '', false, false)]
    local procedure AfterLPLineModify(var Rec: Record "DOPSWHS LP Line"; var xRec: Record "DOPSWHS LP Line"; RunTrigger: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if (Rec."LP No." = xRec."LP No.") and
           (Rec."Item No." = xRec."Item No.") and
           (Rec."Variant Code" = xRec."Variant Code") and
           (Rec."Unit of Measure" = xRec."Unit of Measure") and
           (Rec.Quantity = xRec.Quantity) then
            exit;
        RefreshLine(xRec);
        if LP.Get(Rec."LP No.") and IsProductionVisible(LP) then
            EnsureLPItemRow(LP, Rec);
        RefreshLine(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"DOPSWHS LP Line", 'OnAfterDeleteEvent', '', false, false)]
    local procedure AfterLPLineDelete(var Rec: Record "DOPSWHS LP Line"; RunTrigger: Boolean)
    begin
        RefreshLine(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Bin Content", 'OnAfterInsertEvent', '', false, false)]
    local procedure AfterBinContentInsert(var Rec: Record "Bin Content"; RunTrigger: Boolean)
    begin
        RefreshBinContent(Rec);
    end;

    procedure RebuildCurrentLPNos()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        BinContent: Record "Bin Content";
        Seen: Dictionary of [Text, Boolean];
        BinKey: Text;
    begin
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetFilter("Item No.", '<>%1', '');
                LPLine.SetFilter(Quantity, '>0');
                if LPLine.FindSet() then
                    repeat
                        if BinContent.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                            LPLine."Variant Code", LPLine."Unit of Measure") then begin
                            BinKey := Format(BinContent.RecordId());
                            if not Seen.ContainsKey(BinKey) then begin
                                Seen.Add(BinKey, true);
                                RefreshBinContent(BinContent);
                            end;
                        end;
                        if LPLine."Unit of Measure" <> '' then
                            if BinContent.Get(LP."Location Code", LP."Bin Code", LPLine."Item No.",
                                LPLine."Variant Code", '') then begin
                                BinKey := Format(BinContent.RecordId());
                                if not Seen.ContainsKey(BinKey) then begin
                                    Seen.Add(BinKey, true);
                                    RefreshBinContent(BinContent);
                                end;
                            end;
                    until LPLine.Next() = 0;
            until LP.Next() = 0;
    end;

    local procedure RefreshHeader(LP: Record "DOPSWHS LP Header")
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then
            repeat
                RefreshBinLine(LP."Location Code", LP."Bin Code", LPLine);
            until LPLine.Next() = 0;
    end;

    local procedure RefreshLine(LPLine: Record "DOPSWHS LP Line")
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if (LPLine."Item No." <> '') and LP.Get(LPLine."LP No.") then
            RefreshBinLine(LP."Location Code", LP."Bin Code", LPLine);
    end;

    local procedure RefreshBinLine(LocationCode: Code[10]; BinCode: Code[20]; LPLine: Record "DOPSWHS LP Line")
    var
        BinContent: Record "Bin Content";
    begin
        if BinContent.Get(LocationCode, BinCode, LPLine."Item No.",
            LPLine."Variant Code", LPLine."Unit of Measure") then
            RefreshBinContent(BinContent);
        // A blank UOM on Bin Content is treated as an aggregate by the
        // existing LP summary; refresh that row when a specific UOM changes.
        if LPLine."Unit of Measure" <> '' then
            if BinContent.Get(LocationCode, BinCode, LPLine."Item No.",
                LPLine."Variant Code", '') then
                RefreshBinContent(BinContent);
    end;

    local procedure RefreshBinContent(var BinContent: Record "Bin Content")
    var
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
        LPNos: Text[250];
        LPQuantity: Decimal;
    begin
        BinContentSubscriber.GetActiveLPItemInfo(
            BinContent."Location Code", BinContent."Bin Code", BinContent."Item No.",
            BinContent."Variant Code", BinContent."Unit of Measure Code", LPNos, LPQuantity);
        if BinContent."DOPSWHS Current LP Nos" = LPNos then
            exit;
        BinContent."DOPSWHS Current LP Nos" := LPNos;
        BinContent.Modify(false);
    end;

    local procedure IsProductionAssigned(LP: Record "DOPSWHS LP Header"): Boolean
    begin
        exit((LP.Status = LP.Status::Assigned) and
             (LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption));
    end;

    local procedure IsProductionVisible(LP: Record "DOPSWHS LP Header"): Boolean
    begin
        exit(IsProductionAssigned(LP) or (LP."Bin Code" = 'A.URETIM'));
    end;
}
