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
    procedure login(username: Code[20]; pin: Text): Text
    var
        Auth: Codeunit "DOPSWHS Local Auth Mgmt";
    begin
        exit(Auth.VerifyTerminal(Rec.Code, username, pin));
    end;

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
        if LocalUser.Disabled or not LocalUser."PIN Login" or
           ((LocalUser."Terminal Code" <> Terminal.Code) and not LocalUser."Terminal Admin") then
            Error('Kullanıcı bu terminalde etkin değil.');
        Printer.Get(printerCode);
        if not Printer.Active then
            Error('Yazıcı pasif.');
        case usage of
            'LpLabel':
                begin
                    if Printer.Format <> Printer.Format::ZPL then
                        Error('Etiket yazıcısı ZPL formatında olmalı.');
                    Terminal.Validate("Label Printer Code", Printer.Code);
                end;
            'Document':
                begin
                    if Printer.Format <> Printer.Format::PDF then
                        Error('Belge yazıcısı PDF formatında olmalı.');
                    Terminal.Validate("Document Printer Code", Printer.Code);
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
