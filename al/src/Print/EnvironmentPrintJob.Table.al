table 72379 "DOPSWHS Environment Print Job"
{
    Access = Internal;
    Caption = 'Environment Print Job Routing';
    DataPerCompany = false;
    DataClassification = CustomerContent;
    fields
    {
        field(1; "Cloud Job ID"; Guid) { Caption = 'Cloud Job ID'; }
        field(2; "Company Name"; Text[30]) { Caption = 'Company Name'; }
        field(3; "Result Body"; Blob) { Caption = 'Result Body'; }
        field(4; "Result Pending"; Boolean) { Caption = 'Result Pending'; }
        field(5; "Result Applied"; Boolean) { Caption = 'Result Applied'; }
        field(6; Created; DateTime) { Caption = 'Created'; }
        field(7; "Last Error"; Text[250]) { Caption = 'Last Error'; }
    }
    keys
    {
        key(PK; "Cloud Job ID") { Clustered = true; }
        key(Pending; "Company Name", "Result Pending") { }
    }
}
