# Element4 / Kitoko Android 1.14.206

- Ürün Sorgu raf dağılımı: renkli raf kartları, büyük raf kodu ve miktar rozeti.
- Lokasyon başlıkta bir kez gösterilir; aynı alan/raf adı tekrarlanmaz.
- Toplam stok, müsait ve rezerve kartları korunur.
- Stok açıklaması ve ürün detayları isteğe bağlı açılır; miktar/birim/varyant bilgileri kartlarda kalır.
- Yalnız arayüz değişikliği; BC stok kayıtları ve hesaplamalar değişmez.

Derleme sürümü: `-PreleaseVersionCode=200206 -PreleaseVersionName=1.14.206`.

Doğrulama: release derlemesi başarılı, 642 birim testi hatasız. Emülatör instrumentation sonucu OK (9 tests); dar 240dp / 1.8 yazı ölçeği ve koyu tema kart testi dahil. Bağımsız incelemede bildirilen dar ekran ve tema sorunları düzeltildi; kalan doğrulama talepleri emülatörde kontrol edildi. Gerçek Sand2010 ekranında toplam 716, HM1 616 ve URT/MONT 100 adet görünümü doğrulandı. Fiziksel cihaz testi yapılmadı.
