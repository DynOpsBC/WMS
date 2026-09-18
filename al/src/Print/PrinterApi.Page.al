page 72289 "DOPSWHS Printer API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'printer';
    EntitySetName = 'printers';
    SourceTable = "DOPSWHS Printer";
    DelayedInsert = true;
    ODataKeyFields = "Code";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(format; Rec."Format") { Caption = 'format'; }
                field(printerHandle; Rec."Printer Handle") { Caption = 'printerHandle'; }
                field(hostname; Rec.Hostname) { Caption = 'hostname'; }
                field(port; Rec.Port) { Caption = 'port'; }
                field(active; Rec.Active) { Caption = 'active'; }
                field(defaultCopies; Rec."Default Copies") { Caption = 'defaultCopies'; }
                field(lastSeenAt; Rec."Last Seen At") { Caption = 'lastSeenAt'; }
                field(lastAgentId; Rec."Last Agent ID") { Caption = 'lastAgentId'; }
                field(stationId; Rec."Station ID") { Caption = 'stationId'; }
                field(discoveredByAgent; Rec."Discovered by Agent") { Caption = 'discoveredByAgent'; }
                field(agentStatus; Rec."Agent Status") { Caption = 'agentStatus'; }
                field(lastStatusAt; Rec."Last Status At") { Caption = 'lastStatusAt'; }
                field(lastStatusMessage; Rec."Last Status Message") { Caption = 'lastStatusMessage'; }
                field(agentVersion; Rec."Agent Version") { Caption = 'agentVersion'; }
                field(agentDefaultPrinter; Rec."Agent Default Printer") { Caption = 'agentDefaultPrinter'; }
                field(tokenIssuedAt; Rec."Token Issued At") { Caption = 'tokenIssuedAt'; }
                field(enableBcReports; Rec."Enable BC Reports") { Caption = 'enableBcReports'; }
                field(paperWidthMm; Rec."Paper Width (mm)") { Caption = 'paperWidthMm'; }
                field(paperHeightMm; Rec."Paper Height (mm)") { Caption = 'paperHeightMm'; }
                field(comment; Rec.Comment) { Caption = 'comment'; }
            }
        }
    }

    [ServiceEnabled]
    procedure generateToken(): Text
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
    begin
        exit(Client.RotateToken(Rec."Code"));
    end;

    [ServiceEnabled]
    procedure testPrint(): Integer
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
    begin
        exit(Client.EnqueueSelfTest(Rec."Code"));
    end;

    [ServiceEnabled]
    procedure printNameLabel(): Integer
    var
        Client: Codeunit "DOPSWHS Self-Host Print Client";
        Encoder: Codeunit "DOPSWHS ZPL Encoder";
        Name: Text;
        Zpl: Text;
    begin
        Rec.TestField(Active, true);
        if Rec.Format <> Rec.Format::ZPL then
            Error('Yazıcı ad etiketi için ZPL etiket yazıcısı seçin.');
        Name := Rec.Description;
        if Name = '' then
            Name := Rec."Printer Handle";
        if Name = '' then
            Name := Rec.Code;
        Zpl := '^XA^CI28^PW400^LL240' +
            '^FO10,24^A0N,72,72^FB380,2,4,C^FH_^FD' + Encoder.EncodeFieldData(Name) +
            '^FS^FO10,210^A0N,16,16^FB380,1,0,C^FH_^FD' + Encoder.EncodeFieldData(Rec.Code) + '^FS^PQ1^XZ';
        exit(Client.Enqueue('PRINTER-NAME', Rec.Code, Rec.Format, Zpl, 1));
    end;

    [ServiceEnabled]
    procedure printBarcodeTest(barcodeValue: Text; copies: Integer): Integer
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        exit(Dispatcher.PrintBarcodeTest(Rec."Code", barcodeValue, copies));
    end;

}
