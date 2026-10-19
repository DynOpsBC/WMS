> tarihsel çalışma notu: bu dosya 21 eylül tarihindeki sürüm ve inceleme durumunu korur. güncel sürüm için [apk 155 / al 68 notlarına](bade-source-repair-and-delivery-1.14.155.md) bakın.

# BADE — Hazır LP ile üretim emrine bağlı ambar çekme

## Durum

Android 1.14.149-bade test adayı oluşturuldu; 1.14.147 ve 1.14.148 adayları son miktar kapsamı düzeltmesini içermez. BC kaynak sürümü 1.14.1.63 olarak hazırlandı. **BC 1.14.1.63 uygulaması ve test uygulaması Windows’ta başarıyla derlendi (CI 35613146337). AL testleri Business Central içinde çalıştırılmadı. Canlıya kurulum veya canlı stok işlemi yapılmadı.** APK tek başına bu düzeltmeyi sağlamaz; yeni sunucu uç noktaları gerekir.

Kapsam, kaynak ve üretim gözünün **aynı BC lokasyon/ambar kodunda** olduğu standart üretim ambar toplamasıdır. Müşteri BADE olarak doğrulandı. Yeni ekran görüntülerinde çekme PI001945, üretim emri RLO.B100919, konum MERKEZDEPO ve hedef üretim gözü D0.01 görülüyor. Bu örnekte farklı ambarlar arası transfer gerekmiyor. Gerçek LP numarası ve canlı kayıt sonucu henüz doğrulanmadı. Farklı lokasyona gerçek stok transferi bu değişiklikle uygulanmaz; LP lokasyonu yalnız metadata değiştirilerek taşınmaz.

## Bulunan nedenler ve değişiklik

- Üretimden çekme oluşturma BC servis hesabını atıyordu. Yeni `createPickFor(userId)` ve `createPickFromLpFor(lpNo,userId)` terminal operatörünü kullanır. Başka operatörün belgesi devralınmaz; istemci kaydedilen sahip ve üretim emrini yeniden okur.
- Açık üretim çekmesi yalnız belge numarasıyla aranıyordu. Kaynak türü, serbest bırakılmış durum ve üretim emri birlikte kontrol edilir; satışla numara çakışması veya karışık kaynak belge kabul edilmez.
- Hazırlanan LP'nin rafını seçme yolu yalnız satışta vardı. Üretimde hazır LP önizleme ve standart BC çekmesi oluştururken kaynak raf tercihi eklendi. BC'nin stok, rezervasyon, ölçü birimi ve takip kontrolleri korunur. Normal yeni çekme sıfır miktarla açılır. Hazır LP seçiminde yalnız o LP’nin miktarları öneri olarak hazırlanır; fiziksel raf ve LP okutma zorunluluğu devam eder.
- Hazır LP ile çekme açılınca boşta olan LP ilgili çekmeye ayrılır; ikinci belge aynı LP'yi seçemez. Çekme iptalinde yalnız o açık belgeye ayrılmış LP serbest kalır; üretime teslim edilmiş LP'nin emir bağlantısı korunur.
- Genel kayıt yolu üretim LP'sini kapanan çekme belgesine bağlı bırakabiliyordu. Üretime özel kayıt, tamamı okutulmuş LP'yi aynı LP numarası ve SSCC ile bileşenin üretim gözüne taşır; LP'yi `ProdConsumption / üretim emri` olarak bağlar. İçerik miktarı, lot/seri, SKT ve orijinal stok kaynağı değişmez. Gerçek ambar hareketini standart BC kayıt işlemi oluşturur; sarfiyat yapılmaz.
- LP planı sunucuda kilit altında yeniden okunur. Her ürün/varyant/lot/seri miktarı LP'nin gerçek içeriğiyle karşılaştırılır. Eksik içerik, fazla miktar, farklı emir/hedef raf, başka belgeye ayrılmış veya henüz tamamlanmamış LP reddedilir. Yeni sevk LP oluşturarak parçalama üretim çekmesinde engellenir.
- Tek standart satır birden fazla LP içeriyorsa yanıltıcı tek LP damgası yazılmaz. Birleşmiş Place satırına son LP'nin bütün miktarı temsil ettiği yanlış bilgi yazılmaz. Her LP'nin hareket/atama geçmişi ayrı tutulur.
- Standart üretim çekmesi oluşturma içindeki açık Commit çağrıları dar kapsamda bastırılır; son doğrulama hatası yarım belge bırakmamalıdır. Kayıtta standart SuppressCommit kullanılır; LP hazırlığı ve gerçek ambar kaydı aynı işlem kapsamındadır.

## Terminal akışı

1. Depoda üretime gönderilecek gerçek miktarı ayrı LP olarak hazırlayıp kapatın.
2. Üretim → ilgili serbest bırakılmış emir → **Hazır LP ile Ambar Çekme**.
3. LP'yi okutun; içerik ile bileşenlerin ambar/üretim gözünü kontrol edip çekmeyi açın.
4. Çekme ekranı seçilen LP’nin **tam miktarıyla** başlar; diğer satırların işlenecek miktarı sıfırdır. Raf ve LP’yi okutarak bütün içerik satırlarını doğrulayın. Emir ihtiyacı 10, LP miktarı 4 ise yalnız 4 hazırlanır, kalan 6 ihtiyaç açık kalır. Bu miktarlar tek başına okutma kanıtı değildir.
5. Toplamayı Kaydet. Kayıt başarılı olduğunda gerçek Take/Place hareketi yapılır ve LP ilgili üretim emrine atanır.

## Doğrulama

- BADE release birim testleri: 445 test, 0 hata/başarısız/atlanan (son kaynak).
- Release lint: 0 hata, 60 uyarı, 19 bilgi. İmzalı APK derlemesi ve v2 imza doğrulaması başarılı.
- Paket: `com.dynops.bcwms.bade`, versionCode `200149`, versionName `1.14.149-bade`.
- APK SHA256: `291d42cfea5305bd6c952322c122d1846637b64455bc6a5485036df3b174d9c8`.
- AL nesne ön ek denetimi ve 9 posting yolunun TransferFields şema denetimi başarılı. Genel izin taramasındaki değişiklik dışı 8 mevcut eşleme hatası devam ediyor; loglar `tmp/production-lp-fix-20260921` altında.
- Üretim kaynak/operatör, LP tercih ve tam palet/geri alma regresyonları ayrı test uygulamasına eklendi: 41 test (72184, 72185, 72186, 72187). **41 üretim AL testi Windows’ta derlendi; BC çalışma zamanında henüz çalıştırılmadı.**

## Windows ve BADE sandbox kabulü

Windows derlemesinde 1.14.1.63 uygulaması ve test uygulaması birlikte doğrulandı: https://github.com/DynOpsBC/WMS/actions/runs/35613146337 . Depo çalışanının gerçek yetkileriyle BADE sandbox'ta aşağıdakiler denenmeli:

- Hazır tek LP ve çok ürünlü LP: aynı LP/SSCC, bütün içerik ve kaynak bağlantıları korunur; gerçek ambar stoğu kaynak gözü düşüp üretim gözü artar; üretim bileşeninin picked miktarı artar; sarfiyat oluşmaz.
- Emir ihtiyacından küçük tam LP, birden fazla palet ve birleşmiş Place satırı doğru kaydedilir.
- Aynı LP'yi iki terminal/üretim emri isteme; aynı emre eşzamanlı çekme oluşturma; başka operatördeki çekmeye erişme kontrollü sonuç verir.
- Kayıt başarısız olduğunda LP konumu/ataması, ambar kayıtları ve üretim picked miktarı birlikte geri alınır. Başarılı kaydı ağ cevabı kaybolunca tekrar gönderme ikinci stok hareketi yaratmaz.
- Yanlış ürün/lot/seri/varyant, değişmiş miktar/raf, eksik palet içeriği, tamamlanmamış LP, farklı ambar ve iç içe LP açık hata verir.
- Mevcut satış/sevkiyat toplaması ve LP bölme akışı regresyona uğramaz.

Bu kontroller ve gerçek kaynak/hedef ambar ayrımı doğrulanmadan saha sorunu kesin çözüldü kabul edilmemelidir.

## Ekran görüntüleri sonrası ek kontrol

- AB.02029 / A.C01.13 açıkken YM.00273 / Y.A01.11 hatası, ilgisiz önceki satırın pencere planlamasını engellemesidir. Bu istemci düzeltmesi 1.14.146'dan beri kaynakta ve sonraki adaylarda var; müşterinin cihazına kurulduğu doğrulanmış değildir.
- Üretimin Al/Yer eşleştirmesi aynı kaynak anahtarı, miktar ve satır sırasıyla yapılır. 1200 ve 6800 çiftleri ayrı tutulur; birleşmiş tek Yer miktarı ilgili Al satırlarından toplanır; tek Al birden fazla Yer'e ayrılmışsa rastgele eş seçilmez, açık hata verilir. Miktar/lot değişmeden önce eş seçilir.
- Önceden belirlenmiş lot kısıtı korunur. Lot boşken açıkça seçilmiş ve ilgili çekmeye ayrılmış LP'nin lotu aday planı için kullanılır; başka lotlu palet sessizce eklenmez.
- Üretim kaydı yeni `registerProductionPalletsFor` servisini gerektirir. Eski `registerScannedFor` varlığı üretim desteği sayılmaz. Eski API üretim kaynak türünü sunmadığından yeni BADE APK tüm çekme kayıtlarında uyumlu BC protokolünü zorunlu tutar; BC güncellemesi olmadan bu APK kurulmaz.

## Hâlâ açık olan saha kabulü ve kullanım sınırları

- Mevcut çekmenin LP hazırlanırken değişen kaynak rafını otomatik yeniden planlama yoktur. Hedef/source LP rafı mevcut çekmeyle uyuşmuyorsa işlem durur; işlenmemiş belge için kontrollü yeniden planlama ayrıca doğrulanmalıdır.
- Hazır LP kapsamı yalnız başlamamış belgede hazırlanır. Önceden LP seçilmiş, miktarı kısmen değiştirilmiş, başka LP ayrılmış veya kayıt yapılmış belgeyi otomatik sıfırlamaz. Aynı çekmeye ayrılmış LP tekrar açıldığında operatörün mevcut miktarları korunur.
- PI001945 gibi önceden bütün satırları varsayılan miktarlarla dolu, başlanmamış belgede seçilen LP kapsamı Al/Yer miktarlarını birlikte hazırlar. Seçim ekranı diğer satırların sıfırlanacağını açıkça belirtir. Multi modu üretimde tek tam LP’nin kısmi emir ihtiyacını karşılamasına izin verir; satış Multi kuralı korunur. Bu yeni BC davranışının çalışma zamanı testi henüz yapılmadı.
- Sarfiyatın LP miktarını düşürmesi ayrı bir akıştır; bu çekme düzeltmesinin içinde çözülmüş kabul edilmez.

Paket artık sandbox’a kurulabilir; gerçek belge kayıt testi tamamlanmadan canlı saha sorunu kesin çözüldü kabul edilmez.

## Son yayın engelleri — 21 Eylül

- BADE salt okunur erişim denemesi yeniden yapıldı: AADSTS50020, mevcut hesap Bade Natural kiracısında yok. Yetkili BADE test oturumu gerekli.
- Son doğrulanmış BC .62 (`211e468170136c61a18890144b2683d59d1a28f5`) üzerindeki 14 dosyalık bağımsız değişiklik `audit/bade-production-lp-20260921` dalında `5f389e9e8aaad9fce6f35dbbeb83f20e51c26459` olarak Windows CI’a gönderildi. CI 35613146337 uygulama ve test uygulamasını başarıyla derledi. İndirilen .app kimlik/sürüm ve SHA256 değerleri doğrulandı.
- Kullanıcı APK ve AL paketinin tamamlanmasını ve sandbox’a kendisinin alacağını istedi. Bunun üzerine yalnız test dalından derleme tamamlandı. Canlıya dağıtım yapılmadı.
- Canlı APK kanalı 1.14.146 olarak bırakıldı; bağlı gerçek saha terminali yok, yalnız Android emülatörü görüldü. 1.14.149 canlıya yayımlanmadı ve hiçbir cihaza kurulmadı.

## Teslim

`releases/BADE-1.14.149-SANDBOX.zip`: imzalı APK, gerçek `BCWMSApp-1.14.1.63.app`, opsiyonel AL test uygulaması, kurulum sırası, kabul senaryosu, derleme logları ve SHA256 listesi. Önce BC .app, ardından aynı sandbox ortamına bağlı APK kurulmalı. AL SHA256: `95c283b2dc6cf4b4a741012a13d9a319d9237cb892b038df36de47e580dff9cf`.

## GitHub yayını — kullanıcı BC kurulumunu bildirdikten sonra

Kullanıcı “githuba at güncellemeyi bc yükledim” talimatını verdi. Android 1.14.149 yayını oluşturuldu: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.149-bade . İndirilen APK’nın SHA256 değeri yerel doğrulanmış APK ile aynı. AL .app, GitHub uzantı kısıtı nedeniyle ZIP içinde sunuldu. BADE kanal manifesti 200149 olarak yüklendi; yayın kanıtı `tmp/bade-149-publication` altında. Önceki sandbox paketi içindeki kurulum/yayın durum notları paket hazırlanma anını anlatır. BC çalışma zamanı testleri tarafımızdan yürütülmedi.

Yayın sonrası terminalin kullandığı sorgu parametresiz sabit manifest adresi yeniden okunarak **200149 / 1.14.149-bade** doğrulandı. İlk okumadaki eski GitHub önbelleği sonraki okumada güncellendi; APK URL ve SHA256 eşleşiyor.
