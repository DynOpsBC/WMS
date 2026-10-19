# BADE 1.14.121 — LP yaşam döngüsü, tam palet sevki, kaynak LP izi, sorgu rafı, lot kilidi, elle etiket (BC 1.14.1.42)

Android: **1.14.121-bade**, versionCode **200121**. BC: **BCWMSApp 1.14.1.42** (1.14.1.41 üstüne yüklenir).
1.14.120/1.14.1.41'deki her şey bu pakette de vardır.

## Merve'nin 7 maddesi (16 Eylül, öğleden sonra)

| # | Bildirim | Durum |
|---|---|---|
| 1 | İçeriği tamamen boşalan kaynak LP "Oluşturuldu" kalıyor, tekrar kullanılabiliyor | **Çözüldü (BC)** |
| 2 | Tam palet sevkinde bile yeni Sevk LP zorunlu | **Çözüldü (BC + terminal metni)** |
| 3 | Sevk LP hareketlerinde kaynak LP görünmüyor | **Çözüldü (BC + terminal)** |
| 4 | Ürün Sorgu'da LP ile sorguda Alan Kodu ve Raf gelmiyor | **Çözüldü (terminal)** |
| 5 | "Lot No. Ata" lotu elle değiştirilebiliyor | **Çözüldü (BC kilidi + terminal)** |
| 6 | Mal kabulde etiket otomatik basılıyor; "Etiket Yazdır" ile basılsın | **Çözüldü (Kurulum anahtarı + terminal)** |
| 7 | Farklı lotlardan toplamada satış hareketi lot bazında ayrı ILE satırı | **BC çekirdek davranışı, değiştirilmez** (aşağıda) |

## 1. Boşalan LP → Kullanıldı

`LP Management`: toplama transferi (`TransferPickedQuantity`), LP kartı Transfer (`Transfer`) ve Kısmi İşlem → "kullanılan
kısmı çıkar" bir LP'nin son satırını sildiğinde LP **Kullanıldı** olur (`MarkUsedIfEmptied`); belge ataması temizlenir,
harekete `EMPTIED` satırı yazılır. Kullanıldı LP hiçbir yerde hedef/kaynak olarak okutulamaz (mevcut kontroller:
toplama hedefi, ana sepet, transfer, terminal düğmeleri). Eskiden yalnız sevkiyat kaydı bu durumu veriyordu.

## 2. Tam palet doğrudan sevk

`Pick Mgmt.MovePickedContentsToMainLp`: toplamada **Hedef LP yoksa** ve palet planı varsa, okutulan her paletin
tüm içeriği (temel birimde) planlanan miktara eşitse paletler **olduğu gibi sevk LP'si olur** (`ShipScannedPalletsDirectly`
→ `LP Management.ShipLpDirectly`): palet toplamaya atanır (Assigned/WhsePick), Place rafına taşınır (hareket: Moved,
Assigned), toplama/yerleştirme satırları ve sevkiyat satırı (LP No., SSCC) bu paletle damgalanır. Sevkiyat kaydı paleti
mevcut kurallarla tüketir (toplamaya atanmış LP → izinli). Bir palet **kısmen** toplanıyorsa kayıt açık hatayla durur:
"Palet(ler) kısmen toplanıyor: LP… Kısmi toplamada önce Hedef LP Oluştur…". Aynı paletin iki farklı raftan/iki sevk
rafına gitmesi de reddedilir. Hedef LP açılmışsa eski davranış (içerik aktarma) aynen sürer.
Terminal ipucu metni buna göre değişti (PickingModule).

## 3. Kaynak LP izi

- `DOPSWHS LP Line` alan 65 **Source LP No.**: toplama ve transferle oluşan sevk LP satırında kaynak palet. API
  `licensePlateLines.sourceLpNo`; terminal LP kartında satır altında "Kaynak LP: LP000025"; BC LP kartı satırlarında sütun.
- `DOPSWHS LP Movement Ledger` alan 110 **Source LP No.** / 111 **Target LP No.**: Transfer In/Out satırlarında iki palet de
  yazılır (`WriteTransferToLedger`); BC hareket listesinde iki yeni sütun.

## 4. Ürün Sorgu: Raf ve Alan

LP ile sorguda `licensePlates` (lokasyon/raf) + `bins` (zoneCode) okunur; "Okutulan LP" panelinde ve LP satırlarında
"Raf: MERKEZDEPO/M.A01.11 · Alan: A01" gösterilir (`loadLpPlacements`, en çok 25 LP). Veri yoksa satır boş kalır.

## 5. Lot kilidi

- BC `Receipt Mgmt.EnsurePendingLotUnchanged`: "Lot No Ata" ile ayrılmış lot varken farklı lot gönderilirse kayıt
  reddedilir ("… atanan LOT lot numarası değiştirilemez"). `ConfirmLine` ve toplu LP dağıtımında uygulanır; toplu dağıtım
  bekleyen lotu yeniden kullanır (ikinci numara yakmaz).
- Terminal: lot alanı zaten salt-okunurdu; **Tedarikçi Lotu Lookup / Uygun Lot Lookup** artık atanan iç lotu ezmiyor
  (yalnız tedarikçi lotunu doldurur).

## 6. Etiket: otomatik değil, "Etiket Yazdır"

Kurulum → **Manual Receipt Label Print** (yeni, varsayılan kapalı = eski davranış). **BADE'de açılmalı.** Açıkken
`receipts/postAndCloseLP` etiket basmaz; terminal (profil bayrağı `manualReceiptLabelPrint`) kayıt sonrası açılan ekranı
"Mal kabul kaydedildi · Etiket Yazdır" olarak gösterir, tüm paletler seçili gelir, **Etiket Yazdır** düğmesiyle basılır.
Eski terminal + yeni BC: etiket basılmaz, mevcut MTE ekranından seçilerek basılır. Yeni terminal + eski BC: bayrak yok →
otomatik baskı sürer.

## 7. Lot bazında ayrı Madde Defter Girişi — değiştirilemez

Business Central lot/seri takipli maddede her lot için ayrı Item Ledger Entry yazar; tek sevkiyat satırı üç lottan
toplanmışsa üç ILE oluşur. Bu, izlenebilirliğin temelidir (lot bazında maliyet, geri çağırma, rezervasyon) ve BCWMS'in
dışındadır. Satış irsaliyesi satırı tek kalır; yalnız defter girişleri lot bazında bölünür. Rapor/analizde tek satır
isteniyorsa ILE yerine Satış İrsaliyesi Satırları ya da Posted Whse. Shipment Lines kullanılmalı.

## Doğrulama

- alc 0 hata. Android: BADE birim testleri tümü geçti (yeni: LP raf/alan etiketi, OData filtre), lint 0 hata, imzalı APK 200121.
- Canlı BC testi yapılmadı. Sahada sırayla: (a) tam palet toplama → Hedef LP açmadan kaydet → palet Assigned, sevkiyat
  satırında LP No.; (b) kısmi toplama → açık hata → Hedef LP Oluştur; (c) boşalan kaynak LP → Kullanıldı; (d) Kurulum'da
  Manual Receipt Label Print aç → mal kabul → Etiket Yazdır ekranı.

## Dosyalar

`output/release-bade-1.14.121/`: `BCWMS-BADE-1.14.121-RELEASE.apk`, `BCWMSApp-1.14.1.42.zip`, `latest.json`, `SHA256SUMS.txt`.

## Ek (16 Eyl 15:50): lisans hatası artık açık yazılır

Merve'nin LP000026 fotoğrafları (Seçilenleri Yazdır ve MTE Yazdır, ikisi de REF) MTE'ye özgü olmadığını gösterdi:
tüm baskı yolları Azure'a çıkmadan `License Mgmt.GuardFeature(PrintBridge)` adımında kesiliyor olabilir. Eski metin
("License is not active (Expired). Verification failed (expired)") İngilizce olduğu için REF'e dönüşüyordu.
BC 1.14.1.42: lisans hataları Türkçe ve yönlendirici ("BCWMS lisansı aktif değil (…): … Kurulum → Lisans → Şimdi Doğrula").
Terminal 1.14.121: eski BC metinleri de aynı Türkçe mesaja eşlenir (aktif değil / paket yetersiz / cihaz sınırı).
Sahada ilk kontrol: BC → BCWMS Kurulum → Lisans bölümü → Lisans Durumu ve Durum Mesajı.

## KÖK NEDEN BULUNDU ve DÜZELTİLDİ (16 Eyl 16:07) — terminal MTE / Seçilenleri Yazdır REF hatası

BC LP kartındaki yeni "MTE Yazdır (terminal yolu)" düğmesi ham hatayı verdi:
`Cannot call SetAscending on field Posting Date because it is not part of the current sorting.`
(`DOPSWHS MTE Zpl Builder`.ResolveProductionDate). 1.14.1.39 ile gelen 10×8 ZPL MTE üreticisi üretim tarihini ararken
sıralama anahtarında olmayan bir alanda `SetAscending` çağırıyordu; lot takipli her palette çalışma zamanı hatası → etiket
yazıcısına giden her MTE (LP kartı "MTE Yazdır", LP listesi "Seçilenleri Yazdır", mal kabul sonrası MTE) düşüyordu.
Terminal İngilizce metni REF koduna çevirdiği için 14:07'den beri neden görünmüyordu. Düzeltme: `SetCurrentKey("Item No.",
"Posting Date")` + varsayılan artan sıralama. **BC 1.14.1.42 (bu paket) yüklenince MTE tekrar basılır; terminal güncellemesi
gerekmez.**
