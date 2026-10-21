// Kitoko (21 Eki 2026): sürükle-bırak etiket tasarımcısının BC tarafı. Tasarım
// tabloları <-> DesignJson (docs/label-designer-contract.md). ZPL'i yine
// DOPSWHS Label Layout Engine üretir; tasarımcı yalnız çizer.
codeunit 72472 "DOPSWHS Label Designer Mgt"
{
    Access = Public;
    Permissions = tabledata "Company Information" = R;

    var
        CompanyImageCodeTxt: Label 'COMPANY', Locked = true;
        CompanyLogoNameTxt: Label 'Şirket logosu';
        NoWritePermissionErr: Label 'Etiket tasarımlarını değiştirme yetkiniz yok.';
        InvalidJsonErr: Label 'Tasarım JSON okunamadı.';
        UnsupportedVersionErr: Label 'Desteklenmeyen tasarım sürümü: %1.', Comment = '%1 = version';
        CodeMismatchErr: Label 'Tasarım kodu (%1) açık tasarımla (%2) uyuşmuyor.', Comment = '%1 = code in JSON, %2 = layout code';
        UnknownKindErr: Label 'Bilinmeyen etiket türü: "%1". Item, Bin, Zone veya LP olmalı.', Comment = '%1 = kind';
        InvalidSizeErr: Label 'Etiket ölçüsü geçersiz (%1 x %2 mm). Genişlik 0-300 mm, yükseklik 0-400 mm olmalı (0 = Kurulum sayfasındaki etiket ölçüsü).', Comment = '%1 = width, %2 = height';
        InvalidDpiErr: Label 'Çözünürlük 203, 300 veya 600 dpi olmalı (0 = 203) (%1).', Comment = '%1 = dpi';
        MissingElementsErr: Label 'Tasarım JSON "elements" dizisini içermiyor; kayıt yapılmadı (boş tasarım için boş dizi gönderin).';
        InvalidElementErr: Label '%1. eleman bir JSON nesnesi değil.', Comment = '%1 = element index';
        UnknownTypeErr: Label '%1. eleman: bilinmeyen tür "%2".', Comment = '%1 = element index, %2 = type';
        InvalidRotationErr: Label '%1. eleman: döndürme 0, 90, 180 veya 270 olmalı (%2).', Comment = '%1 = element index, %2 = rotation';
        UnknownSymbologyErr: Label '%1. eleman: bilinmeyen barkod türü "%2" (code128, ean13, gs1-128).', Comment = '%1 = element index, %2 = symbology';
        UnknownAlignErr: Label '%1. eleman: bilinmeyen hizalama "%2" (left, center, right).', Comment = '%1 = element index, %2 = alignment';
        TooLongErr: Label '%1. eleman: "%2" en çok %3 karakter olabilir.', Comment = '%1 = element index, %2 = property, %3 = max length';
        InvalidGraphicErr: Label '%1. eleman: resim verisi geçersiz (^GFA bekleniyor).', Comment = '%1 = element index';
        InvalidImageErr: Label 'Resim "%1" geçersiz: kod 1-20 karakter, veri data:image/... olmalı.', Comment = '%1 = image id';
        PreviewFailedErr: Label 'Önizleme alınamadı (labelary.com): %1', Comment = '%1 = error text';

    // ------------------------------------------------------------------
    // BC -> designer
    // ------------------------------------------------------------------

    /// <summary>DesignJson of a saved layout: header, elements (line order), fields of its kind and referenced images.</summary>
    procedure DesignToJson(LayoutCode: Code[20]): Text
    begin
        exit(BuildDesignJson(LayoutCode, false));
    end;

    /// <summary>
    /// DesignJson with the company logo (Company Information picture) added to images[] as COMPANY.
    /// Carries "merge": "images" so the designer can keep its unsaved elements and only take the images.
    /// </summary>
    procedure DesignToJsonWithCompanyLogo(LayoutCode: Code[20]): Text
    begin
        exit(BuildDesignJson(LayoutCode, true));
    end;

    /// <summary>Company Information picture as a base64 data URL; '' when the company has no picture.</summary>
    procedure CompanyLogoDataUrl(): Text
    var
        CompanyInformation: Record "Company Information";
        Base64Convert: Codeunit "Base64 Convert";
        InStr: InStream;
        Base64: Text;
    begin
        if not CompanyInformation.Get() then
            exit('');
        CompanyInformation.CalcFields(Picture);
        if not CompanyInformation.Picture.HasValue() then
            exit('');
        CompanyInformation.Picture.CreateInStream(InStr);
        Base64 := Base64Convert.ToBase64(InStr);
        if Base64 = '' then
            exit('');
        exit('data:' + MimeTypeOf(Base64) + ';base64,' + Base64);
    end;

    /// <summary>Copies the company logo into Label Image COMPANY (when allowed); false = no logo.</summary>
    procedure EnsureCompanyImage(): Boolean
    var
        DataUrl: Text;
    begin
        DataUrl := CompanyLogoDataUrl();
        if DataUrl = '' then
            exit(false);
        StoreCompanyImage(DataUrl);
        exit(true);
    end;

    local procedure StoreCompanyImage(DataUrl: Text)
    var
        LabelImage: Record "DOPSWHS Label Image";
    begin
        if not LabelImage.WritePermission() then
            exit;
        if LabelImage.Get(CompanyImageCodeTxt) then begin
            if LabelImage.GetDataUrl() = DataUrl then
                exit;
            LabelImage.SetDataUrl(DataUrl);
            LabelImage.Modify(true);
            exit;
        end;
        LabelImage.Init();
        LabelImage."Code" := CompanyImageCodeTxt;
        LabelImage.Name := CompanyLogoNameTxt;
        LabelImage.SetDataUrl(DataUrl);
        LabelImage.Insert(true);
    end;

    local procedure BuildDesignJson(LayoutCode: Code[20]; IncludeCompanyLogo: Boolean): Text
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Root: JsonObject;
        Elements: JsonArray;
        Images: JsonArray;
        ImageIds: List of [Code[20]];
        ImageId: Code[20];
        CompanyDataUrl: Text;
        Result: Text;
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
    begin
        Layout.Get(LayoutCode);
        Engine.LayoutSizeOf(Layout, WidthMm, HeightMm, Dpi);
        Root.Add('version', 1);
        Root.Add('code', Layout."Code");
        Root.Add('description', Layout.Description);
        Root.Add('kind', KindToText(Layout."Label Kind"));
        Root.Add('widthMm', WidthMm);
        Root.Add('heightMm', HeightMm);
        Root.Add('dpi', Dpi);
        Root.Add('active', Layout.Active);
        // Kitoko (21 Eki 2026): tasarımcı geri gönderir; Aktif yalnız kullanıcı değiştirdiyse yazılır.
        Root.Add('activeAtLoad', Layout.Active);
        Root.Add('readOnly', not CanEdit());

        LayoutLine.SetRange("Layout Code", Layout."Code");
        if LayoutLine.FindSet() then
            repeat
                Elements.Add(ElementToJson(LayoutLine));
                if (LayoutLine."Image Id" <> '') and not ImageIds.Contains(LayoutLine."Image Id") then
                    ImageIds.Add(LayoutLine."Image Id");
            until LayoutLine.Next() = 0;
        Root.Add('elements', Elements);
        Root.Add('fields', FieldsToJson(Layout."Label Kind"));

        if IncludeCompanyLogo then begin
            CompanyDataUrl := CompanyLogoDataUrl();
            if CompanyDataUrl <> '' then begin
                StoreCompanyImage(CompanyDataUrl);
                Images.Add(ImageJson(CompanyImageCodeTxt, CompanyLogoNameTxt, CompanyDataUrl, 0, 0));
            end;
            Root.Add('merge', 'images');
        end;
        foreach ImageId in ImageIds do
            if not (IncludeCompanyLogo and (ImageId = CompanyImageCodeTxt) and (CompanyDataUrl <> '')) then
                AddStoredImage(Images, ImageId);
        Root.Add('images', Images);
        Root.WriteTo(Result);
        exit(Result);
    end;

    local procedure ElementToJson(var LayoutLine: Record "DOPSWHS Label Layout Line"): JsonObject
    var
        Element: JsonObject;
        ElementId: Text;
    begin
        ElementId := LayoutLine."Element Id";
        if ElementId = '' then
            ElementId := 'e' + Format(LayoutLine."Line No.", 0, 9);
        Element.Add('id', ElementId);
        Element.Add('lineNo', LayoutLine."Line No.");
        Element.Add('type', TypeToText(LayoutLine."Element Type"));
        Element.Add('xMm', LayoutLine."X (mm)");
        Element.Add('yMm', LayoutLine."Y (mm)");
        Element.Add('wMm', LayoutLine."Width (mm)");
        Element.Add('hMm', LayoutLine."Height (mm)");
        Element.Add('rotation', LayoutLine.Rotation);
        Element.Add('fontMm', LayoutLine."Font Height (mm)");
        Element.Add('fontWidthMm', LayoutLine."Font Width (mm)");
        Element.Add('minFontMm', LayoutLine."Min Font Height (mm)");
        Element.Add('bold', LayoutLine.Bold);
        Element.Add('align', AlignToText(LayoutLine.Alignment));
        Element.Add('field', LayoutLine."Source Field");
        Element.Add('text', LayoutLine."Static Text");
        Element.Add('prefix', LayoutLine.Prefix);
        Element.Add('suffix', LayoutLine.Suffix);
        Element.Add('maxLines', LayoutLine."Max Lines");
        Element.Add('fit', LayoutLine."Fit to Width");
        Element.Add('inverted', LayoutLine.Inverted);
        Element.Add('symbology', SymbologyToText(LayoutLine.Symbology));
        Element.Add('showText', LayoutLine."Show Text");
        Element.Add('thicknessMm', LayoutLine."Thickness (mm)");
        Element.Add('imageId', LayoutLine."Image Id");
        Element.Add('imageGf', LayoutLine.GetImageGf());
        Element.Add('enabled', LayoutLine.Enabled);
        exit(Element);
    end;

    local procedure FieldsToJson(Kind: Enum "DOPSWHS Label Kind"): JsonArray
    var
        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
        Fields: JsonArray;
        FieldObject: JsonObject;
        FieldKeys: List of [Text];
        Samples: Dictionary of [Text, Text];
        FieldKey: Text;
        Sample: Text;
    begin
        LayoutFields.KeysFor(Kind, FieldKeys);
        LayoutFields.SampleValues(Kind, Samples);
        foreach FieldKey in FieldKeys do begin
            Clear(FieldObject);
            Sample := '';
            if Samples.Get(FieldKey, Sample) then;
            FieldObject.Add('key', FieldKey);
            FieldObject.Add('label', LayoutFields.FieldLabel(FieldKey));
            FieldObject.Add('sample', Sample);
            Fields.Add(FieldObject);
        end;
        exit(Fields);
    end;

    local procedure AddStoredImage(var Images: JsonArray; ImageId: Code[20])
    var
        LabelImage: Record "DOPSWHS Label Image";
    begin
        if not LabelImage.Get(ImageId) then
            exit;
        Images.Add(ImageJson(LabelImage."Code", LabelImage.Name, LabelImage.GetDataUrl(), LabelImage."Width (px)", LabelImage."Height (px)"));
    end;

    local procedure ImageJson(ImageId: Text; Name: Text; DataUrl: Text; WidthPx: Integer; HeightPx: Integer): JsonObject
    var
        Image: JsonObject;
    begin
        Image.Add('id', ImageId);
        Image.Add('name', Name);
        Image.Add('dataUrl', DataUrl);
        if WidthPx > 0 then
            Image.Add('widthPx', WidthPx);
        if HeightPx > 0 then
            Image.Add('heightPx', HeightPx);
        exit(Image);
    end;

    // ------------------------------------------------------------------
    // designer -> BC
    // ------------------------------------------------------------------

    /// <summary>True when the current user may change label layouts (write permission on both layout tables).</summary>
    procedure CanEdit(): Boolean
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
    begin
        exit(Layout.WritePermission() and LayoutLine.WritePermission());
    end;

    /// <summary>Validates a DesignJson without writing anything; false = GetLastErrorText has the reason.</summary>
    [TryFunction]
    procedure TryValidateDesign(LayoutCode: Code[20]; DesignJson: Text)
    var
        TempLayout: Record "DOPSWHS Label Layout" temporary;
        TempLayoutLine: Record "DOPSWHS Label Layout Line" temporary;
        TempLabelImage: Record "DOPSWHS Label Image" temporary;
    begin
        ParseDesign(LayoutCode, DesignJson, TempLayout, TempLayoutLine, TempLabelImage);
    end;

    /// <summary>
    /// Saves a DesignJson: header fields, all lines deleted and rewritten in array
    /// order (line no. 10000, 20000, ...), ^GFA data in the line blob, images upserted.
    /// </summary>
    procedure SaveFromJson(LayoutCode: Code[20]; DesignJson: Text)
    var
        Layout: Record "DOPSWHS Label Layout";
        LayoutLine: Record "DOPSWHS Label Layout Line";
        LabelImage: Record "DOPSWHS Label Image";
        TempLayout: Record "DOPSWHS Label Layout" temporary;
        TempLayoutLine: Record "DOPSWHS Label Layout Line" temporary;
        TempLabelImage: Record "DOPSWHS Label Image" temporary;
    begin
        if not CanEdit() then
            Error(NoWritePermissionErr);
        ParseDesign(LayoutCode, DesignJson, TempLayout, TempLayoutLine, TempLabelImage);

        Layout.Get(LayoutCode);
        Layout.Description := TempLayout.Description;
        Layout."Label Kind" := TempLayout."Label Kind";
        Layout."Width (mm)" := TempLayout."Width (mm)";
        Layout."Height (mm)" := TempLayout."Height (mm)";
        Layout.Dpi := TempLayout.Dpi;
        Layout.Modify(true);
        // Validate after the kind is stored so only this kind's other layouts are deactivated.
        Layout.Validate(Active, TempLayout.Active);
        Layout.Modify(true);

        LayoutLine.SetRange("Layout Code", LayoutCode);
        LayoutLine.DeleteAll(true);
        TempLayoutLine.Reset();
        if TempLayoutLine.FindSet() then
            repeat
                LayoutLine.Init();
                LayoutLine.TransferFields(TempLayoutLine);
                LayoutLine."Layout Code" := LayoutCode;
                LayoutLine.SetImageGf(TempLayoutLine.GetImageGf());
                LayoutLine.Insert(true);
            until TempLayoutLine.Next() = 0;

        // Kitoko (21 Eki 2026): only a changed picture is written, so re-sending the
        // stored images (every save does) needs no write permission on Label Image.
        if TempLabelImage.FindSet() then
            repeat
                if LabelImage.Get(TempLabelImage."Code") then begin
                    if LabelImage.GetDataUrl() <> TempLabelImage.GetDataUrl() then begin
                        CheckImageWritePermission();
                        CopyImage(TempLabelImage, LabelImage);
                        LabelImage.Modify(true);
                    end else
                        if ImageInfoChanged(TempLabelImage, LabelImage) and LabelImage.WritePermission() then begin
                            CopyImage(TempLabelImage, LabelImage);
                            LabelImage.Modify(true);
                        end;
                end else begin
                    CheckImageWritePermission();
                    LabelImage.Init();
                    LabelImage."Code" := TempLabelImage."Code";
                    CopyImage(TempLabelImage, LabelImage);
                    LabelImage.Insert(true);
                end;
            until TempLabelImage.Next() = 0;
    end;

    local procedure CheckImageWritePermission()
    var
        LabelImage: Record "DOPSWHS Label Image";
    begin
        if not LabelImage.WritePermission() then
            Error(NoWritePermissionErr);
    end;

    local procedure ImageInfoChanged(var Source: Record "DOPSWHS Label Image"; var Target: Record "DOPSWHS Label Image"): Boolean
    begin
        exit((Source.Name <> Target.Name) or (Source."Width (px)" <> Target."Width (px)") or (Source."Height (px)" <> Target."Height (px)"));
    end;

    local procedure CopyImage(var Source: Record "DOPSWHS Label Image"; var Target: Record "DOPSWHS Label Image")
    begin
        Target.Name := Source.Name;
        Target."Width (px)" := Source."Width (px)";
        Target."Height (px)" := Source."Height (px)";
        Target.SetDataUrl(Source.GetDataUrl());
    end;

    /// <summary>
    /// Test print with SAMPLE values through the same queue as the card's "Test Baskı".
    /// An empty DesignJson prints the saved layout; otherwise the unsaved design is printed.
    /// </summary>
    procedure TestPrint(LayoutCode: Code[20]; DesignJson: Text; PrinterCode: Code[50])
    var
        TempLayout: Record "DOPSWHS Label Layout" temporary;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Zpl: Text;
    begin
        Zpl := BuildSampleZplFor(LayoutCode, DesignJson, TempLayout);
        Dispatcher.PrintLayoutTest(Zpl, PrinterCode, TempLayout."Label Kind");
    end;

    /// <summary>Sample-data ZPL of the saved layout (empty JSON) or of the unsaved design.</summary>
    procedure SampleZpl(LayoutCode: Code[20]; DesignJson: Text): Text
    var
        TempLayout: Record "DOPSWHS Label Layout" temporary;
    begin
        exit(BuildSampleZplFor(LayoutCode, DesignJson, TempLayout));
    end;

    /// <summary>Labelary PNG (base64, no data: prefix) of the design with SAMPLE values only.</summary>
    procedure PreviewPngBase64(LayoutCode: Code[20]; DesignJson: Text): Text
    var
        TempLayout: Record "DOPSWHS Label Layout" temporary;
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Preview: Codeunit "DOPSWHS Label Layout Preview";
        Base64Convert: Codeunit "Base64 Convert";
        TempBlob: Codeunit "Temp Blob";
        PngStream: InStream;
        Zpl: Text;
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
    begin
        Zpl := BuildSampleZplFor(LayoutCode, DesignJson, TempLayout);
        Engine.LayoutSizeOf(TempLayout, WidthMm, HeightMm, Dpi);
        if not Preview.TryRenderPng(Zpl, WidthMm, HeightMm, Dpi, TempBlob) then
            Error(PreviewFailedErr, GetLastErrorText());
        TempBlob.CreateInStream(PngStream);
        exit(Base64Convert.ToBase64(PngStream));
    end;

    /// <summary>PreviewPngBase64 that never raises; false = GetLastErrorText has the reason.</summary>
    [TryFunction]
    procedure TryPreviewPngBase64(LayoutCode: Code[20]; DesignJson: Text; var PngBase64: Text)
    begin
        PngBase64 := PreviewPngBase64(LayoutCode, DesignJson);
    end;

    local procedure BuildSampleZplFor(LayoutCode: Code[20]; DesignJson: Text; var TempLayout: Record "DOPSWHS Label Layout" temporary): Text
    var
        Layout: Record "DOPSWHS Label Layout";
        TempLayoutLine: Record "DOPSWHS Label Layout Line" temporary;
        TempLabelImage: Record "DOPSWHS Label Image" temporary;
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
        Values: Dictionary of [Text, Text];
    begin
        if DesignJson = '' then begin
            Layout.Get(LayoutCode);
            TempLayout := Layout;
            exit(Engine.BuildSampleZpl(LayoutCode));
        end;
        ParseDesign(LayoutCode, DesignJson, TempLayout, TempLayoutLine, TempLabelImage);
        LayoutFields.SampleValues(TempLayout."Label Kind", Values);
        exit(Engine.BuildZplFromRecords(TempLayout, TempLayoutLine, Values, 1));
    end;

    /// <summary>Reads and validates a DesignJson into temporary records (nothing is written to the database).</summary>
    procedure ParseDesign(LayoutCode: Code[20]; DesignJson: Text; var TempLayout: Record "DOPSWHS Label Layout" temporary; var TempLayoutLine: Record "DOPSWHS Label Layout Line" temporary; var TempLabelImage: Record "DOPSWHS Label Image" temporary)
    var
        Layout: Record "DOPSWHS Label Layout";
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Root: JsonObject;
        Token: JsonToken;
        Item: JsonToken;
        JsonCode: Text;
        Index: Integer;
        WidthMm: Decimal;
        HeightMm: Decimal;
        ResolvedWidthMm: Decimal;
        ResolvedHeightMm: Decimal;
        Dpi: Integer;
        ResolvedDpi: Integer;
        JsonActive: Boolean;
        LayoutFound: Boolean;
    begin
        TempLayout.Reset();
        TempLayout.DeleteAll();
        TempLayoutLine.Reset();
        TempLayoutLine.DeleteAll();
        TempLabelImage.Reset();
        TempLabelImage.DeleteAll();
        if not Root.ReadFrom(DesignJson) then
            Error(InvalidJsonErr);
        if Root.Contains('version') then
            if GetInteger(Root, 'version') > 1 then
                Error(UnsupportedVersionErr, GetInteger(Root, 'version'));
        JsonCode := GetText(Root, 'code');
        if (JsonCode <> '') and (UpperCase(JsonCode) <> LayoutCode) then
            Error(CodeMismatchErr, JsonCode, LayoutCode);

        // Missing header values keep the saved layout's values.
        LayoutFound := Layout.Get(LayoutCode);
        if LayoutFound then begin
            TempLayout := Layout;
            Engine.LayoutSizeOf(Layout, ResolvedWidthMm, ResolvedHeightMm, ResolvedDpi);
        end else begin
            TempLayout.Init();
            TempLayout."Code" := LayoutCode;
        end;
        if Root.Contains('description') then
            TempLayout.Description := CopyStr(GetText(Root, 'description'), 1, MaxStrLen(TempLayout.Description));
        if Root.Contains('kind') then
            TempLayout."Label Kind" := TextToKind(GetText(Root, 'kind'));
        WidthMm := TempLayout."Width (mm)";
        HeightMm := TempLayout."Height (mm)";
        if Root.Contains('widthMm') then
            WidthMm := Round(GetDecimal(Root, 'widthMm'), 0.01);
        if Root.Contains('heightMm') then
            HeightMm := Round(GetDecimal(Root, 'heightMm'), 0.01);
        if (WidthMm < 0) or (WidthMm > 300) or (HeightMm < 0) or (HeightMm > 400) then
            Error(InvalidSizeErr, WidthMm, HeightMm);
        // Kitoko (21 Eki 2026): a stored 0 (= Setup label size) stays 0 while the designer
        // sends back the size BC resolved for it; only a real change is stored.
        if LayoutFound then begin
            if (Layout."Width (mm)" = 0) and (WidthMm = Round(ResolvedWidthMm, 0.01)) then
                WidthMm := 0;
            if (Layout."Height (mm)" = 0) and (HeightMm = Round(ResolvedHeightMm, 0.01)) then
                HeightMm := 0;
        end;
        TempLayout."Width (mm)" := WidthMm;
        TempLayout."Height (mm)" := HeightMm;
        if Root.Contains('dpi') then begin
            Dpi := GetInteger(Root, 'dpi');
            if not (Dpi in [0, 203, 300, 600]) then
                Error(InvalidDpiErr, Dpi);
            if Dpi = 0 then
                Dpi := 203;
            TempLayout.Dpi := Dpi;
        end;
        // Kitoko (21 Eki 2026): Active changes only when the user switched it in the
        // designer (active <> activeAtLoad), so a stale designer never overrides an
        // activation made elsewhere meanwhile. Either key missing = Active untouched.
        if Root.Contains('active') and Root.Contains('activeAtLoad') then begin
            JsonActive := GetBoolean(Root, 'active', TempLayout.Active);
            if JsonActive <> GetBoolean(Root, 'activeAtLoad', JsonActive) then
                TempLayout.Active := JsonActive;
        end;
        TempLayout.Insert();

        // Kitoko (21 Eki 2026): "elements" is required; saving rewrites every line, so a
        // missing array must not wipe the design. An explicit [] is an empty design.
        if not Root.Get('elements', Token) then
            Error(MissingElementsErr);
        if not Token.IsArray() then
            Error(MissingElementsErr);
        foreach Item in Token.AsArray() do begin
            Index += 1;
            if not Item.IsObject() then
                Error(InvalidElementErr, Index);
            ParseElement(Item.AsObject(), Index, LayoutCode, TempLayoutLine);
        end;

        if Root.Get('images', Token) then
            if Token.IsArray() then
                foreach Item in Token.AsArray() do
                    if Item.IsObject() then
                        ParseImage(Item.AsObject(), TempLabelImage);
    end;

    local procedure ParseElement(Element: JsonObject; Index: Integer; LayoutCode: Code[20]; var TempLayoutLine: Record "DOPSWHS Label Layout Line" temporary)
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
        Rotation: Integer;
        ImageGf: Text;
    begin
        TempLayoutLine.Init();
        TempLayoutLine."Layout Code" := LayoutCode;
        TempLayoutLine."Line No." := Index * 10000;
        TempLayoutLine."Element Id" := CopyStr(GetText(Element, 'id'), 1, MaxStrLen(TempLayoutLine."Element Id"));
        TempLayoutLine."Element Type" := TextToType(GetText(Element, 'type'), Index);
        TempLayoutLine."X (mm)" := Round(GetDecimal(Element, 'xMm'), 0.01);
        TempLayoutLine."Y (mm)" := Round(GetDecimal(Element, 'yMm'), 0.01);
        TempLayoutLine."Width (mm)" := NonNegative(Round(GetDecimal(Element, 'wMm'), 0.01));
        TempLayoutLine."Height (mm)" := NonNegative(Round(GetDecimal(Element, 'hMm'), 0.01));
        Rotation := GetInteger(Element, 'rotation');
        if not (Rotation in [0, 90, 180, 270]) then
            Error(InvalidRotationErr, Index, Rotation);
        if TempLayoutLine."Element Type" = TempLayoutLine."Element Type"::QRCode then
            Rotation := 0;
        TempLayoutLine.Rotation := Rotation;
        TempLayoutLine."Font Height (mm)" := NonNegative(Round(GetDecimal(Element, 'fontMm'), 0.01));
        TempLayoutLine."Font Width (mm)" := NonNegative(Round(GetDecimal(Element, 'fontWidthMm'), 0.01));
        TempLayoutLine."Min Font Height (mm)" := NonNegative(Round(GetDecimal(Element, 'minFontMm'), 0.01));
        TempLayoutLine.Bold := GetBoolean(Element, 'bold', false);
        TempLayoutLine.Alignment := TextToAlign(GetText(Element, 'align'), Index);
        TempLayoutLine."Source Field" := CopyStr(CheckLength(GetText(Element, 'field'), MaxStrLen(TempLayoutLine."Source Field"), Index, 'field'), 1, MaxStrLen(TempLayoutLine."Source Field"));
        TempLayoutLine."Static Text" := CopyStr(CheckLength(GetText(Element, 'text'), MaxStrLen(TempLayoutLine."Static Text"), Index, 'text'), 1, MaxStrLen(TempLayoutLine."Static Text"));
        TempLayoutLine.Prefix := CopyStr(CheckLength(GetText(Element, 'prefix'), MaxStrLen(TempLayoutLine.Prefix), Index, 'prefix'), 1, MaxStrLen(TempLayoutLine.Prefix));
        TempLayoutLine.Suffix := CopyStr(CheckLength(GetText(Element, 'suffix'), MaxStrLen(TempLayoutLine.Suffix), Index, 'suffix'), 1, MaxStrLen(TempLayoutLine.Suffix));
        TempLayoutLine."Max Lines" := GetInteger(Element, 'maxLines');
        if TempLayoutLine."Max Lines" < 0 then
            TempLayoutLine."Max Lines" := 0;
        TempLayoutLine."Fit to Width" := GetBoolean(Element, 'fit', false);
        TempLayoutLine.Inverted := GetBoolean(Element, 'inverted', false);
        TempLayoutLine.Symbology := TextToSymbology(GetText(Element, 'symbology'), Index);
        TempLayoutLine."Show Text" := GetBoolean(Element, 'showText', false);
        TempLayoutLine."Thickness (mm)" := NonNegative(Round(GetDecimal(Element, 'thicknessMm'), 0.01));
        TempLayoutLine."Image Id" := CopyStr(UpperCase(CheckLength(GetText(Element, 'imageId'), MaxStrLen(TempLayoutLine."Image Id"), Index, 'imageId')), 1, MaxStrLen(TempLayoutLine."Image Id"));
        TempLayoutLine.Enabled := GetBoolean(Element, 'enabled', true);
        ImageGf := GetText(Element, 'imageGf');
        if ImageGf <> '' then
            if not Engine.IsSafeGraphic(ImageGf) then
                Error(InvalidGraphicErr, Index);
        TempLayoutLine.SetImageGf(ImageGf);
        TempLayoutLine.Insert();
    end;

    local procedure ParseImage(Image: JsonObject; var TempLabelImage: Record "DOPSWHS Label Image" temporary)
    var
        ImageId: Text;
        DataUrl: Text;
    begin
        ImageId := UpperCase(GetText(Image, 'id'));
        DataUrl := GetText(Image, 'dataUrl');
        // A reference without data (image already stored in BC) needs no write.
        if DataUrl = '' then
            exit;
        if (ImageId = '') or (StrLen(ImageId) > MaxStrLen(TempLabelImage."Code")) or not DataUrl.StartsWith('data:image/') then
            Error(InvalidImageErr, ImageId);
        if TempLabelImage.Get(ImageId) then
            exit;
        TempLabelImage.Init();
        TempLabelImage."Code" := CopyStr(ImageId, 1, MaxStrLen(TempLabelImage."Code"));
        TempLabelImage.Name := CopyStr(GetText(Image, 'name'), 1, MaxStrLen(TempLabelImage.Name));
        TempLabelImage."Width (px)" := GetInteger(Image, 'widthPx');
        TempLabelImage."Height (px)" := GetInteger(Image, 'heightPx');
        if TempLabelImage."Width (px)" < 0 then
            TempLabelImage."Width (px)" := 0;
        if TempLabelImage."Height (px)" < 0 then
            TempLabelImage."Height (px)" := 0;
        TempLabelImage.SetDataUrl(DataUrl);
        TempLabelImage.Insert();
    end;

    // ------------------------------------------------------------------
    // Mappings
    // ------------------------------------------------------------------

    procedure KindToText(Kind: Enum "DOPSWHS Label Kind"): Text
    begin
        case Kind of
            Kind::Bin:
                exit('Bin');
            Kind::Zone:
                exit('Zone');
            Kind::LP:
                exit('LP');
        end;
        exit('Item');
    end;

    procedure TextToKind(Value: Text): Enum "DOPSWHS Label Kind"
    begin
        case LowerCase(Value) of
            'item':
                exit(Enum::"DOPSWHS Label Kind"::Item);
            'bin':
                exit(Enum::"DOPSWHS Label Kind"::Bin);
            'zone':
                exit(Enum::"DOPSWHS Label Kind"::Zone);
            'lp':
                exit(Enum::"DOPSWHS Label Kind"::LP);
        end;
        Error(UnknownKindErr, Value);
    end;

    procedure TypeToText(ElementType: Enum "DOPSWHS Label Element Type"): Text
    begin
        case ElementType of
            ElementType::Field:
                exit('field');
            ElementType::Barcode128:
                exit('barcode');
            ElementType::QRCode:
                exit('qr');
            ElementType::Line:
                exit('line');
            ElementType::Box:
                exit('box');
            ElementType::Image:
                exit('image');
        end;
        exit('text');
    end;

    local procedure TextToType(Value: Text; Index: Integer): Enum "DOPSWHS Label Element Type"
    begin
        case LowerCase(Value) of
            'text':
                exit(Enum::"DOPSWHS Label Element Type"::Text);
            'field':
                exit(Enum::"DOPSWHS Label Element Type"::Field);
            'barcode', 'barcode128':
                exit(Enum::"DOPSWHS Label Element Type"::Barcode128);
            'qr':
                exit(Enum::"DOPSWHS Label Element Type"::QRCode);
            'line':
                exit(Enum::"DOPSWHS Label Element Type"::Line);
            'box':
                exit(Enum::"DOPSWHS Label Element Type"::Box);
            'image':
                exit(Enum::"DOPSWHS Label Element Type"::Image);
        end;
        Error(UnknownTypeErr, Index, Value);
    end;

    procedure SymbologyToText(Symbology: Enum "DOPSWHS Label Symbology"): Text
    begin
        case Symbology of
            Symbology::EAN13:
                exit('ean13');
            Symbology::GS1128:
                exit('gs1-128');
        end;
        exit('code128');
    end;

    local procedure TextToSymbology(Value: Text; Index: Integer): Enum "DOPSWHS Label Symbology"
    begin
        case LowerCase(Value) of
            'code128', '':
                exit(Enum::"DOPSWHS Label Symbology"::Code128);
            'ean13', 'ean-13':
                exit(Enum::"DOPSWHS Label Symbology"::EAN13);
            'gs1-128', 'gs1128':
                exit(Enum::"DOPSWHS Label Symbology"::GS1128);
        end;
        Error(UnknownSymbologyErr, Index, Value);
    end;

    local procedure AlignToText(Alignment: Enum "DOPSWHS Label Alignment"): Text
    begin
        case Alignment of
            Alignment::Center:
                exit('center');
            Alignment::Right:
                exit('right');
        end;
        exit('left');
    end;

    local procedure TextToAlign(Value: Text; Index: Integer): Enum "DOPSWHS Label Alignment"
    begin
        case LowerCase(Value) of
            'left', '':
                exit(Enum::"DOPSWHS Label Alignment"::Left);
            'center':
                exit(Enum::"DOPSWHS Label Alignment"::Center);
            'right':
                exit(Enum::"DOPSWHS Label Alignment"::Right);
        end;
        Error(UnknownAlignErr, Index, Value);
    end;

    local procedure MimeTypeOf(Base64: Text): Text
    begin
        case true of
            Base64.StartsWith('iVBOR'):
                exit('image/png');
            Base64.StartsWith('/9j/'):
                exit('image/jpeg');
            Base64.StartsWith('R0lGOD'):
                exit('image/gif');
            Base64.StartsWith('Qk'):
                exit('image/bmp');
        end;
        exit('image/png');
    end;

    // ------------------------------------------------------------------
    // JSON helpers (missing or null = default)
    // ------------------------------------------------------------------

    local procedure GetText(Obj: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Obj.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() or Token.AsValue().IsUndefined() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure GetDecimal(Obj: JsonObject; KeyName: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Obj.Get(KeyName, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() or Token.AsValue().IsUndefined() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure GetInteger(Obj: JsonObject; KeyName: Text): Integer
    begin
        exit(Round(GetDecimal(Obj, KeyName), 1));
    end;

    local procedure GetBoolean(Obj: JsonObject; KeyName: Text; Default: Boolean): Boolean
    var
        Token: JsonToken;
    begin
        if not Obj.Get(KeyName, Token) then
            exit(Default);
        if not Token.IsValue() then
            exit(Default);
        if Token.AsValue().IsNull() or Token.AsValue().IsUndefined() then
            exit(Default);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure CheckLength(Value: Text; MaxLength: Integer; Index: Integer; PropertyName: Text): Text
    begin
        if StrLen(Value) > MaxLength then
            Error(TooLongErr, Index, PropertyName, MaxLength);
        exit(Value);
    end;

    local procedure NonNegative(Value: Decimal): Decimal
    begin
        if Value < 0 then
            exit(0);
        exit(Value);
    end;
}
