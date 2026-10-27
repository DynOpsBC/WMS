Kitoko Android 1.14.199 (200199)

Ana menüde ve depo girişinde **Ortam / şirket değiştir** düğmesi bulunur. Ortam ve şirket ayrı kartlardan seçilir; **Seçilen şirkete bağlan** düğmesi WMS bağlantısını doğrular. Başarısız doğrulamada mevcut ortam, şirket ve operatör korunur. Başarılı geçişte hedef ortamın terminali ve operatörü seçilip PIN ile giriş yapılır.

Sand2010, DemoSandbox, Production, mevcut ortam ve bu kiracıda daha önce bulunan ortamlar birlikte aranır. Arama paralel yapılır; oturum süresi yaklaştığında Microsoft belirteci arka planda yenilenir. Özel ortam adı **Başka ortam ekle** altında girilir. Vazgeçmek yalnız seçim taslağını kapatır.

Uygulama kimliği `com.dynops.bcwms.kitoko`; güncelleme kanalı `android-kitoko-channel`. BC paketi değişikliği gerekmez. Kaynak tabanı `d12a44843ab9fbf7d4fa02a713400182fa85b032`; sürüm eki bu değişiklikleri içerir.

Doğrulama: 623 birim testi, 360 × 640 dp terminal boyutunda 15 ekran testi, release lint ve imzalı release derlemesi geçti. Mevcut giriş testleri küçük ekranda kullanıcı ve PIN alanlarına kaydırarak erişir. Emülatörde imzalı 1.14.198 üzerine 1.14.199 kurulumu ve soğuk açılış doğrulandı. Canlı BC’ye stok işlemi veya yazdırma işi gönderilmedi.
