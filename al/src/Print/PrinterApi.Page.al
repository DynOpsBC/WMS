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
                field(tokenIssuedAt; Rec."Token Issued At") { Caption = 'tokenIssuedAt'; }
                field(comment; Rec.Comment) { Caption = 'comment'; }
            }
        }
    }

    [ServiceEnabled]
    procedure generateToken(): Text
    var
        Client: Codeunit "DOPSWHS Self-Hosted Print Client";
    begin
        exit(Client.RotateToken(Rec."Code"));
    end;

    [ServiceEnabled]
    procedure testPrint(): Integer
    var
        Client: Codeunit "DOPSWHS Self-Hosted Print Client";
    begin
        exit(Client.EnqueueSelfTest(Rec."Code"));
    end;
}
