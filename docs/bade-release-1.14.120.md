# BADE 1.14.120 — LP kartındaki "İşlem tamamlanamadı … REF-…" hatası çözülebilir hale geldi (BC 1.14.1.41)

Android: **1.14.120-bade**, versionCode **200120**. BC: **BCWMSApp 1.14.1.41** (1.14.1.40 üstüne yüklenir;
BadeProduction 1.3.3.13 aynı kalır). 1.14.119/1.14.1.40'taki her şey bu pakette de vardır.

## Bildirim (16 Eylül 14:07, terminal fotoğrafı)

LP000025 (PALLET-EUR, MERKEZDEPO/M.A01.11, MM.00782 × 200, lot 207BS6070, kaynak giriş #11474) kartında
bir işlem şu metinle bitti: **"HATA: İşlem tamamlanamadı. Yenileyip tekrar deneyin. Sorun sürerse yöneticinize
REF-534F3BFA kodunu iletin."** Fotoğraftan hangi düğmeye basıldığı belli değil (Transfer, Kısmi İşlem,
MTE Yazdır, LP QR Belgesini Yazdır veya LP'yi Boz).

## Kök neden

REF kodu, BC'nin ham hata metninin özetidir (CorrelationId dahil); cihaz logcat'i olmadan geri çözülemez.
Terminal tanımadığı İngilizce BC hatalarını bilerek gizler; bu yüzden operatör de yönetici de nedeni göremedi.
Kodun incelemesinde bu kartta genel metne düşen İngilizce hatalar şunlardı:

- **MTE Yazdır (müşteri raporu 60150 yolu)**: `Report.SaveAs` başarısız olunca BC yalnız
  "Report 60150 could not be rendered as PDF." diyordu; raporun kendi hatası (rapor için **Execute yetkisi yok**,
  raporun "Etiket basılacak kayıt bulunamadı" hatası, düzen/veri hatası) yutuluyordu.
- **LP QR Belgesini Yazdır**: aynı desen — "The LP QR PDF could not be rendered."
- **Transfer**: hedef LP numarası yazım hatalıysa "The DOPSWHS LP Header does not exist. Identification fields…".
- Genel BC hataları: "You do not have the following permissions…", "The length of the string is…".

## Değişiklikler

**BC 1.14.1.41**
- `Print Dispatcher`: rapor/belge üretimi başarısız olunca gerçek BC hatası mesaja eklenir:
  "60150 Madde Tanımlama Etiketi raporu PDF olarak oluşturulamadı. BC hatası: …", "LP000025 LP QR belgesi
  oluşturulamadı. BC hatası: …", barkod test PDF'i için de aynı.
- `LP API` transfer/nest: hedef LP yoksa "LP000099 numaralı LP bulunamadı. LP numarasını kontrol edip tekrar deneyin."

**Terminal 1.14.120**
- Rapor hatası önekli mesaj operatöre "… oluşturulamadı. Neden: …" olarak gider; iç neden biliniyorsa Türkçeye çevrilir
  (yetki: "Terminal kullanıcısının BC'de 'Madde Tanımlama Etiketi' (Report) nesnesi için Execute yetkisi yok…").
- Yeni Türkçe eşlemeler: kayıt bulunamadı ("LP kaydı bulunamadı (No.='LP00099')"), yetki yok, değer çok uzun.
- **Yardım → "Son hata kayıtları (yönetici)"**: son 30 başarısız BC isteği cihazda saklanır (REF kodu, saat, HTTP,
  istek, ham BC metni). Ekrandaki REF kodu artık logcat olmadan bu listeden çözülür. Token/başlık tutulmaz.
- Operatör ekranına ham İngilizce metin gitmez kuralı korunur (testler aynı).

## Sahada REF-534F3BFA için yapılacak

1. Terminali 1.14.120'ye güncelleyin; BC'ye 1.14.1.41'i yükleyin.
2. Aynı işlemi LP000025'te tekrarlayın. Ekranda artık neden yazar. Yazmıyorsa Yardım → Son hata kayıtları → REF'e bakın.
3. MTE ise en olası neden: terminal BC kullanıcısının (dynops@badenatural.com) **BadeProduction / rapor 60150 için
   Execute yetkisi** yok → BC'de ilgili yetki setini kullanıcıya ekleyin. Kurulum → MTE Report ID = 60150 olmalı.

## Doğrulama

- alc: 0 hata (352 dosya). Android: `testBadeDebugUnitTest` tüm testler geçti (0 hata), `lintBadeDebug` 0 hata,
  `assembleBadeRelease` (200120 / 1.14.120) imzalı.
- Yeni birim testleri: rapor hatası nedeni, yetki, kayıt bulunamadı, uzunluk, cihaz içi hata kaydı (REF eşleşmesi + 30 sınırı).
- Canlı BC testi yapılmadı (hangi işlemin başarısız olduğu bilinmiyor); paket kurulunca aynı işlem tekrarlanmalı.

## Dosyalar

`output/release-bade-1.14.120/`: `BCWMS-BADE-1.14.120-RELEASE.apk`, `BCWMSApp-1.14.1.41.zip`, `latest.json`, `SHA256SUMS.txt`.
