# BADE — Yeni tur düğmesinde arşiv hatası

BC kaynak sürümü: **1.14.1.127**. Kaynak düzeltmesi hazır; paket derlenmedi veya yayınlanmadı.

## Bildirilen durum

Merve Hanım ilk turu saydıktan sonra BC kartındaki **Ad-hoc Sonrası Yeni Tur Başlat** eylemine basınca arşivlenmiş tur mesajı alıyor. Kullanıcı, hatanın terminalde okutma sırasında değil BC düğmesinde çıktığını doğruladı. Hatanın tam metni ve BC oturum kaydı alınmadığı için canlı ortamda kesin kök neden henüz doğrulanmış değildir.

## Değişiklik

- Başlık `OnModify` kontrolü `xRec` yerine kilit altında yeniden okunan kayıtlı durumu denetler. İlk arşivleme geçişi serbesttir; zaten arşivlenmiş veya stoklara işlenmiş belgenin değiştirilmesi engellenir.
- Yeni tur oluşturma sonrasında yalnız `Rec.Get` ile eski kartın kaydı değiştirilmez. Hedef tur için ayrı kart örneği açılır, eski kart kapatılır. Böylece eski belgeye ait sayfa filtreleri taşınmaz; ekranda aynı kök sayım numarası ve yeni tur gösterilir.
- **Sonraki Tura Geç**, **Aktif Sayım Turunu Aç** olarak adlandırıldı. Yalnız devam turu bulunan eski belgede görünür ve mevcut son tura gider; yeni kayıt oluşturmaz.
- **Ad-hoc Sonrası Yeni Tur Başlat** eski belgelerde gizlenir. Etkin V2 belgesinde kullanılabilir. Tamamlanmamış sayımlar için mevcut sunucu doğrulamaları sürer.
- Kart üstünde mevcut turun durumuna göre kullanım açıklaması, eylemlerde açıklayıcı ipuçları bulunur.

`Record.Get` mevcut filtreleri değiştirmez: [Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/methods-auto/record/record-get-method). Yeni kartın hedef kaydı `Page.SetRecord` ile belirlenir: [Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/methods-auto/page/page-setrecord-method).

## Kullanım açıklaması

1. İlk sayımı terminalde bitirip **Sayım Turunu Kaydet** ile kaydedin; atanmış bütün sayıcılar kaydetmiş olmalı.
2. Gerekli Ad-hoc raf/stok düzeltmelerini tamamlayın.
3. BC'de **Ad-hoc Sonrası Yeni Tur Başlat** ile güncel stoklardan ikinci turu oluşturun. İlk sonuçlar korunur, yeni tur açılır.
4. Daha sonra eski turu açarsanız **Aktif Sayım Turunu Aç** ile zaten oluşturulmuş son tura dönün. Bu düğme yeni bir sayım başlatmaz.
5. Terminalde tur desteği için **1.14.171-bade** gerekir; listedeki aynı kök sayımı açarak tekrar sayın. Stok düzeltmesini yalnız son turdan yapın.

Mevcut sistemde arşiv hatası alınmış olması, yeni turun başarıyla oluştuğunu tek başına kanıtlamaz. Belgenin sonraki tur bağlantısı kontrol edilmeden yeni tur oluştuğu söylenmemelidir.

## Doğrulama

- Değişen AL başlık/kart ve test dosyası: Microsoft AL ayrıştırıcısında **0 söz dizimi hatası**.
- Eklenen iki TestPage senaryosu: eski numarayla filtreli karttan yeni tur oluşturup açma; arşiv kartından yeni belge yaratmadan etkin turu açma.
- **Bu iki test BC üzerinde henüz çalıştırılmadı.** Windows AL derlemesi ve BC doğrulaması gerekli.
- Android kodu veya APK değiştirilmedi; önceki 477 birim ve 2 Android arayüz testinin sonucu bu BC düzeltmesinin çalışma zamanı doğrulaması değildir.
- Günlük: `build/bade-count-round-navigation-20261007/al-syntax.log`.
