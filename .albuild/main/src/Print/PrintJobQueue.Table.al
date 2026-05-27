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
        field(6; ZPL; Blob) { Caption = 'ZPL'; DataClassification = CustomerContent; }
        field(7; Created; DateTime) { Caption = 'Created'; DataClassification = CustomerContent; }
        field(8; Sent; DateTime) { Caption = 'Sent'; DataClassification = CustomerContent; }
    }

    keys { key(PK; "Job ID") { Clustered = true; } }
}
