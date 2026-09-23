# BADE 1.14.159 / BCWMSApp 1.14.1.71

Kısmi LP işlemindeki **Kalanı yeni LP'ye ayır** seçeneğinde, mevcut LP'de kalacak miktar `0` olabilir. Seçilen ürün satırının tamamı yeni LP'ye aktarılır. Son satırı boşalan kaynak LP mevcut kurala göre **Kullanıldı** durumuna geçer. Diğer kısmi işlem seçeneklerinde `0` geçersiz kalır.

Bu davranış için Android **1.14.159-bade** (versionCode **200159**) ve BCWMSApp **1.14.1.71** birlikte gereklidir. BC paketi yüklenmeden `0` girilirse sunucu işlemi reddeder. ZIP içindeki `.app` dosyası Business Central Uzantı Yönetimi'ne yüklenir.

Yayın, yayımlanmış 1.14.158 / 1.14.1.70 kaynaklarından hazırlanmıştır. BADE dışındaki Android kanalları değiştirilmez.

## Doğrulama

- BCWMSApp 1.14.1.71, AL derleyicisinde hatasız derlendi.
- 453 Android birim testi geçti; release lint ve imzalı APK derlemesi başarılı oldu.
- APK `com.dynops.bcwms.bade`, `versionCode 200159` ve `versionName 1.14.159-bade` içeriyor. İmza sertifikası 1.14.158 BADE APK'sıyla aynı.
- Müşteri BC ortamına kurulum ve fiziksel terminalde uçtan uca deneme bu yayın hazırlığının parçası değildir.
