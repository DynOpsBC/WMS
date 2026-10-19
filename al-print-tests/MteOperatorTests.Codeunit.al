codeunit 72181 "DOPSWHS MTE Operator Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
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
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ExplicitInspectorWins()
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Check(
            Dispatcher.ResolveMteInspectorEmployeeNo('{"inspectorEmployeeNo":"MTE-EXPLICIT","operatorDisplayName":"PIN Operator"}') = 'MTE-EXPLICIT',
            'The explicitly selected inspector was replaced.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
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
    [TransactionModel(TransactionModel::AutoRollback)]
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
    [TransactionModel(TransactionModel::AutoRollback)]
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

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BcReportPrintsOneLabelPerProductOnMixedPallet()
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        TempBlob: Codeunit "Temp Blob";
        LpRef: RecordRef;
        OutStr: OutStream;
        InStr: InStream;
        DataSet: Text;
        Chunk: Text;
    begin
        // BADE (9 Eki 2026): LP001645 (8 ürün) için "Tüm LP MTE Etiketleri"
        // hep ilk ürünü basıyordu. Her ürün/lot grubu ayrı etiket olmalı.
        Item."No." := 'MTE-MIX-A';
        Item.Description := 'Karma palet ürün A';
        Item.Insert(false);
        Clear(Item);
        Item."No." := 'MTE-MIX-B';
        Item.Description := 'Karma palet ürün B';
        Item.Insert(false);
        LP."No." := 'MTE-MIX-TEST';
        LP.Status := LP.Status::Built;
        LP.Insert(false);
        AddLine(LP."No.", 10000, 'MTE-MIX-A', 'MIXLOT-A', 3);
        AddLine(LP."No.", 20000, 'MTE-MIX-A', 'MIXLOT-A', 2);
        AddLine(LP."No.", 30000, 'MTE-MIX-B', 'MIXLOT-B', 4);

        LP.SetRange("No.", LP."No.");
        LpRef.GetTable(LP);
        TempBlob.CreateOutStream(OutStr);
        Check(Report.SaveAs(Report::"DOPSWHS MTE LP Report", '', ReportFormat::Xml, OutStr, LpRef), 'The MTE report did not run.');
        TempBlob.CreateInStream(InStr);
        while not InStr.EOS() do begin
            InStr.ReadText(Chunk);
            DataSet += Chunk;
        end;

        Check(CountOf(DataSet, 'MTE-MIX-A') >= 1, 'Product A label is missing.');
        Check(CountOf(DataSet, 'MTE-MIX-B') >= 1, 'Product B label is missing (only the first product was printed).');
        Check(CountOf(DataSet, 'MIXLOT-A') = 1, StrSubstNo('Product A split lines must share one label; lot A appears %1 times.', CountOf(DataSet, 'MIXLOT-A')));
        Check(CountOf(DataSet, 'MIXLOT-B') = 1, StrSubstNo('Product B must have exactly one label; lot B appears %1 times.', CountOf(DataSet, 'MIXLOT-B')));
        Check(StrPos(DataSet, '5 ') > 0, 'Product A label must carry the merged quantity 5.');
        Clear(TempBlob);
        TempBlob.CreateOutStream(OutStr);
        Check(Report.SaveAs(Report::"DOPSWHS MTE LP Report", '', ReportFormat::Pdf, OutStr, LpRef), 'The mixed-pallet RDLC could not render as PDF.');
        Check(TempBlob.Length() > 1000, 'The MTE PDF output must contain a rendered label.');
    end;

    local procedure AddLine(LpNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LotNo: Code[50]; Qty: Decimal)
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine."LP No." := LpNo;
        LPLine."Line No." := LineNo;
        LPLine."Item No." := ItemNo;
        LPLine."Unit of Measure" := 'ADET';
        LPLine."Lot No." := LotNo;
        LPLine.Quantity := Qty;
        LPLine.Insert(false);
    end;

    local procedure CountOf(Haystack: Text; Needle: Text): Integer
    var
        Position: Integer;
        Found: Integer;
    begin
        Position := StrPos(Haystack, Needle);
        while Position > 0 do begin
            Found += 1;
            Haystack := CopyStr(Haystack, Position + StrLen(Needle));
            Position := StrPos(Haystack, Needle);
        end;
        exit(Found);
    end;

    local procedure Check(Condition: Boolean; Message: Text)
    begin
        if not Condition then
            Error(Message);
    end;
}
