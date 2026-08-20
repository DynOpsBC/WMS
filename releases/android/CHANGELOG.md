# BCWMS Android — Release Changelog

Sideload sürümleri burada toplanır. Her sürüm `bcwms-<version>-debug.apk`
olarak `releases/android/` altında saklanır.

Kurulum: [docs/android-install-guide.md](../../docs/android-install-guide.md)

---

## v1.14.9-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.9-release.apk`

**SHA-256:** `66c758ada6daaa7429c05830f88ea6fc028c6e7024abe38c40347a93f00c2136`

**versionCode:** 1409 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — nihai adres bazlı akış

- **Etiket okutunca bilgi kartı:** madde no + ürün adı + miktar. LP'li kalemde
  miktar etiketten gelir (GS1 AI 30/37 varsa QR'dan, yoksa LP kaydından) ve tek
  tuşla onaylanır. **LP'siz (dökme) kalemde otomatik miktar yok** — depocu
  saydığını elle girmeden kaydedemez.
- Ürün barkodu paletli satıra denk gelirse kalem PALET olarak açılır (tek
  satırı sayıp paleti bitti işaretleme hatası kapatıldı).
- Sayım yazıldıktan sonra satırlar hemen tazelenir: aynı ürünün ikinci lotu
  okutulunca ilk satırın üstüne yazma hatası kapatıldı.
- **Sayıcı slotları artık gerçekten bağımsız:** sayıldı-durumu seçili slota
  göre hesaplanır; 2./3. sayıcı okutarak yeniden sayım yapabilir. Satır
  düzeltme ekranı paneldeki slotu devralır (yanlışlıkla slot 1'i ezme bitti).
- 'Yeniden Say' pane ilerlemesini sıfırlar; sayılmış palet ikinci adresten tek
  tuşla ezilemez; bilgi kartı açıkken ikinci okutma işlenmez.
- Miktar girişinde virgül noktaya çevrilir (12,5 → 125 hatası kapandı);
  geçersiz girdide buton kilitli (sessiz 0 kaydı bitti).
- 200+ satırlı sayfalarda sayfalama: tüm satırlar yüklenir (5000 tavan).
- **Ekran netliği:** adres kartlarında X/Y sayıldı + ilerleme çubuğu; sayılan
  kalemde yeşil 'Sayılan: N', sayılmayanda gri 'Sistem: N'.
- GS1 çözümleme sağlamlaştırıldı: AI 02/30/37, FNC1 sonrası sabit AI, 00
  önekli 20 haneli SSCC.

### BC (AL — Windows'ta publish bekliyor)

- Count Sheet Card'a 'Sayım Durumu' paneli: Toplam/Sayılan/Kalan/Farklı Satır.
- Count Sheet Lines: 'Sayıldı' kolonu + satır renkleri (yeşil=fark yok,
  turuncu=fark var), Description kolonu.

### Bilinen sınırlamalar

- 0 girilen sayım sunucuda 'hiç sayılmadı'dan ayırt edilemiyor (şemada bayrak
  yok); adres kapatma/tekrar giriş 0'lı satırları bekliyor gösterebilir. Kalıcı
  çözüm AL şema değişikliği (Counted bayrağı) gerektirir.
- Etiket QR'ında miktar yoksa LP kaydı esas alınır — müşterinin QR formatı
  netleşince ayrıştırıcı uyarlanmalı.

---

## v1.14.8-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.8-release.apk`

**SHA-256:** `68c3189ae998913a69bacf310111e6064fc619d560e2e8b215e425db6fd8383e`

**versionCode:** 1408 · **minSdk:** 26 · **targetSdk:** 35

### Değişiklikler

- **Etiket okutunca bilgi kartı açılıyor:** madde no, ürün adı, miktar (+ birim,
  lot/seri) gösterilir; onaylayınca okutulan adrese sayıldı olarak yazılır.
  Kart hem LP etiketini hem ürünün kendi barkodunu (madde no / ürün referansı /
  GTIN) tanır. Ürün adı sayım satırında boşsa ürün kartından tamamlanır.
  Miktar farklıysa karta dokunup elle girilebilir.
- Yanlış adreste okutulan palet uyarısı bilgi kartının içine taşındı.
- **Kör (Blind) mod terminalden kaldırıldı.** Sayım palet/etiket doğrulamasıyla
  yürüdüğü için miktar her zaman gösterilir; BC'deki Mode alanı ne olursa olsun
  terminal miktarı gizlemez, KÖR rozeti kalktı.

---

## v1.14.7-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.7-release.apk`

**SHA-256:** `367766dab25b07d886c1db043819c4a25c261cc7741c3aaba94fd1937d1cef79`

**versionCode:** 1407 · **minSdk:** 26 · **targetSdk:** 35

### Değişiklikler

- **Sayım artık adres bazlı yürüyor — tek akış.** Sayım belgesi açılınca doğrudan
  adres listesi gelir: rafı okut (veya listeden seç) → o rafta beklenen paletler
  listelenir → LP'leri tek tek okut → "Adresi Kapat" → sonraki rafa geç. LP
  okutmak paleti tam kabul eder, miktar girmeye gerek yoktur. Adres
  kapatılırken okutulmayan paletler onay alınarak eksik (0) sayılır.
  Yanlış adreste okutulan palet uyarı verir; paletsiz stok ve içeriği hatalı
  palet için satıra dokunup miktar elle girilebilir.
- Eski satır listesi (grid + kolon seçici) sayım ekranından kaldırıldı; süreç
  tek ve yönlendirilmiş hale getirildi.

---

## v1.14.6-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.6-release.apk`

**SHA-256:** `7ad6144520cfd8e706f413cad9540ff594ce8530a0785dcf46aee33d88795f42`

**versionCode:** 1406 · **minSdk:** 26 · **targetSdk:** 35

### Yenilikler

- **Yerleştirmede adım adım doğrulama.** Bir yerleştirmeye dokunulduğunda
  kaynak raf → ürün → hedef raf → miktar sırasıyla ilerlenir. Her adımda
  okutulan barkod belgedeki beklenen değerle karşılaştırılır; uyuşmazsa
  "Yanlış raf/ürün — Beklenen: X" uyarısı çıkar ve adım ilerlemez. Kaynak raf
  bilgisi belgede yoksa o adım atlanır.
- **Sevkiyat ve toplamada lot seçimi.** "Stoktaki Lotlardan Seç" listesi artık
  her zaman görünür; elde pozitif stoklu lotları miktar ve rafıyla listeler.
  Ürünün stoğunda lot varsa lot alanı otomatik olarak zorunlu olur ve boş
  bırakılırsa satır onaylanamaz — BC'deki `lotRequired` alanı gelmese bile.
  Toplama ekranında lot alanı önceden ne zorunluydu ne de seçim listesi vardı.

---

## v1.14.2-bade — 2026-08-12

**APK:** `bcwms-bade-1.14.2-barcode-auto-print-release.apk`

**SHA-256:** `752ba4c9ab7b741e329653becddad646f748c71fa50f352d4adb936d097fbe41`

**versionCode:** 1402 · **minSdk:** 26 · **targetSdk:** 35

### Düzeltmeler

- Barkod okutulduğunda/yazdırıldığında terminal klavyesi kapanır.
- Barkod test işi BC'de bekleyen `Queued` satır olarak bırakılmaz; aynı API
  isteğinde Azure'a gönderilir. Bir dakikalık worker çevrimini veya elle
  `Validate Azure Print` çalıştırmayı beklemez.

---

## v1.14.1-bade — 2026-08-12

**APK:** `bcwms-bade-1.14.1-barcode-print-test-release.apk`

**SHA-256:** `9cee4b0061cde859eccdd6d9ee5cd9b6b92f000061dfeab58d6a833b9e98e682`

**versionCode:** 1401 · **minSdk:** 26 · **targetSdk:** 35

### Bu sürümde

- **Yazıcılar → Barkod Baskı Testi** eklendi.
- Donanım okuyucu, kamera veya elle girişle alınan ham barkod numarası terminalde
  büyük olarak gösterilir.
- Okunan numara seçili PDF belge yazıcısına tek sayfalık test çıktısı olarak
  gönderilir.
- Bu özellik, gerçek Code 128 barkod çıktısı ve Azure üzerinden otomatik baskı için BCWMS AL extension `1.14.0.7` veya üstü gerekir.

---

## v1.10.0 — 2026-06-24

**APK:** `bcwms-1.10.0-debug.apk` (32 MB)
**SHA-256:** `c19f10a73ca5edf41971898a74509e798ca0f463c57377211dbedbeb0f0e9020`
**versionCode:** 110 · **minSdk:** 26 · **targetSdk:** 35

### Bu sürümde

- 🩺 **Sistem Sağlığı** paneli (yeni): 10 check probe BC API + ScanBus +
  PWA service worker + localStorage — kurulum sonrası tek-dokunuş smoke test
- 📷 **Picking Tara & Doğrula** (yeni): barkod ↔ itemNo eşleşmedikçe
  updateLine çağrılmaz; yanlış ürün toplanma riski elimine edildi
- 📋 **Posting Test grouping** (yeni): 4 kategori — Passed / Real Failure
  / Setup Eksik (gizli tab) / Cascade Atlandı (gizli tab); her Setup
  satırında BC sayfa hint'i
- ⚙️ **DocSearchBar** (yeni): 11 list ekranında ortak belge no arama
  (Picking, Receiving Tab1/Tab2, PutAway, Shipping Tab1/Tab2, Count,
  Movement, LP, Production×2, Assembly, Quality)
- 🔧 **SheetScaffold** (yeni): 10 BottomSheet refactor — klavye açılınca
  Onayla button artık görünür (verticalScroll + imePadding wrapper)
- 🛡 **ActionGuards** (yeni): qty=0 iken Post/Register button disabled
- 🔵 **Zebra DataWedge** entegrasyonu (yeni): ScanBus event bus +
  focus-based subscribe; cold-start intent drop fix (Codex Finding 7)
- 📊 **Item Inquiry stok bloğu** (yeni): inventory + 4 FlowField
  (qty on PO/SO/Prod + reserved); blocked chip
- 📍 **Bin Inquiry içerik tablosu** (yeni): T7302 Bin Content gerçek item
  miktarları (LP listesinin üstünde)
- 🏷 **LP Build template dropdown**: licensePlateTemplates'tan seçim
- 🖨 **LP printLabel default printer**: getDefaultPrinter() ile otomatik
- 🐛 Codex review wave 1+2 fix'leri:
  - ItemApi `OnAfterGetRecord` trigger + 5 FlowField CalcFields
  - PickingModule ScanVerifySheet race fix (busy atomic)
  - MainActivity DataWedge cold-start LaunchedEffect dispatch
  - PickingModule OData filter merge → `buildList` pattern

### BC tarafı gereksinimleri

DOPSWHS extension v1.10.0 publish edilmiş olmalı. Aksi halde Sistem
Sağlığı'nda 3 API check FAIL döner (BinContentApi 72097, ItemApi
inventory, LPTemplateApi 72280).

### Önceki sürümler

v1.8.2.0 ve öncesi BC AL paketleri `releases/bcwmsapp-*.app` altında.
Android APK arşivi v1.10.0'dan itibaren `releases/android/` altında.
