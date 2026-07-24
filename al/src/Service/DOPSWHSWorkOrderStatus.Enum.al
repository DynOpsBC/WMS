enum 72001 "DOPSWHS Work Order Status"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Extensible = true;
    value(0; Open) { Caption = 'Open'; }
    value(10; Assigned) { Caption = 'Assigned'; }
    value(20; "In Progress") { Caption = 'In Progress'; }
    value(30; "Waiting Parts") { Caption = 'Waiting Parts'; }
    value(40; Completed) { Caption = 'Completed'; }
    value(50; Closed) { Caption = 'Closed'; }
    value(60; Cancelled) { Caption = 'Cancelled'; }
}
