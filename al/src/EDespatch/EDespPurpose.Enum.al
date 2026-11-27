enum 72217 "DOPSWHS EDesp Purpose"
{
    Extensible = false;
    Caption = 'Despatch Purpose';

    value(0; " ") { Caption = ' '; }
    value(1; InterLocation) { Caption = 'Inter-Location Transfer'; }
    value(2; Subcontracting) { Caption = 'Subcontracting'; }
    value(3; Consignment) { Caption = 'Consignment'; }
    value(4; Other) { Caption = 'Other'; }
}
