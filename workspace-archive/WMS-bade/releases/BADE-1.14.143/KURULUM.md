> CANLIYA ALMAYIN — 1.14.143 / BC 1.14.1.61 güvenlik incelemesinde durduruldu.
> Otomatik eski-kaynak eşleştirmesi ve eski/üretim LP baskı engeli bulundu.
> Yerine hazırlanan 1.14.144 / BC 1.14.1.62 için sandbox doğrulaması gerekir.

# BADE 1.14.143 — kaynak stok girişi ve etiket düzeltmesi

1. Önce BCWMSApp 1.14.1.61 paketini BADE Business Central ortamına yükleyin.
2. Sonra BCWMS-BADE-1.14.143-RELEASE.apk dosyasını mevcut BADE uygulamasının üzerine kurun. Uygulamayı kaldırmayın.
3. PIN ile giriş yapın.

## Mevcut LP000400 için

LP kartında 850 adetlik satırı bulun. **Kaynak Girişi Bağla** düğmesinden gerçek kaynak belgesini/madde defteri girişini seçin. Ürün AB.01743, lot A101119 ve lokasyonun aynı olduğunu kontrol edin. Fotoğraftaki 850 adet kalan girişin gerçek giriş numarası canlı kayıt üzerinden doğrulanmalıdır; numarayı tahmin ederek seçmeyin.

Alternatif: Madde Defter Girişlerinde ilgili pozitif giriş seçiliyken **LP Bilgisini Yenile**. Yalnız tek uygun ve yeterli kaynak varsa eksik satır otomatik bağlanır; belirsizse LP kartından seçim gerekir.

Bağlantı işlemi yeni stok veya miktar oluşturmaz. Kaynak belge/giriş LP satırına yazılır, madde defteri girişinde LP bilgisi görünür. Ardından MTE etiketini yeniden basın ve depo giriş numarası/tarihini doğrulayın. Önceden basılmış etiketler kendiliğinden değişmez.

## Yeni LP satırları

Satır Ekle sırasında kaynak giriş belgesi seçilir. Birden fazla girişten ürün alınacaksa ayrı satırlar ekleyin. Kaynak miktarı temel birimde kontrol edilir. Kaynaksız eski satır varsa MTE basımı bağlantının tamamlanmasını ister.

Önceki sürümdeki Giriş Yapan / PIN kullanıcı adı düzeltmesi bu pakette korunur.

## Durum

Bu dosyalar kurulum paketidir. Canlı BC ve APK güncelleme kanalı bu çalışma sırasında değiştirilmedi. BC sandbox test yürütümü ve fiziksel etiket doğrulaması henüz yapılmadı.
