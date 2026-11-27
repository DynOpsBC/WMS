enum 72218 "DOPSWHS EDesp Print Format"
{
    Extensible = false;
    Caption = 'E-Despatch Print Format';

    value(0; A4Official) { Caption = 'A4 (official PDF)'; }
    value(1; Thermal80) { Caption = '80 mm thermal'; }
    value(2; A4Fallback) { Caption = 'A4 shipment slip (no e-despatch)'; }
}
