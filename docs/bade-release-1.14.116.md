# BADE 1.14.116 — Terminalden MTE yazdırma geri geldi (BC 1.14.1.38)

Android sürümü: **1.14.116-bade**, versionCode **200116**. BC paketi: **BCWMSApp 1.14.1.38**.
1.14.115'teki toplama düzeltmeleri (önce raf, sonra palet; palet listesi hatası) bu pakette de bulunur.

## Sahadan gelen bulgu (15 Eylül, 17:39)

Terminalde LP kartından **MTE Yazdır** "HATA: Yazıcı ayarı tamamlanamadı" verdi (REF-CE366887).
Yazıcılar ekranında yalnız ZPL etiket yazıcısı (Zebra ZQ630) aktifti; ZPL yazıcı "Belge" olarak
seçilemiyordu, Windows yazıcı ajanında da Belge yazıcısı tanımlı değildi.

## Neden

Dünkü 1.14.1.37 + 1.14.115 paketi terminaldeki MTE'yi ZPL etiketten, BC'deki onaylı 10×8 cm RDLC
raporunun **PDF** çıktısına çevirmişti. PDF yalnız Belge yazıcısına gidebilir; sahada Belge yazıcısı
yok ve Zebra'daki rulo 4×2 inç (10×5 cm) olduğu için 10×8 cm PDF o yazıcıya zaten sığmazdı. Yani
kurulum hatası değil, yazılımın sahayla uyumsuz bir varsayımıydı.

## Düzeltme

- **BC 1.14.1.38** — MTE'nin formatını yazıcı belirler: seçili yazıcı ZPL ise 1.14.1.36'daki ZPL
  MTE (ürün grubu başına bir etiket) basılır; PDF belge yazıcısıysa onaylı RDLC raporu (LP başına
  sayfa) basılır. Yazıcı verilmezse önce cihazın etiket eşlemesi, sonra belge eşlemesi denenir.
  Belge yazıcısı olmaması artık hata üretmez.
- **Android 1.14.116** — MTE isteği (LP kartı "MTE Yazdır", LP tamamlama, toplu LP, mal kabul
  sonrası MTE ekranı, sayım sonrası etiketler, mal kabul kaydı) cihazın **Etiket** yazıcısını
  gönderir; etiket yazıcısı seçili değilse Belge yazıcısı, o da yoksa BC eşlemesi kullanılır.
  1.14.115 bu isteklerde yalnız Belge yazıcısını gönderiyordu.
- Yazıcı hataları operatöre açık yazılır: "belge yazıcısı seçilmemiş" ve "seçili yazıcı ZPL etiket
  yazıcısı, bu çıktı PDF gerektirir" mesajları eklendi; genel "Yazıcı ayarı tamamlanamadı" bu iki
  durumda artık görünmez.

Kurulum değişikliği gerekmez: Zebra ZQ630 "Etiket" olarak seçili kalır, MTE oradan çıkar.
Onaylı 10×8 düzenin terminalden basılması istenirse ileride ayrı adım: yazıcıya 10×8 cm rulo,
ajanda ikinci bir Windows kuyruğu "Belge" yazıcısı olarak, terminalde etiket seçimi kaldırılıp
o kuyruk Belge seçilir.

## Doğrulama

- alc derlemesi 0 hata. Paket 1.14.1.37 üzerine yükseltme; tablo değişikliği yok. Paket içinde
  ZPL geri dönüşü (`PrintPalletItemZplLabels`) ve MTE raporu 72375 birlikte doğrulandı.
- BADE ve EMU için ayrı ayrı **346 JVM testi**, 0 hata (MTE yazıcı seçimi ve yeni hata mesajı
  testleri dahil).
- Emülatörde **31 pencere/okuyucu testi** başarılı.
- BADE lint 0 hata, 77 uyarı. İmzalı APK: `com.dynops.bcwms.bade`, 200116 / 1.14.116-bade,
  sertifika önceki sürümlerle aynı. Emülatörde eski sürüm üzerine veri silmeden kurulum ve açılış
  başarılı.

Fiziksel yazıcıda ve BC ortamında uçtan uca test yapılmadı; BC paketinin E-DefterSandbox'a
yüklenmesi ayrı adımdır. Terminal güncellemesi tek başına yeterli değildir: BC 1.14.1.38
yüklenmeden 1.14.116'nın gönderdiği ZPL yazıcı BC'de yine PDF yolu hatası verir.
