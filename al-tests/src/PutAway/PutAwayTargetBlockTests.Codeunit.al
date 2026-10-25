/// <summary>
/// BADE (25 Eki 2026): yerleştirme hedefi olamayacak gözler (bloke / mal kabul /
/// sevk / düzeltme) için neden kodu ve Türkçe mesaj. Terminal bu kodu bins API'sinden
/// okur; setPlacement aynı kuralla sunucuda reddeder.
/// </summary>
codeunit 72164 "DOPSWHS PutAway Target Tests"
{
    Subtype = Test;

    [Test]
    procedure NormalBinIsAllowed()
    var
        Bin: Record Bin;
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
        Assert: Codeunit "Library Assert";
    begin
        SeedLocation();
        SeedBin(Bin, 'PTB.NORMAL', '');
        Assert.AreEqual('', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Normal bin is a valid put-away target.');
        Assert.AreEqual('', DirectedPutAway.PutAwayTargetBlockMessage(Bin), 'No message for a valid bin.');
    end;

    [Test]
    procedure BlockedSpecialAndTypedBinsAreRefused()
    var
        Bin: Record Bin;
        BinType: Record "Bin Type";
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
        Assert: Codeunit "Library Assert";
    begin
        SeedLocation();

        SeedBin(Bin, 'PTB.BLOCK', '');
        Bin."Block Movement" := Bin."Block Movement"::Inbound;
        Bin.Modify();
        Assert.AreEqual('blocked', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Inbound-blocked bin.');
        Assert.IsTrue(StrPos(DirectedPutAway.PutAwayTargetBlockMessage(Bin), 'yerleştirmeye kapalı') > 0, 'Turkish message for blocked.');
        Bin."Block Movement" := Bin."Block Movement"::Outbound;
        Bin.Modify();
        Assert.AreEqual('', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Outbound block does not stop put-away.');

        SeedBin(Bin, 'PTB.RECV', '');
        Assert.AreEqual('receive', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Location receipt bin.');
        SeedBin(Bin, 'PTB.SHIP', '');
        Assert.AreEqual('ship', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Location shipment bin.');
        SeedBin(Bin, 'PTB.ADJ', '');
        Assert.AreEqual('adjustment', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Location adjustment bin.');

        if not BinType.Get('PTBRECV') then begin
            BinType.Init();
            BinType.Code := 'PTBRECV';
            BinType.Receive := true;
            BinType.Insert();
        end;
        SeedBin(Bin, 'PTB.TYPED', 'PTBRECV');
        Assert.AreEqual('receive', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Receive-only bin type.');
        BinType."Put Away" := true;
        BinType.Modify();
        Assert.AreEqual('', DirectedPutAway.PutAwayTargetBlockReason(Bin), 'Receive + put-away bin type is allowed.');
    end;

    local procedure SeedLocation()
    var
        Location: Record Location;
    begin
        if not Location.Get('PTB-LOC') then begin
            Location.Init();
            Location.Code := 'PTB-LOC';
            Location."Bin Mandatory" := true;
            Location.Insert();
        end;
        Location."Receipt Bin Code" := 'PTB.RECV';
        Location."Shipment Bin Code" := 'PTB.SHIP';
        Location."Adjustment Bin Code" := 'PTB.ADJ';
        Location.Modify();
    end;

    local procedure SeedBin(var Bin: Record Bin; BinCode: Code[20]; BinTypeCode: Code[10])
    begin
        if not Bin.Get('PTB-LOC', BinCode) then begin
            Bin.Init();
            Bin."Location Code" := 'PTB-LOC';
            Bin.Code := BinCode;
            Bin.Insert();
        end;
        Bin."Bin Type Code" := BinTypeCode;
        Bin."Block Movement" := Bin."Block Movement"::" ";
        Bin.Modify();
    end;
}
