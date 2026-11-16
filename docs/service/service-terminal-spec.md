# BCWMS Servis Modülü — BC Servis Yönetimi + Terminal (saha teknisyeni)

Durum: tasarım / uygulama spesifikasyonu (16 Kas 2026). İlk müşteri: Ayıkband (BC 29, Service Management modülü hiç kullanılmamış, BCWMS kurulu değil).
Hedef: BC **standart** Servis Yönetimi tablolarını (Service Header/Item Line/Line/Order Allocation/Comment) kullanarak
saha teknisyeninin terminalden işini yürütmesi ve ofisin BC içinden servis işlerini yönetmesi. Kendi iş emri tablosu YOK
(`origin/feature/service-management-module` dalındaki özel tablolu deneme bu işin temeli değildir).

Alan adları: `docs/service/bc-service-fields.txt` (Base Application 28.1 sembollerinden). Derleme sembolleri 28.1, `app.json application 24.0`.

## 0. Uygulama durumu (16 Kas 2026)

- Uygulandı: bölüm 2–8 (dal `feat/service-terminal`). Codex `ai run` ile üç görev (AL çekirdek, AL API+sayfalar, Android), ardından inceleme ve sandbox testinde bulunan düzeltmeler.
- Spec'ten sapmalar / eklemeler:
  - Zaman damgaları kullanıcının BC saat diliminde (`Type Helper.GetCurrentDateTimeInUserTimeZone`); BC online AL `Time()` UTC döner.
  - `Service Mgt. Setup."Fault Reporting Level"` None ise varsayılan kodlar IRIS düzeyine çeker (None iken arıza alanı eklenemez).
  - Not ve ekler (imza) tamamlanmış ama kaydedilmemiş siparişe eklenebilir; bitmiş servis kalemine başlama/parça/işçilik/bekletme reddedilir.
  - `setRepairStatus` yalnız *Waiting for Customer* / *Spare Part Ordered* kodlarını kabul eder.
  - Aynı kaleme birden çok aktif teknisyen atanmışsa `finishWork` yalnız çağıranın tahsisini kapatır.
  - `IMZA-` dosya adı yalnız imza eylemiyle oluşur; boş ek reddedilir.
  - Terminal "Bugün bitenler" yerine **Kayıt bekleyen** (Finished + kaydedilmemiş tahsisler); İşlerim önceliğe göre sıralı; fotoğraf tam çözünürlük (FileProvider + `TakePicture`, en fazla 1600 px).
  - Sayfa başlıkları `DOPSWHS.tr-TR.xlf` ile Türkçe. BC, `<trans-unit>` öğelerini `<body><group id="body">` altında bekler; grup olmadan dosyanın tamamı yok sayılıyordu (dosyadaki eski `CountSheet` vb. geçersiz kimlikli 25 yer tutucu da kaldırıldı). Bu düzeltme diğer müşteri dallarındaki `DOPSWHS.tr-TR.xlf` için de geçerlidir; oralarda henüz yapılmadı.
  - Teknisyen Ata diyaloğu siparişin ilk servis kalemi satırıyla dolu açılır ve servis maddesini gösterir.
- Doğrulama: AL 0 hata; Android 359 birim testi; Ayıkband Sandbox1611'de emülatörle uçtan uca (SS000006 → SV000001, ILE −6 METRE; SS000004 → SV000002, ILE −12 METRE; SS000005 PARCA ile beklemede). BC sayfalarının Türkçe görünümü 1.14.0.5 ile tarayıcıda kontrol edildi.
- Denenmedi: fiziksel el terminali, Premium olmayan / yalnız `DOPSWHS SERVICE` izinli teknisyen kullanıcısı, faturalama, canlı ortam.
- Sandbox demo verisi: `docs/service/sandbox-seed` (yalnız sandbox'ta çalışır; `runSeed`, `resetSeed`, `addDemoOrder`).

## 1. Kapsam

### BC tarafı (AL, BCWMSApp BASE, sürüm 1.14.0.5)
1. Servis kurulumu (tekil kayıt) + teknisyen eşlemesi (BC kullanıcısı → Kaynak).
2. "Servis Yönetimi" sayfası: açık servis siparişleri, durum/öncelik/teknisyen/yanıt tarihi, sayaçlar, teknisyen atama, standart sayfalara geçiş.
3. Terminal için API sayfaları (dynops/warehouse/v2.0) + iş kuralları codeunit'i.
4. "Varsayılan servis kodlarını oluştur" eylemi (onarım durumları, durum öncelikleri, arıza alanı/belirti/arıza/çözüm, iş türü, SAAT birimi) — yalnız eksikleri ekler, mevcut kayda dokunmaz.

### Terminal (Android, `dynops` flavor, sürüm 1.14.109)
1. Ana menüde "Servis" kutusu (servis kurulumu etkinse). Kurulumda "Depo modüllerini gizle" açıksa yalnız Servis + Destek ve Ayarlar görünür.
2. Teknisyen: "İşlerim" listesi → iş detayı → İşe Başla / Beklet / Bitir, arıza-çözüm kodları, işçilik saati, parça (barkod/elle), not, fotoğraf, müşteri imzası, "Servisi Kaydet (Sevk)".
3. Servis yöneticisi (dispatcher): "Tüm İşler" sekmesi, teknisyen atama.

Kapsam dışı: fatura kaydı (ofis BC'den yapar), servis sözleşmeleri, teklif, kredi notu, rota optimizasyonu, çevrimdışı mod.

## 2. Nesne numaraları

`al/app.json idRanges` içine `{ "from": 72100, "to": 72199 }` eklenir (main ve tüm müşteri dallarında boş, 16 Kas'ta kontrol edildi). Servis modülü yalnız **72100–72149** kullanır.

| ID | Tür | Ad |
|---|---|---|
| 72100 | table | DOPSWHS Service Setup |
| 72101 | table | DOPSWHS Service Technician |
| 72102 | table | DOPSWHS Service Cue |
| 72100 | codeunit | DOPSWHS Service Terminal Mgt |
| 72101 | codeunit | DOPSWHS Service Defaults |
| 72100 | page | DOPSWHS Service Setup (Card) |
| 72101 | page | DOPSWHS Service Technicians (List) |
| 72102 | page | DOPSWHS Service Dispatch (List, "Servis Yönetimi") |
| 72103 | page | DOPSWHS Svc Assign Dialog (StandardDialog) |
| 72104 | page | DOPSWHS Service Dispatch Cue (CardPart) |
| 72105 | page | API serviceOrders |
| 72106 | page | API serviceItemLines |
| 72107 | page | API serviceLines |
| 72108 | page | API myServiceAllocations |
| 72109 | page | API serviceAllocations |
| 72110 | page | API serviceComments |
| 72111 | page | API serviceRepairStatuses |
| 72112 | page | API serviceFaultAreas |
| 72113 | page | API serviceSymptomCodes |
| 72114 | page | API serviceFaultCodes |
| 72115 | page | API serviceResolutionCodes |
| 72116 | page | API serviceWorkTypes |
| 72117 | page | API serviceTechnicians |
| 72118 | page | API serviceSetups |
| 72119 | page | API serviceAttachments |
| 72100 | permissionset | DOPSWHS SERVICE |

Dosyalar `al/src/Service/` altında. Yeni nesneler Admin/User izin kümelerine de eklenir (mevcut kalıba uy).

## 3. Tablolar

### 72100 DOPSWHS Service Setup (tekil, PK `Primary Key` Code[10])
| Alan | Tür | Not |
|---|---|---|
| Enabled | Boolean | Terminalde Servis kutusu |
| Hide Warehouse Modules | Boolean | Terminal yalnız Servis gösterir |
| Default Work Type Code | Code[10] → Work Type | İşçilik satırında |
| Default Location Code | Code[10] → Location | Teknisyenin depo/araç lokasyonu boşsa parça satırına |
| Allow Terminal Posting | Boolean, InitValue true | Terminalden "Sevk Et" kaydı |
| Require Signature | Boolean | Kayıttan önce imza eki zorunlu |
| Labor Rounding (Hours) | Decimal, InitValue 0.25 | Süre önerisi yuvarlaması |

`GetSetup()` yoksa Init+Insert eder. Install codeunit'e eklenir (Enabled=false).

### 72101 DOPSWHS Service Technician (PK `User Name`)
| Alan | Tür | Not |
|---|---|---|
| User Name | Code[50], TableRelation User."User Name", ValidateTableRelation=false | BC kullanıcı adı (`UserId()`) |
| Resource No. | Code[20] → Resource where Type=Person | Zorunlu |
| Resource Name | FlowField Lookup Resource.Name | |
| Van Location Code | Code[10] → Location | Parça satırı lokasyonu |
| Dispatcher | Boolean | Terminalde Tüm İşler + atama |
| Active | Boolean InitValue true | |

Aynı Resource No. iki aktif kullanıcıya bağlanamaz (OnValidate kontrolü).

### 72102 DOPSWHS Service Cue (PK Code[10]) — FlowField sayaçlar
`Service Header` (Document Type=Order) üzerinde Count: Pending, In Process, On Hold, Finished (henüz kayıtlı değil = hâlâ tabloda), Unassigned (No. of Allocations? — Service Header'da yoksa sayfada hesapla), Overdue (Response Date < bugün, Status<>Finished; FlowFilter `Date Filter` ile). FlowField ile yapılamayanlar CardPart'ta `OnAfterGetRecord` içinde hesaplanır.

## 4. Codeunit 72100 DOPSWHS Service Terminal Mgt (tüm iş kuralları burada; API ve sayfalar yalnız bunu çağırır)

`Permissions` özelliğiyle Service Header/Item Line/Line/Order Allocation/Comment Line, Document Attachment, Repair Status RIMD.
Her yazma işlemi: sipariş `Document Type::Order` olmalı; Status=Finished veya kaydedilmiş satıra yazma reddedilir; açık Türkçe hata mesajları (Label).

| Prosedür | Davranış |
|---|---|
| `CurrentTechnician(var Tech)` / `TryCurrentTechnician` | `UserId()` ile aktif teknisyen; yoksa hata "Bu kullanıcı servis teknisyeni olarak tanımlı değil (Servis Teknisyenleri sayfası)." |
| `AssertDispatcher()` | Teknisyen.Dispatcher değilse hata |
| `AssertCanWork(OrderNo, SILineNo)` | Teknisyen o satıra (veya satır 0 ise siparişe) Active/Finished tahsisi olan kaynak değilse ve Dispatcher değilse hata |
| `AssignTechnician(OrderNo, SILineNo, ResourceNo, AllocDate, Hours)` | Dispatcher. Service Order Allocation ekler: Document Type=Order, Document No., Service Item Line No. (0 ise siparişin ilk servis kalemi satırı), Validate Resource No., Allocation Date, Allocated Hours (>0), Service Item No./Description/Serial kopyala, **Status := Active** açıkça. Aynı kaynak+satır için Active kayıt varsa onu günceller (çift kayıt yok). Satırın Repair Status boşsa Initial kodunu verir. Döner: Entry No. |
| `StartWork(OrderNo, SILineNo)` | AssertCanWork. Servis kalemi satırında Starting Date/Time boşsa Today/Time; Repair Status := `In Process`=true olan kod (Validate → başlık durumu standart öncelik kuralıyla güncellenir). Teknisyenin bu satırdaki Active tahsisinde Starting Time = Time, Service Started=true. |
| `SetRepairStatus(OrderNo, SILineNo, RepairStatusCode)` | AssertCanWork; Validate. (Beklet: Waiting for Customer / Spare Part Ordered kodları) |
| `FinishWork(OrderNo, SILineNo, FaultArea, Symptom, Fault, Resolution, ResolutionNote)` | AssertCanWork; kodları Validate (boş olanı değiştirme); Finishing Date/Time; Repair Status := `Finished`=true kod; not varsa Resolution türünde yorum; teknisyenin Active tahsisi Status=Finished, Finishing Time. |
| `AddLabor(OrderNo, SILineNo, Hours, WorkTypeCode, Description)` | AssertCanWork; Service Line Type=Resource, No.=teknisyenin kaynağı, Service Item Line No., Quantity=Hours (>0), Work Type Code (boşsa Setup.Default Work Type). Döner Line No. |
| `AddPart(OrderNo, SILineNo, ItemNo, Qty, LocationCode)` | AssertCanWork; Type=Item; Location: parametre → teknisyen Van Location → Setup.Default Location → başlık lokasyonu. Döner Line No. |
| `DeleteLine(OrderNo, LineNo)` | AssertCanWork; Quantity Shipped=0 ve Quantity Consumed=0 ise sil. |
| `AddComment(OrderNo, SILineNo, CommentType, Text)` | Service Comment Line: Table Name=Service Header, Table Subtype=Order, No., Table Line No.=SILineNo, Type (General/Fault/Resolution/Internal), Date=Today; metin 80 karakterlik parçalara bölünür, Line No. 10000 artışlı. |
| `AddAttachment(OrderNo, FileName, Base64, Kind)` | Base64 Convert ile InStream; Document Attachment `SaveAttachmentFromStream` (RecordRef = Service Header). Kind='signature' ise dosya adı `IMZA-<No>-<yyyyMMddHHmmss>.png`. Döner attachment ID. |
| `PostShipment(OrderNo, Consume)` | Setup.Allow Terminal Posting; Setup.Require Signature ise IMZA- ekli dosya şartı; tüm satırlarda Qty. to Ship = Outstanding (Consume ise Qty. to Consume); `Service-Post`.PostWithLines(Header, TempLine(boş), Ship=true, Consume, Invoice=false). Döner son sevk no (Last Shipping No.). Hata mesajı aynen yukarı. |
| `ElapsedHours(StartDate, StartTime, Rounding)` | Bugün/şimdiye kadar geçen süre, Rounding'e yukarı yuvarlanmış; terminal öneri için de API alanı olarak kullanılır. |

## 5. API sayfaları (APIPublisher dynops, APIGroup warehouse, APIVersion v2.0, ODataKeyFields SystemId, `id` = SystemId)

Hepsi salt okunur (InsertAllowed/ModifyAllowed/DeleteAllowed=false, Editable=false) — yazma yalnız `[ServiceEnabled]` eylemleriyle.
Eylemler `Microsoft.NAV.<ad>` ile POST edilir; geri dönüş Text (JSON veya no) ve `ActionContext` gerekmez (mevcut DeviceApi kalıbı).

### 72105 serviceOrder / serviceOrders — Service Header, SourceTableView Document Type=Order
Alanlar: id, no, customerNo, name, address, address2, city, postCode, phoneNo, phoneNo2, eMail, contactName, shipToCode, shipToName, shipToAddress, shipToCity, description, status (Text: enum adı), priority, orderDate, orderTime, responseDate, responseTime, locationCode, serviceOrderType, releaseStatus, assignedUserId,
hesaplanan: technicianNames (aktif tahsislerin kaynak adları, virgülle), allocatedHours, noOfServiceItemLines.
Eylemler (servis kalemi satır no `serviceItemLineNo` Integer; 0 = siparişin ilk satırı):
`assignTechnician(serviceItemLineNo, resourceNo, allocationDate: Date, hours: Decimal)`, `startWork(serviceItemLineNo)`, `setRepairStatus(serviceItemLineNo, repairStatusCode)`,
`finishWork(serviceItemLineNo, faultAreaCode, symptomCode, faultCode, resolutionCode, resolutionNote)`, `addLabor(serviceItemLineNo, hours, workTypeCode, description)`,
`addPart(serviceItemLineNo, itemNo, quantity, locationCode)`, `deleteLine(lineNo)`, `addComment(serviceItemLineNo, commentType, text)`,
`addAttachment(fileName, base64Content, kind)`, `postShipment(consume: Boolean)`.

### 72106 serviceItemLine(s) — Service Item Line (Document Type=Order)
id, documentNo, lineNo, serviceItemNo, serviceItemGroupCode, itemNo, serialNo, description, description2, repairStatusCode, priority, responseDate, responseTime, startingDate, startingTime, finishingDate, finishingTime, faultAreaCode, symptomCode, faultCode, resolutionCode, faultReasonCode, warranty, locationOfServiceItem, customerNo.

### 72107 serviceLine(s) — Service Line (Document Type=Order)
id, documentNo, lineNo, serviceItemLineNo, type (Text), no, description, quantity, unitOfMeasureCode, locationCode, quantityShipped, quantityConsumed, quantityInvoiced, workTypeCode, postedQuantity? yok.

### 72108 myServiceAllocation(s) — Service Order Allocation, OnOpenPage: Resource No. = CurrentTechnician kaynağı, Document Type=Order, Status in Active|Finished, Posted=false
id, entryNo, documentNo, serviceItemLineNo, resourceNo, allocationDate, allocatedHours, status (Text), startingTime, finishingTime, serviceStarted, serviceItemNo, serviceItemDescription, serviceItemSerialNo, repairStatus,
hesaplanan (OnAfterGetRecord, Service Header'dan): customerName, address, city, phoneNo, contactName, orderDescription, orderStatus, priority, responseDate, responseTime, orderSystemId (Guid, serviceOrders'a gitmek için).
Teknisyen tanımlı değilse OnOpenPage hata verir (terminal mesajı gösterir).

### 72109 serviceAllocation(s) — tüm tahsisler, OnOpenPage AssertDispatcher; 72108 ile aynı alanlar + resourceName.

### 72110 serviceComment(s) — Service Comment Line, Table Name=Service Header, Table Subtype=Order
id, no (sipariş), tableLineNo, lineNo, type (Text), date, comment.

### 72111–72116 katalog: serviceRepairStatuses (code, description, initial, inProcess, finished, partlyServiced, referred, sparePartOrdered, waitingForCustomer, serviceOrderStatus), serviceFaultAreas (code, description), serviceSymptomCodes, serviceFaultCodes (faultAreaCode, symptomCode, code, description), serviceResolutionCodes, serviceWorkTypes (code, description, unitOfMeasureCode).

### 72117 serviceTechnicians — DOPSWHS Service Technician (Active=true): userName, resourceNo, resourceName, vanLocationCode, dispatcher.

### 72118 serviceSetup(s) — DOPSWHS Service Setup (tek kayıt; OnOpenPage GetSetup)
enabled, hideWarehouseModules, allowTerminalPosting, requireSignature, laborRoundingHours, defaultWorkTypeCode,
hesaplanan (çağıran kullanıcı): isTechnician, myResourceNo, myResourceName, isDispatcher, userName.

### 72119 serviceAttachment(s) — Document Attachment, Table ID=5900, Document Type=Order (Attachment Document Type)
id, no, lineNo, fileName, fileExtension, attachedDate, user.

## 6. BC sayfaları

- **72100 Service Setup (Card)**, UsageCategory=Administration, Caption "Servis Terminali Kurulumu". Eylemler: Teknisyenler, Servis Yönetimi, **Varsayılan servis kodlarını oluştur** (codeunit 72101).
- **72101 Service Technicians (List)**, Caption "Servis Teknisyenleri", UsageCategory=Lists.
- **72102 Service Dispatch (List)**, Caption "Servis Yönetimi", UsageCategory=Lists, SourceTable Service Header (Order), Editable=false, CardPageId = standart "Service Order" sayfası.
  Sütunlar: No., Customer No., Name, City, Description, Status, Priority, Order Date, Response Date, Response Time, hesaplanan Teknisyen(ler), Atanan Saat, Onarım Durumu (ilk satırın), Gecikme (Response Date < Today ve Status<>Finished → `Unfavorable` stil).
  Görünümler/filtre: Varsayılan Status<>Finished; eylem grupları: **Yeni Servis Siparişi** (Service Order kartı), **Teknisyen Ata** (72103 dialog → AssignTechnician), **Kaynak Tahsisleri** (standart Resource Allocations sayfası, sipariş filtreli), **Servis Siparişini Aç**, **Kayıtlı Servis Sevkiyatları**, **Servis Maddeleri**, **Teknisyenler**, **Kurulum**. FactBox: 72104 Cue.
- **72103 Svc Assign Dialog** (StandardDialog): Servis Kalemi Satırı (lookup), Teknisyen (DOPSWHS Service Technician lookup → Resource No.), Tarih (Today), Saat (Setup yoksa 1).
- **72104 Service Dispatch Cue** (CardPart, cuegroup): Bekleyen, İşlemde, Beklemede, Tamamlandı (kaydedilmemiş), Atanmamış, Geciken. Drilldown Service Dispatch'i filtreli açar.

## 7. Codeunit 72101 DOPSWHS Service Defaults — `CreateMissingDefaults()` (idempotent, yalnız eksik ekler)

- Unit of Measure `SAAT` (Saat).
- Repair Status: `ILK` (Initial, Pending), `ISLEMDE` (In Process), `BEKLEMUS` (Waiting for Customer, On Hold), `PARCA` (Spare Part Ordered, On Hold), `KISMI` (Partly Serviced), `BITTI` (Finished, Finished, Posting Allowed). Durum izinleri (Pending/In Process/Finished/On Hold Status Allowed) standart demo verisine benzer şekilde doldurulur.
- Service Status Priority Setup: Pending=High? — standart: In Process=High, On Hold=Medium High, Pending=Medium Low, Finished=Low (kayıt yoksa).
- Fault Area: `BANT`, `MOTOR`, `RULO`, `ELEKTRIK`, `GENEL`; Symptom: `DURDU`, `KAYMA`, `SES`, `YIRTIK`, `ISINMA`; Resolution: `DEGISIM`, `AYAR`, `TAMIR`, `BAKIM`, `TEMIZLIK`; Fault Code: her alan için `GENEL` (Fault Area×Symptom yerine `Symptom Code` boş).
- Work Type: `MONTAJ`, `TAMIR`, `BAKIM` (birim SAAT).
- Service Mgt. Setup'ta numara serileri boşsa `SRV-SIP` (Service Order Nos.), `SRV-MAD` (Service Item Nos.), `SRV-SEV` (Posted Service Shipment Nos.), `SRV-FAT` (Posted Service Invoice Nos.), `SRV-TKL` (Service Quote Nos.) No. Series + satırı oluşturulup bağlanır (serinin yoksa).
- Servis Kurulumunda Default Work Type boşsa `TAMIR`.
Hiçbir posting group, müşteri, madde veya fiyat OLUŞTURMAZ.

## 8. Terminal (Android) — `feature/ServiceModule.kt` (+ `ServiceWorkflow.kt` saf fonksiyonlar)

- `Screen.Service("Servis")`, `WmsGlyph` içinde uygun bir ikon (yoksa mevcut bir glyph'i kullan, yeni çizim gerekiyorsa basit).
- Ana menü: açılışta (bağlıyken) `serviceSetups` okunur ve SharedPreferences'ta saklanır. `enabled` → "Servis" kategorisi en üstte ("Servis İşlerim", açıklama "Atanan servis işlerini yürüt"). `hideWarehouseModules` → Gelen/Giden/İç Operasyon/Üretim/Kalite/Sorgu kategorileri gizlenir. API 404 (eski BC) → servis kutusu görünmez, hata yok.
- **İşlerim**: `myServiceAllocations?$filter=status eq 'Active'` (ve 'Finished' ayrı filtre çipi "Bugün bitenler"); kart: sipariş no, müşteri, şehir, servis kalemi açıklaması, öncelik renk şeridi, onarım durumu, tahsis tarihi/saati. Yenile düğmesi. Boşsa "Size atanmış açık servis işi yok."
- **Tüm İşler** (yalnız isDispatcher): `serviceOrders?$filter=status ne 'Finished'`; kartta teknisyen adları; detayda "Teknisyen Ata" (serviceTechnicians listesi, tarih=bugün, saat=1 düzenlenebilir).
- **İş detayı**: başlık (müşteri, adres, telefon → `ACTION_DIAL`, adres → `geo:0,0?q=` intent), açıklama, servis kalemleri (serviceItemLines, siparişe filtreli), satırlar (serviceLines), notlar (serviceComments), ekler sayısı.
  Düğmeler (servis kalemi satırı bazında):
  - **İşe Başla** → startWork (Starting Date boşsa görünür).
  - **Beklet** → onarım durumu seçimi (waitingForCustomer veya sparePartOrdered olan kodlar) → setRepairStatus.
  - **İşi Bitir** → sayfa: arıza alanı / belirti / arıza kodu (seçilen alana göre filtreli) / çözüm kodu seçicileri, çözüm notu, işçilik saati (öneri: başlangıçtan bu yana geçen, laborRounding'e yukarı yuvarla; 0 girilirse işçilik satırı eklenmez) → finishWork + addLabor.
  - **İşçilik Ekle** (saat + iş türü), **Parça Ekle** (ScannerTextField ile madde no/barkod; `items?$filter=number eq '<x>'` standart API ile doğrula; miktar) → addPart. Satır listesinde kaydedilmemiş satırı uzun basınca sil (deleteLine, onay).
  - **Not Ekle** (Genel/Arıza/Çözüm/Dahili seçimi) → addComment.
  - **Fotoğraf** → `ActivityResultContracts.TakePicturePreview` → JPEG %80, uzun kenar ≤1600 px → base64 → addAttachment(kind=photo, `FOTO-<no>-<zaman>.jpg`).
  - **Müşteri İmzası** → Compose Canvas imza alanı (Temizle/Kaydet), beyaz zemin siyah çizgi PNG → addAttachment(kind=signature).
  - **Servisi Kaydet** (allowTerminalPosting) → onay diyaloğu (satır özeti, "Parçalar stoktan düşer, işçilik kaydedilir; fatura ofiste kesilir") → postShipment(consume=false) → başarı: "Servis sevkiyatı kaydedildi: <no>".
- Hatalar `BcApi.errorMessage` ile Türkçe gösterilir; her eylemden sonra detay yeniden yüklenir; eylem sürerken düğmeler kilitli (çift gönderim yok).
- Saf fonksiyonlar (birim testli): öncelik etiketi/renk, durum etiketi Türkçe (Pending→Bekliyor, In Process→İşlemde, Finished→Tamamlandı, On Hold→Beklemede), geçen süre yuvarlama, OData filtre kaçışı, imza noktalarından bitmap boyutu, base64 yardımcıları, ana menü görünürlük kararı (enabled/hide).

## 9. Kabul ölçütleri

1. AL derlenir (0 hata), yeni uyarı en aza indirilir; mevcut nesnelerde davranış değişmez.
2. Android `testDynopsDebugUnitTest` yeşil; `assembleDynopsDebug` derlenir.
3. Sandbox'ta: kod oluştur → teknisyen eşle → BC'de servis siparişi aç → Servis Yönetimi'nden ata → terminalde İşlerim'de görünür → başla → parça + işçilik → bitir → imza + fotoğraf → kaydet → BC'de Kayıtlı Servis Sevkiyatı + madde/kaynak hareketleri + ekler görünür.
4. Teknisyen olmayan kullanıcı API'de açık hata alır; dispatcher olmayan atama yapamaz; Finished siparişe satır eklenemez.
