# BADE — yazıcı ajanı 1.1.0 tek tık kurulum paketi + BC 1.14.1.54 (17 Eyl 2026)

## Ne değişti
- `customer/bade` üzerine main birleştirildi: yazıcı ajanı **1.1.0** (bir istasyonda birden çok etiket yazıcısı; ajan panelinde
  "Etiket yazıcıları" işaretli liste, işaretli her yazıcı iş hedefi olarak buluta yayınlanır), `KUR.cmd` tek tık kurulum,
  BC **72326 Location API** (terminal lokasyon/raf seçicileri). BC sürümü 1.14.1.54 (WMS/ çalışma kopyasındaki paralel
  oturum 1.14.1.53'e kadar kullanıyor; çakışmamak için atlandı).
- BADE Azure stack'i (`rg-bade-bcwms-print-sandbox`, abonelik ea2f1f09…) için istasyon **DYNOPS.BADE.MAIN.PRINT01**
  ayarları 3 yıl geçerli SAS ile yeniden üretildi (`Initialize-Configuration.ps1`, bitiş 16 Eyl 2029). Konteyner politikaları
  (`agent-read`, `bc-upload`) uzatıldı; BC'deki mevcut SAS aynı politikaya bağlı olduğu için BC tarafında değişiklik gerekmez.

## Paket: `output/release-bade-agent-1.1.0/BADE-Print-Agent-1.1.0-win-x64.zip`
```
BADE-Print-Agent-1.1.0/
  KUR.cmd                          ← çift tık
  kur-bade.ps1                     ← ajanı kapatır, imzalı paketi install.ps1 ile kurar (manifest/hash), autostart,
                                     secrets'ı ajanın yanına kopyalar (ilk açılışta otomatik içe aktarılır), ajanı başlatır
  print-agent.runtime.secrets.json ← BADE PRINT01 gizli bağlantı bilgileri (yalnız BADE IT ile paylaşılır)
  OKU-BENI.txt
  BCWMS-Print-Agent-win-x64/       ← publish-win-x64.ps1 çıktısı, manifest dışı dosya içermez
```
Kurulum sonrası tek elle adım: ajan penceresinde Zebra yazıcıları işaretle → Kaydet ve Bağlan → Buluta Eşitle.
Terminalde her cihaz Yazıcılar ekranından kendi yazıcısını seçer (cihaz bazlı saklanır).

## Doğrulama
alc 0 hata (1.14.1.54); ajan `dotnet publish win-x64` bu Mac'te üretildi (testler atlandı, Windows projesi Mac'te koşmaz);
paket Windows'ta denenmedi. Terminal (Android) bu dalda değiştirilmedi; BADE terminalini WMS/ içindeki diğer oturum yürütüyor.
