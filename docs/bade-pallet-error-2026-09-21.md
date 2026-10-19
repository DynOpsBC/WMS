> tarihsel çalışma notu: bu dosya 21 eylül tarihindeki sürüm ve inceleme durumunu korur. güncel sürüm için [apk 155 / al 68 notlarına](bade-source-repair-and-delivery-1.14.155.md) bakın.

# Toplamada ilgisiz satırın seçilen ürünü engellemesi

## Bildirim ve tespit

Terminal fotoğrafında AB.02029, A.C01.13 rafı, 7809 ADET ve LP000159
görünüyor. Raf doğrulanmış; palet planı oluşmadığı için onay pasif.
Sonraki fotoğrafta asıl hata görüldü: AB.02029 / A.C01.13 satırı açıkken
YM.00273 / Y.A01.11 için kaynak palet bulunamadığı yazıyordu.

`loadDocumentPalletPlans`, satır penceresini hazırlarken belgenin önceki
bütün pozitif Take satırlarını planlıyordu. Başka bir ürünün kaynak paleti
olmaması, seçilen ürünün paletleri sorgulanmadan bütün pencereyi durduruyordu.

`PalletPickSheet` kaynak yükleme ve barkod doğrulama hatalarını aynı `error`
değişkeninde tutuyordu. Doğru raf okutulduğunda `error = ""` ile kaynak
hatası da siliniyordu. Yanlış raf okutulması da kaynak hatasının üstüne
yazabiliyordu.

## Düzeltme

- Satır penceresinde yalnız seçilen pozitif satırlar ve onlardan önce gelen,
  aynı ürün/varyant/depo/raf stoğunu paylaşabilen satırlar planlanır.
- Aynı stoktan önceki tüketim base miktarda düşülür; ölçü birimi, lot veya
  seri farklılığı nedeniyle bu kontrol atlanmaz. Sıfır miktar verilen satır
  önceki miktarı ayırmaz ve arama sınırını gereksiz yere uzatmaz.
- Belgenin tamamı kaydedilirken bütün pozitif Take satırları ve okutma
  kanıtları yine doğrulanır. Başka satırdaki eksik stok kayıtta gizlenmez.
- Kaynak yükleme/plan hatası ayrı durumda tutulur ve ayrı hata kartında
  gösterilir. Raf veya palet okutmak bu hatayı silemez.
- Toplama satırları alınamazsa API'nin döndürdüğü hata ayrıntısı korunur.
- Kaynak planı ve palet okutma doğrulaması olmadan onay açılmaz.
- Yenileme, doğrulanmış rafı korur; palet planını yeniden sorgular.

Bu değişiklik, ekran görüntüsündeki ilgisiz satır engelini giderir.
LP000159'un canlı stok/lot uygunluğu ayrıca BC tarafından doğrulanmalıdır.
AL kodu ve BC verileri değiştirilmedi; BC paketi 1.14.1.62 olarak kaldı.
BADE Android sürümü 1.14.146 (200146). Yayın ve kurulum kanıtları
`releases/BADE-1.14.146-TEST-ADAYI` ve `tmp/bade-146-publication` altında tutulur.

## Doğrulama

- 429 BADE release birim testi geçti; bunların 15'i yeni satır planlama
  regresyonudur. 1.14.146 imzalı release derlemesi başarılı.
  Derleme sonucu `tmp/bade-1.14.146-build.log` dosyasındadır.
- BADE release lint: 0 hata, 21 uyarı, 18 bilgi.
- Yeni emülatör testi
  `palletLookupErrorSurvivesWrongScanCorrectBinPalletScanAndReload`: geçti.
  Yanlış LP, yanlış raf, doğru raf, LP ve yenileme sonrasında hata
  korunuyor; onay pasif kalıyor.
- Görsel: `tmp/bade-pallet-error-retained.png`.
- Log: `tmp/bade-pallet-error-validation.log`.
- Önceden mevcut `failedPalletLookupStillShowsScannerAndNeverEnablesConfirmation`
  testi Android 16 emülatöründe klavyenin kapanmasını beklerken zaman aşımına
  uğradı. Üç dosyanın değişiklik öncesi HEAD sürümüyle de aynı kontrol
  başarısız oldu (baseline satır 97); yeni düzeltmeye özgü değil. Klavye
  davranışı bu işte değiştirilmedi. Baseline logu:
  `tmp/bade-pallet-error-ui-baseline.log`.
- Canlı BADE çekme işlemi çalıştırılmadı. Kullanıcının paylaştığı gerçek
  hata, ilgisiz satırın pencereyi durdurmasıyla eşleşmektedir.
