# DKC toplama ve parçalı üretim çıktısı — 18.11.2026

Çalışma `WMS-emu` / `emu` içindedir. Kullanıcının terminal güncelleme talebi kapsamında Android 1.14.173 (200173) ve BCWMSApp 1.14.2.32 hazırlanmıştır. Commit/push yapılmadı; kaynak farkı ve yayın kanıtları `output/dkc-update-20261118/` altında saklanır.

## Kullanıcı akışı

- DKC toplamasında Multi / Mono / Tek SKU ayrımı yoktur. Kaynak belge listede ve belge içinde **Satış siparişi: …** veya **Serbest bırakılmış üretim emri: …** olarak gösterilir. Karma toplamada tüm kaynaklar gösterilir; bilinmeyen kaynaklar tahmin edilmeden **Kaynak belge** olarak kalır.
- Ana menüde **Üretim Çıktısı**: açık/biten üretim emirleri, ürün, planlanan/çıkan/kalan miktarlar, gerçekleşme yüzdesi ve arama.
- Serbest bırakılmış emirde **Çıktı Bildir** açılır. Örneğin 5.000 adetlik emirde 2.000 girilir, kayıt tarihi ve çıktı gözü seçilir. Zorunluysa son kullanma tarihi girilir.
- **Lot Ata — BC'den Otomatik**, ürün kartındaki standart `Lot Nos.` serisini kayıt tarihiyle kullanır. Lot takipli üründe seri yoksa hata verir; başka müşterinin veya WMS genel serisine sessizce geçmez. BC zorunlu tutuyorsa lot bilgi kartı da oluşturulur. Bu aşama stok kaydı yapmaz.
- **Deftere Naklet** onayından sonra BC standart çıktı günlüğü kaydedilir. Emir satırının son operasyonu kullanılır; rota yoksa rotasız çıktı kaydedilir. Birden fazla olası son operasyon varsa tahmin edilmeden hata verilir. İş emri/operasyon otomatik bitirilmez.
- Sunucu kayıt anında kalan miktarı tekrar okuyup kilitler. 2.000 kayıt sonrası emirde 2.000 çıkan / 3.000 kalan görünür; yeni bildirimle kalan miktar üretilebilir. Kalanı aşan, sıfır ve negatif miktarlar reddedilir.
- Başarılı kayıttan sonra **Bu Çıktının Etiketini Bas** yalnız o bildirimin ürün/lot/temel birim miktarını etiket penceresine taşır. Miktar/kopya ayarlanabilir. Baskı üretim kaydından ayrı bir işlemdir; baskı başarısızlığı aynı çıktıyı yeniden nakletmez.
- **Bildirimi Kapat — Yeni Üretime Geç** tamamlanan sonucu cihazdan kapatır. Sonucu kapatmadan pencere yeniden açılırsa aynı bildirim gösterilir. Önceki çıktılar lot listesinden de etiketlenebilir.
- Seri numarası takibi bu toplu lot akışının dışında kalır; seri takipli üründe BC ürün izleme ekranına yönlendirilir.

## Tekrar gönderim ve kayıt bütünlüğü

Bildirim UUID'si ve değişmez istek gövdesi ilk ağ isteğinden önce cihazda senkron saklanır. Hazırlama/lot atama aynı UUID ile tekrarlandığında aynı sonucu döndürür. Gövde değiştirilerek aynı kimlik kullanılamaz. Yerel kayıt şirket/ortam/emir satırına bağlıdır; bozuk veya başka satıra ait kayıt yeni üretime izin vermez.

`productionOutputRequests` API'si, üretim emri sonradan bitse bile değişmeyen UUID üzerinden kayıt ve iptal işlemlerini sürdürür. Sunucu isteği oluşturan BC kullanıcısını kontrol eder. Hazırlanan talep iptal edilebilir; nakledilmiş bir isteğe iptal gönderilirse nakledilmiş sonuç döner, stok geri alınmış gibi gösterilmez.

Her bildirim kendi çıktı günlük grubunu kullanır; mevcut satır bulunursa silmez veya birlikte nakletmez. Standart kayıt `SetSuppressCommit(true)` ve `CommitBehavior::Error` altında çalışır. Madde hareketi, beklenen temel miktar ve tamamlanan istek aynı işlemde doğrulanır. Miktar uyuşmazlığında tamamı geri alınır. Tekrar gönderim tamamlanan sonucu döndürür.

## BC kaynakları ve yetkiler

AL sürümü **1.14.2.32**. Yeni sayfa 72233 `productionOrderLines`; 72234 numarası ayrı nesne türlerinde talep tablosu, talep API sayfası ve kayıt codeunit'i için kullanılır. Mevcut genişletilmiş 72200–72489 aralığı içindedir; başlangıç 72000–72099 aralığı dışındadır.

- `productionOrderLines.prepareOutput(quantity, postingDate, binCode, expirationDate, requestId)`
- `productionOutputRequests(<UUID>).postOutput()` / `.cancelOutput()`
- `items.printProductionLabels` mevcut etiket kanalını kullanır.
- `itemLedgerEntries.orderNo/orderLineNo` çıktı geçmişini emre bağlar.
- Toplama API'sinde `sourceSummary`, satırlarda `sourceType/sourceSubtype` eklenmiştir.

User/Admin yeni kayıt codeunit'ini çalıştırabilir. View talep kayıtlarını okuyabilir; yeni kayıt codeunit'i için çalıştırma yetkisi verilmez. Talep API'si oluşturan BC kullanıcısına filtrelenir. Yeni `ProductionOrderLine` rol filtresi liste ve kayıt anında uygulanır; alan numaraları farklı olduğu için eski rota satırı filtreleri bu tabloya kopyalanmaz. Günlük ve talep yazma izinleri kontrollü codeunit üzerindedir.

## Çalıştırılan kontroller

- Android `:app:assembleEmuRelease :app:assembleEmuLegacyRelease :app:testEmuDebugUnitTest`, sürüm parametreleri 200173 / 1.14.173: **BUILD SUCCESSFUL, 467 test, 0 hata/başarısızlık/atlanan**. Her iki release lint kontrolü geçti.
- Standart ve tarihsel imzalı APK'ların uygulama kimliği, sürümü ve sertifika parmak izleri doğrulandı. Standart APK emülatöre kuruldu; giriş ekranında 1.14.173-emu görüldü. Bu, fiziksel terminal testi değildir.
- Daha güncel `docs/al-publish-from-macos.md` eski `CLAUDE.md` macOS kısıtının yerini alır. Microsoft AL 30 derleyicisi ile uygulama ve test kaynakları başarıyla derlendi.
- DKC `Sandbox1111` ortamında BCWMSApp 1.14.2.32 yayımlandı; uygulama API'leri HTTP 200 verdi. Genel test paketindeki 72100 aralığı kurulu üretim eklentisiyle çakıştığından hedef testler 79870–79874 aralığındaki izole `DKC Output Verification` eklentisinde çalıştırıldı.
- **7 AL sunucu testi geçti**: BC lot serisini tek tüketme / hazırlamada stok oluşmaması; kalan miktar değiştiğinde kayıt reddi; tamamlanan kaydın tekrarında aynı sonuç; iptal ve sahiplik; miktar sınırları / kaynak başlığı; gerçek 2.000 + 3.000 çıktı, lot, hareket, kalan ve tekrar; üretim/mal kabul etiket ayrımı.
- Gerçek kayıt testi, BC'deki **Doc. No. Is Prod. Order No.** ayarını açık tutar. Standart emir doğrulaması belge numarasını değiştirdiği için isteğin tekil belge numarası tüm doğrulamalardan sonra atanır. İki kısmi kayıtta tam iki çıktı hareketi ve toplam 5.000 üretilen / 0 kalan doğrulandı.
- Sunucu testleri `AutoRollback` altında çalıştı. API ile test ürünü, test hareketleri ve çıktı taleplerinin geride kalmadığı doğrulandı. Sonuçlar `server-tests.json` ve `sandbox-rollback-verification.json` içindedir. Test çalıştırıcısı kapanışında bir SignalR iptal uyarısı kaydetti; tüm 7 test sonucu Passed ve süreç çıkış kodu 0 idi.

## Sınırlar

Fiziksel terminal/yazıcı, yönlendirilmiş rota üzerinde operasyon kaydı, farklı ölçü birimi ve iki terminalin eş zamanlı canlı kullanımı denenmedi. Android testleri ile BC sunucusunda gerçek kayıt testleri ayrı ayrı raporlandı.

AI Workbench bağımsız Claude incelemesi bu genişletme için de denendi; `403 oauth_not_allowed_for_organization` hesap erişim hatası verdi. İnceleme onayı alınmadı. Rapor: `AI_WORKBENCH/.state/runs/20261118-150057-c063ff/run.json` (çalışma alanı köküne göre). Ücretsiz modele kaynak kod gönderilmedi.

Standart API imzaları yerel BC sembol/kaynakları ve Microsoft'un [Item Jnl.-Post Batch](https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/codeunit/microsoft.inventory.posting.item-jnl.-post-batch) / [Create Reserv. Entry](https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/codeunit/microsoft.inventory.tracking.create-reserv.-entry) belgeleriyle karşılaştırıldı.

## İstenen toplu göz QR PDF'leri

18.11.2026 DKC Production / DKC şirketi / DKC WMS konumunun gerçek göz kayıtları kullanıldı. Hammadde 12, hurda 1, karantina 1, mal kabul 1, mamul 10, sevk 1, yarı mamul 11, üretim 4: toplam **41 göz**. Üretim alanındaki AYR.0001 de dahil edildi; ÜR.0002 kodu aksanı ve noktasıyla korundu.

`output/dkc-qr-20261118/DKC-8-Alan-Toplu-QR-A4.pdf`: 7 sayfa, sayfada 6 etiket. `DKC-8-Alan-QR-100x100mm.pdf`: 41 tekil etiket sayfası. Her iki PDF rasterize edilip bütün QR'lar yeniden okutularak kaynak kodlarla birebir eşleştirildi. Ayrıntı `verification.json` içindedir. PDF'ler müşteri verisi içerdiğinden APK'nın genel GitHub yayınına eklenmedi.

## Tamamlanan yayın

- **DKC Production**: BCWMSApp **1.14.2.27 → 1.14.2.32**, 18.11.2026 15:15 TRT. Automation API `schemaSyncMode=Add` kullanıldı. Kurulu sürüm tekrar okundu; diğer kurulu eklentilerin sürümlerinin değişmediği doğrulandı. Üretim emirleri, bildirimler, toplama API'leri HTTP 200; hazırlama/nakletme/iptal/etiket eylemleri metadata üzerinden doğrulandı. Canlı stok kaydıyla test yapılmadı.
- **Android 1.14.173-emu / 200173**: [yayın](https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.173-emu). Standart `android-emu-channel` ve tarihsel imza `android-emu-legacy-channel` güncellendi. Her iki APK yayın URL'sinden yeniden indirilip SHA-256 eşleştirildi; dört manifest dosyası yayın URL'lerinden okunarak karşılaştırıldı.
- Standart APK SHA-256: `54d4249d8da90b4739db31a0e46fc02a52fb12e25912a725134235627a987ab0`.
- Uyumlu APK SHA-256: `a5acbc36c5863fb0d6791f1a8c71faa3ece7b3c86244ad1d52ff1d97487b5dba`.
- Yalnız emülatör bağlıydı. Fiziksel terminale yükleme yapılamadı; cihazdaki **Güncellemeyi Kontrol Et** ile uygun imza kanalından kurulur.

Yayın kayıtları: `production-publish-result.json`, `production-api-verification.json`, `android-artifacts.json`, `android-publication.json`. Kaynak çalışma ağacı commit edilmedi; yayın etiketi kaynak tabanı `3effee04716f38e1d37569b0c87fdc71a6e10afd` üzerindedir. Bu sürümün ek kaynak değişiklikleri yerel `source.patch` dosyasında saklanır; GitHub'ın otomatik kaynak arşivi tek başına yayımlanan değişiklikleri içermez.

## Terminal ekranı ek doğrulaması

Kullanıcının yeniden kontrol talebiyle canlı üretim API'si HTTP 200 ve iki yayın kanalındaki 1.14.173 sürümü tekrar doğrulandı. Android emülatöründe `ProductionOutputScreenTest` sınıfındaki **3 cihaz arayüz testi geçti**: EMU menüsünde üretim çıktısının bulunması, lot düğmesi ve boş miktarın reddi; hazırlanmış lotun geri yüklenmesi ve nakletme onayı; nakledilmiş sonucun kendi lotu/2.000 ADET miktarıyla etiket adımına aktarılması ve yeniden nakletmenin açılmaması. Testler izole yerel bildirimlerle çalışır; gerçek BC veya yazıcıya kayıt göndermez. Gerçek BC nakli yukarıdaki 7 sunucu testi kapsamında ayrıca doğrulanmıştır. Sonuç: `production-ui-verification.json`; Gradle `connectedEmuDebugAndroidTest` BUILD SUCCESSFUL, 3 test.

## 1.14.174 ek (18.11.2026 akşam)

- Paketleme tuşu DKC'de Multi / Mono / Tek SKU seçicisi ve sepet/koli kuyruğu yerine doğrudan Sevkiyat > Toplama listesini açar; belgeye basınca parçalı toplama ekranı gelir. BC değişikliği yoktur (BCWMSApp 1.14.2.32).
- Üretim çıktısı Sandbox1111'de gerçek emirle terminalden denendi: UR000381 / BILLET BPS, 10 KG; BC lotu DKC26L601-004, madde hareketi 3316, emir 100 → 110 çıkan / 90 kalan, ÜR.0003 gözü 110 KG. Etiket basılmadı; fiziksel terminal denenmedi.
- Kaynak bu commit ile depoya alınmıştır; 1.14.173 yayını commit edilmemiş çalışma ağacından yapılmıştı.
