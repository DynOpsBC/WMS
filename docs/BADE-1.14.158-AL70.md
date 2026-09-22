# BADE APK 1.14.158 / AL 1.14.1.70

Stoktan Tekli LP Oluştur ekranında aynı lot şartı kaldırıldı. Aynı ürün ve lokasyondaki farklı lotlara ait stok girişleri birlikte seçilerek tek LP oluşturulabilir. Her kaynak giriş ayrı LP satırında kendi lotunu, SKT'sini, miktarını ve kaynak belge bağlantısını korur. Ürün, lokasyon, varyant ve seri uyumluluk kontrolleri devam eder.

Çoklu seçimde seçilen her girişin LP yapılabilir miktarının tamamı kullanılır. Raf boş bırakılırsa uygun kaynak raflardan hedef rafa hareket kaydedilir. Raf belirtilirse seçilen lotların stokları o rafta yeterli olmalıdır. Stok kontrolü lot bazında yapılır; bir lotun fazlası başka lotun eksiğini karşılayamaz. Aynı isteğin tekrarı ikinci LP oluşturmaz.

Bu özellik için APK 1.14.158-bade ve BCWMSApp 1.14.1.70 birlikte gereklidir. ZIP içindeki .app dosyası Business Central'a yüklenir. Test uzantısı müşteri kurulum paketinin parçası değildir.

## Doğrulama

- AL 1.14.1.70 yalnız sand0309 Sandbox'a yüklendi.
- Kaynak bağlantısı testleri: 21 adlandırılmış test geçti; koşucu adsız sonuç dahil 22 geçti, 0 hata raporladı. Farklı lotların aynı/farklı raflardan birleştirilmesi, lot/SKT/kaynak/miktar korunması, tekrar isteği ve lot bazında yetersiz stok senaryoları dahil.
- Android: 453 birim testi, release lint ve imzalı APK derlemesi geçti.
- Emülatörde iki arayüz testi geçti: farklı lotlu iki girişin seçili kalması ve sunucu desteği yokken gönderimin engellenmesi. Bu arayüz testleri sahte okuma verileri kullanır.
- Fiziksel terminal, okuyucu ve yazıcı ile müşteri verileri üzerinde uçtan uca test yapılmadı. Canlı ortama girilmedi.

Yalnız customer/bade dalı ve BADE güncelleme kanalı içindir. DKC/EMU değiştirilmedi. Önceki 1.14.157 / AL69 silinmiş çekme kontrolleri korunur.
