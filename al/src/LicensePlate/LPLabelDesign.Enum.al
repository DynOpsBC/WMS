/// <summary>
/// Which label an LP template prints. ByContainerKind follows the template's
/// container kind; Report renders "Label Report ID" as a PDF document instead
/// of ZPL. See codeunit "DOPSWHS LP Label Builder".
/// </summary>
enum 72234 "DOPSWHS LP Label Design"
{
    Extensible = true;

    value(0; ByContainerKind) { Caption = 'Kaba göre'; }
    value(1; Standard) { Caption = 'Standart LP'; }
    value(2; Pallet) { Caption = 'Palet'; }
    value(3; Carton) { Caption = 'Koli'; }
    value(4; Box) { Caption = 'Kutu'; }
    value(5; Sack) { Caption = 'Çuval'; }
    value(6; Report) { Caption = 'Rapor (PDF)'; }
}
