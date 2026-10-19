table 72377 "DOPSWHS Print Environment"
{
    Access = Internal;
    Caption = 'Environment Print Connection';
    DataPerCompany = false;
    DataClassification = CustomerContent;

    // IDs/types deliberately mirror only the Azure fields of company Setup.
    // Warehouse, terminal, user, report and license settings stay company-local.
    fields
    {
        field(1; "Primary Key"; Code[10]) { Caption = 'Primary Key'; }
        field(50; "Print Channel"; Enum "DOPSWHS Print Channel") { Caption = 'Print Channel'; }
        field(260; "Azure SB Namespace"; Text[50]) { Caption = 'Azure SB Namespace'; }
        field(270; "Azure Print Jobs Queue"; Text[260]) { Caption = 'Azure Print Jobs Queue'; }
        field(280; "Azure Printer Status Queue"; Text[260]) { Caption = 'Azure Printer Status Queue'; }
        field(290; "Azure Jobs SAS Policy"; Text[50]) { Caption = 'Azure Jobs SAS Policy'; }
        field(300; "Azure Status SAS Policy"; Text[50]) { Caption = 'Azure Status SAS Policy'; }
        field(310; "Azure Storage Account"; Text[24]) { Caption = 'Azure Storage Account'; }
        field(320; "Azure Blob Container"; Text[63]) { Caption = 'Azure Blob Container'; }
        field(330; "Azure Blob Endpoint Suffix"; Text[100]) { Caption = 'Azure Blob Endpoint Suffix'; }
        field(340; "Azure SB Endpoint Suffix"; Text[100]) { Caption = 'Azure SB Endpoint Suffix'; }
        field(350; "Azure Dispatch Max Attempts"; Integer) { Caption = 'Azure Dispatch Max Attempts'; }
        field(380; "Azure Tenant Route ID"; Code[32]) { Caption = 'Azure Tenant Route ID'; }
        field(390; "Azure Company Route ID"; Code[32]) { Caption = 'Azure Company Route ID'; }
        field(400; "Azure Blob SAS Expires At"; DateTime) { Caption = 'Azure Blob SAS Expires At'; }
        field(1000; "Status Owner Company"; Text[30]) { Caption = 'Status Owner Company'; }
        field(1001; "Environment Name"; Text[250]) { Caption = 'Environment Name'; }
        field(1002; Production; Boolean) { Caption = 'Production'; }
    }
    keys { key(PK; "Primary Key") { Clustered = true; } }
}

