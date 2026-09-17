# BADE BC 1.14.1.49 — MTE etiketi yatay (15×10 cm okunur), yazı sığdırma (Android değişmedi, 1.14.122 kalır)

BC: **BCWMSApp 1.14.1.49** (`output/release-bade-bc-1.14.1.49/BCWMSApp-1.14.1.49.zip`). 1.14.1.48'deki sayım taşıma
düzeltmesi de bu pakettedir. Android: 1.14.122 aynen.

## Kullanıcı (17 Eyl 11:00, fotoğraf)

Zebra'dan çıkan MTE dikeydi (10 cm en, 15 cm boy, 1.14.1.46/47 düzeni). "Yatay çıkması lazım." Fotoğrafta ayrıca
"MADDE KATEGORİSİ" ve "SON KULLANMA TARİHİ" üst üste binmiş, "KARANTİNA" → "KARANTİN-" kesilmişti.

## Neden bozuktu

`MteZplBuilder.Text` metni `^FB…,1` (tek satır) ile basar; ZPL tek satırlık blokta sığmayan kelimeyi aynı satırın
üstüne yazar (ya da tireleyerek keser). Dikey düzende hücreler dar olduğu için uzun etiketler taşıyordu.

## 1.14.1.49

- **Yatay düzen**: etiket stoğu 4×6 inç (100×150 mm) ve 4 inç yazıcıdan dikey besleniyor; tasarım 1218×812 yatay
  kanvasta kuruldu, her primitif (Box/Text/Qr) 90° saat yönünde döndürerek 812×1218 stoğa basıyor (`^A0R` metin;
  kanvas (x,y,w,h) → stok (812−y−h, x, h, w)). Operatör etiketi çeyrek tur sola çevirince 15 cm en × 10 cm boy okur.
- Düzen müşterinin basılı etiketiyle birebir (17 Eyl ikinci fotoğraf, AB.00730, "tam olarak bu fotodaki gibi"):
  çerçevesiz başlık bandı (BS GROUP solda, başlık ortada); 7 üst satır raporla aynı sırada (MADDE KODU/KATEGORİSİ,
  MADDE ADI, INCI ADI, TEDARİKÇİ ADI, TEDARİKÇİ LOTU, ÜRETİM TARİHİ/LOT NO, SON KULLANMA/MİKTAR); altta sol blok
  (DEPOLAMA KOŞULU, DEPO GİRİŞ TARİHİ/NO, GİRİŞ YAPAN, KALİTE KONTROL ONAYI, KONTROL EDEN, TARİH, İMZA), dar
  KABUL/RED/KARANTİNA sütunu (satır gruplarını kaplar) ve yalnız QR içeren geniş sütun (başlık ve LP yazısı YOK;
  QR = LP no, ZPL büyütme üst sınırı 10); en altta DOKÜMAN/REVİZYON satırı. Bütün hücre metinleri raporun kendisi gibi
  ortalı. Zebra'da Verdana yok: tüm yazılar Zebra font 0 (kalın, dar); değerler etiketlerden biraz dar basılır.
- **Yazı sığdırma** (`FitFontWidth`): metin hücreye sığmıyorsa font genişliği daraltılır (min 12), üst üste binme/tireleme
  kalmaz.
- Önizleme: `docs/labels/bade/mte-zpl-landscape-4x6.png` (Labelary 8dpmm 4x6, 90° döndürülmüş), aynı ZPL
  `mte-zpl-landscape-4x6.zpl`, Python aynası `mte-zpl-landscape-preview.py` (AL primitifleriyle birebir; düzen
  değişince ikisi birlikte güncellenmeli).

## Doğrulama

- alc 0 hata. Labelary render'ı yatay okunuyor, tüm hücreler sığıyor, QR ortada.
- Fiziksel yazıcıda basılmadı. Saha: BC'ye 1.14.1.49 yükle → LP kartı "MTE Yazdır (terminal yolu)" ya da terminalden
  MTE → etiket dikey çıkar, sola çevirince yatay okunur. Yazıcı sürücüsü/etiket ölçüsü değişmez (^PW812 ^LL1218).

## Dosyalar

`output/release-bade-bc-1.14.1.49/`: `BCWMSApp-1.14.1.49.zip`, `SHA256SUMS.txt`. Commit edilmedi, yayınlanmadı.
