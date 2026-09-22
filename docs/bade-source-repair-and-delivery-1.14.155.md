# BADE APK 1.14.155 / AL 1.14.1.68

## Üretime teslim

Hazırlık sonrası kaynak raf/LP okutması, yeni hedef LP için teslim doğrulaması sayılmaz. Üretime Teslim Et / LP Hazırla düğmesi artık mevcut sunucu planıyla yerel okutma kaydını önceden karşılaştırır. Eksik veya eski kayıt varsa hedef göz penceresinden önce ilgili satırın raf/LP doğrulama ekranını açar. Gerçek okutma şartı ve kaydetmeden hemen önce sunucudan tekrar kontrol korunur; doğrulanmamış palet otomatik onaylanmaz.

## Eski LP kaynak bağlantıları

BC → LP listesi → Eksik Kaynakları Toplu Bağla.

İşlem listedeki filtrelere uyan aktif LP'leri tarar, ön kontrol sayılarını gösterir. Onayda eşleşmeyi yeniden hesaplar. Aynı ürün/varyant/lokasyon/lot/seri ve varsa kayıtlı belge/SKT bilgisine uyan tek bir açık pozitif giriş bulunan, ayrılabilir miktarı yeterli satırları bağlar. Birden fazla aday varsa en büyük miktarlı girişi seçmez. Kapasite LP satırları arasında tekrar kullanılamaz. Mevcut kaynaklar korunur; stok miktarı, raf ve SKT değiştirilmez. Her bağlantı kaynak hareket kaydına yazılır. JSON sonuç raporunda bağlanan/atlanmış satırlar ve nedenleri bulunur. Belgeye bağlı veya mal kabulü bekleyen satırlar otomatik onarılmaz.

Bu sürüm geçmiş kayıtları yükleme sırasında otomatik değiştirmez. Canlı ortamda hiçbir veri düzeltmesi yapılmadı. Sand0309 salt-okunur ön kontrolünde kaynağı eksik aktif satır sayısı 0 bulundu; fotoğraftaki gerçek eski satırlar bu sandbox verisinde yeniden üretilemedi.

## Küçük LP önceliği

Üretim çekmesinde aynı lot ve aynı rafın uygun LP'leri, elde kalan temel miktarı küçükten büyüğe sıralanır. 1000 adet için 300 + 400 + 500 kaynaklarında 300 + 400 + 300 alınır, son LP'de 200 kalır. Satırdaki sıradan LP önerisi bu sırayı bozmaz. Açıkça hazırlanmış/rezerve edilmiş LP korunur. Satış çekmesinin mevcut sırası değiştirilmedi. Farklı rafların BC'de seçilme sırası bu sürümde değiştirilmedi; HM/YM SKT ve diğer ürünlerde FIFO lot kuralı korunur.

## Doğrulama ve sınırlar

- Android 452 birim testi geçti; release lint hatası 0; imzalı BADE release APK derlendi ve emülatöre kuruldu.
- Sand0309'da 18 adlandırılmış kaynak bağlantısı testi geçti. Test koşucusunun bir adsız sonuç satırıyla rapor sayısı 19'dur.
- Yeni toplu işlem testleri: ön izlemenin salt okunur olması, idempotent bağlama, belirsiz kaynağın atlanması, ortak kaynak kapasitesi, kayıtlı belge eşleşmesi ve bekleyen mal kabulünün atlanması.
- Yeni terminal testleri: eksik/eskimiş okutmanın doğru satıra yönlendirilmesi, 300/400/300 dağıtımı, lotun korunması, temel birim ve önceki tahsis hesabı.
- APK 155'in gerçek terminal UI denemesinde 30 dakikalık operatör oturumu sona erdi ve yeniden PIN istedi. Yeni yönlendirme için tamamlanmış uçtan uca UI sonucu henüz yoktur. Önceki APK 154 akış ve AL 67 eşzamanlılık sonuçları ayrı raporlardadır; yeni testin yerine sayılmamıştır.
- Fiziksel okuyucu ve yazıcı denenmedi. Canlı ortama girilmedi.
