codeunit 72381 "DOPSWHS DKC EWaybill Printer"
{
    Access = Internal;

    procedure Print(ShipmentNo: Code[20]; PdfUrl: Text; PrinterId: Code[50]): Integer
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        TempBlob: Codeunit "Temp Blob";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceStream: InStream;
        HeaderStream: InStream;
        PrintStream: InStream;
        BufferStream: OutStream;
        Magic: Text[5];
    begin
        ValidateBlobUrl(PdfUrl);
        Dispatcher.EnsureDocumentPrinter(PrinterId, Enum::"DOPSWHS IWX Report Usage"::PostedShipment);
        if not Client.Get(PdfUrl, Response) then
            Error('%1 e-belge PDF dosyasına erişilemedi.', ShipmentNo);
        if not Response.IsSuccessStatusCode() then
            Error('%1 e-belge PDF dosyası alınamadı (HTTP %2).', ShipmentNo, Response.HttpStatusCode());
        if not Response.Content().ReadAs(SourceStream) then
            Error('%1 e-belge PDF içeriği okunamadı.', ShipmentNo);
        TempBlob.CreateOutStream(BufferStream);
        CopyStream(BufferStream, SourceStream);
        if (TempBlob.Length() < 5) or (TempBlob.Length() > 50 * 1024 * 1024) then
            Error('%1 e-belge PDF boyutu geçersiz.', ShipmentNo);
        TempBlob.CreateInStream(HeaderStream);
        HeaderStream.ReadText(Magic, 5);
        if Magic <> '%PDF-' then
            Error('%1 için indirilen dosya PDF değil.', ShipmentNo);
        TempBlob.CreateInStream(PrintStream);
        exit(Dispatcher.PrintExternalPdf(ShipmentNo, PrinterId, PrintStream));
    end;

    local procedure ValidateBlobUrl(PdfUrl: Text)
    var
        AuthorityAndPath: Text;
        Host: Text;
        Suffix: Text;
        SlashPos: Integer;
    begin
        if CopyStr(LowerCase(PdfUrl), 1, 8) <> 'https://' then
            Error('E-belge PDF bağlantısı HTTPS olmalı.');
        AuthorityAndPath := CopyStr(PdfUrl, 9);
        SlashPos := StrPos(AuthorityAndPath, '/');
        if SlashPos < 2 then
            Error('E-belge PDF bağlantısı geçersiz.');
        Host := LowerCase(CopyStr(AuthorityAndPath, 1, SlashPos - 1));
        Suffix := '.blob.core.windows.net';
        if (StrPos(Host, '@') <> 0) or (StrPos(Host, ':') <> 0) or
           (StrLen(Host) <= StrLen(Suffix)) or
           (CopyStr(Host, StrLen(Host) - StrLen(Suffix) + 1) <> Suffix)
        then
            Error('E-belge PDF yalnız güvenilir Azure Blob adresinden yazdırılabilir.');
    end;
}
