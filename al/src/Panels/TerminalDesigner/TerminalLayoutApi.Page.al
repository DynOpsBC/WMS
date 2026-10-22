page 72386 "DOPSWHS Terminal Layout API"
{
    // GET .../dynops/warehouse/v2.0/companies(id)/terminalLayouts
    //     ?$filter=terminalCode eq 'T1' and userName eq 'AHMET'
    // Çağıran terminal için GEÇERLİ yerleşimi tek satır olarak döndürür:
    // Terminal > Rol (çağıran BC kullanıcısının rolleri, öncelik sırasıyla) > Tümü.
    // roleCode filtresi verilirse rol çözümlemesini ezer (önizleme/test).
    // "version" alanı terminal önbelleğinin anahtarıdır; değişmediyse terminal
    // yerleşimi yeniden uygulamaz. Salt okunur.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'terminalLayout';
    EntitySetName = 'terminalLayouts';
    SourceTable = "DOPSWHS Terminal Layout";
    SourceTableTemporary = true;
    ODataKeyFields = "Code";
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    Extensible = false;
    Permissions = tabledata "DOPSWHS Terminal Layout" = R,
                  tabledata "DOPSWHS Terminal Layout Line" = R;

    layout
    {
        area(Content)
        {
            repeater(Layouts)
            {
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(appliesTo; AppliesToTxt) { Caption = 'appliesTo'; }
                field(appliesToCode; Rec."Applies-to Code") { Caption = 'appliesToCode'; }
                field(terminalCode; Rec."Request Terminal Code") { Caption = 'terminalCode'; }
                field(roleCode; Rec."Request Role Code") { Caption = 'roleCode'; }
                field(userName; Rec."Request User Name") { Caption = 'userName'; }
                field(version; VersionTxt) { Caption = 'version'; }
                field(layoutJson; LayoutJsonTxt) { Caption = 'layoutJson'; }
            }
        }
    }

    var
        Mgt: Codeunit "DOPSWHS Terminal Layout Mgt";
        Loaded: Boolean;
        VersionTxt: Text;
        LayoutJsonTxt: Text;
        AppliesToTxt: Text;

    trigger OnFindRecord(Which: Text): Boolean
    begin
        if not Loaded then
            LoadEffective();
        exit(Rec.Find(Which));
    end;

    trigger OnAfterGetRecord()
    begin
        VersionTxt := Mgt.GetVersion(EffectiveCode());
        LayoutJsonTxt := Mgt.BuildTerminalJson(EffectiveCode());
        AppliesToTxt := Mgt.AppliesToText(Rec."Applies-to Type");
    end;

    local procedure LoadEffective()
    var
        Layout: Record "DOPSWHS Terminal Layout";
        TerminalCode: Code[20];
        RoleCode: Code[20];
        UserName: Code[20];
        LayoutCode: Code[20];
    begin
        Loaded := true;
        TerminalCode := FilterValue(Rec.GetFilter("Request Terminal Code"));
        RoleCode := FilterValue(Rec.GetFilter("Request Role Code"));
        UserName := FilterValue(Rec.GetFilter("Request User Name"));
        LayoutCode := Mgt.ResolveForRequest(TerminalCode, RoleCode, UserName, CopyStr(UserId(), 1, 50));
        Rec.Init();
        if Layout.Get(LayoutCode) then
            Rec.TransferFields(Layout)
        else
            Rec.Code := 'STANDART';
        Rec."Request Terminal Code" := TerminalCode;
        Rec."Request Role Code" := RoleCode;
        Rec."Request User Name" := UserName;
        Rec.Insert();
    end;

    local procedure EffectiveCode(): Code[20]
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        // Geçici satırın kodu ya gerçek yerleşimdir ya da katalog varsayılanı.
        if Layout.Get(Rec.Code) and Layout.Active then
            exit(Rec.Code);
        exit('');
    end;

    local procedure FilterValue(FilterText: Text): Code[20]
    begin
        // OData "eq" filtresi tek değerli bir aralık olarak gelir; tırnaklar temizlenir.
        FilterText := DelChr(FilterText, '<>', '''');
        if StrPos(FilterText, '|') > 0 then
            exit('');
        exit(CopyStr(UpperCase(FilterText), 1, 20));
    end;
}
