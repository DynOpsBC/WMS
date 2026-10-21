// Kitoko (21 Eki 2026): etiket tasarımcısındaki barkod türü (DesignJson "symbology").
enum 72466 "DOPSWHS Label Symbology"
{
    Extensible = true;

    value(0; Code128) { Caption = 'Code128'; }
    value(1; EAN13) { Caption = 'EAN-13'; }
    value(2; GS1128) { Caption = 'GS1-128'; }
}
