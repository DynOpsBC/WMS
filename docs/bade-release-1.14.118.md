# BADE 1.14.118 — Terminal MTE = BS Group'un kendi etiketi, ek alanlarla (BC 1.14.1.39 + BadeProduction 1.3.3.13)

Android: **1.14.118-bade**, versionCode **200118**. BC: **BCWMSApp 1.14.1.39** ve **BadeProduction 1.3.3.13**
(ikisi de yüklenmeli). 1.14.116/1.14.1.38'deki düzeltmeler bu pakette de vardır.

## Merve'nin bildirimi (16 Eylül 08:40)

Terminal/BCWMS için yapılan MTE raporu (72375), BS Group'un güncelde kullandığı etiketin kopyası değildi:
madde kategorisi, INCI adı, tedarikçi adı, depolama koşulu farklı kaynaklardan geliyor; "Giriş Yapan",
Kalite Kontrol Onayı, Doküman/Revizyon alanları etiket alınırken doldurulamıyordu.

## Çözüm: kopya yerine müşterinin raporu

- **BadeProduction 1.3.3.13** (rapor 60150 "Madde Tanımlama Etiketi"): istek sayfasına **LP No. Filtresi**
  eklendi (dolu ise yalnız o paletin etiketi basılır); "Kontrol Eden / Onaylayan" başlığı **Giriş Yapan** oldu;
  uzantı düzenindeki başlıklar da "GİRİŞ YAPAN" / "KONTROL EDEN" olarak düzeltildi. 1.3.3.12'deki çoklu LP
  döngüsü korunur. BC'de seçili özel düzen aynen kullanılır.
- **BCWMS 1.14.1.39**: Kurulum → **MTE Report ID** (BADE'de **60150** yazılacak). Terminaldeki MTE, paletin kaynak
  madde defteri girişleriyle bu raporu çalıştırır; operatörün girdiği ek alanlar rapora istek parametresi olarak
  geçer. Rapor bulunamazsa veya alan boşsa eski BCWMS raporu, yazıcı ZPL ise 4×2 ZPL MTE basılır.
  LP API: `printMte(printerId, copies, optionsJson)`, `listEmployees()`.
- **Terminal 1.14.118**: LP kartında **MTE Yazdır** önce ek alanları sorar — Giriş Yapan (çalışan listesi),
  Tedarikçi Lotu, Kalite Kontrol Onayı İsim/Tarih, Doküman No, Revizyon No, Revizyon Tarihi; "Alanları boş
  bırak, yazdır" kestirmesi var. Çıktı PDF olduğu için cihazın **Belge** yazıcısı kullanılır (yoksa etiket
  yazıcısına ZPL MTE gider).


## Terminal ZPL MTE = rapor formatı (aynı gün, 12:10)

Merve'nin fotoğrafı Zebra'da **10×8 cm** etiket takılı olduğunu gösterdi; eski ZPL MTE etiketin yalnız üst 5 cm'ini
kullanıyordu. `DOPSWHS MTE Zpl Builder` (72320) etiketi raporun düzeniyle çiziyor: kutu tablo (MADDE KODU / KATEGORİSİ,
MADDE ADI, INCI ADI, TEDARİKÇİ ADI / LOTU, ÜRETİM TARİHİ, LOT NO, SKT, MİKTAR/BİRİM, DEPOLAMA KOŞULU, DEPO GİRİŞ
TARİHİ / NO., GİRİŞ YAPAN, KALİTE KONTROL ONAYI: KONTROL EDEN / TARİH / İMZA), KABUL / RED / KARANTİNA kutuları, QR
(LP no) ve DOKÜMAN / REVİZYON alt satırı. Veriler raporla aynı kaynaklardan: üst kategori, Item "INCI Name"
(isimle okunur), alış irsaliyesi tedarikçisi, "Vendor Item Name", ambar sınıfı açıklaması, Lot No. Information,
posted ambar mal kabul no; miktar Türkçe biçimde (1.030 ADET). Terminalde girilen ek alanlar ZPL etikete de basılır.
Önizleme: `docs/labels/bade/mte-zpl-10x8.png`. Bu yol için belge yazıcısı gerekmez; Zebra "Etiket" olarak kalır.
Fark: BS Group logosu ZPL'de yok, yerine şirket adı yazılır.

## Kurulum sırası

1. BadeProduction 1.3.3.13'ü yükle.
2. BCWMS 1.14.1.39'u yükle; Kurulum → MTE Report ID = 60150.
3. Yazıcılar: MTE'nin bugün BC'den basıldığı Windows yazıcısı ajanda **Belge** olarak seçili ve terminalde
   "Belge" olarak işaretli olmalı (PDF).
4. Terminal 1.14.118.

## Depo gözü "Güncel LP No.ları" (Merve, 09:39)

Bağımsız doğrulama (4 analiz + 3 çürütme denemesi, hepsi aynı sonuçta): özet alan ve açılan "Güncel LP Dağılımı"
birebir aynı filtreyi okur (`BinContentSubscriber.FilterActiveLPItemLines`); aynı veri için farklı LP dönmeleri
mümkün değil. Fark, liste satırının iki transfer arasında hesaplanıp yenilenmemesi: değer sayfa değişkeni, açılan
pencere ise her tıklamada canlı okur. Miktar iki durumda da 380 olduğu için bayatlık miktardan belli olmuyor.
Kontrol: Bin Contents'te F5 → LP000005 / 380 görünmeli; LP000002 kartı Built, A.Z11.41, satır 0.

Yapılanlar:
- Bin Contents: açılan pencere kapanınca satır yeniden hesaplanır (`CurrPage.Update`), ipucu metni "F5 ile yenileyin" oldu.
- **Gerçek hata (doğrulama sırasında bulundu, bu olayla ilgisiz):** iki veya daha çok satırlı bir LP'nin transferi
  "record already exists" ile başarısız oluyordu (`LPManagement.Transfer` döngüde `Init()` birincil anahtarı
  sıfırlamadığı için ikinci satır ilk satırın numarasını alıyordu; toplama böl yolunda da aynı desen). Düzeltildi
  (`Clear(TargetLine)`), iki satırlı transfer testi eklendi. LP000005 tek satırlı olduğu için Merve bunu görmedi.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| alc BCWMSApp 1.14.1.39 | 0 hata |
| alc BadeProduction 1.3.3.13 | 0 hata |
| JVM testleri BADE / EMU flavor | 349 / 349 (3 yeni: tarih normalizasyonu, ek alan JSON'u, yazıcı seçimi) |
| Emülatör UI testleri | 31 geçti |
| Lint | 0 hata, 77 uyarı |
| APK 200118 / 1.14.118-bade | Aynı sertifika, emülatörde 1.14.116 üzerine kuruldu |

BC ortamında çalıştırılmadı: 60150 raporunun istek parametreleriyle (LP filtresi, ek alanlar) terminalden
çağrılması ilk gerçek MTE baskısında doğrulanmalı.
