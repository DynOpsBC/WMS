# Etiket Tasarımcısı — BC ↔ HTML sözleşmesi (v1)

Sürükle-bırak etiket tasarımcısı BC'ye control add-in olarak gömülür
(`controladdin "DOPSWHS Label Designer"`). Tasarımcı yalnız çizer ve
tasarımı JSON olarak verir; ZPL'i BC'deki `DOPSWHS Label Layout Engine`
üretir. Terminal, BC ve test baskı aynı motoru kullanır.

İlk sürüm etiket türleri: **Item** (Ürün), **Bin** (Raf), **LP** (LP / Palet).
Zone mevcut olarak kalır.

## Control add-in

```
controladdin "DOPSWHS Label Designer"
  Scripts / StartupScript = Resources/labelDesigner.js
  StyleSheets             = Resources/labelDesigner.css

  procedure LoadDesign(DesignJson: Text);     // tasarım + alan listesi + resimler
  procedure ShowPreview(PngBase64: Text);     // BC/Labelary önizleme sonucu (opsiyonel)
  procedure ShowMessage(Kind: Text; Message: Text); // Kind: info | error | success

  event ControlReady();
  event SaveRequested(DesignJson: Text);
  event TestPrintRequested(DesignJson: Text);
  event PreviewRequested(DesignJson: Text);   // Labelary ile kontrol (örnek veri)
  event CompanyLogoRequested();               // BC şirket logosunu gönderir (LoadDesign ile images[])
```

## DesignJson

```json
{
  "version": 1,
  "code": "ITEM",
  "description": "Ürün etiketi",
  "kind": "Item",                 // Item | Bin | Zone | LP
  "widthMm": 80, "heightMm": 40, "dpi": 203,   // dpi: 203 | 300
  "active": true,
  "activeAtLoad": true,           // BC → tasarımcı → BC: yüklemedeki Aktif (aşağıya bakın)
  "elements": [                   // zorunlu; boş tasarım = []
    {
      "id": "e1",                  // tasarımcı içi kimlik; BC satır no ile eşleşir (lineNo)
      "lineNo": 10000,             // yeni elemanda 0
      "type": "text",              // text | field | barcode | qr | line | box | image
      "xMm": 2, "yMm": 2, "wMm": 50, "hMm": 6,
      "rotation": 0,               // 0 | 90 | 180 | 270 (QR yalnız 0)
      "fontMm": 4, "fontWidthMm": 0, "minFontMm": 0,
      "bold": false,               // ZPL'de kalın font yok: 0 = normal; true ise ^A0 genişlik %120
      "align": "left",             // left | center | right
      "field": "ItemNo",           // type=field / barcode / qr için veri anahtarı (fields[].key)
      "text": "",                  // type=text için sabit metin; barcode/qr'da field boşsa sabit veri
      "prefix": "", "suffix": "",
      "maxLines": 1, "fit": true, "inverted": false,
      "symbology": "code128",      // barcode: code128 | ean13 | gs1-128
      "showText": true,            // barcode altı insan okunur yazı
      "thicknessMm": 0.3,          // line / box kenar; box'ta 0 = dolu
      "imageId": "",               // type=image: images[].id
      "imageGf": "",               // type=image: ^GFA verisi (tasarımcı eleman boyutu+dpi ile üretir)
      "enabled": true
    }
  ],
  "fields": [                       // BC → tasarımcı (yalnız okuma): bu türün veri alanları
    { "key": "ItemNo", "label": "Ürün No", "sample": "AB.00175" }
  ],
  "images": [                       // BC ↔ tasarımcı: yüklenen resimler / şirket logosu
    { "id": "COMPANY", "name": "Şirket logosu", "dataUrl": "data:image/png;base64,..." }
  ]
}
```

Kurallar:
- Birimler mm; tasarımcı ekranda ölçekler. BC mm → nokta çevirir (203 dpi = 8 nokta/mm, 300 dpi = 12).
- `SaveRequested` tüm tasarımı gönderir; BC satırları silip yeniden yazar (lineNo korunmaz, sıra = dizi sırası).
  `elements` anahtarı **zorunludur** ve dizi olmalıdır; yoksa veya dizi değilse kayıt hata verir ve
  hiçbir satır silinmez. Boş tasarım için açıkça `[]` gönderilir. Dizideki her öğe nesne olmalıdır.
- Resim ZPL'e tasarımcıda çevrilir: eleman boyutu ve dpi'ye göre siyah-beyaz (eşik %50)
  `^GFA,<toplam byte>,<toplam byte>,<satır byte>,<hex>` verisi `imageGf` alanına yazılır.
  BC bunu olduğu gibi `^FO x,y` ardına koyar. Resmin kendisi (`dataUrl`) `images[]` içinde saklanır.
- Bilinmeyen alan anahtarı, sığmayan eleman (etiket dışına taşan) tasarımcıda uyarı verir, kaydı engellemez.
- Etiket türüne göre alan anahtarları BC `DOPSWHS Label Layout Fields` codeunit'inden gelir.

## LP türü veri alanları (yeni)

`LPNo, SSCC, BarcodeData, ItemNo, Description, LotNo, ExpirationDate, Quantity, TotalQuantity,
UoM, LocationCode, BinCode, ItemCount, LineCount, ExtraLines, Company, Today`

Sabit LP etiketiyle aynı veriyi vermek için (BC 1.14.3.14):
- `BarcodeData`: SSCC doluysa SSCC, değilse LP No (sabit etiketin çizgi barkodu).
- `TotalQuantity`: tüm ürün satırlarının miktar toplamı (Quantity ile aynı biçim). Satırların
  birimleri farklıysa boş kalır (farklı birimler toplanmaz).
- `LineCount`: ürün satırı sayısı. `ExtraLines`: birden fazla satır varsa `+N DİĞER SATIR`, yoksa boş.
- `Quantity`, `UoM`, `ItemNo`, `LotNo`, `ExpirationDate` ilk ürün satırındandır; `ItemCount` farklı ürün sayısıdır.

## BC uygulama notları (BC 1.14.3.13, 21 Eki 2026)

BC tarafı bu sözleşmeye göre yazıldı; aşağıdakiler sözleşmeyi netleştirir veya
geriye uyumlu (opsiyonel) alan ekler.

- **Döndürme:** saat yönünde. `xMm,yMm` = elemanın etikette **döndürülmüş** halinin
  sol-üst köşesi (ZPL `^FO`). `wMm` metin/barkod yönündeki uzunluk, `hMm` dönmemiş
  yükseklik; 90/270'te etikette kapladığı alan `hMm × wMm`. ZPL: 0=N, 90=R, 180=I, 270=B
  (`^A0R`, `^BCR`, `^BER`). Kutu/çizgide 90/270 genişlik-yükseklik yer değiştirir.
  QR her zaman 0 (BC kayıtta 0'a çeker). Çok satırlı metinde satırlar metnin "aşağı"
  yönünde dizilir.
- **Kalın:** `^A0` genişliği ×1,2; "sığdır" açıksa genişliğin 1/1,2'sine göre ölçülür.
- **Barkod:** `code128` + rotation 0 → mevcut Label Canvas çıktısı (insan okunur yazıyı BC
  ortalar). Diğerlerinde yazıcının kendi yorum satırı (`showText`) kullanılır.
  `ean13`: veri 12/13 rakam (13. hane atılır, yazıcı kontrol hanesini ekler); rakam
  değilse Code128 basılır. `gs1-128`: `^BC…,D` (UCC/EAN modu, FNC1 ile başlar); veri AI'lar
  parantezli yazılır, ör. `(01)08690000012345(10)LOT1(17)271231`. **FNC1 ayırıcıyı BC üretir**
  (1.14.3.14): önceden tanımlı uzunlukta olmayan bir AI'dan (00–04, 11–20, 31–36, 41 dışındakiler)
  sonra başka AI geliyorsa `^FD` içine çıplak `>8` yazılır; kullanıcı verisi `^FH_` ile kaçırılır.
  Yazıcı `^FH`'yi Code 128 invocation kodlarından önce çözdüğü için (`_3E8` de FNC1 olur, mod D'de
  başka bir `>x` sembolü bozar) GS1 verisinde `>` olamaz: varsa barkod düz Code128 (mod A) basılır.
  Eski sözleşmedeki elle yazılmış `>8` yok sayılıp yeniden üretilir. Mod D GTIN/SSCC kontrol
  hanesini kendisi hesaplar (yanlış hane düzeltilerek basılır). Labelary ile çözülerek doğrulandı.
- **Resim:** `imageGf` yalnız `^GFA,<n>,<n>,<n>,<veri>` olabilir; başka `^`/`~` içerirse
  kayıt reddedilir, basımda atlanır. BC resmi döndürmez — döndürme `imageGf`'e işlenmiş
  gelmelidir. `imageId` büyük harfe çevrilir, en çok 20 karakter.
- **images[]:** `dataUrl` dolu olan kayıt BC'de `DOPSWHS Label Image`'a yazılır/güncellenir —
  yalnız saklı resimden farklıysa (aynı resim yeniden yazılmaz, yazma izni gerektirmez; yalnız
  ad/boyut farkı izin varsa güncellenir). `dataUrl` boş kayıt yalnız referanstır. Opsiyonel `widthPx`, `heightPx` (BC saklar, geri
  gönderir). BC → tasarımcı: elemanların referans verdiği resimler (+ istenirse COMPANY).
- **CompanyLogoRequested yanıtı:** `LoadDesign` DB'deki kayıtlı tasarımı + `images[]`
  (COMPANY dahil) ile gelir ve **`"merge": "images"`** taşır. Tasarımcı bu alanı görünce
  yalnız `images[]`'i birleştirmeli, kaydedilmemiş elemanlarını korumalıdır. Şirket logosu
  yoksa `ShowMessage('error', …)`.
- **readOnly (BC → tasarımcı, yeni):** kullanıcının tasarım tablolarına yazma izni yoksa
  `true`; `SaveRequested` bu durumda `ShowMessage('error', …)` döner.
- **activeAtLoad (BC → tasarımcı → BC, 1.14.3.14):** BC `LoadDesign`'da tasarımın o anki Aktif
  değerini `activeAtLoad` olarak da gönderir; tasarımcı bunu kayıtta aynen geri yollar ve her
  başarılı kayıttan sonra tabanı gönderdiği `active` değerine çeker. BC Aktif'i yalnız
  `active ≠ activeAtLoad` ise (kullanıcı tasarımcıda değiştirdiyse) yazar; eşitse veya iki
  anahtardan biri yoksa Aktif'e dokunmaz. Böylece eski bir tasarımcı penceresi, arada başka bir
  yerde yapılan aktifleştirmeyi ezmez.
- **Başlık:** `widthMm/heightMm/dpi` BC'nin etkin değerleridir (BC'de 0 = Kurulum ölçüsü,
  gönderilmeden çözülür). Kayıtta BC'deki değer 0 iken geri gelen ölçü çözülen ölçüyle aynıysa
  0 korunur (Kurulum ölçüsünü izlemeye devam eder); farklıysa yeni ölçü yazılır.
  Kabul edilen dpi: 203, 300, 600 (0 → 203). Ölçü: genişlik 0–300 mm, yükseklik 0–400 mm.
  `kind` gönderilirse Item | Bin | Zone | LP olmalıdır; boş veya bilinmeyen değer hatadır.
- **Eleman:** `id` en çok 50 karakter (BC "Element Id"); `lineNo` kayıtta yok sayılır.
  `text` ≤ 100, `field`/`prefix`/`suffix` ≤ 30 karakter; aşan değer kaydı hatayla durdurur.
  Bilinmeyen `type`/`symbology`/`align` veya rotation ∉ {0,90,180,270} hatadır.
  Bilinmeyen alan anahtarı kaydı engellemez (o eleman boş basılır).
- **Yanıtlar:** doğrulama hatası → `ShowMessage('error', metin)`; kayıt → `ShowMessage('success', …)`
  (BC kayıttan sonra `LoadDesign` çağırmaz). `TestPrintRequested`: BC yazıcıyı kendi
  listesinden sordurur, **kaydedilmemiş** tasarımı ÖRNEK verilerle basar.
  `PreviewRequested` → `ShowPreview(PngBase64)`: `data:` öneki olmayan çıplak base64.
  Labelary'e (labelary.com, dış hizmet) gerçek kayıt verisi gitmez, alanlar örnek verilerle
  doldurulur; **ancak tasarımdaki resimler (şirket logosu, yüklenen resimler) `^GFA` verisi olarak
  önizleme ZPL'inde Labelary'e gider.**
- **LP türü:** aktif LP tasarımı varsa LP etiketi (`DOPSWHS LP Label`.BuildZpl → terminal,
  LP kartı, LP Browser, Print Dispatcher) motorla basılır; yoksa sabit 4x2" tasarım aynen
  kalır. Varsayılan pasif `LP` tasarımı (101,6 × 50,8 mm) sabit tasarımı taklit eder:
  çizgi barkod `BarcodeData` (SSCC, yoksa LP No), miktar `TotalQuantity`, lotun yanında
  `ExtraLines` ("+N DİĞER SATIR"). İlk sürümün (1.14.3.13) varsayılan satırları, hiç
  değiştirilmemişlerse liste açılışında bu sürüme yükseltilir; düzenlenmiş tasarıma dokunulmaz.
  Değerler LP başlığı + satırlardan (yukarıdaki LP alanları).
- **ETIKETV2:** QR/ürün no büyütmesi şirket başına bir kez yapılır (upgrade tag
  `DOPSWHS-KITOKO-ETIKETV2-SIZE-20261021`); sonra tasarımcıda veya satırlarda seçilen ölçü geri alınmaz.
