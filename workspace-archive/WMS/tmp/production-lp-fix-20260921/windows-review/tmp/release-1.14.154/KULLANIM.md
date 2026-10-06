# BADE: üretim çekmesinde kısmi LP toplama

Sürümler: BC **1.14.1.66**, Android **1.14.154-bade** (200154).

## Kullanım

1. Üretim → Sarfiyat → üretim emri → **Ambar Çekme Aç**. BC'de açılmış üretim çekmesini Toplama listesinden de seçebilirsiniz.
2. Belgeyi **Bana Ata** ile üstlenin. **Yeni Üretim LP** ile hedef paleti açın.
3. Çekmenin her açık satırında kaynak rafı ve kaynak LP'leri okutun. Satırın ihtiyaç miktarı alınır; kaynak LP'nin tamamını vermek gerekmez. Farklı raflardaki parçalar aynı hedef LP'de birleşir.
4. **LP Hazırla** → paletin bırakıldığı hazırlık gözünü okutun → Onayla. BC aynı işlemde gerçek depo hareketini kaydeder, kaynak LP bakiyelerini azaltır, hedef LP'yi doldurur. Üretim emrinin çekilen miktarı bu aşamada artmaz.
5. **LP Etiketi Yazdır** ile yeni paletin etiketini alın. Hazırlanan LP, aynı çekme belgesine ayrılmış halde hazırlık gözünde kalır.
6. Üretime götürürken aynı belgeyi açın. Satırlarda hazırlık gözünü ve yeni LP'yi doğrulayın. **Üretime Teslim Et** → üretim teslim gözünü okutun → Onayla. Aynı çekme kaydedilir; LP üretim emrine bağlanır. Eski kaynak raflardan ikinci kez çekilmez.

Hazır bir LP'yi bölmeden taşıma akışı da devam eder; bu akış için Yeni Üretim LP açılması gerekmez.

## Sınırlar

- Bir hazırlama işlemi, aynı üretim emrine ve aynı üretim teslim gözüne giden tek bir hedef LP oluşturur.
- Çekmenin tüm açık satırlarının açık miktarı doğrulanmalıdır. Bu, kaynak LP'nin tamamını almak anlamına gelmez; kaynak LP'den yalnız ihtiyaç alınır.
- Hazırlık gözü aynı lokasyonda, giriş/çıkışı açık ve yönlendirilmiş depoda çekmeye uygun olmalıdır. Üretim teslim gözünden farklı olmalıdır; kaynak gözlerden biri hazırlık gözü olarak kullanılabilir.
- Hazırlanmış palet üzerinde eksik bildirimi, miktar/lot değişikliği veya dolu LP'yi silerek çekme iptali engellenir. Fiziksel bir düzeltme gerekiyorsa kontrollü depo düzeltmesi gerekir.
- Yeni akış için önce AL 1.14.1.66, ardından APK 1.14.154 yüklenmelidir. Canlı BC'ye otomatik dağıtım yapılmamıştır.

## Uygulama

`prepareProductionLPFor` doğrulanmış LP planını ve hedef gözü alır. Standart Warehouse Movement ile stok hazırlık gözüne taşınırken aynı üretim çekmesinin Take satırları bu göze yönlendirilir. Üretim kaynak referansları, lot/seri ve miktarlar korunur. İşlem hata verirse LP, çekme ve stok değişiklikleri birlikte geri alınır. Başlıktaki kalıcı hazırlama durumu, kayıp yanıttan sonraki tekrarın ikinci bir hareket üretmesini engeller.

Hazırlanmış LP kaynak sorgusunda tek adaydır. `deliverProductionLPFor`, okutulan üretim gözünü doğrular ve mevcut bütün-LP üretim kayıt yolunu kullanır. Standart BC kaydı üretim bileşeninin çekilen miktarını günceller. Tamamlanmış çekmeye tekrar istek stok oluşturmaz.

## Doğrulama

Sandbox test raporu yayın paketindeki TEST-RESULTS.json dosyasındadır. Temel senaryo: iki rafta 100'er birim kaynak LP; her birinden 10 alınır; kaynaklar 90/90, hazırlık LP'si 20 olur. Hazırlamada üretim çekilen miktarı sıfır kalır. Teslimde hazırlık gözü sıfır, üretim gözü ve bileşenin çekilen miktarı 20 olur. Tekrar, yanlış hedef, hazırlanmış miktarı değiştirme, iptal ve başarısız depo hareketinde geri alma kontrolleri bulunur. Testler yalnız PPTEST sentetik lokasyon ve test belgelerini kullanır; müşteri çekmesi kaydedilmez.
