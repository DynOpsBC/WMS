codeunit 72141 "DOPSWHS LP Label Tests"
{
    Subtype = Test;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ProductionAndReceiptLabelsKeepTheirOwnTitleAndSource()
    var
        Item: Record Item;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        SourceDoc: Code[50];
        Count: Integer;
        Rows: Text;
        Zpl: Text;
    begin
        Item.Init();
        Item."No." := 'TEST-OUTPUT-LABEL';
        Item.Description := 'Output label test';
        Item.Insert();
        Rows := '[{"itemNo":"TEST-OUTPUT-LABEL","lotNo":"LOT-01","quantityText":"12,5 KG","receiptNo":"UR001","dateText":"18.11.2026","copies":2}]';
        Zpl := Dispatcher.BuildDocumentItemLabels(Rows, 'ÜRETİM', Count, SourceDoc);
        Assert.AreEqual(2, Count, 'Requested copies must be preserved.');
        Assert.AreEqual('UR001', SourceDoc, 'The print job references the production order.');
        Assert.IsTrue(StrPos(Zpl, 'ÜRETİM') > 0, 'Production title.');
        Assert.IsTrue(StrPos(Zpl, 'LOT-01') > 0, 'Produced lot is printed.');
        Assert.IsTrue(StrPos(Zpl, '12,5 KG') > 0, 'Base quantity and unit are printed.');
        Zpl := Dispatcher.BuildReceiptItemLabels(Rows, Count, SourceDoc);
        Assert.AreEqual(2, Count, 'Receipt copies remain unchanged.');
        Assert.IsTrue(StrPos(Zpl, 'MAL KABUL') > 0, 'Receipt title remains unchanged.');
        Assert.IsFalse(StrPos(Zpl, 'ÜRETİM') > 0, 'Receipt must not gain a production title.');
        asserterror Dispatcher.BuildDocumentItemLabels('[]', 'ÜRETİM', Count, SourceDoc);
    end;

    [Test]
    procedure LabelContainsScannableLpQr()
    var
        LP: Record "DOPSWHS LP Header" temporary;
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        LP.Init();
        LP."No." := 'LP00042';
        LP.SSCC := '123456789012345675';

        Zpl := LabelReport.BuildZpl(LP);

        Assert.IsTrue(StrPos(Zpl, '^BQN,2,6') > 0, 'LP label must contain a Zebra QR command.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,LP00042^FS') > 0, 'QR payload must contain the exact LP number.');
        Assert.IsTrue(StrPos(Zpl, '^FD123456789012345675^FS') > 0, 'Linear barcode must keep the SSCC value.');
    end;

    [Test]
    procedure OpenLpWithoutSsccStillPrintsQr()
    var
        LP: Record "DOPSWHS LP Header" temporary;
        LabelReport: Report "DOPSWHS LP Label";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        LP.Init();
        LP."No." := 'LP00043';

        Zpl := LabelReport.BuildZpl(LP);

        Assert.IsTrue(StrPos(Zpl, '^FDLA,LP00043^FS') > 0, 'An open LP must be printable before SSCC generation.');
    end;

    [Test]
    procedure PalletItemLabelShowsReceiptTotalAndPalletQuantity()
    var
        LP: Record "DOPSWHS LP Header" temporary;
        LPLine: Record "DOPSWHS LP Line" temporary;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        LP.Init();
        LP."No." := 'LP00044';
        LPLine.Init();
        LPLine."LP No." := LP."No.";
        LPLine."Item No." := 'AB.01939';
        LPLine."Unit of Measure" := 'ADET';
        LPLine.Quantity := 250;
        LPLine."Lot No." := 'A100171';
        LPLine."Source Document Quantity" := 500;

#pragma warning disable AL0432
        Zpl := Dispatcher.BuildPalletItemZpl(LP, LPLine);
#pragma warning restore AL0432

        Assert.IsTrue(StrPos(Zpl, 'TOPLAM MAL KABUL: 500 ADET') > 0, 'MTE must keep the total receipt quantity.');
        Assert.IsTrue(StrPos(Zpl, 'PALET MIKTARI: 250 ADET') > 0, 'MTE must show the quantity assigned to this LP.');
        Assert.IsTrue(StrPos(Zpl, '^FDLA,LP00044^FS') > 0, 'A pallet-bound MTE QR must identify the LP.');
        Assert.IsTrue(StrPos(Zpl, 'LP: LP00044') > 0, 'MTE must visibly identify its LP.');
    end;

    [Test]
    procedure MteQrFallsBackToLotAndThenItemWithoutLp()
    var
        LP: Record "DOPSWHS LP Header" temporary;
        LPLine: Record "DOPSWHS LP Line" temporary;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Assert: Codeunit "Library Assert";
        Zpl: Text;
    begin
        LP.Init();
        LPLine.Init();
        LPLine."Item No." := 'AB.01939';
        LPLine."Lot No." := 'A100171';

#pragma warning disable AL0432
        Zpl := Dispatcher.BuildPalletItemZpl(LP, LPLine);
#pragma warning restore AL0432
        Assert.IsTrue(StrPos(Zpl, '^FDLA,A100171^FS') > 0, 'An LP-free MTE QR must identify the lot when present.');

        LPLine."Lot No." := '';
#pragma warning disable AL0432
        Zpl := Dispatcher.BuildPalletItemZpl(LP, LPLine);
#pragma warning restore AL0432
        Assert.IsTrue(StrPos(Zpl, '^FDLA,AB.01939^FS') > 0, 'An LP-free MTE QR must fall back to the item number.');
    end;

}
