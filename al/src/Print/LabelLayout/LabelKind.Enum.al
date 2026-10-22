// Kitoko (20 Eki 2026): veriyle yönetilen etiket tasarımı.
enum 72463 "DOPSWHS Label Kind"
{
    Extensible = true;

    value(0; Item) { Caption = 'Ürün'; }
    value(1; Bin) { Caption = 'Raf'; }
    value(2; Zone) { Caption = 'Alan'; }
    // Kitoko (21 Eki 2026): LP / palet etiketi; aktif LP tasarımı yoksa LP Label raporundaki sabit tasarım basılır.
    value(3; LP) { Caption = 'LP / Palet'; }
    // Kitoko (22 Eki 2026): mal kabulde ürünün üstüne yapıştırılan lot etiketi (QR = ürün no, barkod = lot no).
    value(4; Lot) { Caption = 'Lot'; }
}
