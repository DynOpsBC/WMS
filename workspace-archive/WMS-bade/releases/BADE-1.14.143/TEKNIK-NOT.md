# BADE 1.14.143 / BC 1.14.1.61 — LP kaynak giriş bağlantısı

## Neden

Mevcut LP'ye `AddLineFromBin` ile ürün eklenirken raf stoğu kontrol edilip gerekirse raf hareketi yapılıyor, ancak LP satırına kaynak madde defteri giriş numarası ve kaynak belge yazılmıyordu. Etiket bu satırda depo giriş numarası yerine U.Y ve tarih olarak LP oluşturma tarihini kullanabiliyordu. ILE üzerindeki LP alanı da güncellenmiyordu. Fotoğraftaki LP000400: 150 adet bağlı satır, 850 adet kaynak bilgisi eksik satır durumuyla uyumlu. Canlı kayıt okunamadığı için bu örneğin gerçek kaynak giriş numarası henüz doğrulanmadı.

## Düzeltme

- BADE terminal Satır Ekle akışında aynı ürün/varyant/lot/seri/lokasyonun kaynak girişleri tarih, belge ve ayrılabilir miktarla gösterilir; kullanıcı seçer.
- `addLineFromBinWithSource` kaynak girişini zorunlu taşır; eski BC'ye sessiz geri dönüş yoktur.
- Sunucu kaynak kimliğini ve temel birimde ayrılabilir miktarı kontrol eder, kaynak bağlantısını satır eklemeyle aynı işlemde yazar. Stoktan toplu LP üretimi de aynı yolu kullanır.
- Eski istemci kaynak seçmiyorsa yalnız tek uygun giriş otomatik seçilir; birden fazla giriş varsa işlem açıklamayla reddedilir.
- Mevcut eksik satırlar terminal ve BC LP kartından **Kaynak Girişi Bağla** ile onarılır. Yanlış ürün/lot/seri/varyant/lokasyon ve yetersiz miktar reddedilir. Mevcut kaynak değiştirilemez. Miktar ve raf hareketi yapılmaz; hareket geçmişine sıfır miktarlı kaynak bağlama kaydı yazılır. Tekrarlanan istek çoğaltılmaz.
- **LP Bilgisini Yenile** raf kaynaklı eski satırları yalnız tek uygun ve yeterli stok girişi varsa onarır. Ürün/lot benzerliğine dayalı eski tahmin kaldırıldı. Birden fazla aday varsa LP kartından seçim gerekir. Tarihsel tüketim LP referansları silinmez.
- Etiket basılmadan bütün aktif stok satırlarının kaynak bilgisi kontrol edilir. Kaynağı eksik satır için açıklama gösterilir. Sıfır miktarlı eski satırlar toplu etiket verisine katılmaz.
- Giriş Yapan kullanıcı düzeltmesi de bu sürümde korunur.

## Doğrulama

Android release derlemesi başarılı; 405 birim testi geçti, lint 0 hata (21 uyarı). APK imzası 1.14.141/142 ile aynı. BC 1.14.1.61 ve test paketi Windows CI üzerinde başarıyla derlendi: https://github.com/DynOpsBC/WMS/actions/runs/35582199867. AL testleri yalnız derlendi; BC sandbox içinde yürütülmedi. Ayrıntılar paket içindeki DOGRULAMA.txt dosyasında. AL regresyon testleri: 150+850 onarım/etiket, yeni raf ekleme, belirsiz eşleşme, farklı lot/lokasyon, miktar yetersizliği, koli-temel birim dönüşümü, tekrarlanan istek, tarihsel LP koruma, kaynak eksikliği, mevcut kaynağı değiştirmeme. AL testleri BC sandbox içinde ayrıca yürütülmelidir.

## Kurulum ve mevcut palet

Önce BCWMSApp 1.14.1.61, ardından BADE APK 1.14.143 kurulmalı. Canlıya paket yüklenmedi, mevcut stok/LP kaydı değiştirilmedi, fiziksel baskı yapılmadı.

LP000400 kartındaki 850 adetlik satırın kaynak girişini doğrulayın. Madde Defter Girişlerinde ilgili pozitif giriş seçilip LP Bilgisini Yenile çalıştırılabilir. Otomatik eşleşme bulunmazsa LP satırından Kaynak Girişi Bağla ile doğru belge/giriş seçilir. Kaynak giriş numarası ve belge, satırda ve ILE LP sütununda doğrulandıktan sonra etiket yeniden basılır. Eski kâğıt etiket kendiliğinden değişmez.
