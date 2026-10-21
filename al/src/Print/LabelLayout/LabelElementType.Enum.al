enum 72464 "DOPSWHS Label Element Type"
{
    Extensible = true;

    value(0; Text) { Caption = 'Metin'; }
    value(1; Field) { Caption = 'Alan'; }
    // Kitoko (21 Eki 2026): tasarımcıdaki "barcode"; türü Symbology alanı seçer (Code128 / EAN-13 / GS1-128).
    value(2; Barcode128) { Caption = 'Barkod'; }
    value(3; QRCode) { Caption = 'QR Kod'; }
    value(4; Line) { Caption = 'Çizgi'; }
    value(5; Box) { Caption = 'Kutu'; }
    // Kitoko (21 Eki 2026): sürükle-bırak tasarımcıdan gelen resim (^GFA verisi satırda saklanır).
    value(6; Image) { Caption = 'Resim'; }
}
