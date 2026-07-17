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
        field(130; "Print Relay URL"; Text[250])
        {
            Caption = 'Print Relay URL';
            DataClassification = CustomerContent;
            ExtendedDatatype = URL;
            ToolTip = 'Base URL of the print-relay Azure Function used by the self-hosted local agent.';
        }
        field(140; "Print Token TTL Hours"; Integer)
        {
            Caption = 'Print Token TTL Hours';
            DataClassification = CustomerContent;
            InitValue = 8760;
            ToolTip = 'Lifetime in hours of agent tokens. Zero disables rotation.';
        }
        field(150; "License Service URL"; Text[250])
        {
            Caption = 'License Service URL';
            DataClassification = CustomerContent;
            ExtendedDatatype = URL;
            ToolTip = 'Base URL of the DynOps licensing-service Azure Function (e.g. https://bcwms-licensing-func.azurewebsites.net).';
        }
        field(160; "License Key"; Text[2048])
        {
            Caption = 'License Key (JWT)';
            DataClassification = CustomerContent;
            ToolTip = 'RS256 JWT issued by DynOps licensing-service. Pasted from the customer portal.';
        }
        field(170; "License Status"; Enum "DOPSWHS License Status")
        {
            Caption = 'License Status';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(180; "License Last Verified At"; DateTime)
        {
            Caption = 'License Last Verified At';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(190; "License Expires At"; DateTime)
        {
            Caption = 'License Expires At';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(200; "License Seats"; Integer)
        {
            Caption = 'License Seats';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(210; "License Email"; Text[100])
        {
            Caption = 'License Email';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(220; "License Status Message"; Text[250])
        {
            Caption = 'License Status Message';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(230; "Show SO Shipment Mobile"; Boolean)
        {
            // Müşteri toplantısı kararı: sipariş bazlı (Sales Order) sevkiyat
            // terminalde opsiyonel olsun. Varsayılan açık — kapatınca el
            // terminali sadece Warehouse Shipment belgelerini gösterir.
            Caption = 'Show SO Shipment on Mobile';
            DataClassification = CustomerContent;
            InitValue = true;
        }
        field(240; "Lot No. Series"; Code[20])
        {
            // Otomatik Lot numarası üretimi (mal kabulde lot boş bırakılırsa).
            Caption = 'Lot No. Series';
            DataClassification = CustomerContent;
            TableRelation = "No. Series";
        }
        field(250; "Serial No. Series"; Code[20])
        {
            // Otomatik Seri numarası üretimi (mal kabulde seri boş bırakılırsa).
            Caption = 'Serial No. Series';
            DataClassification = CustomerContent;
            TableRelation = "No. Series";
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
