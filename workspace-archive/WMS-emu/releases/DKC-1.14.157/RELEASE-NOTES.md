# DKÇ / EMU 1.14.157

Ürün Sorgu ve Bin Sorgu ekranlarında arama alanına sesli giriş eklendi.

- Arama alanının yanındaki mikrofon düğmesine basılır ve kod söylenir. Örnek: "a be tire sıfır bir" → AB-01.
- Harfler, rakamlar, "tire", "nokta", "bölü" ve "on iki" gibi sayılar koda çevrilir.
- Arama kendiliğinden başlamaz. Alanın altında duyulan kod görünür; operatör "Ara" ile arar, "Sil" ile vazgeçer.
- Etiket Çıkar ekranındaki ürün araması da aynı alanı kullandığı için orada da mikrofon görünür.
- Ses tanımayı Android'in Google ses hizmeti yapar; uygulama mikrofon izni istemez. Hizmeti olmayan cihazda "Bu cihazda sesli giriş hizmeti yok" uyarısı çıkar.

Bu sürüm yalnız Android terminal güncellemesidir. DKÇ Business Central paketi **1.14.2.16** olarak kalır.

Doğrulama: 386 birim testi geçti, release lint hatası yok, standart ve tarihsel imzalı iki APK'nın paket kimliği, sürümü ve sertifikası doğrulandı. Emülatörde mikrofon düğmesi ve Türkçe ses ekranı görüldü; fiziksel terminalde konuşarak deneme yapılmadı.

- Standart APK SHA-256: `8c211546e4f852f30edfe2534d0adf65b4fed73d03efa20ea2b2c702299f8849`
- Uyumlu APK SHA-256: `f99dc7afc695318b658c7ba04412bd0da0480bc7784aae48615850049b8a5a21`
