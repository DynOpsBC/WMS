// Kitoko (20 Eki 2026): önizleme yalnız ÖRNEK verili ZPL'i labelary.com'a gönderir
// (gerçek ürün/raf/müşteri verisi asla gönderilmez) ve dönen PNG'yi indirir.
codeunit 72468 "DOPSWHS Label Layout Preview"
{
    Access = Public;

    procedure ShowPreview(LayoutCode: Code[20])
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        TempBlob: Codeunit "Temp Blob";
        PngStream: InStream;
        Zpl: Text;
        FileName: Text;
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
    begin
        Zpl := Engine.BuildSampleZpl(LayoutCode);
        Engine.LayoutSize(LayoutCode, WidthMm, HeightMm, Dpi);
        ClearLastError();
        if not TryRender(Zpl, WidthMm, HeightMm, Dpi, TempBlob) then begin
            Message('Önizleme alınamadı (labelary.com): %1\Ağ erişimini ve uzantının "HttpClient isteklerine izin ver" ayarını kontrol edin. "ZPL Göster" ile ZPL yine incelenebilir.', GetLastErrorText());
            exit;
        end;
        TempBlob.CreateInStream(PngStream);
        FileName := 'etiket-onizleme.png';
        DownloadFromStream(PngStream, 'Etiket Önizleme', '', 'PNG (*.png)|*.png', FileName);
    end;

    /// <summary>Labelary sizes are in inches and the resolution in dots per mm (6/8/12/24).</summary>
    procedure PreviewUrl(WidthMm: Decimal; HeightMm: Decimal; Dpi: Integer): Text
    var
        Dpmm: Integer;
    begin
        case true of
            Dpi <= 175:
                Dpmm := 6;
            Dpi <= 250:
                Dpmm := 8;
            Dpi <= 450:
                Dpmm := 12;
            else
                Dpmm := 24;
        end;
        exit('https://api.labelary.com/v1/printers/' + Format(Dpmm) + 'dpmm/labels/' +
            Format(Round(WidthMm / 25.4, 0.01), 0, 9) + 'x' + Format(Round(HeightMm / 25.4, 0.01), 0, 9) + '/0/');
    end;

    [TryFunction]
    local procedure TryRender(Zpl: Text; WidthMm: Decimal; HeightMm: Decimal; Dpi: Integer; var TempBlob: Codeunit "Temp Blob")
    var
        Client: HttpClient;
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        Response: HttpResponseMessage;
        ResponseStream: InStream;
        OutStr: OutStream;
    begin
        Content.WriteFrom(Zpl);
        Content.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');
        Client.DefaultRequestHeaders().Add('Accept', 'image/png');
        Client.Timeout(15000);
        if not Client.Post(PreviewUrl(WidthMm, HeightMm, Dpi), Content, Response) then
            Error('Sunucuya bağlanılamadı.');
        if not Response.IsSuccessStatusCode() then
            Error('Labelary hata döndürdü (HTTP %1).', Response.HttpStatusCode());
        Response.Content().ReadAs(ResponseStream);
        TempBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, ResponseStream);
    end;
}
