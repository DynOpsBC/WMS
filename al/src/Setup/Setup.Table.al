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
        field(80; "Webhook Endpoint"; Text[250])
        {
            Caption = 'Webhook Endpoint';
            DataClassification = CustomerContent;
            ExtendedDatatype = URL;
        }
        field(90; "Count Sheet No. Series"; Code[20])
        {
            Caption = 'Count Sheet No. Series';
            TableRelation = "No. Series";
            DataClassification = CustomerContent;
        }
        field(100; "License Tier"; Option)
        {
            Caption = 'License Tier';
            OptionMembers = Essentials,Advanced,Enterprise;
            OptionCaption = 'Essentials,Advanced,Enterprise';
            DataClassification = CustomerContent;
        }
        field(110; "Device Limit"; Integer)
        {
            Caption = 'Device Limit';
            InitValue = 10;
            DataClassification = CustomerContent;
        }
        field(120; "WI Migration Complete"; Boolean)
        {
            Caption = 'WI Migration Complete';
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
