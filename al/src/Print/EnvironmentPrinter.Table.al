table 72378 "DOPSWHS Environment Printer"
{
    Access = Internal;
    Caption = 'Environment Printer';
    DataPerCompany = false;
    DataClassification = CustomerContent;

    // Physical agent identity/status only. Location, copies, BC report settings
    // and device mappings remain on the company's existing Printer table.
    fields
    {
        field(1; "Code"; Code[20]) { Caption = 'Code'; }
        field(2; Description; Text[100]) { Caption = 'Description'; }
        field(4; "Format"; Enum "DOPSWHS Print Format") { Caption = 'Format'; }
        field(5; "Printer Handle"; Text[260]) { Caption = 'Printer Handle'; }
        field(6; Hostname; Text[100]) { Caption = 'Hostname'; }
        field(7; Port; Integer) { Caption = 'Port'; }
        field(8; Active; Boolean) { Caption = 'Active'; }
        field(10; "Last Seen At"; DateTime) { Caption = 'Last Seen At'; }
        field(17; "Last Agent ID"; Code[50]) { Caption = 'Last Agent ID'; }
        field(18; "Station ID"; Code[128]) { Caption = 'Station ID'; }
        field(19; "Discovered by Agent"; Boolean) { Caption = 'Discovered by Agent'; }
        field(20; "Agent Status"; Option) { Caption = 'Agent Status'; OptionMembers = Unknown,Online,Offline,Printing,Error; }
        field(21; "Last Status At"; DateTime) { Caption = 'Last Status At'; }
        field(22; "Last Status Message"; Text[250]) { Caption = 'Last Status Message'; }
        field(23; "Agent Version"; Text[50]) { Caption = 'Agent Version'; }
        field(24; "Agent Default Printer"; Boolean) { Caption = 'Agent Default Printer'; }
    }
    keys { key(PK; "Code") { Clustered = true; } }
}

