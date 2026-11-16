# BADE Android 1.14.209 — Sand1311 test paketi

- Ürün Sorgu'da LP ve konum listesi stok kartının hemen altında. Uzun ürün bilgileri ve etiket seçimi açılır detaylara taşındı.
- Konum sorgusu ilk 25 LP ile sınırlı değil; tüm LP'ler 25'lik sorgu gruplarıyla yüklenir. Başlık sorgusu başarısızsa konum uydurulmaz.
- Ana menü şirket değiştiricisi ve bağlantı ayarları, kurulmuş BADE cihazında BC yönetici PIN doğrulaması ister. Microsoft oturumunun yenilenmesi bu kontrolü kaldırmaz.
- Doğrulama mevcut operatörü yöneticiye dönüştürmez. Şirket değişmeden önce eski operatör oturumu temizlenir, hedef şirkette terminal girişi gerekir.
- İlk cihaz kurulumu serbesttir. Başka şirketin terminali henüz seçilmemiş olması cihazın yeniden ilk kurulum sayılmasına yol açmaz.
- Kurulmuş BADE cihazında farklı Microsoft tenant token'ı, onay alınacak tenant'ı değiştiremez; özgün tenant'taki yönetici doğrulaması gerekir.

Kontrol: 543 birim testi, 0 hata/başarısız/atlanan; 3 emülatör testi (taze PIN, yönetici olmayan yanıtın reddi, iptal) geçti. Emülatör testleri sahte sunucu yanıtıyla UI kontrolüdür; gerçek müşteri yönetici PIN'iyle uçtan uca doğrulama yapılmadı. Bağımsız incelemede bulunan atlama yolları düzeltildi; tenant koruması ayrıca birim testine eklendi.

Sand1311 salt okunur API kontrolünde AB.00222 için LP002295, 474 ADET doğrulandı. LP başlığından konumun son sunucu kontrolü ağ hatasıyla tamamlanamadı. İlk 25 LP dışındaki konumlar ve başarısız başlık yanıtı birim testinde doğrulandı.

APK: com.dynops.bcwms.bade, versionCode 200209. Derleme parametreleri: `-PreleaseVersionCode=200209 -PreleaseVersionName=1.14.209`. BC paketi değişmedi. İlk hazırlıkta genel BADE güncelleme kanalı ilerletilmedi; 16.11.2026 yayın durumu aşağıdadır.

## 16.11.2026 — BADE kanal yayını

Kullanıcı talimatıyla `android-v1.14.209-bade` yayını oluşturuldu ve `android-bade-channel/latest.json` 200207 → 200209 olarak güncellendi. APK indirilip SHA-256 eşitliği ve kanal manifesti yeniden okunarak doğrulandı. Diğer müşteri kanalları değiştirilmedi.

- Kaynak: `fb06cc53f85c4fa673fb0ae215752ba43cea997f`.
- Yayın: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.209-bade
- APK SHA-256: `1c7e786c039fdbf00884a8b62f38b25b78e0dfc2c6f1be5f5f6cc6e8f2a678b8`.
- Güncel kontrol: 543 birim testi geçti; BADE release derlemesi başarılı, imza sabit saha sertifikasıyla eşleşiyor.
- Erişim engeli: GitHub deposu PRIVATE; uygulamanın kimlik doğrulamasız kullandığı kanal adresi HTTP 404 dönüyor. GitHub oturumuyla yayın/kanal doğrulandı, fakat terminalin uygulama içi güncellemeyi indirebildiği doğrulanmadı ve mevcut erişimle beklenmez. Kaynak depo görünürlüğü değiştirilmedi; erişilebilir dağıtım ayrıca çözülmelidir.
- Fiziksel terminal ve gerçek BC yönetici PIN’iyle uçtan uca test bu yayında yapılmadı.
