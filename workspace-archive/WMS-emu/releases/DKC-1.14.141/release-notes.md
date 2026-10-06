DKÇ / EMU 1.14.141 — Yazıcı seçimi ve yazıcı ad etiketi

Kurulum sırası:
1. BCWMSApp-EMU-1.14.2.11.zip içindeki .app dosyasını DKÇ BC ortamına yükleyin.
2. DKÇ Print Agent 1.1.3 ZIP'ini tamamen açın; aynı Windows kullanıcısıyla installer/install.cmd çalıştırın. Mevcut bağlantı ayarları korunur; bu genel paket secret içermez.
3. EMU APK 1.14.141'i mevcut uygulamanın üzerine kurun. RELEASE standart imza; UYUMLU eski saha imzası içindir. Uygulamayı silmeyin.

Agent'ta ilgili yazıcıların Görünen ad alanına Yazıcı 1, Yazıcı 2 gibi isimler girin. Ayarları Kaydet ve Bağlan, ardından Buluta Eşitle yapın.
Terminalde Yazıcılar → Yenile. Yazıcı kartına dokunup hedefi seçin. Etiket ve belge seçimleri cihazda ayrı saklanır; Seçimi kaldır ile temizlenebilir. Bu DKÇ sürümünde seçim BC terminal kartına yazılmaz.

Yazıcı ad etiketi çıkar: Adı basılacak ZPL yazıcının kartındaki düğmeye basın. Etiket aynı yazıcının kendisine gönderilir ve BC'deki eşitlenmiş görünen adı kullanır. Seçili etiket yazıcısının özetinde de düğme vardır. Etiket 203 dpi'de yaklaşık 50 × 30 mm'dir, tek kopya basılır. Fiziksel yazıcı üzerinde ölçü/Türkçe karakter kontrolü yapılmalıdır.

Görünen adların kaydetme/yenilemede silinmesi düzeltildi. Güncelleme denetiminde eski GitHub önbelleğini atlamak için her sorguya farklı parametre eklendi.

Doğrulama: 360 Android testi, 54 Agent testi, Android lint, iki APK imzası, Agent paket manifesti ve Windows BC derlemesi başarılı. Fiziksel terminal/yazıcı ve canlı BC üzerinde uçtan uca çalışma testi yapılmadı.

Tek tık Agent güncellemesi: DKC-Print-Agent-1.1.3-Tek-Tik.zip dosyasını tamamen çıkarıp kökteki KUR.cmd dosyasını çalıştırın. Aynı Windows kullanıcısındaki mevcut bağlantı/yazıcı ayarları korunur. Yeni PC kurulumu için DKÇ bağlantı dosyanız gerekir; GitHub paketinde secret bulunmaz.
