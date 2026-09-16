# EMU / DKÇ 1.14.119 — Raf Sorgu'da lokasyon ve raf seçici, birden fazla etiket yazıcısı

Android **1.14.119-emu** (versionCode 200119), BC **BCWMSApp 1.14.2.5**, yazıcı ajanı **1.1.0**.
Dal `customer/emu`; ana paket 1.14.0.3'ten merge edildi. BADE'ye dokunulmadı.

## Terminal 1.14.119
- **Raf Sorgu**: Lokasyon alanının yanında **Seç** (BC'deki lokasyon listesi), Bin alanının yanında **Raf listesi**
  (seçili lokasyonun rafları, arama kutusuyla). Elle yazma ve barkod okutma aynen çalışır.
  Lokasyon listesi için BC 1.14.2.5 gerekir; eski BC'de düğme görünmez, yazarak devam edilir.

## BC 1.14.2.5
- API `locations` (sayfa 72326): terminal lokasyon seçici için.
- 1.14.2.4'teki her şey (Bin List / Item List'ten etiket basma, 80x40 etiket düzeni, kurulum emniyeti, MTE Report ID alanı).

## Yazıcı ajanı 1.1.0 (bcwms-print-agent-1.1.0-win-x64.zip)
- Aynı PC'ye bağlı **birden fazla etiket yazıcısı**: Yazıcılar sekmesinde işaretli liste. Her işaretli yazıcı
  Buluta Eşitle ile BC'ye kendi Printer ID'siyle kaydolur; terminal/BC hangisini seçerse iş oraya basılır.
- Belge (PDF) yazıcısı ayrı; etiket formatı bütün etiket yazıcıları için ortak (ZPL).
- 1.0 ayarları korunur: mevcut seçili yazıcı listenin ilk elemanı olur, JSON yeniden içe aktarılmaz.
- Kurulum: eski ajanı tepsiden Çıkış ile kapatın, zip'i açıp `app/` klasörünü mevcut kurulumun üstüne kopyalayın
  (ya da installer/install.ps1), ajanı açın, yazıcıları işaretleyin, Kaydet, Buluta Eşitle.

## Kurulum sırası (DKÇ)
1. BC: 1.14.1.41 → Allow Edition Change → **1.14.2.5** (2.2/2.3/2.4 atlanır).
2. Ajan 1.1.0.
3. Terminal 1.14.119 (eski imzalı cihazlar için legacy paket ayrıca derlenir: masaüstündeki .command).
