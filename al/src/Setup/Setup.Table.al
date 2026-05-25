table 72000 "DOPSWHS Setup"
{
    Caption = 'Advanced WMS Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
            InitValue = '';
            DataClassification = SystemMetadata;
        }
        field(10; "LP No. Series"; Code[20])
        {
            Caption = 'LP No. Series';
            TableRelation = "No. Series";
        }
        field(20; "SSCC No. Series"; Code[20])
        {
            Caption = 'SSCC No. Series';
            TableRelation = "No. Series";
        }
        field(30; "GS1 Company Prefix"; Code[12])
        {
            Caption = 'GS1 Company Prefix';
        }
        field(40; "Default Location Code"; Code[10])
        {
            Caption = 'Default Location Code';
            TableRelation = Location;
        }
        field(50; "Print Channel"; Enum "DOPSWHS Print Channel")
        {
            Caption = 'Print Channel';
        }
        field(60; "PrintNode API Key Set"; Boolean)
        {
            Caption = 'PrintNode API Key Set';
            Editable = false;
        }
        field(70; "Max LP Nesting Depth"; Integer)
        {
            Caption = 'Max LP Nesting Depth';
            InitValue = 3;
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    trigger OnInsert()
    var
        ExistingSetup: Record "DOPSWHS Setup";
    begin
        "Primary Key" := '';
        if ExistingSetup.Get('') then
            Error('Only one Advanced WMS Setup row is allowed.');
    end;
}
