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

    [Test]
    procedure BcReportAndTerminalShareLabelValues()
    var
        ParentCategory: Record "Item Category";
        ChildCategory: Record "Item Category";
        WarehouseClass: Record "Warehouse Class";
        Item: Record Item;
        LP: Record "DOPSWHS LP Header" temporary;
        LPLine: Record "DOPSWHS LP Line" temporary;
        Builder: Codeunit "DOPSWHS MTE Zpl Builder";
        Values: Dictionary of [Text, Text];
    begin
        // BADE (8 Eki 2026): BC "Tüm LP MTE Etiketleri" kategori için alt kategoriyi
        // (Şişe), depolama ve doküman için U.Y basıyordu; terminal PRİMER AMBALAJ,
        // ODA SIC. ve ET011 basıyor. Rapor artık bu değerleri buradan alır.
        ParentCategory.Code := 'MTE-PRIMER';
        ParentCategory.Description := 'Primer ambalaj';
        ParentCategory.Insert(false);
        ChildCategory.Code := 'MTE-SISE';
        ChildCategory.Description := 'Şişe';
        ChildCategory."Parent Category" := ParentCategory.Code;
        ChildCategory.Insert(false);
        WarehouseClass.Code := 'MTE-ODA';
        WarehouseClass.Description := 'ODA SIC. (15-25 °C)';
        WarehouseClass.Insert(false);
        Item."No." := 'MTE-SHARED';
        Item.Description := 'ŞİŞE - CAM ŞEFFAF 10 ML';
        Item."Item Category Code" := ChildCategory.Code;
        Item."Warehouse Class Code" := WarehouseClass.Code;
        Item.Insert(false);

        LP."No." := 'MTE-SHARED';
        LPLine."Item No." := Item."No.";
        LPLine.Quantity := 5000;
        Builder.GetLabelValues(LP, LPLine, '', Values);

        Check(Values.Get('Category') = ParentCategory.Code, 'The label must print the parent category, not the leaf.');
        Check(Values.Get('StorageCondition') = WarehouseClass.Description, 'The storage condition comes from the warehouse class.');
        Check(Values.Get('ItemName') = Item.Description, 'Without a vendor item name the item description is printed.');
        Check(Values.Get('DocumentNo') = 'ET011', 'The controlled form number must be printed.');
        Check(Values.Get('RevisionDate') = '24.07.2026', 'The controlled form revision date must be printed.');
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
