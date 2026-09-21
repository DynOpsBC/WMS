codeunit 72186 "DOPSWHS Prod Pallet Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure WholePalletKeepsIdentityContentsAndSource()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        Mgt.PrepareProductionPallets(Pick, Plan(TakeLine, LP."No.", 10));
        LP.Get(LP."No.");
        Check(LP."Bin Code" = 'PROD', 'LP did not reach production bin.');
        Check(LP."Assigned Document Type" = LP."Assigned Document Type"::ProdConsumption, 'LP remained attached to deleted pick.');
        Check(LP."Assigned Document No." = TakeLine."Source No.", 'Wrong production order assignment.');
        Check(LP.SSCC = '123456789012345678', 'SSCC changed.');
        LPLine.Get(LP."No.", 10000);
        Check(LPLine.Quantity = 10, 'Prepared pallet was split.');
        Check(LPLine."Source Item Ledger Entry No." = 987654, 'Stock source was overwritten.');
        Check(LPLine."Source Document No." = 'RECEIPT-ORIGIN', 'Source document was overwritten.');
    end;

    [Test]
    procedure MergedPlaceDoesNotAttributeBothPalletsToLastTake()
    var
        Pick: Record "Warehouse Activity Header";
        FirstTake: Record "Warehouse Activity Line";
        SecondTake: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        FirstLP: Record "DOPSWHS LP Header";
        SecondLP: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Bin: Record Bin;
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Plans: JsonArray;
        SecondPlan: JsonArray;
        Token: JsonToken;
        PlanText: Text;
    begin
        Fixture(Pick, FirstTake, FirstLP);
        Bin."Location Code" := FirstLP."Location Code";
        Bin.Code := 'RAW2';
        Bin.Insert(false);
        SecondLP := FirstLP;
        SecondLP."No." := 'SECOND-PROD-LP';
        SecondLP."Bin Code" := Bin.Code;
        SecondLP.Insert(false);
        Content.Get(FirstLP."No.", 10000);
        Content."LP No." := SecondLP."No.";
        Content.Insert(false);
        SecondTake := FirstTake;
        SecondTake."Line No." := 30000;
        SecondTake."Bin Code" := SecondLP."Bin Code";
        // Creation-time preferences may differ from the operator's scan.
        SecondTake."LP No." := FirstLP."No.";
        SecondTake.Insert(false);
        FirstTake."LP No." := SecondLP."No.";
        FirstTake.Modify(false);
        PlaceLine.Get(Pick.Type, Pick."No.", 20000);
        PlaceLine."Qty. to Handle" := 20;
        PlaceLine."Qty. to Handle (Base)" := 20;
        PlaceLine."LP No." := 'STALE-HINT';
        PlaceLine.Modify(false);
        Plans.ReadFrom(Plan(FirstTake, FirstLP."No.", 10));
        SecondPlan.ReadFrom(Plan(SecondTake, SecondLP."No.", 10));
        SecondPlan.Get(0, Token);
        Plans.Add(Token);
        Plans.WriteTo(PlanText);

        Mgt.PrepareProductionPallets(Pick, PlanText);

        FirstTake.Get(Pick.Type, Pick."No.", 10000);
        SecondTake.Get(Pick.Type, Pick."No.", 30000);
        PlaceLine.Get(Pick.Type, Pick."No.", 20000);
        Check(FirstTake."LP No." = FirstLP."No.", 'First Take retained a stale preference instead of the scanned LP.');
        Check(SecondTake."LP No." = SecondLP."No.", 'Second Take retained a stale preference instead of the scanned LP.');
        Check(PlaceLine."LP No." = '', 'Merged Place incorrectly attributed both pallets to one LP.');
        Check(PlaceLine."Target LP No." = '', 'Merged Place retained a misleading target LP.');
        FirstLP.Get(FirstLP."No.");
        SecondLP.Get(SecondLP."No.");
        Check((FirstLP."Bin Code" = 'PROD') and (SecondLP."Bin Code" = 'PROD'), 'Both whole pallets must reach the production bin.');
    end;

    [Test]
    procedure MultiPalletTakeClearsCreationHintOnBothActions()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        FirstLP: Record "DOPSWHS LP Header";
        SecondLP: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Plans: JsonArray;
        Steps: JsonArray;
        LinePlan: JsonObject;
        Step: JsonObject;
        Token: JsonToken;
        PlanText: Text;
    begin
        Fixture(Pick, TakeLine, FirstLP);
        Content.Get(FirstLP."No.", 10000);
        Content.Quantity := 5;
        Content.Modify(false);
        SecondLP := FirstLP;
        SecondLP."No." := 'SECOND-PROD-LP';
        SecondLP.Insert(false);
        Content."LP No." := SecondLP."No.";
        Content.Insert(false);
        TakeLine."LP No." := FirstLP."No.";
        TakeLine.Modify(false);
        Plans.ReadFrom(Plan(TakeLine, FirstLP."No.", 5));
        Plans.Get(0, Token);
        LinePlan := Token.AsObject();
        LinePlan.Get('steps', Token);
        Steps := Token.AsArray();
        Steps.Get(0, Token);
        Step := Token.Clone().AsObject();
        Step.Replace('lpNo', SecondLP."No.");
        Steps.Add(Step);
        LinePlan.Replace('steps', Steps);
        Clear(Plans);
        Plans.Add(LinePlan);
        Plans.WriteTo(PlanText);

        Mgt.PrepareProductionPallets(Pick, PlanText);

        TakeLine.Get(Pick.Type, Pick."No.", 10000);
        PlaceLine.Get(Pick.Type, Pick."No.", 20000);
        Check(TakeLine."LP No." = '', 'Multi-pallet Take retained the first pallet as the complete stock source.');
        Check(TakeLine."Target LP No." = '', 'Multi-pallet Take retained a single target LP.');
        Check(PlaceLine."LP No." = '', 'Multi-pallet Place retained a single LP.');
        Check(PlaceLine."Target LP No." = '', 'Multi-pallet Place retained a single target LP.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FailedStandardRegistrationRollsBackPreparedLpAndLedger()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        ActivityLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Location: Record Location;
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        RequestingUserId: Code[50];
        ErrorStack: Text;
    begin
        Fixture(Pick, TakeLine, LP);
        RequestingUserId := CopyStr(UserId(), 1, MaxStrLen(RequestingUserId));
        Check(RequestingUserId <> '', 'The registration test requires a BC session user.');
        Pick."Assigned User ID" := RequestingUserId;
        Pick.Modify(false);
        Location.Get(Pick."Location Code");
        Location."Bin Mandatory" := true;
        Location."Require Pick" := true;
        Location.Modify(false);
        ActivityLine.SetRange("Activity Type", Pick.Type);
        ActivityLine.SetRange("No.", Pick."No.");
        ActivityLine.FindSet(true);
        repeat
            ActivityLine.Quantity := 10;
            ActivityLine."Qty. (Base)" := 10;
            ActivityLine."Qty. Outstanding" := 10;
            ActivityLine."Qty. Outstanding (Base)" := 10;
            ActivityLine."Qty. per Unit of Measure" := 1;
            ActivityLine.Modify(false);
        until ActivityLine.Next() = 0;
        TakeLine.Get(Pick.Type, Pick."No.", 10000);
        Ledger.SetRange("LP No.", LP."No.");
        Check(Ledger.IsEmpty(), 'Fixture unexpectedly has movement ledger entries.');

        // No warehouse stock or posting setup is created. The valid LP plan
        // stages the pallet, then BC registration must reject the real pick.
        // AssertError has its own transaction scope; fixture records survive.
        asserterror Mgt.RegisterScannedPickFor(Pick, RequestingUserId, Plan(TakeLine, LP."No.", 10));
        ErrorStack := GetLastErrorCallStack();
        Check(StrPos(ErrorStack, 'Whse.-Activity-Register') > 0,
            'Expected failure inside standard warehouse registration after LP preparation: ' + GetLastErrorText());

        AssertUnmoved(LP);
        Check(LP."Assigned Document Type" = LP."Assigned Document Type"::None, 'Failed stock registration assigned the LP.');
        Check(LP."Assigned Document No." = '', 'Failed stock registration retained the production order.');
        Content.Get(LP."No.", 10000);
        Check(Content.Quantity = 10, 'Failed stock registration changed pallet contents.');
        Check(Content."Source Item Ledger Entry No." = 987654, 'Failed stock registration changed the source entry.');
        Check(Content."Source Document No." = 'RECEIPT-ORIGIN', 'Failed stock registration changed the source document.');
        Check(Ledger.IsEmpty(), 'Failed stock registration left an LP movement or assignment ledger entry.');
        TakeLine.Get(TakeLine."Activity Type", TakeLine."No.", TakeLine."Line No.");
        Check(TakeLine."LP No." = '', 'Failed stock registration retained staged activity LP references.');
    end;

    [Test]
    procedure PartialPalletIsRejectedWithoutMovingIt()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        TakeLine."Qty. to Handle" := 5;
        TakeLine."Qty. to Handle (Base)" := 5;
        TakeLine.Modify(false);
        asserterror Mgt.PrepareProductionPallets(Pick, Plan(TakeLine, LP."No.", 5));
        Check(StrPos(GetLastErrorText(), 'tamamını karşılamıyor') > 0, GetLastErrorText());
        AssertUnmoved(LP);
    end;

    [Test]
    procedure SameTotalOfWrongContentDoesNotPass()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        Content.Get(LP."No.", 10000);
        Content.Quantity := 5;
        Content.Modify(false);
        Content."Line No." := 20000;
        Content."Lot No." := 'UNPLANNED';
        Content.Insert(false);
        asserterror Mgt.PrepareProductionPallets(Pick, Plan(TakeLine, LP."No.", 10));
        Check(StrPos(GetLastErrorText(), 'tamamı') > 0, GetLastErrorText());
        AssertUnmoved(LP);
    end;

    [Test]
    procedure ForeignOrderAssignmentIsRejected()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := 'ANOTHER-ORDER';
        LP.Modify(false);
        asserterror Mgt.PrepareProductionPallets(Pick, Plan(TakeLine, LP."No.", 10));
        Check(StrPos(GetLastErrorText(), 'başka bir belgeye') > 0, GetLastErrorText());
        LP.Get(LP."No.");
        Check(LP."Bin Code" = 'RAW', 'Foreign LP moved.');
    end;

    [Test]
    procedure OwnProductionAssignmentIsAllowed()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        LP.Status := LP.Status::Assigned;
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := TakeLine."Source No.";
        LP.Modify(false);
        Mgt.PrepareProductionPallets(Pick, Plan(TakeLine, LP."No.", 10));
        LP.Get(LP."No.");
        Check(LP."Bin Code" = 'PROD', 'Own production LP was not moved.');
    end;

    [Test]
    procedure MissingScannedPlanCannotLeaveLpAtOldBin()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        Fixture(Pick, TakeLine, LP);
        asserterror Mgt.PrepareProductionPallets(Pick, '');
        Check(StrPos(GetLastErrorText(), 'tamamını okutun') > 0, GetLastErrorText());
        AssertUnmoved(LP);
    end;

    [Test]
    procedure StaleQuantityAndLocationCannotMoveLp()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        PlanText: Text;
    begin
        Fixture(Pick, TakeLine, LP);
        PlanText := Plan(TakeLine, LP."No.", 10);
        TakeLine."Qty. to Handle" := 9;
        TakeLine.Modify(false);
        asserterror Mgt.PrepareProductionPallets(Pick, PlanText);
        Check(StrPos(GetLastErrorText(), 'miktarı değişmiş') > 0, GetLastErrorText());
        AssertUnmoved(LP);
        TakeLine."Qty. to Handle" := 10;
        TakeLine.Modify(false);
        LP."Location Code" := 'OTHER';
        LP.Modify(false);
        asserterror Mgt.PrepareProductionPallets(Pick, PlanText);
        LP.Get(LP."No.");
        Check(LP."Location Code" = 'OTHER', 'Metadata-only cross-location transfer occurred.');
        Check(LP."Bin Code" = 'RAW', 'Cross-location LP was moved.');
    end;

    [Test]
    procedure ProductionAssignmentDoesNotMatchSameNumberSalesOrder()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Verification: Codeunit "DOPSWHS LP Verification";
    begin
        Fixture(Pick, TakeLine, LP);
        LP."Assigned Document Type" := LP."Assigned Document Type"::ProdConsumption;
        LP."Assigned Document No." := TakeLine."Source No.";
        Check(Verification.AssignmentMatchesLine(LP, TakeLine), 'Production assignment should match.');
        TakeLine."Source Type" := Database::"Sales Line";
        Check(not Verification.AssignmentMatchesLine(LP, TakeLine), 'Sales number collision matched production assignment.');
    end;

    local procedure Fixture(var Pick: Record "Warehouse Activity Header"; var TakeLine: Record "Warehouse Activity Line"; var LP: Record "DOPSWHS LP Header")
    var
        ProductionOrder: Record "Production Order";
        Component: Record "Prod. Order Component";
        PlaceLine: Record "Warehouse Activity Line";
        Content: Record "DOPSWHS LP Line";
        Item: Record Item;
        Location: Record Location;
        Bin: Record Bin;
    begin
        Location.Code := 'PPTEST';
        Location.Insert(false);
        Bin."Location Code" := Location.Code;
        Bin.Code := 'RAW';
        Bin.Insert(false);
        Bin.Code := 'PROD';
        Bin.Insert(false);
        Item."No." := 'PROD-LP-ITEM';
        Item."Base Unit of Measure" := 'PCS';
        Item.Insert(false);
        ProductionOrder.Status := ProductionOrder.Status::Released;
        ProductionOrder."No." := 'PROD-LP-TEST';
        ProductionOrder.Insert(false);
        Component.Status := Component.Status::Released;
        Component."Prod. Order No." := ProductionOrder."No.";
        Component."Prod. Order Line No." := 10000;
        Component."Line No." := 10000;
        Component."Item No." := Item."No.";
        Component."Location Code" := Location.Code;
        Component."Bin Code" := 'PROD';
        Component."Unit of Measure Code" := 'PCS';
        Component.Insert(false);
        Pick.Type := Pick.Type::Pick;
        Pick."No." := 'PROD-PICK-TEST';
        Pick."Location Code" := Location.Code;
        Pick.Insert(false);
        TakeLine."Activity Type" := TakeLine."Activity Type"::Pick;
        TakeLine."No." := Pick."No.";
        TakeLine."Line No." := 10000;
        TakeLine."Action Type" := TakeLine."Action Type"::Take;
        TakeLine."Source Type" := Database::"Prod. Order Component";
        TakeLine."Source Subtype" := 3;
        TakeLine."Source No." := ProductionOrder."No.";
        TakeLine."Source Line No." := 10000;
        TakeLine."Source Subline No." := 10000;
        TakeLine."Item No." := Item."No.";
        TakeLine."Location Code" := Location.Code;
        TakeLine."Bin Code" := 'RAW';
        TakeLine."Unit of Measure Code" := 'PCS';
        TakeLine."Lot No." := 'LOT1';
        TakeLine."Qty. to Handle" := 10;
        TakeLine."Qty. to Handle (Base)" := 10;
        TakeLine.Insert(false);
        PlaceLine := TakeLine;
        PlaceLine."Line No." := 20000;
        PlaceLine."Action Type" := PlaceLine."Action Type"::Place;
        PlaceLine."Bin Code" := 'PROD';
        PlaceLine.Insert(false);
        LP."No." := 'PROD-LP-READY';
        LP.Status := LP.Status::Built;
        LP."Location Code" := Location.Code;
        LP."Bin Code" := 'RAW';
        LP.SSCC := '123456789012345678';
        LP.Insert(false);
        Content."LP No." := LP."No.";
        Content."Line No." := 10000;
        Content."Item No." := Item."No.";
        Content."Unit of Measure" := 'PCS';
        Content."Lot No." := 'LOT1';
        Content.Quantity := 10;
        Content."Source Item Ledger Entry No." := 987654;
        Content."Source Document No." := 'RECEIPT-ORIGIN';
        Content.Insert(false);
    end;

    local procedure Plan(TakeLine: Record "Warehouse Activity Line"; LpNo: Code[20]; Qty: Decimal) PlanText: Text
    var
        Document: JsonArray;
        LinePlan: JsonObject;
        Steps: JsonArray;
        Step: JsonObject;
    begin
        Step.Add('lpNo', LpNo);
        Step.Add('binCode', TakeLine."Bin Code");
        Step.Add('lotNo', TakeLine."Lot No.");
        Step.Add('serialNo', TakeLine."Serial No.");
        Step.Add('baseQuantity', Qty);
        Steps.Add(Step);
        LinePlan.Add('lineNo', TakeLine."Line No.");
        LinePlan.Add('identity', UpperCase(TakeLine."No." + '|' + TakeLine."Item No." + '|' + TakeLine."Variant Code" + '|' + TakeLine."Location Code" + '|' + TakeLine."Bin Code" + '|' + TakeLine."Serial No." + '|' + TakeLine."Unit of Measure Code"));
        LinePlan.Add('lotNo', TakeLine."Lot No.");
        LinePlan.Add('quantity', TakeLine."Qty. to Handle");
        LinePlan.Add('steps', Steps);
        Document.Add(LinePlan);
        Document.WriteTo(PlanText);
    end;

    local procedure AssertUnmoved(var LP: Record "DOPSWHS LP Header")
    begin
        LP.Get(LP."No.");
        Check(LP."Bin Code" = 'RAW', 'Rejected plan moved the LP.');
        Check(LP.Status = LP.Status::Built, 'Rejected plan assigned the LP.');
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
