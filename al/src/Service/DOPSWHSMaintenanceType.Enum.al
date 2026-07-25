enum 72000 "DOPSWHS Maintenance Type"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Extensible = true;
    value(0; Preventive) { Caption = 'Preventive'; }
    value(10; Corrective) { Caption = 'Corrective'; }
    value(20; Predictive) { Caption = 'Predictive'; }
    value(30; Inspection) { Caption = 'Inspection'; }
}
