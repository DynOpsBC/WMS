# BADE BC 1.14.1.65 — üretim lot seçimi

- HM / YM ile başlayan lot takipli ürünler: en yakın geçerli SKT önce (FEFO).
- Diğer lot takipli ürünler: en eski açık stok girişinin nakil tarihi önce (FIFO).
- HM/YM için SKT'siz stok tarihli stoklardan sonra değerlendirilir; tarihi geçmiş stok otomatik önerilmez.
- Açık lot seçimi ve terminalde hazır LP seçimi korunur.
- BC'nin rezervasyon, çekilebilir raf ve mevcut çekme kontrolleri kullanılmaya devam eder.
- Önceden oluşturulmuş çekmeler yeniden sıralanmaz. Henüz işlenmemiş eski çekmeyi iptal edip yeniden oluşturun.

APK 1.14.153 yeterlidir; Android güncellemesi yoktur.
Paket sand0309'a yüklenip doğrulandı. Canlı BC ortamına yüklenmedi.

## Doğrulama

AL derleme, izin ve nesne öneki kontrolleri başarılı.
Sandbox'ta 7 test metodu geçti (test aracı genel sonuç kaydıyla 8 başarılı, 0 başarısız raporluyor).
AB.00175 için 1050 adet önerisi A101296 lotundan ve bu lotu içeren gerçek kaynak raflardan oluşturuldu.
120000 adetlik ayrı test talebinde eski stoktan yeni lota geçiş doğrulandı.
A101812 açıkça seçildiğinde seçim korundu.
HM/YM SKT sırası, diğer kodlarda giriş tarihi sırası ve bloke/tükenmiş/geçmiş SKT'li stok kontrolleri geçti.
Testler BC'nin gerçek öneri satırlarını belge oluşturma noktasında inceledi; müşteri çekmesi veya stok hareketi kaydetmedi. Sentetik stok ve test emri temizlendi.
