# DKÇ: Agent yazıcı adları ve terminal hedefleri

DKÇ / EMU — 1.14.132

İçerik
- BCWMSApp EMU 1.14.2.10
- Windows Print Agent 1.1.1 (bir PC'de birden fazla etiket yazıcısı, görünen adlar)
- Terminal 1.14.132-emu (standart ve eski imzalı cihazlara uyumlu APK)

Kurulum
1. BC Uzantı Yönetimi'nden BCWMSApp-EMU-1.14.2.10.app dosyasını DKÇ ortamına yükleyin.
2. Agent ZIP'ini tamamen açın. installer/install.cmd dosyasını çalıştırın.
   Mevcut aynı Windows kullanıcı hesabıyla kurun; kayıtlı bağlantı ve yazıcı ayarları korunur.
   Yeni bilgisayarda DKÇ'ye ait Agent bağlantı dosyasını Azure Ayarları'ndan içe aktarın.
3. Windows'ta 2–3 yazıcının sürücüsünü kurun; her yazıcı ayrı Windows kuyruğu olarak görünmeli.
   Agent → Yazıcılar → Etiket yazıcıları listesinden kullanılacak tüm yazıcıları işaretleyin.
   Etiket formatı ZPL. Her yazıcıya Görünen ad alanında ayrı isim verin:
   Mal Kabul / Sevkiyat / Depo gibi. Ayarları Kaydet ve Bağlan → Buluta Eşitle.
4. Terminal APK'sını mevcut uygulamanın üzerine kurun.
   RELEASE standart imzalı cihazlar, UYUMLU eski saha imzalı cihazlar içindir.
   İmza uyuşmazlığında uygulamayı silmeyin; diğer uygun APK'yı kullanın.
5. Her terminalde Yazıcılar → Değiştir ile o terminalin etiket yazıcısını seçin.
   Yazdırma hedefleri kartından da seçim yapılabilir. Belge yazıcısı ayrı seçilir.
   Terminal 1 → Mal Kabul, Terminal 2 → Sevkiyat, Terminal 3 → Depo.
   Aynı PC için ayrı Agent/istasyon kurmak gerekmez.
6. Önce Agent'ten yerel etiket testi, ardından her terminalden bir test etiketi basın.
   Her çıktının seçilen fiziksel yazıcıdan geldiğini kontrol edin.

İsim değişikliği Windows kuyruk adını, Printer ID'yi veya terminal seçimini değiştirmez.
BC eşitlemesinden sonra terminalde Yenile ile yeni isim alınır; üst çubuk dakikada bir yenilenir.
Boş görünen ad Windows yazıcı adına döner. Görünen ad en fazla 100 karakterdir.

Doğrulama
Agent Core: 50 test geçti; Windows x64 bağımsız kurulum paketi üretildi.
BC: derlendi, 0 hata (mevcut uyarılar var).
Terminal: 360 test geçti; lint 0 hata, 79 mevcut uyarı. Standart ve eski imza için release derlemeleri doğrulandı.
Bu bilgisayarda bağlı fiziksel terminal veya Windows yazıcısı bulunmadığından gerçek baskı denenmedi.
Paketler hazırlandı; canlı BC kurulumu ve terminal güncelleme kanalları değiştirilmedi.

## Secret dahil tek tık paket

`output/DKC-1.14.132-Tek-Tik.zip` yerel, DKÇ WMS02 bağlantısı dahil müşteri paketidir.
Kök `KUR.cmd` doğrulanmış Agent kurulumunu çalıştırır, secret dosyasını kurulu EXE'nin
yanına kopyalar, ardından Agent'i açar. Secret, genel Agent manifestinin dışında kalır;
output dizini git tarafından yok sayılır. Yeni ayarların DEFAULT istasyonunu mevcut
kurulum sanan otomatik içe aktarma kontrolü düzeltildi. İlk kurulumda alanlar otomatik
dolar; yazıcı seçimi sonrası Kaydet ve Bağlan gerekir. Başka mevcut istasyon değiştirilmez.

50 Agent testi ve Windows çapraz derlemesi geçti. Kurulum sırası, birebir secret
kopyası ve başlatma sırası PowerShell'de sahte installer/process ile doğrulandı.
ZIP CRC ve iç Agent manifesti doğrulandı; gerçek Windows çalıştırması yapılmadı.
