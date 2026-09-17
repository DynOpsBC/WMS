page 72323 "DOPSWHS Create PIN User"
{
    PageType = StandardDialog;
    Caption = 'Kullanıcı Oluştur';
    layout
    {
        area(Content)
        {
            group(User)
            {
                ShowCaption = false;
                field(Name; OperatorName) { Caption = 'Ad Soyad'; ApplicationArea = All; }
                field(PIN; PinText) { Caption = '4 Haneli PIN'; ExtendedDatatype = Masked; ApplicationArea = All; }
            }
        }
    }
    trigger OnOpenPage()
    begin
        if Manager then
            CurrPage.Caption('Yönetici Oluştur');
    end;
    trigger OnQueryClosePage(CloseAction: Action): Boolean
    begin
        if CloseAction = Action::OK then begin
            if OperatorName.Trim() = '' then
                Error('Ad soyad girin.');
            Auth.ValidatePin(PinText);
        end;
        exit(true);
    end;
    procedure SetTerminal(Value: Code[20])
    begin
        TerminalCode := Value;
    end;
    procedure SetManager()
    begin
        Manager := true;
    end;
    procedure CreateUser()
    begin
        if Manager then
            Auth.CreateTerminalAdmin(OperatorName, PinText)
        else
            Auth.CreateTerminalUser(TerminalCode, OperatorName, PinText);
        Clear(PinText);
    end;
    var
        Manager: Boolean;
        TerminalCode: Code[20];
        OperatorName: Text[100];
        PinText: Text;
        Auth: Codeunit "DOPSWHS Local Auth Mgmt";
}
