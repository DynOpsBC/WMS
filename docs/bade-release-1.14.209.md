# BADE Android 1.14.209 — Sand1311 test paketi

- Ürün Sorgu'da LP ve konum listesi stok kartının hemen altında. Uzun ürün bilgileri ve etiket seçimi açılır detaylara taşındı.
- Konum sorgusu ilk 25 LP ile sınırlı değil; tüm LP'ler 25'lik sorgu gruplarıyla yüklenir. Başlık sorgusu başarısızsa konum uydurulmaz.
- Ana menü şirket değiştiricisi ve bağlantı ayarları, kurulmuş BADE cihazında BC yönetici PIN doğrulaması ister. Microsoft oturumunun yenilenmesi bu kontrolü kaldırmaz.
- Doğrulama mevcut operatörü yöneticiye dönüştürmez. Şirket değişmeden önce eski operatör oturumu temizlenir, hedef şirkette terminal girişi gerekir.
- İlk cihaz kurulumu serbesttir. Başka şirketin terminali henüz seçilmemiş olması cihazın yeniden ilk kurulum sayılmasına yol açmaz.
- Kurulmuş BADE cihazında farklı Microsoft tenant token'ı, onay alınacak tenant'ı değiştiremez; özgün tenant'taki yönetici doğrulaması gerekir.

Kontrol: 543 birim testi, 0 hata/başarısız/atlanan; 3 emülatör testi (taze PIN, yönetici olmayan yanıtın reddi, iptal) geçti. Emülatör testleri sahte sunucu yanıtıyla UI kontrolüdür; gerçek müşteri yönetici PIN'iyle uçtan uca doğrulama yapılmadı. Bağımsız incelemede bulunan atlama yolları düzeltildi; tenant koruması ayrıca birim testine eklendi.

Sand1311 salt okunur API kontrolünde AB.00222 için LP002295, 474 ADET doğrulandı. LP başlığından konumun son sunucu kontrolü ağ hatasıyla tamamlanamadı. İlk 25 LP dışındaki konumlar ve başarısız başlık yanıtı birim testinde doğrulandı.

APK: com.dynops.bcwms.bade, versionCode 200209. Derleme parametreleri: `-PreleaseVersionCode=200209 -PreleaseVersionName=1.14.209`. BC paketi değişmedi. Genel BADE güncelleme kanalı bu test paketiyle ilerletilmedi.
