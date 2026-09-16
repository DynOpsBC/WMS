/// <summary>
/// Physical container class of an LP template. Drives the label design and the
/// pallet / carton / box counters on the packing list.
/// </summary>
enum 72233 "DOPSWHS LP Container Kind"
{
    Extensible = true;

    value(0; Unspecified) { Caption = 'Belirtilmedi'; }
    value(1; Pallet) { Caption = 'Palet'; }
    value(2; Carton) { Caption = 'Koli'; }
    value(3; Box) { Caption = 'Kutu'; }
    value(4; Sack) { Caption = 'Çuval'; }
    value(5; Tote) { Caption = 'Sepet'; }
    value(6; Other) { Caption = 'Diğer'; }
}
