codeunit 72218 "DOPSWHS Lot Serial Generator"
{
    // Otomatik Lot/Seri numarası üretimi — müşteri isteği (WI "auto lot/serial").
    // Setup'ta ilgili No. Series tanımlıysa numara üretir; tanımlı değilse boş
    // döner (elle giriş). SSCCGenerator ile aynı No. Series desenini kullanır.
    Access = Public;

    procedure GenerateLotNo(): Code[50]
    var
        Setup: Record "DOPSWHS Setup";
        NoSeries: Codeunit "No. Series";
    begin
        Setup.Get('');
        if Setup."Lot No. Series" = '' then
            exit('');
        exit(CopyStr(NoSeries.GetNextNo(Setup."Lot No. Series"), 1, 50));
    end;

    procedure GenerateSerialNo(): Code[50]
    var
        Setup: Record "DOPSWHS Setup";
        NoSeries: Codeunit "No. Series";
    begin
        Setup.Get('');
        if Setup."Serial No. Series" = '' then
            exit('');
        exit(CopyStr(NoSeries.GetNextNo(Setup."Serial No. Series"), 1, 50));
    end;
}
