/// <summary>
/// EMU/DKÇ (15 Eyl 2026): template-driven label designs, LP auto rules and
/// document linking. Pure record setup, no posting.
/// </summary>
codeunit 72498 "DOPSWHS LP Design Tests"
{
    Subtype = Test;

    [Test]
    procedure DesignFollowsContainerKindByDefault()
    var
        Template: Record "DOPSWHS LP Template";
        Builder: Codeunit "DOPSWHS LP Label Builder";
        Assert: Codeunit "Library Assert";
    begin
        Template."Label Design" := Template."Label Design"::ByContainerKind;
        Template."Container Kind" := Template."Container Kind"::Pallet;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Pallet, Builder.ResolveDesign(Template), 'Pallet kind -> pallet design');
        Template."Container Kind" := Template."Container Kind"::Carton;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Carton, Builder.ResolveDesign(Template), 'Carton kind -> carton design');
        Template."Container Kind" := Template."Container Kind"::Box;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Box, Builder.ResolveDesign(Template), 'Box kind -> box design');
        Template."Container Kind" := Template."Container Kind"::Sack;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Sack, Builder.ResolveDesign(Template), 'Sack kind -> sack design');
        Template."Container Kind" := Template."Container Kind"::Tote;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Standard, Builder.ResolveDesign(Template), 'Other kinds keep the standard label');
        Template."Label Design" := Template."Label Design"::Sack;
        Template."Container Kind" := Template."Container Kind"::Pallet;
        Assert.AreEqual(Enum::"DOPSWHS LP Label Design"::Sack, Builder.ResolveDesign(Template), 'An explicit design wins over the kind');
    end;

    [Test]
    procedure EveryDesignKeepsTheLpQrAndTitle()
    var
        LP: Record "DOPSWHS LP Header";
        Builder: Codeunit "DOPSWHS LP Label Builder";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        SeedTemplate('TST-PAL', Enum::"DOPSWHS LP Container Kind"::Pallet, true, 2);
        SeedTemplate('TST-KOLI', Enum::"DOPSWHS LP Container Kind"::Carton, false, 1);
        SeedTemplate('TST-KUTU', Enum::"DOPSWHS LP Container Kind"::Box, true, 1);
        SeedTemplate('TST-CUVAL', Enum::"DOPSWHS LP Container Kind"::Sack, false, 1);
        SeedLp(LP, 'TST-LP-PAL', 'TST-PAL');
        SeedLine(LP, 'TST-ITEM', 'LOT-1', 12);

        Zpl := Builder.BuildZpl(LP);
        Assert.IsTrue(StrPos(Zpl, '^FDPALET^FS') > 0, 'Pallet design carries the PALET band.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,TST-LP-PAL^FS') > 0, 'QR must carry the LP number.');
        Assert.IsTrue(StrPos(Zpl, 'TST-ITEM') > 0, 'Contents are listed when the template asks for them.');
        Assert.AreEqual(2, Builder.ResolveCopies(LP), 'Template copies drive the print.');

        LP."LP Template Code" := 'TST-KOLI';
        LP.Modify();
        Zpl := Builder.BuildZpl(LP);
        Assert.IsTrue(StrPos(Zpl, '^FDKOL') > 0, 'Carton design carries the KOLİ band.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,TST-LP-PAL^FS') > 0, 'Carton QR must carry the LP number.');

        LP."LP Template Code" := 'TST-KUTU';
        LP.Modify();
        Assert.IsTrue(StrPos(Builder.BuildZpl(LP), '^FDKUTU^FS') > 0, 'Box design carries the KUTU band.');

        LP."LP Template Code" := 'TST-CUVAL';
        LP.Modify();
        Zpl := Builder.BuildZpl(LP);
        Assert.IsTrue(StrPos(Zpl, 'UVAL^FS') > 0, 'Sack design carries the ÇUVAL band.');
        Assert.IsTrue(StrPos(Zpl, 'NET: 12') > 0, 'Sack design prints the net quantity.');
    end;

    [Test]
    procedure ReportDesignRoutesToTheTemplateReport()
    var
        Template: Record "DOPSWHS LP Template";
        LP: Record "DOPSWHS LP Header";
        Builder: Codeunit "DOPSWHS LP Label Builder";
        Assert: Codeunit "Library Assert";
        ReportId: Integer;
    begin
        SeedTemplate('TST-RPT', Enum::"DOPSWHS LP Container Kind"::Pallet, false, 1);
        Template.Get('TST-RPT');
        Template."Label Design" := Template."Label Design"::Report;
        Template."Label Report ID" := Report::"DOPSWHS LP QR Document";
        Template.Modify();
        SeedLp(LP, 'TST-LP-RPT', 'TST-RPT');
        Assert.IsTrue(Builder.UsesReportLayout(LP, ReportId), 'Report design must use the template report.');
        Assert.AreEqual(Report::"DOPSWHS LP QR Document", ReportId, 'Template report id is returned.');
        Template."Label Design" := Template."Label Design"::ByContainerKind;
        Template.Modify();
        Assert.IsFalse(Builder.UsesReportLayout(LP, ReportId), 'ZPL designs never route to a report.');
    end;

    [Test]
    procedure AutoRuleFallsBackToBlankLocation()
    var
        Rule: Record "DOPSWHS LP Auto Rule";
        Found: Record "DOPSWHS LP Auto Rule";
        RuleMgt: Codeunit "DOPSWHS LP Auto Rule Mgt.";
        Assert: Codeunit "Library Assert";
    begin
        Rule.DeleteAll();
        SeedTemplate('TST-RULE', Enum::"DOPSWHS LP Container Kind"::Pallet, false, 1);
        Rule.Init();
        Rule."Location Code" := '';
        Rule."Document Type" := Rule."Document Type"::WhseReceipt;
        Rule.Enabled := true;
        Rule."Create Mode" := Rule."Create Mode"::PerDocument;
        Rule."LP Template Code" := 'TST-RULE';
        Rule.Insert(true);
        Rule.Init();
        Rule."Location Code" := 'TST-LOC';
        Rule."Document Type" := Rule."Document Type"::WhseReceipt;
        Rule.Enabled := false;
        Rule."Create Mode" := Rule."Create Mode"::PerLine;
        Rule."LP Template Code" := 'TST-RULE';
        Rule.Insert(true);

        Assert.IsTrue(RuleMgt.FindRule('TST-LOC', Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Found), 'A disabled location rule falls back to the blank rule.');
        Assert.AreEqual('', Found."Location Code", 'Blank-location rule is the fallback.');
        Assert.IsTrue(RuleMgt.FindRule('OTHER', Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, Found), 'Unknown locations use the blank rule.');
        Assert.IsFalse(RuleMgt.FindRule('OTHER', Enum::"DOPSWHS Assigned Doc Type"::WhseShipment, Found), 'No shipment rule exists.');
    end;

    [Test]
    procedure AutoRuleRejectsUnsupportedDocumentTypes()
    var
        Rule: Record "DOPSWHS LP Auto Rule";
    begin
        asserterror Rule.Validate("Document Type", Rule."Document Type"::SalesOrder);
    end;

    [Test]
    procedure PullFromDocumentRequiresAnOpenLp()
    var
        LP: Record "DOPSWHS LP Header";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
    begin
        SeedTemplate('TST-PAL2', Enum::"DOPSWHS LP Container Kind"::Pallet, false, 1);
        SeedLp(LP, 'TST-LP-BUILT', 'TST-PAL2');
        LP.Status := LP.Status::Built;
        LP.Modify();
        asserterror DocumentLink.PullFromDocument(LP, Enum::"DOPSWHS Assigned Doc Type"::SalesOrder, 'SO-NONE');
    end;

    [Test]
    procedure SalesOrderSnapshotAndLinesLandOnTheLp()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        DocumentLink: Codeunit "DOPSWHS LP Document Link";
        Assert: Codeunit "Library Assert";
        Added: Integer;
    begin
        SeedTemplate('TST-PAL3', Enum::"DOPSWHS LP Container Kind"::Pallet, false, 1);
        SeedItem('TST-ITEM');
        SeedLp(LP, 'TST-LP-SO', 'TST-PAL3');

        if SalesHeader.Get(SalesHeader."Document Type"::Order, 'TST-SO-1') then
            SalesHeader.Delete(true);
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := 'TST-SO-1';
        SalesHeader."Sell-to Customer No." := 'TST-CUST';
        SalesHeader."Sell-to Customer Name" := 'Test Müşteri';
        SalesHeader."Ship-to Name" := 'Test Depo';
        SalesHeader."Ship-to City" := 'İzmir';
        SalesHeader."Shipment Method Code" := 'CIF';
        SalesHeader."External Document No." := 'PO-77';
        SalesHeader.Insert(false);
        SalesLine.Init();
        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := 'TST-SO-1';
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := 'TST-ITEM';
        SalesLine."Unit of Measure Code" := 'PCS';
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Quantity := 5;
        SalesLine."Outstanding Quantity" := 5;
        SalesLine.Insert(false);

        Added := DocumentLink.PullFromDocument(LP, Enum::"DOPSWHS Assigned Doc Type"::SalesOrder, 'TST-SO-1');
        Assert.AreEqual(1, Added, 'One untracked line is pulled.');
        LP.Get('TST-LP-SO');
        Assert.AreEqual('Test Depo', LP."Ship-to Name", 'Ship-to name is snapshotted.');
        Assert.AreEqual('CIF', LP."Shipment Method Code", 'Shipment method is snapshotted.');
        Assert.AreEqual('PO-77', LP."External Document No.", 'External document no is snapshotted.');
        Assert.AreEqual('TST-SO-1', LP."Source Document No.", 'Source document is referenced.');
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.FindFirst();
        Assert.AreEqual(5, LPLine.Quantity, 'Outstanding quantity becomes the LP line quantity.');
        Assert.AreEqual(LPLine."Source Document Type"::SalesOrder, LPLine."Source Document Type", 'Line source type is stamped.');
        Assert.AreEqual(10000, LPLine."Source Document Line No.", 'Line source line no is stamped.');

        SalesHeader.Delete(false);
        LP.Get('TST-LP-SO');
        Assert.AreEqual('Test Depo', LP."Ship-to Name", 'Snapshot survives deletion of the source document.');
    end;

    local procedure SeedTemplate(Code: Code[20]; Kind: Enum "DOPSWHS LP Container Kind"; IncludeContents: Boolean; Copies: Integer)
    var
        Template: Record "DOPSWHS LP Template";
    begin
        if Template.Get(Code) then
            Template.Delete();
        Template.Init();
        Template.Code := Code;
        Template.Description := Code;
        Template."Container Kind" := Kind;
        Template."Label Design" := Template."Label Design"::ByContainerKind;
        Template."Label Includes Contents" := IncludeContents;
        Template."Label Copies" := Copies;
        Template."Allow Mixed Items" := true;
        Template."Allow Mixed Lots" := true;
        Template.Insert();
    end;

    local procedure SeedLp(var LP: Record "DOPSWHS LP Header"; No: Code[20]; TemplateCode: Code[20])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if LP.Get(No) then begin
            LPLine.SetRange("LP No.", No);
            LPLine.DeleteAll();
            LP.Delete();
        end;
        LP.Init();
        LP."No." := No;
        LP."LP Template Code" := TemplateCode;
        LP."Location Code" := 'TST-LOC';
        LP.Status := LP.Status::Open;
        LP.Insert();
    end;

    local procedure SeedLine(var LP: Record "DOPSWHS LP Header"; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        SeedItem(ItemNo);
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine."Line No." := 10000;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Quantity := Qty;
        LPLine."Lot No." := LotNo;
        LPLine.Insert();
    end;

    local procedure SeedItem(ItemNo: Code[20])
    var
        Item: Record Item;
    begin
        if Item.Get(ItemNo) then
            exit;
        Item.Init();
        Item."No." := ItemNo;
        Item.Description := 'Test item';
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert();
    end;
}
