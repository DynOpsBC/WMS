# BADE 1.14.122 — Sayımda bulunan stok: satır oluşur, kayıtta eski raftan taşınır (BC 1.14.1.47)

Android: **1.14.122-bade**, versionCode **200122**. BC: **BCWMSApp 1.14.1.47**. 1.14.121 / 1.14.1.42–46'daki her şey bu pakette de vardır.

## Merve (16 Eyl 18:20, Teams)

"O rafta o ürün var aslında ama BC'de yok. Ürünü o rafa okuttuğumda terminal 'böyle bir madde yok' diyor. Konuştuğumuz gibi
satır yine oluşsun; ürün sistemde başka yerdeyse oraya taşınsın."

## Terminal (Sayım V2)

- BC'de bu rafta stoğu olmayan ürün okutulduğunda "Bu rafta bulduğunuz miktar" penceresi açılır (eskisi gibi); durum satırı artık
  ürünün BC'de kayıtlı olduğu rafları yazar: "BC'de A.B01.01 (500), A.B02.03 (20) rafında kayıtlı. Burada bulduğunuz miktarı girin;
  kayıtta stok o raftan bu rafa taşınır." Hiçbir rafta yoksa: "… hiçbir rafında kayıtlı değil … artı sayım farkı olur."
- Barkod BC'de madde numarası değilse (GTIN vb.) mesaj açık: "'X' BC'de madde numarası olarak bulunamadı. Ürünün BCWMS etiketini
  (madde no) ya da LP/lot etiketini okutun; barkod GTIN ise BC'de madde referansı tanımlı olmalı." Merve'nin gördüğü "böyle bir
  madde yok" bu duruma karşılık gelir: okutulan barkod BC madde numarası değildi.

## BC: Kurulum → **Count Relocates Found Stock** (yeni, varsayılan kapalı — BADE'de AÇILMALI)

Açıkken sayım kaydında (`Count Mgmt.PostSheet` → `RelocateFoundStock`): "Unexpected Stock" satırları için (BC'de o rafta stok yok,
sayımda bulundu) stok, aynı madde/lot/serinin BC'de durduğu ve **bu sayımda sayılmayan** raflardan bu rafa taşınır
(`Movement Mgmt.AdHocMoveTrackedAtLocation`: yönlendirilmiş lokasyonda ambar reclass, değilse madde reclass; lot/seri izlemeli).
Yalnız LP'ye bağlı olmayan (serbest) stok taşınır; en çok stoğu olan raftan başlar. Taşınan miktar satırın System Qty'sine
eklenir; kalan fark eskisi gibi fiziksel envanter artısı olur. Satırda **Moved From Bin / Moved Qty** görünür (çoklu kaynak: MULTI).
Aynı sayımda sayılan raflar taşıma kaynağı olmaz; oradaki eksik fiziksel envanter kaydında zaten düşer. Kapalıyken eski davranış.
Varyantlı satırlar ve LP satırları bu adıma girmez.

## Bu pakette ayrıca

- MTE ZPL etiketi 4×6 inç (100×150 mm) düzenine alındı (paralel çalışma, `MTE Zpl Builder`).

## Doğrulama

- alc 0 hata; al-tests projesi de derlendi. Android: BADE birim testleri tümü geçti (yeni: raf ipucu), lint 0 hata, imzalı APK 200122.
- Canlı BC testi yok. Saha kontrolü: Kurulum'da anahtarı aç → sayımda BC'de olmayan ürünü okut → miktar gir → sayımı Post et →
  eski rafta stok azalmış, yeni rafta artmış, satırda Moved From Bin dolu olmalı.

## Dosyalar

`output/release-bade-1.14.122/`: `BCWMS-BADE-1.14.122-RELEASE.apk`, `BCWMSApp-1.14.1.47.zip`, `latest.json`, `SHA256SUMS.txt`.
