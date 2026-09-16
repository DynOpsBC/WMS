# EMU / DKÇ — LP etiketleri, otomatik LP kuralları, belge bağlama, paketleme listesi

BC paketi **1.14.2.0**, Android **1.14.117 (emu)**. Yalnız `customer/emu` dalında; BADE'ye dokunulmadı.

## 1. Şablona göre etiket tasarımı

LP Şablonları (Kurulum → LP Templates) sayfasına dört alan eklendi:

| Alan | Anlamı |
|---|---|
| **Kap Türü** (Container Kind) | Palet / Koli / Kutu / Çuval / Sepet / Diğer. Etiket tasarımını ve paketleme listesindeki sayaçları belirler. |
| **Etiket Tasarımı** (Label Design) | *Kaba göre* (varsayılan): kap türüne uygun ZPL. *Standart LP*: eski etiket. *Palet/Koli/Kutu/Çuval*: türden bağımsız seçim. *Rapor (PDF)*: `Label Report ID` raporu belge yazıcısından basılır. |
| **Etikette İçerik Listelensin** | Açık: iç katmanlar (alt LP'ler ve madde satırları, en çok 3 satır + "+N satır daha") etikete yazılır. Kapalı: yalnız özet. Kutu/koli etiketi kapalıyken de ilk maddeyi gösterir. |
| **Kopya Sayısı** | Tek "Etiket Yazdır" ile çıkan kopya (0 = 1). |

Bütün tasarımlar 4×2 inç (812×406 nokta, 203 dpi); mevcut Zebra rulosu değişmez. Her etikette QR = LP numarası
(terminal aynı kaydı açar), Code128 = LP kapatıldıysa SSCC, değilse LP numarası.

Önizlemeler: `docs/labels/emu/` — `palet-icerikli.png`, `palet-ozet.png`, `koli.png`, `kutu.png`, `cuval.png`
(aynı ZPL, Labelary ile çizildi).

**Basım noktaları (tek düğme, tipe göre şablon):**
- BC: LP kartı → **Etiket Yazdır** (şablon kopya sayısıyla).
- Terminal: LP kartı → **Etiket Yazdır**; LP listesi → **Seçilenleri Yazdır** (her LP kendi tasarımı).
- Otomatik: LP kapatılınca (Stop) ve kural açıksa belge kaydında (aşağıda).
- Ürün ve raf etiketleri: Ürün Sorgu / Raf Sorgu → Etiket Yazdır (mevcut).

Kod: `DOPSWHS LP Label Builder` (72302). `Print Dispatcher.PrintLPLabel` kopya 0 gelirse şablon kopyasını kullanır;
tasarım *Rapor (PDF)* ise `Label Report ID` raporunu belge yazıcısına gönderir.

## 2. Kural bazlı otomatik LP

Kurulum → **LP Auto Rules** (tablo 72236). Anahtar: Lokasyon × Belge Türü (Ambar Mal Kabul / Ambar Sevkiyat).
Boş lokasyonlu kural, kendi kuralı olmayan bütün lokasyonlar için geçerlidir.

| Alan | Davranış |
|---|---|
| Oluşturma Modu | *Belge başına*: belgenin ilk satırı eklenince başlığa bağlı bir LP (`DOPSWHS LP No.`). *Satır başına*: her satıra ayrı LP. |
| LP Şablonu | Açılan LP'nin şablonu (tasarım, tare, kap türü). |
| Kayıtta Kapat (SSCC) | Belge kaydedilince açık LP'ler kapatılır, SSCC üretilir. |
| Kayıtta Belgeden Doldur | BC istemcisinden kaydedilen belgede boş kalan otomatik LP, kaydedilen satırlarla (lot/seri dahil) doldurulur. Terminalden onaylanan satırlar zaten LP'ye yazılır. |
| Kayıtta Etiket Bas | Kapatılan LP'nin şablon etiketi belirtilen yazıcıya (boşsa cihaz/lokasyon eşlemesi) gönderilir. |

Olaylar: `Warehouse Receipt Line` / `Warehouse Shipment Line` OnAfterInsert (oluşturma),
`Whse.-Post Receipt.OnAfterCode` ve `Whse.-Post Shipment.OnPostUpdateWhseDocumentsOnBeforeWhseShptHeaderParamModify`
(kayıt). Kayıt sonrası işler TryFunction içindedir: yazıcı/kural hatası kaydı geri almaz, telemetriye
`LPAutoRule.*` uyarısı düşer. Terminalin mal kabul akışında ayrılan (Pending Receipt) LP'lere dokunulmaz.

## 3. LP'yi her belgeye bağla, satırları içine çek

`DOPSWHS Assigned Doc Type` enum'una eklendi: Satış Siparişi, Satınalma Siparişi, Transfer Siparişi ve kayıtlı
belgeler (satış sevki, alış irsaliyesi, ambar mal kabul/sevkiyat, transfer sevk/alım).

**Belgeden Satırları Çek** (BC LP kartı, terminal LP kartı → *Belgeden Doldur*, API `licensePlates/pullFromDocument`):
- Açık belgelerde kalan miktar (Outstanding), kayıtlı belgelerde kaydedilen miktar.
- Lot/seri: açık belgelerde Item Tracking (Reservation Entry), kayıtlı belgelerde madde defteri girişleri
  (ambar belgelerinde `Whse. Item Entry Relation`). Her lot/seri ayrı LP satırı olur.
- LP satırlarına kaynak belge türü/no/satır no ve belge miktarı yazılır.
- LP başlığındaki anlık görüntü alanları (**Belge / Sevk Bilgisi** grubu): kaynak belge türü/no/tarih, dış belge no,
  müşteri/tedarikçi/lokasyon no-adı, sevk kodu/ad/adres/şehir/posta kodu/ülke, **Sevkiyat Yöntemi**, acente/servis,
  konteyner no, mühür no, tare. Kaynak belge silinse veya kaydedilse de LP'de kalır.
- LP bir belgeye atanınca (Assign) anlık görüntü boşsa kendiliğinden doldurulur; **Belge Bilgisini Yenile** yeniden okur.

Kod: `DOPSWHS LP Document Link` (72239).

## 4. Paketleme listesi

Rapor **72315 "Paketleme Listesi"** (A4, RDLC `src/Ship/PackingList.rdlc`). Palet → koli → kutu → madde hiyerarşisi;
her kap için SSCC, net (madde net ağırlığı × miktar) ve brüt (net + kap tare) ağırlık; başlıkta belge, müşteri,
sevk adresi, sevkiyat yöntemi/acente, **konteyner ve mühür no**; özet satırında palet/koli/kutu/çuval sayıları ve
toplam net/brüt.

- Ambar Sevkiyatı kartı: **Paketleme Listesi** (önizleme) + başlıkta Konteyner No. / Mühür No. alanları;
  kayıtta posted sevkiyata taşınır (Posted Whse. Shipment kartında da vardır).
- Terminal sevkiyat ekranı: **Paketleme Listesi** düğmesi → belge yazıcısına PDF (`shipments/printPackingList`);
  konteyner/mühür için `shipments/setContainer`.
- LP kartı (BC ve terminal): tek palet/kök kap için paketleme listesi.
- Kurulum → **Auto Print Packing List** açıksa terminalden sevkiyat kaydında liste kendiliğinden kuyruğa girer.

Kök kaplar: sevkiyat başlığı LP'si, satır LP'leri, sevkiyata atanmış LP'ler ve kaynağı bu belge olan LP'ler; iç içe
kaplar en üst kaba kadar toparlanır. Kod: `DOPSWHS Packing List Mgt.` (72319), tampon tablo 72316.

## 5. Terminal ↔ yazıcı (Ömer Bey'in sorusu)

Kurulum → **Print Channel = Azure Direct** zaten DKÇ'deki kurulumdur: terminal → BC → Azure Service Bus/Blob →
Windows **BCWMS Print Agent** → ZPL etiket yazıcısı / PDF belge yazıcısı. Ayrı bir "DynOps Print Agent" kanalına
gerek yok; ZPL etiketler (LP, ürün, raf) etiket yazıcısına, PDF'ler (paketleme listesi, rapor tasarımlı etiket)
belge yazıcısına gider. Kurulum adımları `releases/docs/BADE-LP-QR-Azure-Yazici-Kurulum.md` ile aynıdır
(istasyon secret dosyası DKÇ için üretilir). Aynı Windows yazıcısı hem etiket hem belge rolüne alınamaz;
PDF çıktılar için ayrı bir Windows yazıcı kuyruğu (veya belge yazıcısı) gerekir.

## Kurulum sırası (DKÇ)

1. BC 1.14.2.0 paketini yükle (1.14.1.x üzerine yükseltme; tablo alanları eklenir, veri değişmez).
2. LP Templates: her şablona Kap Türü, Etiket Tasarımı, İçerik, Kopya ata (ör. PALLET-EUR = Palet, KOLI = Koli, KUTU = Kutu, CUVAL = Çuval).
3. LP Auto Rules: örn. `''` × Ambar Mal Kabul → Belge başına, PALLET-EUR, Kayıtta Kapat + Etiket Bas.
4. Kurulum → Auto Print Packing List (isteğe bağlı).
5. Terminal 1.14.117 (emu) ve Yazıcılar ekranında etiket/belge yazıcısı seçimi.

## Test edilmeyenler

alc 0 hata ve AL test codeunit'i (72498) derlendi; BC ortamında çalıştırılmadı. Kayıt olayı abonelikleri
(`OnAfterCode`, `OnPostUpdateWhseDocumentsOnBeforeWhseShptHeaderParamModify`) canlı bir mal kabul / sevkiyat ile
doğrulanmalı. RDLC paketleme listesi BC'de önizlenmedi.
