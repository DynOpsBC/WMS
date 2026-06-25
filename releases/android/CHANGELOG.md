# BCWMS Android — Release Changelog

Sideload sürümleri burada toplanır. Her sürüm `bcwms-<version>-debug.apk`
olarak `releases/android/` altında saklanır.

Kurulum: [docs/android-install-guide.md](../../docs/android-install-guide.md)

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
