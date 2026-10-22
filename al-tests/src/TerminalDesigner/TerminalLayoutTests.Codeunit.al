codeunit 72149 "DOPSWHS Terminal Layout Tests"
{
    // Terminal Ekran Tasarımcısı: tohumlama, geçerli yerleşim çözümlemesi
    // (Terminal > Rol > Tümü) ve terminalLayouts API JSON'u.
    Subtype = Test;

    var
        Assert: Codeunit Assert;
        Mgt: Codeunit "DOPSWHS Terminal Layout Mgt";
        RoleTok: Label 'TDROLE', Locked = true;
        Role2Tok: Label 'TDROLE2', Locked = true;
        TerminalTok: Label 'TDTERM', Locked = true;

    [Test]
    procedure SeedCreatesStandardLayoutWithEveryCatalogItem()
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        Reset();
        Mgt.EnsureStandardLayout();

        Assert.IsTrue(Layout.Get('STANDART'), 'STANDART layout must be seeded.');
        Assert.AreEqual(Layout."Applies-to Type"::All, Layout."Applies-to Type", 'Seeded layout applies to all terminals.');
        Assert.IsTrue(Layout.Active, 'Seeded layout is active.');
        Line.SetRange("Layout Code", 'STANDART');
        Assert.AreEqual(Mgt.GetCatalog().Count(), Line.Count(), 'Every catalog item gets a line.');
        Line.Get('STANDART', 'HOME', 'RECEIVING');
        Assert.IsTrue(Line.Visible, 'Defaults keep tiles visible.');
        Assert.AreEqual(10, Line."Sort Order", 'Receiving is the first tile, as on the terminal today.');
        Assert.AreEqual('', Line."Label Override", 'Defaults do not rename.');
        Line.Get('STANDART', 'LABELS', 'LABELS.RANGES');
        Assert.IsTrue(Line.Visible, 'Label range buttons default to visible (the build decides).');

        // Second call must not duplicate or reset an edited line.
        Line.Get('STANDART', 'HOME', 'PICKING');
        Line.Visible := false;
        Line.Modify();
        Mgt.EnsureStandardLayout();
        Mgt.AddMissingLines('STANDART');
        Line.Get('STANDART', 'HOME', 'PICKING');
        Assert.IsFalse(Line.Visible, 'Seeding never overwrites a manager edit.');
    end;

    [Test]
    procedure ResolutionPrefersTerminalThenRoleThenAll()
    var
        Roles: List of [Code[20]];
        NoRoles: List of [Code[20]];
    begin
        Reset();
        CreateTargets();
        Mgt.CreateLayout('ALLX', 'Tümü', 0, '', '');
        Mgt.CreateLayout('ROLEX', 'Rol', 1, RoleTok, '');
        Mgt.CreateLayout('TERMX', 'Terminal', 2, TerminalTok, '');
        Roles.Add(RoleTok);

        Assert.AreEqual('TERMX', Mgt.ResolveLayoutCode(TerminalTok, Roles), 'Terminal layout wins.');
        Assert.AreEqual('ROLEX', Mgt.ResolveLayoutCode('', Roles), 'Role layout when no terminal layout.');
        Assert.AreEqual('ROLEX', Mgt.ResolveLayoutCode('OTHER', Roles), 'Unknown terminal falls back to role.');
        Assert.AreEqual('ALLX', Mgt.ResolveLayoutCode('OTHER', NoRoles), 'All layout as last resort.');

        SetActive('TERMX', false);
        Assert.AreEqual('ROLEX', Mgt.ResolveLayoutCode(TerminalTok, Roles), 'Inactive terminal layout is skipped.');
        SetActive('ALLX', false);
        SetActive('ROLEX', false);
        Assert.AreEqual('', Mgt.ResolveLayoutCode(TerminalTok, Roles), 'No active layout = catalog defaults.');
    end;

    [Test]
    procedure UserRolesFollowPriorityAndLocalUserGivesTerminal()
    var
        UserRole: Record "DOPSWHS App User Role";
        LocalUser: Record "DOPSWHS Local User";
        Roles: List of [Code[20]];
    begin
        Reset();
        CreateTargets();
        AddUserRole('TDUSER', Role2Tok, 50);
        AddUserRole('TDUSER', RoleTok, 10);
        Mgt.GetUserRoles('TDUSER', Roles);
        Assert.AreEqual(2, Roles.Count(), 'Both roles are returned.');
        Assert.AreEqual(RoleTok, Roles.Get(1), 'Lowest priority value comes first.');

        Mgt.CreateLayout('ROLE2X', 'Rol 2', 1, Role2Tok, '');
        Assert.AreEqual('ROLE2X', Mgt.ResolveForRequest('', '', '', 'TDUSER'), 'Only role with a layout applies.');
        Mgt.CreateLayout('ROLEX', 'Rol 1', 1, RoleTok, '');
        Assert.AreEqual('ROLEX', Mgt.ResolveForRequest('', '', '', 'TDUSER'), 'Higher priority role wins.');
        Assert.AreEqual('ROLE2X', Mgt.ResolveForRequest('', Role2Tok, '', 'TDUSER'), 'Explicit role overrides.');

        Mgt.CreateLayout('TERMX', 'Terminal', 2, TerminalTok, '');
        LocalUser.Init();
        LocalUser.Username := 'TDPIN';
        LocalUser."Terminal Code" := TerminalTok;
        if not LocalUser.Insert() then
            LocalUser.Modify();
        Assert.AreEqual('TERMX', Mgt.ResolveForRequest('', '', 'TDPIN', 'TDUSER'), 'Local user supplies its terminal.');
        UserRole.SetRange("User ID", 'TDUSER');
        UserRole.DeleteAll();
    end;

    [Test]
    procedure TerminalJsonIsCompactAndCarriesOverrides()
    var
        Line: Record "DOPSWHS Terminal Layout Line";
        Root: JsonObject;
        Token: JsonToken;
        Item: JsonObject;
        FoundReceiving: Boolean;
        FoundPicking: Boolean;
    begin
        Reset();
        Mgt.EnsureStandardLayout();
        Line.Get('STANDART', 'HOME', 'RECEIVING');
        Line.Visible := false;
        Line."Label Override" := 'Giriş';
        Line."Require Lot No." := true;
        Line.Modify();

        Root.ReadFrom(Mgt.BuildTerminalJson('STANDART'));
        Root.Get('version', Token);
        Assert.AreEqual(Mgt.GetVersion('STANDART'), Token.AsValue().AsText(), 'Version is the cache key.');
        Root.Get('items', Token);
        Assert.AreEqual(Mgt.GetCatalog().Count(), Token.AsArray().Count(), 'Every catalog item is sent.');
        foreach Token in Token.AsArray() do begin
            Item := Token.AsObject();
            if JText(Item, 'key') = 'RECEIVING' then begin
                FoundReceiving := true;
                Assert.AreEqual('false', JText(Item, 'visible'), 'Hidden tile.');
                Assert.AreEqual('Giriş', JText(Item, 'label'), 'Label override is sent.');
                Assert.IsTrue(Item.Contains('require'), 'Required lot is sent.');
            end;
            if JText(Item, 'key') = 'PICKING' then begin
                FoundPicking := true;
                Assert.IsFalse(Item.Contains('label'), 'Empty label is omitted.');
                Assert.IsFalse(Item.Contains('require'), 'No required scans omitted.');
            end;
        end;
        Assert.IsTrue(FoundReceiving and FoundPicking, 'Tiles are present.');

        Root.ReadFrom(Mgt.BuildTerminalJson(''));
        Root.Get('version', Token);
        Assert.AreEqual('STD.0.c' + Mgt.CatalogVersion(), Token.AsValue().AsText(), 'Defaults have a stable version.');
    end;

    [Test]
    procedure SaveFromDesignerBumpsVersionAndRejectsLockedHide()
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Line: Record "DOPSWHS Terminal Layout Line";
        VersionBefore: Integer;
    begin
        Reset();
        Mgt.EnsureStandardLayout();
        Layout.Get('STANDART');
        VersionBefore := Layout."Version No.";

        Mgt.SaveLayoutFromJson('{"code":"STANDART","description":"Std","appliesTo":"all","active":true,"lines":[' +
            '{"screen":"HOME","key":"PICKING","visible":false,"sort":5,"label":"Toplama","note":"","requireLp":true,"requireLot":true,"requireBin":false},' +
            '{"screen":"HOME","key":"BOGUS","visible":false,"sort":1}]}');
        Layout.Get('STANDART');
        Assert.AreEqual(VersionBefore + 1, Layout."Version No.", 'Save increments version.');
        Line.Get('STANDART', 'HOME', 'PICKING');
        Assert.IsFalse(Line.Visible, 'Visibility saved.');
        Assert.AreEqual(5, Line."Sort Order", 'Order saved.');
        Assert.AreEqual('', Line."Label Override", 'Label equal to default is not stored.');
        Assert.IsTrue(Line."Require LP Scan", 'Supported flag saved.');
        Assert.IsFalse(Line."Require Lot No.", 'Unsupported flag (picking has no lot) ignored.');
        Assert.IsFalse(Line.Get('STANDART', 'HOME', 'BOGUS'), 'Unknown keys are dropped.');
        Line.SetRange("Layout Code", 'STANDART');
        Assert.AreEqual(Mgt.GetCatalog().Count(), Line.Count(), 'Missing items are completed with defaults.');

        asserterror Mgt.SaveLayoutFromJson('{"code":"STANDART","appliesTo":"all","lines":[{"screen":"HOME","key":"CONNECTION","visible":false,"sort":1}]}');
        Assert.ExpectedError('gizlenemez');
    end;

    [Test]
    procedure DuplicateActiveTargetIsRejected()
    begin
        Reset();
        CreateTargets();
        Mgt.CreateLayout('ROLEX', 'Rol', 1, RoleTok, '');
        asserterror Mgt.CreateLayout('ROLEY', 'Rol tekrar', 1, RoleTok, '');
        Assert.ExpectedError('ROLEX');
        asserterror Mgt.CreateLayout('BADROLE', 'Yok', 1, 'NOSUCHROLE', '');
        Assert.ExpectedError('Rol bulunamadı');
    end;

    [Test]
    procedure CreateCopiesSourceLayout()
    var
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        Reset();
        CreateTargets();
        Mgt.EnsureStandardLayout();
        Line.Get('STANDART', 'LABELS', 'LABELS.RANGES');
        Line.Visible := false;
        Line.Modify();
        Mgt.CreateLayoutFromJson('{"code":"dkc","description":"DKÇ","appliesTo":"terminal","appliesToCode":"' + TerminalTok + '","copyFrom":"STANDART"}');
        Line.Get('DKC', 'LABELS', 'LABELS.RANGES');
        Assert.IsFalse(Line.Visible, 'Copy keeps the hidden range buttons.');
    end;

    local procedure Reset()
    var
        Layout: Record "DOPSWHS Terminal Layout";
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        Line.DeleteAll();
        Layout.DeleteAll();
    end;

    local procedure CreateTargets()
    var
        Role: Record "DOPSWHS App Role";
        Terminal: Record "DOPSWHS WMS Terminal";
    begin
        if not Role.Get(RoleTok) then begin
            Role.Init();
            Role.Code := RoleTok;
            Role.Active := true;
            Role.Insert();
        end;
        if not Role.Get(Role2Tok) then begin
            Role.Init();
            Role.Code := Role2Tok;
            Role.Active := true;
            Role.Insert();
        end;
        if not Terminal.Get(TerminalTok) then begin
            Terminal.Init();
            Terminal.Code := TerminalTok;
            Terminal.Insert();
        end;
    end;

    local procedure AddUserRole(UserKey: Code[50]; RoleCode: Code[20]; Priority: Integer)
    var
        UserRole: Record "DOPSWHS App User Role";
    begin
        UserRole.Init();
        UserRole."User ID" := UserKey;
        UserRole."Role Code" := RoleCode;
        UserRole.Priority := Priority;
        if not UserRole.Insert() then
            UserRole.Modify();
    end;

    local procedure SetActive(LayoutCode: Code[20]; IsActive: Boolean)
    var
        Layout: Record "DOPSWHS Terminal Layout";
    begin
        Layout.Get(LayoutCode);
        Layout.Active := IsActive;
        Layout.Modify();
    end;

    local procedure JText(Obj: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Obj.Get(Name, Token) then
            exit('');
        exit(Token.AsValue().AsText());
    end;
}
