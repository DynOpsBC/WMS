# BADE LP kaynak düzeltmesi — canlı güvenlik incelemesi

## Yayın durumu

**1.14.143 APK / BC 1.14.1.61 canlıya alınmamalı.** Güvenlik incelemesinde tespit edilen davranışlar aşağıdaki 1.14.144 / BC 1.14.1.62 adayında daraltıldı. Yeni aday da BADE sandbox doğrulaması yapılmadan canlıya hazır olarak değerlendirilmemeli.

## Tespit edilen ve kaldırılan riskler

- Kalan stokta tek eşleşme bulunması, eski LP satırının gerçek kökeninin kanıtı değildir. Otomatik eski-kaynak bağlama kaldırıldı. LP Bilgisini Yenile yalnız kayıtlı kesin kaynak bağlantılarını/standart kayıt ilişkilerini yansıtır. Kaynaksız satır için kullanıcı doğru girişi açıkça seçer.
- Yeni genel kaynak-zorunluluğu, normal üretim LP'lerini ve onarımı mümkün olmayan tarihsel LP etiketlerini engelleyebiliyordu. Genel baskı engeli kaldırıldı; mevcut etiket yolları kaynak eksikliği yüzünden yeni bir engele takılmaz.
- Bağlantı onarımı SKT'yi kaynak girişten koşulsuz kopyalıyordu. Onarım mevcut SKT'yi korur; iki bilinen tarih çelişiyorsa reddedilir. Yeni oluşturulan satır kaynak SKT'yi alır.
- Eski addLineFromBin uç noktası kaynak numarası olmadan çalışmaya devam eder. Yeni BADE APK addLineFromBinWithSource kullanır ve açık kaynak seçer. Kaynağı olmayan eski istemciye kaynak tahmini yapılmaz.
- Kaynak seçimindeki toplam 100 kayıt sınırı kaldırıldı. Belge numarası boş girişler seçilemez ve yeni API/onarım tarafından reddedilir.

## Korunan düzeltme

Yeni BADE Satır Ekle akışında aynı ürün/varyant/lot/seri/lokasyon için kaynak belge/giriş seçilir. Sunucu eşleşmeyi ve temel birimde LP'ye ayrılabilir miktarı kontrol eder. Kaynak numarası, belge ve miktar referansı satıra aynı işlemde yazılır. Stoktan toplu LP oluşturma zaten seçilmiş olan kesin giriş numarasını taşır.

Mevcut LP satırında Kaynak Girişi Bağla işlemi yalnız bağlantı alanlarını ve ILE özel LP alanlarını günceller; stok/ambar hareketi oluşturmaz, miktar/raf/SKT değiştirmez. Mevcut dolu kaynak değiştirilemez. Tekrarlanan istek ikinci stok/audit kaydı oluşturmaz. Sıfır miktarlı kaynak-bağlandı audit kaydı tutulur.

## Test kapsamı ve sınırı

- Android release test/lint/build ve Windows AL derleme sonuçları paket DOGRULAMA.txt içinde.
- AL kaynak regresyonları derlenir; **BC runtime içinde henüz çalıştırılmadı**. TestPermissions=Disabled olduğundan runtime testleri başarılı olsa dahi terminal kullanıcısının gerçek izinleri ayrıca kontrol edilmelidir.
- Mevcut Azure oturumu BADE tenant için AADSTS50020 alıyor. BADE canlı kayıtları okunamadı/değiştirilmedi, fiziksel etiket basılmadı.

## Canlı öncesi gerekli BADE sandbox kontrolleri

1. Önce BC 1.14.1.62, sonra APK 1.14.144 test ortamında kurulmalı; paket yüklemesinin eski LP/source alanlarını kendiliğinden değiştirmediği doğrulanmalı.
2. Ayrı test uygulamasındaki codeunit 72182 Microsoft Test Explorer veya Test Tool üzerinden çalıştırılmalı. Uygulamanın kendi Test Center'ı bu Subtype=Test codeunit'ini çalıştırmaz.
3. 150 bağlı + 850 kaynaksız örnekte LP Bilgisini Yenile'nin kaynak tahmin etmediği doğrulanmalı. 850 satırına açıkça doğru giriş seçildiğinde ILE Quantity/Remaining Quantity, toplam LP miktarı, raf ve SKT önce/sonra aynı kalmalı; sadece kaynak/LP referansları değişmeli. İkinci aynı istek yeni audit yaratmamalı.
4. Farklı ürün/lot/seri/varyant/lokasyon, yetersiz stok, çelişen SKT ve boş belge reddedilmeli; başarısız işlem hiçbir kaynak bağlantısı bırakmamalı.
5. Eski kaynak-opsiyonel APK/API, yeni kaynak seçmeli ekleme, toplu LP oluşturma, üretim LP etiketi ve tarihsel etiket yeniden basımı denenmeli.
6. BADE müşteri PDF raporu 60150 kullanılıyorsa her PIN kullanıcısının displayName'i aynı şirkette tek aktif Employee ile eşleşmeli. Eşleşme yok/çoklu ise otomatik PDF baskısı hata verebilir; mal kabul başarılı kalabilir. ZPL bu Employee eşleşmesine ihtiyaç duymaz. Gerçek terminal rolüyle mal kabul+otomatik baskı ve bir yeniden baskı doğrulanmalı.

## Mevcut LP000400

Canlı 850 adetlik satır henüz onarılmadı. Doğru kaynak belge/giriş kullanıcı tarafından doğrulanıp seçilmeli; ardından etiket yeniden basılmalı. Eski kâğıt etiket veya eski giriş-yapan geçmişi kendiliğinden değişmez. Yeni basımdaki ad, o anda PIN ile giriş yapan operatördür.
