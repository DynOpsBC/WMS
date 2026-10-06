# BADE 1.14.142 — MTE giriş yapan kullanıcı

## Kurulum sırası

1. BCWMSApp 1.14.1.60 paketini BADE Business Central ortamına yükleyin.
2. Ardından BCWMS-BADE-1.14.142-RELEASE.apk dosyasını mevcut BADE uygulamasının üzerine kurun.
3. Kullanıcıyı PIN ile açın. Tek bir deneme MTE etiketi üzerinden Giriş Yapan alanını kontrol edin.

Yeni APK, 1.14.1.60 ile eklenen kullanıcı bilgili baskı servislerini kullanır.
BC güncellemesinden önce sahadaki APK'yı değiştirmeyin.

## Düzeltme

Mal kabul sonrası etiket, LP listesinden toplu yeniden basım, LP tamamlama ve
stoktan LP oluşturma sırasında PIN ile giriş yapan kullanıcının adı etikete
aktarılır. Manuel Giriş Yapan seçimi korunur. PDF çalışan eşleşmesi yoksa
veya birden fazla ise uygulama açıklama verir; BC bağlantı hesabını yazmaz.

Önceden basılmış etiketler değişmez; gerekiyorsa yeni sürümde yeniden basılır.
