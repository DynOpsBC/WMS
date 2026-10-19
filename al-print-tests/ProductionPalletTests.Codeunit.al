codeunit 72186 "DOPSWHS Prod Pallet Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Warehouse Entry" = RIMD, tabledata "Item Ledger Entry" = RIMD;

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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
        asserterror Mgt.PrepareProductionPallets(Pick, PlanText);
        Check(StrPos(GetLastErrorText(), 'miktarı değişmiş') > 0, GetLastErrorText());
        AssertUnmoved(LP);
        TakeLine."Qty. to Handle" := 10;
        TakeLine.Modify(false);
        LP."Location Code" := 'OTHER';
        LP.Modify(false);
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
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

    [Test]
    procedure PrepareTwoBinsKeepsProductionUnpickedAndRetryDoesNotDuplicate()
    begin
        PreparationRoundTrip(false);
    end;

    [Test]
    procedure DirectedPreparationAndDeliveryPreserveLotStock()
    begin
        PreparationRoundTrip(true);
    end;

    [Test]
    procedure DirectBcDeleteRetiresEmptyTargetAndStaleStartCreatesNothing()
    var
        Pick: Record "Warehouse Activity Header";
        StalePick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        TargetNo: Code[20];
        BeforeCount: Integer;
    begin
        PreparationFixture(Pick, TakeLine, Source, Target);
        StalePick := Pick;
        TargetNo := Target."No.";
        // This is the standard BC delete path, not terminal CancelPickFor.
        Pick.Delete(true);
        Target.Get(TargetNo);
        Check(Target.Status = Target.Status::Unbuilt, 'BC deletion left an active empty target LP.');
        Target.Reset();
        BeforeCount := Target.Count();
        Commit();
        asserterror Mgt.StartProductionLPFor(StalePick, StalePick."Assigned User ID", '');
        Check(Target.Count() = BeforeCount, 'A stale terminal request created another LP.');
    end;

    [Test]
    procedure DirectBcDeleteCannotOrphanPreparedProductionStock()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PreparationFixture(Pick, TakeLine, Source, Target);
        AddPreparationStock(TakeLine, 100);
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', Plan(TakeLine, Source."No.", 10));
        Commit();
        asserterror Pick.Delete(true);
        Check(Pick.Get(Pick.Type, Pick."No."), 'Prepared production pick was deleted.');
        Target.Get(Target."No.");
        Check(Target."Assigned Document No." = Pick."No.", 'Prepared pallet lost its document.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 10, 'Prepared pallet quantity changed.');
        AssertBinQuantity(TakeLine."Item No.", 'STAGE', 10);
        AssertBinQuantity(TakeLine."Item No.", 'RAW', 90);
    end;

    local procedure PreparationRoundTrip(Directed: Boolean)
    var
        Pick: Record "Warehouse Activity Header";
        First: Record "Warehouse Activity Line";
        Second: Record "Warehouse Activity Line";
        Place: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        SecondLP: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Component: Record "Prod. Order Component";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Plans: JsonArray;
        Part: JsonArray;
        Token: JsonToken;
        PlanText: Text;
        OperatorId: Code[50];
        Location: Record Location;
        Bin: Record Bin;
        BinType: Record "Bin Type";
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
    begin
        PreparationFixture(Pick, First, LP, Target);
        if Directed then begin
            Location.Get(Pick."Location Code");
            Location."Directed Put-away and Pick" := true;
            Location.Modify(false);
            if not BinType.Get('PPTEST') then begin
                BinType.Code := 'PPTEST';
                BinType.Pick := true;
                BinType."Put Away" := true;
                BinType.Insert(false);
            end;
            Bin.SetRange("Location Code", Location.Code);
            Bin.ModifyAll("Bin Type Code", BinType.Code);
            if not Tracking.Get('PPTEST') then begin
                Tracking.Code := 'PPTEST';
                Tracking."Lot Warehouse Tracking" := true;
                Tracking.Insert(false);
            end;
            Item.Get(First."Item No.");
            Item."Item Tracking Code" := Tracking.Code;
            Item.Modify(false);
        end;
        AddPreparationStock(First, 100);
        Second := First;
        Second."Line No." := 30000;
        Second."Bin Code" := 'RAW2';
        Second.Insert(false);
        AddPreparationStock(Second, 100);
        SecondLP := LP;
        SecondLP."No." := 'SECOND-PREP-LP';
        SecondLP."Bin Code" := 'RAW2';
        SecondLP.Insert(false);
        Content.Get(LP."No.", 10000);
        Content."LP No." := SecondLP."No.";
        Content.Insert(false);
        Place.Get(Pick.Type, Pick."No.", 20000);
        Place.Quantity := 20;
        Place."Qty. (Base)" := 20;
        Place."Qty. Outstanding" := 20;
        Place."Qty. Outstanding (Base)" := 20;
        Place."Qty. to Handle" := 20;
        Place."Qty. to Handle (Base)" := 20;
        Place.Modify(false);
        Plans.ReadFrom(Plan(First, LP."No.", 10));
        Part.ReadFrom(Plan(Second, SecondLP."No.", 10));
        Part.Get(0, Token);
        Plans.Add(Token);
        Plans.WriteTo(PlanText);
        OperatorId := Pick."Assigned User ID";

        Mgt.PrepareProductionLPFor(Pick, OperatorId, 'STAGE', PlanText);
        Check(Pick."DOPSWHS Prod LP Staged", 'Preparation state not persisted.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Target did not collect both partial pallets.');
        Check(LPMgt.TotalBaseQuantity(LP."No.") = 90, 'First source remainder incorrect.');
        Check(LPMgt.TotalBaseQuantity(SecondLP."No.") = 90, 'Second source remainder incorrect.');
        AssertBinQuantity(First."Item No.", 'RAW', 90);
        AssertBinQuantity(First."Item No.", 'RAW2', 90);
        AssertBinQuantity(First."Item No.", 'STAGE', 20);
        AssertBinQuantity(First."Item No.", 'PROD', 0);
        Component.Get(Component.Status::Released, First."Source No.", 10000, 10000);
        Check(Component."Qty. Picked" = 0, 'Preparation prematurely picked production.');
        First.Get(Pick.Type, Pick."No.", 10000);
        Check(First."Bin Code" = 'STAGE', 'Pick still points to the old source bin.');
        Check(First."Source No." = Component."Prod. Order No.", 'Production source lost.');
        Check(First."Qty. Handled" = 0, 'Preparation registered the production pick.');
        Target.Get(Target."No.");
        Check(Target."Assigned Document No." = Pick."No.", 'Prepared LP not reserved to original pick.');
        Mgt.PrepareProductionLPFor(Pick, OperatorId, 'STAGE', PlanText);
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Retry duplicated target stock.');
        AssertBinQuantity(First."Item No.", 'STAGE', 20);
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
        asserterror Mgt.ConfirmPickLineFor(First, 5, First."Lot No.", Target."No.", OperatorId);
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Quantity edit changed a prepared pallet.');
        Mgt.ConfirmPickLineFor(First, 10, First."Lot No.", Target."No.", OperatorId);
        Commit();
        asserterror Mgt.CancelPickFor(Pick, OperatorId);
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Cancel lost the prepared pallet.');
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
        asserterror Mgt.DeliverProductionLPFor(Pick, OperatorId, 'RAW', '[]');
        Target.Get(Target."No.");
        Check(Target."Bin Code" = 'STAGE', 'Wrong destination moved the target.');
        // Now deliver the same prepared LP on the original production pick.
        First.Get(Pick.Type, Pick."No.", 10000);
        Second.Get(Pick.Type, Pick."No.", 30000);
        Clear(Plans); Clear(Part);
        Plans.ReadFrom(Plan(First, Target."No.", 10));
        Part.ReadFrom(Plan(Second, Target."No.", 10));
        Part.Get(0, Token); Plans.Add(Token); Plans.WriteTo(PlanText);
        Mgt.DeliverProductionLPFor(Pick, OperatorId, 'PROD', PlanText);
        AssertBinQuantity(First."Item No.", 'RAW', 90);
        AssertBinQuantity(First."Item No.", 'RAW2', 90);
        AssertBinQuantity(First."Item No.", 'STAGE', 0);
        AssertBinQuantity(First."Item No.", 'PROD', 20);
        Component.Get(Component.Status::Released, First."Source No.", 10000, 10000);
        Check(Component."Qty. Picked" = 20, 'Delivery did not update the original production component exactly once.');
        Target.Get(Target."No.");
        Check(Target."Bin Code" = 'PROD', 'Delivered LP stayed in preparation bin.');
        Check(Target."Assigned Document Type" = Target."Assigned Document Type"::ProdConsumption, 'Delivered LP lost production assignment.');
        Check(Target."Assigned Document No." = Component."Prod. Order No.", 'Delivered LP belongs to wrong production order.');
        Commit();
        asserterror Mgt.DeliverProductionLPFor(Pick, OperatorId, 'PROD', PlanText);
        Component.Get(Component.Status::Released, First."Source No.", 10000, 10000);
        Check(Component."Qty. Picked" = 20, 'Repeated delivery picked the component twice.');
    end;

    [Test]
    procedure PreparingInSourceBinDoesNotMoveWarehouseStock()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PreparationFixture(Pick, TakeLine, LP, Target);
        AddPreparationStock(TakeLine, 100);
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'RAW', Plan(TakeLine, LP."No.", 10));
        AssertBinQuantity(TakeLine."Item No.", 'RAW', 100);
        Check(LPMgt.TotalBaseQuantity(LP."No.") = 90, 'Same-bin split changed the source incorrectly.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 10, 'Same-bin target did not receive the needed quantity.');
        Check(Pick."DOPSWHS Prod LP Staged", 'Same-bin preparation was not persisted.');
    end;

    [Test]
    procedure MissingPhysicalStockLeavesSourceTargetAndPickUnchanged()
    var
        Pick: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PreparationFixture(Pick, TakeLine, LP, Target);
        // LP metadata exists but physical warehouse stock is deliberately absent.
        Commit(); // Commit only synthetic fixture state; assert the operation rolls back.
        asserterror Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', Plan(TakeLine, LP."No.", 10));
        Check(StrPos(GetLastErrorText(), 'gerçek stoku yetersiz') > 0, GetLastErrorText());
        Check(LPMgt.TotalBaseQuantity(LP."No.") = 100, 'Failed movement changed source LP.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 0, 'Failed movement filled target LP.');
        Pick.Get(Pick.Type, Pick."No.");
        Check(not Pick."DOPSWHS Prod LP Staged", 'Failed movement persisted preparation state.');
        TakeLine.Get(Pick.Type, Pick."No.", TakeLine."Line No.");
        Check(TakeLine."Bin Code" = 'RAW', 'Failed movement rebased original pick.');
    end;

    [Test]
    procedure MixedItemsAndLotsPrepareAndDeliverTogether()
    begin
        MixedPreparation(false);
    end;

    [Test]
    procedure FailureOnSecondSourceRollsBackFirstSource()
    begin
        MixedPreparation(true);
    end;

    local procedure MixedPreparation(FailSecond: Boolean)
    var
        Pick: Record "Warehouse Activity Header";
        First: Record "Warehouse Activity Line";
        Second: Record "Warehouse Activity Line";
        Place: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Source2: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Item: Record Item;
        Uom: Record "Item Unit of Measure";
        Component: Record "Prod. Order Component";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Plans: JsonArray;
        Part: JsonArray;
        Token: JsonToken;
        PlanText: Text;
    begin
        PreparationFixture(Pick, First, Source, Target);
        AddPreparationStock(First, 100);
        Item.Get(First."Item No.");
        Item."No." := 'PROD-LP-ITEM2'; Item.Insert(false);
        Uom.Get(First."Item No.", 'PCS');
        Uom."Item No." := Item."No."; Uom.Insert(false);
        Component.Get(Component.Status::Released, First."Source No.", 10000, 10000);
        Component."Line No." := 20000; Component."Item No." := Item."No."; Component.Insert(false);
        Second := First; Second."Line No." := 30000;
        Second."Source Subline No." := 20000; Second."Item No." := Item."No.";
        Second."Bin Code" := 'RAW2'; Second."Lot No." := 'LOT2'; Second.Insert(false);
        Place := Second; Place."Line No." := 40000;
        Place."Action Type" := Place."Action Type"::Place; Place."Bin Code" := 'PROD'; Place.Insert(false);
        AddPreparationStock(Second, 100);
        Source2 := Source; Source2."No." := 'SECOND-PREP-LP'; Source2."Bin Code" := 'RAW2'; Source2.Insert(false);
        Content.Get(Source."No.", 10000); Content."LP No." := Source2."No.";
        Content."Item No." := Item."No."; Content."Lot No." := 'LOT2';
        if FailSecond then Content.Quantity := 1;
        Content.Insert(false);
        Plans.ReadFrom(Plan(First, Source."No.", 10)); Part.ReadFrom(Plan(Second, Source2."No.", 10));
        Part.Get(0, Token); Plans.Add(Token); Plans.WriteTo(PlanText);
        if FailSecond then begin
            Commit();
            asserterror Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', PlanText);
            Check(LPMgt.TotalBaseQuantity(Source."No.") = 100, 'First LP was consumed before the second source failed.');
            Check(LPMgt.TotalBaseQuantity(Source2."No.") = 1, 'Failed source changed.');
            Check(LPMgt.TotalBaseQuantity(Target."No.") = 0, 'Failed mixed preparation left target content.');
            AssertBinQuantity(First."Item No.", 'RAW', 100);
            AssertBinQuantity(Second."Item No.", 'RAW2', 100);
            AssertBinQuantity(First."Item No.", 'STAGE', 0);
            exit;
        end;
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', PlanText);
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Mixed target total incorrect.');
        AssertBinQuantity(First."Item No.", 'RAW', 90);
        AssertBinQuantity(Second."Item No.", 'RAW2', 90);
        AssertBinQuantity(First."Item No.", 'STAGE', 10);
        AssertBinQuantity(Second."Item No.", 'STAGE', 10);
        First.Get(Pick.Type, Pick."No.", 10000); Second.Get(Pick.Type, Pick."No.", 30000);
        Clear(Plans); Clear(Part);
        Plans.ReadFrom(Plan(First, Target."No.", 10)); Part.ReadFrom(Plan(Second, Target."No.", 10));
        Part.Get(0, Token); Plans.Add(Token); Plans.WriteTo(PlanText);
        Mgt.DeliverProductionLPFor(Pick, Pick."Assigned User ID", 'PROD', PlanText);
        AssertBinQuantity(First."Item No.", 'PROD', 10);
        AssertBinQuantity(Second."Item No.", 'PROD', 10);
        AssertBinQuantity(First."Item No.", 'STAGE', 0);
        AssertBinQuantity(Second."Item No.", 'STAGE', 0);
        Component.Get(Component.Status::Released, First."Source No.", 10000, 10000);
        Check(Component."Qty. Picked" = 10, 'First component not picked exactly once.');
        Component.Get(Component.Status::Released, Second."Source No.", 10000, 20000);
        Check(Component."Qty. Picked" = 10, 'Second component not picked exactly once.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 20, 'Delivery changed mixed LP contents.');
    end;

    [Test]
    procedure SourceBoxUomIsConvertedWithoutLosingStock()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Uom: Record "Item Unit of Measure";
        Unit: Record "Unit of Measure";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 100);
        if not Unit.Get('PPBOX') then begin Unit.Code := 'PPBOX'; Unit.Insert(false); end;
        Uom."Item No." := Line."Item No."; Uom.Code := 'PPBOX'; Uom."Qty. per Unit of Measure" := 10; Uom.Insert(false);
        Content.Get(Source."No.", 10000); Content."Unit of Measure" := 'PPBOX'; Content.Quantity := 10; Content.Modify(false);
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', Plan(Line, Source."No.", 10));
        Check(LPMgt.TotalBaseQuantity(Source."No.") = 90, 'Box conversion changed source base quantity.');
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 10, 'Box conversion changed target base quantity.');
        Content.Get(Source."No.", 10000); Check(Content.Quantity = 9, 'Expected nine boxes to remain.');
        Line.Get(Pick.Type, Pick."No.", 10000);
        Mgt.DeliverProductionLPFor(Pick, Pick."Assigned User ID", 'PROD', Plan(Line, Target."No.", 10));
        AssertBinQuantity(Line."Item No.", 'PROD', 10);
    end;

    [Test]
    procedure WrongOwnerCannotPrepare()
    begin PreparationRejected(1); end;
    [Test]
    procedure BlockedPreparationBinCannotReceive()
    begin PreparationRejected(2); end;
    [Test]
    procedure ProductionBinCannotBeUsedAsPreparationBin()
    begin PreparationRejected(3); end;
    [Test]
    procedure MissingScansCannotPrepare()
    begin PreparationRejected(4); end;
    [Test]
    procedure ExcessScannedQuantityCannotPrepare()
    begin PreparationRejected(5); end;
    [Test]
    procedure WrongLotSourceCannotPrepare()
    begin PreparationRejected(6); end;
    [Test]
    procedure MovedSourceCannotPrepare()
    begin PreparationRejected(7); end;
    [Test]
    procedure ForeignAssignedSourceCannotPrepare()
    begin PreparationRejected(8); end;
    [Test]
    procedure DuplicatePlanLineCannotPrepare()
    begin PreparationRejected(9); end;
    [Test]
    procedure InsufficientScannedQuantityCannotPrepare()
    begin PreparationRejected(10); end;

    [Test]
    procedure BlockedLotCannotBePrepared()
    begin PreparationRejected(11); end;
    [Test]
    procedure BlockedSourceCannotBePrepared()
    begin PreparationRejected(12); end;

    [Test]
    procedure SharedSameBinStockIsNotCountedTwice()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Second: Record "Warehouse Activity Line";
        Place: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        Plans: JsonArray;
        Part: JsonArray;
        Token: JsonToken;
        PlanText: Text;
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 15);
        Second := Line; Second."Line No." := 30000; Second.Insert(false);
        Place.Get(Pick.Type, Pick."No.", 20000);
        Place.Quantity := 20; Place."Qty. (Base)" := 20;
        Place."Qty. Outstanding" := 20; Place."Qty. Outstanding (Base)" := 20;
        Place."Qty. to Handle" := 20; Place."Qty. to Handle (Base)" := 20; Place.Modify(false);
        Plans.ReadFrom(Plan(Line, Source."No.", 10)); Part.ReadFrom(Plan(Second, Source."No.", 10));
        Part.Get(0, Token); Plans.Add(Token); Plans.WriteTo(PlanText);
        Commit();
        asserterror Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'RAW', PlanText);
        Check(StrPos(GetLastErrorText(), 'gerçek stoku yetersiz') > 0, GetLastErrorText());
        Pick.Get(Pick.Type, Pick."No."); Check(not Pick."DOPSWHS Prod LP Staged", 'Shared stock was prepared twice.');
        AssertBinQuantity(Line."Item No.", 'RAW', 15);
    end;

    [Test]
    procedure PreparedReplayWrongBinAndMissingDeliveryProofAreRejected()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 100);
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', Plan(Line, Source."No.", 10));
        Commit();
        asserterror Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'RAW2', Plan(Line, Source."No.", 10));
        AssertBinQuantity(Line."Item No.", 'STAGE', 10);
        Commit();
        asserterror Mgt.DeliverProductionLPFor(Pick, Pick."Assigned User ID", 'PROD', '[]');
        AssertBinQuantity(Line."Item No.", 'STAGE', 10);
        AssertBinQuantity(Line."Item No.", 'PROD', 0);
    end;

    [Test]
    procedure StaleDeliveryAfterTargetMovedIsRejected()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 100);
        Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'STAGE', Plan(Line, Source."No.", 10));
        Line.Get(Pick.Type, Pick."No.", 10000);
        Target.Get(Target."No."); Target."Bin Code" := 'RAW2'; Target.Modify(false);
        Commit();
        asserterror Mgt.DeliverProductionLPFor(Pick, Pick."Assigned User ID", 'PROD', Plan(Line, Target."No.", 10));
        AssertBinQuantity(Line."Item No.", 'STAGE', 10);
        AssertBinQuantity(Line."Item No.", 'PROD', 0);
    end;

    local procedure PreparationRejected(Scenario: Integer)
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
        Bin: Record Bin;
        Lot: Record "Lot No. Information";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        LPMgt: Codeunit "DOPSWHS LP Management";
        OperatorId: Code[50];
        TargetBin: Code[20];
        PlanText: Text;
        Plans: JsonArray;
        Token: JsonToken;
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 100);
        OperatorId := Pick."Assigned User ID"; TargetBin := 'STAGE'; PlanText := Plan(Line, Source."No.", 10);
        case Scenario of
            1: OperatorId := 'OTHER-OPERATOR';
            2: begin Bin.Get(Pick."Location Code", 'STAGE'); Bin."Block Movement" := Bin."Block Movement"::Inbound; Bin.Modify(false); end;
            3: TargetBin := 'PROD';
            4: PlanText := '[]';
            5: PlanText := Plan(Line, Source."No.", 11);
            6: begin Content.Get(Source."No.", 10000); Content."Lot No." := 'WRONG-LOT'; Content.Modify(false); end;
            7: begin Source."Bin Code" := 'RAW2'; Source.Modify(false); end;
            8: begin Source.Status := Source.Status::Assigned; Source."Assigned Document Type" := Source."Assigned Document Type"::WhsePick; Source."Assigned Document No." := 'OTHER-PICK'; Source.Modify(false); end;
            9: begin Plans.ReadFrom(PlanText); Plans.Get(0, Token); Plans.Add(Token); Plans.WriteTo(PlanText); end;
            10: PlanText := Plan(Line, Source."No.", 9);
            11: begin Lot."Item No." := Line."Item No."; Lot."Lot No." := Line."Lot No."; Lot.Blocked := true; Lot.Insert(false); end;
            12: begin Bin.Get(Pick."Location Code", 'RAW'); Bin."Block Movement" := Bin."Block Movement"::Outbound; Bin.Modify(false); end;
        end;
        Commit();
        asserterror Mgt.PrepareProductionLPFor(Pick, OperatorId, TargetBin, PlanText);
        Check(LPMgt.TotalBaseQuantity(Target."No.") = 0, 'Rejected preparation filled target.');
        Check(LPMgt.TotalBaseQuantity(Source."No.") = 100, 'Rejected preparation changed source.');
        Pick.Get(Pick.Type, Pick."No."); Check(not Pick."DOPSWHS Prod LP Staged", 'Rejected preparation marked complete.');
        AssertBinQuantity(Line."Item No.", 'RAW', 100); AssertBinQuantity(Line."Item No.", 'STAGE', 0);
    end;

    [Test]
    procedure SameBinPreparationWithoutPhysicalStockIsRejected()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PreparationFixture(Pick, Line, Source, Target);
        Commit();
        asserterror Mgt.PrepareProductionLPFor(Pick, Pick."Assigned User ID", 'RAW', Plan(Line, Source."No.", 10));
        Pick.Get(Pick.Type, Pick."No."); Check(not Pick."DOPSWHS Prod LP Staged", 'Nonexistent stock was prepared.');
    end;

    [Test]
    procedure OwnershipChangeBetweenPreparationAndDeliveryIsEnforced()
    var
        Pick: Record "Warehouse Activity Header";
        Line: Record "Warehouse Activity Line";
        Source: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS Pick Mgmt";
        OldOwner: Code[50];
    begin
        PreparationFixture(Pick, Line, Source, Target); AddPreparationStock(Line, 100);
        OldOwner := Pick."Assigned User ID";
        Mgt.PrepareProductionLPFor(Pick, OldOwner, 'STAGE', Plan(Line, Source."No.", 10));
        Mgt.ReassignPick(Pick, 'PP-NEW-OWNER', 'Sandbox ownership handover test');
        Line.Get(Pick.Type, Pick."No.", 10000);
        Commit();
        asserterror Mgt.DeliverProductionLPFor(Pick, OldOwner, 'PROD', Plan(Line, Target."No.", 10));
        AssertBinQuantity(Line."Item No.", 'STAGE', 10);
        Mgt.DeliverProductionLPFor(Pick, 'PP-NEW-OWNER', 'PROD', Plan(Line, Target."No.", 10));
        AssertBinQuantity(Line."Item No.", 'PROD', 10);
    end;

    // Explicitly invoked by the sandbox HTTP concurrency harness, not normal tests.
    procedure SetupConcurrentHttpFixture()
    var
        Environment: Codeunit "Environment Information";
        Pick: Record "Warehouse Activity Header";
        First: Record "Warehouse Activity Line";
        Second: Record "Warehouse Activity Line";
        Place: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        SecondLP: Record "DOPSWHS LP Header";
        Target: Record "DOPSWHS LP Header";
        Content: Record "DOPSWHS LP Line";
    begin
        Check(Environment.IsSandbox(), 'Concurrency fixtures are sandbox only.');
        Check(LowerCase(Environment.GetEnvironmentName()) = 'sand0309', 'Expected sand0309.');
        PreparationFixture(Pick, First, LP, Target);
        AddPreparationStock(First, 100);
        Second := First;
        Second."Line No." := 30000;
        Second."Bin Code" := 'RAW2';
        Second.Insert(false);
        AddPreparationStock(Second, 100);
        SecondLP := LP;
        SecondLP."No." := 'SECOND-PREP-LP';
        SecondLP."Bin Code" := 'RAW2';
        SecondLP.Insert(false);
        Content.Get(LP."No.", 10000);
        Content."LP No." := SecondLP."No.";
        Content.Insert(false);
        Place.Get(Pick.Type, Pick."No.", 20000);
        Place.Quantity := 20;
        Place."Qty. (Base)" := 20;
        Place."Qty. Outstanding" := 20;
        Place."Qty. Outstanding (Base)" := 20;
        Place."Qty. to Handle" := 20;
        Place."Qty. to Handle (Base)" := 20;
        Place.Modify(false);
        Commit();
    end;

    procedure VerifyConcurrentHttpFixture(Delivered: Boolean)
    var
        Environment: Codeunit "Environment Information";
        Pick: Record "Warehouse Activity Header";
        Target: Record "DOPSWHS LP Header";
        Component: Record "Prod. Order Component";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Check(Environment.IsSandbox(), 'Sandbox only.');
        Check(LowerCase(Environment.GetEnvironmentName()) = 'sand0309', 'Expected sand0309.');
        Check(LPMgt.TotalBaseQuantity('PROD-LP-READY') = 90, 'First source debited more than once.');
        Check(LPMgt.TotalBaseQuantity('SECOND-PREP-LP') = 90, 'Second source debited more than once.');
        Check(LPMgt.TotalBaseQuantity('TARGET-PREP-LP') = 20, 'Target stock duplicated or lost.');
        AssertBinQuantity('PROD-LP-ITEM', 'RAW', 90);
        AssertBinQuantity('PROD-LP-ITEM', 'RAW2', 90);
        Target.Get('TARGET-PREP-LP');
        Component.Get(Component.Status::Released, 'PROD-LP-TEST', 10000, 10000);
        if Delivered then begin
            AssertBinQuantity('PROD-LP-ITEM', 'STAGE', 0);
            AssertBinQuantity('PROD-LP-ITEM', 'PROD', 20);
            Check(Component."Qty. Picked" = 20, 'Production picked more than once.');
            Check(not Pick.Get(Pick.Type::Pick, 'PROD-PICK-TEST'), 'Delivered pick still exists.');
            Target.TestField("Bin Code", 'PROD');
            Target.TestField("Assigned Document Type", Target."Assigned Document Type"::ProdConsumption);
            Target.TestField("Assigned Document No.", 'PROD-LP-TEST');
        end else begin
            AssertBinQuantity('PROD-LP-ITEM', 'STAGE', 20);
            AssertBinQuantity('PROD-LP-ITEM', 'PROD', 0);
            Check(Component."Qty. Picked" = 0, 'Preparation picked production.');
            Pick.Get(Pick.Type::Pick, 'PROD-PICK-TEST');
            Pick.TestField("DOPSWHS Prod LP Staged", true);
            Target.TestField("Bin Code", 'STAGE');
        end;
    end;

    local procedure PreparationFixture(var Pick: Record "Warehouse Activity Header"; var TakeLine: Record "Warehouse Activity Line"; var LP: Record "DOPSWHS LP Header"; var Target: Record "DOPSWHS LP Header")
    var
        Line: Record "Warehouse Activity Line";
        Location: Record Location;
        Bin: Record Bin;
        Uom: Record "Unit of Measure";
        ItemUom: Record "Item Unit of Measure";
        Content: Record "DOPSWHS LP Line";
        Component: Record "Prod. Order Component";
        Setup: Record "Warehouse Setup";
        Tracking: Record "Item Tracking Code";
        Item: Record Item;
    begin
        Fixture(Pick, TakeLine, LP);
        if not Tracking.Get('PPTEST') then begin
            Tracking.Code := 'PPTEST';
            Tracking."Lot Warehouse Tracking" := true;
            Tracking.Insert(false);
        end;
        Item.Get(TakeLine."Item No.");
        Item."Item Tracking Code" := Tracking.Code;
        Item.Modify(false);
        Location.Get(Pick."Location Code");
        Location."Bin Mandatory" := true;
        Location."Require Pick" := true;
        Location.Modify(false);
        Bin."Location Code" := Location.Code;
        Bin.Code := 'STAGE';
        Bin.Insert(false);
        Bin.Code := 'RAW2';
        Bin.Insert(false);
        if not Uom.Get('PCS') then begin
            Uom.Code := 'PCS';
            Uom.Insert(false);
        end;
        ItemUom."Item No." := TakeLine."Item No.";
        ItemUom.Code := 'PCS';
        ItemUom."Qty. per Unit of Measure" := 1;
        ItemUom.Insert(false);
        Line.SetRange("Activity Type", Pick.Type);
        Line.SetRange("No.", Pick."No.");
        Line.FindSet(true);
        repeat
            Line."Source Document" := Line."Source Document"::"Prod. Consumption";
            Line."Whse. Document Type" := Line."Whse. Document Type"::Production;
            Line."Whse. Document No." := Line."Source No.";
            Line.Quantity := 10;
            Line."Qty. (Base)" := 10;
            Line."Qty. Outstanding" := 10;
            Line."Qty. Outstanding (Base)" := 10;
            Line."Qty. per Unit of Measure" := 1;
            Line.Modify(false);
        until Line.Next() = 0;
        TakeLine.Get(Pick.Type, Pick."No.", 10000);
        Content.Get(LP."No.", 10000);
        Content.Quantity := 100;
        Content.Modify(false);
        Target."No." := 'TARGET-PREP-LP';
        Target.Status := Target.Status::Built;
        Target."Location Code" := Location.Code;
        Target.SSCC := '987654321012345678';
        Target.Insert(false);
        Component.Get(Component.Status::Released, TakeLine."Source No.", 10000, 10000);
        Component."Qty. per Unit of Measure" := 1;
        Component."Expected Quantity" := 20;
        Component."Expected Qty. (Base)" := 20;
        Component."Remaining Quantity" := 20;
        Component."Remaining Qty. (Base)" := 20;
        Component.Modify(false);
        Setup.Get();
        Pick."Registering No. Series" := Setup."Registered Whse. Pick Nos.";
        Pick."Assigned User ID" := CopyStr(UserId(), 1, MaxStrLen(Pick."Assigned User ID"));
        Pick."DOPSWHS Main LP No." := Target."No.";
        Pick.Modify(false);
    end;

    local procedure AddPreparationStock(Line: Record "Warehouse Activity Line"; Qty: Decimal)
    var
        Entry: Record "Warehouse Entry";
        ItemEntry: Record "Item Ledger Entry";
        Content: Record "Bin Content";
        NextNo: Integer;
    begin
        ItemEntry."Entry No." := -66000 - (Line."Line No." div 10000);
        ItemEntry."Item No." := Line."Item No.";
        ItemEntry."Location Code" := Line."Location Code";
        ItemEntry."Lot No." := Line."Lot No.";
        ItemEntry."Posting Date" := WorkDate();
        ItemEntry."Entry Type" := ItemEntry."Entry Type"::Purchase;
        ItemEntry.Quantity := Qty;
        ItemEntry."Remaining Quantity" := Qty;
        ItemEntry.Open := true;
        ItemEntry.Positive := true;
        ItemEntry.Insert(false);
        Entry.LockTable();
        if Entry.FindLast() then
            NextNo := Entry."Entry No.";
        Entry.Init();
        Entry."Entry No." := NextNo + 1;
        Entry."Location Code" := Line."Location Code";
        Entry."Bin Code" := Line."Bin Code";
        Entry."Item No." := Line."Item No.";
        Entry."Unit of Measure Code" := Line."Unit of Measure Code";
        Entry."Qty. per Unit of Measure" := 1;
        Entry."Lot No." := Line."Lot No.";
        Entry.Quantity := Qty;
        Entry."Qty. (Base)" := Qty;
        Entry.Insert(false);
        Content."Location Code" := Line."Location Code";
        Content."Bin Code" := Line."Bin Code";
        Content."Item No." := Line."Item No.";
        Content."Unit of Measure Code" := Line."Unit of Measure Code";
        Content."Qty. per Unit of Measure" := 1;
        Content.Insert(false);
    end;

    local procedure AssertBinQuantity(ItemNo: Code[20]; BinCode: Code[20]; Expected: Decimal)
    var
        Entry: Record "Warehouse Entry";
    begin
        Entry.SetRange("Location Code", 'PPTEST');
        Entry.SetRange("Item No.", ItemNo);
        Entry.SetRange("Bin Code", BinCode);
        Entry.CalcSums("Qty. (Base)");
        Check(Entry."Qty. (Base)" = Expected, StrSubstNo('Wrong stock in %1: expected %2 actual %3', BinCode, Expected, Entry."Qty. (Base)"));
    end;

    [Test]
    procedure CleanupProductionPalletFixtures()
    begin
        CleanupFixture();
    end;

    local procedure CleanupFixture()
    var
        Location: Record Location;
        Bin: Record Bin;
        Content: Record "Bin Content";
        Entry: Record "Warehouse Entry";
        Activity: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Ledger: Record "DOPSWHS LP Movement Ledger";
        Component: Record "Prod. Order Component";
        ProdOrder: Record "Production Order";
        Item: Record Item;
        Lot: Record "Lot No. Information";
        Reservation: Record "Reservation Entry";
        TrackingSpec: Record "Tracking Specification";
        WhseTracking: Record "Whse. Item Tracking Line";
        ItemEntry: Record "Item Ledger Entry";
        Tracking: Record "Item Tracking Code";
        BinType: Record "Bin Type";
        ItemUom: Record "Item Unit of Measure";
    begin
        // Exact, synthetic fixture IDs only; no customer stock is selected.
        Reservation.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); Reservation.DeleteAll(false);
        TrackingSpec.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); TrackingSpec.DeleteAll(false);
        WhseTracking.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); WhseTracking.DeleteAll(false);
        ItemEntry.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); ItemEntry.DeleteAll(false);
        Entry.SetRange("Location Code", 'PPTEST'); Entry.DeleteAll(false);
        Content.SetRange("Location Code", 'PPTEST'); Content.DeleteAll(false);
        ActivityLine.SetRange("Location Code", 'PPTEST'); ActivityLine.DeleteAll(false);
        Activity.SetRange("Location Code", 'PPTEST'); Activity.DeleteAll(false);
        LP.SetFilter("No.", 'PROD-LP-READY|SECOND-PROD-LP|SECOND-PREP-LP|TARGET-PREP-LP');
        if LP.FindSet() then repeat
            LPLine.SetRange("LP No.", LP."No."); LPLine.DeleteAll(false);
            Ledger.SetRange("LP No.", LP."No."); Ledger.DeleteAll(false);
        until LP.Next() = 0;
        LP.DeleteAll(false);
        Bin.SetRange("Location Code", 'PPTEST'); Bin.DeleteAll(false);
        Location.SetRange(Code, 'PPTEST'); Location.DeleteAll(false);
        Component.SetRange("Prod. Order No.", 'PROD-LP-TEST'); Component.DeleteAll(false);
        ProdOrder.SetRange("No.", 'PROD-LP-TEST'); ProdOrder.DeleteAll(false);
        ItemUom.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); ItemUom.DeleteAll(false);
        Lot.SetFilter("Item No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); Lot.DeleteAll(false);
        Item.SetFilter("No.", 'PROD-LP-ITEM|PROD-LP-ITEM2'); Item.DeleteAll(false);
        Tracking.SetRange(Code, 'PPTEST'); Tracking.DeleteAll(false);
        BinType.SetRange(Code, 'PPTEST'); BinType.DeleteAll(false);
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
        CleanupFixture();
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
