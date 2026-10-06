BADE 1.14.139 — Terminal yazıcısı senkronu

Kurulum sırası: önce BCWMSApp 1.14.1.57 uzantısını BC'ye yükleyin, ardından BADE APK 1.14.139'u güncelleyin. Print Agent değişikliği gerekmez.

Terminalde Yazıcılar ekranından seçilen etiket veya belge yazıcısı, aktif şirketin ilgili WMS terminal kaydına kaydedilir. BC onayından sonra cihaz seçimi güncellenir. BC'den değiştirilen seçim, Yazıcılar ekranı açıldığında/yenilendiğinde ve PIN girişinde alınır. Sürekli arka plan eşitlemesi yapılmaz.

Bağlantı veya yetki hatasında başarı mesajı gösterilmez. Terminal/şirket değişmişse önceki isteğin cevabı yeni terminalin ayarlarını değiştirmez. BC pasif terminali, pasif kullanıcıyı, başka terminale ait kullanıcıyı ve uyumsuz/pasif yazıcıyı reddeder. Bir yazıcı seçilirken diğer kullanım türünün mevcut seçimi korunur.

Önceki 1.14.138 sürümünde yalnız cihazda yapılan seçim, bu sürümde BC'deki kayıtla yenilenir; gerekirse yazıcıyı bir kez yeniden seçin.

Doğrulama: 392 Android birim testi, lint, imzalı release derlemesi ve Windows AL derlemesi başarılı. Fiziksel terminal/BC üzerinde uçtan uca çalışma testi yapılmadı.
