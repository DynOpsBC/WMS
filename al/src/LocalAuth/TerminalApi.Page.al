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
}
