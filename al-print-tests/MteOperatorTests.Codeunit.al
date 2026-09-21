codeunit 72181 "DOPSWHS MTE Operator Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure ZplUsesPinNameInsteadOfServiceAccount()
    var
        LP: Record "DOPSWHS LP Header" temporary;
        LPLine: Record "DOPSWHS LP Line" temporary;
        Builder: Codeunit "DOPSWHS MTE Zpl Builder";
        Encoder: Codeunit "DOPSWHS ZPL Encoder";
        Zpl: Text;
    begin
        LP."No." := 'MTE-OP-TEST';
        LP."Built By User" := 'DYNOPS';
        LPLine.Quantity := 1;
        Zpl := Builder.Build(LP, LPLine, '{"operatorDisplayName":"Bülent Abatay"}');
        Check(StrPos(Zpl, Encoder.EncodeFieldData('Bülent Abatay')) > 0, 'The PIN operator was not printed.');
        Check(StrPos(Zpl, Encoder.EncodeFieldData('DYNOPS')) = 0, 'The service account leaked onto the MTE.');
    end;

    [Test]
    procedure ExplicitInspectorWins()
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Check(
            Dispatcher.ResolveMteInspectorEmployeeNo('{"inspectorEmployeeNo":"MTE-EXPLICIT","operatorDisplayName":"PIN Operator"}') = 'MTE-EXPLICIT',
            'The explicitly selected inspector was replaced.');
    end;

    [Test]
    procedure PdfMapsOperatorOnlyInCurrentCompany()
    var
        Employee: Record Employee;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Options: JsonObject;
        OptionsJson: Text;
    begin
        Employee.Init();
        Employee."No." := 'MTE-OP-TEST';
        Employee."First Name" := 'MTE test';
        Employee."Last Name" := CopyStr(Format(CreateGuid()), 1, MaxStrLen(Employee."Last Name"));
        Employee.Status := Employee.Status::Active;
        Employee.Insert(false);
        Options.Add('operatorDisplayName', Employee."First Name" + ' ' + Employee."Last Name");
        Options.WriteTo(OptionsJson);
        Check(Dispatcher.ResolveMteInspectorEmployeeNo(OptionsJson) = Employee."No.", 'The current-company employee was not resolved.');
        Employee."No." := 'MTE-OP-TEST-2';
        Employee.Insert(false);
        asserterror Dispatcher.ResolveMteInspectorEmployeeNo(OptionsJson);
        Check(StrPos(GetLastErrorText(), 'birden fazla') > 0, 'Ambiguous employee names must fail.');
    end;

    [Test]
    procedure MissingPdfEmployeeDoesNotFallBackToBcUser()
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Options: JsonObject;
        OptionsJson: Text;
    begin
        Options.Add('operatorDisplayName', Format(CreateGuid()));
        Options.WriteTo(OptionsJson);
        asserterror Dispatcher.ResolveMteInspectorEmployeeNo(OptionsJson);
        Check(StrPos(GetLastErrorText(), 'çalışan bulunamadı') > 0, 'A missing employee must not print the service account.');
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
