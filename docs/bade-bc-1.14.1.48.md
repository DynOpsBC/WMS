# BADE BC 1.14.1.48 — Sayımda bulunan stok: eksi+artı yerine tek raf taşıması (Android değişmedi, 1.14.122 kalır)

BC: **BCWMSApp 1.14.1.48** (`output/release-bade-bc-1.14.1.48/BCWMSApp-1.14.1.48.zip`). Android: 1.14.122 aynen.

## Merve (17 Eyl 10:28, Teams)

"Şöyle saydım diyelim: üründen saydığım rafta yok, onu post ettim. Onun bir pozitif girişi oldu. Ama o ürün BC'de başka
rafta görünüyor ve aslında bir satınalma ile girmiş stoğa. Hem pozitif girişi oldu hem satınalma girişi oldu."

## Kodda 1.14.1.47'de olan (Merve'nin senaryosunu izleyince bulundu)

- Sayım V2 kapsam kuralı (`EnsureV2BinCoverage`, önceki oturumların tasarımı): bir rafta sistemden FAZLA çıkan ürün için
  BC'nin o ürünü (aynı lot/birim) tuttuğu diğer raflar sayıma "tohumlanır" ve o raflar sayılmadan Post edilemez
  ("Related bins are only seeded, never counted or deducted automatically"). Yani Merve'nin senaryosunda post, A rafı
  sayılmadan zaten geçmiyordu; A 0 sayılınca sonuç **A −100 / B +100** = iki ayarlama hareketi (satınalma girişi kalır,
  yanına eksi ve artı gelir). Stok ikilenmez ama Merve'nin istediği "taşıma" değildir.
- 1.14.1.47'deki `RelocateFoundStock` taşımayı yalnız **sayımda satırı olmayan** raflardan yapıyordu; kapsam kuralı kaynak
  rafı her zaman sayıma soktuğu için standart senaryoda taşıma HİÇ çalışmıyordu (ölü kod).
- Bölge filtreli sayımda (terminalde "alan" seçilerek açılan fiş) fazla çıkan ürün BC'de BAŞKA bölgenin rafındaysa
  `CompleteV2Bin` (Rafı Bitir) `BinOutsideZoneFilterErr` ile düşüyordu: operatör rafı kapatamıyordu.

## 1.14.1.48

- `Count Mgmt.PlanFoundStockRelocations` (yeni, testlenebilir): Kurulum **Count Relocates Found Stock** açıkken post
  anında her LP'siz fazla satır için sırayla:
  1. **aynı fişte eksik sayılan** aynı madde/lot/seri satırları (tohumlanan kaynak raf; operatör orada yok/az dedi) —
     eksik kadar ve o raftaki serbest stok kadar **tek raf taşıması** (yönlendirilmiş lokasyonda ambar reclass, değilse
     madde reclass). İki satırın da System Qty'si taşımayla güncellenir → fiziksel envanter kaydına eksi/artı KALMAZ,
     satınalma girişi tek hareket olarak kalır.
  2. kalan fazla için fiş dışındaki (ör. başka bölge) raflardan, en büyük bakiyeden başlayarak.
  Karşılanamayan kısım eskisi gibi artı düzeltme. Satırda Moved From Bin / Moved Qty (çoklu: MULTI).
  Kaynak raf kısmen doluysa (sistem 5, sayılan 2, bulunan 5) yalnız eksik 3 taşınır; kalan 2 gerçek fazladır.
- Kapsam kuralı: bölge filtresi dışındaki ilgili raf artık hata yerine **atlanır**. Anahtar açıkken post'ta oradan
  taşınır; kapalıyken burada artı, o bölgenin kendi sayımında eksi olur.
- Kurulum açıklaması güncellendi. Anahtar kapalıyken (varsayılan) davranış 1.14.1.47 ile aynı: eksi+artı.
- LP satırları ve varyantlı satırlar taşıma adımına girmez (başka rafta bulunan LP eskisi gibi eksi/artı).

## Doğrulama

- alc 0 hata; al-tests derlendi. Yeni testler (`CountV2Tests`): `ZoneCountSkipsRelatedBinOutsideZoneFilter`,
  `RelocationPlanPairsSurplusWithCountedShortfall`, `RelocationPlanMovesOnlyTheShortfallWhenSourceStillHoldsPart`,
  `RelocationPlanUsesUncountedBinOutsideZoneFilter`. Bu Mac'te AL testleri çalıştırılamaz (yalnız derleme).
- Canlı BC testi YOK. Saha senaryosu: Kurulum'da anahtarı aç → sayımda B rafında BC'nin A'da bildiği ürünü okut, miktar gir
  → Rafı Bitir → terminal "bekleyen rafları da sayın" der, A rafını aç, boş ise Rafı Bitir → Post → Ambar hareketlerinde
  A→B taşıma, madde defterinde YENİ hareket yok, sayım satırında Moved From Bin = A.

## Dosyalar

`output/release-bade-bc-1.14.1.48/`: `BCWMSApp-1.14.1.48.zip`, `SHA256SUMS.txt`. Yayınlanmadı (kullanıcı isteyince GitHub
release'e eklenecek).
