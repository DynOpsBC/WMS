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

    /// <summary>
    /// Kitoko (21 Eki 2026): renders ZPL to PNG through labelary.com for the label
    /// designer. Callers must pass sample-data ZPL only. False = failed (GetLastErrorText).
    /// </summary>
    procedure TryRenderPng(Zpl: Text; WidthMm: Decimal; HeightMm: Decimal; Dpi: Integer; var TempBlob: Codeunit "Temp Blob"): Boolean
    begin
        ClearLastError();
        exit(TryRender(Zpl, WidthMm, HeightMm, Dpi, TempBlob));
    end;

    /// <summary>
    /// Labelary sizes are in inches and the resolution in dots per mm (6/8/12/24).
    /// Kitoko (23 Eki 2026): Labelary renders floor(inches x nominal dpi) dots
    /// (8 dpmm = 203, 12 dpmm = 304, measured). The old 2-decimal inches gave
    /// 3.15 x 1.57 = 639 x 318 dots for 80 x 40 mm, so the preview itself cut the
    /// last dot column and two rows. The size is now (dots + 0.5) / nominal dpi,
    /// which yields exactly the ^PW x ^LL of the label (640 x 320).
    /// </summary>
    procedure PreviewUrl(WidthMm: Decimal; HeightMm: Decimal; Dpi: Integer): Text
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Dpmm: Integer;
        Nominal: Decimal;
    begin
        case true of
            Dpi <= 175:
                begin
                    Dpmm := 6;
                    Nominal := 152;
                end;
            Dpi <= 250:
                begin
                    Dpmm := 8;
                    Nominal := 203;
                end;
            Dpi <= 450:
                begin
                    Dpmm := 12;
                    Nominal := 304;
                end;
            else begin
                Dpmm := 24;
                Nominal := 608.8;
            end;
        end;
        exit('https://api.labelary.com/v1/printers/' + Format(Dpmm) + 'dpmm/labels/' +
            InchText(Engine.MmToDots(WidthMm, Dpi), Nominal) + 'x' + InchText(Engine.MmToDots(HeightMm, Dpi), Nominal) + '/0/');
    end;

    local procedure InchText(Dots: Integer; Nominal: Decimal): Text
    begin
        exit(Format(Round((Dots + 0.5) / Nominal, 0.0001), 0, 9));
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
