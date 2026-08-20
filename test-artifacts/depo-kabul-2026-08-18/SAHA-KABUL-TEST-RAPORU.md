# BADE WMS El Terminali — Saha Kabul Test Raporu

**Test tarihi:** 18.08.2026  
**Ortam:** `sand1506`  
**Şirket:** `BADE NATURAL DOĞAL YAŞAM ÜRÜNLERİ SAN. TİC. A.Ş.`  
**Uygulama:** `com.dynops.bcwms.bade`, V2  
**Terminal:** Android emulator, 1080 × 2400  
**Operatör:** `KAANODABAS`  
**Test türü:** Gerçek API/BC kayıtlarıyla uçtan uca saha kabul testi

## 1. Yönetici özeti

**Canlı depo kullanımı için sonuç: KOŞULLU NO-GO.**

Multi toplama ve üç satış siparişinin paketlenmesi uçtan uca tamamlandı. Pick kaydı post edildi, paketleme oturumu `Completed` oldu ve üç sipariş için sevkiyat ile fatura kayıtları oluştu. Buna rağmen canlı kullanımı engelleyen dört kritik sorun bulundu:

1. Paketleme kapanışında terminal üç defa da `timeout` gösterdi; sunucu işlemi gerçekte tamamladı.
2. Aynı koli barkodu iki farklı müşteri siparişinde kabul edildi.
3. Test edilen pick'in bütün satırlarında raf/bin boştu; depocu ürünü nereden alacağını göremiyor.
4. Mono ve Tek SKU grupları BC'de açık olmasına rağmen Warehouse Pick'e post edilmediği için terminal kuyrukları boş kaldı; iki modun gerçek toplama kabul testi tamamlanamadı.

Ek olarak, aynı ürünün iki siparişe dağıtıldığı Multi toplamada paralel güncellemeler BC deadlock üretti ve yalnız bir satır yazıldı. Operatör ürünü yeniden okutarak devam edebildi; gerçek depoda bu davranış hız ve miktar doğruluğu açısından risklidir.

## 2. Test kapsamı ve gerçekleşen veri

| Alan | Sonuç |
|---|---|
| Toplama | `PI000015`, Multi, 3 sipariş, 8 satır, toplam 13 adet |
| Ana toplama sepeti | `LP00041` — terminalden otomatik oluşturuldu ve pick'e bağlandı |
| Paketleme oturumu | Entry No. `15`, Batch, 3/3 sipariş tamamlandı |
| Paketleme 1 | `HB.0002084`, 2 adet, harici koli `BOX-PI15-01` |
| Paketleme 2 | `HB.0002032`, 5 adet, negatif test kapsamında aynı `BOX-PI15-01` tekrar kullanıldı |
| Paketleme 3 | `HB.0002063`, 6 adet, barkodsuz karton üretildi: `LP00042` |
| Faturalar | `433543`, `433544`, `433545` |
| Sevkiyatlar | `435218`, `435219`, `435220` |
| Android otomatik testleri | Tüm flavor'larda başarılı; Gradle `BUILD SUCCESSFUL` |

## 3. Toplama testleri

### T-01 — Multi toplama: uçtan uca

**Belge:** `PI000015`  
**Siparişler:** `HB.0002032`, `HB.0002063`, `HB.0002084`  
**Beklenen:** Sepet doğrulama, ürün okutma, aynı ürünün siparişlere dağıtılması, 8/8 satır ve pick register.

**Gerçekleşen:**

1. Belge “Bana atanan” kuyruğunda doğru kullanıcıyla göründü.
2. Sistem yeni sepet önerdi; onay sonrası `LP00041` oluşturuldu ve ekranda kalıcı gösterildi.
3. Tek siparişe ait `BN.0286` için “Sepete koy 2 ADET” onayı doğru gösterildi.
4. İki siparişte bulunan `BN.0067` toplam 4 adet olarak tek grup ekranında gösterildi.
5. Grup onayında iki API güncellemesi paralel gitti; bir tanesi deadlock oldu. Ekran `HATA: 1/2 yazıldı` gösterdi.
6. Sunucuda satırlardan biri 3 adet yazılmış, diğer 1 adet yazılmamıştı. Ürün yeniden okutulduğunda yalnız kalan 1 adet açıldı ve süreç devam etti.
7. Bütün ürünler tamamlandığında ekran 8/8 ve %100 gösterdi.
8. “Pick'i Post Et” başarılı oldu; Warehouse Pick kaydı kapandı ve üç paketleme kaydı `Ready` oluştu.

**Sonuç:** Fonksiyonel olarak tamamlandı; deadlock ve raf bilgisinin olmaması nedeniyle canlı kabul verilmez.

**Kanıtlar:**

- [Pick açılışı ve sepet önerisi](screenshots/06-pi15-acilis.png)
- [Ana sepet LP00041](screenshots/07-pi15-sepet-sonrasi.png)
- [Tek ürün miktar onayı](screenshots/08-pi15-urun-tarama.png)
- [Multi dağıtım deadlock mesajı](screenshots/11-pi15-grup-dagitim-sonuc.png)
- [8/8 tamamlanmış pick](screenshots/13-pi15-8-8.png)
- [Post sonrası boş aktif kuyruk](screenshots/14-pi15-post-sonuc.png)

### T-02 — Mono toplama

**Beklenen:** Mono Warehouse Pick açılması, farklı tek ürünlü siparişlerin ayrı iş olarak işlenmesi.

**Gerçekleşen:** Terminalde “Bana atanan”, “Atanmamış” ve “Tümü” kapsamlarında Mono işi yoktu. API/BC kontrolünde aşağıdaki gruplar bulundu:

- Picking Order `24`: “Otomatik Mono - MERKEZDEPO”, 6 sipariş, `Open`, Warehouse Pick No. boş.
- Picking Order `22`: “Otomatik Mono - MERKEZDEPO”, 6 sipariş, `Open`, Warehouse Pick No. boş.
- Picking Order `19`: “Otomatik Mono - MERKEZDEPO”, 2 sipariş, `Open`, Warehouse Pick No. boş.

**Sonuç:** **BLOCKED.** Gruplar oluşturulmuş fakat `PostPickingOrder` çalıştırılmadığı için terminalin `picks` API'sine düşmüyor. Tarayıcı oturumu bulunmadığından BC kartındaki post işlemi bu testte çalıştırılamadı.

### T-03 — Tek SKU toplama

**Beklenen:** Aynı SKU'lu siparişlerin toplu miktar olarak toplanması ve paylara dağıtılması.

**Gerçekleşen:** Terminalde bütün kapsamlar boştu. BC/API'de Picking Order `23`, “Otomatik Tek SKU - BN.0067 - MERKEZDEPO”, 2 sipariş, `Open`; Warehouse Pick No. boş.

**Sonuç:** **BLOCKED.** Terminale aktarılmamış hazırlık kaydı nedeniyle gerçek toplama testi yapılamadı.

## 4. Paketleme testleri

### P-01 — Sipariş 1: doğru LP + ürün kilidi + harici koli

**Sipariş:** `HB.0002084`, müşteri `SÜMEYYE ALBAYRAK`  
**Ürünler:** `BN.0407 ×1`, `BN.0415 ×1`

**Kontroller:**

- Kuyrukta olmayan `LP99999` reddedildi.
- `LP00041` okutulduğunda pick doğrudan açıldı ve LP doğrulandı.
- İlk ürün `BN.0407` okutulduktan sonra sipariş kilidi devreye girdi.
- Aktif siparişe ait olmayan `BN.0067` reddedildi: “Önce HB.0002084 siparişini bitir”.
- İkinci ürün okutulunca koli adımı açıldı.
- `BOX-PI15-01` barkodu okutuldu.

**Sorun:** Terminal `Koli bağlanamadı: Hata: timeout` gösterdi. Sunucu kontrolünde siparişin aslında `Completed` olduğu, sevkiyat `435218` ve fatura `433543` oluştuğu görüldü.

**Kanıtlar:**

- [Yanlış LP reddi](screenshots/16-paketleme-yanlis-lp.png)
- [Doğru LP doğrulaması](screenshots/17-paketleme-lp-onay.png)
- [Aktif sipariş kilidi](screenshots/19-paket1-siparis-kilidi.png)
- [Koli adımı](screenshots/20-paket1-koli-adimi.png)
- [Yanlış timeout sonucu](screenshots/21-paket1-kapandi.png)

### P-02 — Sipariş 2: kısmi ilerleme + aynı koli barkodu negatif testi

**Sipariş:** `HB.0002032`, müşteri `Gülfatma Tataroğlu`  
**Ürünler:** `BN.0286 ×2`, `BN.0067 ×1`, `BN.0137 ×1`, `BN.0212 ×1`

**Kontroller:**

- Aynı ürün iki kez okutuldu; sayaç 2/2 ilerledi.
- Aktif sipariş kilidi yalnız bu siparişin kalan ürünlerini gösterdi.
- İlk siparişin timeout mesajından sonra `boxInput` temizlenmedi; `BOX-PI15-01` ikinci siparişin koli alanına taşındı.
- Aynı koli barkodu ikinci sipariş için onaylandı.

**Kritik sonuç:** Sistem aynı `BOX-PI15-01` barkodunu iki farklı müşteri siparişinde kabul etti. Sipariş `Completed`, sevkiyat `435219`, fatura `433544` oluştu. Koli barkodu için benzersizlik veya başka siparişe bağlı olma kontrolü yok.

**Kanıtlar:**

- [Kısmi paketleme ve sipariş kilidi](screenshots/22-paket2-kismi.png)
- [İkinci sipariş koli adımı; eski barkod alanda](screenshots/23-paket2-koli-adimi.png)
- [Aynı barkod sonrası timeout](screenshots/24-paket2-ayni-koli-barkodu.png)

### P-03 — Sipariş 3: toplu miktarlar + sistem kartonu

**Sipariş:** `HB.0002063`, müşteri `erkan mert`  
**Ürünler:** `BN.0067 ×3`, `BN.0283 ×3`

**Kontroller:**

- Her ürün üç kez okutuldu; toplam sayaç 13/13 oldu.
- “Barkodsuz kapat (karton üret)” kullanıldı.
- Sunucu `LP00042` kartonunu oluşturdu.

**Sorun:** Terminal yine timeout gösterdi. Sunucuda sipariş `Completed`, sevkiyat `435220`, fatura `433545`, oturum 3/3 `Completed` idi. Manuel “Yenile” sonrasında terminal doğru tamamlandı özetine geçti.

**Kanıtlar:**

- [Üçüncü sipariş koli adımı](screenshots/25-paket3-koli-adimi.png)
- [Barkodsuz karton işleminde yanlış timeout](screenshots/26-paket3-barkodsuz-sonuc.png)
- [Yenileme sonrası doğru tamamlandı özeti](screenshots/27-pi15-paketleme-tamam.png)

## 5. Bulgular ve öncelikler

| ID | Öncelik | Bulgu | Etki | Önerilen düzeltme |
|---|---|---|---|---|
| F-01 | **P0 / Blocker** | Koli kapatma her siparişte 12 saniyelik istemci timeout'una düştü; sunucu işlemi tamamladı. | Operatör işlemin başarısız olduğunu sanır, tekrar dener veya koli/sipariş durumunu yanlış yorumlar. | Koli/sevk/fatura aksiyonu için uzun süreli ayrı HTTP client kullanın veya sunucuyu job/idempotency yanıtı verecek şekilde ayırın. Timeout sonrası durumu otomatik sorgulayıp gerçek sonucu gösterin. |
| F-02 | **P0 / Blocker** | Aynı harici koli barkodu iki farklı siparişte kabul edildi. | Koli izlenebilirliği bozulur; iki müşterinin sevki aynı barkoda bağlanabilir. | `Box Barcode` için aktif/tamamlanmış paketleme satırlarında global benzersizlik kontrolü ve açık hata ekleyin. |
| F-03 | **P0 / Blocker** | `PI000015` üzerindeki sekiz satırın tamamında `Bin Code` boştu; ekranda Raf `-` göründü. | Depocu ürünü nereden alacağını bilemez; rota talimatı işlevsizdir. | Lokasyon/bin konfigürasyonunu ve pick oluşturma yöntemini düzeltin. Pick post öncesi boş bin satırlarını engelleyin. |
| F-04 | **P0 / Blocker** | Mono/Tek SKU Picking Order kayıtları açık fakat Warehouse Pick'e post edilmemiş; terminal kuyrukları boş. | Üç moddan ikisi sahada kullanılamıyor ve kabul testi yapılamıyor. | BC listesinde açık gruplar için kontrollü toplu “Pick Oluştur/Post Et” akışı ekleyin; terminale düşme SLA/uyarısı gösterin. |
| F-05 | **P1 / Kritik** | Aynı ürünün iki sipariş satırına paralel PATCH'i Warehouse Activity Line deadlock üretti; 1/2 yazıldı. | Kısmi miktar yazımı ve tekrar okutma ihtiyacı; yoğun depoda sık hata riski. | Grup dağıtım PATCH'lerini seri veya tek sunucu aksiyonu içinde atomik çalıştırın. 429/deadlock için sınırlı otomatik retry ekleyin. |
| F-06 | **P1 / Kritik** | Timeout sonrası koli barkodu temizlenmedi ve sonraki siparişe taşındı. | Operatör eski barkodu fark etmeden yeniden kullanabilir; F-02'yi tetikler. | Sipariş değiştiğinde `boxInput` koşulsuz temizlensin. Timeout sonrası önce sunucu durumu sorgulansın. |
| F-07 | **P1 / Kritik** | Terminal toplama satırlarını güvenli `confirmLine(userId)` aksiyonu yerine doğrudan `pickLines PATCH` ile yazıyor. Yerel kullanıcı sahipliğinde sunucu paylaşımlı BC hesabını ayırt edemiyor. | Başkasına atanmış pick satırının değiştirilmesi ihtimali; audit/atama kontrolü zayıf. | Android tüm satır onaylarını `picks(...)/confirmLine` üzerinden, yerel `userId` ile göndersin. Grup onayı için kullanıcı kimlikli toplu aksiyon ekleyin. |
| F-08 | **P2 / Yüksek** | “Yenile” gerçek veriyi getirse de eski timeout mesajı ekranda kaldı. | Operatör doğru durumla hata mesajını aynı anda görür; güven kaybı ve yanlış eskalasyon. | Başarılı reload sonrası mesajı temizleyin veya “Sunucuda tamamlandı” durumuna çevirin. |
| F-09 | **P2 / Yüksek** | Paketleme kuyruğunda ana LP'si boş eski pick kayıtları var (`PI000003`, `PI000008`, `PI000011`, `PI000012`). | Karttan girildiğinde LP doğrulama alanı yüklenemez; LP ile arama da mümkün değildir. | Veri temizliği/migrasyon yapın; Ready/In Progress paketleme kaydında `Main LP No.` zorunlu olsun veya yetkili kurtarma akışı sunun. |
| F-10 | **P2 / Yüksek** | Paketleme ürün okutma iyimser ve arka planda paralel çağrılara açık. | Çok hızlı taramada aynı satır için eşzamanlı yazım, geri alma ve sayaç sapması riski. | Aynı session/line için istemci kuyruğu veya sunucu tarafı idempotency anahtarı kullanın. |
| F-11 | **P3 / Orta** | Android test görevi ilk çalıştırmada sistem Java'sını bulamadı; Android Studio JBR ile başarılı oldu. | CI/yerel doğrulama standart değil. | Gradle/CI dokümanına desteklenen `JAVA_HOME` ekleyin veya toolchain tanımlayın. |

## 6. Olumlu sonuçlar

- Doğru ortam ve şirket bilgisi ana menüde net göründü.
- Paketleme kuyruğunda olmayan LP reddedildi.
- Paketlemeye girerken önce toplama LP'si doğrulaması çalıştı.
- Bir sipariş başladıktan sonra başka siparişin ürünü reddedildi.
- Yanlış/artan ürün için uygulama seviyesinde koruma mevcut.
- Sepete konacak miktar tek ürün ekranında büyük ve anlaşılır gösterildi.
- Multi aynı ürün grubu kalan miktarı tekrar okutulduğunda doğru şekilde tamamlanabildi.
- Pick register sonrasında üç paketleme kaydı otomatik oluştu.
- Üç paketleme sonunda üç satış sevkiyatı ve üç satış faturası oluştu.
- Barkodsuz karton üretimi `LP00042` oluşturdu.
- Manuel yenileme sonrası son tamamlandı özeti doğru gösterildi.
- Android unit testleri bütün flavor'larda başarılı tamamlandı.

## 7. Canlıya geçiş öncesi zorunlu kabul testleri

1. F-01 timeout düzeltildikten sonra en az 20 ardışık sipariş koli kapatma testi.
2. Koli barkodu benzersizlik testi: aynı barkod ikinci siparişte kesin reddedilmeli.
3. Bin'li lokasyonda Take/Place satırları, raf sıralaması, lot ve LP ile gerçek cihaz taraması.
4. Mono Picking Order `24` ve Tek SKU Picking Order `23` post edilerek tam toplama + paketleme.
5. Aynı SKU'nun 10+ siparişe dağıtımında deadlock/atomiklik yük testi.
6. İki farklı yerel operatörle sahiplik testi: operatör B, operatör A'nın pick satırını değiştirememeli.
7. Wi‑Fi kesilmesi, 5–15 saniye gecikme ve timeout sonrası otomatik durum uzlaştırma testi.
8. Hızlı barkod taraması: saniyede 2–4 okutma; eksik/fazla/çift kayıt olmamalı.
9. Ana LP'si boş eski paketleme kayıtlarının temizlenmesi veya kurtarma akışı.
10. Yazıcı bağlı ve yazıcı kapalıyken fatura/fiş kuyruğu ile sipariş kapanışının birbirinden bağımsız doğrulanması.

## 8. Nihai karar

Mevcut sürüm demo ve kontrollü pilot için işlevsel bir temel sağlıyor; ancak **P0 bulguları kapatılmadan gerçek depoda genel kullanıma açılmamalıdır**. En kritik sıra:

1. Timeout sonrası gerçek durum uzlaştırması,
2. koli barkodu benzersizliği,
3. bin/raf verisi zorunluluğu,
4. Mono ve Tek SKU pick oluşturma/post akışının tamamlanması,
5. Multi grup güncellemesinin atomik hale getirilmesi.

---

Bu test yalnız `sand1506` sandbox ortamında yürütülmüştür. Negatif koli barkodu tekrar testi bilinçli olarak sandbox siparişlerinde uygulanmıştır.
