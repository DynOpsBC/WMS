# BADE WMS UAT ve teknik denetim raporu

Tarih: 27.08.2026
Uygulama: `com.dynops.bcwms.bade`
Kurulu sürüm: `1.14.47-bade` / versionCode `1447`
Ortam: `E-DefterSandbox`
Şirket: `BS GROUP ÜRETİM VE KİMYA SAN. TİC. A.Ş.`
Emülatör: Android 16, Medium Phone API 36.1

## Sonuç

BADE için şu anda **“müşteriye yüzde 100 hatasız hazır”** onayı verilemez.

| Katman | Geçti | Başarısız | Engelli | Bilinçli çalıştırılmadı |
|---|---:|---:|---:|---:|
| Otomatik çalıştırılabilen testler | **139** | **0** | 0 | 0 |
| Canlı emülatör UAT senaryoları | **129** | **2** | **12** | **19** |
| Toplam çalıştırılan test | **268** | **2** | - | - |

`Engelli`, canlı BC'de uygun belge/veri veya aktif etiket yazıcısı olmadığı için sonuca ulaşılamayan testi ifade eder. `Bilinçli çalıştırılmadı`, stok veya belge durumunu geri dönüşsüz değiştirecek post/register/transfer işlemleridir. Bu işlemler gerçek/sandbox BC verisini değiştireceği için son onaylarına basılmadı.

Ek envanter:

- 343 statik tıklama noktası incelendi; boş `onClick` handler bulunmadı. Bu sayı “343 test geçti” anlamına gelmez.
- AL tarafında 46 test codeunit içinde 114 `[Test]` prosedürü bulundu. macOS'ta BC/AL test sunucusu olmadığı için derlenip çalıştırılmadı ve başarı sayısına eklenmedi.
- UAT boyunca Android crash buffer boş kaldı; uygulama çökmesi görülmedi.

## Canlı UAT dağılımı

| Modül | Geçti | Başarısız | Engelli | Çalıştırılmadı | Test edilen başlıca işlevler |
|---|---:|---:|---:|---:|---|
| Genel / Ana Menü | 5 | 1 | 0 | 0 | soğuk açılış, oturum geri yükleme, şirket/ortam, şirket seçici, tüm modül rotaları, çökme kontrolü |
| Mal Kabul | 20 | 0 | 1 | 1 | liste, filtre, yenile, arama, detay, kolonlar, miktar, lot, barkod, birleştir, LP başlat/satır/kapat, PO güvenlik kapısı |
| Yerleştirme | 11 | 0 | 0 | 1 | liste, arama, kaynak raf/ürün/hedef raf rehberi, miktar, tam kodla sunucu bin araması, toplu yerleştirme sayısı |
| Toplama V2 | 3 | 0 | 1 | 0 | üç mod, kapsam filtreleri, yenile/arama; açık pick yok |
| Paketleme V2 | 2 | 0 | 1 | 0 | üç mod, yenile, geçersiz LP reddi; paketleme sepeti yok |
| Sevkiyat | 11 | 0 | 1 | 3 | üç sekme, filtre/arama/yenile, pick ve shipment detay, lot/miktar, doğrudan SO güvenlik kapısı |
| LP | 11 | 0 | 1 | 3 | liste, arama, oluşturma formu, detay, geçersiz transfer, kısmi seçenekleri, miktar sınırı, add-line reddi |
| Ad-Hoc Hareket | 8 | 0 | 0 | 1 | LP modu, LP→LP ve LP→bin doğrulama, aynı LP reddi, ürün alanından LP akışına güvenli yönlendirme |
| Yönlendirilmiş Hareket | 3 | 0 | 1 | 0 | filtreler, yenile, arama; açık belge yok |
| Sayım | 7 | 0 | 0 | 3 | liste, arama, yenile, 200 satır/4 raf yükleme, header/line API, buton durumları |
| Sayım V2 | 8 | 0 | 0 | 3 | liste, yenile, hazır belge, geçersiz/geçerli raf, geçersiz QR, yeni belge formu |
| Üretim | 9 | 0 | 0 | 4 | 12 emir/67 bileşen, yenile/arama, detay, kolonlar, sarfiyat ve çıktı formu, bitirme onayı |
| Montaj | 2 | 0 | 1 | 0 | yenile/arama; serbest bırakılmış montaj emri yok |
| Kalite Denetimi | 2 | 0 | 1 | 0 | Açık/Tümü; kalite emri yok |
| MS Kalite | 2 | 0 | 1 | 0 | Sadece Açık/Tümü; denetim kaydı yok |
| Ürün Sorgu | 4 | 0 | 1 | 0 | HM.00025 başlık, stok özeti, LP ve hareket bilgisi; etiket baskısı engelli |
| Bin Sorgu | 5 | 0 | 1 | 0 | MERKEZDEPO/K.K03.11 metadata, 3 ürün, 3 LP, 20 hareket; etiket baskısı engelli |
| Ambar Hareketleri | 4 | 0 | 0 | 0 | son 50 kayıt, filtre paneli, K.K03.11 filtresi, panel aç/kapat |
| Yazıcılar | 4 | 1 | 1 | 0 | liste, yenile, aktif/pasif, belge varsayılanı; aktif etiket yazıcısı yok |
| Nasıl Kullanılır | 5 | 0 | 0 | 0 | arama, kaydırma, konu aç/kapat, LP adımları, doğru modüle yönlendirme |
| Bağlantı / Güncelleme | 3 | 0 | 0 | 0 | sürüm/tarih, uzaktan kontrol, sunucu sürümü |
| **Toplam** | **129** | **2** | **12** | **19** | **162 canlı UAT senaryosu** |

## Canlıda kesin başarısız olan 2 test

### F-01 — Kritik — Şifresiz yönetici geçişi açık

Bağlantı ekranında `Yönetici — Şifresiz, BC hesabıyla devam et` seçeneği görünüyor. Terminali eline alan kişi yerel WMS şifresi olmadan yönetici test oturumu açabiliyor ve belge sahipliği kapısını aşabiliyor.

Kanıt: `feature/LoginFlow.kt:45,97,427-470,532-538`.

### F-05 — Yüksek — Yazıcı ekranı pasif yazıcıyı “hazır” sayıyor

Ekran `TAMAM: 2 yazıcı hazır` diyor; Zebra ZQ630 `Pasif`, Epson yalnız belge yazıcısı ve aktif bir ZPL etiket yazıcısı yok. Bu nedenle etiket varsayılanı seçilemiyor. LP, ürün ve bin etiketi saha testleri tamamlanamıyor.

Kanıt: `feature/PrintersModule.kt:70-81,225-245`.

## Bu turda çözülen 3 test

- **F-02 çözüldü:** Bin seçici artık ilk 200 satırda olmayan tam raf kodunu lokasyon + kod ile BC sunucusunda doğruluyor. Emülatörde `Y.G03.12` için `TAMAM: Y.G03.12 rafı sunucuda bulundu` sonucu ve seçilebilir raf kartı görüldü.
- **F-03 çözüldü:** Toplu yerleştirme Take/Place satırlarını iki satır değil tek depo hareketi olarak sayıyor. PU000570 üzerinde `1 yerleştirmenin...` ve `Tümüne Uygula (1)` doğrulandı.
- **F-04 çözüldü:** Ürün modunda okutulan LP, boş `itemNo` ile `movementOps.adHoc` çağrısına gitmiyor; atomik LP akışına yönlendiriliyor. `K.K03.11` kaynak rafında ürün alanına okutulan `LP000032`, otomatik `LP ile` moduna geçti ve 1 LP satırını yükledi. Stok değiştiren son onay verilmedi.

## Canlıda doğrulanan önemli başarılı akışlar

- Mal kabul RE000621 listelendi, HM.00025 satırı/lotu yüklendi, geçerli ürün taraması miktar penceresini açtı.
- Mal kabulde LP başlatma çalıştı: `LP000032` oluştu; 500 KG HM.00025 / lot H100773 satırı bağlandı; LP kapatılıp Built durumuna geçti; SSCC `099999990000000232` oluştu.
- Mal kabul post edilmedi. Item ledger/warehouse entry yaratılmadı.
- Yerleştirmede yanlış kaynak raf reddedildi; `K.K03.11 → AB.00812 → Y.G03.12 → 50` rehberi son onay öncesine kadar geçti.
- LP modunda Ad-Hoc `LP000032 → LP000030` ve `LP000032 → Y.G03.12` son onay öncesine kadar doğrulandı.
- Sayım belgesi `CNT-20260825172015` uygulamada 200 satır ve 4 rafla açıldı. Header ve line endpointleri ayrı ayrı HTTP 200 döndü.
- Sayım V2 `CNT-20260826112720` hazır açıldı; geçersiz raf reddedildi, `DO.01` kabul edildi, miktarsız QR doğru mesajla reddedildi.
- Üretimde 12 emir/67 bileşen yüklendi; RLO.A100773 sarfiyat ve çıktı formları açıldı, geri dönüşsüz onaylar verilmedi.
- Ürün sorguda HM.00025; bin sorguda MERKEZDEPO/K.K03.11; ambar hareketlerinde son 50 kayıt yüklendi.
- Güncelleme kontrolü çalıştı ve son kontrol tarihini yeniledi.

## Çalıştırılmayan veya engellenen son işlemler

Bu işlemler “çalışıyor” olarak onaylanmamıştır:

- Mal kabul post, yerleştirme register, pick register, shipment create-pick ve shipment post.
- Gerçek LP transferi, gerçek kısmi LP işlemi, unbuild/delete ve gerçek Ad-Hoc stok hareketi.
- Klasik sayım kayıt/yeniden say, Sayım V2 geçerli ürün QR kaydı/undo/post.
- Üretim pick oluşturma/sarfiyat/çıktı/emir bitirme.
- Montaj post, kalite kabul/red, MS Quality test/bitir/blok işlemleri.
- Fiziksel LP/ürün/bin etiketi ve belge baskısı.

Nedenler:

1. Post/register/transfer işlemleri BC stok ve belge durumunu geri dönüşsüz değiştirir.
2. Bazı modüllerde uygun açık belge/sepet bulunmuyor.
3. Aktif ZPL etiket yazıcısı yok.

## Kod denetiminde bulunan, canlı test başarısızlığı sayısına dahil edilmeyen riskler

1. **Kritik — mal kabul retry/çoklu LP veri sapması:** receipt satırı mutlak `Qty. to Receive` ile ezilirken her tekrar LP'ye yeni tam miktarlı satır ekleyebilir. Çoklu palet senaryosu ilk LP'ye damgalanabilir (`ReceiptMgmt.Codeunit.al:279-304`).
2. **Yüksek — aktif mal kabul LP'si yalnız Compose belleğinde:** uygulama kapanırsa aktif LP geri yüklenmez (`ReceivingModule.kt:171`). İlk satırdan önce çıkış yetim LP oluşturabilir.
3. **Yüksek — `touched` işlem durumu yalnız bellekte:** mal kabul/doğrudan PO/SO ekranına yeniden girildiğinde önceki oturumdaki miktarlar yanlışlıkla “dokunulmadı” sayılabilir (`ReceivingModule.kt:181,490-499,879`).
4. **Yüksek — seri takipli mal kabulda miktar 1 zorunluluğu yok:** tek seri numarası qty>1 satıra uygulanabilir (`ReceivingModule.kt:526-612`).
5. **Yüksek — mal kabul ataması izin ve sahiplik açısından zayıf:** Warehouse Employee eşleşmesi yoksa atama/LP başlatma reddedilebilir; mevcut sahibin belgesi kilit/sahip kontrolü olmadan devralınabilir.
6. **Yüksek — Ad-Hoc kaynak LP lokasyon açısından belirsiz:** kaynak LP listesi yalnız bin koduna göre daralıyor; farklı lokasyonlarda aynı bin kodu varsa yanlış LP seçilebilir.
7. **Yüksek — seri takibi eksikleri:** Picking API seri bilgisini uçtan uca taşımıyor; yönlendirilmiş harekette tek seriyle qty>1 girilebilir.
8. **Yüksek — Üretim çıktı ve Montaj lot/seri desteklemiyor:** formlarda lot/seri alanı yok; takipli ürün postu reddedilebilir veya yanlış izleme yaratabilir.
9. **Orta/Yüksek — MS Kalite capability/atama kapısı yok:** menü her ortamda görünüyor; unassigned denetim için `Bana Ata` yok; repo AL hedefi ile beklenen Microsoft Quality API sürümü aynı değil.
10. **Yüksek — permission-set riski:** yalnız `DOPSWHS-USER` atanırsa Receipt Line modify ve bazı Count delete yetkileri eksik olabilir.
11. **Orta — Yardım metni canlı V2 akışlarından sapıyor:** Picking/Paketleme/Sayım düğme adları ve adımları mevcut V2 ekranlarıyla birebir aynı değil.
12. **Orta — dar terminalde taşma riski:** uzun ekran başlıkları, alt aksiyon satırları ve grid kolonları için adaptif wrap/ellipsis her yerde yok. Üretim gridindeki `PÜ No.` kolonu canlıda çok dar kaldı.

## Güncelleme durumu

- Terminalde: `1.14.47-bade` / `1447`.
- Uzaktan manifestte: `1.14.46-bade` / `1446`.
- Uygulamanın kontrol butonu doğru çalışıyor ve yerel sürüm daha yeni olduğu için `Uygulama güncel` diyor.
- Ancak 1.14.47 APK/manifest uzaktaki yayın kanalına alınmadığı için başka terminaller son yerel sürümü henüz indiremez.

## Otomatik test kanıtları

- Android BADE JVM testleri: 126/126 geçti.
- Web Playwright: 3/3 geçti.
- Push relay: 10/10 geçti.
- Bu düzeltme turundaki Gradle testi/lint/APK derlemesi: 92/92 görev, `BUILD SUCCESSFUL`.
- Lint: 0 error/fatal, 72 warning, 13 info.
- Release APK package/sürüm: `com.dynops.bcwms.bade`, `1.14.47-bade`, `1447`.
- Release APK SHA-256: `18583ba59bd526dfdf846ce2df19099c13c8e9df82784e4b90a435106dee2335`.
- Düzeltmelerin kurulduğu debug APK SHA-256: `5cf53f64d51c90759862803cf3fe76bccd5105c170e94728423f96b8d3b8987f`.

Kanıt dosyaları:

- `android/app/build/reports/tests/testBadeDebugUnitTest/index.html`
- `android/app/build/test-results/testBadeDebugUnitTest/`
- `android/app/build/reports/lint-results-badeDebug.html`
- `android/app/build/reports/lint-results-badeDebug.xml`
- `android/app/build/outputs/apk/bade/release/app-bade-release.apk`
- `android/app/build/outputs/apk/bade/release/output-metadata.json`

## Test verisi notu

Bu turda E-DefterSandbox üzerinde geri dönüşsüz posting yapılmadı. Ancak mal kabul LP başlangıç/satır/kapat akışını gerçekten doğrulamak için RE000621 üzerinde 500 KG staged miktar bırakıldı ve `LP000032` Built durumunda oluşturuldu. Bu bir test artefaktıdır. Temizlenmesi istenirse belge/LP hedefi ayrıca doğrulanmalı ve açık kullanıcı onayıyla yapılmalıdır.

F-02, F-03 ve F-04 kaynak kodda düzeltildi; debug APK emülatöre güncelleme olarak kurulup canlı ve mutasyonsuz UAT ile doğrulandı.
