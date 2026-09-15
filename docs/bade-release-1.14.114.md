# BADE 1.14.114 — Toplamada palet okuyucu girişi

Android sürümü: **1.14.114-bade**, versionCode **200114**. 1.14.113'te yayımlanan LP kartı ve mal kabul sonrası MTE işlemleri bu pakette de bulunur.

## Düzeltme

Toplamanın yalnız okutma alanı salt okunurdu. Bu nedenle kodu klavye tuşları veya metin olarak gönderen okuyucuların verisi alana giremiyordu. Alan artık Android'in düzenlenebilir giriş bağlantısını kullanır; ekran klavyesi kendiliğinden açılmaz.

- Palet penceresi tamamen açılıp kaynak kontrolü bitince okutma alanı odaklanır.
- Okuyucunun Enter, sayısal Enter veya Tab bitiş tuşu barkodu işler ve sonraki palet için odağı korur. Metin olarak gönderilen CR/LF/Tab da desteklenir.
- Bitiş karakteri göndermeyen okuyucunun kodu alanda görünür. **Okunan Paleti Doğrula** düğmesiyle bu kodu işleyin.
- Kamera ve mevcut intent okuyucu yolu desteklenir. Arkadaki pencerenin alanı ön plandaki palet penceresiyle birlikte aynı intent olayını işlemez.
- Miktar değişip kaynaklar yeniden yüklenirken yarım barkod temizlenir. Sıradaki palet doğrulaması ve BC kayıt kontrolleri devam eder; okutma tek başına ambar kaydı yapmaz.

Bu sürüm Android değişikliğidir; AL veya Windows Print Agent değişikliği gerektirmez. Gerçek saha okuyucusu, DataWedge profili ve BC stok hareketi uçtan uca test edilmedi.

## Teknik dayanak

Zebra'nın [Keystroke Output belgesi](https://techdocs.zebra.com/datawedge/latest/guide/output/keystroke/) okuyucunun hem tuş olayları hem InputMethodService üzerinden metin gönderebildiğini belirtir. Salt okunur alan yerine gerçek Android EditText kullanılması bu iki yolu karşılar. Klavye çıkışı fiziksel okuyucuyla harici klavyeyi ayırt eden bir kimlik doğrulama mekanizması değildir.

## Doğrulama

- BADE ve EMU için ayrı ayrı 342 JVM testi başarılı.
- 13 okuyucu/pencere testi emülatörde başarılı: native tuşlar, InputConnection metin girişi, Enter/Tab, suffixsiz doğrulama, yükleme sırasında yarım kod temizliği, yazılım klavyesi ve modal otomatik odağı.
- BADE lint 0 hata, 77 uyarı. İmzalı APK kimliği/sürümü ve mevcut BADE sertifikası doğrulandı.
- Emülatörde 1.14.113 üzerine veri silmeden 1.14.114 kurulumu ve uygulama açılışı başarılı.
