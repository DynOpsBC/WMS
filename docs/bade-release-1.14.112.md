# BADE 1.14.112 — teslim öncesi düzeltmeler

Bu sürüm, yayımlanmış 1.14.111 kaynağına (`c14aa69`) dayanır. Android versionCode: **200112**. Ana çalışma ağacındaki tamamlanmamış MTE ve diğer LP geliştirmeleri bu sürüme alınmadı.

## Android düzeltmeleri

- Odaklı barkod alanı raf veya işlem adımı değişince güncel bilgiyi kullanır.
- Farklı depo veya ölçü birimi satırları aynı gruba karışmaz. Grup miktarı azaltılınca eski alt satır miktarları temizlenir; bitmiş satıra yeni miktar dağıtılmaz.
- Kapasiteyi aşan miktar sessizce kırpılmaz; operatöre açıklanır.
- Lot sorgusu miktarı kaybetmeden yeniden denenir. Bazı kalite, giriş ve LP pencerelerinde klavye/kaydırma erişimi düzeltildi.
- Kamera kapanışında analiz kaynakları bırakılır ve geç sonuçlar eski akışı çalıştırmaz.
- Pasif yazıcılar aktif sayısına dahil edilmez.
- Palet sorgusunun ölçü birimi veya miktar bilgisi satırla uyuşmuyorsa operatöre eski veriyle toplama yaptırılmaz. Yeni BC paketi kalan miktarı da sorgu cevabına ekler.
- Yerleştirmede elle LP girişi açık; zorunlu toplamada palet okutma kuralı korunur.

## BC 1.14.1.36 ile yeni kayıt yolu

Yeni `registerScannedFor(userId, palletPlan)` action'ı bütün okutulan LP ve temel miktarlarını alır. Sunucuda belge sahibi, satır kimliği, depo/raf, lot/seri, ölçü birimi, miktar toplamı, eksik ve tekrarlı satır/paletler kontrol edilir. Tam olarak belirtilen LP miktarları aktarılır; eksik miktar başka paletten veya serbest stoktan tamamlanmaz. Aynı işlemde standart ambar kaydı yapılır. Standart kayıt için `SetSuppressCommit(true)` kullanılır, yeni action kapsamındaki beklenmeyen açık COMMIT hata verir.

Terminal yeni action'ı `$metadata` içinde görürse bu yolu kullanır. Henüz güncellenmemiş BC paketlerinde mevcut `registerFor` akışı korunur. Yeni action çağrıldıktan sonra hata/zaman aşımında eski action'a dönüş veya otomatik kayıt tekrarı yoktur.

**Android güncellemesi tek başına eski BC paketindeki çoklu palet yarışını kapatmaz.** BC 1.14.1.36 kurulmadan mevcut sunucu tahsis davranışı devam eder. Bu yayında canlı BC kurulumu veya stok hareketi yapılmadı. Başarılı derleme de gerçek BC kabul testi yerine geçmez.

## Doğrulama

- BADE: 336 JVM testi, 0 hata/atlanan.
- EMU: aynı 336 JVM testi, 0 hata/atlanan.
- BADE: 26 emülatör testi, 0 hata/atlanan (18 bağlantısız ekran, 5 barkod, 3 pencere).
- BADE/EMU lint: her birinde 0 hata, 77 uyarı (ayrıca 18 bilgi notu).
- İmzalı release APK derlendi; emülatörde 1.14.98 üstüne veri silmeden kuruldu ve ana menü açıldı. Oturum korundu. Bu yalnız kurulum/açılış kontrolüdür.
- Yeni regresyonlar: eski ölçü birimi/kalan miktar, tam palet listesinin gönderilmesi, miktar hassasiyeti, geçersiz planlar ve eski/yeni sunucu yeteneğinin ayırt edilmesi.
- BC plan doğrulaması için 5 AL test senaryosu eklendi; BC üzerinde henüz çalıştırılmadı.
- GitHub Windows AL derlemesi ayrı `AL verified package` işidir. Eski `AL Build` işindeki placeholder sonucu derleme kanıtı sayılmaz.

İmzalı APK, lint ve Windows paket derlemesinin nihai sonuçları GitHub yayınının varlıkları/CI çalışmasında kayıtlıdır. Fiziksel Zebra, yazıcı, çoklu terminal yarışı ve gerçek mal kabul → yerleştirme → toplama → sevkiyat kabul testi hâlâ gereklidir. Önceki [teslim incelemesindeki](bade-delivery-audit-2026-09-15.md) yönetici test girişi değerlendirmesi de açıktır.

## Sunucu kurulumu sonrası kabul ölçütleri

1. Aynı satırda LP-A 6 + LP-B 4 okutulup kaydedildiğinde yalnız bu iki LP'den 6 ve 4 düşmeli; başka LP'ye dokunulmamalı.
2. Okutmadan sonra LP-B miktarı azalırsa kayıt hata vermeli; LP-A, hedef LP ve ambar kayıtları da geri alınmalı.
3. Lot/seri/raf/depo/miktar değişikliği, eksik satır, tekrarlı LP veya geçersiz JSON kaydı durdurmalı.
4. Aynı belgeyi iki terminal kaydettiğinde ikinci kayıt yeni stok hareketi üretmemeli.
5. İşlem ortasında hata veya bağlantı kesilmesinde belge/defterler kontrol edilmeden otomatik tekrar yapılmamalı.

## Teknik kaynaklar

Microsoft'un [Whse.-Activity-Register açıklaması](https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/codeunit/microsoft.warehouse.activity.whse.-activity-register) `SetSuppressCommit` seçeneğini; [CommitBehavior açıklaması](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/attributes/devenv-commitbehavior-attribute) açık COMMIT davranışının kapsamını tanımlar. Windows derlemesi [Microsoft ALTool](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-al-tool) kullanır.
