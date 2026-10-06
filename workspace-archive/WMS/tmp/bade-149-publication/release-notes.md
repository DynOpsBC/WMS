Hazır LP, üretim emrine bağlı standart ambar çekmesiyle LP numarası ve içeriği korunarak üretim gözüne taşınır. Seçilen LP miktarı hazırlanır; başka operatörün veya başlanmış toplamanın çalışması sıfırlanmaz. Aynı ürünün 1200/6800 Al/Yer çiftleri ayrı eşleştirilir.

**APK 1.14.149-bade (200149), BC uygulaması 1.14.1.63 gerektirir.** APK, eski BC üzerinde çekme kaydını reddeder. Terminal ile BC uygulaması aynı ortamda kullanılmalıdır.

445 Android birim testi geçti; release lint 0 hata. APK imzası yayımdaki 1.14.146 ile aynıdır. [Windows CI](https://github.com/DynOpsBC/WMS/actions/runs/35613146337) uygulama ve regresyon test .app dosyalarını başarıyla derledi. 41 üretim AL testi derlendi; BC çalışma zamanı testleri bu yayın sırasında çalıştırılmadı. Gerçek üretim çekme kabulü sandbox ortamında yapılmalıdır.

Dosyalar: tek APK, kurulabilir BC .app içeren AL ZIP, ikisini ve kurulum/test adımlarını içeren sandbox ZIP, SHA256 listesi ve Android kaynak değişiklikleri.

Kaynak tabanı ve AL derlemesi: `5f389e9e8aaad9fce6f35dbbeb83f20e51c26459`. Android değişiklikleri `android-source.patch` dosyasında; derleme sürüm seçenekleri `-PreleaseVersionCode=200149 -PreleaseVersionName=1.14.149`.
