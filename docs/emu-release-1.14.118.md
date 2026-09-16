# EMU / DKÇ 1.14.118 — Etiketler rulo ölçüsüne göre (80x40 mm), sorgu etiketi yazıcı düzeltmesi

Android sürümü: **1.14.118-emu**, versionCode **200118**. BC paketi: **BCWMSApp 1.14.2.4** (EMU dalı 1.14.2.x).
Dal: `customer/emu`. BADE dalına ve yayınlarına dokunulmadı.

## Neden

DKÇ'deki Zebra ZD230'a takılı rulo 80 x 40 mm; bütün terminal etiketleri 4x2 inç (101,6 x 50,8 mm) için
çizilmişti. Sahadaki ilk ürün etiketinde sağdaki QR ve alttaki barkod kesildi (16 Eyl 2026 fotoğrafı).

## BC 1.14.2.1

- **Kurulum → Etiket Rulosu (ZPL)**: "Label Width (mm)" / "Label Height (mm)". Boş = 80 x 40 mm.
  Rulo değişince yalnız bu iki değer güncellenir; yeni paket gerekmez. 100x50 (4x2 inç), 100x80,
  100x100 gibi rulolar da desteklenir.
- Yeni codeunit 72321 **DOPSWHS Label Canvas**: bant yüksekliği, punto boyları, QR büyütmesi, barkod
  yüksekliği ve satır sığdırma etiket ölçüsünden türetilir (`^PW`/`^LL` her etikette ölçüye göre).
- Yeniden çizilen tasarımlar (hepsi aynı iskelet: siyah başlık bandı, solda metin + Code128, sağda
  en büyük sığan QR ve altında açıklaması):
  - **Ürün etiketi** (`BuildItemZpl`): madde no sütuna sığan en büyük puntoda, açıklama kelime
    sınırından 2 satır, BİRİM + GTIN, Code128 altta (değeri açık yazılı), QR = madde no.
  - **Raf etiketi** (`BuildBinZpl`): raf kodu koridordan okunacak büyüklükte, BÖLGE/TİP/açıklama,
    Code128 + QR = raf kodu.
  - **LP tasarımları** (`DOPSWHS LP Label Builder`): standart, palet (içerikli/özet), koli, kutu, çuval.
    SSCC üretildiyse Code128 SSCC taşır ve altında açık yazılır; yoksa LP no (başlıkta zaten büyük).
    40 mm etikette en çok 2 içerik satırı listelenir, fazlası "+N satır daha".
  - **Madde tanımlama (palet madde) etiketi** (`BuildPalletItemZpl`): madde, açıklama, lot, toplam
    mal kabul, palet miktarı, QR + Code128 = LP no.
- Önizlemeler (80x40 mm, Labelary): `docs/labels/emu/*.png`.
- Testler: codeunit 72499 "DOPSWHS Label Canvas Tests" (varsayılan ölçü, Kurulum ölçüsü, sığdırma,
  QR büyütmesi, her tasarımın `^FO` başlangıçlarının etiket içinde kalması).

## Android 1.14.118

- Ürün/Raf Sorgu → Etiket Yazdır her zaman cihazda seçili **etiket** yazıcısına gider. BC kaydı yoksa
  ya da ZPL değilse iş yine gönderilir, ekranda "Windows yazıcı ajanında Yazıcıları Yenile + Buluta
  Eşitle" uyarısı çıkar (eskiden sessizce belge yazıcısına yönleniyordu).

## Yazıcı tarafı (ZD230, 203 dpi)

1. Windows sürücüsünde etiket ölçüsünü 80,00 x 40,00 mm yapın (yalnız test sayfasını etkiler; terminal
   ZPL'si kendi ölçüsünü taşır).
2. Zebra Setup Utilities → Printer Configuration → **Calibrate Media**, ki yazıcı 40 mm etiket
   aralığını öğrensin.
3. Rulo 80x40 değilse Kurulum'daki iki değeri gerçek ölçüyle değiştirin.

## BC 1.14.2.2 (16 Eyl, 15:50) — DKC Production'a yüklenebilir sürüm

DKC Production'a yanlışlıkla BADE paketi yüklenmişti; onun Kurulum tablosundaki "MTE Report ID"
alanı EMU paketinde olmadığı için BC 1.14.2.1 yükseltmesini reddetti ("Alanların kaldırılmasına izin
verilmez"). Alan artık ana şemada; 1.14.2.2 BADE 1.14.1.39/40 üzerine yüklenir. Kurulum kartına
"Allow Edition Change" eklendi: ortamda BADE damgası varsa önce bunu işaretleyin.

## Kurulum emniyeti ve genel düzeltmeler (14:15)

- Kurulum kartında **Installed Edition** (= EMU). BADE paketi (1.14.1.x) bu ortama yüklenemez; EMU
  paketi de BADE ortamına yüklenirse yükseltme hata verip geri alınır (codeunit 72322).
- Çok satırlı LP transferindeki "record already exists" hatası düzeltildi (LPManagement).
- Raf Kartı'nda LP drill-down'dan dönünce liste yenilenir.
- Ürün etiketi kısa madde no'lar için de (ör. "1") sığdırılır; eski imzalı terminaller için ayrı
  APK gerekir (bkz. docs/emu-update-2026-09-14.md).

## Kurulum sırası

1. BC: `BCWMSApp-1.14.2.4.zip` içindeki .app'i DKÇ ortamına yükleyin (1.14.2.0 üzerine).
2. Kurulum → Etiket Rulosu: 80 / 40 (ya da gerçek ölçü).
3. Terminal: `BCWMS-EMU-1.14.118-RELEASE.apk` (kanal ilerletilince uygulama içi güncelleme).

## BC 1.14.2.3 (16 Eyl, 16:05)

Ürün etiketinde QR altındaki "QR = ÜRÜN NO" yazısı kaldırıldı; QR biraz daha büyük basılabiliyor. Başka değişiklik yok.

## BC 1.14.2.4 (16 Eyl, 16:10)

BC sayfalarından etiket basma: **Bin List → Raf Etiketi Yazdır** ve **Item List → Ürün Etiketi Yazdır** (codeunit 72325). Aktif ZPL yazıcılar arasından seçim yapılır (tek yazıcı varsa sorulmaz); çıktı terminaldeki Raf/Ürün Sorgu etiketiyle aynıdır ve yazıcının istasyonuna gider.
