# BADE 1.14.115 — Toplamada raf doğrulaması ve palet listesi düzeltmesi

Android sürümü: **1.14.115-bade**, versionCode **200115**. BC paketi: **BCWMSApp 1.14.1.37** (MTE raporu; ayrıntı aşağıda). 1.14.114'teki okuyucu girişi düzeltmeleri bu pakette de bulunur.

## Sahadan gelen bulgu

15 Eylül'de terminalde palet listesi (LP000013 ve LP000012) ekrandayken okutulan LP000013 için
"kaynak paletler doğrulanamadığı için onaylanmadı" mesajı görüldü ve 0/2 adımda kalındı.

Nedeni: miktar alanı değişince önceki palet listesi yüklemesi iptal ediliyor, ancak iptal edilen
yükleme kapanırken okutma alanını erken açıyordu. Yeni liste gelmeden okutulan LP boş listeye karşı
değerlendiriliyor, liste geldikten sonra da eski mesaj ekranda kalıyordu. Palet okutma mantığı
ayrıca ekrandaki liste yerine eski bir kopyaya bakabiliyordu.

## Düzeltmeler

- Palet listesi yüklenirken iptal edilen eski yükleme okutma alanını artık açmıyor. LP her zaman
  okutma anındaki güncel listeyle karşılaştırılır.
- Liste yüklenirken okutulan LP sessizce düşmez: "Palet listesi henüz yükleniyor, liste gelince
  tekrar okutun" uyarısı verilir.
- Liste alınamadığında mesaj artık BC hatasına yönlendirir: "LP okutuldu ama palet listesi hazır
  değil. Yukarıdaki BC hatasını giderip listeyi yenileyin."

## Yeni akış: önce raf, sonra palet

Palet penceresi iki adımlıdır ve sıra atlanamaz:

1. **1. Kaynak rafı okut** — satırın rafı büyük puntoyla gösterilir. Fiziksel raf etiketi
   okutulmadan LP kabul edilmez. Yanlış raf ("Yanlış raf: A.E08.11. Bu toplama için önce A.TOPLAM
   rafını okutun.") ve erken okutulan palet ("LP000013 bir palet etiketi. Önce ... rafının
   etiketini okutun") açık uyarıyla reddedilir.
2. **2. Paletin QR kodunu okut** — raf doğrulanınca "SIRADAKİ PALET" kartı açılır ve paletler
   sırayla okutulur. Doğrulanan raf miktar değişse, liste yenilense veya BC onayı reddedilse de
   geçerli kalır; yalnız pencere kapanınca sıfırlanır.

Raf etiketindeki düz raf kodu (`A.TOPLAM`) ve `B-` önekli raf barkodları kabul edilir.
"Okutulan Paletleri Onayla" düğmesi raf doğrulanmadan ve tüm paletler okutulmadan açılmaz.
Miktar sıfırlama akışı (girilen miktarı sıfırla) raf okutma gerektirmez.

## BC paketi 1.14.1.37 — MTE (Madde Tanımlama Etiketi)

- Yeni rapor **72375 "DOPSWHS MTE LP Report"**: onaylı 10×8 cm RDLC düzeni (`MaddeTanimlamaLP.rdlc`,
  BC'den indirilen dosyayla birebir aynı). Her LP ayrı sayfadır; madde, lot, miktar ve QR
  (QR içeriği = LP numarası) o LP'nin güncel kayıtlarından doldurulur.
- Terminaldeki **MTE Yazdır** (`licensePlates/printPalletLabels`) artık ZPL yerine bu PDF raporu
  üretir ve **Belge** olarak seçilmiş Windows yazıcı rotasına gönderir. Etiket yazıcısının Windows
  sürücüsünün "Belge" yazıcısı olarak eşlenmiş olması gerekir.
- Madde Defteri Girişleri sayfasına **Tüm LP MTE Etiketleri** işlemi eklendi: seçili girişlere bağlı
  bütün LP'ler tek raporda, LP başına bir sayfa. Eski çağrının yalnız ilk LP'yi göndermesi sorunu
  bununla giderildi.
- Eski `BuildPalletItemZpl` işlemi uyumluluk için korunur (Obsolete işaretli).
- Paket aynı uygulama kimliğiyle 1.14.1.36 üzerine yükseltme olarak kurulur; veri şeması değişmedi.

## Doğrulama

- alc derlemesi 0 hata (350 dosya). Paket içindeki RDLC, kaynak dosya ve BC'den indirilen
  `MaddeTanimlamaLP.rdl` bayt bayt aynı; paket kimliği ve sürüm (1.14.1.37) doğrulandı.
- BADE ve EMU için ayrı ayrı **346 JVM testi**, 0 hata/atlanan (raf eşleşmesi, `B-` öneki ve erken LP uyarısı testleri dahil).
- Emülatörde **31 pencere/okuyucu testi** başarılı; palet penceresi testi yeni sıraya göre güncellendi
  (erken LP reddi → yanlış raf reddi → raf doğrulama → listesiz LP uyarısı, onay düğmesi kapalı).
- BADE lint 0 hata, 77 uyarı. İmzalı APK: `com.dynops.bcwms.bade`, 200115 / 1.14.115-bade, sertifika 1.14.114 ile aynı.
- Emülatörde 1.14.114 üzerine veri silmeden 1.14.115 kurulumu ve açılış başarılı.

Gerçek saha okuyucusu, fiziksel yazıcı ve BC ortamında MTE PDF çıktısı uçtan uca test edilmedi.
BC paketinin E-DefterSandbox'a yüklenmesi ayrı bir adımdır.
