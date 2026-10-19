# BADE: ortam bazlı ortak yazıcılar — BC 1.14.1.56

Bu özellik açıkça etkinleştirilir. Paketi yüklemek mevcut şirket kurulumunu
kendiliğinden değiştirmez. APK ve Windows Print Agent güncellemesi gerekmez.

## Kurulum

1. BC paketini hedef ortama yükleyin ve uzantının HTTP isteklerine izin verin.
2. Yazıcı bağlantısının yönetileceği şirkette UMUT, DYNOPS veya BC_SUPPORT ile
   WMS Kurulum sayfasını açın.
3. Mevcut doğru `business-central.runtime.secrets.json` dosyasını içe aktarın
   ve Azure yazdırma bağlantısını doğrulayın.
4. **Yazıcıları Bu Ortamda Ortak Kullan** eylemini çalıştırın.
5. Diğer şirketlerde Yazıcılar sayfasını veya terminal yazıcı listesini açın.
   Bağlantı ve fiziksel yazıcı bilgileri ortak kayıttan alınır; o şirketin
   yazdırma görevi oluşturulur. JSON'u her şirkete yeniden yüklemeyin.
6. Her terminalde kullanılacak yazıcıyı seçin. İki terminal aynı yazıcıyı veya
   farklı yazıcıları seçebilir.

İlk şirket durum kuyruğunun tek okuyucusudur. Bu şirketin WMS yazdırma görevi
çalışır durumda tutulmalıdır. Diğer şirketlerin görevleri kendi baskı
sonuçlarını uygular ve kendi bekleyen işlerini gönderir.

Ortak bağlantıyı değiştirmek/secret yenilemek ilk şirketin Kurulum sayfasından
yapılır. Ortak mod açıkken bağlantı alanları elle düzenlenmez; yeni JSON içe
aktarılır veya Azure Secrets eylemi kullanılır.

## Veri ayrımı

- Azure bağlantısı, güvenli depodaki bağlantı anahtarları ve fiziksel yazıcı
  kimliği/durumu bu BC ortamında ortaktır.
- Kullanıcılar/PIN'ler, terminal seçimleri, depo/lokasyon, kopya sayısı, BC
  rapor ayarları, belgeler ve baskı geçmişi şirket bazında kalır.
- Mevcut `DYNOPS.BADE.MAIN.PRINT01` istasyon kimliği değişmez. JSON'daki
  `companyId=BADE` ortak dağıtımın yönlendirme kodudur; belge şirketi değildir.
- Her iş kendi Cloud Job GUID'si ile kaydedilir. Durum okuyucusu sonucu
  kalıcı ortak gelen kutusuna yazar ve ancak Commit'ten sonra Azure mesajını
  tamamlar. İlgili şirket kendi işini doğrulayıp sonucu uygular.
- Aynı mesajın tekrarı ikinci baskı veya ikinci tamamlanma kaydı oluşturmaz.
  Uygulanmış sonuçların GUID kayıtları 30 gün korunur; uygulanmamış sonuçlar
  silinmez. Hatalı eşleşme `Last Error` ile bekler.
- Şirketlere kopyalanan fiziksel yazıcı kodu başka bir istasyona aitse işlem
  hata verir; mevcut yazıcı eşleşmesi sessizce değiştirilmez.

## Ortam sınırı

Production ve Sandbox aynı Azure kuyruklarını paylaşmamalıdır. Kaydedilmiş
BC ortam adı/türü değişirse ortak bağlantı kapalı davranır ve yazdırma hata
verir. Bu, Production veritabanının Sandbox'a kopyalanması halinde canlı
yazıcıya iş gönderilmesini önler. Böyle bir kopyada ayrı Azure kurulumu ve
ortak bağlantının kontrollü yeniden kurulması gerekir; mevcut kaydı silerek
eski şirket secret'larına geri dönmeyin.

## Doğrulama

Windows CI üretim paketini ve `al-print-tests` test uzantısını ayrı ayrı
derler. Test uzantısı üretime kurulmaz. Testler yalnız boş/atılabilir BC test
ortamında, test izolasyonu ile çalıştırılmalıdır: fixture tabloları temizler.
Derleme, testlerin BC hizmetinde çalıştırıldığı anlamına gelmez.

Otomatik AL senaryoları: isteğe bağlı etkinleştirme; şirket ayarlarını koruyan
eşitleme; farklı ortamı reddetme; istasyon çakışması; yabancı şirket sonucunu
uygulamama; GUID ile tamamlama ve tekrar; geçiş öncesi işi kurtarma; yanlış
yazıcı sonucunu bekletme.

Canlıya geçiş kabul kontrolü: aynı ortamdaki A ve B şirketlerinden aynı
yazıcıya farklı belgeler gönderin; iki işin yalnız kendi şirketinde Sent
olduğunu, diğer şirketin geçmişinde görünmediğini doğrulayın. Ardından farklı
iki yazıcıyla tekrarlayın. Agent çevrimdışıyken işleri bekletip tekrar
açıldığında tamamlandığını kontrol edin. Bu fiziksel/çok şirketli kontrol
derleme ortamında yapılmaz.
