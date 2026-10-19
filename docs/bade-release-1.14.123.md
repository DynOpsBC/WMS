# BADE 1.14.123 / BC 1.14.1.50 — MTE çerçeve + kenar boşluğu + QR altı LP no, BC'den açılan Sayım V2

Android: **1.14.123-bade**, versionCode **200123**. BC: **BCWMSApp 1.14.1.50**. 1.14.122 / BC 1.14.1.47–1.14.1.49'daki
her şey bu pakette de vardır (sayımda bulunan stoğun taşınması, MTE'nin yatay basılması).

## Merve (17 Eyl, Teams)

1. "qr altında lp nosu" → QR'ın altına LP numarası basılır (40 nokta, ortalı).
2. "sıfıra sıfır biraz daha daraltmanız gerekicek" → etiketin dört kenarında 3 mm (24 nokta) boşluk bırakılır; baskı
   kayması olsa da hiçbir çizgi kenardan taşmaz.
3. "çerçeveli alsa süper olur" → başlık dahil tüm etiketi saran dış çerçeve (3 nokta kalınlık).
4. "bc den sayım açınca böyle oluyor / v2 de seçili" → BC'de V2 Scan Mode açık oluşturulan sayım belgesi klasik Sayım
   ekranında açıldığında yalnız "ana menüden Sayım V2'yi açın" notu çıkıyordu. Artık o kartta **"Sayım V2'de Aç"**
   düğmesi var; belge doğrudan Sayım V2 ekranında açılır (`CountV2Handoff`). BC'de bir değişiklik gerekmez.

## BC 1.14.1.50 — MTE ZPL düzeni

`MTE Zpl Builder`: yatay kanvas 1218 x 812, çerçeve 24..1194 x 24..788, başlık bandı 24..78, tablo 78..756, altbilgi
756..788. Sütunlar 272 / 296 / 306 / 296. Alt blokta sol alanlar, dar KABUL/RED/KARANTİNA sütunu ve QR sütunu; QR
büyütme 10 (ZPL üst sınırı), altında LP numarası. Önizleme `docs/labels/bade/mte-zpl-landscape-4x6.png`, aynı ZPL
`.zpl`, Python aynası `mte-zpl-landscape-preview.py` (düzen değişince ikisi birlikte güncellenir).

## Doğrulama

- alc 0 hata. 358 BADE birim testi yeşil, lint 0 hata, APK imzası sahadaki 1.14.122 ile aynı (ea7710af…).
- Labelary render'ında dört kenarda 24 nokta boşluk ölçüldü; çerçeve, LP no ve tüm hücreler yerinde.
- Fiziksel yazıcıda basılmadı, canlı BC testi yok.

## Kurulum

BC'ye `BCWMSApp-1.14.1.50.zip` yüklenmelidir (etiket düzeni bunu gerektirir). Terminaller kanaldan 1.14.123'e güncellenir.
Sayım V2 düğmesi BC güncellemesi olmadan da çalışır.
