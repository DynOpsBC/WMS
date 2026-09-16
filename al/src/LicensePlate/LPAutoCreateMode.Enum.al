/// <summary>
/// How an LP auto rule opens license plates for a warehouse document.
/// </summary>
enum 72235 "DOPSWHS LP Auto Create Mode"
{
    Extensible = true;

    value(0; None) { Caption = 'Oluşturma'; }
    value(1; PerDocument) { Caption = 'Belge başına bir LP'; }
    value(2; PerLine) { Caption = 'Satır başına bir LP'; }
}
