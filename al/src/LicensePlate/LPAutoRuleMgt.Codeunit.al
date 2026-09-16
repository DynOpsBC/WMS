/// <summary>
/// Rule-based automatic license plates (EMU/DKÇ, 15 Eyl 2026).
/// Creation: when the first / every line of a warehouse receipt or shipment is
/// inserted, the matching "DOPSWHS LP Auto Rule" opens an LP and stamps it on
/// the header (per document) or on the line (per line).
/// Posting: after Whse.-Post Receipt / Shipment finish, the LPs of the document
/// are filled from the posted lines when still empty, stopped (SSCC) and their
/// template label is printed. Everything after posting is best-effort: a
/// printer or rule problem never rolls back a posted document.
/// </summary>
codeunit 72238 "DOPSWHS LP Auto Rule Mgt."
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Auto Rule" = R,
        tabledata "DOPSWHS LP Header" = RM,
        tabledata "DOPSWHS LP Line" = R,
        tabledata "Warehouse Receipt Header" = RM,
        tabledata "Warehouse Receipt Line" = RM,
        tabledata "Warehouse Shipment Header" = RM,
        tabledata "Warehouse Shipment Line" = RM,
        tabledata "Posted Whse. Receipt Header" = R,
        tabledata "Posted Whse. Receipt Line" = R,
        tabledata "Posted Whse. Shipment Header" = R,
        tabledata "Posted Whse. Shipment Line" = R;

    /// <summary>Effective rule for a location and document type: exact location first, then the blank-location rule.</summary>
    procedure FindRule(LocationCode: Code[10]; DocType: Enum "DOPSWHS Assigned Doc Type"; var Rule: Record "DOPSWHS LP Auto Rule"): Boolean
    begin
        Clear(Rule);
        if (LocationCode <> '') and Rule.Get(LocationCode, DocType) and Rule.Enabled then
            exit(true);
        if Rule.Get('', DocType) and Rule.Enabled then
            exit(true);
        Clear(Rule);
        exit(false);
    end;

    // ------------------------------------------------------------------
    // Creation
    // ------------------------------------------------------------------

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Receipt Line", 'OnAfterInsertEvent', '', false, false)]
    local procedure CreateLpForReceiptLine(var Rec: Record "Warehouse Receipt Line"; RunTrigger: Boolean)
    var
        Rule: Record "DOPSWHS LP Auto Rule";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        LpNo: Code[20];
    begin
        if Rec.IsTemporary() then
            exit;
        if not FindRule(Rec."Location Code", Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Rule) then
            exit;
        case Rule."Create Mode" of
            Rule."Create Mode"::PerDocument:
                begin
                    if not WhseReceiptHeader.Get(Rec."No.") then
                        exit;
                    if WhseReceiptHeader."DOPSWHS LP No." <> '' then
                        exit;
                    LpNo := BuildRuleLp(Rule, Rec."Location Code", Rec."Bin Code", Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Rec."No.");
                    WhseReceiptHeader."DOPSWHS LP No." := LpNo;
                    WhseReceiptHeader.Modify(true);
                end;
            Rule."Create Mode"::PerLine:
                begin
                    if Rec."DOPSWHS LP No." <> '' then
                        exit;
                    Rec."DOPSWHS LP No." := BuildRuleLp(Rule, Rec."Location Code", Rec."Bin Code", Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Rec."No.");
                    Rec.Modify(false);
                end;
        end;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Shipment Line", 'OnAfterInsertEvent', '', false, false)]
    local procedure CreateLpForShipmentLine(var Rec: Record "Warehouse Shipment Line"; RunTrigger: Boolean)
    var
        Rule: Record "DOPSWHS LP Auto Rule";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        LpNo: Code[20];
    begin
        if Rec.IsTemporary() then
            exit;
        if not FindRule(Rec."Location Code", Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, Rule) then
            exit;
        case Rule."Create Mode" of
            Rule."Create Mode"::PerDocument:
                begin
                    if not WhseShipmentHeader.Get(Rec."No.") then
                        exit;
                    if WhseShipmentHeader."DOPSWHS LP No." <> '' then
                        exit;
                    LpNo := BuildRuleLp(Rule, Rec."Location Code", Rec."Bin Code", Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, Rec."No.");
                    WhseShipmentHeader."DOPSWHS LP No." := LpNo;
                    WhseShipmentHeader.Modify(true);
                end;
            Rule."Create Mode"::PerLine:
                begin
                    if Rec."LP No." <> '' then
                        exit;
                    Rec."LP No." := BuildRuleLp(Rule, Rec."Location Code", Rec."Bin Code", Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, Rec."No.");
                    Rec.Modify(false);
                end;
        end;
    end;

    local procedure BuildRuleLp(Rule: Record "DOPSWHS LP Auto Rule"; LocationCode: Code[10]; BinCode: Code[20]; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        Template: Record "DOPSWHS LP Template";
        LPMgt: Codeunit "DOPSWHS LP Management";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
    begin
        Rule.TestField("LP Template Code");
        LPMgt.Build(Rule."LP Template Code", LocationCode, BinCode, LP);
        if Template.Get(Rule."LP Template Code") then
            LP."Tare Weight kg" := Template."Default Tare Weight kg";
        LP.Modify(true);
        // Best effort: the LP keeps working without partner data.
        if not TrySnapshot(LP, DocType, DocNo) then
            ClearLastError();
        exit(LP."No.");
    end;

    [TryFunction]
    local procedure TrySnapshot(var LP: Record "DOPSWHS LP Header"; DocType: Enum "DOPSWHS Assigned Doc Type"; DocNo: Code[20])
    var
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
    begin
        DocumentLink.SnapshotFromDocument(LP, DocType, DocNo);
    end;

    // ------------------------------------------------------------------
    // Posting
    // ------------------------------------------------------------------

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", 'OnAfterCode', '', false, false)]
    local procedure CloseReceiptLpsAfterPost(var WarehouseReceiptHeader: Record "Warehouse Receipt Header"; WarehouseReceiptLine: Record "Warehouse Receipt Line"; CounterSourceDocTotal: Integer; CounterSourceDocOK: Integer)
    var
        Rule: Record "DOPSWHS LP Auto Rule";
        PostedHeader: Record "Posted Whse. Receipt Header";
        PostedLine: Record "Posted Whse. Receipt Line";
        LpNos: List of [Code[20]];
        LpNo: Code[20];
    begin
        if not FindRule(WarehouseReceiptHeader."Location Code", Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Rule) then
            exit;
        if not (Rule."Stop On Post" or Rule."Print Label On Post" or Rule."Fill From Document On Post") then
            exit;
        PostedHeader.SetRange("Whse. Receipt No.", WarehouseReceiptHeader."No.");
        if not PostedHeader.FindLast() then
            exit;

        AddLp(LpNos, WarehouseReceiptHeader."DOPSWHS LP No.");
        PostedLine.SetRange("No.", PostedHeader."No.");
        if PostedLine.FindSet() then
            repeat
                AddLp(LpNos, PostedLine."LP No.");
            until PostedLine.Next() = 0;

        foreach LpNo in LpNos do
            if not TryCloseReceiptLp(Rule, LpNo, PostedHeader."No.", WarehouseReceiptHeader."DOPSWHS LP No.") then
                LogRuleFailure('LPAutoRule.ReceiptClose', LpNo, PostedHeader."No.", GetLastErrorText());
    end;

    // Fires at the end of PostUpdateWhseDocuments: posted header/lines exist and
    // the source documents are posted, while the shipment header is still there.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Shipment", 'OnPostUpdateWhseDocumentsOnBeforeWhseShptHeaderParamModify', '', false, false)]
    local procedure CloseShipmentLpsAfterPost(var WhseShptHeaderParam: Record "Warehouse Shipment Header"; var WhseShptHeader: Record "Warehouse Shipment Header")
    var
        Rule: Record "DOPSWHS LP Auto Rule";
        PostedHeader: Record "Posted Whse. Shipment Header";
        PostedLine: Record "Posted Whse. Shipment Line";
        AssignedLP: Record "DOPSWHS LP Header";
        LpNos: List of [Code[20]];
        LpNo: Code[20];
    begin
        if not FindRule(WhseShptHeaderParam."Location Code", Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, Rule) then
            exit;
        if not (Rule."Stop On Post" or Rule."Print Label On Post" or Rule."Fill From Document On Post") then
            exit;
        PostedHeader.SetRange("Whse. Shipment No.", WhseShptHeaderParam."No.");
        if not PostedHeader.FindLast() then
            exit;

        AddLp(LpNos, WhseShptHeaderParam."DOPSWHS LP No.");
        PostedLine.SetRange("No.", PostedHeader."No.");
        if PostedLine.FindSet() then
            repeat
                AddLp(LpNos, PostedLine."LP No.");
            until PostedLine.Next() = 0;
        AssignedLP.SetRange("Assigned Document Type", AssignedLP."Assigned Document Type"::WhseShipment);
        AssignedLP.SetRange("Assigned Document No.", WhseShptHeaderParam."No.");
        if AssignedLP.FindSet() then
            repeat
                AddLp(LpNos, AssignedLP."No.");
            until AssignedLP.Next() = 0;

        foreach LpNo in LpNos do
            if not TryCloseShipmentLp(Rule, LpNo, PostedHeader."No.", WhseShptHeaderParam."DOPSWHS LP No.") then
                LogRuleFailure('LPAutoRule.ShipmentClose', LpNo, PostedHeader."No.", GetLastErrorText());
    end;

    [TryFunction]
    local procedure TryCloseReceiptLp(Rule: Record "DOPSWHS LP Auto Rule"; LpNo: Code[20]; PostedNo: Code[20]; HeaderLpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
        LpFilter: Code[20];
    begin
        if not LP.Get(LpNo) then
            exit;
        // Terminal-staged pallets are materialised and closed by Receipt Mgmt.
        if LP."Pending Receipt No." <> '' then
            exit;
        if Rule."Fill From Document On Post" and (LP.Status = LP.Status::Open) and LpIsEmpty(LP) then begin
            // Per-line LPs take their own posted line; the document LP takes the
            // posted lines that carry no LP of their own.
            LpFilter := LpNo;
            if LpNo = HeaderLpNo then
                LpFilter := '';
            DocumentLink.PullPostedWhseReceipt(LP, PostedNo, LpFilter);
            if LpFilter = '' then
                DocumentLink.PullPostedWhseReceipt(LP, PostedNo, LpNo);
            LP.Get(LpNo);
        end;
        FinishLp(Rule, LP, Enum::"DOPSWHS Assigned Doc Type"::PostedWhseReceipt, PostedNo);
    end;

    [TryFunction]
    local procedure TryCloseShipmentLp(Rule: Record "DOPSWHS LP Auto Rule"; LpNo: Code[20]; PostedNo: Code[20]; HeaderLpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
        LpFilter: Code[20];
    begin
        if not LP.Get(LpNo) then
            exit;
        if Rule."Fill From Document On Post" and (LP.Status = LP.Status::Open) and LpIsEmpty(LP) then begin
            LpFilter := LpNo;
            if LpNo = HeaderLpNo then
                LpFilter := '';
            DocumentLink.PullPostedWhseShipment(LP, PostedNo, LpFilter);
            if LpFilter = '' then
                DocumentLink.PullPostedWhseShipment(LP, PostedNo, LpNo);
            LP.Get(LpNo);
        end;
        FinishLp(Rule, LP, Enum::"DOPSWHS Assigned Doc Type"::PostedWhseShipment, PostedNo);
    end;

    /// <summary>Stop (SSCC) an open LP and print its template label according to the rule.</summary>
    local procedure FinishLp(Rule: Record "DOPSWHS LP Auto Rule"; var LP: Record "DOPSWHS LP Header"; PostedDocType: Enum "DOPSWHS Assigned Doc Type"; PostedNo: Code[20])
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Copies: Integer;
    begin
        if LP."Source Document No." = '' then
            DocumentLink.SnapshotFromDocument(LP, PostedDocType, PostedNo);
        if Rule."Stop On Post" and (LP.Status = LP.Status::Open) and not LpIsEmpty(LP) then
            LPMgt.Stop(LP, false);
        if Rule."Print Label On Post" and not LpIsEmpty(LP) then begin
            Copies := Rule."Label Copies";
            Dispatcher.PrintLPLabel(LP, Rule."Printer Code", Copies);
        end;
    end;

    local procedure LpIsEmpty(LP: Record "DOPSWHS LP Header"): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", LP."No.");
        exit(LPLine.IsEmpty());
    end;

    local procedure AddLp(var LpNos: List of [Code[20]]; LpNo: Code[20])
    begin
        if LpNo = '' then
            exit;
        if not LpNos.Contains(LpNo) then
            LpNos.Add(LpNo);
    end;

    local procedure LogRuleFailure(Category: Text; LpNo: Code[20]; PostedNo: Code[20]; ErrorText: Text)
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        ClearLastError();
        Telemetry.LogWarning(
            Category,
            CopyStr(StrSubstNo('LP %1 could not be closed/printed for posted document %2: %3', LpNo, PostedNo, ErrorText), 1, 250),
            '');
    end;
}
