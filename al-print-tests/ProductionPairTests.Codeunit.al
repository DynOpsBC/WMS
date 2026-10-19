codeunit 72187 "DOPSWHS Prod Pair Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure TwoSourceBins1200And6800ResolveTheirOwnPlace()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        InsertLine(10000, true, 1200, 'AH04.11');
        InsertLine(20000, false, 1200, 'D0.01');
        InsertLine(30000, true, 6800, 'AH03.31');
        InsertLine(40000, false, 6800, 'D0.01');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 10000);
        Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(PlaceLine."Line No." = 20000, '1200 Take resolved the wrong Place.');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 30000);
        Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(PlaceLine."Line No." = 40000, '6800 Take resolved the 1200 Place.');
    end;

    [Test]
    procedure EqualQuantityPairsNeedNotBeAdjacent()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        InsertLine(10000, true, 1200, 'RAW1');
        InsertLine(20000, true, 1200, 'RAW2');
        InsertLine(30000, false, 1200, 'D0.01');
        InsertLine(40000, false, 1200, 'D0.01');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 20000);
        Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(PlaceLine."Line No." = 40000, 'Equal Take rows reused the first Place.');
    end;

    [Test]
    procedure CombinedPlaceCanReceiveBothTakes()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        InsertLine(10000, true, 1200, 'RAW1');
        InsertLine(20000, true, 6800, 'RAW2');
        InsertLine(30000, false, 8000, 'D0.01');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 10000);
        Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(PlaceLine."Line No." = 30000, 'Combined Place was not found.');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 20000);
        Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(PlaceLine."Line No." = 30000, 'Second Take lost combined Place.');
    end;

    [Test]
    procedure OneTakeSplitAcrossPlacesIsNotGuessed()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        InsertLine(10000, true, 8000, 'RAW1');
        InsertLine(20000, false, 1200, 'D0.01');
        InsertLine(30000, false, 6800, 'D0.02');
        TakeLine.Get(TakeLine."Activity Type"::Pick, 'PAIR-TEST', 10000);
        asserterror Mgt.FindProductionPlaceLine(TakeLine, PlaceLine);
        Check(StrPos(GetLastErrorText(), 'eşleştirmesi belirsiz') > 0, GetLastErrorText());
    end;

    local procedure InsertLine(LineNo: Integer; IsTake: Boolean; Qty: Decimal; BinCode: Code[20])
    var
        Line: Record "Warehouse Activity Line";
    begin
        Line."Activity Type" := Line."Activity Type"::Pick;
        Line."No." := 'PAIR-TEST';
        Line."Line No." := LineNo;
        if IsTake then
            Line."Action Type" := Line."Action Type"::Take
        else
            Line."Action Type" := Line."Action Type"::Place;
        Line."Source Type" := Database::"Prod. Order Component";
        Line."Source Subtype" := 3;
        Line."Source No." := 'RLO.B100919';
        Line."Source Line No." := 10000;
        Line."Source Subline No." := 30000;
        Line."Item No." := 'AB.00090';
        Line."Location Code" := 'MERKEZDEPO';
        Line."Bin Code" := BinCode;
        Line."Unit of Measure Code" := 'ADET';
        Line.Quantity := Qty;
        Line."Qty. (Base)" := Qty;
        Line.Insert(false);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
