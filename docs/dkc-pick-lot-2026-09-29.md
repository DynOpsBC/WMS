# DKÇ / EMU — toplamada lot zorunluluğu

## Bildirim ve sınır

29 Eylül 2026 bildirimi: toplamada mevcut lot elle girilince hata oluşuyor;
lot görüntüleme listesi boş. Görselde PI000018, KLC-7, WMS / HM.0001 ve
REF-0F6BAA25 görülüyor. Lot numarası ve sahadaki uygulama sürümü bildirilmedi.

DKÇ API erişimi kayıtlı Microsoft oturumunun MFA süresi dolduğu için
başarısız oldu. Bağlı Android cihazı yok. Bu belgenin gerçek ayarları ve
REF kodunun ham hata mesajı doğrulanmadı; aşağıdaki yeniden üretilebilir
kod hatası bildirilen iki belirtiyle uyumludur.

## Neden ve düzeltme

`PickLineRequiresLot` yalnız stok/satış lot takibinden de zorunluluk
üretiyordu. BC'nin `Warehouse Activity Line` lot doğrulaması ise ambar
takibi açık değilse `Warehouse item tracking is not enabled for ...`
hatası veriyor. `availableLots` Warehouse Entry toplamlarından beslendiği
için stok hareketlerinde görülen bir lot ambar girişlerinde olmayabilir.

- Ambar takibi kapalı ürünlerde stok/satış lot bayrakları toplamada lot
  zorlamaz. Var olan satır lotu ve ambar takibinin gerektirdiği lotlar korunur.
- Terminal, BC'nin açıkça döndürdüğü `lotRequired=false` değerini stok
  yoklamasıyla değiştirmez; lot alanını gizler. Eski BC paketinde alan
  yoksa/null ise stok yoklaması devam eder.
- Dört toplama miktar ekranı aynı kuralı kullanır. Grup lot listeleri
  seçili kaynak rafla sınırlandırılır.
- Ambar takibi kapalı hatası terminalde Türkçe bir neden ve destek
  referansıyla görünür.
- Raf bilgisi bulunmayan Item Ledger Entry kayıtları raf lot stokuna
  eklenmez. BC'nin yerel doğrulaması ve sevkiyat lot kontrolü korunur.

## Paketleme

BC sürümü `1.14.2.21`; EMU Android aday sürümü `1.14.161` (`200161`).
Android sürümü Gradle `releaseVersionCode` / `releaseVersionName`
parametreleriyle derlendi. 29 Eylül 2026 tarihinde standart ve tarihsel
EMU güncelleme kanalları 200161 sürümüne ilerletildi.

Önce BC paketi yüklenmeli, sonra terminal APK'sı güncellenmelidir.
Android tek başına eski BC paketinin yanlış `lotRequired=true` değerini
düzeltemez. APK mevcut uygulamanın imzasına uygun seçilir: standart
imza için RELEASE, tarihsel imza için UYUMLU. Uygulama kaldırılmaz.

## Doğrulama

- 398 EMU JVM testi geçti; hata/atlanan test yok. Sekiz yeni Android
  senaryosu lot politikası ve ambar takip hata metnini kapsıyor.
- EMU debug lint: 0 hata; 79 uyarı ve 19 bilgi (deprecation dahil).
- AL uygulama ve 7 yeni regresyon testini içeren test paketi başarıyla
  derlendi. AL testlerinin gerçek
  BC üzerinde çalıştırılması ve fiziksel terminal denemesi yapılmadı.
- Standart ve tarihsel imzalı release APK derlemeleri ile release lint
  kontrolleri geçti. Her iki APK kimliği, 200161 sürüm kodu, imzası ve
  debug kapalı durumu doğrulandı.
- GitHub yayını tamamlandı: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.161-emu
- Her iki APK ve BC paketi public bağlantıdan indirilip SHA-256 ile doğrulandı.
  İki EMU manifesti 200161; BADE kanalı ve genel latest değişmedi.
- Canlı BC kurulumu yapılmadı. Yayın etiketi temel commit olan
  `8fb17141bbeb1d4e81cb9c3e979d06eec54c0ba0` üzerindedir; kaynak düzeltmeleri
  yayına `source-changes.patch` olarak eklenmiştir.

Saha doğrulamasında KLC-7 takip kodunun ambar ayarları, PI000018 satırları
ve girilen lotun Warehouse Entry kayıtları karşılaştırılmalıdır. Ambar
takibi zaten açıksa veya aynı hata sürerse ham BC hata mesajı gerekir;
bu bildirim için canlı çözüm doğrulandı kabul edilmemelidir.
