table 72022 "DOPSWHS Print Job Queue"
{
    Caption = 'DOPSWHS Print Job Queue';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Job ID"; Integer) { Caption = 'Job ID'; DataClassification = CustomerContent; AutoIncrement = true; }
        field(2; "Source Doc"; Code[50]) { Caption = 'Source Doc'; DataClassification = CustomerContent; }
        field(3; "Report ID"; Integer) { Caption = 'Report ID'; DataClassification = CustomerContent; }
        field(4; "Printer ID"; Code[50]) { Caption = 'Printer ID'; DataClassification = CustomerContent; }
        field(5; Status; Option) { Caption = 'Status'; DataClassification = CustomerContent; OptionMembers = Queued,Sent,Failed; OptionCaption = 'Queued,Sent,Failed'; }
        field(6; ZPL; Blob) { Caption = 'Payload'; DataClassification = CustomerContent; }
        field(7; Created; DateTime) { Caption = 'Created'; DataClassification = CustomerContent; }
        field(8; Sent; DateTime) { Caption = 'Sent'; DataClassification = CustomerContent; }
        field(10; Channel; Enum "DOPSWHS Print Channel") { Caption = 'Channel'; DataClassification = CustomerContent; }
        field(11; "Format"; Enum "DOPSWHS Print Format") { Caption = 'Format'; DataClassification = CustomerContent; }
        field(12; Copies; Integer) { Caption = 'Copies'; DataClassification = CustomerContent; InitValue = 1; }
        field(13; "Agent ID"; Code[50]) { Caption = 'Agent ID'; DataClassification = CustomerContent; }
        field(14; "Claimed At"; DateTime) { Caption = 'Claimed At'; DataClassification = CustomerContent; }
        field(15; "Last Error"; Text[250]) { Caption = 'Last Error'; DataClassification = CustomerContent; }
        field(16; "Retry Count"; Integer) { Caption = 'Retry Count'; DataClassification = CustomerContent; }
        field(17; "Payload Size"; Integer) { Caption = 'Payload Size'; DataClassification = CustomerContent; }
    }

    keys
    {
        key(PK; "Job ID") { Clustered = true; }
        key(Pull; Channel, Status, "Printer ID") { }
    }
}
