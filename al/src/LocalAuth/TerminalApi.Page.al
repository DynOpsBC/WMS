page 72325 "DOPSWHS Terminal API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'wmsTerminal';
    EntitySetName = 'wmsTerminals';
    SourceTable = "DOPSWHS WMS Terminal";
    ODataKeyFields = Code;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Permissions = tabledata "DOPSWHS WMS Terminal" = m;

    layout
    {
        area(Content)
        {
            repeater(Terminals)
            {
                field(code; Rec.Code) { }
                field(disabled; Rec.Disabled) { }
                field(labelPrinterCode; Rec."Label Printer Code") { }
                field(documentPrinterCode; Rec."Document Printer Code") { }
            }
        }
    }

    [ServiceEnabled]
    procedure selectPrinter(username: Code[20]; usage: Text; printerCode: Code[20]): Text
    var
        Terminal: Record "DOPSWHS WMS Terminal";
        LocalUser: Record "DOPSWHS Local User";
        Printer: Record "DOPSWHS Printer";
        Result: JsonObject;
        ResultText: Text;
    begin
        Terminal.LockTable();
        Terminal.Get(Rec.Code);
        if Terminal.Disabled then
            Error('Terminal devre dışı.');
        LocalUser.Get(username);
        if LocalUser.Disabled then
            Error('Kullanıcı devre dışı.');

        if printerCode <> '' then begin
            Printer.Get(printerCode);
            if not Printer.Active then
                Error('Yazıcı pasif.');
        end;

        case usage of
            'LpLabel':
                begin
                    if (printerCode <> '') and (Printer.Format <> Printer.Format::ZPL) then
                        Error('Etiket yazıcısı ZPL formatında olmalı.');
                    Terminal.Validate("Label Printer Code", printerCode);
                end;
            'Document':
                begin
                    if (printerCode <> '') and (Printer.Format <> Printer.Format::PDF) then
                        Error('Belge yazıcısı PDF formatında olmalı.');
                    Terminal.Validate("Document Printer Code", printerCode);
                end;
            else
                Error('Geçersiz yazıcı kullanım türü.');
        end;
        Terminal.Modify(true);

        Result.Add('terminalCode', Terminal.Code);
        Result.Add('labelPrinterCode', Terminal."Label Printer Code");
        Result.Add('documentPrinterCode', Terminal."Document Printer Code");
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;
}
