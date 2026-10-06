İki saha sorununu birlikte çözen sand0309 test adayıdır.

- Açık üretim ambar çekmesinde bir hazır LP kaydedildikten sonra BC kalan miktarı yeniden önerip eski LP numarasını satırda tutuyordu. Terminal artık bu kayıtlı geçmişi aktif toplama sanmıyor; aynı üretim emrine ikinci ve sonraki hazır LP'ler sırayla hazırlanabiliyor. Gerçek kısmi toplama ve başka açık LP hâlâ korunuyor.
- `Stoktan Tekli LP Oluştur` ekranında aynı ürün, varyant, lot, seri, lokasyon ve ölçü birimine ait birden fazla Madde Defter Girişi seçilebiliyor. Seçilen girişlerin LP'lenebilir miktarları tek LP'ye ekleniyor ve her LP satırı kendi kaynak giriş numarasını koruyor. Farklı stok kimlikleri aynı LP'ye seçilemiyor.

**APK 1.14.150-bade (200150), BC uygulaması 1.14.1.64 gerektirir.** Önce AL paketi sand0309'a, sonra APK terminale kurulmalıdır.

409 BADE Android birim testi geçti; release lint hata vermedi. APK sabit saha sertifikasıyla imzalandı. [Windows AL doğrulaması](https://github.com/DynOpsBC/WMS/actions/runs/35620416210) uygulamayı ve AL regresyon test paketini başarıyla derledi.

1.14.149 ile ilk hazır LP'nin üretim çekmesi gerçek sand0309 verisinde geçti. Bu sürümde eklenen ardışık ikinci LP ve çoklu stok girişi senaryoları sand0309'da tamamlanmadan Production'a yüklenmemelidir. `INSTALL-TEST.md` zorunlu kabul adımlarını içerir.

Kaynak commit: `b4df3eef11e4567ba56dd5f0823a5181b2093684`.
