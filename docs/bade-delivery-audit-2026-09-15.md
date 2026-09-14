# BADE teslim öncesi inceleme — 15 Eylül 2026

**Karar: koşulsuz teslim için hazır değil.** Android tarafındaki aşağıdaki düzeltmeler hazırlandı. Çoklu paletin BC kayıt anında doğrulanması ve gerçek ortam kabul testi açık. Bu inceleme yeni bir yayın yapmadı; müşterideki 1.14.111 bu düzeltmeleri içermez.

## İncelenen kaynak ve kapsam

- Yayındaki Android 1.14.111 / 200111 kaynağı: `c14aa69`.
- Çalışma dalı: `audit/bade-delivery-20260915`, ayrı `WMS-audit-bade-delivery` çalışma ağacı.
- Ana `WMS` ağacındaki tamamlanmamış MTE, LP ve diğer değişiklikler bu incelemeye dahil edilmedi; üzerlerine yazılmadı.
- Odak: Merve'nin bildirdiği LP/QR akışı, yanlış veya bulunamayan palet, satır gruplama, miktar, bağlantı kesilmesi, küçük ekran ve klavye nedeniyle işlemin tamamlanamaması.

## Düzeltilen hatalar

| Bulgu | Eski davranış / etkisi | Düzeltme ve kanıt |
|---|---|---|
| Odaklı barkod alanı eski ekran bilgisini tutuyordu | Hedef RAF-A'dan RAF-B'ye değişse bile ikinci barkod RAF-A callback'ine gidiyordu | Güncel callback ile işleme. Gerçek Compose testi önce başarısız, düzeltmeden sonra başarılı |
| Farklı depo veya ölçü birimleri aynı gruba girebiliyordu | Aynı raf kodu farklı depolarda kullanıldığında ya da ADET/KOLİ satırlarında yanlış toplam | Grup anahtarına depo ve ölçü birimi eklendi; kartta ikisi de gösteriliyor. Önce başarısız olan iki regresyon testi |
| Kapasitesi bitmiş satıra miktar dağıtılıyordu | İlk satırın kalanı sıfırsa sonraki açık satırın miktarını alabiliyordu | Yalnız pozitif, sonlu kapasiteye dağıtım. Önce başarısız olan regresyon testi |
| Grup miktarı azaltılınca eski kalan miktar durabiliyordu | İki satır 10+10 iken toplamı 5 yapmak ikinci satırın eski 10 miktarını bırakabiliyordu | Dağıtım sıfırlanacak satırları da içeriyor; toplama doğrulaması ve yerel kanıtı buna göre temizleniyor |
| Fazla miktar sessizce kırpılıyordu | İstenen miktarın yalnız bir bölümü işlenmesine rağmen grup akışı tamamlanabiliyordu | Kapasiteyi aşan dağıtım reddediliyor; miktar penceresi sınırı ve nedenini gösteriyor |
| Başarısız lot sorgusunda pencereyi kapatmadan tekrar deneme yoktu | Operatör girdiği miktarı yeniden girmek zorunda kalıyordu | Lot sorgusu yeniden denenebiliyor, girilen miktar korunuyor; yükleniyor ve hata ayrı gösteriliyor |
| Bazı pencerelerde klavye alt işlemleri gizleyebiliyordu | Kalite değer/sonuç, şifre yenileme ve toplu LP pencerelerinde erişim riski | Ortak kaydırılabilir pencere ve klavye boşluğu kullanıldı |
| Pasif yazıcılar olumlu durum mesajına dahil oluyordu | Operatör aktif yazıcı bulunduğunu sanabiliyordu | Aktif/pasif sayıları ayrıldı; hiç aktif yazıcı yoksa uyarı. Bu, fiziksel yazıcının hazır olduğuna dair test değildir |
| Kamera kaynağı pencere kapanınca açık kalabiliyordu | Tekrarlı kamera açılışlarında kaynak ve eski callback riski | Kullanılan kamera use case'leri, analiz ve ML Kit istemcisi kapatılıyor; geç callback ve kapanış yarışı korunuyor. Fiziksel kamera testi henüz yok |

Yerleştirmede elle LP girişi açık kaldı. Zorunlu toplama alanında donanım/kamera okutma kuralı korunuyor. Palet sorgusu başarısızsa okutma alanı kaybolmuyor; okutulan LP için neden onay verilemediği gösteriliyor.

## Açık teslim engelleri

### P1 — Çoklu palet tahsisi BC kayıt işleminin içinde sabitlenmiyor

`PalletPickSheet` bütün gerekli paletleri terminalde okutuyor, ancak `confirmLine` yalnız ilk LP'yi sunucuya gönderiyor. `al/src/Pick/PickMgmt.Codeunit.al` içindeki `ConfirmPickLineInternal` açıklaması ve `ResolvePickSourceLp` akışı kalan miktarın kayıt sırasında aynı raftaki diğer paletlerden tamamlanmasına izin veriyor.

Örnek: terminal LP-A'dan 5 ve LP-B'den 5 aldırdıktan sonra başka işlem LP-B'nin stoğunu değiştirirse, kontrol ile kayıt arasındaki sürede BC farklı LP kullanabilir. Android'in kayıt öncesi tekrar kontrolü ayrı bir istektir; bu yarışı ortadan kaldırmaz. Bu mevcut açık, önceki `bade-feedback-2026-09-14.md` belgesinde de kayıtlıdır.

Gerekli iş: bütün LP + miktar tahsisini BC'ye iletmek, belge/satırla saklamak ve kayıt işlemi içinde yalnız doğrulanmış tahsisi tüketmek; eşzamanlı stok değişimini hatayla durdurmak. AL kodu bu incelemede değiştirilmedi, derlenmedi veya BC'ye kurulmadı.

### P1 — Gerçek BC ve terminal kabul testi eksik

Test şirketi ve kullanılabilir belgeler henüz belirtilmedi. Canlı stok hareketi yapılmadı. Aşağıdaki akışların BC defterleri ve LP bakiyeleri karşılaştırılarak tamamlanması gerekiyor:

1. Mal kabul → LP oluşturma → QR etiketi → yerleştirme; elle LP ve okutma yolları.
2. Aynı ürün için doğru/yanlış lot, raf, depo, seri ve ölçü birimi; sıfır/eksik stok; etiketi olmayan palet.
3. Tek ve çoklu palet toplama → miktar azaltma/sıfırlama → ambar kaydı → sevkiyat; Take/Place ve LP bakiyeleri eşitliği.
4. İki terminalin aynı stoğu kullanması, onay ortasında bağlantı kesilmesi, tekrar deneme; çift kayıt veya yanlış palet tüketimi olmaması.
5. Zebra DataWedge tetik tuşu, kamera izni reddi/aç-kapa, gerçek etiket basımı, operatör değiştirme ve uygulama güncelleme.

### Teslim profili kararı — Yönetici test girişi

`LoginFlow.allowAdminBypass` tüm flavor'larda açık. BC servis hesabı bağlıyken yönetici test geçişi yalnız BC bağlantısını kontrol ediyor ve `startAdminTestSession` çağırıyor. Kaynak yorumuna göre bu bilinçli kurulum/saha testi özelliği; sessizce kaldırılmadı. Müşteriye verilecek cihazda bu geçişin erişimi ve BC/WMS rol sınırları doğrulanmalı. Bu inceleme kapsamlı güvenlik denetimi değildir.

## Doğrulama

Son toplu çalışma başarılı (`final-validation.log`, `validation-summary.json`):

- BADE: 332 JVM testi, 0 hata/atlanan.
- EMU: aynı 332 JVM testi, 0 hata/atlanan (664 test çalıştırımı, 332 ayrı senaryo).
- BADE emülatör: 26 test, 0 hata/atlanan — 18 bağlantısız ekran, 5 barkod, 3 miktar/palet/lot penceresi.
- BADE lint: 0 hata, 77 uyarı.
- EMU lint: 0 hata, 77 uyarı.
- BADE debug APK derleme ve test kurulumu başarılı; yeni release APK yayımlanmadı.
- `git diff --check` başarılı.

Çalıştırma:

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew \
  :app:testBadeDebugUnitTest :app:testEmuDebugUnitTest \
  :app:lintBadeDebug :app:lintEmuDebug :app:connectedBadeDebugAndroidTest \
  --no-daemon --continue --console=plain
```

Emülatör: Android 16 / API 36.1, 720×1280 px, 320 dpi (360×640 dp). Ayrı debug uygulaması ve oturumsuz BC kullanıldı. Donanım barkod senaryoları gerçek DataWedge yerine `ScanBus` olaylarıyla çalıştı.

18 ekran için test gerçek üretim composable'ını açar, yazı bulunduğunu ve varsa Yenile'nin çökmeye yol açmadığını kontrol eder: mal kabul, yerleştirme, toplama, sevkiyat, paketleme, LP, ad hoc/yönlendirilmiş hareket, iki sayım ekranı, üretim, montaj, kalite, yazıcı, ürün/raf/ambar hareketleri sorgusu ve yardım. Bunlar bağlantısız açılış kontrolleridir; uçtan uca işlemler veya bütün düğmelerin testi değildir. Test görünümünde ana uygulama gezinme çubuğu yoktur.

Yerel kanıtlar: `output/delivery-audit-20260915/`. İlk başarısız regresyon çıktıları korunmuştur. Bazı önceki emülatör denemeleri test zamanlaması/Android 16 test bağımlılığı uyumu nedeniyle başarısız oldu; nihai sonuç yalnız son çalışmayı esas alır. Üretim Compose sürümü değiştirilmedi.
