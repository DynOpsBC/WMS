page 72280 "DOPSWHS LP Template API"
{
    // LP template listesi mobil/web tarafında "Build LP" dropdown'u için
    // gereken seed verisi. Şimdiye kadar sadece BC içi list page (72012)
    // vardı — mobil LP Build sheet & Sistem Sağlığı paneli `licensePlateTemplates`
    // endpoint'ini çağırıyor ama AL page yoktu her zaman 404 dönüyordu.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'licensePlateTemplate';
    EntitySetName = 'licensePlateTemplates';
    SourceTable = "DOPSWHS LP Template";
    ODataKeyFields = "Code";
    Caption = 'WMS License Plate Template API';
    ApplicationArea = All;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(code; Rec.Code) { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(defaultTareWeightKg; Rec."Default Tare Weight kg") { Caption = 'defaultTareWeightKg'; }
                field(defaultLengthCm; Rec."Default Length cm") { Caption = 'defaultLengthCm'; }
                field(defaultWidthCm; Rec."Default Width cm") { Caption = 'defaultWidthCm'; }
                field(defaultHeightCm; Rec."Default Height cm") { Caption = 'defaultHeightCm'; }
                field(maxWeightKg; Rec."Max Weight kg") { Caption = 'maxWeightKg'; }
                field(labelReportId; Rec."Label Report ID") { Caption = 'labelReportId'; }
                field(noSeries; Rec."No. Series") { Caption = 'noSeries'; }
                field(allowMixedItems; Rec."Allow Mixed Items") { Caption = 'allowMixedItems'; }
                field(allowMixedLots; Rec."Allow Mixed Lots") { Caption = 'allowMixedLots'; }
                field(reusable; Rec.Reusable) { Caption = 'reusable'; }
            }
        }
    }

    [ServiceEnabled]
    procedure build(locationCode: Code[10]; binCode: Code[20]): Code[20]
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        CreatedLP: Record "DOPSWHS LP Header";
    begin
        // LP creation is intentionally an explicit domain action.  This makes
        // it impossible for the mobile client to bypass template defaults,
        // number-series handling or the LP movement ledger via a flat POST.
        LPMgt.Build(Rec.Code, locationCode, binCode, CreatedLP);
        exit(CreatedLP."No.");
    end;

    [ServiceEnabled]
    procedure buildBulk(locationCode: Code[10]; binCode: Code[20]; quantitiesJson: Text): Text
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        CreatedLP: Record "DOPSWHS LP Header";
        Quantities: JsonArray;
        QuantityToken: JsonToken;
        Result: JsonArray;
        ResultObject: JsonObject;
        PlannedQuantity: Decimal;
    begin
        if not Quantities.ReadFrom(quantitiesJson) then
            Error('Toplu LP miktar listesi geçerli JSON değildir.');
        if (Quantities.Count() < 1) or (Quantities.Count() > 200) then
            Error('Bir işlemde 1 ile 200 arasında LP oluşturabilirsiniz.');

        foreach QuantityToken in Quantities do begin
            Evaluate(PlannedQuantity, Format(QuantityToken.AsValue()));
            if PlannedQuantity < 0 then
                Error('LP planlanan miktarı negatif olamaz.');
            LPMgt.Build(Rec.Code, locationCode, binCode, CreatedLP);
            CreatedLP."Planned Quantity" := PlannedQuantity;
            CreatedLP.Modify(true);

            Clear(ResultObject);
            ResultObject.Add('no', CreatedLP."No.");
            ResultObject.Add('plannedQuantity', PlannedQuantity);
            Result.Add(ResultObject);
        end;
        Result.WriteTo(quantitiesJson);
        exit(quantitiesJson);
    end;
}
