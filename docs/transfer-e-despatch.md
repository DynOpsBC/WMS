# Transfer Sevk ve e-İrsaliye

Bu belge, Business Central (BC), BCWMSApp, DynOpsEtrans (e-Dönüşüm) ve
"DynOps WMS e-Despatch Connector" birlikte kurulduğunda transfer e-İrsaliyesinin
nasıl kurulacağını, el terminalinden nasıl kullanılacağını ve API sözleşmesini anlatır.

Mimari kararlar: [decisions/transfer-e-despatch-decisions.md](decisions/transfer-e-despatch-decisions.md).

> Durum (27.11.2026): BCWMSApp 1.14.0.4, BCWMSApp Tests, DynOpsEtrans 2.0.0.82, Connector 1.0.0.0 ve
> e-Dönüşüm test uygulaması hatasız derleniyor. Sandbox'ta (CustomerSandbox / Demo Business Central)
> aşağıdaki "Kabul senaryoları" henüz çalıştırılmadı; yayından önce çalıştırılmalıdır.

## 1. Kim ne yapar?

| Katman | Görev |
|---|---|
| **DynOpsEtrans** | Yasal e-İrsaliye: alıcı eşlemeleri, kaynak politikaları, UBL-TR, entegratör (Turkcell / Sovos), A4 PDF, 80 mm termal çıktı. WMS olmadan da çalışır. |
| **BCWMSApp** | El terminali sözleşmesi: transfer/hareket API'leri, sağlayıcıdan bağımsız **e-İrsaliye Talebi** kaydı, Print Dispatcher ile yazdırma. e-Dönüşüm yoksa talep `Sağlayıcı bekleniyor` durumunda kalır ve yalnız "Sevk fişi" basılabilir. |
| **Connector** | WMS olaylarını e-Dönüşüm facade'ına bağlar, durumu WMS'e yansıtır, fason alıcısını (fasoncu tedarikçi) çözer. |
| **Android** | "Transfer Sevk" ekranı, e-İrsaliye inceleme sayfası, hareket ve fason ekranlarındaki bağlantılar. |

## 2. Hangi hareket e-İrsaliye üretir?

| Kaynak belge (BC) | e-Dönüşüm kaynak türü | Ne zaman oluşur |
|---|---|---|
| Transfer emri | TransferOrder | Sayfadan elle ("E-İrsaliye Oluştur") |
| Kayıtlı transfer sevkiyatı | TransferShipment | Sevkiyat post edilince (politika açıksa) veya WMS terminalinden sevk edilince |
| Kayıtlı doğrudan transfer | DirectTransfer | Doğrudan transfer post edilince |
| Kayıtlı ambar hareketi | RegisteredWhseMovement | Hareket kaydedilince |
| Kayıtlı stok hareketi | RegisteredInvtMovement | Stok hareketi kaydedilince |
| WMS serbest raf hareketi | ExternalBinTransfer | Connector üzerinden (talep satırları) |
| Kaydedilmemiş ambar hareketi | WarehouseMovement | Sayfadan elle (yalnız "Yerleştir" satırları alınır) |

**Alıcı önceliği:** belgede seçilen alıcı > uzantı olayı (ör. fason) > **raf eşlemesi** >
**lokasyon eşlemesi** > kendi şirketi.

**Otomatik oluşturmada atlanan durumlar** (atlama gerekçesi Otomasyon Kayıtları'na yazılır):

- Aynı lokasyon içinde, kendi şirketine giden olağan raf-raf hareketi.
- Eşlemesi olmayan lokasyon (politikada "Require Receiver Mapping" açıksa).
- Fasoncu rafından kendi rafına dönüş (bu gelen harekettir).
- Eşlemede "E-Despatch Mode = Not Required".

Elle oluşturma hiçbir zaman atlanmaz; "Required" eşlemesi de hiçbir zaman atlanmaz.

## 3. Kurulum (BC)

### 3.1 e-Dönüşüm

1. **E-Document Setup** → "Transfer E-Despatch Automation" açık, "Default Item Tracking Mode"
   (None / Lot/Serial in Line Note / Lot/Serial on Line), gerekiyorsa "Thermal 80 mm XSLT Code".
   "Outgoing Desp. Source Mode" = Both veya Posted Documents olmalıdır.
2. **E-Despatch Source Policies**: her kaynak türü için Enabled, Create Trigger (Manual / OnPost),
   Auto Send (varsayılan kapalı), Require Receiver Mapping, Skip Own Company in Same Location,
   Tracking Mode, Location Filter. Kurulumda hepsi kapalı gelir.
3. **E-Despatch Receiver Mappings** (Lokasyon kartı ve Raflar sayfasından da açılır):
   - Boş raf = lokasyonun tamamı. Dolu raf = o raf (fasoncu rafı).
   - Receiver Type: Own Company / Vendor / Customer; Receiver No.; Address Code
     (tedarikçide Order Address, müşteride Ship-to Address).
   - Despatch Purpose (Depolar arası / Fason / Konsinye / Diğer), E-Despatch Mode (Auto / Required / Not Required),
     varsayılan not, nakliyeci, plaka, şoför, XSLT ve 80 mm XSLT kodları.
4. **Tedarikçi kartı**: e-İrsaliye mükellefi ve PK alias'ı. Müşteride mevcut alanlar kullanılır.
   Kayıtlı olmayan alıcıda GİB genel alias'ı kullanılır ve çıktıya uyarı basılır.
5. **Lokasyon kartı**: şube başına kendi PK alias'ı (kendi şirketimize giden transferlerde).

Örnek: Tek bir `FASON` lokasyonu, her fasoncu için bir raf:

| Lokasyon | Raf | Alıcı türü | Alıcı | Adres | Amaç |
|---|---|---|---|---|---|
| FASON | V001 | Vendor | V001 | ATOLYE | Fason |
| FASON | V002 | Vendor | V002 | | Fason |
| SUBE2 | | Own Company | | | Depolar arası |
| KONSINYE | | Customer | C010 | DEPO1 | Konsinye |

Raf eşlemesinde teslim adresi lokasyonun (sanal) adresi değil, alıcının adresidir.

### 3.2 BCWMSApp (WMS Setup → e-İrsaliye grubu)

| Alan | Açıklama |
|---|---|
| E-Despatch Requests Enabled | Terminal sevk/hareketlerinde e-İrsaliye talebi açılır. |
| Default E-Despatch Print Format | A4 (resmi PDF) / 80 mm termal / A4 sevk fişi. |
| E-Despatch Print Copies | Terminal kopya sayısı göndermezse kullanılır; 0 = 1 kopya. |
| Require Vehicle Info for E-Despatch | Gönderimden önce plaka ve şoför (ya da nakliyeci) zorunlu. |
| Review E-Despatch After Register | Kayıttan sonra terminal inceleme sayfasını açar. |
| Shipment Slip Report ID | Sağlayıcı yokken basılacak sevk fişi raporu (boşsa transfer sevkiyatı için 5704). |
| Handheld Transfers Use In-Transit / Handheld Transfer In-Transit Code | Terminalden açılan yeni transferler transit lokasyonla mı gitsin? Kapalıysa Inventory Setup "Direct Transfer Posting" = Receipt and Shipment olmalıdır. |

İzinler: DOPSWHS-ADMIN / USER / VIEW izin setleri yeni tablo ve sayfaları kapsar.
Connector için `DYN WMS EDESP` izin seti atanmalıdır.

### 3.3 Yazıcılar

- A4: cihazın **Belge** yazıcısı (IWX Report Usage 11 `EDespatch`).
- 80 mm: cihazın **Termal** yazıcısı (usage 12 `EDespatchThermal`). Windows yazıcı ajanında
  **PDF** formatıyla tanımlanmalıdır; terminal başka formatı kabul etmez.
- Kanal: Azure Direct, SelfHosted veya PrintNode (mevcut Print Dispatcher).
- 80 mm PDF, render-service'in `paper: THERMAL80` modu ile üretilir (80 mm genişlik,
  yükseklik içerikten; gönderilmemiş belgede "TASLAK" filigranı).

## 4. El terminali

Ana menü → **Giden** → **Transfer Sevk**. Üç sekme:

### 4.1 Transfer Emirleri

1. Kaynak lokasyondaki serbest bırakılmış emirler listelenir; emir no okutulabilir.
2. Emri seçin. Satırlarda ürün / GTIN okutun, miktarı girin; lot/seri takipli üründe lot/seri okutun.
3. **Alıcı ve Taşıma** kartı eşlemeden gelen öneriyi gösterir (`resolveReceiver`). Gerekirse
   Tedarikçi / Müşteri / Kendi şirketim seçip alıcıyı ve adresini değiştirin; plaka, dorse,
   şoför, TCKN, nakliyeci ve not girin.
4. **Sevk Et** → stok düşer, e-İrsaliye taslağı oluşur, inceleme sayfası açılır.
5. Lokasyon ambar sevkiyatı gerektiriyorsa (`REQUIRES_WHSE_SHIPMENT`) terminal sizi
   Sevkiyat → Ambar Sevkiyatı ekranına yönlendirir; orada `postWithDespatch` kullanılır.

### 4.2 Yeni Transfer

Kaynak ve hedef lokasyonu (fasoncu/konsinye rafı dahil) seçin, ürün veya LP okutun,
**Oluştur ve Sevk Et**. İşlem anahtarı (idempotency key) sayesinde bağlantı kopup tekrar
basıldığında ikinci transfer veya ikinci e-İrsaliye oluşmaz.

### 4.3 e-İrsaliyeler

Taleplerin listesi ve durumları: Hazırlanıyor, Taslak, Gönderiliyor, Gönderildi, Kabul edildi,
Reddedildi, İptal, Hata, Sağlayıcı bekleniyor, Gerekmiyor. Kayda dokununca inceleme sayfası açılır.

### 4.4 İnceleme sayfası

- Alıcı, VKN/TCKN, alias durumu, teslim adresi, araç/dorse/şoför/nakliyeci, not, satır özeti.
- **Değişiklikleri kaydet** (taslak, hata ve sağlayıcı bekleniyor durumlarında; gönderilmemiş
  entegratör taslağı da güncellenir).
- **Gönder (GİB)** (onay sorulur), ardından durum okunur.
- **A4 yazdır** / **80 mm yazdır**. Sağlayıcı yoksa yalnız **Sevk fişi** basılır
  ("e-İrsaliye değildir" ibaresiyle).
- Gönderilmiş, kabul edilmiş veya reddedilmiş belge düzenlenemez.

### 4.5 Diğer ekranlar

- **Yönlendirilmiş hareket** (Taşıma): kayıt `registerForWithDespatch` ile yapılır; hedef raf eşlenmişse
  inceleme sayfası açılır. Eski BC paketinde `registerFor`'a geri düşülür.
- **Fason İşlemler**: sevk sonrası "e-İrsaliyeyi kontrol et, gönder ve yazdır" düğmesi.

Yardım: terminaldeki "Nasıl Kullanılır?" → "Transfer sevk ve e-İrsaliye".

## 5. API (dynops/warehouse/v2.0)

Temel adres: `https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/api/dynops/warehouse/v2.0/companies({companyId})/`

Bound action yanıtları `{"value": "<json metni>"}` biçimindedir. Yazma işlemleri otomatik
tekrar denenmez; belirsiz hatada istemci aynı `idempotencyKey` ile yeniden sorgular.

| Entity set | Eylem | Gövde | Dönen |
|---|---|---|---|
| `transferOrders('{no}')` | `ship` | `linesJson`, `overridesJson`, `userId`, `idempotencyKey` | `transferOrderNo`, `postedShipmentNo`, `eDespatchRequired`, `eDespatch{}` |
| `transferOrderLines` | (okuma) | | satırlar, `outstandingQuantity`, `lotRequired`, `serialRequired`, `gtin` |
| `transferOps('')` | `createAndShip` | `requestJson`, `userId`, `idempotencyKey` | `ship` ile aynı |
| `transferOps('')` | `resolveReceiver` | `fromLocationCode`, `fromBinCode`, `toLocationCode`, `toBinCode` | önerilen alıcı |
| `transferOps('')` | `listReceivers` | `receiverType`, `searchText`, `maxCount` | tedarikçi/müşteri ve adresleri |
| `transferOps('')` | `findByIdempotencyKey` | `idempotencyKey` | önceki sonuç |
| `inventoryMovements('{no}')` | `confirmLine`, `registerWithDespatch` | `userId`, `overridesJson`, `idempotencyKey` | `activityNo`, `registeredNo`, `eDespatch{}` |
| `movements('{no}')` | `registerForWithDespatch` | `userId`, `overridesJson`, `idempotencyKey` | `activityNo`, `registeredNo`, `eDespatch{}` |
| `shipments('{no}')` | `postWithDespatch` | `print`, `printerId`, `overridesJson`, `userId`, `idempotencyKey` | sevk + `eDespatch{}` |
| `eDespatchRequests({entryNo})` | `getDraft` | | talep + `providerDraft{}` (alıcı, adresler, satırlar) |
| | `updateDraft` | `changesJson` | güncel talep |
| | `send` | | güncel talep |
| | `print` | `format` (0 A4, 1 80 mm, 2 sevk fişi), `printerId`, `copies` | yazdırma işi |
| | `refreshStatus`, `retry` | | güncel talep |
| `eDespatchRequestLines` | (okuma) | | serbest hareket satırları |

`overridesJson` / `changesJson` alanları (yalnız gönderilenler değişir):
`receiverType` (1 Kendi şirketi, 2 Tedarikçi, 3 Müşteri — ad da kabul edilir), `receiverNo`,
`receiverAddressCode`, `purpose` (1 Depolar arası, 2 Fason, 3 Konsinye, 4 Diğer), `toBinCode`,
`vehiclePlateNo`, `trailerPlateNo`, `driverFirstName`, `driverFamilyName`,
`driverIdentificationNo`, `shippingAgentCode`, `note`.

Talep durumu (`status`) sayısaldır: 0 Hazırlanıyor, 1 Taslak, 2 Gönderiliyor, 3 Gönderildi,
4 Kabul, 5 Ret, 6 İptal, 7 Hata, 8 Sağlayıcı bekleniyor, 9 Gerekmiyor.

## 6. Kabul senaryoları (sandbox)

1. Eşlemeler: FASON/V001 → tedarikçi (Fason); SUBE2 → kendi şirketi; KONSINYE → müşteri.
2. ANA → FASON/V001 transferini terminalden sevk edin. Beklenen: taslakta alıcı tedarikçi VKN'si
   ve alias'ı, teslim adresi Order Address, DespatchAddress = ANA; TRANSFER ve FASON referansları.
3. Taşıma bilgisini değiştirin, Turkcell TEST'e gönderin; durum Gönderildi olunca A4 belge
   yazıcısına, 80 mm termal yazıcıya gitmeli. 80 mm genişliğini kontrol edin.
4. Aynı "Sevk Et"e iki kez basın: tek transfer sevkiyatı, tek e-İrsaliye.
5. V001 rafına yönlendirilmiş hareket kaydedin: inceleme sayfası açılır.
6. Stok hareketi (Invt. Movement) kaydedin.
7. Fason sevk: alıcı fasoncu, amaç Fason.
8. Connector kaldırılmışken: talep "Sağlayıcı bekleniyor", yalnız sevk fişi basılır.
9. Negatif: önizlemede kayıt oluşmaz; kayıtlı olmayan alıcı → genel alias + uyarı; farklı
   alıcılara giden raflar tek belgede → hata; gönderilmiş belgede `updateDraft` reddedilir.
10. Eşlemesiz 100 hareket e-İrsaliye üretmemeli.

## 7. Testler

- Android: `android/app/src/test/.../feature/TransferShipWorkflowTest.kt` (16 test).
- WMS AL: `al-tests/src/EDespatch/EDespRequestTests.Codeunit.al` (codeunit 72145). Connector
  kurulu olmayan bir şirkette çalıştırın; connector kuruluyken sağlayıcı olayları yanıtlar.
- e-Dönüşüm AL: `bc-extension/test/src/DYNDespatchReceiverTest.Codeunit.al` (78942) ve
  `DYNDespatchBinTransferTest.Codeunit.al` (78943).
- render-service: `pnpm test:thermal` (80 mm PDF genişliği).
