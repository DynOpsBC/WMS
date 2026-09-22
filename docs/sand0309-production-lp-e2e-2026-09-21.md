# sand0309 production LP acceptance — 2026-09-21

Environment: `sand0309`  
Company: `BS İlaç Kozmetik San.Tic.A.Ş.`  
BCWMSApp: `1.14.1.64`  
Android: `1.14.150-bade`  
Code commit: `b4df3eef11e4567ba56dd5f0823a5181b2093684`

## Sequential production LP

The existing warehouse pick `PI001729` for released production order
`RLO.B100845` already contained 100 handled units from `LP000070`. The open
take/place lines for item `AB.00150`, lot `A101787`, still held the historical
LP reference and 26,188 outstanding units. This is the original failure state.

1. Created `LP000072` from item ledger entry `8183`, source bin `A.TOPLAM`,
   quantity 100.
2. Called `createPickFromLpFor` for `RLO.B100845` and `LP000072`.
   The existing pick `PI001729` was returned and its active scope became exactly
   100 units for `LP000072`; the historical 100 handled units did not block it.
3. Called `registerScannedFor` with an empty pallet plan. BC rejected it with
   HTTP 400: `Kaydedilecek doğrulanmış palet satırı yok.` No movement occurred.
4. Registered the exact scanned plan for take line 30000, source bin
   `A.TOPLAM`, LP `LP000072`, lot `A101787`, base quantity 100. BC returned
   HTTP 204.
5. Read-back verified that `LP000072` is in bin `DO.01`, status `Assigned`,
   document type `ProdConsumption`, document `RLO.B100845`. Its one content
   line remains 100 units and keeps source item ledger entry `8183`.
6. Pick read-back shows handled quantity 200 and outstanding quantity 26,088
   for both take and place lines. Item ledger entry `8183` references both
   `LP000070` and `LP000072`.

Result: **PASS**. A second prepared LP can be moved to production against the
same production order after an earlier LP has already been registered.

## One LP from multiple stock entries

The customer screenshot entries `12435` and `1042` could not both be replayed
in this sandbox: entry `1042` exists, while entry `12435` is absent. The same
acceptance case was run with two current compatible entries:

- `3807`: item `YM.00038`, lot `204BS6024`, 20 KG
- `3805`: item `YM.00038`, lot `204BS6024`, 40 KG

`createSingleLicensePlateFromEntriesIdempotent` created one pallet,
`LP000071`, with total quantity 60 KG and two content lines. Each line retains
its exact source item ledger entry and requested quantity. Repeating the same
request ID returned `replayed=true` and did not create another LP. Both source
entries now reference `LP000071` and have zero LP-allocatable balance.

Result: **PASS**. Compatible stock entries selected together produce one LP,
with source traceability and idempotent retry behavior.

## Package and automation status

- Android build, unit tests and lint: PASS (409 tests)
- Windows AL compile and tests: PASS
- Custom API metadata exposes `createSingleLicensePlateFromEntriesIdempotent`
- Android APK connected to `sand0309` and loaded terminal/user data
- Android CI: <https://github.com/DynOpsBC/WMS/actions/runs/35620382224>
- Windows AL CI: <https://github.com/DynOpsBC/WMS/actions/runs/35620416210>
- Prerelease: <https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.150-bade>

The emulator reached the BADE terminal PIN screen. A full tap-through under a
terminal operator was not performed because no valid operator PIN was supplied;
the state-changing acceptance checks above were executed directly against the
same published Business Central API and read back from `sand0309`.


---

## Önceki 1.14.149 UI test kaydı (tarihsel)

Aşağıdaki kayıt önceki sürümün yerel test notudur; yukarıdaki 1.14.150 kabul kaydının yerine geçmez.

# sand0309 üretim LP çekme testi — 21 Eylül 2026

Sonuç: **GEÇTİ — tek ürün, tek lot, tam LP ile üretime ambar çekme senaryosu.**

BCWMSApp 1.14.1.63 sandbox'ta kurulu görüldü. Bilgisayardaki Android emülatörü BADE 1.14.149 (200149) APK'ya güncellendi; sand0309 ortamında TERMİNAL-1 / KAAN ODABAS ile test edildi. BC doğrulaması kullanıcının açık Safari oturumunda CUA ile, terminal işlemleri Playwright Android üzerinden yapıldı.

## Uygulanan işlem

- Sandbox'taki hazır AB.00175 LP'leri için Released üretim bileşeni bulunmadığından mevcut AB.00150 stokundan bir test LP'si hazırlandı.
- LP000070: 100 ADET AB.00150, lot A101787, SSCC 099999990000000676, kaynak madde defter girişi 8183, kaynak belge 107736, MERKEZDEPO / A.TOPLAM. Etiket baskısı kapatıldı.
- RLO.B100845 → Hazır LP ile Ambar Çekme → LP000070 önizlemesinde hedef MERKEZDEPO / DO.01 doğrulandı.
- PI001729 oluştu. AB.00150 için işlenecek miktar 100; diğer bileşenlerin miktarı 0 kaldı.
- Okutma öncesi kayıt denemesi doğrulama hatasıyla engellendi (REF-097A1B8A).
- A.TOPLAM rafı ve LP000070 okutuldu; 1/1 palet doğrulandı.
- Toplamayı Kaydet işlemi “Toplama kaydedildi.” ile tamamlandı.

## BC'den bağımsız doğrulama

| Kontrol | Sonuç |
| --- | --- |
| LP numarası / SSCC | LP000070 / 099999990000000676 korundu |
| Ürün / lot / miktar | AB.00150 / A101787 / 100 ADET korundu |
| Kaynak giriş / belge | 8183 / 107736 korundu |
| LP rafı | A.TOPLAM → DO.01 |
| LP ataması | Production Consumption / RLO.B100845 |
| LP hareket kaydı | 327: Moved, A.TOPLAM → DO.01, PROD:RLO.B100845/PICK:PI001729 |
| LP emir bağlantısı kaydı | 328: Assigned, PROD:RLO.B100845/PICK:PI001729 |
| AB.00150 üretim bileşeni çekilen miktar | 3.712 → 3.812 |
| AB.00150 tüketim miktarı | 3.712; bu işlemde sarfiyat oluşmadı |
| AB.00150 bekleyen çekme miktarı | 26.288 → 26.188 |

Terminal yeniden açılan LP listesinde de LP000070 / MERKEZDEPO / DO.01 / 100 adet gösterdi. Test sonucu için LP ve kalan PI001729 çekmesi sandbox'ta bırakıldı. Production ortamına işlem yapılmadı.

## Kapsam sınırı ve kanıtlar

Bu gerçek UI testi tek operatör, tek ürün, tek lot ve tam LP senaryosunu doğrular. Eşzamanlı operatör, karışık lot, kısmi LP, iptal ve canlı PI001945 bu çalıştırmada denenmedi. Daha önce derlenen 41 AL regresyon testi BC'de çalıştırılmış değildir. Bu sonuç tüm canlı senaryolar için sıfır hata garantisi değildir.

Kanıtlar: `tmp/sand0309-production-lp-e2e/test-progress.json`, `lp000070-before.png`, `ready-lp-preview.png`, `pick-created-scoped.png`, `unscanned-register-rejected.png`, `lp-scan-validated.png`, `registration-result.png`, `lp000070-after.png`.
