# Kitoko / Element 4 — Android 1.14.202 + BC 1.14.3.32

11 Kasım 2026 · versionCode 200202 · com.dynops.bcwms.kitoko · Azure DevOps #3338

## Projeye Çıkış (saha iş emrine malzeme)

Terminal ana menüsü → Giden → **Projeye Çıkış**:

1. Açık saha iş emirleri listelenir (iş emri no, proje no, proje görevi, açıklama, ekip). Arama kutusu iş emri / proje no ile süzer.
2. İş emri seçilir → lokasyon → raf (raf zorunlu lokasyonda) → isteğe bağlı LP → ürün okutulur veya iş emri malzeme satırından seçilir → miktar (lot/seri gerekiyorsa).
3. **Çıkış Yap**: BC'de proje kullanımı olarak kaydedilir (Proje Günlüğü, Tür = Madde, Belge No. = saha iş emri, Harici Belge No. = terminal kullanıcısı). Stok düşer, proje defterine maliyet yazılır, PROJE boyutu eklenir. LP okutulduysa LP içeriği aynı işlemde düşülür. İş emri satırının "Gerçekleşen Miktar" alanı artar.

Kurallar: yönlendirilmiş lokasyon ve proje tüketiminde ambar toplaması zorunlu lokasyon reddedilir; LP okutulmadıysa yalnız LP'ye atanmamış serbest stoktan çıkılır; iş emrinde proje görevi yoksa çıkış yapılmaz. Canlı ortamda ekran yalnız terminal yöneticilerine açıktır (Sevkiyat/Toplama gibi).

## Yönlendirilmiş lokasyon (ELM4-WMS)

Element 4 deposu yönlendirilmiş ve "Proje Sarf. Ambar İşlemi = Ambar Çekme (zorunlu)". BC burada proje günlüğünden doğrudan düşüme izin vermez. Çıkış Yap aynı işlemde: iş emrinin proje görevine bütçe planlama satırı açar → yalnız okutulan raftan ambar toplaması oluşturur → terminal kullanıcısı adına onaylayıp kaydeder (stok Projeye Depo Gözü'ne geçer) → toplanan miktarı proje kullanımı olarak işler. Lokasyonda "Projeye Depo Gözü Kodu" dolu olmalı (Sand2010: PROJE, URETIM alanı).

Sand2010 testi (11 Kas 2026): PR00010/100, TEST-3338-01, P-00016 HM1'den 2 + 3 adet → proje defteri 1 ve 2, HM1 82→77, PROJE gözü boş, iş emri satırı gerçekleşen 3 (ilk çıkışta Türkçe "I" hatası nedeniyle yazılmamıştı, düzeltildi). LP'li çıkış ve terminal (API) yolu cihazda denenmedi.

## BC 1.14.3.32

- API: `fieldWorkOrders`, `fieldWorkOrderLines`, `fieldWorkOrders('…')/Microsoft.NAV.issueItem`.
- Sayfalar: **WMS Projeye Çıkış (Saha İş Emri)** (terminalsiz aynı işlem), **WMS Proje Malzeme Çıkışları** (proje bazında stok çıkış listesi), DOPSWHS Setup → "Proje Boyutu" (boş = PROJE).
- Saha İş Emri "DynOps Project Management Core" uzantısından RecordRef ile okunur; bağımlılık eklenmedi. Uzantı olmayan şirkette liste boş döner.
- Terminal Ekran Tasarımcısı kataloğuna PROJECT_ISSUE kutusu eklendi.
