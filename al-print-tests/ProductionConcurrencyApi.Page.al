page 72189 "DOPSWHS Sandbox HTTP Fixture"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'sandboxTests';
    APIVersion = 'v1.0';
    EntityName = 'productionFixture';
    EntitySetName = 'productionFixtures';
    SourceTable = Company;
    ODataKeyFields = Id;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.Id) { }
                field(name; Rec.Name) { }
            }
        }
    }
    trigger OnOpenPage()
    begin
        Guard();
        Rec.SetRange(Name, CompanyName());
    end;
    [ServiceEnabled]
    procedure setupFixture()
    begin
        Guard();
        Tests.SetupConcurrentHttpFixture();
    end;
    [ServiceEnabled]
    procedure verifyPrepared()
    begin
        Guard();
        Tests.VerifyConcurrentHttpFixture(false);
    end;
    [ServiceEnabled]
    procedure verifyDelivered()
    begin
        Guard();
        Tests.VerifyConcurrentHttpFixture(true);
    end;
    [ServiceEnabled]
    procedure cleanupFixture()
    begin
        Guard();
        Tests.CleanupProductionPalletFixtures();
    end;
    [ServiceEnabled]
    procedure previewLegacySources(): Text
    var
        Scope: Record "DOPSWHS LP Header";
        Mgt: Codeunit "DOPSWHS LP Management";
    begin
        Guard();
        exit(Mgt.RepairMissingStockSources(Scope, false));
    end;
    local procedure Guard()
    begin
        if not Environment.IsSandbox() or (LowerCase(Environment.GetEnvironmentName()) <> 'sand0309') then
            Error('This fixture API is restricted to sand0309 Sandbox.');
    end;
    var
        Tests: Codeunit "DOPSWHS Prod Pallet Tests";
        Environment: Codeunit "Environment Information";
}
