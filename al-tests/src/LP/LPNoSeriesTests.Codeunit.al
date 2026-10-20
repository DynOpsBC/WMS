codeunit 72146 "DOPSWHS LP No. Series Tests"
{
    Subtype = Test;

    // BADE (20 Eki 2026): BS Üretim hammadde LP'leri HLP, üretim çıkışı YLP.
    [Test]
    procedure BuildWithSeriesUsesThatSeries()
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        LPMgt.Build('PALLET-EUR', 'BLUE', 'PICK', 'YLPT', LP);
        Assert.AreEqual('YLPT000001', LP."No.", 'Production output LP must use the given series.');
    end;

    [Test]
    procedure BuildWithoutSeriesUsesCompanyLpSeries()
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        LPMgt.Build('PALLET-EUR', 'BLUE', 'PICK', LP);
        Assert.AreEqual('HLPT000001', LP."No.", 'Other LPs keep the company LP No. Series.');
    end;

    [Test]
    procedure ProdOutputSeriesComesFromSetup()
    var
        Setup: Record "DOPSWHS Setup";
        LPSeriesSetup: Codeunit "DOPSWHS LP Series Setup";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        Assert.AreEqual('', LPSeriesSetup.ProdOutputLpNoSeries(), 'Blank setup keeps the old behaviour.');
        Setup.Get('');
        Setup."Prod. Output LP No. Series" := 'YLPT';
        Setup.Modify(true);
        Assert.AreEqual('YLPT', LPSeriesSetup.ProdOutputLpNoSeries(), 'Setup series must be returned.');
    end;

    [Test]
    procedure NextFreeLpNoSkipsExistingNumbers()
    var
        LP: Record "DOPSWHS LP Header";
        LPSeriesSetup: Codeunit "DOPSWHS LP Series Setup";
        Assert: Codeunit "Library Assert";
    begin
        Seed();
        LP.Init();
        LP."No." := 'YLPT000001';
        LP.Insert(false);
        Assert.AreEqual('YLPT000002', LPSeriesSetup.NextFreeLpNo('YLPT'), 'An LP restored ahead of the series must be skipped.');
    end;

    local procedure Seed()
    var
        Helper: Codeunit "DOPSWHS Test Helper";
        SetupWizard: Codeunit "DOPSWHS Setup Wizard";
        Setup: Record "DOPSWHS Setup";
    begin
        Helper.ResetSetup();
        SeedNoSeries('HLPT', 'HLPT000001', 'HLPT999999');
        SeedNoSeries('YLPT', 'YLPT000001', 'YLPT999999');
        SeedNoSeries('SSCC', '3000000001', '3999999999');
        Setup := Helper.EnsureSetup();
        Setup."LP No. Series" := 'HLPT';
        Setup."SSCC No. Series" := 'SSCC';
        Setup."Prod. Output LP No. Series" := '';
        Setup.Modify(true);
        SeedLocationBin('BLUE', 'PICK');
        SetupWizard.SeedDefaultLPTemplates();
    end;

    local procedure SeedNoSeries(Code: Code[20]; StartNo: Code[20]; EndNo: Code[20])
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(Code) then begin
            NoSeries.Init();
            NoSeries.Code := Code;
            NoSeries."Default Nos." := true;
            NoSeries.Insert(true);
        end;
        if not NoSeriesLine.Get(Code, 10000) then begin
            NoSeriesLine.Init();
            NoSeriesLine."Series Code" := Code;
            NoSeriesLine."Line No." := 10000;
            NoSeriesLine."Starting No." := StartNo;
            NoSeriesLine."Ending No." := EndNo;
            NoSeriesLine.Insert(true);
        end;
    end;

    local procedure SeedLocationBin(LocationCode: Code[10]; BinCode: Code[20])
    var
        Location: Record Location;
        Bin: Record Bin;
    begin
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not Bin.Get(LocationCode, BinCode) then begin
            Bin.Init();
            Bin."Location Code" := LocationCode;
            Bin.Code := BinCode;
            Bin.Insert(true);
        end;
    end;
}
