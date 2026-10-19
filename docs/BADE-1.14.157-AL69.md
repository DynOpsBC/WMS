# BADE APK 1.14.157 / AL 1.14.1.69

## Silinen üretim çekmesi

BC'den doğrudan silme de terminal iptalindeki LP kontrollerinden geçer. Ürün aktarılmamış boş hedef LP pasife alınır; çekmenin LP rezervasyonları bırakılır. Hazırlanmış üretim LP'sinde stok bulunduğunda çekme silinemez: mevcut çekme üzerinden teslim tamamlanmalıdır. Bu sürüm hazırlanmış paleti otomatik olarak eski raflarına geri dağıtmaz.

Standart başarılı çekme kaydının belgeyi kapatmasına izin verilir. İstisna yalnız aynı çekmenin kayıt belgesi mevcutken ve bekleyen satır kalmamışken uygulanır. Silinmiş belgeden gelen eski LP başlatma isteği sunucuda reddedilir. Aynı açık belgeye tekrar başlatma isteği mevcut hedef LP'yi döndürür.

Terminal açık çekmeyi 10 saniyede bir yeniden kontrol eder; belge bulunamazsa satır ve teslim pencerelerini kapatır, işlem düğmelerini kilitler. 404 cevabı artık teslim başarısı olarak gösterilmez. Mevcut hedef LP düğmesi de sunucuya sorar; yalnız yerel ekrandaki bilgiye dayanarak başarı bildirmez. Ağ yokken silinme anında görünmeyebilir; yazma isteklerindeki BC kontrolü geçerlidir.

## Tek LP'de birden fazla stok girişi

LP → Stoktan Tekli LP Oluştur → ürün numarası → Stokları Getir. Birlikte kullanılacak girişlerin kutularını işaretleyin. Seçili kayıt sayısı görünür; ikinci seçim ilkini kaldırmaz. Aynı ürün, varyant, lot, seri, lokasyon ve temel ölçü birimi gerekir. Çoklu seçimde her girişin LP'lenebilir miktarının tamamı tek LP'ye eklenir; her satır kendi stok giriş bağlantısını korur. Farklı lotları birleştirme bu akışın kapsamı değildir.

Sunucu desteği alınamadığında ekran sessizce tek seçime dönmez. Bağlantı hatası ile eski BC paketi ayrı açıklanır; çoklu gönderim destek doğrulanana kadar kapalıdır. Stokları Getir desteği yeniden sorgular. Sand0309 metadata'sında çoklu stok girişi API'si doğrulandı.

## Eski LP'leri topluca bulma

BC LP listesi → Eksik Kaynakları Toplu Bağla, listedeki filtrelere uyan tüm aktif LP satırlarını tarar. Önceden hangi LP'ye ikinci satır eklendiğini bulmanız gerekmez. Tüm LP'ler için önce liste filtrelerini kaldırın. Kaynağı kesin satırlar onayla bağlanır; birden fazla aday veya yetersiz miktar varsa atlanır ve raporlanır. Ürün/varyant/lokasyon/lot/seri, kayıtlı kaynak belge ve uyumlu SKT kontrol edilir. Yalnız lot benzerliğine bakarak kaynak tahmini yapılmaz.

## Doğrulama

- AL 1.14.1.69 ve test paketi 1.0.0.77 yalnız sand0309 Sandbox'a yüklendi.
- Üretim LP testleri: 38 adlandırılmış sonuç geçti (temizlik dahil); koşucu adsız sonuçla 39/0 raporladı. Yeni testler doğrudan BC silmesi, boş hedefin pasife alınması, eski isteğin LP yaratmaması ve hazırlanmış stokun korunmasını kapsar. Normal ve yönlendirilmiş depo hazırlama/teslim testleri de geçti.
- Kaynak bağlantısı testleri: 18 adlandırılmış sonuç geçti; koşucu adsız sonuçla 19/0 raporladı. Toplu onarımın belirsizlik, kapasite ve tekrar çalıştırma kontrolleri dahil.
- Android: 453 birim testi geçti. Gerçek tekli LP ekranının emülatördeki iki arayüz testi geçti: iki girişin seçili kalması ve desteklenmeyen sunucuda gönderimin engellenmesi. Arayüz testi sahte okuma verileriyle çalışır, stok yazmaz.
- Fiziksel terminal/okuyucu/yazıcı ve müşterinin mevcut kayıtlarıyla baştan sona işlem bu doğrulamanın parçası değildir. Canlı ortama girilmedi.

Yalnız customer/bade dalına aittir. DKC/EMU paketleri ve güncelleme kanalı değiştirilmez.
