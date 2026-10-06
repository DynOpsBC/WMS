Üretim çekmesinde farklı raflardaki kaynak LP’lerden ihtiyaç kadar alıp tek hedef LP hazırlama eklendi. Kaynak bakiyeleri korunur. Hazırlık gözüne hareket üretime teslim sayılmaz; aynı çekme belgesiyle Üretime Teslim Et adımı stok ve üretim emrini birlikte günceller.

Kurulum: önce AL 1.14.1.66, sonra APK 1.14.154. Sand0309 kurulumu ve testleri tamamlandı; canlı BC’ye yüklenmedi.

Kullanım: Üretim > Sarfiyat > emir > Ambar Çekme Aç (veya mevcut üretim çekmesini aç) > Yeni Üretim LP > kaynak raf/LP doğrulama > LP Hazırla ve hazırlık gözü okutma > LP Etiketi Yazdır > hazırlanan LP’yi doğrulama > Üretime Teslim Et ve üretim gözü okutma.

Tek hedef LP aynı emrin aynı üretim gözüne giden açık çekme miktarlarının tamamını içerir; kaynak LP’nin tamamı alınmak zorunda değildir. Hazırlık gözü üretim gözünden farklı olmalıdır. Hazırlanmış LP’de miktar/lot değiştirme ve dolu LP’yi iptal etme engellenir.

16 AL test yöntemi ve 444 Android birim testi geçti; release derlemesi, lint ve emülatöre güncelleme kurulumu başarılı. Test raporundaki 17. AL sonucu test koşusunun toplam sonucudur.

HM/YM için SKT, diğer ürünler için FIFO kuralı korunur.
