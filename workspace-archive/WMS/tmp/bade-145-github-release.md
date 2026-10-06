BADE 1.14.145 — Bana Ata düzeltmesi (test adayı)

Sevkiyat > Toplama ekranındaki Bana Ata düğmesi terminalin PIN kullanıcısını göndermediği için BC bağlantı hesabına (ör. DYNOPS) atıyor, ardından hatalı bir başarı mesajı gösteriyordu.

- Artık mevcut claim uç noktasına terminalin kullanıcı kodu gönderilir.
- Kaydedilmiş belge sahibi sunucudan okunup doğrulanmadan başarı gösterilmez.
- Kimlik yoksa istek gönderilmez; eski BC hesabına atama ucuna geri dönülmez.
- Başka kullanıcıya atanmış belge otomatik devralınmaz. DYNOPS'a önceden atanmış belge, BC Toplama Kuyruğu > Toplayıcı Ata / Değiştir üzerinden doğru terminal kullanıcısına devredilmelidir.
- Aynı eski geri dönüşü içeren klasik Toplama belgesindeki Bana Ata düğmesi de düzeltildi.

414 Android testi (7 yeni atama regresyonu), release derlemesi ve lint kontrolü başarılı. APK imzası önceki BADE sürümleriyle aynıdır.

AL paketi bu değişiklikte artmadı; önceki aday **1.14.1.62** kullanılmaktadır. APK önceki LP/etiket düzeltmelerini de içerdiği için **test adayıdır**. BADE sandbox/runtime ve gerçek baskı kontrolü henüz tamamlanmadı. Kararlı otomatik güncelleme kanalı değiştirilmedi; canlı belgelere müdahale edilmedi.

Kaynak tabanı 211e468170136c61a18890144b2683d59d1a28f5; sonraki Android kod/test ve not değişiklikleri kaynak-degisiklikleri.patch dosyasında bulunur.
