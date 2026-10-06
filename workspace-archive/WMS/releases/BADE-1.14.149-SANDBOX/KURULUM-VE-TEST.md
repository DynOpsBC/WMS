# BADE — Üretim LP sandbox paketi

APK: **1.14.149-bade** (`200149`, `com.dynops.bcwms.bade`).
BC uygulaması: **1.14.1.63**.

## Kurulum sırası

1. BC **Sandbox** ortamında Uzantı Yönetimi’nden `BCWMSApp-1.14.1.63.app` dosyasını yükleyin. Yüklü sürümün 1.14.1.63 olduğunu kontrol edin.
2. Test terminaline `BCWMS-BADE-1.14.149.apk` dosyasını güncelleme olarak kurun. Yayımdaki 1.14.146 ile aynı imza sertifikası kullanılır.
3. Terminalin ortam/şirket seçiminde AL paketini kurduğunuz **aynı BADE Sandbox** ortamını seçin. APK varsayılanı `E-DefterSandbox` olsa da mevcut kurulumdaki Production seçimi korunabilir; girişte ortam adını kontrol edin.
4. Yalnız test verisiyle aşağıdaki senaryoyu çalıştırın. Eski BC sürümünde yeni APK çekme kaydını reddeder; önce BC kurulmalıdır.

## İlk kabul testi

- Depoda kapatılmış, gerçek stok ve raf bilgileri doğru bir LP hazırlayın. Üretim emri serbest bırakılmış olsun. Kaynak ve üretim gözü aynı BC lokasyonunda olmalıdır.
- Üretim → ilgili emir → **Hazır LP ile Ambar Çekme**. LP’yi okutun; içerik ve hedefi kontrol edip açın.
- Emir ihtiyacı örneğin 10, LP içeriği 4 ise işlenecek miktar 4 olmalı; diğer ürün satırları sıfır kalmalı. LP’de birden fazla ürün varsa tamamını doğrulayın.
- Kaynak rafı ve LP etiketini okutun; **Toplamayı Kaydet**.
- Standart ambar hareketinde kaynak gözden 4 çıkıp üretim gözüne 4 girdiğini, bileşenin picked miktarının arttığını kontrol edin. Sarfiyat oluşmamalıdır.
- LP numarası/SSCC/içerik/lot korunmalı; LP yeni üretim gözünde ve ilgili üretim emrine bağlı olmalıdır. Kalan 6 birim üretim ihtiyacı açık kalmalıdır.

PI001945 örneğinin sandbox karşılığında lokasyon `MERKEZDEPO`, üretim gözü `D0.01`, üretim emri `RLO.B100919` bağlantısı beklenir. Aynı bileşenin 1200/6800 Al/Yer çiftlerini ayrı ayrı kontrol edin.

## Kontrol edilmesi gereken durumlar

- AB.02029 / A.C01.13 satırı açıldığında ilgisiz YM.00273 / Y.A01.11 eksik LP hatası çıkmamalı.
- Yanlış LP/lot/raf, başka operatör veya başka belgeye ayrılmış LP kabul edilmemeli.
- Hazır LP kapsamı, başlanmış/kısmen miktarı değiştirilmiş/LP okutulmuş bir çekmeyi sıfırlamaz. Böyle bir belge varsa mevcut toplamayı tamamlayın veya sahibi olarak yalnız kaydedilmemiş çekmeyi kontrollü iptal edip Hazır LP ile tekrar oluşturun.
- LP hazırlanınca raf değiştiyse eski çekmenin rafı sessizce değiştirilmez. Kaydı olmayan eski çekmeyi kontrollü iptal edip gerçek LP rafından yeniden oluşturun.
- Kayıt hatasında LP rafı/ataması ve ambar stok hareketi birlikte geri alınmalı. Başarılı kaydın tekrar gönderilmesi ikinci stok hareketi oluşturmamalı.
- Satış/sevkiyat çekmesini de test edin. Üretim LP’sini kısmi bölme ve farklı lokasyonlar arası aktarım bu paketin akışı değildir.
- BC çekmesinde lot önceden belirlenmişse LP’nin lotu aynı olmalıdır. Lot boşsa seçilen LP’den doğrulanır; bir standart satıra farklı lot/seriler birleştirilemez.

## Doğrulamanın sınırı

Android: 445 birim testi geçti; lint 0 hata, 60 uyarı, 19 bilgi; imzalı release derlendi. BC uygulaması ve test uygulamasının Windows derleme sonucu `DOGRULAMA.txt` içinde bulunur. 41 üretim AL testi kodda vardır; BC çalışma zamanı testleri burada çalıştırılmamıştır. Test uygulaması isteğe bağlıdır ve yalnız Sandbox içindir.

Bu paket sandbox kabulü içindir. Canlı stok üzerinde test yapılmadı ve canlı APK güncelleme kanalı değiştirilmedi. Sarfiyatın LP içeriğini azaltması ayrı bir süreçtir.
