table 50029015 "WMS Carrier"
{
    Caption = 'WMS Carrier';
    DataClassification = CustomerContent;

    fields
    {
        field(1; Code; Code[20]) { Caption = 'Code'; NotBlank = true; }
        field(2; Name; Text[100]) { Caption = 'Name'; }
        field(3; Provider; Enum "WMS Carrier Provider") { Caption = 'Provider'; }
        field(4; "API Endpoint"; Text[250]) { Caption = 'API Endpoint'; }
        field(5; "Account Number"; Code[40]) { Caption = 'Account Number'; }
        field(6; "Sandbox"; Boolean) { Caption = 'Sandbox'; }
        field(7; Active; Boolean) { Caption = 'Active'; }
    }
    keys { key(PK; Code) { Clustered = true; } }
}
