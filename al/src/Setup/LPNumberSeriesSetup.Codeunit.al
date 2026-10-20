codeunit 72057 "DOPSWHS LP Series Setup"
{
    Access = Internal;
    Permissions =
        tabledata "DOPSWHS Setup" = RIM,
        tabledata "No. Series" = RIM,
        tabledata "No. Series Line" = RIM;

    procedure EnsureLpNoSeries(): Code[20]
    var
        Setup: Record "DOPSWHS Setup";
        SeriesCode: Code[20];
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup."Primary Key" := '';
            Setup.Insert(true);
        end;

        if Setup."LP No. Series" <> '' then
            exit(Setup."LP No. Series");

        SeriesCode := 'AWMS-LP';
        EnsureDefaultLpSeries(SeriesCode);
        Setup.Validate("LP No. Series", SeriesCode);
        Setup.Modify(true);
        exit(SeriesCode);
    end;

    /// <summary>
    /// Seriden kullanılmamış ilk LP numarasını verir. Kopyalanmış/geri yüklenmiş
    /// şirkette LP kayıtları serinin ilerisinde olabilir; dolu numaralar atlanır.
    /// </summary>
    procedure NextFreeLpNo(SeriesCode: Code[20]): Code[20]
    var
        ExistingLP: Record "DOPSWHS LP Header";
        NoSeries: Codeunit "No. Series";
        LpNo: Code[20];
        Attempts: Integer;
    begin
        repeat
            LpNo := NoSeries.GetNextNo(SeriesCode);
            Attempts += 1;
            if Attempts > 10000 then
                Error(
                    '%1 numara serisinde kullanılabilir LP numarası bulunamadı. Numara serisinin son kullanılan değerini kontrol edin.',
                    SeriesCode);
        until not ExistingLP.Get(LpNo);
        exit(LpNo);
    end;

    /// <summary>Üretim çıkışı LP serisi; tanımlı değilse '' (şirketin LP serisi kullanılır).</summary>
    procedure ProdOutputLpNoSeries(): Code[20]
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if Setup.Get('') then
            exit(Setup."Prod. Output LP No. Series");
        exit('');
    end;

    procedure EnsureSsccNoSeries(): Code[20]
    var
        Setup: Record "DOPSWHS Setup";
        SeriesCode: Code[20];
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup."Primary Key" := '';
            Setup.Insert(true);
        end;

        if Setup."SSCC No. Series" <> '' then
            exit(Setup."SSCC No. Series");

        SeriesCode := 'AWMS-SSCC';
        EnsureDefaultSsccSeries(SeriesCode);
        Setup.Validate("SSCC No. Series", SeriesCode);
        Setup.Modify(true);
        exit(SeriesCode);
    end;

    local procedure EnsureDefaultLpSeries(SeriesCode: Code[20])
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(SeriesCode) then begin
            NoSeries.Init();
            NoSeries.Code := SeriesCode;
            NoSeries.Description := 'LP Numbering';
            NoSeries."Default Nos." := true;
            NoSeries."Manual Nos." := false;
            NoSeries.Insert(true);
        end;

        NoSeriesLine.SetRange("Series Code", SeriesCode);
        if not NoSeriesLine.IsEmpty() then
            exit;

        NoSeriesLine.Init();
        NoSeriesLine."Series Code" := SeriesCode;
        NoSeriesLine."Line No." := 10000;
        NoSeriesLine."Starting No." := 'LP000001';
        NoSeriesLine."Ending No." := 'LP999999';
        NoSeriesLine."Increment-by No." := 1;
        NoSeriesLine."Starting Date" := 0D;
        NoSeriesLine.Insert(true);
    end;

    local procedure EnsureDefaultSsccSeries(SeriesCode: Code[20])
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(SeriesCode) then begin
            NoSeries.Init();
            NoSeries.Code := SeriesCode;
            NoSeries.Description := 'SSCC Numbering';
            NoSeries."Default Nos." := true;
            NoSeries."Manual Nos." := false;
            NoSeries.Insert(true);
        end;

        NoSeriesLine.SetRange("Series Code", SeriesCode);
        if not NoSeriesLine.IsEmpty() then
            exit;

        NoSeriesLine.Init();
        NoSeriesLine."Series Code" := SeriesCode;
        NoSeriesLine."Line No." := 10000;
        NoSeriesLine."Starting No." := '0000000001';
        NoSeriesLine."Ending No." := '9999999999';
        NoSeriesLine."Increment-by No." := 1;
        NoSeriesLine."Starting Date" := 0D;
        NoSeriesLine.Insert(true);
    end;
}
