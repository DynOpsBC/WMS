codeunit 72031 "DOPSWHS Setup Wizard"
{
    Access = Public;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Assisted Setup", 'OnRegister', '', false, false)]
    local procedure OnRegisterAssistedSetup()
    var
        AssistedSetup: Codeunit "Assisted Setup";
        AssistedSetupGroup: Enum "Assisted Setup Group";
        VideoCategory: Enum "Video Category";
    begin
        AssistedSetup.Add(
            GetAppId(),
            Page::"DOPSWHS Setup",
            'Set up Advanced WMS',
            AssistedSetupGroup::Extensions,
            '',
            VideoCategory::Uncategorized,
            'Configure license plate, SSCC, location, and print settings.');
    end;

    local procedure GetAppId(): Guid
    begin
        exit('984e25aa-07c2-4401-babc-88f975303a52');
    end;

    procedure SeedSprint1Defaults()
    begin
        SeedDeviceConfig();
        SeedSymbologies();
        SeedBarcodeRules();
    end;

    local procedure SeedDeviceConfig()
    var
        DeviceConfig: Record "DOPSWHS Device Configuration";
        DeviceMenu: Record "DOPSWHS Device Menu";
    begin
        if not DeviceConfig.Get('DEFAULT') then begin
            DeviceConfig.Init();
            DeviceConfig."Code" := 'DEFAULT';
            DeviceConfig.Description := 'Default handheld profile';
            DeviceConfig."Login Mode" := DeviceConfig."Login Mode"::SSO;
            DeviceConfig."Assign Document On Open" := true;
            DeviceConfig."LP Usage Default Action" := DeviceConfig."LP Usage Default Action"::CreateNewLP;
            DeviceConfig."Max List Rows" := 100;
            DeviceConfig."Scan Beep" := true;
            DeviceConfig."Print Channel" := DeviceConfig."Print Channel"::None;
            DeviceConfig.Insert(true);
        end;

        SeedMenu(DeviceMenu, 'DEFAULT', DeviceMenu."Application Module"::ItemInquiry, 'ITEM-INQUIRY', 10);
        SeedMenu(DeviceMenu, 'DEFAULT', DeviceMenu."Application Module"::BinInquiry, 'BIN-INQUIRY', 20);
        SeedMenu(DeviceMenu, 'DEFAULT', DeviceMenu."Application Module"::Configuration, 'CONFIG', 90);
    end;

    local procedure SeedMenu(var DeviceMenu: Record "DOPSWHS Device Menu"; ConfigCode: Code[20]; Module: Enum "DOPSWHS Application Module"; MenuItem: Code[30]; SortOrder: Integer)
    begin
        if DeviceMenu.Get(ConfigCode, MenuItem) then
            exit;

        DeviceMenu.Init();
        DeviceMenu."Config Code" := ConfigCode;
        DeviceMenu."Application Module" := Module;
        DeviceMenu."Menu Item" := MenuItem;
        DeviceMenu."Sort Order" := SortOrder;
        DeviceMenu.Visible := true;
        DeviceMenu.Insert(true);
    end;

    local procedure SeedSymbologies()
    var
        Symbology: Record "DOPSWHS Barcode Symbology";
    begin
        SeedSymbology(Symbology, 'EAN13', 'EAN-13 item reference', Symbology.Format::EAN13, 13, 13);
        SeedSymbology(Symbology, 'GS1-128', 'GS1-128 application identifiers', Symbology.Format::GS1128, 16, 80);
        SeedSymbology(Symbology, 'SSCC-18', 'SSCC-18 license plate code', Symbology.Format::SSCC18, 22, 22);
        SeedSymbology(Symbology, 'CODE128', 'Code 128 warehouse labels', Symbology.Format::Code128, 1, 80);
    end;

    local procedure SeedSymbology(var Symbology: Record "DOPSWHS Barcode Symbology"; Code: Code[20]; Description: Text[100]; Format: Enum "DOPSWHS Symbology"; MinLength: Integer; MaxLength: Integer)
    begin
        if Symbology.Get(Code) then
            exit;

        Symbology.Init();
        Symbology."Code" := Code;
        Symbology.Description := Description;
        Symbology.Format := Format;
        Symbology."Min Length" := MinLength;
        Symbology."Max Length" := MaxLength;
        Symbology.Insert(true);
    end;

    local procedure SeedBarcodeRules()
    var
        Rule: Record "DOPSWHS Barcode Rule";
    begin
        SeedRule(Rule, 'EAN13-ITEM', 'EAN-13 item reference', 'EAN13', '^\d{13}$', '{"itemReference":"$0"}', Rule."Maps To"::Item, 10);
        SeedRule(Rule, 'GS1-128-FULL', 'GS1-128 GTIN/lot/expiry/serial', 'GS1-128', '^\(01\)(?<gtin>\d{14})(\(10\)(?<lot>[A-Za-z0-9\-]+))?(\(17\)(?<exp>\d{6}))?(\(21\)(?<sn>[A-Za-z0-9\-]+))?$', '{"gtin":"gtin","lot":"lot","exp":"exp","sn":"sn"}', Rule."Maps To"::Item, 20);
        SeedRule(Rule, 'SSCC-18', 'SSCC-18 license plate', 'SSCC-18', '^\(00\)(\d{18})$', '{"sscc":"1"}', Rule."Maps To"::LP, 30);
        SeedRule(Rule, 'BIN-PREFIX', 'Bin barcode prefix', 'CODE128', '^B-(?<bin>[\w-]+)$', '{"bin":"bin"}', Rule."Maps To"::Bin, 40);
        SeedRule(Rule, 'LP-TEMPLATE', 'LP template barcode prefix', 'CODE128', '^TPL-(?<tpl>[\w-]+)$', '{"tpl":"tpl"}', Rule."Maps To"::LpTemplate, 50);
    end;

    local procedure SeedRule(var Rule: Record "DOPSWHS Barcode Rule"; Code: Code[30]; Description: Text[100]; Symbology: Code[20]; Regex: Text[250]; CaptureMapJson: Text[2048]; MapsTo: Enum "DOPSWHS Barcode Map Target"; SortOrder: Integer)
    begin
        if Rule.Get(Code) then
            exit;

        Rule.Init();
        Rule."Code" := Code;
        Rule.Description := Description;
        Rule.Symbology := Symbology;
        Rule.Regex := Regex;
        Rule."Capture Map JSON" := CaptureMapJson;
        Rule."Maps To" := MapsTo;
        Rule."Order" := SortOrder;
        Rule.Active := true;
        Rule.Insert(true);
    end;
}
