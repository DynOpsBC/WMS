# BCWMS Android — Release Changelog

Sideload sürümleri burada toplanır. Her sürüm `bcwms-<version>-debug.apk`
olarak `releases/android/` altında saklanır.

Kurulum: [docs/android-install-guide.md](../../docs/android-install-guide.md)

---

## v1.14.88 — BADE — 2026-09-04

**versionCode:** 200088 · **BC paketi:** 1.14.1.19

**BADE SHA-256:** `a9f248d3a57a527252a59ae583fa5604cce6506b8c931d5e501b961d9b98b0eb`

### Güvenli mal kabul ve LP'li yönlendirilmiş hareket

- “LP Kapat” ve “Mal kabulü kaydet” tek işlem oldu; kayıt başarısızsa LP kapanmaz, başarılıysa LP kapanıp etiketi hazırlanır.
- Kaydedilmeden iptal edilen mal kabul belgesine ait açık/tamamlanmış LP içeriği temizlenir; kayıtlı veya başka belgeye bağlı LP'lere dokunulmaz.
- Yönlendirilmiş harekette okutulan LP artık kaynak raftan hedef rafa aynı LP numarası ve miktarıyla taşınır; her iki ambar hareketi LP numarasını gösterir.
- Bir LP'nin yalnız bir kısmı taşınmak istenirse işlem durur ve önce LP'nin bölünmesi istenir; LP ile raf miktarı birbirinden kopamaz.
- Toplu mal kabulde satın alma, ambar mal kabulü ve Madde Defter Girişi tek toplam satır olarak korunmaya devam eder.

## v1.14.87 — BADE — 2026-09-04

**versionCode:** 200087 · **BC paketi:** 1.14.1.18

**BADE SHA-256:** `5dd05ab5885c34d962d32d76c2a88bfd81c10dbca81687d4ad79174ddcaf50bc`

### Toplu paletli mal kabulde tek stok hareketi

- 100 adetlik tek satın alma ve mal kabul satırı 2 × 50 LP oluşturulsa da bölünmez; Madde Defter Girişi tek satır 100 adet kalır.
- Fiziksel palet miktarları bağımsız LP kayıtlarında korunur; yerleştirme satırları palet bazında hazırlanabilir.
- Aynı mal kabul satırındaki bütün LP'ler tek ortak iç lot, tedarikçi lotu ve son kullanma tarihi kullanır; iç lot boş bırakılırsa yalnız bir kez üretilir.
- Birden fazla LP numarası tek Madde Defter Girişinin “İlgili LP No.ları” alanına birlikte yazılır.
- BC paketi 1.14.1.18 yüklü değilse terminal eski satır bölme davranışını çağırmadan Palet LP işlemini güvenli biçimde durdurur.

## v1.14.86 — BADE — 2026-09-04

**versionCode:** 200086 · **BC paketi:** 1.14.1.17

**BADE SHA-256:** `e12eaa7c40e2116efe3682b379942aaf8988293c64be0b713db0135ca5537dd0`

### Toplu LP ekranında sade operatör dili

- Teknik stok hata metinleri kaldırıldı; yanlış raf, yetersiz miktar ve mevcut LP stoku için doğrudan yapılacak işlem gösterilir.
- “Madde Defter Girişi” ve “Bin” gibi alan adları operatör dilinde “stok kaydı” ve “ürünün bulunduğu raf” olarak sadeleştirildi.
- Ağ cevabı alınamayan güvenli tekrar akışı, yeni LP oluşturmadan önce “Önceki İşlemi Kontrol Et” düğmesiyle anlaşılır hale getirildi.

## v1.14.85 — BADE — 2026-09-04

**versionCode:** 200085 · **BC paketi:** 1.14.1.17

**BADE SHA-256:** `28381823acfa4c97807032d065729ccf50c78e7f2bbbe8ee9327f3c300f31fdb`

### Yönlendirilmiş harekette zorunlu raf ve kaynak LP doğrulaması

- “Al” satırına dokununca önce satırdaki kaynak raf, ardından o raftan alınacak LP okutulur; yanlış rafla işleme devam edilemez.
- LP’nin lokasyonu, rafı, durumu, belge ataması, maddesi, varyantı, lotu/serisi ve yeterli miktarı hem terminalde hem Business Central’da doğrulanır.
- Doğrulama ekranı taşınacak maddeyi, miktarı, kaynak/hedef rafı ve seçilen LP’nin madde-lot-miktar içeriğini birlikte gösterir.
- Hareket kaydedilince standart Ambar Hareketi değişmeden kalır; yalnız alınan miktar kaynak LP içeriğinden aynı kayıt işlemi içinde düşer. Madde Defter Girişi oluşturulmaz veya bölünmez.

## v1.14.84 — BADE — 2026-09-04

**versionCode:** 200084 · **BC paketi:** 1.14.1.16

**BADE SHA-256:** `4e7486dd09bc3ac2bfc2542fb1c56979dd7c1d740bd8e28f779950531719f0b3`

### Raf sıralı çoklu LP toplama ve gerçek sevk LP'si

- Tek paletin yetmediği sevkiyatta uygun paletler raf kodu sırasıyla birlikte kullanılır; terminal artık tek LP seçme zorunluluğu göstermez.
- Toplama kaydedilirken miktar kaynak LP'ler arasında bölünür, kullanılan miktarlar yeni sevk LP'sinde birleşir ve son kaynak LP yalnız alınmayan bakiyeyi korur.
- Sevkiyat yeni sevk LP'sinden düşer; kaynak paletin kalan miktarı ikinci kez tüketilmez. Başka belgeye ayrılmış LP stoku serbest stok sayılmaz.
- Standart Ambar Toplama ve stok hareket satırları çoğaltılmaz; LP içerik aktarımı aynı kayıt işlemi içinde atomik yapılır.

## v1.14.83 — BADE — 2026-09-04

**versionCode:** 200083 · **BC paketi:** 1.14.1.15

**BADE SHA-256:** `794e52b39ac43f8eb8207156d5940d4904c9669fe4295e2820f4c8c58eeed41c`

### Tek Madde Defter Girişinden güvenli çoklu LP ve sayım

- 1.000 adetlik tek Madde Defter Girişi ve tek Ambar Girişi değiştirilmeden, aynı kaynağa bağlı 10 × 100 gibi ayrı LP kayıtları ve her LP için ayrı etiket oluşturulur.
- Etikette toplam mal kabul miktarı ile palet miktarı ayrı gösterilir; Madde Defter Girişleri bölünmez ve aynı raftaki LP hazırlığı depo hareketi üretmez.
- Ağ cevabı kaybolursa aynı işlem kimliğiyle güvenli tekrar yapılır; ikinci LP seti veya çift etiket kuyruğu oluşturulmaz.
- Sayım V2 her LP'nin kendi miktarını kullanır. 10 × 100 okutma toplamı 1.000 kalır; sıfır farkta stok günlüğü ve yeni Madde Defter Girişi oluşmaz.
- Eski, kaynağı bilinmeyen LP kayıtları yeniden tahsis edilmez; güvenli olmayan eski sayım snapshot'ı stoklara işlenmeden durdurulur.

## v1.14.82 — BADE — 2026-09-04

**versionCode:** 200082 · **BC paketi:** 1.14.1.14

**BADE SHA-256:** `e76645ff09ad70196c67e81a0aff65da4c9db5d4a6a9b2edc5e92a7bdb559b5c`

### Ad-hoc harekette LP bütünlüğü · bekleyen sevkiyat ve yazıcı düzeltmeleri

- “Ürün ile” ad-hoc hareket artık yalnız LP'ye atanmamış serbest raf stokunu taşıyabilir; aktif LP içindeki miktar seçimsiz olarak başka rafa taşınıp LP'yi kendiliğinden bölemez.
- LP stoku taşınacaksa terminal açık bir hata mesajıyla “LP ile” moduna yönlendirir; seçilen LP tüm içeriği ve başlığıyla atomik taşınır.
- Bekleyen sevkiyat/toplama LP aktarımı ile yazıcı ajanı ilk kurulum iyileştirmeleri de bu sürüme dahil edildi.

## v1.14.81 — BADE — 2026-09-04

**versionCode:** 200081 · **BC paketi:** 1.14.1.13

**BADE SHA-256:** `8efd0a297ae8915ef4a9d8cc20edf339972fa55292d7cf21261af8cb002ea555`

### Madde Defterinden toplu LP · güncel kısmi LP dağılımı

- Bir Madde Defter Girişi tek satır olarak korunur; aynı kaynaktan örneğin 10 × 100 miktarlı 10 ayrı LP oluşturulur.
- Oluşturulan her LP için ayrı malzeme/LP etiketi yazdırılır; yazıcı hatası LP oluşumunu geri almaz.
- Kaynak girişin kalan miktarı ve raftaki atanmamış stok aşılırsa işlem engellenir; seri takipli kayıt bölünmez.
- Kısmi işlem sonrası tarihsel Ambar Girişi değiştirilmez. Depo Gözü İçeriği'ndeki “Güncel LP Miktarı” veya Ambar Girişleri'ndeki güncel LP alanı 15 + 1.905 gibi gerçek LP dağılımını ayrı satırlarda açar.

## v1.14.80 — BADE — 2026-09-03

**versionCode:** 200080 · **BC paketi:** 1.14.1.12

**BADE SHA-256:** `e4770c9ab27fa68ccc158371c930032c0761f02cf1bf80a748f368490cbb73f6`

### Toplamada kaynak palet seçimi · stok hareketinde tüm paletler

- "Pick Oluştur" artık hangi paletten toplanacağını soruyor. Aday paletler numara, raf, lot ve mevcut miktarla listeleniyor; siparişin tamamını karşılayan palete "Tamamını karşılar" etiketi konuyor. "Sistem seçsin" seçeneği eski davranışı sürdürür.
- Seçilen palet toplama satırına yazılıyor, stok o paletten düşüyor.
- Birden fazla paletten toplanan satışlarda stok hareketi artık tüm paletleri gösteriyor (yeni "LP No.leri" alanı, Business Central madde defter girişleri ekranında görünür). Tek palette eski davranış korunuyor.

## v1.14.79 — BADE — 2026-09-03

**versionCode:** 200079 · **BC paketi:** 1.14.1.11

**BADE SHA-256:** `0bb0bfb4545b9950eb7c90ac47131d6343652c2d019bd85d2fa2e37e8d40a330`

### Sayım yalnız BC'den işlenir · V2 modu BC'de · çoklu LP sevkiyat

- Terminalden "Onayla ve Stoklara İşle" kaldırıldı. Sayım stoklara yalnız Business Central'daki Count Sheet → Post ile işlenir. Sunucu tarafında da kapalı: DOPSWHS Kurulum → "Terminal Count Posting" (varsayılan kapalı, istenirse açılır).
- Count Sheet kartında "V2 Scan Mode" artık BC'den açılıp kapatılabiliyor (satırı olmayan, kapatılmamış belgede); listede "V2 Sayımına Çevir" eylemi eklendi.
- Aynı madde+lot birden fazla LP'de olduğunda satış sevkiyatı artık "birden fazla LP eşleşti" ile durmuyor: kayıtlı pick satırlarının raf/LP bilgisine göre doğru paletler deterministik sırayla düşürülür; açıkça seçilmiş LP yolu değişmedi. Pick satırındaki LP numarası kayıtlı pick satırına taşınıyor.

## v1.14.78 — BADE — 2026-09-02

**versionCode:** 200078 · **BC paketi:** 1.14.1.10

**BADE SHA-256:** `cc5f81fe01eda32143f1f358bc7391d47241665e6d674a922ebf055a39654443`

### LP hareket izi · satış pick · toplu yazdırma

- LP ile raflar arasında taşınan stokta LP numarası Warehouse Journal üzerinden her iki ambar hareketine de aktarılıyor.
- 1.14.1.9 öncesindeki LP'siz hareketler, LP hareket defterinde tek ve kesin eşleşme bulunduğunda Ambar Hareketleri ekranında LP numarasıyla gösteriliyor.
- Satış pick oluşturma, siparişin tamamını karşılayabilen tamamlanmış LP stoklarını standart raf stoklarına tercih ediyor; kaynak LP pick satırına yazılıyor.
- Pick ekranında Kalan/Girilen miktarları ilk görünümde gösteriliyor.
- 1.14.77'de hazırlanan toplu LP yazdırma yazıcı-yönlendirme ve açıklayıcı hata düzeltmeleri dahil edildi.

## v1.14.77 — BADE + EMU — 2026-09-02

**versionCode:** 200077 · **BC paketi:** 1.14.1.9

**BADE SHA-256:** _CI çıktısından eklenecek_

**EMU SHA-256:** _CI çıktısından eklenecek_

### LP · toplu yazdırma yazıcı seçimi

- "Seçilenleri Yazdır" artık LP kartındaki tekli "QR Etiketini Yazdır" ile aynı yazıcıya gidiyor: cihazda ZPL etiket yazıcısı seçiliyse etiket, yalnız PDF belge yazıcısı seçiliyse LP QR belgesi. (1.14.76'da toplu baskı her zaman ZPL etiket yazıcısı istiyor, belge yazıcısı olan sahada "Yazıcı ayarı tamamlanamadı" veriyordu.)
- Yazıcı hataları gerçek nedenini söylüyor: etiket/belge yazıcısı seçilmemiş, seçili yazıcı BC'de kayıtlı değil veya pasif, iş kaydedildi ama ajana iletilemedi.
- Yazıcılar ekranı, telefonda kayıtlı olup listede artık bulunmayan yazıcı kodunu uyarıyor.

## v1.14.76 — BADE + EMU — 2026-09-02

**versionCode:** 200076 · **BC paketi:** 1.14.1.9

**BADE SHA-256:** `3070947e2db66fa71abb767a85abb83b01fe5a6b44aa651de92d7c923eb92124`

**EMU SHA-256:** `d4561731de2f689187a5cd84a4e83a4293df37e2c784fad9643fc8041c702476`

### Ürün Sorgu · okutulan LP özeti

- LP numarasıyla sorgulamada okutulan LP, toplam adedi ve lot bilgisi doğrudan ürün kartında gösteriliyor.
- LP satır kartları daha yüksek, büyük yazılı ve miktarı ayrı vurgulanmış düzene geçirildi.

## v1.14.75 — BADE + EMU — 2026-09-02

**versionCode:** 200075 · **BC paketi:** 1.14.1.9

**BADE SHA-256:** `124b97715d202cd72bff0b4227b5333d08b3b75385bb11a52843281c96b3a812`

**EMU SHA-256:** `bed2386379c3ce826a472c4ef43a04a57cbdcad25704f53a8e6fe0f82eb90f93`

### LP toplu yazdırma · lokasyon seçimi

- Satırsız/toplu oluşturulmuş LP'ler artık PDF belge aksiyonuna değil, ZPL LP etiketi aksiyonuna gönderiliyor.
- Azure Direct yanıtı için uzun işlem süresi kullanılıyor; kuyruğa kabul edilmiş baskının telefonda zaman aşımı hatası görünmesi önleniyor.
- Kısmi baskı hatasında sunucu mesajı ve ilk başarısız LP gösteriliyor; yalnız başarısız LP'ler seçili bırakılıyor.
- Toplu LP oluşturmadaki lokasyon alanı, Business Central'daki mevcut lokasyonları gösteren salt-okunur seçim listesine çevrildi.
- Lokasyon değiştirildiğinde önceki depo gözü temizleniyor; lokasyon listesi eksik yüklenirse oluşturma güvenli biçimde devre dışı kalıyor.

## v1.14.73 — BADE + EMU — 2026-09-01

**versionCode:** 200073 · **BC paketi:** 1.14.1.8

**BADE SHA-256:** `4400018b65ca212f9ecf5488a945a23bcdd9ced7bc62768a60a595e33f52f52b`

**EMU SHA-256:** `fa7c646341d8379a26c4f7161d5cb9032bd730dd6b9804afcc74eb94774ee199`

### Toplu LP · sayım onayı · sorgulama

- Tek işlemde 1–200 LP oluşturma, ortak miktarı tüm LP'lere uygulama ve miktarları ayrı ayrı düzenleme eklendi.
- LP toplu seçimi ve malzeme/LP etiketi toplu yazdırma akışı eklendi.
- Klasik Sayım ve Sayım V2'ye lokasyon alanı filtresi eklendi; alan dışındaki raflar engellendi.
- Sayım turunu kaydetme stok hareketinden ayrıldı; stok yalnız **Onayla ve Stoklara İşle** adımıyla değişir.
- Ürün sorgulama ekranı ürün numarasının yanında LP numarasıyla da arama yapar.

## v1.14.72 — BADE + EMU — 2026-08-31

**versionCode:** 200072 · **BC paketi:** 1.14.1.7

**BADE SHA-256:** `d5871e4e2c749c141f61aa9ef9d5ea1be39f28e4c1f856f9220fcdd8c004c0d0`

**EMU SHA-256:** `2f23285ef39442aa6b23b2ec00e16c08cb4658a0a294e22371a4dbaea18557a9`

### Mal kabul · kompakt işlem paneli

- Belge altındaki dört ayrı işlem şeridi tek, iki satırlı kompakt panelde birleştirildi.
- Yazdırma, Palet LP, Tara, LP Başlat/Kapat ve Kaydet işlevleri korunurken satır listesine daha fazla ekran alanı bırakıldı.
- Belge kullanıcıya atanmışsa pasif **Bana Ata** düğmesi artık yer kaplamıyor; atanması gereken belgede tek ana işlem olarak gösteriliyor.

## v1.14.71 — BADE + EMU — 2026-08-31

**versionCode:** 200071 · **BC paketi:** 1.14.1.7

**BADE SHA-256:** `c93c1b4940156a1605d0455303d2cc20be4236aca8cbf761cd68a4d4ce82a95c`

**EMU SHA-256:** `bfdda2ad8ddd3338cb21fa901ef3fdfc644063fcdb57f1cd31d576192fed2b76`

### Mal kabul · toplu palet LP dağıtımı

- Palet LP oluşturma ekranına toplam kabul miktarı ve palet sayısı alanları eklendi.
- **Eşit Böl** işlemi toplamı beş ondalık hassasiyetle LP'lere dağıtır; yuvarlama farkını son LP'ye vererek toplamı korur.
- Otomatik oluşturulan her LP'nin miktar, iç lot, tedarikçi lotu ve SKT bilgisi ayrı ayrı düzenlenebilir.
- SKT girişi `GG.AA.YYYY` biçimine geçirildi; noktalar otomatik eklenir ve takvimden tarih seçilebilir.
- Geçmiş SKT hem terminal doğrulamasında hem BC kayıt katmanında reddedilir.

## v1.14.70 — BADE + EMU — 2026-08-31

**versionCode:** 200070 · **BC paketi:** 1.14.1.7

**BADE SHA-256:** `58ad6d910b913e4995489361a057f9b8773649bec9e7108ff362977f09e50d71`

**EMU SHA-256:** `fcbb9a6cf5d2b7af09cc72c14d052c1ed5c1508a0b09036ad51b1b01849a31c9`

### Canlıya geçiş turu (30.08 gecesi, E-DefterSandbox canlı UAT)

**Mal Kabul**
- Satın alma siparişi ekranına **📥 Ambar Kabulü Oluştur** eklendi; belge ofis BC'de açılmamışsa operatör terminalden üretir.
- Girilen miktar/lot/SKT belge listesine çıkıp dönünce korunuyor (cihazda saklanan işlenmiş-satır kümesi).
- Tam kayıt sonrası BC belgeyi sildiğinde ekran artık hata değil "belge kapandı" gösterip listeye dönüyor.
- Toplu LP dağıtımında SKT alanı boş satırda `0001-01-01` yerine boş geliyor.
- Doğrudan PO kabulü kapısı satır lokasyonlarına da bakıyor; karışık/boş lokasyonda Türkçe, eyleme dönük hata.
- PO araması sunucu tarafında (iki ayrı sorgu) — en yeni 100 dışındaki eski siparişler de bulunuyor.
- Oluşan yerleştirme belgesi mal kabulü yapan operatöre atanıyor; toplu LP satır bölmesinde birim fiyat ve raf korunuyor.

**Sevkiyat + Toplama**
- Sevkiyat ekranına **Sevkiyat Acentesi** kartı/diyaloğu; seçim hem ambar sevkiyatına hem kaynak satış siparişine yazılıyor (BADE zorunlu alanı).
- Kısmen işlenmiş lot izleme satırları silinmiyor → "Pick Oluştur" hatası giderildi.
- Yeni toplama %0 başlıyor (Qty. to Handle ön-doldurma kapatıldı); ilerleme gerçek kaydedilen miktardan.
- Sevk satırı güncellemesi raf kodu göndermiyor ("Status must be Open" hatası kalktı).
- Post sonrası numara serisi hatasında sevk gerçekten kaydedildiyse "kaydedildi + uyarı" gösteriliyor.

**Sayım**
- LP okutmada sistem miktarı BC raf bakiyesinden alınıyor (LP/BC tutarsızlığı artık "fark 0" görünmüyor).
- Yönlendirilmiş lokasyonda sayım farkı **sayılan rafa** yazılıyor (ambar fiziksel sayım günlüğü; lot/seri satırın kendi alanlarında).
- Rafta olmayan üründe lokasyon toplamı rafa yazılmıyor; lot okutmasında uyarı ile yazılıyor.
- Aynı miktarlı etiket iki kez sayılmıyor; geri alınca yeniden okutulabiliyor. Satır 0'a düzeltilebiliyor.
- Klasik sayımda "Kaydet" kapalıyken nedeni yazılıyor; sayım belge numarası kırpılmıyor (izlenebilirlik).
- Türkçe `MİKTAR/BİRİM=` etiketi çözülüyor; raf seçilince ürün alanı otomatik odaklanıyor.

**Genel**
- Miktar alanlarında Türkçe ondalık virgül kabul ediliyor (`12,5` → 12.5).
- Maskelenen BC hataları Türkçeleştirildi: kalan miktar aşımı, sevk/kabul miktarı, "Status must be Open", lot dağılımı uyuşmazlığı, numara serisi, "Nothing to handle", fazla kabul sınırı.
- Tüm belge ekranlarında donanım Geri tuşu listeye dönüyor (uygulama kapanmıyor).

**Fason İşlemler (yeni modül)**
- Ana menüye **Fason İşlemler** eklendi: taşerona sevk ve referans numarasıyla teslim alma tek modülde.
- Fasona sevk transfer belgesi üzerinden yürür; sevk edilen bileşenler ve e‑irsaliye çıkışı BC tarafında kuyruğa alınır.
- Teslim almada üretim emri operasyonu ve satırı seçilerek gelen miktar kaydedilir.

**LP (Taşıma Kabı)**
- Satır eklemede kaynak raf LP'nin lokasyonunda değilse satır gönderilmeden "HATA ÖNLENDİ" ile durduruluyor.
- Boş LP'de tamamlama düğmesi sessizce pasif kalmıyor; nedeni ekranda yazıyor (UAT lp‑04).
- Bozma/silme yapılamayan durumlarda düğme kaybolmak yerine nedeni yazılıyor (Atandı / Kullanıldı / Bozuldu).

## v1.14.69 — BADE + EMU — 2026-08-29

**versionCode:** 200069 · **BC paketi:** 1.14.0.87

**BADE SHA-256:** `80ee60064843155f754d70f8d28e091700ac54ce8941fe3c7678b1f3998756a1`

**EMU SHA-256:** `b4c46192c8b7201e76bf1aac280a98b19f840d88dace6c09474aa560756d32e1`

### Mal kabul, LP'li sevkiyat ve sayım kapanışı

- Aynı mal kabulde ikinci kısmi dalga ve farklı lotlar yeni LP'lere dağıtılabilir; ekran yenilendiğinde hazırlanan LP miktarları korunur.
- Çoklu LP kabulü, BC ambar ve madde defteri hareketlerinde her LP için ayrı miktar/lot kırılımı oluşturur.
- Tek, grup ve yönlendirmeli pick ekranlarında kullanılmayacak lot `0` miktarla onaylanabilir; Take ve Place birlikte sıfırlanır.
- LP'li sevkiyat, seçilen kaynak LP'yi satış commit edilmeden önce tam bir kez azaltır ve LP numarasını madde defteri girişine yazar.
- Post yanıtı hata olsa bile sevkiyat kapanmışsa terminal işlemi başarılı kabul eder ve ikinci kez post etmez.
- Yanlış raftaki LP sayıma alınmaz; sayım belgeleri ayrı journal batch'leriyle sorunsuz tamamlanır.

## v1.14.68 — BADE + EMU — 2026-08-28

**versionCode:** 200068 · **BC paketi:** 1.14.0.86

**BADE SHA-256:** `9486e95fda9e9c1b157c974f8b0b1658962a58a6ef1e937b44d78dd74cdb9de8`

**EMU SHA-256:** `c940bf98d798fecb2221466b314a9f6a3559c9ac86962722e2d0fffbe06e69a4`

### Raf bazlı hızlı LP yerleştirme

- Operatör hedef rafı bir kez okutup aynı rafa bırakacağı LP'leri art arda okutabilir.
- Hedef değiştiğinde yeni raf barkodu okutularak farklı LP gruplarına aynı ekranda devam edilir.
- Tamamla işleminde okutulan LP'ler kendi miktar, lot ve hedef raflarıyla birlikte kaydedilir.
- Kalite bekleyen LP normal rafa konamaz; reddedilen LP yalnız tanımlı ret/karantina rafına yönlendirilir.

## v1.14.67 — BADE + EMU — 2026-08-28

**versionCode:** 200067 · **BC paketi:** 1.14.0.85

**BADE SHA-256:** `4984b94e99aa0d09dc0022e2b7b6d39c5eb2b1588847fd1a15ba6e856c160d1c`

**EMU SHA-256:** `c6c93308b3126811e43dc7f9714d32a0f5c492dfbce771f1b9dd59cf185e916f`

### LP bazlı yerleştirme

- Toplu mal kabulde tek 1.000'lik yerleştirme yerine, kaynak LP dağıtımına göre her palet için ayrı Take/Place çifti oluşturulur.
- Yerleştirme kartlarında LP numarası görünür ve LP etiketi okutularak doğru fiziksel palet doğrudan seçilebilir.
- Her LP kendi miktarıyla ayrı rafa yerleştirilebilir; kayıt sonrası LP başlığı ve ambar hareketi hedef rafla güncellenir.
- Toplu kabulün tek Madde Defter Girişi birden fazla LP içerdiği için LP alanı boş kalabilir; gerçek LP ayrımı yerleştirme ve LP hareketlerinde korunur.

## v1.14.66 — BADE + EMU — 2026-08-28

**versionCode:** 200066 · **BC paketi:** 1.14.0.81

**BADE SHA-256:** `9f193533fba9a17b6b24f9a2bad2f1ba41fdff25bec8d4db065077e3bd81e484`

**EMU SHA-256:** `232cf3a8d42f1ce82ab5b24d362104e55327a26ca79f6a489d7c745d70742fd5`

### Tek mal kabulde toplu LP dağıtımı

- Kabul miktarı, `Toplu LP Dağıtımı` ekranından birden fazla LP'ye tek işlemde dağıtılır.
- LP sayısı ve LP başına miktarla eşit dağıtım yapılabilir; kalan miktar isteğe bağlı olarak son LP'ye aktarılır.
- Palet miktarları tek listeden düzenlenebilir ve LP toplamı kabul miktarına eşit değilse işlem engellenir.
- Aynı mal kabulde farklı lot grupları tanımlanabilir; farklı lotlar aynı LP içinde birleştirilmez.
- LP numaraları ardışık üretilir, aynı depo mal kabulüne bağlanır ve etiketleri toplu basılabilir.

## v1.14.65 — BADE + EMU — 2026-08-28

**versionCode:** 200065 · **BC paketi:** 1.14.0.79

**BADE SHA-256:** `e5125c80478a659732801c9bfa312a95f8eab638927f9bbeb0a89f6e3383d615`

**EMU SHA-256:** `d8a3efa42002113f38de7a740aaea43d3bc5be9e7196e1b5348966633c95582b`

### EMU Kutu ve Palet ekranı

- Mevcut taşıma kabı menüsünün adı yeniden `LP` yapıldı.
- EMU ana menüsüne ayrı `Kutu ve Palet` butonu geri getirildi.
- Ürün LP → kutu → palet oluşturma, bağlama/ayırma, içerik görüntüleme, toplu taşıma ve hiyerarşi etiketi işlemleri yeniden kullanılabilir.
- `Kutu ve Palet` butonu yalnız EMU paketinde görünür; BADE menüsü değişmez.

## v1.14.64 — BADE + EMU — 2026-08-28

**versionCode:** 200064 · **BC paketi:** 1.14.0.79

**BADE SHA-256:** `650436e87ef2a4117569e947e72289790b198abcecc9856e7fb16f6dec7df284`

**EMU SHA-256:** `a88318ba7bc3899d641a9548cf409e749791c731589e590c39c129b435498654`

### Çok ürün, çok lot/LP ve geçmiş SKT

- Bir yerleştirme satırını hazırlamak belgeyi hemen register etmez; yalnız seçilen satırlar kaydedilir ve kalan ürünler belgede kalır.
- Aynı ürünün farklı lot, seri veya LP hareketleri ayrı yerleştirme kartları olarak gösterilir.
- Mal kabul paletine farklı ürün veya lot eklenemez; operatör mevcut LP'yi kapatıp yeni LP başlatır.
- Geçmiş son kullanma tarihi mobil onayda ve BC post işleminde engellenir.

## v1.14.63 — BADE + EMU — 2026-08-28

**versionCode:** 200063 · **BC paketi:** 1.14.0.78

**BADE SHA-256:** `6daae310a5bc68e2694967f9ee238e2db47feea6781fd8456729a11cde90b512`

**EMU SHA-256:** `1b2408f966f3934cf5e465b28eb2c28676ab2b888cd5f17a416559d62877b49f`

### Tek sürüm, iki müşteri paketi

- BADE ve EMU aynı kaynak koddan, aynı sürüm numarasıyla birlikte üretilir.
- Ana menüdeki `LP` adı `Palet / LP` olarak netleştirildi; ekran iki pakette de aynıdır.
- Her müşteri kendi güvenli güncelleme kanalını kullanır, ancak iki kanal aynı yayında birlikte ilerletilir.

## v1.14.62-emu — 2026-08-28

**APK:** `BCWMS-EMU-1.14.62-RELEASE.apk`

**versionCode:** 200062

**SHA-256:** `6a4c3dac1469548fc4873405a0240848208e72f897989e23ffb82a146b96966c`

### EMU güncelleme bağlantısı

- Güncelleme manifesti, bazı telefon ağlarında erişilemeyen `raw.githubusercontent.com` yerine sabit GitHub release kanalından okunur.
- Bu sürüm bir kez elle kurulduktan sonra sonraki EMU güncellemeleri uygulama içinden alınabilir.
- Pick ekranında kullanılmayacak lot satırı `0` miktarla onaylanabilir.

## v1.14.61-bade — 2026-08-28

**APK:** `BCWMS-BADE-1.14.61-RELEASE.apk`

**versionCode:** 200061 · **BC paketi:** 1.14.0.78

**SHA-256:** `563652d3a973d2cd3bfcc3509d1cfc9aeb462b85eed276a7a935917f1a6489d7`

### Çoklu LP ve lot eşleşmesi

- Mal kabulde her kayıtlı lot satırı artık başlıktaki ilk LP yerine kaynak satır, ürün, varyant, lot ve seri bilgisine göre kendi LP'siyle eşleştirilir.
- `LP000063 → 5 KG / H100795` ve `LP000064 → 15 KG / H100796` ayrımı korunur; belirsiz eşleşmelerde yanlış LP yazılmaz.
- Kapatılmış LP'den sonra aynı mal kabulde yeni LP başlatılır; önceki palet yeniden açılıp yeni lotla karıştırılmaz.
- AL yükseltmesi eski kayıtlı mal kabul ve depo hareketlerindeki kanıtlanabilir yanlış LP damgalarını otomatik onarır.

## v1.14.60-bade — 2026-08-28

**APK:** `BCWMS-BADE-1.14.60-RELEASE.apk`

**SHA-256:** `237821ca48acbba6c88375706e62b12e53bf7b686b91f0652bcbe93d8156b94b`

**versionCode:** 200060 · **BC paketi:** 1.14.0.72

### Pick satırında sıfır miktar

- Sevkiyat toplamada kullanılmayacak bir lot satırı `0` miktarla onaylanabilir ve satırın işlenecek miktarı sıfırlanır.
- Boş, negatif veya geçersiz miktarlar engellenmeye devam eder; diğer miktar girişlerinin mevcut kuralları değişmez.

## v1.14.59-bade — 2026-08-28

**APK:** `BCWMS-BADE-1.14.59-RELEASE.apk`

**SHA-256:** `b7bfba1383d8abfbd282c5594bf248d2f57ec8c0e7ed906bcaeb9637dc01408c`

**versionCode:** 200059 · **BC paketi:** 1.14.0.72

### Sayım V2, çoklu lot sevkiyat ve mal kabul LP

- Sayım V2'de LP veya lot barkodu ürün, lot, UOM ve BC miktarını otomatik getirir; miktar penceresi açmadan sonraki okutmaya geçilir. Satıra dokunarak miktar isteğe bağlı değiştirilebilir.
- Sevkiyat pick'i ürünün mevcut miktarını lot ve depo gözü bazında ayrı satırlara böler; eski tek-lot seçimine takılmaz.
- Hatalı veya eski pick, yalnız belge sahibi ve kaydedilmiş hareket yokken güvenli şekilde iptal edilip yeniden oluşturulabilir.
- Mal kabulde yeni LP numarası eski bir LP ile çakışmaz; LP kapatılıp tekrar açılabilir ve alınan ürün aktif LP'nin içine kaydedilir.
- Mal kabul lot alanındaki yönlendirme artık sevkiyat metni göstermeden `Lot No Ata` adımını açıkça anlatır.

### Canlı BADE doğrulaması

- `SH000273` için `PI001130` dört ayrı lot/depo gözü satırıyla oluşturuldu.
- `RE000625` içinden `LP000048` üzerine `HM.00181`, lot `H100782`, `1 KG` eklendi ve LP detayından geri okundu.

---

## v1.14.58-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.58-RELEASE.apk`

**versionCode:** 200058 · **BC paketi:** 1.14.0.69

### Sayım V2 kullanım düzeltmeleri

- Sayım sayfası araması yazıldığı anda listeyi gerçekten filtreler; eşleşme yoksa açık mesaj gösterir.
- Kamera önizlemesi açıkken Android geri tuşu artık belge ekranından çıkmaz, yalnız kamerayı kapatır.
- Raf, ürün, lot ve çok satırlı LP okutma; LP geri alma, satır düzeltme ve kaydetme onayı canlı BADE belgesinde yeniden doğrulandı.

## v1.14.57-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.57-RELEASE.apk`

**versionCode:** 200057 · **BC paketi:** 1.14.0.69

### Sayım V2: yalnız lot kodu taşıyan QR

- Düz metin barkodu önce gerçek madde numarası olarak kontrol edilir.
- Madde bulunamazsa aynı değer otomatik olarak lot numarası kabul edilir.
- Lotun ürün, UOM ve okutulan raftaki miktarı BC stokundan getirilir; manuel giriş ekranı açılmaz.

---

## v1.14.56-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.56-RELEASE.apk`

**versionCode:** 200056 · **BC paketi:** 1.14.0.69

### Sayım V2: manuel girişsiz hızlı okutma

- Raf QR ardından LP/MTE QR okutulunca LP içeriğindeki ürün, lot, seri, UOM ve miktarlar otomatik sayılır.
- LP'siz ürünlerde GTIN/madde ve lot barkodu, okutulan raftaki BC stok miktarını ve UOM'u otomatik getirir.
- Aynı barkodu tekrar okutmak miktarı katlamaz; sayılan satır yalnız gerektiğinde dokunularak düzeltilebilir.
- Geri alma, tek katkı kalan satırı `0 sayıldı` bırakmak yerine güvenli biçimde kaldırır.
- Yalnız BC'de ilgili rafta bulunmayan beklenmeyen üründe fiziksel miktar sorulur.

---

## v1.14.54-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.54-RELEASE.apk`

**versionCode:** 200054 · **BC paketi:** 1.14.0.66

### Mal kabul: LP kapatıldıktan sonra yeniden başlatma

- `LP Kapat`, mal kabul başlığındaki LP bağlantısını korur.
- Aynı belgede tekrar `LP Başlat`, yeni LP/numara üretmeden mevcut kapalı LP'yi yeniden açar.
- Mevcut LP'nin ürünleri korunur ve sonraki ürünler aynı LP'ye eklenir.

### Doğrulama

- BCWMS AL `1.14.0.66`: derleme başarılı
- `Start → Stop → Start` aynı LP'yi yeniden açma senaryosu eklendi

---

## v1.14.53-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.53-RELEASE.apk`

**SHA-256:** `a4ca44b177587a5a32b0b9295e974261c7c2b6caf1b6d3c380d18c548b734051`

**versionCode:** 200053 · **minSdk:** 26 · **targetSdk:** 35

### Sayım V2: sadece okut — LP, ürün, lot

- **LP (MTE etiketi) okutma:** LP içeriği (ürün, lot, seri, birim, miktar)
  sunucuda olduğu gibi sayılır (`scanV2Lp`); tekrar okutma miktarı toplamaz.
  BC'de başka rafta kayıtlı LP hata vermez, bu rafta beklenmeyen stok olarak
  fark üretir. Geri alma LP bazında (`undoV2Lp`).
- **Ürün / lot barkodu okutma:** okutulan rafın BC stoku lot ve birim bazında
  "burada" diye teyit edilir; her lot ayrı satır. Aynı raf/ürün/lot ikinci
  okutmada toplanmaz. Rafta stok yoksa lotun/ürünün lokasyondaki BC miktarı bu
  rafa yazılır ("BC başka rafta biliyordu"); hiç yoksa yalnız uyarı. Hiçbir
  durumda miktar penceresi açılmaz.
- Miktar taşıyan QR'larda davranış değişmedi (otomatik satır).
- **Satıra dokun → miktarı düzelt** (`recordCount`); geri alma son LP /
  ürün okutmasının ürettiği tüm satırları kapsar.
- UOM, lot, seri artık hiçbir adımda elle girilmiyor.

Bu değişiklik BADE BCWMS AL `1.14.0.68` ister (`scanV2Lp`, `undoV2Lp`);
eski BC'de LP okutma "güncel paket yayınlanmalı" der, ürün/lot teyidi çalışır.
AL `1.14.0.68` ayrıca V2 geri almayı düzeltir: geri alınan okutma satırın tek
katkısıysa artık "0 sayıldı" (kayıtta stoku sıfırlayan eksi fark) bırakılmaz;
sayıcının kaydı silinir, başka sayıcı yoksa satır kalkar.

### SKT hızlı girişi ve sevkiyatta çoklu lot/raf

- Son kullanma tarihi yalnız rakamla girilir; `11122028` yazılırken uygulama
  ayraçları ekleyerek değeri `11.12.2028` biçimine getirir.
- Otomatik biçimlendirme sırasında imleç sonda tutulur; hızlı terminal girişinde
  gün, ay ve yıl hanelerinin sırası bozulmaz.
- Lot takipli sevkiyat satırına `Birden Fazla Lot / Raf Seç` eylemi eklendi.
- Çoklu seçim, BC'nin doğru depo akışı olan ambar toplamayı açar; mevcut toplama
  varsa onu kullanır, yoksa oluşturur. Farklı lot ve raf miktarları ayrı toplama
  satırlarından işlenir.
- Parantezsiz `01<GTIN>10<lot>` GS1 barkodları da ürün ve lot olarak doğru
  ayrıştırılır.

Bu Android sürümü BADE BCWMS AL `1.14.0.64` ile birlikte kullanılmalıdır.

### Doğrulama

- `testBadeDebugUnitTest`: **135 test, 0 hata**
- `assembleBadeRelease`: başarılı
- APK Signature Scheme v2: doğrulandı
- Emülatör SKT: `11122028 → 11.12.2028` başarılı
- Emülatör sevkiyat: `SH000273 / AB.00005` satırında çoklu lot/raf eylemi görünür
- Canlı BC verisi değiştirilmedi; toplama oluşturma eylemine testte basılmadı

---

## v1.14.52-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.52-RELEASE.apk`

**SHA-256:** `5fce8305ad102cc10b46e9deeda326e7e2e6ce626a265262d90c2283d6461a5b`

**versionCode:** 200052 · **minSdk:** 26 · **targetSdk:** 35


### Mal kabul: LP başlatma durumu ve ürün bağlantısı

- `LP Başlat` sonrası oluşan LP anında mal kabul başlığına bağlanır.
- Başarılı LP yanıtı, hemen ardından gelen gecikmeli belge yenilemesi
  tarafından artık silinmez; buton doğrudan `LP Kapat` olur.
- Satır onayı aktif LP numarasını koruduğu için okutulan ürün LP
  içine eklenir.
- Aynı belgeye art arda dokunulursa ikinci sahipsiz LP oluşturulmaz;
  mevcut açık LP döndürülür.

Bu Android sürümü BADE BCWMS AL `1.14.0.64` ile birlikte kullanılmalıdır.

### Doğrulama

- `testBadeDebugUnitTest`: **132 test, 0 hata**
- `assembleBadeRelease`: başarılı
- APK Signature Scheme v2: doğrulandı
- Simülatör: `RE000625 → LP000046 → HM.00181 / 1 KG / H100781` başarılı
- Mal kabul post edilmedi; test LP'si açık bırakıldı
- BC AL `1.14.0.64`: alc derlemesi başarılı

---

## v1.14.51-bade — 2026-08-27

**APK:** `BCWMS-BADE-1.14.51-RELEASE.apk`

**SHA-256:** `00d56ef42f59b880bf480c5bf97bf40680573e82e1f0135bed6a7abd111a5937`

**versionCode:** 200051 · **minSdk:** 26 · **targetSdk:** 35

### Mal kabul: tedarikçi lotu ve BADE başlık alanları

- Terminalden girilen tedarikçi lotu artık BC'deki **Madde İzleme
  Satırları → Tedarikçi Lotu** kolonuna da yazılır.
- Eski mobil sürümde yalnız Lot Bilgi Kartına kaydedilmiş değerler,
  mal kabul postundan önce takip satırına otomatik senkronlanır.
- Fiili alış tarihi, tedarikçi irsaliye numarası ve BADE araç/sürücü
  alanları için tamamlanan doğrulamalar bu pakete dahildir.
- Sayım V2, şirketin yerel WMS kullanıcı listesinde kaydı olmayan
  oturumlarda sayıcısız belge oluşturarak kullanılabilir kalır.

Bu Android sürümü BADE BCWMS AL `1.14.0.63` ile birlikte kullanılmalıdır.

### Doğrulama

- `testBadeDebugUnitTest`: **129 test, 0 hata**
- `assembleBadeRelease`: başarılı
- APK Signature Scheme v2: doğrulandı
- BC AL `1.14.0.63`: alc derlemesi başarılı

---

## v1.14.50-bade — 2026-08-27

**APK:** `bcwms-bade-1.14.50-sayim-v2-kullanici-release.apk`

**SHA-256:** `2f1b3530f35aa330f712525dfab3cb971e4d7c0801264ce2e719dacb3bd93bdd`

**versionCode:** 200050 · **minSdk:** 26 · **targetSdk:** 35

### Sayım V2 oluşturma: kullanıcı şirkette kayıtlı değilse net mesaj

- "Yeni V2 Sayımı → Oluştur ve Aç" hiçbir şey oluşturmuyor gibi görünüyordu:
  BC, sayıcı-1 olarak atanan terminal kullanıcısı o şirketin *Local WMS
  Users* listesinde yoksa `Count Counter → Local WMS User` tablo ilişkisi
  hatası veriyor, uygulama da bunu REF koduna çevirip diyaloğu açık bırakıyordu.
- Hata artık diyalog kapanınca listede okunuyor: "Terminal kullanıcısı (X) bu
  şirketin Local WMS Users listesinde kayıtlı değil. BC'de ekleyin veya kayıtlı
  bir WMS kullanıcısıyla giriş yapın."
- Başarısız her BC isteği artık `BCWMS.ApiError` etiketiyle logcat'e ham
  haliyle yazılıyor; REF kodu destek tarafında bu satırla eşleşir.
- BCWMS'in kendi Türkçe AL hataları (ör. "Araç bilgileri eksik…", "Terminal
  kullanıcısı … kayıtlı değil") artık CorrelationId eki yüzünden maskelenmiyor;
  operatör kullanıcı adı ve şirket gibi eyleme dönük bilgiyi görüyor. İngilizce
  BC/platform hataları maskelenmeye devam ediyor.

Bu Android sürümü BADE BCWMS AL `1.14.0.62` ile birlikte yayımlanmalıdır
(`build/al/BCWMS-BC-1.14.0.62-BADE.app`): `createV2` artık sayıcı atamasını
zorunlu tutmuyor — operatör şirketin Local WMS Users listesinde kayıtlı ve
etkinse sayıcı-1 olarak atanır, değilse belge sayıcısız açılır ve slot 1
herkese açık kalır (BC ve terminal sayıcısız belgeyi zaten destekliyordu).
Uygulamadaki "Local WMS Users" açıklaması yalnız eski BC paketleriyle görülür.

### Doğrulama

- `testBadeDebugUnitTest`: **129 test, 0 hata**
- `assembleBadeRelease`: başarılı
- BC AL `1.14.0.62`: alc derlemesi başarılı

---

## v1.14.49-bade — 2026-08-27

**APK:** `bcwms-bade-1.14.49-arac-bilgisi-release.apk`

**SHA-256:** `7063ebc5f5c974f33d4637d050728b2c7f07020456726ff4d6d2e0d68fc67b63`

**versionCode:** 200049 · **minSdk:** 26 · **targetSdk:** 35

### Mal kabul: BADE zorunlu başlık alanları (plaka / sürücü)

- BADE uzantısı mal kabul kaydında Fiili Alış Tarihi, Tedarikçi İrsaliye No,
  Araç Plaka No ve Sürücü Kodu'nu zorunlu tutuyor; terminal bu alanları
  giremediği için `Kaydet` HTTP 400 ile düşüyor ve ekranda yalnız
  "İşlem tamamlanamadı … REF-…" görünüyordu.
- Belge ekranına **Araç / Sürücü** kartı eklendi: plaka, tedarikçi irsaliye no
  ve BC'deki Araç Sürücüleri listesinden aranabilir sürücü seçimi. Bilgi
  eksikse `Kaydet` önce bu formu açar. Kart yalnız bu alanları isteyen
  şirketlerde (`vehicleInfoRequired`) görünür; diğer müşterilerde değişiklik yok.
- BC'nin "X must have a value in Y" hatası artık operatöre
  "Zorunlu alan boş: <alan> (<belge>)" olarak gösteriliyor (REF kodu korunuyor).
- Açık LP artık sunucudan okunuyor (`lpNo`/`lpOpen`): uygulama yeniden
  açılınca "Aktif LP" kaybolmuyor, ikinci bir LP başlatılmıyor.

Bu Android sürümü BADE BCWMS AL `1.14.0.59` ile birlikte yayımlanmalıdır
(`build/al/BCWMS-BC-1.14.0.59-BADE.app`): Receipt API'de `vehicleInfoRequired`,
`vehiclePlateNo`, `driverCode`, `driverName`, `vendorShipmentNo` alanları ve
`setVehicleInfo` / `listVehicleDrivers` aksiyonları; Kayıt Tarihi, Fiili Alış
Tarihi ve Tedarikçi İrsaliye No post öncesi otomatik dolduruluyor, plaka/sürücü
eksikse Türkçe hata ile erken duruluyor. **LP'li kabulün asıl kök nedeni:**
LP yayılım codeunit'i (72428) `Purch.-Post` sonrası `Purch. Rcpt. Line`'a LP
yazıyordu ve kullanıcı lisansı bu tabloya Modify vermiyordu (403 "Your license
does not grant…"); LP'siz kabulde bu kod hiç çalışmadığından sorun yalnız LP'li
belgelerde çıkıyordu. 72428 ve Receipt Mgmt'e dolaylı tablo izinleri
(`Permissions`) eklendi; akış artık kullanıcı lisansından bağımsız.

### Doğrulama

- `testBadeDebugUnitTest --tests ProductionUxRulesTest`: **10 test, 0 hata**
- `assembleBadeRelease`: başarılı
- BC AL `1.14.0.59`: alc derlemesi başarılı (325 dosya) (canlı post + put-away doğrulaması
  uzantı E-DefterSandbox'a yayımlandıktan sonra yapılacak)

---

## v1.14.28-bade — 2026-08-25

**APK:** `BCWMS-BADE-1.14.28-BAGLANTI-LP-SAYIM-DUZELTMELERI.apk`

**SHA-256:** `3c714c76e23715de5a4f0113c8688617e37d657d95cc9302beed6bc5fe58f4d5`

- Şirket bağlantısı artık tek bir LP veri sorgusunun sonucuna bağlı değil;
  giriş için gereken hafif WMS kullanıcı API'si esas alınıyor.
- Eski BC paketleri için LP bağlantı kontrolü yedek olarak korunuyor.
- Yetki, oturum, ağ ve eksik BC paketi hataları artık ayrı ve anlaşılır
  mesajlarla gösteriliyor.
- `testBadeReleaseUnitTest`: **91 test, 0 hata**; release derleme ve APK v2
  imza doğrulaması başarılı.

---

## v1.14.27-bade — 2026-08-25

**APK:** `BCWMS-BADE-1.14.27-LP-URUN-ADI-SAYIM-DUZELTMELERI.apk`

**SHA-256:** `feb78682c6a38d0239fc9ee742f49fa35c17aaefc39ecbc5c49137fee7460d2f`

**versionCode:** 1427 · **minSdk:** 26 · **targetSdk:** 35

### LP ürün seçimi ve sayım güvenliği

- LP satırına ürün numarası ve lot numarasının yanında ürün adıyla arayıp
  sonuç listesinden seçim yapma eklendi.
- Seri takipli ürünün LP satırına uygun olmayan doğrudan eklenmesi, işlem
  sonunda ham hata vermek yerine seçim aşamasında Türkçe uyarıyla durduruluyor.
- Boş `Open` ve `Unbuilt` LP'ler terminalden silinebiliyor; LP oluşturma bütün
  kanallarda şablon ölçülerini ve `Built` hareketini üreten tek iş kuralından geçiyor.
- Kaydedilmiş sayım belgesi ve satırları değiştirilemiyor; yalnız operatöre
  atanmış gerçek sayıcı slotları gösteriliyor ve kaydedilebiliyor.
- İki veya üç sayıcının miktar uyuşmazlığı satır bazında gösteriliyor, post
  durduruluyor; `Yeniden Say` bütün önceki miktarları ve bayrakları temizliyor.
- Fiziksel sayım günlük batch'i başka belge satırı içeriyorsa silme/post işlemi
  veri kaybını önlemek için durduruluyor.

Bu Android sürümü BADE BCWMS AL `1.14.0.42` ile birlikte yayımlanmalıdır.

### Doğrulama

- `testBadeReleaseUnitTest`: **88 test, 0 hata**
- `assembleBadeRelease`: başarılı
- APK Signature Scheme v2: doğrulandı; sertifika SHA-256:
  `ea7710af652faf6beff836d64327159b021c0561297cf9ae60987d26592b81eb`
- BC AL `1.14.0.42`: **323 dosya, derleme başarılı**

---

## v1.14.19-bade — 2026-08-24

**APK:** `bcwms-bade-1.14.19-production-release.apk`

**SHA-256:** `d5e955f52547834f94b7da8c20170b475800d080df186e9cd5b38b4c0321f40a`

**versionCode:** 1419 · **minSdk:** 26 · **targetSdk:** 35

### Güvenli üretim akışları ve sade operatör deneyimi

- Toplama, mal kabul, yerleştirme, sevkiyat, sayım, paketleme, montaj ve LP
  işlemleri; kullanıcı sahipliği ve belgenin bütün satırları doğrulanmadan
  değişiklik yapmayacak şekilde kapalı-güvenli hale getirildi.
- Büyük belge ve kuyruklarda sunucunun tüm sayfaları okunuyor. Eksik/bozuk bir
  sayfa, boş veya tamamlanmış belge gibi değerlendirilmeden operatöre yeniden
  deneme mesajı gösteriliyor.
- Lot/seri ve ölçü birimi alanları BC takip kurallarına göre seçiliyor; zorunlu
  lot bilgisi alınamadığında lotsuz kayıt engelleniyor. Doğrudan siparişte
  saklanamayacak takip bilgisi ambar belgesi akışına yönlendiriliyor.
- Aynı ürünün birden fazla lot/seri toplama satırı varsa okutulan takip
  bilgisi tam satır grubuyla eşleşmeden miktar veya onay ekranı açılmıyor.
- Sayımda sonradan rafa bağlanan LP'nin tüm satırları alınamazsa eksik veriyle
  miktar kaydına geçilmiyor; belge yenilenip operatöre tekrar deneme bildiriliyor.
- Doğrudan satınalma mal kabulünün satır ön kontrolü kısmen başarısız olursa
  kayıt durduruluyor, belge sunucudan yeniden okunuyor ve kısmi işlem uyarısı
  yenileme sonrasında da korunuyor.
- LP'ye raftan ürün eklemeden önce kaynak rafın tüm OData sayfaları okunuyor;
  doğrulama tamamlanamazsa stok veya LP hareketi oluşturulmuyor.
- LP raf hareketi ve LP içeriği aktarımı sunucu tarafındaki atomik işlemleri
  kullanıyor; yarım stok/LP hareketi oluşturabilecek ardışık mobil yazımlar
  kaldırıldı.
- Paketleme çift okutma, zaman aşımı sonrası uzlaşma, başarısız oturumun tekrar
  başlatılması ve koli kapatılırken bekleyen yazım kontrolleri güçlendirildi.
- Operatör ekranlarında test/teknik alanlar, boş tıklanabilir kontroller ve ham
  API ayrıntıları gizlendi; teknik hata ayrıntıları yalnız destek referansı ile
  kayda alınıyor. Şirket değişimi ve oturum kimliği yeniden doğrulanmadan
  operasyon butonları ve yalnız kullanıcıya atanmış kuyruklar açılmıyor.

Bu Android sürümü BADE BCWMS AL `1.14.0.36` veya daha yeni paketle birlikte
yayımlanmalıdır.

### Doğrulama

- `testBadeDebugUnitTest`: **77 test, 0 hata, 0 atlanan**
- `lintBadeDebug`: **0 hata**; 72 uyarı yalnız bağımlılık/sürüm, Compose
  performans önerisi ve proje yapılandırma kontrolleridir.
- `assembleBadeDebug` ve `assembleBadeRelease`: başarılı
- APK Signature Scheme v2: doğrulandı; sertifika SHA-256:
  `ea7710af652faf6beff836d64327159b021c0561297cf9ae60987d26592b81eb`

---

## v1.14.18-bade — 2026-08-24

**APK:** `bcwms-bade-1.14.18-production-stabilization-release.apk`

**SHA-256:** build sonrası doldurulacak

**versionCode:** 1418 · **minSdk:** 26 · **targetSdk:** 35

### Production stabilizasyonu

- Toplama satırları ve belge kaydı, terminalde oturum açan depo
  kullanıcısıyla sunucu tarafında doğrulanan atomik aksiyonlara taşındı;
  paralel satır yazımları ve başkasının belgesini kaydetme yolu kapatıldı.
- Paketlemede hızlı çift okutma, aynı kolinin farklı siparişte kullanımı,
  zaman aşımından sonra sunucuda tamamlanmış oturum ve yarım kalan ilk
  oturumu yeniden başlatma akışları güvenli hale getirildi.
- Sayım sayfalaması eksik sonuçta başarılı sayılmıyor; kaydetme/kayıt
  butonları belge ve veri tamamlanmadan açılmıyor, kritik işlemler onay istiyor.
- LP oluşturma/atama, ürün veya lotla arama, UOM ve zorunlu lot seçimi
  fail-closed çalışıyor. Müşteriye özel sabit şablon/lokasyon/raf kodları
  kaldırıldı; uygun şablon BC verisinden belirleniyor.
- Mal kabul, yerleştirme ve sevkiyat yalnız operatörün dokunduğu satırları
  kaydediyor; lot/seri takipli doğrudan siparişler doğru ambar belgesine
  yönlendiriliyor.
- BADE operatör arayüzü tek üretim akışına indirildi. V2 anahtarı,
  token/Azure CLI alanları, test menüleri ve boş tıklanabilir rozetler gizlendi;
  teknik API/HTTP ayrıntıları yerine kısa Türkçe hata metinleri gösteriliyor.

Bu Android sürümü, aynı teslimde derlenen güncel BADE BCWMS AL paketiyle
birlikte yayımlanmalıdır.

---

## v1.14.17-bade — 2026-08-21

**APK:** `bcwms-bade-1.14.17-release.apk`

**SHA-256:** `38e1bbda69bbf2746f41b944f852ae73e1083fe7a0c885f528a85cdc760f5fbf`

**versionCode:** 1417 · **minSdk:** 26 · **targetSdk:** 35

### LP — ürün/lot çözümleme, UOM seçimi ve zorunlu lot

- LP satırı eklerken ilk okutulan değer önce ürün numarası, ürün bulunamazsa
  pozitif stoklu lot numarası olarak aranır; lot artık ürün numarası diye BC'ye
  gönderilmez.
- Ölçü birimi elle yazılmaz; ürün kartındaki geçerli UOM listesinden seçilir.
- Lot takipli veya lokasyonda lotlu stoğu bulunan üründe stok lotu seçilmeden
  satır onaylanamaz. Aynı lot birden fazla üründe bulunursa doğru ürün seçtirilir.
- Sunucu tarafı da lot takipli ürünü boş lotla LP'ye eklemeyi reddeder.

Bu sürüm için BCWMS AL `1.14.0.35` paketi de yayımlanmalıdır.

---

## v1.14.16-bade — 2026-08-21

**APK:** `bcwms-bade-1.14.16-release.apk`

**SHA-256:** `0a5f743264ed86e3278762cce263abdfee2a72c03357c8ce7b2bb91651456a5a`

**versionCode:** 1416 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — düz lot kodunun yanlış ekrana yönlenmesi düzeltildi

- Aktif raftaki düz lot numarası artık ürün kodu sanılarak `Beklenmeyen
  fiziksel stok` ekranını açmıyor; ilgili lot satırı veya lot seçim ekranı
  doğrudan açılıyor.
- Rafta yerel eşleşme bulunmazsa kod BC ürün kartından doğrulanıyor: gerçek ürün
  kodunda mevcut beklenmeyen stok akışı korunuyor, ürün olmayan kod BC lot
  bakiyesinde aranıyor.
- Bir ürünün/lotun kayıtları sırayla açılmaya devam ediyor; önceki çoklu seçim
  denemesi bu sürüme dahil edilmedi.

---

## v1.14.15-bade — 2026-08-21

**APK:** `bcwms-bade-1.14.15-release.apk`

**SHA-256:** `5e2bad2bd657d3c06309b545f7b0f07b756e9a47d317ed158a93659952ed08f0`

**versionCode:** 1415 · **minSdk:** 26 · **targetSdk:** 35

### LP QR etiketi — Azure Direct müşteri sürümü

- LP içindeki `Yazdır` butonu, oluşturulan LP numarasını taşıyan QR etiketini
  güncel BCWMS AL paketi üzerinden Azure Direct yazıcı kuyruğuna gönderir.
- SSCC henüz oluşmamış açık LP'ler de kendi LP numarasıyla QR basabilir.
- Sayım lot görünürlüğü, BC depo gözündeki LP bilgisi, güvenli LP silme ve
  lokasyon uyuşmazlığı kontrolleri bu müşteri APK'sında birlikte bulunur.
- Tam yazdırma akışı için BCWMS AL `1.14.0.31` derlenip BADE şirketine
  yayınlanmalı ve Windows Print Agent kurulmalıdır.

---

## v1.14.14-bade — 2026-08-21

**APK:** `bcwms-bade-1.14.14-release.apk`

**SHA-256:** `ee38194c3534f53d70a69fa6ca17fec9c704630f9cee9d2fd685ecdb5bce98d3`

**versionCode:** 1414 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — lot miktarını açık gösterme ve yanlış lota girişi engelleme

- Sayım miktarı girişinde seçili lot/seri ve o lotun sistem miktarı belirgin
  olarak gösterilir; raftaki diğer lotların BC miktarları da ayrı listelenir.
- Rafın lotlu bakiyesi varken lotsuz sayım satırına miktar yazılması engellenir;
  operatörün lot satırını seçmesi veya lot barkodunu okutması istenir.
- 1., 2. ve 3. sayıcı tarafından daha önce girilen miktarlar aynı ekranda
  lot/seri bağlamıyla görünür.

### LP — depo gözü görünürlüğü, güvenli silme ve lokasyon kontrolü

- BC Bin Contents ve terminal depo gözü sorgusunda aktif LP numaraları ile
  ürünün aktif LP'lerdeki miktarı gösterilir. LP factbox'ı ürün, miktar ve lot
  özetini içerir.
- `Boz` işlemi LP satırlarını kaldırdıktan sonra Açık/Bozuldu ve boş LP için
  onaylı `Sil` işlemi açılır. Dolu veya işlem görmüş LP sunucuda da silinemez.
- Ürünün kaynak rafı ile LP lokasyonu farklıysa işlem mobilde gönderilmeden
  durdurulur; sunucu tarafındaki ikinci kontrol de stok hareketini reddeder.
- Aynı lokasyonda kaynak raf ile LP rafı farklıysa gerçek BC bin-to-bin
  hareketi yapılır; böylece LP ve ürün aynı depo gözünde kalır.
- LP içindeki `Yazdır` işlemi ZPL etikete LP numarasını taşıyan QR ekler ve
  Azure Direct işini aynı istekte kuyruğa gönderir; SSCC oluşmamış açık LP de
  QR etiketi basabilir.
- Bu sürümün tüm alanları ve işlemleri için BCWMS AL `1.14.0.31` paketi
  derlenip ilgili şirkete yayınlanmalıdır.

---

## v1.14.13-bade — 2026-08-21

**APK:** `bcwms-bade-1.14.13-release.apk`

**SHA-256:** `295ec8e099bbca938b3415285527974ea76389e39a498f31a512361f137fe163`

**versionCode:** 1413 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — fiziksel raf farkı, lot seçimi ve güvenli sürüm kontrolü

- Sayım satırında bulunmayan fiziksel ürün/lot için ürün, varyant, birim,
  lot/seri ve miktar doğrulama ekranı eklendi.
- Sistemde başka rafta görünen LP fiziksel rafta doğrulanabilir; sayım başarıyla
  post edildikten sonra LP rafı fiziksel adresle eşitlenir.
- Terminalde görünen fakat fiziksel rafta bulunmayan satırlar, adres kapatılırken
  açık onayla kalıcı `0` sayım olarak kaydedilir.
- Ürün+lot etiketi tam eşleşmeyle seçilir; aynı ürünün başka lotuna düşme
  engellendi. Aynı lot için birden fazla kayıt varsa madde/LP/miktar seçim
  ekranı açılır.
- BADE sürümü varsayılan şirketi artık şirket listesinden tam adıyla çözer;
  eski `CRONUS USA, Inc.` varsayılanı otomatik temizlenir.
- Yeni fark işlemleri BCWMS AL `1.14.0.30` gerektirir. Sunucuda eski paket varsa
  normal sayım çalışmaya devam eder; desteklenmeyen işlemler HTTP hatasına
  gönderilmeden kapatılır ve ekranda paket gereksinimi gösterilir.

---

## v1.14.12-bade — 2026-08-20

**APK:** `bcwms-bade-1.14.12-release.apk`

**SHA-256:** `f18ce367fa11dec85cda1e55df8560bb1070991ee2c45d01a513657b2bc5b5e6`

**versionCode:** 1412 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — lot/seri bazlı miktar görünürlüğü

- LP dışındaki raf stoku artık ürün toplamı yerine Warehouse Entry bakiyesine
  göre lot/seri kırılımında ayrı sayım satırlarına dönüştürülür.
- Terminalde ürün ve LP satırlarında lot/seri, sistem miktarı ve seçili
  sayıcının girdiği miktar birlikte gösterilir.
- Satır düzeltme ekranı daha önce girilmiş 1./2./3. sayım miktarlarını gösterir;
  slot değiştirilince ilgili slotun değeri düzenlemeye açılır.
- Sayım içindeki LP kartına doğrudan **LP etiketini yazdır** düğmesi eklendi.
- Bu sürüm, BCWMS AL `1.14.0.29` paketiyle birlikte kullanılmalıdır.

---

## v1.14.11-bade — 2026-08-20

**APK:** `bcwms-bade-1.14.11-release.apk`

**SHA-256:** `233c080867c92ad24064eff82fe382a474821d82d7197b296f75eea7159780c5`

**versionCode:** 1411 · **minSdk:** 26 · **targetSdk:** 35

### LP — gerçek raf stok hareketi

- LP'ye satır eklenirken kaynak raf ile LP rafı farklıysa BC bin-to-bin
  hareketi aynı işlem içinde kaydedilir.
- Hareket veya LP satırı hata verirse ikisi de geri alınır; yalnızca LP
  satırı oluşturan eski geri dönüş yolu kaldırıldı.
- Yetersiz veya başka aktif LP'lere ayrılmış stok açık hata ile reddedilir.
- Satırdaki adres artık `Kaynak raf` etiketiyle gösterilir.
- Bu sürüm, BCWMS AL `1.14.0.28` paketiyle birlikte kullanılmalıdır.

---

## v1.14.10-bade — 2026-08-20

**APK:** `bcwms-bade-1.14.10-release.apk`

**SHA-256:** `76ac84f7ea494d71ab2224629c35f533d8b1b5e55bee730867fe7eedd005775b`

**versionCode:** 1410 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — rafsız LP ilk yerleştirme

- Rafı boş LP artık `Satır Üret` işlemini durdurmaz.
- Operatör önce rafı, sonra LP'yi okuttuğunda LP okutulan rafa bağlanır ve
  LP satırları açık sayım belgesine eklenir.
- LP miktarı, aynı raftaki paletsiz sistem stokundan düşülür; çift sayım
  önlenir. BC raf stoku yoksa/yetersizse işlem açık hata verir.
- LP başka bir rafa önceden atanmışsa otomatik taşınmaz; fiziksel doğrulama
  istenir.

### BC — sayıcı kullanıcı seçimi

- Count Counters / User ID seçimi, terminal operatörlerinin bulunduğu etkin
  `Local WMS Users` listesine bağlandı.
- Seçimden sonra Assigned DateTime otomatik dolar; serbest metin ve standart
  BC User tablosu kaynaklı seçim hataları kaldırıldı.

---

## v1.14.9-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.9-release.apk`

**SHA-256:** `66c758ada6daaa7429c05830f88ea6fc028c6e7024abe38c40347a93f00c2136`

**versionCode:** 1409 · **minSdk:** 26 · **targetSdk:** 35

### Sayım — nihai adres bazlı akış

- **Etiket okutunca bilgi kartı:** madde no + ürün adı + miktar. LP'li kalemde
  miktar etiketten gelir (GS1 AI 30/37 varsa QR'dan, yoksa LP kaydından) ve tek
  tuşla onaylanır. **LP'siz (dökme) kalemde otomatik miktar yok** — depocu
  saydığını elle girmeden kaydedemez.
- Ürün barkodu paletli satıra denk gelirse kalem PALET olarak açılır (tek
  satırı sayıp paleti bitti işaretleme hatası kapatıldı).
- Sayım yazıldıktan sonra satırlar hemen tazelenir: aynı ürünün ikinci lotu
  okutulunca ilk satırın üstüne yazma hatası kapatıldı.
- **Sayıcı slotları artık gerçekten bağımsız:** sayıldı-durumu seçili slota
  göre hesaplanır; 2./3. sayıcı okutarak yeniden sayım yapabilir. Satır
  düzeltme ekranı paneldeki slotu devralır (yanlışlıkla slot 1'i ezme bitti).
- 'Yeniden Say' pane ilerlemesini sıfırlar; sayılmış palet ikinci adresten tek
  tuşla ezilemez; bilgi kartı açıkken ikinci okutma işlenmez.
- Miktar girişinde virgül noktaya çevrilir (12,5 → 125 hatası kapandı);
  geçersiz girdide buton kilitli (sessiz 0 kaydı bitti).
- 200+ satırlı sayfalarda sayfalama: tüm satırlar yüklenir (5000 tavan).
- **Ekran netliği:** adres kartlarında X/Y sayıldı + ilerleme çubuğu; sayılan
  kalemde yeşil 'Sayılan: N', sayılmayanda gri 'Sistem: N'.
- GS1 çözümleme sağlamlaştırıldı: AI 02/30/37, FNC1 sonrası sabit AI, 00
  önekli 20 haneli SSCC.

### BC (AL — Windows'ta publish bekliyor)

- Count Sheet Card'a 'Sayım Durumu' paneli: Toplam/Sayılan/Kalan/Farklı Satır.
- Count Sheet Lines: 'Sayıldı' kolonu + satır renkleri (yeşil=fark yok,
  turuncu=fark var), Description kolonu.

### Bilinen sınırlamalar

- 0 girilen sayım sunucuda 'hiç sayılmadı'dan ayırt edilemiyor (şemada bayrak
  yok); adres kapatma/tekrar giriş 0'lı satırları bekliyor gösterebilir. Kalıcı
  çözüm AL şema değişikliği (Counted bayrağı) gerektirir.
- Etiket QR'ında miktar yoksa LP kaydı esas alınır — müşterinin QR formatı
  netleşince ayrıştırıcı uyarlanmalı.

---

## v1.14.8-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.8-release.apk`

**SHA-256:** `68c3189ae998913a69bacf310111e6064fc619d560e2e8b215e425db6fd8383e`

**versionCode:** 1408 · **minSdk:** 26 · **targetSdk:** 35

### Değişiklikler

- **Etiket okutunca bilgi kartı açılıyor:** madde no, ürün adı, miktar (+ birim,
  lot/seri) gösterilir; onaylayınca okutulan adrese sayıldı olarak yazılır.
  Kart hem LP etiketini hem ürünün kendi barkodunu (madde no / ürün referansı /
  GTIN) tanır. Ürün adı sayım satırında boşsa ürün kartından tamamlanır.
  Miktar farklıysa karta dokunup elle girilebilir.
- Yanlış adreste okutulan palet uyarısı bilgi kartının içine taşındı.
- **Kör (Blind) mod terminalden kaldırıldı.** Sayım palet/etiket doğrulamasıyla
  yürüdüğü için miktar her zaman gösterilir; BC'deki Mode alanı ne olursa olsun
  terminal miktarı gizlemez, KÖR rozeti kalktı.

---

## v1.14.7-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.7-release.apk`

**SHA-256:** `367766dab25b07d886c1db043819c4a25c261cc7741c3aaba94fd1937d1cef79`

**versionCode:** 1407 · **minSdk:** 26 · **targetSdk:** 35

### Değişiklikler

- **Sayım artık adres bazlı yürüyor — tek akış.** Sayım belgesi açılınca doğrudan
  adres listesi gelir: rafı okut (veya listeden seç) → o rafta beklenen paletler
  listelenir → LP'leri tek tek okut → "Adresi Kapat" → sonraki rafa geç. LP
  okutmak paleti tam kabul eder, miktar girmeye gerek yoktur. Adres
  kapatılırken okutulmayan paletler onay alınarak eksik (0) sayılır.
  Yanlış adreste okutulan palet uyarı verir; paletsiz stok ve içeriği hatalı
  palet için satıra dokunup miktar elle girilebilir.
- Eski satır listesi (grid + kolon seçici) sayım ekranından kaldırıldı; süreç
  tek ve yönlendirilmiş hale getirildi.

---

## v1.14.6-bade — 2026-08-19

**APK:** `bcwms-bade-1.14.6-release.apk`

**SHA-256:** `7ad6144520cfd8e706f413cad9540ff594ce8530a0785dcf46aee33d88795f42`

**versionCode:** 1406 · **minSdk:** 26 · **targetSdk:** 35

### Yenilikler

- **Yerleştirmede adım adım doğrulama.** Bir yerleştirmeye dokunulduğunda
  kaynak raf → ürün → hedef raf → miktar sırasıyla ilerlenir. Her adımda
  okutulan barkod belgedeki beklenen değerle karşılaştırılır; uyuşmazsa
  "Yanlış raf/ürün — Beklenen: X" uyarısı çıkar ve adım ilerlemez. Kaynak raf
  bilgisi belgede yoksa o adım atlanır.
- **Sevkiyat ve toplamada lot seçimi.** "Stoktaki Lotlardan Seç" listesi artık
  her zaman görünür; elde pozitif stoklu lotları miktar ve rafıyla listeler.
  Ürünün stoğunda lot varsa lot alanı otomatik olarak zorunlu olur ve boş
  bırakılırsa satır onaylanamaz — BC'deki `lotRequired` alanı gelmese bile.
  Toplama ekranında lot alanı önceden ne zorunluydu ne de seçim listesi vardı.

---

## v1.14.2-bade — 2026-08-12

**APK:** `bcwms-bade-1.14.2-barcode-auto-print-release.apk`

**SHA-256:** `752ba4c9ab7b741e329653becddad646f748c71fa50f352d4adb936d097fbe41`

**versionCode:** 1402 · **minSdk:** 26 · **targetSdk:** 35

### Düzeltmeler

- Barkod okutulduğunda/yazdırıldığında terminal klavyesi kapanır.
- Barkod test işi BC'de bekleyen `Queued` satır olarak bırakılmaz; aynı API
  isteğinde Azure'a gönderilir. Bir dakikalık worker çevrimini veya elle
  `Validate Azure Print` çalıştırmayı beklemez.

---

## v1.14.1-bade — 2026-08-12

**APK:** `bcwms-bade-1.14.1-barcode-print-test-release.apk`

**SHA-256:** `9cee4b0061cde859eccdd6d9ee5cd9b6b92f000061dfeab58d6a833b9e98e682`

**versionCode:** 1401 · **minSdk:** 26 · **targetSdk:** 35

### Bu sürümde

- **Yazıcılar → Barkod Baskı Testi** eklendi.
- Donanım okuyucu, kamera veya elle girişle alınan ham barkod numarası terminalde
  büyük olarak gösterilir.
- Okunan numara seçili PDF belge yazıcısına tek sayfalık test çıktısı olarak
  gönderilir.
- Bu özellik, gerçek Code 128 barkod çıktısı ve Azure üzerinden otomatik baskı için BCWMS AL extension `1.14.0.7` veya üstü gerekir.

---

## v1.10.0 — 2026-06-24

**APK:** `bcwms-1.10.0-debug.apk` (32 MB)
**SHA-256:** `c19f10a73ca5edf41971898a74509e798ca0f463c57377211dbedbeb0f0e9020`
**versionCode:** 110 · **minSdk:** 26 · **targetSdk:** 35

### Bu sürümde

- 🩺 **Sistem Sağlığı** paneli (yeni): 10 check probe BC API + ScanBus +
  PWA service worker + localStorage — kurulum sonrası tek-dokunuş smoke test
- 📷 **Picking Tara & Doğrula** (yeni): barkod ↔ itemNo eşleşmedikçe
  updateLine çağrılmaz; yanlış ürün toplanma riski elimine edildi
- 📋 **Posting Test grouping** (yeni): 4 kategori — Passed / Real Failure
  / Setup Eksik (gizli tab) / Cascade Atlandı (gizli tab); her Setup
  satırında BC sayfa hint'i
- ⚙️ **DocSearchBar** (yeni): 11 list ekranında ortak belge no arama
  (Picking, Receiving Tab1/Tab2, PutAway, Shipping Tab1/Tab2, Count,
  Movement, LP, Production×2, Assembly, Quality)
- 🔧 **SheetScaffold** (yeni): 10 BottomSheet refactor — klavye açılınca
  Onayla button artık görünür (verticalScroll + imePadding wrapper)
- 🛡 **ActionGuards** (yeni): qty=0 iken Post/Register button disabled
- 🔵 **Zebra DataWedge** entegrasyonu (yeni): ScanBus event bus +
  focus-based subscribe; cold-start intent drop fix (Codex Finding 7)
- 📊 **Item Inquiry stok bloğu** (yeni): inventory + 4 FlowField
  (qty on PO/SO/Prod + reserved); blocked chip
- 📍 **Bin Inquiry içerik tablosu** (yeni): T7302 Bin Content gerçek item
  miktarları (LP listesinin üstünde)
- 🏷 **LP Build template dropdown**: licensePlateTemplates'tan seçim
- 🖨 **LP printLabel default printer**: getDefaultPrinter() ile otomatik
- 🐛 Codex review wave 1+2 fix'leri:
  - ItemApi `OnAfterGetRecord` trigger + 5 FlowField CalcFields
  - PickingModule ScanVerifySheet race fix (busy atomic)
  - MainActivity DataWedge cold-start LaunchedEffect dispatch
  - PickingModule OData filter merge → `buildList` pattern

### BC tarafı gereksinimleri

DOPSWHS extension v1.10.0 publish edilmiş olmalı. Aksi halde Sistem
Sağlığı'nda 3 API check FAIL döner (BinContentApi 72097, ItemApi
inventory, LPTemplateApi 72280).

### Önceki sürümler

v1.8.2.0 ve öncesi BC AL paketleri `releases/bcwmsapp-*.app` altında.
Android APK arşivi v1.10.0'dan itibaren `releases/android/` altında.
