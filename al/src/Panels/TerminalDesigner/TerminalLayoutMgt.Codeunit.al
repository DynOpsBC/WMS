codeunit 72384 "DOPSWHS Terminal Layout Mgt"
{
    // Terminal Ekran Tasarımcısı'nın tek kaynağı:
    //  * KATALOG — el terminalinde yapılandırılabilen ana menü kutuları ve ekran
    //    düğmeleri. Anahtarlar Android TerminalLayoutCatalog.kt ile BİREBİR aynıdır.
    //    Varsayılanlar bugünkü Android menüsünü yansıtır: yerleşim düzenlenmedikçe
    //    terminalde hiçbir şey değişmez.
    //  * ÇÖZÜMLEME — çağıran terminal için geçerli yerleşim: Terminal > Rol > Tümü.
    //  * JSON — tasarımcı denetimi ve terminalLayouts API'si için.
    Permissions = tabledata "DOPSWHS Terminal Layout" = RIMD,
                  tabledata "DOPSWHS Terminal Layout Line" = RIMD,
                  tabledata "DOPSWHS App Role" = R,
                  tabledata "DOPSWHS App User Role" = R,
                  tabledata "DOPSWHS WMS Terminal" = R,
                  tabledata "DOPSWHS Local User" = R;

    trigger OnRun()
    begin
        // Tasarımcı sayfası kaydet/oluştur işlemlerini Codeunit.Run ile çalıştırır:
        // hata olursa işlem geri alınır ve mesaj denetime döner.
        case PendingAction of
            'save':
                PendingResult := SaveLayoutFromJson(PendingJson);
            'create':
                PendingResult := CreateLayoutFromJson(PendingJson);
        end;
    end;

    var
        PendingAction: Text;
        PendingJson: Text;
        PendingResult: Code[20];
        Catalog: JsonArray;
        CatalogBuilt: Boolean;
        HomeScreenTok: Label 'HOME', Locked = true;
        StandardLayoutTok: Label 'STANDART', Locked = true;
        CatalogVersionTok: Label '1', Locked = true;
        DuplicateTargetErr: Label 'Aynı hedef için başka bir etkin yerleşim var: %1. Önce onu pasifleştirin.', Comment = '%1 = layout code';
        RoleMissingErr: Label 'Rol bulunamadı: %1', Comment = '%1 = role code';
        TerminalMissingErr: Label 'Terminal bulunamadı: %1', Comment = '%1 = terminal code';
        TargetCodeMissingErr: Label 'Rol veya terminal kodu seçilmeli.';
        LayoutExistsErr: Label 'Bu kodla bir yerleşim zaten var: %1', Comment = '%1 = layout code';
        LockedItemErr: Label '"%1" gizlenemez; terminale erişim için gereklidir.', Comment = '%1 = item label';

    procedure SetPending(ActionName: Text; Json: Text)
    begin
        PendingAction := ActionName;
        PendingJson := Json;
        PendingResult := '';
    end;

    procedure GetPendingResult(): Code[20]
    begin
        exit(PendingResult);
    end;

    // ------------------------------------------------------------------ katalog

    procedure CatalogVersion(): Text
    begin
        exit(CatalogVersionTok);
    end;

    procedure HomeScreenKey(): Code[30]
    begin
        exit(HomeScreenTok);
    end;

    procedure StandardLayoutCode(): Code[20]
    begin
        exit(StandardLayoutTok);
    end;

    /// <summary>Returns the item catalog (menu tiles + screen buttons) as a JSON array.</summary>
    procedure GetCatalog(): JsonArray
    begin
        BuildCatalog();
        exit(Catalog.Clone().AsArray());
    end;

    /// <summary>Screens the designer can open: the main menu plus screens that have configurable buttons.</summary>
    procedure GetScreens(): JsonArray
    var
        Screens: JsonArray;
    begin
        Screens.Add(ScreenJson('HOME', 'Ana Menü', ''));
        Screens.Add(ScreenJson('LABELS', 'Etiket Çıkar', 'LABELS'));
        Screens.Add(ScreenJson('PUTAWAY', 'Yerleştirme', 'PUTAWAY'));
        Screens.Add(ScreenJson('LICENSE_PLATES', 'LP (Taşıma Kabı)', 'LICENSE_PLATES'));
        Screens.Add(ScreenJson('COUNT', 'Sayım', 'COUNT'));
        Screens.Add(ScreenJson('BIN_INQUIRY', 'Bin Sorgu', 'BIN_INQUIRY'));
        exit(Screens);
    end;

    local procedure ScreenJson(ScreenKey: Text; Title: Text; TileKey: Text): JsonObject
    var
        Obj: JsonObject;
    begin
        Obj.Add('key', ScreenKey);
        Obj.Add('title', Title);
        Obj.Add('tileKey', TileKey);
        exit(Obj);
    end;

    local procedure BuildCatalog()
    begin
        if CatalogBuilt then
            exit;
        Clear(Catalog);
        // Ana menü — Android AppRoot.HomeCategories ile aynı sıra ve kategoriler.
        AddTile('Gelen', 'RECEIVING', 'Mal Kabul', 'Gelen ürünü kaydet, LP''yi başlat', 10, 'LP,LOT', '', false);
        AddTile('Gelen', 'PUTAWAY', 'Yerleştirme', 'Ürünü veya LP''yi rafına kaldır', 20, 'LP,BIN', '', false);
        AddTile('Giden', 'PICKING', 'Toplama', 'Sipariş ürünlerini raflardan topla', 30, 'LP,BIN', '', false);
        AddTile('Giden', 'PACKING', 'Paketleme', 'Toplanan ürünleri kolilere ayır', 40, '', '', false);
        AddTile('Giden', 'SHIPPING', 'Sevkiyat', 'Belgeyi tamamla ve çıkışı kaydet', 50, 'LP', '', false);
        AddTile('İç Operasyon', 'LICENSE_PLATES', 'LP', 'Palet ve taşıma kabı işlemleri', 60, '', '', false);
        AddTile('İç Operasyon', 'HIERARCHICAL_LP', 'Kutu ve Palet', 'Ürün LP''lerini kutuya, kutuları palete bağla', 70, '', 'Yalnız EMU / DKÇ sürümünde', false);
        AddTile('İç Operasyon', 'ADHOC_MOVE', 'Ad-Hoc Hareket', 'Belgesiz raf veya LP hareketi', 80, 'LP,BIN', '', false);
        AddTile('İç Operasyon', 'DIRECTED_MOVE', 'Yönlendirilmiş', 'Hazırlanmış taşıma emrini uygula', 90, 'BIN', '', false);
        AddTile('İç Operasyon', 'COUNT', 'Sayım', 'Hazır sayım belgesini tamamla', 100, 'BIN', '', false);
        AddTile('İç Operasyon', 'COUNT_V2', 'Sayım V2', 'QR okutarak sıfırdan sayım yap', 110, 'BIN', '', false);
        AddTile('İç Operasyon', 'FIRST_COUNT', 'İlk Sayım', 'Sadece madde okut, adet gir', 115, '', 'Yalnız Kitoko sürümünde', false);
        AddTile('Üretim', 'PRODUCTION', 'Üretim', 'Tüketim ve üretim çıkışı kaydet', 120, 'LOT', '', false);
        AddTile('Üretim', 'SUBCONTRACTING', 'Fason İşlemler', 'Fasona sevk ve referansla teslim alma', 130, '', '', false);
        AddTile('Üretim', 'ASSEMBLY', 'Montaj', 'Montaj emrinin sarf ve çıktıları', 140, '', '', false);
        AddTile('Kalite', 'QUALITY', 'Kalite Denetimi', 'Kontrol sonuçlarını değerlendir', 150, '', '', false);
        AddTile('Kalite', 'QUALITY_MGMT', 'MS Kalite', 'Lot blokajlarını ve ölçümleri yönet', 160, '', '', false);
        AddTile('Sorgu', 'ITEM_INQUIRY', 'Ürün Sorgu', 'Ürünün raf, lot ve miktarını bul', 170, '', '', false);
        AddTile('Sorgu', 'LABELS', 'Etiket Çıkar', 'Ürün etiketi · Raf etiketi · A4 belge', 180, '', 'Kitoko / EMU sürümlerinde', false);
        AddTile('Sorgu', 'BIN_INQUIRY', 'Bin Sorgu', 'Bir rafın mevcut içeriğini gör', 190, '', '', false);
        AddTile('Sorgu', 'WHSE_ENTRIES', 'Ambar Hareketleri', 'Geçmiş stok hareketlerini incele', 200, '', '', false);
        AddTile('Destek ve Ayarlar', 'FIELD_SETTINGS', 'Alan Ayarları', 'Kartlarda gösterilen bilgileri seç', 210, '', 'Müşteri sürümlerinde gizli', false);
        AddTile('Destek ve Ayarlar', 'SELF_TEST', 'Sistem Sağlığı', 'Bağlantıları ve servisleri kontrol et', 220, '', 'Müşteri sürümlerinde gizli', false);
        AddTile('Destek ve Ayarlar', 'PRINTERS', 'Yazıcılar', 'Etiket ve belge yazıcısını seç', 230, '', '', false);
        AddTile('Destek ve Ayarlar', 'TEST_CENTER', 'Test Merkezi', 'Operasyon test sonuçlarını incele', 240, '', 'Yalnız yönetici test oturumunda', false);
        AddTile('Destek ve Ayarlar', 'POSTING_TEST', 'Kayıt Testi', 'BC kayıt servislerini doğrula', 250, '', 'Yalnız yönetici test oturumunda', false);
        AddTile('Destek ve Ayarlar', 'CONNECTION', 'Bağlantı', 'Hesap, ortam ve şirket ayarları', 260, '', '', true);

        // Ekran düğmeleri — v1'de terminal yalnız görünürlüğü uygular.
        AddButton('LABELS', 'LABELS.LAYOUT_PICKER', 'Etiket tasarımı seçimi', 'Ekranın üstünde etiket tasarımı seçilir', 10, 'Kitoko');
        AddButton('LABELS', 'LABELS.ALL_ITEMS', 'Tüm ürün etiketleri', 'BC''deki bütün ürünlerin etiketini tek seferde basar', 20, 'DKÇ / EMU');
        AddButton('LABELS', 'LABELS.RANGES', 'Aralık blokları (1–300, 301–500 …)', 'Ürün no sırasına göre blok blok basar', 30, 'Kitoko');
        AddButton('LABELS', 'LABELS.EXCEL', 'Excel listesinden etiket', 'Excel''den yüklenen ürün listesini basar', 40, 'DKÇ / EMU');
        AddButton('LABELS', 'LABELS.PREPARED_LIST', 'Hazır listeden etiket', 'BC''de hazırlanmış listeyi basar', 50, 'DKÇ / EMU');
        AddButton('PUTAWAY', 'PUTAWAY.ALL_TO_ONE_BIN', 'Tümünü Bir Bine', 'Belgedeki bütün yerleştirmeleri tek rafa atar', 10, '');
        AddButton('LICENSE_PLATES', 'LP.CREATE_SINGLE', 'Tekli LP Oluştur', 'Listeden yeni boş LP açar', 10, '');
        AddButton('LICENSE_PLATES', 'LP.PRINT_MTE', 'MTE Yazdır', 'LP detayında MTE etiketi basar', 20, 'BADE (Kitoko''da MTE yok)');
        AddButton('LICENSE_PLATES', 'LP.BREAK', 'Boz', 'LP''yi bozar (içeriği serbest bırakır)', 30, '');
        AddButton('COUNT', 'COUNT.CREATE_NEW', 'Yeni Sayım Oluştur', 'Terminalden yeni sayım belgesi açar', 10, '');
        AddButton('COUNT', 'COUNT.PRINT_LP_LABELS', 'Sayılan LP etiketlerini yazdır', 'Sayım sonrası LP etiketlerini basar', 20, '');
        AddButton('BIN_INQUIRY', 'BIN_INQUIRY.PRINT_LP_LABELS', 'Seçilen LP etiketlerini bas', 'Raf sorgusunda seçili LP etiketlerini basar', 10, '');
        CatalogBuilt := true;
    end;

    local procedure AddTile(Group: Text; ItemKey: Text; DefaultLabel: Text; Description: Text; SortOrder: Integer; Flags: Text; Availability: Text; Locked: Boolean)
    begin
        Catalog.Add(CatalogItem(HomeScreenTok, ItemKey, 'tile', Group, DefaultLabel, Description, SortOrder, Flags, Availability, Locked));
    end;

    local procedure AddButton(ScreenKey: Text; ItemKey: Text; DefaultLabel: Text; Description: Text; SortOrder: Integer; Availability: Text)
    begin
        Catalog.Add(CatalogItem(ScreenKey, ItemKey, 'button', '', DefaultLabel, Description, SortOrder, '', Availability, false));
    end;

    local procedure CatalogItem(ScreenKey: Text; ItemKey: Text; Kind: Text; Group: Text; DefaultLabel: Text; Description: Text; SortOrder: Integer; Flags: Text; Availability: Text; Locked: Boolean): JsonObject
    var
        Obj: JsonObject;
        FlagArr: JsonArray;
        Flag: Text;
    begin
        Obj.Add('screen', ScreenKey);
        Obj.Add('key', ItemKey);
        Obj.Add('kind', Kind);
        Obj.Add('group', Group);
        Obj.Add('label', DefaultLabel);
        Obj.Add('description', Description);
        Obj.Add('sort', SortOrder);
        if Flags <> '' then
            foreach Flag in Flags.Split(',') do
                FlagArr.Add(Flag);
        Obj.Add('flags', FlagArr);
        Obj.Add('availability', Availability);
        Obj.Add('locked', Locked);
        exit(Obj);
    end;

    /// <summary>Fills a temporary line buffer with the catalog defaults (what the terminal shows today).</summary>
    procedure FillDefaults(var TempLine: Record "DOPSWHS Terminal Layout Line" temporary; LayoutCode: Code[20])
    var
        Token: JsonToken;
        Obj: JsonObject;
    begin
        BuildCatalog();
        foreach Token in Catalog do begin
            Obj := Token.AsObject();
            TempLine.Init();
            TempLine."Layout Code" := LayoutCode;
            TempLine."Screen Key" := CopyStr(JText(Obj, 'screen'), 1, MaxStrLen(TempLine."Screen Key"));
            TempLine."Item Key" := CopyStr(JText(Obj, 'key'), 1, MaxStrLen(TempLine."Item Key"));
            TempLine.Visible := true;
            TempLine."Sort Order" := JInt(Obj, 'sort');
            if not TempLine.Insert() then
                TempLine.Modify();
        end;
    end;

    procedure IsCatalogItem(ScreenKey: Code[30]; ItemKey: Code[50]): Boolean
    var
        Obj: JsonObject;
    begin
        exit(FindCatalogItem(ScreenKey, ItemKey, Obj));
    end;

    local procedure FindCatalogItem(ScreenKey: Code[30]; ItemKey: Code[50]; var Found: JsonObject): Boolean
    var
        Token: JsonToken;
        Obj: JsonObject;
    begin
        BuildCatalog();
        foreach Token in Catalog do begin
            Obj := Token.AsObject();
            if (UpperCase(JText(Obj, 'screen')) = ScreenKey) and (UpperCase(JText(Obj, 'key')) = ItemKey) then begin
                Found := Obj;
                exit(true);
            end;
        end;
        exit(false);
    end;

    // ------------------------------------------------------------------ tohumlama

    /// <summary>Creates the company-wide STANDART layout from the catalog when the company has no layout yet.</summary>
    procedure EnsureStandardLayout()
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        if not Layout.IsEmpty() then
            exit;
        SeedDefaults(StandardLayoutTok, 'Standart terminal yerleşimi', Layout."Applies-to Type"::All, '');
    end;

    /// <summary>Creates the layout if missing and adds every catalog item that has no line yet (existing lines are kept).</summary>
    procedure SeedDefaults(LayoutCode: Code[20]; Description: Text[100]; AppliesToType: Option All,Role,Terminal; AppliesToCode: Code[20])
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        if not Layout.Get(LayoutCode) then begin
            Layout.Init();
            Layout.Code := LayoutCode;
            Layout.Description := Description;
            Layout."Applies-to Type" := AppliesToType;
            Layout."Applies-to Code" := AppliesToCode;
            Layout.Active := true;
            Layout."Version No." := 1;
            Layout.Insert(true);
        end;
        AddMissingLines(LayoutCode);
    end;

    procedure AddMissingLines(LayoutCode: Code[20])
    var
        TempDefault: Record "DOPSWHS Terminal Layout Line" temporary;
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        FillDefaults(TempDefault, LayoutCode);
        if TempDefault.FindSet() then
            repeat
                if not Line.Get(LayoutCode, TempDefault."Screen Key", TempDefault."Item Key") then begin
                    Line := TempDefault;
                    Line.Insert();
                end;
            until TempDefault.Next() = 0;
    end;

    // ------------------------------------------------------------------ çözümleme

    /// <summary>Roles of a BC user ordered by assignment priority (lowest first), active roles only.</summary>
    procedure GetUserRoles(UserKey: Code[50]; var Roles: List of [Code[20]])
    var
        UserRole: Record "DOPSWHS App User Role";
        Role: Record "DOPSWHS App Role";
        TempPriority: Record "Integer" temporary;
    begin
        Clear(Roles);
        if UserKey = '' then
            exit;
        UserRole.SetRange("User ID", UserKey);
        UserRole.SetRange(Disabled, false);
        if UserRole.FindSet() then
            repeat
                TempPriority.Number := UserRole.Priority;
                if TempPriority.Insert() then;
            until UserRole.Next() = 0;
        if TempPriority.FindSet() then
            repeat
                UserRole.SetRange(Priority, TempPriority.Number);
                if UserRole.FindSet() then
                    repeat
                        if Role.Get(UserRole."Role Code") and Role.Active then
                            if not Roles.Contains(UserRole."Role Code") then
                                Roles.Add(UserRole."Role Code");
                    until UserRole.Next() = 0;
            until TempPriority.Next() = 0;
    end;

    /// <summary>Effective layout code for a terminal: Terminal &gt; Role (in priority order) &gt; All. Empty = catalog defaults.</summary>
    procedure ResolveLayoutCode(TerminalCode: Code[20]; Roles: List of [Code[20]]): Code[20]
    var
        Layout: Record "DOPSWHS Terminal Layout";
        RoleCode: Code[20];
    begin
        Layout.SetRange(Active, true);
        if TerminalCode <> '' then begin
            Layout.SetRange("Applies-to Type", Layout."Applies-to Type"::Terminal);
            Layout.SetRange("Applies-to Code", TerminalCode);
            if Layout.FindFirst() then
                exit(Layout.Code);
        end;
        foreach RoleCode in Roles do
            if RoleCode <> '' then begin
                Layout.SetRange("Applies-to Type", Layout."Applies-to Type"::Role);
                Layout.SetRange("Applies-to Code", RoleCode);
                if Layout.FindFirst() then
                    exit(Layout.Code);
            end;
        Layout.SetRange("Applies-to Type", Layout."Applies-to Type"::All);
        Layout.SetRange("Applies-to Code");
        if Layout.FindFirst() then
            exit(Layout.Code);
        exit('');
    end;

    /// <summary>Resolves the calling terminal's context. An explicit role wins; otherwise the BC user's roles are used.
    /// A local (PIN) user name supplies the terminal when none was sent.</summary>
    procedure ResolveForRequest(TerminalCode: Code[20]; RoleCode: Code[20]; LocalUserName: Code[20]; BcUserKey: Code[50]): Code[20]
    var
        LocalUser: Record "DOPSWHS Local User";
        Roles: List of [Code[20]];
    begin
        if (TerminalCode = '') and (LocalUserName <> '') then
            if LocalUser.Get(LocalUserName) then
                TerminalCode := LocalUser."Terminal Code";
        if RoleCode <> '' then
            Roles.Add(RoleCode)
        else
            GetUserRoles(BcUserKey, Roles);
        exit(ResolveLayoutCode(TerminalCode, Roles));
    end;

    /// <summary>Catalog defaults overlaid with the layout's lines. Unknown (non-catalog) lines are ignored.</summary>
    procedure BuildEffectiveLines(LayoutCode: Code[20]; var TempLine: Record "DOPSWHS Terminal Layout Line" temporary)
    var
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        TempLine.Reset();
        TempLine.DeleteAll();
        FillDefaults(TempLine, LayoutCode);
        if LayoutCode = '' then
            exit;
        Line.SetRange("Layout Code", LayoutCode);
        if Line.FindSet() then
            repeat
                if TempLine.Get(LayoutCode, Line."Screen Key", Line."Item Key") then begin
                    TempLine.TransferFields(Line, false);
                    if IsLocked(Line."Screen Key", Line."Item Key") then
                        TempLine.Visible := true;
                    TempLine.Modify();
                end;
            until Line.Next() = 0;
    end;

    local procedure IsLocked(ScreenKey: Code[30]; ItemKey: Code[50]): Boolean
    var
        Obj: JsonObject;
    begin
        if not FindCatalogItem(ScreenKey, ItemKey, Obj) then
            exit(false);
        exit(JBool(Obj, 'locked'));
    end;

    /// <summary>Cache key for the terminal: changes whenever the effective layout or catalog changes.</summary>
    procedure GetVersion(LayoutCode: Code[20]): Text
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        if (LayoutCode = '') or not Layout.Get(LayoutCode) then
            exit('STD.0.c' + CatalogVersionTok);
        exit(StrSubstNo('%1.%2.c%3', Layout.Code, Layout."Version No.", CatalogVersionTok));
    end;

    // ------------------------------------------------------------------ terminal JSON

    /// <summary>Compact JSON consumed by the Android TerminalLayoutRepository.
    /// Only non-default attributes are written (empty label/note and false flags are omitted).</summary>
    procedure BuildTerminalJson(LayoutCode: Code[20]): Text
    var
        TempLine: Record "DOPSWHS Terminal Layout Line" temporary;
        Root: JsonObject;
        Items: JsonArray;
        Item: JsonObject;
        Req: JsonArray;
        Result: Text;
    begin
        BuildEffectiveLines(LayoutCode, TempLine);
        TempLine.SetCurrentKey("Layout Code", "Screen Key", "Sort Order");
        if TempLine.FindSet() then
            repeat
                Clear(Item);
                Clear(Req);
                Item.Add('screen', TempLine."Screen Key");
                Item.Add('key', TempLine."Item Key");
                Item.Add('visible', TempLine.Visible);
                Item.Add('sort', TempLine."Sort Order");
                if TempLine."Label Override" <> '' then
                    Item.Add('label', TempLine."Label Override");
                if TempLine.Note <> '' then
                    Item.Add('note', TempLine.Note);
                if TempLine."Require LP Scan" then
                    Req.Add('LP');
                if TempLine."Require Lot No." then
                    Req.Add('LOT');
                if TempLine."Require Bin Scan" then
                    Req.Add('BIN');
                if Req.Count() > 0 then
                    Item.Add('require', Req);
                Items.Add(Item);
            until TempLine.Next() = 0;
        Root.Add('code', LayoutCode);
        Root.Add('version', GetVersion(LayoutCode));
        Root.Add('items', Items);
        Root.WriteTo(Result);
        exit(Result);
    end;

    // ------------------------------------------------------------------ tasarımcı JSON

    procedure BuildDesignerJson(SelectedCode: Code[20]): Text
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Role: Record "DOPSWHS App Role";
        Terminal: Record "DOPSWHS WMS Terminal";
        Root: JsonObject;
        Layouts: JsonArray;
        Roles: JsonArray;
        Terminals: JsonArray;
        Obj: JsonObject;
        Result: Text;
    begin
        EnsureStandardLayout();
        if (SelectedCode = '') or not Layout.Get(SelectedCode) then begin
            Layout.Reset();
            Layout.SetRange("Applies-to Type", Layout."Applies-to Type"::All);
            if not Layout.FindFirst() then begin
                Layout.Reset();
                Layout.FindFirst();
            end;
            SelectedCode := Layout.Code;
        end;
        Layout.Reset();
        if Layout.FindSet() then
            repeat
                Layouts.Add(HeaderJson(Layout));
            until Layout.Next() = 0;
        Role.SetRange(Active, true);
        if Role.FindSet() then
            repeat
                Clear(Obj);
                Obj.Add('code', Role.Code);
                Obj.Add('description', Role.Description);
                Roles.Add(Obj);
            until Role.Next() = 0;
        Terminal.SetRange(Disabled, false);
        if Terminal.FindSet() then
            repeat
                Clear(Obj);
                Obj.Add('code', Terminal.Code);
                Terminals.Add(Obj);
            until Terminal.Next() = 0;
        Root.Add('catalogVersion', CatalogVersionTok);
        Root.Add('catalog', GetCatalog());
        Root.Add('screens', GetScreens());
        Root.Add('layouts', Layouts);
        Root.Add('roles', Roles);
        Root.Add('terminals', Terminals);
        Root.Add('layout', LayoutJson(SelectedCode));
        Root.WriteTo(Result);
        exit(Result);
    end;

    local procedure HeaderJson(Layout: Record "DOPSWHS Terminal Layout"): JsonObject
    var
        Obj: JsonObject;
    begin
        Obj.Add('code', Layout.Code);
        Obj.Add('description', Layout.Description);
        Obj.Add('appliesTo', AppliesToText(Layout."Applies-to Type"));
        Obj.Add('appliesToCode', Layout."Applies-to Code");
        Obj.Add('active', Layout.Active);
        Obj.Add('version', Layout."Version No.");
        if Layout."Last Modified At" <> 0DT then
            Obj.Add('modifiedAt', Format(Layout."Last Modified At", 0, 9))
        else
            Obj.Add('modifiedAt', '');
        Obj.Add('modifiedBy', Layout."Last Modified By");
        exit(Obj);
    end;

    /// <summary>Full layout (header + every catalog item, defaults merged) for the designer.</summary>
    procedure LayoutJson(LayoutCode: Code[20]): JsonObject
    var
        Layout: Record "DOPSWHS Terminal Layout";
        TempLine: Record "DOPSWHS Terminal Layout Line" temporary;
        Obj: JsonObject;
        Lines: JsonArray;
    begin
        if Layout.Get(LayoutCode) then
            Obj := HeaderJson(Layout);
        BuildEffectiveLines(LayoutCode, TempLine);
        TempLine.SetCurrentKey("Layout Code", "Screen Key", "Sort Order");
        if TempLine.FindSet() then
            repeat
                Lines.Add(LineJson(TempLine));
            until TempLine.Next() = 0;
        Obj.Add('lines', Lines);
        exit(Obj);
    end;

    local procedure LineJson(Line: Record "DOPSWHS Terminal Layout Line"): JsonObject
    var
        Obj: JsonObject;
    begin
        Obj.Add('screen', Line."Screen Key");
        Obj.Add('key', Line."Item Key");
        Obj.Add('visible', Line.Visible);
        Obj.Add('sort', Line."Sort Order");
        Obj.Add('label', Line."Label Override");
        Obj.Add('note', Line.Note);
        Obj.Add('requireLp', Line."Require LP Scan");
        Obj.Add('requireLot', Line."Require Lot No.");
        Obj.Add('requireBin', Line."Require Bin Scan");
        exit(Obj);
    end;

    /// <summary>What a terminal with the given role/terminal would get, for the designer's "Önizleme rolü".</summary>
    procedure BuildPreviewJson(RoleCode: Code[20]; TerminalCode: Code[20]): Text
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Roles: List of [Code[20]];
        LayoutCode: Code[20];
        Root: JsonObject;
        Result: Text;
    begin
        if RoleCode <> '' then
            Roles.Add(RoleCode);
        LayoutCode := ResolveLayoutCode(TerminalCode, Roles);
        Root.Add('roleCode', RoleCode);
        Root.Add('terminalCode', TerminalCode);
        Root.Add('layoutCode', LayoutCode);
        if Layout.Get(LayoutCode) then
            Root.Add('layoutDescription', Layout.Description)
        else
            Root.Add('layoutDescription', 'Standart (katalog varsayılanı)');
        Root.Add('layout', LayoutJson(LayoutCode));
        Root.WriteTo(Result);
        exit(Result);
    end;

    // ------------------------------------------------------------------ kaydet / oluştur / sil

    /// <summary>Saves a layout sent by the designer. Lines are replaced; version is incremented.</summary>
    procedure SaveLayoutFromJson(Json: Text): Code[20]
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Line: Record "DOPSWHS Terminal Layout Line";
        Root: JsonObject;
        Token: JsonToken;
        Obj: JsonObject;
        CatalogObj: JsonObject;
        LayoutCode: Code[20];
        ScreenKey: Code[30];
        ItemKey: Code[50];
        IsNew: Boolean;
    begin
        Root.ReadFrom(Json);
        LayoutCode := CopyStr(UpperCase(JText(Root, 'code')), 1, MaxStrLen(LayoutCode));
        Layout.LockTable();
        IsNew := not Layout.Get(LayoutCode);
        if IsNew then begin
            Layout.Init();
            Layout.Code := LayoutCode;
        end;
        Layout.Description := CopyStr(JText(Root, 'description'), 1, MaxStrLen(Layout.Description));
        Layout."Applies-to Type" := AppliesToOption(JText(Root, 'appliesTo'));
        Layout."Applies-to Code" := CopyStr(UpperCase(JText(Root, 'appliesToCode')), 1, MaxStrLen(Layout."Applies-to Code"));
        if Layout."Applies-to Type" = Layout."Applies-to Type"::All then
            Layout."Applies-to Code" := '';
        if Root.Contains('active') then
            Layout.Active := JBool(Root, 'active');
        ValidateTarget(Layout);
        Layout."Version No." += 1;
        if IsNew then
            Layout.Insert(true)
        else
            Layout.Modify(true);

        Line.SetRange("Layout Code", LayoutCode);
        Line.DeleteAll();
        if Root.Get('lines', Token) and Token.IsArray() then
            foreach Token in Token.AsArray() do begin
                Obj := Token.AsObject();
                ScreenKey := CopyStr(UpperCase(JText(Obj, 'screen')), 1, MaxStrLen(ScreenKey));
                ItemKey := CopyStr(UpperCase(JText(Obj, 'key')), 1, MaxStrLen(ItemKey));
                if FindCatalogItem(ScreenKey, ItemKey, CatalogObj) then begin
                    Line.Init();
                    Line."Layout Code" := LayoutCode;
                    Line."Screen Key" := ScreenKey;
                    Line."Item Key" := ItemKey;
                    Line.Visible := JBool(Obj, 'visible');
                    if JBool(CatalogObj, 'locked') and not Line.Visible then
                        Error(LockedItemErr, JText(CatalogObj, 'label'));
                    Line."Sort Order" := JInt(Obj, 'sort');
                    Line."Label Override" := CopyStr(JText(Obj, 'label').Trim(), 1, MaxStrLen(Line."Label Override"));
                    if Line."Label Override" = JText(CatalogObj, 'label') then
                        Line."Label Override" := '';
                    Line.Note := CopyStr(JText(Obj, 'note').Trim(), 1, MaxStrLen(Line.Note));
                    Line."Require LP Scan" := JBool(Obj, 'requireLp') and FlagSupported(CatalogObj, 'LP');
                    Line."Require Lot No." := JBool(Obj, 'requireLot') and FlagSupported(CatalogObj, 'LOT');
                    Line."Require Bin Scan" := JBool(Obj, 'requireBin') and FlagSupported(CatalogObj, 'BIN');
                    if not Line.Insert() then
                        Line.Modify();
                end;
            end;
        // Eksik katalog öğeleri varsayılanla tamamlanır: kaydedilen yerleşim her zaman tamdır.
        AddMissingLines(LayoutCode);
        exit(LayoutCode);
    end;

    /// <summary>Creates a new layout copied from another layout (or from catalog defaults when CopyFrom is empty).</summary>
    procedure CreateLayout(LayoutCode: Code[20]; Description: Text[100]; AppliesToType: Option All,Role,Terminal; AppliesToCode: Code[20]; CopyFrom: Code[20])
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Source: Record "DOPSWHS Terminal Layout Line";
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        if Layout.Get(LayoutCode) then
            Error(LayoutExistsErr, LayoutCode);
        Layout.Init();
        Layout.Code := LayoutCode;
        Layout.Description := Description;
        Layout."Applies-to Type" := AppliesToType;
        Layout."Applies-to Code" := AppliesToCode;
        if AppliesToType = AppliesToType::All then
            Layout."Applies-to Code" := '';
        Layout.Active := true;
        Layout."Version No." := 1;
        ValidateTarget(Layout);
        Layout.Insert(true);
        if CopyFrom <> '' then begin
            Source.SetRange("Layout Code", CopyFrom);
            if Source.FindSet() then
                repeat
                    Line := Source;
                    Line."Layout Code" := LayoutCode;
                    Line.Insert();
                until Source.Next() = 0;
        end;
        AddMissingLines(LayoutCode);
    end;

    procedure CreateLayoutFromJson(Json: Text): Code[20]
    var
        Root: JsonObject;
        LayoutCode: Code[20];
    begin
        Root.ReadFrom(Json);
        LayoutCode := CopyStr(UpperCase(JText(Root, 'code')).Trim(), 1, MaxStrLen(LayoutCode));
        CreateLayout(LayoutCode,
            CopyStr(JText(Root, 'description'), 1, 100),
            AppliesToOption(JText(Root, 'appliesTo')),
            CopyStr(UpperCase(JText(Root, 'appliesToCode')), 1, 20),
            CopyStr(UpperCase(JText(Root, 'copyFrom')), 1, 20));
        exit(LayoutCode);
    end;

    procedure DeleteLayout(LayoutCode: Code[20])
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        if Layout.Get(LayoutCode) then
            Layout.Delete(true);
    end;

    local procedure ValidateTarget(var Layout: Record "DOPSWHS Terminal Layout")
    var
        Role: Record "DOPSWHS App Role";
        Terminal: Record "DOPSWHS WMS Terminal";
        Other: Record "DOPSWHS Terminal Layout";
    begin
        case Layout."Applies-to Type" of
            Layout."Applies-to Type"::Role:
                begin
                    if Layout."Applies-to Code" = '' then
                        Error(TargetCodeMissingErr);
                    if not Role.Get(Layout."Applies-to Code") then
                        Error(RoleMissingErr, Layout."Applies-to Code");
                end;
            Layout."Applies-to Type"::Terminal:
                begin
                    if Layout."Applies-to Code" = '' then
                        Error(TargetCodeMissingErr);
                    if not Terminal.Get(Layout."Applies-to Code") then
                        Error(TerminalMissingErr, Layout."Applies-to Code");
                end;
        end;
        if not Layout.Active then
            exit;
        Other.SetFilter(Code, '<>%1', Layout.Code);
        Other.SetRange("Applies-to Type", Layout."Applies-to Type");
        Other.SetRange("Applies-to Code", Layout."Applies-to Code");
        Other.SetRange(Active, true);
        if Other.FindFirst() then
            Error(DuplicateTargetErr, Other.Code);
    end;

    procedure AppliesToText(AppliesToType: Option All,Role,Terminal): Text
    begin
        case AppliesToType of
            AppliesToType::Role:
                exit('role');
            AppliesToType::Terminal:
                exit('terminal');
        end;
        exit('all');
    end;

    procedure AppliesToOption(Value: Text): Option All,Role,Terminal
    var
        Result: Option All,Role,Terminal;
    begin
        case LowerCase(Value) of
            'role':
                exit(Result::Role);
            'terminal':
                exit(Result::Terminal);
        end;
        exit(Result::All);
    end;

    local procedure FlagSupported(CatalogObj: JsonObject; Flag: Text): Boolean
    var
        Token: JsonToken;
        FlagToken: JsonToken;
    begin
        if not CatalogObj.Get('flags', Token) then
            exit(false);
        foreach FlagToken in Token.AsArray() do
            if FlagToken.AsValue().AsText() = Flag then
                exit(true);
        exit(false);
    end;

    // ------------------------------------------------------------------ JSON yardımcıları

    local procedure JText(Obj: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure JBool(Obj: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        if Token.AsValue().IsNull() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure JInt(Obj: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;
}
