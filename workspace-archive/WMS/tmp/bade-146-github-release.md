Sevkiyat > Toplama ekranında seçilen AB.02029 / A.C01.13 satırı, belgedeki başka ürünün (YM.00273 / Y.A01.11) kaynak paleti bulunamadığı için açılamıyordu.

- Satırın palet planı artık yalnız seçilen ürün ve onunla aynı stoğu paylaşabilen önceki satırları kontrol eder.
- Ortak LP stoğu base miktarda düşülür; farklı ölçü birimleri aynı stoğu iki kez kullanamaz. Sıfırlanan satırlar stok ayırmaz.
- Belge kaydında bütün pozitif toplama satırları ve okutma kanıtları doğrulanmaya devam eder.
- Kaynak palet hatası raf okutulunca kaybolmaz; hata ayrıntısı ayrı kutuda gösterilir.

429 Android birim testi (15 yeni regresyon), release lint ve imzalı APK derlemesi başarılı. Önceki BADE APK ile aynı imza kullanılır. Hata mesajını koruyan hedefli emülatör testi geçti; önceden mevcut ayrı klavye gizleme testinin Android 16 emülatöründeki zaman aşımı ve karşılaştırmalı kontrolü ekte belgelendi.

BC paketi değişmedi: **1.14.1.62**. Canlı BC çekme/kaydetme işlemi yapılmadı; LP000159'un gerçek stok/lot uygunluğu BC tarafından ayrıca doğrulanır. Bu sürüm önceki LP/etiket ve Bana Ata düzeltmelerini içerir.

Kaynak tabanı 211e468170136c61a18890144b2683d59d1a28f5; sonraki Android kod/test ve not değişiklikleri kaynak-degisiklikleri.patch dosyasındadır.
