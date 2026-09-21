// 72184 is in the existing standalone regression-test range (72180-72189).
codeunit 72184 "DOPSWHS Prod LP Pref Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure PreparedLpIsStampedWithoutChangingDemandOrStock()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        // The production demand can exceed one prepared pallet.
        PickLine.Quantity := 30;
        PickLine."Qty. (Base)" := 30;
        PickLine."Qty. Outstanding" := 30;
        PickLine."Qty. Outstanding (Base)" := 30;
        PickLine.Modify(false);
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        Preference.StampPickLines(PickLine."No.");
        Preference.StampPickLines(PickLine."No.");
        PickLine.Get(PickLine."Activity Type", PickLine."No.", PickLine."Line No.");
        Check(PickLine."LP No." = LP."No.", 'Prepared LP was not attached to the production Take line.');
        Check((PickLine.Quantity = 30) and (PickLine."Qty. Outstanding (Base)" = 30), 'LP preference changed standard demand.');
        Check(PickLine."Qty. to Handle" = 0, 'LP preference confirmed an unscanned movement.');
        LPLine.Get(LPLine."LP No.", LPLine."Line No.");
        Check(LPLine.Quantity = 10, 'LP preference consumed pallet stock.');
        LP.Get(LP."No.");
        Check((LP.Status = LP.Status::Built) and (LP."Bin Code" = 'SOURCE'), 'LP preference moved or consumed the pallet.');
    end;

    [Test]
    procedure ProductionStampDoesNotLeakAcrossOrdersSourcesOrStatuses()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        OtherLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        OtherLine := PickLine;
        OtherLine."Line No." := 20000;
        OtherLine."Source No." := 'OTHER-ORDER';
        OtherLine.Insert(false);
        OtherLine := PickLine;
        OtherLine."Line No." := 30000;
        OtherLine."Source Type" := Database::"Sales Line";
        OtherLine.Insert(false);
        OtherLine := PickLine;
        OtherLine."Line No." := 40000;
        OtherLine."Source Subtype" := Enum::"Production Order Status"::"Firm Planned".AsInteger();
        OtherLine.Insert(false);
        OtherLine := PickLine;
        OtherLine."Line No." := 50000;
        OtherLine."Action Type" := OtherLine."Action Type"::Place;
        OtherLine.Insert(false);
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, LP."No.");
        AssertStamp(PickLine."No.", 20000, '');
        AssertStamp(PickLine."No.", 30000, '');
        AssertStamp(PickLine."No.", 40000, '');
        AssertStamp(PickLine."No.", 50000, '');
    end;

    [Test]
    procedure ProductionStampRequiresActualBinAndExactContentIdentity()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        OtherLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
        Index: Integer;
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        for Index := 2 to 8 do begin
            OtherLine := PickLine;
            OtherLine."Line No." := Index * 10000;
            case Index of
                2: OtherLine."Location Code" := 'OTHER';
                3: OtherLine."Bin Code" := 'OTHER';
                4: OtherLine."Item No." := 'OTHER';
                5: OtherLine."Variant Code" := 'OTHER';
                6: OtherLine."Lot No." := 'OTHER';
                7: OtherLine."Serial No." := 'OTHER';
                8: OtherLine."Lot No." := '';
            end;
            OtherLine.Insert(false);
        end;
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, LP."No.");
        for Index := 2 to 7 do
            AssertStamp(PickLine."No.", Index * 10000, '');
        // An explicitly selected LP is also a source hint before the pick has
        // tracking. The lot is still validated at physical confirmation.
        AssertStamp(PickLine."No.", 80000, LP."No.");
        OtherLine.Get(PickLine."Activity Type", PickLine."No.", 80000);
        Check(OtherLine."Lot No." = '', 'Preference bypassed lot confirmation.');
    end;

    [Test]
    procedure OpenOrForeignAssignedLpIsNeverStamped()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        LP.Status := LP.Status::Open;
        LP.Modify(false);
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, '');
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := 'OTHER-ORDER';
        LP.Modify(false);
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, '');
        LP."Assigned Document No." := ProdOrderNo;
        LP.Modify(false);
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, LP."No.");
    end;

    [Test]
    procedure ProductionDoesNotGuessOtherLpOrOverwriteExistingSelection()
    var
        LP: Record "DOPSWHS LP Header";
        OtherLP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        OtherLPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        OtherPickLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        OtherLP := LP;
        OtherLP."No." := NewCode();
        OtherLP."Bin Code" := 'OTHER';
        OtherLP.Insert(false);
        OtherLPLine := LPLine;
        OtherLPLine."LP No." := OtherLP."No.";
        OtherLPLine.Insert(false);
        OtherPickLine := PickLine;
        OtherPickLine."Line No." := 20000;
        OtherPickLine."Bin Code" := OtherLP."Bin Code";
        OtherPickLine.Insert(false);
        PickLine."LP No." := OtherLP."No.";
        PickLine.Modify(false);
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, OtherLP."No.");
        AssertStamp(PickLine."No.", 20000, '');
    end;

    [Test]
    procedure ShipmentConfigurationClearsPreviousProductionScope()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        PickLine."Source Type" := Database::"Sales Line";
        PickLine."Source Subtype" := 1;
        PickLine."Source No." := 'SALES-ORDER';
        PickLine.Modify(false);
        Preference.ConfigureForProduction(ProdOrderNo, LP."No.");
        Preference.ConfigureForcedLp('SHIPMENT', LP."No.");
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, LP."No.");
    end;

    [Test]
    procedure ProductionWithoutSelectedLpDoesNotGuessFromBin()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        PickLine: Record "Warehouse Activity Line";
        Preference: Codeunit "DOPSWHS LP Pick Preference";
        ProdOrderNo: Code[20];
    begin
        Fixture(LP, LPLine, PickLine, ProdOrderNo);
        Preference.ConfigureForcedLp('SHIPMENT', LP."No.");
        Preference.ConfigureForProduction(ProdOrderNo, '');
        Preference.StampPickLines(PickLine."No.");
        AssertStamp(PickLine."No.", 10000, '');
    end;

    local procedure Fixture(var LP: Record "DOPSWHS LP Header"; var LPLine: Record "DOPSWHS LP Line"; var PickLine: Record "Warehouse Activity Line"; var ProdOrderNo: Code[20])
    begin
        ProdOrderNo := NewCode();
        LP."No." := NewCode();
        LP.Status := LP.Status::Built;
        LP."Location Code" := 'PROD-TEST';
        LP."Bin Code" := 'SOURCE';
        LP.Insert(false);
        LPLine."LP No." := LP."No.";
        LPLine."Line No." := 10000;
        LPLine."Item No." := NewCode();
        LPLine."Variant Code" := 'VARIANT';
        LPLine."Lot No." := 'LOT-ONE';
        LPLine.Quantity := 10;
        LPLine."Unit of Measure" := 'PCS';
        LPLine.Insert(false);
        PickLine."Activity Type" := PickLine."Activity Type"::Pick;
        PickLine."No." := NewCode();
        PickLine."Line No." := 10000;
        PickLine."Action Type" := PickLine."Action Type"::Take;
        PickLine."Source Type" := Database::"Prod. Order Component";
        PickLine."Source Subtype" := Enum::"Production Order Status"::Released.AsInteger();
        PickLine."Source No." := ProdOrderNo;
        PickLine."Source Line No." := 10000;
        PickLine."Source Subline No." := 10000;
        PickLine."Location Code" := LP."Location Code";
        PickLine."Bin Code" := LP."Bin Code";
        PickLine."Item No." := LPLine."Item No.";
        PickLine."Variant Code" := LPLine."Variant Code";
        PickLine."Lot No." := LPLine."Lot No.";
        PickLine.Quantity := 10;
        PickLine."Qty. (Base)" := 10;
        PickLine."Qty. Outstanding" := 10;
        PickLine."Qty. Outstanding (Base)" := 10;
        PickLine."Qty. per Unit of Measure" := 1;
        PickLine.Insert(false);
    end;

    local procedure AssertStamp(PickNo: Code[20]; LineNo: Integer; ExpectedLpNo: Code[20])
    var
        PickLine: Record "Warehouse Activity Line";
    begin
        PickLine.Get(PickLine."Activity Type"::Pick, PickNo, LineNo);
        Check(PickLine."LP No." = ExpectedLpNo, StrSubstNo('Incorrect LP on production pick line %1.', LineNo));
    end;

    local procedure NewCode(): Code[20]
    begin
        exit(CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
