# BADE — Hazır LP ile üretim emrine bağlı ambar çekme

## Durum

Android 1.14.147-bade test adayı oluşturuldu. BC kaynak sürümü 1.14.1.63 olarak hazırlandı. **BC paketi henüz Windows'ta derlenmedi; AL testleri Business Central içinde çalıştırılmadı. Canlıya kurulum veya canlı stok işlemi yapılmadı.** APK tek başına bu düzeltmeyi sağlamaz; yeni sunucu uç noktaları gerekir.

Kapsam, kaynak ve üretim gözünün **aynı BC lokasyon/ambar kodunda** olduğu standart üretim ambar toplamasıdır. Müşteri BADE olarak doğrulandı. Kaynak/hedef ambar kodları ve örnek üretim emri/LP henüz verilmedi. Farklı lokasyona gerçek stok transferi bu değişiklikle uygulanmaz; LP lokasyonu yalnız metadata değiştirilerek taşınmaz.

## Bulunan nedenler ve değişiklik

- Üretimden çekme oluşturma BC servis hesabını atıyordu. Yeni `createPickFor(userId)` ve `createPickFromLpFor(lpNo,userId)` terminal operatörünü kullanır. Başka operatörün belgesi devralınmaz; istemci kaydedilen sahip ve üretim emrini yeniden okur.
- Açık üretim çekmesi yalnız belge numarasıyla aranıyordu. Kaynak türü, serbest bırakılmış durum ve üretim emri birlikte kontrol edilir; satışla numara çakışması veya karışık kaynak belge kabul edilmez.
- Hazırlanan LP'nin rafını seçme yolu yalnız satışta vardı. Üretimde hazır LP önizleme ve standart BC çekmesi oluştururken kaynak raf tercihi eklendi. BC'nin stok, rezervasyon, ölçü birimi ve takip kontrolleri korunur. Oluşturulan yeni belgenin işlenecek miktarları okutulana kadar sıfırdır.
- Hazır LP ile çekme açılınca boşta olan LP ilgili çekmeye ayrılır; ikinci belge aynı LP'yi seçemez. Çekme iptalinde yalnız o açık belgeye ayrılmış LP serbest kalır; üretime teslim edilmiş LP'nin emir bağlantısı korunur.
- Genel kayıt yolu üretim LP'sini kapanan çekme belgesine bağlı bırakabiliyordu. Üretime özel kayıt, tamamı okutulmuş LP'yi aynı LP numarası ve SSCC ile bileşenin üretim gözüne taşır; LP'yi `ProdConsumption / üretim emri` olarak bağlar. İçerik miktarı, lot/seri, SKT ve orijinal stok kaynağı değişmez. Gerçek ambar hareketini standart BC kayıt işlemi oluşturur; sarfiyat yapılmaz.
- LP planı sunucuda kilit altında yeniden okunur. Her ürün/varyant/lot/seri miktarı LP'nin gerçek içeriğiyle karşılaştırılır. Eksik içerik, fazla miktar, farklı emir/hedef raf, başka belgeye ayrılmış veya henüz tamamlanmamış LP reddedilir. Yeni sevk LP oluşturarak parçalama üretim çekmesinde engellenir.
- Tek standart satır birden fazla LP içeriyorsa yanıltıcı tek LP damgası yazılmaz. Birleşmiş Place satırına son LP'nin bütün miktarı temsil ettiği yanlış bilgi yazılmaz. Her LP'nin hareket/atama geçmişi ayrı tutulur.
- Standart üretim çekmesi oluşturma içindeki açık Commit çağrıları dar kapsamda bastırılır; son doğrulama hatası yarım belge bırakmamalıdır. Kayıtta standart SuppressCommit kullanılır; LP hazırlığı ve gerçek ambar kaydı aynı işlem kapsamındadır.

## Terminal akışı

1. Depoda üretime gönderilecek gerçek miktarı ayrı LP olarak hazırlayıp kapatın.
2. Üretim → ilgili serbest bırakılmış emir → **Hazır LP ile Ambar Çekme**.
3. LP'yi okutun; içerik ile bileşenlerin ambar/üretim gözünü kontrol edip çekmeyi açın.
4. Çekme ekranında taşınacak LP'nin **tam miktarını** girip paletleri doğrulayın. Emir ihtiyacı LP'den büyükse bütün emir miktarını girmek gerekmez; kalan miktar sonraki çekmede karşılanır. Bir LP birden fazla bileşen satırını içeriyorsa tamamı aynı kayıt planında olmalıdır.
5. Toplamayı Kaydet. Kayıt başarılı olduğunda gerçek Take/Place hareketi yapılır ve LP ilgili üretim emrine atanır.

## Doğrulama

- BADE release birim testleri: 438 test, 0 hata/başarısız/atlanan.
- Release lint: 0 hata, 60 uyarı, 19 bilgi. İmzalı APK derlemesi ve v2 imza doğrulaması başarılı.
- Paket: `com.dynops.bcwms.bade`, versionCode `200147`, versionName `1.14.147-bade`.
- APK SHA256: `c1c720dd6566c691c6253d0cafeba584434e7b23eee357509b60d0cc4f4e0c8e`.
- AL nesne ön ek denetimi ve 9 posting yolunun TransferFields şema denetimi başarılı. Genel izin taramasındaki değişiklik dışı 8 mevcut eşleme hatası devam ediyor; loglar `tmp/production-lp-fix-20260921` altında.
- Üretim kaynak/operatör, LP tercih ve tam palet/geri alma regresyonları ayrı test uygulamasına eklendi: 32 test (72184, 72185, 72186). **Yazılan AL testleri derlenmiş veya çalıştırılmış test sonucu değildir.**

## Windows ve BADE sandbox kabulü

Windows derlemesinde 1.14.1.63 uygulaması ve test uygulaması birlikte doğrulanmalı. Depo çalışanının gerçek yetkileriyle BADE sandbox'ta aşağıdakiler denenmeli:

- Hazır tek LP ve çok ürünlü LP: aynı LP/SSCC, bütün içerik ve kaynak bağlantıları korunur; gerçek ambar stoğu kaynak gözü düşüp üretim gözü artar; üretim bileşeninin picked miktarı artar; sarfiyat oluşmaz.
- Emir ihtiyacından küçük tam LP, birden fazla palet ve birleşmiş Place satırı doğru kaydedilir.
- Aynı LP'yi iki terminal/üretim emri isteme; aynı emre eşzamanlı çekme oluşturma; başka operatördeki çekmeye erişme kontrollü sonuç verir.
- Kayıt başarısız olduğunda LP konumu/ataması, ambar kayıtları ve üretim picked miktarı birlikte geri alınır. Başarılı kaydı ağ cevabı kaybolunca tekrar gönderme ikinci stok hareketi yaratmaz.
- Yanlış ürün/lot/seri/varyant, değişmiş miktar/raf, eksik palet içeriği, tamamlanmamış LP, farklı ambar ve iç içe LP açık hata verir.
- Mevcut satış/sevkiyat toplaması ve LP bölme akışı regresyona uğramaz.

Bu kontroller ve gerçek kaynak/hedef ambar ayrımı doğrulanmadan saha sorunu kesin çözüldü kabul edilmemelidir.
