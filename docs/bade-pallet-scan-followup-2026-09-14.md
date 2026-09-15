# Sevkiyat / toplama palet okutma geri bildirimi

## Tespit

- `PalletPickSheet` okutma alanını yalnız bir sonraki kaynak palet adımı varsa gösteriyordu. Kaynak listesi boş döndüğünde kullanıcı hata ve pasif onay düğmesi görüyor, paleti okutacağı alanı göremiyordu.
- Paylaşılan LP000005 fotoğrafında ürün AB.01091, miktar 380 ADET, depo MERKEZDEPO, raf A.TOPLAM, lot A102116 görünüyor. Toplama fotoğrafındaki lot A103309 gibi okunuyor; düşük çözünürlüklü fotoğraftan alınan bu değer canlı BC verisiyle doğrulanmadı.
- Sunucudaki `ListPickLineSources` ürün, varyant, depo, raf ve doluysa lot/seri bilgisine göre filtreliyor. Open, Built ve uygun belgeye Assigned durumları kabul ediliyor. Dolayısıyla "Oluşturuldu" durumu tek başına engel değil; farklı lotlu stok aynı toplama satırını karşılayamaz.

## Değişiklik

- Ortak toplama ekranında QR okutma alanı, kaynak listesi boş veya hatalı olduğunda da görünür kalır. Donanım taraması için otomatik odak ve kamera seçeneği korunur.
- Plan yokken okutma, okunan kodu ve onaylanmama nedenini gösterir; stok hareketi veya doğrulama kaydı oluşturmaz. Sorun giderilip liste yenilendiğinde palet yeniden okutulmalıdır.
- Kaynak bulunamama mesajı beklenen ürün, depo, raf ve lotu gösterir; LP içeriği ile toplama satırını karşılaştırmaya yönlendirir.
- Sıfır miktarlı sıfırlama işlemi palet toplama olarak değerlendirilmez.
- Farklı lotlu paletin reddedildiğini ve hatanın beklenen kaynağı gösterdiğini doğrulayan JVM regresyon testi eklendi.

BC stok kayıtları değiştirilmedi. APK veya BC paketi yayınlanmadı. Önceki belgede belirtilen, tüm palet/miktar tahsislerinin sunucuya iletilmesiyle ilgili kısıt bu arayüz düzeltmesiyle çözülmez.

## Yerleştirmede elle girişin geri açılması

Kullanıcının devam talebiyle, tekil yerleştirmedeki LP alanında ve raf bazlı toplu yerleştirmedeki raf/LP alanında elle giriş yeniden açıldı. Operatör etiketi okutabilir veya numarayı yazıp OK/Enter ile ilerleyebilir. Alan açıklamaları iki yöntemi de gösterir. Girilen LP aynı eşleşme ve sunucu doğrulamasından geçer; sevkiyat/toplamanın yalnız okutma kuralı değişmez.

## Doğrulama

- `:app:compileBadeDebugKotlin` başarılı.
- `:app:testBadeDebugUnitTest --tests 'com.dynops.bcwms.feature.PalletPickPlanTest'` başarılı.
- `git diff --check` başarılı.
- Gerçek terminalde tarama, görsel arayüz testi ve canlı BC sevkiyat kaydı yapılmadı.

## Yayın — 1.14.111

Kullanıcının yayın talebiyle BADE Android 1.14.111-bade (200111) güncellemesi yayınlandı. Kaynak `release/bade-1.14.111` dalında `c14aa69` commit'idir; çalışma alanındaki diğer tamamlanmamış işler bu pakete alınmadı. Önceki 1.14.110 yayınının build/updater yaması korunmuştur.

- 325 JVM testi başarılı; lint hata/kritik hata yok (73 uyarı, 17 bilgi).
- İmzalı release derlemesi başarılı; uygulama kimliği, sürüm kodu ve mevcut BADE sertifikası doğrulandı.
- Yayın: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.111
- Genel indirme URL'sinden APK indirilip SHA-256 kontrol edildi; BADE güncelleme kanalı 200111 olarak doğrulandı.
- EMU ve eski imzalı EMU kanalları önce/sonra aynı kaldı. BC paketi yayınlanmadı; gerçek terminal kurulumu yapılmadı.
- Yerel yayın kanıtı: `output/bade-putaway-1.14.111/publication-verification.json`.

## Çalışma ağacı eşitlemesi — 15 Eylül 2026

Yereldeki değişiklikler commit edildi ve yayımlanan `release/bade-1.14.114-scanner` dalı bu çalışma ağacına birleştirildi. Android uygulama ve AL kaynakları 1.14.114 yayın dalıyla aynıdır. Ek olarak yayın iş akışında BADE/EMU imza sertifikası zorunlu doğrulanır. Derleme çıktıları `output/` altında yerelde saklanır; dağıtım paketleri GitHub Releases üzerindedir. BC ortamına kurulum yapılmadı.
