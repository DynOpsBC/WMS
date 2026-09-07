# Müşteri öncesi hata kontrolü — 1.14.103

Bu çalışma Android uygulamasını, ortak BC istek katmanını, son sayım/LP değişikliklerini ve web/servis testlerini kapsar. Sıfır hata garantisi veya canlı ortam kabulü değildir. Android 1.14.103 ve BC kaynak sürümü 1.14.1.31 birlikte değerlendirilmelidir.

## Bulunan ve düzeltilen sorunlar

| Sorun | Değişiklik | Doğrulama |
| --- | --- | --- |
| Bekleyen okutma, ekranda son seçilen sayıcıyla tekrar gönderilebiliyordu | İstek kimliği, raf, miktar ve sayıcı birlikte yakalanır ve cihazda saklanır; sonuç belirsizken diğer sayım işlemleri kilitlenir | İsteğin saklanıp geri yüklenmesi ve bozuk kayıt testleri |
| Uygulama kapanınca belirsiz okutmanın işlem kimliği kaybolabiliyordu | Göndermeden önce kalıcı kayıt; yeniden açılışta aynı kimlikle kontrol; kesin sonuçta temizleme | İstek verisi geri yükleme testi; BC idempotency test kaynakları |
| Sunucunun reddettiği etiket cihazda hâlâ okutulmuş sayılabiliyordu | Kesin hata yanıtında etiket tekrar okutulabilir; belirsiz yanıtta yeni işlem başlatılmaz | Sayım hata akışının kod incelemesi |
| Geri alma, beklenen sayım satırını ve son satırsa raf kapsamını silebiliyordu | Satır korunur, yalnız ilgili sayıcının sayıldı bayrağı temizlenir | AL regresyon testi eklendi; Windows çalıştırması bekliyor |
| Eski okutma kimliği farklı sayıcı/miktarla veya yeniden sayım başladıktan sonra kabul edilebiliyordu | BC, tekrar isteğinin içeriğini doğrular; geri alınmış ve eski tur olaylarını reddeder | AL regresyon testleri eklendi; Windows çalıştırması bekliyor |
| Bağlantı kesintisi veya 503 yanıtında HTTP katmanı stok yazma isteğini görünmeden tekrar gönderebiliyordu | Yazma isteklerinde otomatik tekrar/yönlendirme kapalı; işlem gövdesi otomatik yeniden gönderilemez | Gerçek yerel HTTP sunucusuyla 503, yanıt kopması ve yönlendirme testleri |
| Sayfalama bağlantısındaki null/bozuk değerler yanlış işlenebiliyordu | Null son sayfa olarak kabul edilir; bozuk, döngüsel ve eksik sayfalar tamamlanmış sayılmaz | Çok sayfalı sonuç, hata, döngü ve sınır testleri |
| Mutlak veri bağlantıları erişim belirtecini farklı bir adrese taşıyabiliyordu | Kimlik doğrulamalı çağrılar yalnız HTTPS Business Central API adresine gider | Host, protokol ve kullanıcı bilgisi içeren URL testleri |
| Bazı miktar alanları NaN, Infinity veya taşan üs değerlerini kabul ederek JSON oluştururken uygulamayı kapatabiliyordu | Sekiz işlem modülündeki 26 sayı okuması yalnız sonlu değerleri kabul eder | Sonlu sayı, sıfır, negatif ve taşma testleri |
| Android genel test komutu müşteri sürümleri ayrıldığı için belirsiz görev adına düşüyordu | Bade, Dynops ve Emu görevleri açıkça seçilir; tek işçi ve geçici Gradle süreci kullanılır | Düzeltilmiş test görevleriyle doğrulama |
| Android lint hataları dağıtımı durdurmuyordu | Hatalarda derleme durur, release denetimi açık, MissingClass bastırması kaldırıldı | Yapılandırma düzeltildi; son lint disk koruması nedeniyle tamamlanamadı |
| DKC özel LP ekranı ortak BC paketinde olmayan işlemlere dayanıyordu | Özel paketin bütün gerekli işlemleri metadata üzerinden doğrulanmadan ekran etkinleşmez | Eksik, kısmi ve tam özellik sözleşmesi testleri |

## Çalıştırılan kontroller

Kesin sonuçlar ve derleme günlükleri `build/customer-audit/` altında tutulur. Son doğrulama durumu `build/customer-audit/validation.txt` dosyasına yazılır; kaynak değişikliklerinin yedeği `build/customer-audit/source-snapshot/` altındadır. Bu rapor yeni bir APK yayımlandığı anlamına gelmez.

- Android Bade, Dynops ve Emu sürümlerinin her birinde 276 birim testi geçti; toplam 828 çalıştırmada hata veya atlanan test yok. Bunlar üç sürümde aynı ortak test paketinin çalıştırılmasıdır; 828 farklı senaryo anlamına gelmez.
- Web, push relay, lisans servisi, müşteri portalı ve portal API derlemeleri geçti.
- Push relay 10, lisans servisi 12, portal API 7 test geçti.
- Web'in mevcut üç tarayıcı testine ek olarak 17 menünün boş veri ve bağlantı kesintisindeki dolaşımı test edildi; toplam beş Playwright testi geçti. Bu testlerde gerçek BC ve müşteri kimlik bilgileri kullanılmadı.
- Web kaynak dizininde Vitest birim testi bulunmadığı için bu adım ayrıca test kapsamı olarak sayılmadı.
- Android/AL kaynak karşılaştırmasında 65 sabit işlem çağrısı incelendi; 63 işlem ortak BC paketinde mevcut, iki DKC hiyerarşi işlemi ayrı paket gerektiriyor. Dinamik çağrıların tamamının doğrulandığı iddia edilmez.
- AL için isim, izin, eski nesne metadatası ve dokuz posting yolunda alan uyumu denetimleri geçti. Mevcut tr/de çeviri dosyalarının kapsama eksikleri sürmektedir.

## Tamamlanamayan derleme ve canlı kabul

- Son Android lint çalışması, boş disk alanı 350 MiB altına düştüğü için otomatik durduruldu. Önceki sürümün lint raporları bu kaynak için başarı sayılmaz. Yeni imzalı 1.14.103 APK üretilmedi; mevcut eski APK dosyaları yeniden adlandırılmadı.
- macOS üzerinde AL derlenmedi; depo kuralı Windows AL araçlarını gerektiriyor. Eklenen AL testleri çalıştırılmış test sayısına dahil değildir.
- Müşterinin BC ortam bağlantısı ve kullandığı terminal sürümü soruldu; ortam doğrulaması için bu bilgiler ve erişim gerekiyor.
- Daha önce bildirilen LP79 kaydının mevcut madde defter girişi bağlantısı bu erişim olmadan okunamadı veya onarılamadı.
- İzole Android emülatörü, gereken veri bölümü için disk alanı yetersiz olduğundan açılamadı; cihaz üstünde çalışma testi yapılmış sayılmaz.
- Gerçek terminal, donanım barkod okuyucu ve fiziksel etiket yazıcısı ile uçtan uca kabul yapılmadı.
- Canlı BC, kararlı APK kanalı ve müşteri verileri değiştirilmedi. 1.14.103 kaynak değişiklikleri doğrulama adayıdır; tamamlanmamış BC/cihaz kabulünü geçmiş saymayın.

Geçici tarayıcı ve bu denetimde kurulan servis bağımlılıkları disk baskısını azaltmak için temizlendi; test kaynakları ve sonuç günlükleri korundu. Bu çalışmanın Gradle ve test tarayıcısı süreçlerinin kapalı olduğu kontrol edildi. Android ara derleme önbellekleri temizlendi; kaynaklar, mevcut APK dosyaları ve test raporları korundu. Bilgisayarın genel disk doluluğu devam ediyor; kullanıcının diğer uygulamaları veya dosyaları temizlenmedi.
