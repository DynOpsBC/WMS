codeunit 72141 "DOPSWHS LP Label Tests"
{
    Subtype = Test;

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
}
