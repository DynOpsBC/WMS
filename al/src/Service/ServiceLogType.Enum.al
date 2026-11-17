/// <summary>What a service log entry records: a text someone typed, or a step of the job.</summary>
enum 72100 "DOPSWHS Service Log Type"
{
    Extensible = false;

    value(0; Note) { Caption = 'Note'; }
    value(1; "Fault Note") { Caption = 'Fault Note'; }
    value(2; "Resolution Note") { Caption = 'Resolution Note'; }
    value(3; "Internal Note") { Caption = 'Internal Note'; }
    value(4; "Order Description") { Caption = 'Order Description'; }
    value(5; Created) { Caption = 'Service Opened'; }
    value(6; Assigned) { Caption = 'Technician Assigned'; }
    value(7; Started) { Caption = 'Work Started'; }
    value(8; "On Hold") { Caption = 'Put On Hold'; }
    value(9; Labor) { Caption = 'Labor'; }
    value(10; Part) { Caption = 'Part'; }
    value(11; Finished) { Caption = 'Work Finished'; }
    value(12; Posted) { Caption = 'Service Posted'; }
    value(13; Attachment) { Caption = 'Attachment'; }
    value(14; "Line Deleted") { Caption = 'Line Deleted'; }
}
