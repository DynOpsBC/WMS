> tarihsel çalışma notu: bu dosya 21 eylül tarihindeki sürüm ve inceleme durumunu korur. güncel sürüm için [apk 155 / al 68 notlarına](bade-source-repair-and-delivery-1.14.155.md) bakın.

# BADE — Bana Ata kimlik düzeltmesi

Terminalde PIN ile Merve giriş yapmışken PI001943 belgesinde DYNOPS ataması ve aynı anda "Bana atandı" mesajı görülüyordu.

## Neden

Sevkiyat > Toplama ekranının Bana Ata düğmesi `picks.assignToMe({})` çağırıyordu. Bu eski AL uç noktası `UserId()` ile BC bağlantı hesabını kullanır. Terminaldeki PIN kullanıcısı farklı olduğunda belge DYNOPS'a atanıyor, istemci yalnız başarılı HTTP yanıtına bakarak başarı gösteriyor ve sonraki sahiplik kontrolü belgeyi salt okunur bırakıyordu.

## Düzeltme — APK 1.14.145

- Düğme mevcut `picks.claim` uç noktasına terminalin kullanıcı kodunu gönderir.
- Başarılı istekten sonra belge sunucudan yeniden okunur. Kaydedilmiş sahip terminal kullanıcısıyla eşleşmedikçe başarı gösterilmez.
- Kullanıcı çözülemezse atama isteği gönderilmez. Eski `assignToMe` ucuna geri dönüş veya otomatik zorla devir yapılmaz.
- Aynı eski geri dönüşü içeren klasik Toplama belgesindeki Bana Ata düğmesi de ortak doğrulanmış yolu kullanır.
- Sahiplik uyarısı, başka kullanıcıya atanmış belge için BC'den devir gerektiğini açıklar.
- BC iş kuralları ve mevcut AL 1.14.1.62 paketi değişmedi. Başka kullanıcıdaki işi otomatik devralma kuralı eklenmedi.

## Mevcut belge

Bu düzeltme DYNOPS'a önceden atanmış PI001943 belgesini kendiliğinden devretmez. Depo sorumlusu BC Toplama Kuyruğu içindeki **Toplayıcı Ata / Değiştir** işleminden Merve'nin gerçek terminal kullanıcı kaydını seçmelidir. Ardından terminalde belge yeniden açılır/yenilenir. Canlı belge bu çalışma sırasında değiştirilmedi.

## Doğrulama ve yayın

Yedi yeni regresyon; PIN kimliği ile atama, kalıcı sahip doğrulaması, DYNOPS sahibiyle gelen sahte başarı, başka sahibin reddi, boş kimlik, okunamayan/bozuk yanıt ve eksik uç noktada eski hesaba geri dönmeme durumlarını kapsar. Toplam 414 Android testi başarılıdır. APK/lint/imza ayrıntıları yayın klasöründeki DOGRULAMA.txt içindedir.

1.14.144'ün LP ve etiket değişiklikleri bu APK'da da bulunur. Bu nedenle BADE runtime/sandbox kontrolleri tamamlanana kadar 1.14.145 de test adayıdır; kararlı otomatik güncelleme kanalı ilerletilmez. Önceki kaynak/etiket incelemesi için [BADE LP kaynak incelemesi](bade-lp-source-2026-09-21.md).
