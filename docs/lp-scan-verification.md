# LP okutmalı toplama ve yerleştirme

BADE saha kuralı: paletin üzerinde okutulabilir tek barkod, Madde Tanımlama
Etiketi'nin **LP numarası taşıyan QR kodudur**. Operatör ürün barkodu
okutamadığı için "doğru ürünü aldım/koydum" kanıtı yalnızca okutulan paletin
**içeriğinin** ambar aktivitesi satırıyla karşılaştırılmasıyla üretilebilir.

Etiketin kendisi değişmedi: `DOPSWHS Print Dispatcher.BuildPalletItemZpl`
aynen korunur.

## Açma/kapama anahtarı

Kurulum kartı → **LP Scan Required** (`DOPSWHS Setup` alan 430).

| Durum | Davranış |
|---|---|
| Kapalı (varsayılan) | Bu paketten önceki akış. Kaynak LP isteğe bağlı, yerleştirmede ürün okutulur |
| Açık | Toplamada kaynak LP zorunlu; yerleştirme LP okutmasıyla doğrulanır ve ürün okutma adımı gösterilmez |

Anahtar **varsayılan kapalıdır**: yükseltme mevcut kurulumların davranışını
değiştirmez. Sahada bir sorun çıkarsa kutu kapatılarak eski akışa tek adımda
dönülür; yeni paket yayınlamak gerekmez.

> Anahtarı **yalnız yeni APK terminallere indikten sonra** açın. Açıkken eski
> APK'nın kullandığı `setPlacement` ucu paletsiz yerleştirmeyi reddeder.

## Sunucu tarafı

`DOPSWHS LP Verification` (codeunit 72216) tek doğrulama noktasıdır: paletin
durumu, başka belgeye ayrılmamış olması, lokasyonu, rafı, maddesi, varyantı,
lotu ve serisi satırla karşılaştırılır. Hata mesajı paletin gerçekte ne
taşıdığını yazar.

Yönlendirilmiş hareket (Movement) modülündeki eşdeğer doğrulama
(`DOPSWHS Movement Mgmt.ValidateDirectedSourceLp`) **değiştirilmedi**. Sahada
çalışan o akışı bozmamak için bilinçli olarak ayrı bırakıldı; birleştirmek ayrı
bir iştir.

| Uç | Ne yapar |
|---|---|
| `picks({no})/pickLineSources(lineNo)` | Satır için okutulabilecek paletleri raf + palet sırasıyla döndürür. Salt-okunur |
| `picks({no})/confirmLine(..., sourceLpNo, ...)` | `sourceLpNo` zorunluluk açıkken şart. Okutulan palet satırla karşılaştırılır |
| `putAwayLines(...)/setPlacementFromLp(targetBinCode, qtyToHandle, sourceLpNo, userId)` | LP doğrulamalı yerleştirme. Eski `setPlacement` korunur |
| `itemLedgerEntries(...)/createLicensePlatesFromPlanIdempotent(..., quantityLastLp, ...)` | Tam paletler + tek artık palet, tek işlemde |

### Toplamada tam kapsama ARANMAZ

Okutulan paletin toplama satırının tamamını karşılaması şart değildir. Bir satır
birden çok palete yayılabilir; okutulan palet yalnız tahsisin nereden
başlayacağını belirler (`ResolvePickSourceLp`) ve kalan miktar kayıt sırasında
aynı raftaki diğer paletlerden deterministik olarak tamamlanır
(`TransferPickedQuantityFromAvailableLps`). Burada tam kapsama şartı koymak çok
paletli toplamayı imkânsız kılardı.

Yerleştirmede durum farklıdır: bir palet bir yerleştirmedir, bu yüzden miktar
paletin taşıdığıyla sınırlanır.

## Terminal tarafı

Terminal iki bilgiyi sunucudan okur ve ikisi de yoksa eski akışa döner:

- `appUserProfiles('DEFAULT')/resolveCurrent` → `lpScanRequired`
- OData `$metadata` → yeni action'ların yayında olup olmadığı
  (`BcApi.getLpScanCapabilities`)

Yani **yeni APK, eski BC paketine tanımadığı bir işlem göndermez.** Bu, sayım
modülündeki mevcut yetenek yoklama deseninin aynısıdır.

Ayar 5 dakikalık bir önbellekle tutulur: BC'de kapatıldığında terminal yeniden
giriş beklemeden eski akışa döner.

## Toplu LP planı

Operatör yalnız palet kapasitesini girer. Tam palet adedi ve son paletteki artık
miktar `planLedgerLps` ile hesaplanır ve ekranda gösterilir:

```
Plan: 10 × 1.000 + 1 × 350 = 10.350 ADET (11 LP)
LP'lenebilir kalan: 10.350 ADET
```

LP adedi düzenlenebilir kalır. Operatör adedi düşürürse bilerek stoğun bir
kısmını paletliyor demektir ve artık palet oluşturulmaz.

Tekrar denemede ilk çağrının ucu kullanılır; işlem kaydı (`DOPSWHS LP Bulk
Request`) artık paleti de saklar ve değişmezdir.

## Test durumu

- AL denetimleri (izin, prefix, obsolete, çeviri, posting alanları) geçer.
- Android birim testleri: `LpScanVerificationTest`, `LpScanCapabilitiesTest`.
- **Gerçek el terminali ve fiziksel okuyucu ile uçtan uca kabul yapılmamıştır.**
  Sunucu doğrulaması (madde/lot/raf) yalnız BC ortamında sınanabilir.
