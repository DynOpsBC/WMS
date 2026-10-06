# BADE sandbox adayı 1.14.150

Bu paket birlikte kullanılmalıdır:

- Android: `BCWMS-BADE-1.14.150.apk` (`versionCode` 200150)
- Business Central: `BCWMSApp-1.14.1.64.app`

Kurulum sırası:

1. `sand0309` ortamında BC uzantısını 1.14.1.64 sürümüne yükseltin.
2. Terminale 1.14.150-bade APK'sını mevcut uygulamanın üzerine kurun.
3. Uygulamada ortamın `sand0309`, şirketin BS olduğunu doğrulayın.

Zorunlu kabul testleri:

1. Aynı açık üretim ambar çekmesinde ilk hazır LP'yi okutun ve kaydedin.
2. Çekme açık kalırken aynı üretim emrinin kalan ihtiyacı için ikinci hazır LP'yi seçin. İkinci LP eski kayıt geçmişine takılmadan yalnız kendi miktarını hazırlamalıdır.
3. Kaydetmeden önce raf ve LP okutmalarının zorunlu olduğunu doğrulayın.
4. Kayıttan sonra LP'nin üretim gözüne taşındığını, üretim emrine atandığını ve içeriğinin/lotunun değişmediğini doğrulayın.
5. `Stoktan Tekli LP Oluştur` ekranında aynı ürün, lot, seri, lokasyon ve ölçü birimine sahip iki stok girişini işaretleyin. Ekran iki kaydın LP'lenebilir miktarlarını tek LP planında göstermeli; oluşan LP'deki ayrı satırlar kendi Madde Defter Giriş No.'larını korumalıdır.
6. Farklı lot veya lokasyondaki ikinci kaydın seçiminin reddedildiğini doğrulayın.

Canlıya geçiş için bu iki uçtan uca testin sand0309'da başarıyla tamamlanması gerekir.
