# EMU / DKÇ 1.14.117 — Şablona göre etiket, otomatik LP, belge bağlama, paketleme listesi

Android sürümü: **1.14.117-emu**, versionCode **200117**. BC paketi: **BCWMSApp 1.14.2.0** (EMU dalı 1.14.2.x).
Dal: `customer/emu`. BADE dalına ve yayınlarına dokunulmadı.

Ayrıntılı kurulum ve davranış: `docs/emu-lp-labels-and-rules.md`.

## Neler geldi

1. **Şablona göre etiket tasarımı** — LP şablonunda Kap Türü (palet/koli/kutu/çuval), Etiket Tasarımı,
   "içerik listelensin" seçeneği ve kopya sayısı. LP kartından tek **Etiket Yazdır** şablonun tasarımını basar
   (BC ve terminal). Ürün, raf ve LP etiketleri terminalden çıkarılabilir. Önizlemeler `docs/labels/emu/`.
2. **Kural bazlı otomatik LP** — Kurulum → LP Auto Rules: lokasyon × belge türü; mal kabul/sevkiyat oluşunca
   belge başına veya satır başına LP, kayıtta kapatma + SSCC + etiket, BC'den kaydedilen belgede LP'yi
   satırlardan doldurma.
3. **LP'yi her belgeye bağla + satırları içine çek** — Satış/satınalma/transfer siparişi ve kayıtlı belgeler
   eklendi; "Belgeden Satırları Çek" (BC) / "Belgeden Doldur" (terminal, belge barkodu okutulabilir). LP
   başlığında müşteri/tedarikçi, sevk adresi, sevkiyat yöntemi, acente, dış belge no, konteyner/mühür, tare.
4. **Paketleme listesi** — Rapor 72315: palet → koli → kutu → madde, SSCC, net/brüt ağırlık, kap sayaçları,
   konteyner/mühür. Ambar Sevkiyatı ve Posted Whse. Shipment kartlarından, LP kartından ve terminal sevkiyat
   ekranından; kayıtta otomatik basma ayarı.
5. **Terminal ↔ yazıcı** — Mevcut *Azure Direct* kanalı DKÇ'deki Windows Print Agent'tır; ek kanal gerekmedi.

## Terminal (emu) değişiklikleri

- LP kartı: **Etiket Yazdır**, **Belgeden Doldur**, **Paketleme Listesi** düğmeleri; BADE'ye özgü MTE düğmesi
  EMU'da gösterilmez.
- LP listesi "Seçilenleri Yazdır": her LP kendi şablon etiketini basar.
- Sevkiyat ekranı: **Paketleme Listesi** düğmesi (belge yazıcısına PDF).

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| alc BC 1.14.2.0 | 0 hata; test paketi (`DOPSWHS LP Design Tests`, 7 test) 0 hata ile derlendi |
| JVM testleri EMU / BADE flavor | 350 / 350 geçti (4 yeni: şablon etiketi yönlendirme, belge türü seçimi, belgeden doldurma koşulu) |
| Emülatör UI testleri (emu debug) | 31 geçti (ilk deneme emülatörün TTS süreci çökünce kesildi, 13 + 18 olarak tekrarlandı) |
| Lint (emu) | 0 hata, 77 uyarı |
| APK | `com.dynops.bcwms.emu` 200117 / 1.14.117-emu, mevcut sertifika; emülatörde eski sürüm üzerine kuruldu ve açıldı |

BC ortamında çalıştırılmadı: kayıt olayları (mal kabul/sevkiyat), RDLC paketleme listesi önizlemesi ve yazıcı
çıktıları canlı test bekliyor. Yayın yapılmadı (GitHub release / EMU kanalı); eski imzalı 1.14.105 cihazlar için
ayrıca `legacyEmu` derlemesi gerekir.
