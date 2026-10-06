# Mail Taslağı — Deniz Bey (detaylı sürüm)

**Konu:** ELOG Lojistik Depo Ziyareti (7 Temmuz) — Saha Gözlemleri, Mevcut Durumumuz, Eksiklerimiz ve Geliştirme Planı

Deniz Bey merhaba,

Dün ELOG Lojistik'in deposuna gerçekleştirdiğimiz ziyarette, sahada Insight Works **Warehouse Insight** ürünüyle yürüttükleri toplama (pick) ve paketleme (pack) süreçlerini uçtan uca inceleme fırsatı bulduk. Kendi el terminali WMS uygulamamız için hem doğrulama hem de yol haritası açısından oldukça verimli bir ziyaret oldu. Aşağıda saha gözlemlerimi, uygulamamızın mevcut durumunu, tespit ettiğim eksikleri ve geliştirme planımı detaylı olarak paylaşıyorum; ekte ayrıca karşılaştırma tablolarını içeren raporu bulabilirsiniz.

## 1. Saha Gözlemleri

**Depo ve taşıyıcı yapısı:**
- Depo tamamen **bin (raf gözü) bazlı** yönetiliyor; tüm bin'ler barkodlu.
- İki tip taşıyıcı plaka (LP) kullanılıyor: **kalıcı LP'ler** barkod etiketli kırmızı/sarı plastik sepetler (ör. T-06-K0, T-06-S3), **geçici LP'ler** ise tek sevkiyatlık karton kutular.
- Toplama boyunca **bir sepet = bir sipariş** kuralı işletiliyor; siparişler toplama biterken sepetlere ayrışmış oluyor.

**Üç toplama modu gözlemledik:**
- **Multi:** Ofisteki kullanıcı BC üzerinde ~20 siparişi tek bir pick altında birleştirip depo çalışanına atıyor (veya çalışan görevi kendi üzerine alıyor). Çalışan ilk raftan son rafa doğru yürüyor; **rafı okutuyor** ve o raftan alması gereken ürünleri görüyor, **ürünü okutuyor**, sistem ürünün konulacağı **sepeti öneriyor**, miktarı girip **sepeti okutarak** ürünü yerleştiriyor. Farklı ürünler içerdiği için batch/bulk'a göre daha yavaş ilerliyor.
- **Bulk:** Aynı ürün birden fazla siparişe dağılıyor (ör. sepette 6 adet krem, 2+2+2 olarak üç siparişe atanmış).
- **Batch:** Tek ürünlük (mono-SKU) siparişler; her bir ürün ayrı bir siparişi temsil ediyor.

**Paketleme istasyonu:** Paketleme BC üzerinde özel worksheet sayfalarıyla yapılıyor (Batch Package Worksheet ve Mono-SKU Batch Package Worksheet; ekran fotoğraflarını raporda paylaştım):
- Paketleyici önce **sepeti okutuyor**; sepette olması gereken satırlar ekranda **kırmızı (bekliyor)** olarak listeleniyor.
- Ardından kullanılacak **kutuyu okutuyor** ve ürünleri **tek tek okutuyor**; okutuldukça satırlar düzeliyor.
- Bir siparişin tüm ürünleri tamamlandığında **fiş/fatura otomatik basılıyor**, poşete yapıştırılıp kargoya yönlendiriliyor.
- **Bulk'ta** her siparişin payı tamamlandığında (ör. her 2 adette bir) o siparişin fişi ayrı basılıyor; sıraya ait olmayan **farklı bir ürün okutulduğunda sistem hata veriyor**.
- **Batch'te** sepet bir kez okutuluyor; ürün okut → kutu okut döngüsüyle her ürün ayrı bir siparişi kapatıp faturasını kestiriyor.

**Müşterinin doğrudan talebi:** El terminalinde **bin kodu ve ürün numarası aynı olan satırların birleştirilip tek satır olarak gösterilmesi** (miktar toplam gelecek şekilde).

## 2. Mevcut Durumumuz (BCWMS)

Ziyaret sonrası uygulamamızı bu gözlemler ışığında yeniden analiz ettim. Güçlü olduğumuz alanlar:

- **LP altyapımız rakip ürünün önünde:** Tam yaşam döngüsü (Açık → Kurulu → Atandı → Kullanıldı), "Reusable Tote" şablonuyla kalıcı/geçici ayrımı, iç içe paletleme (nesting), SSCC-18 üretimi, LP hareket defteri, kısmi kullanım/bölme ve web tarafında LP Browser. LP kimliği deftere nakil sonrası belgelere de taşınıyor.
- **Baskı altyapısı hazır:** Üç kanallı merkezi baskı yöneticisi (BC Native / PrintNode / Self-Hosted agent), ZPL etiketleri, baskı kuyruğu ve cihaz–yazıcı eşleme.
- **Görev atama ekranları mevcut:** Ops Console (KPI + doküman bazlı atama) ve Pick Board (çalışan bazlı kanban, sürükle-bırak yeniden atama); terminalde "üzerime al".
- Terminalde mal kabul, yerleştirme, toplama (barkod doğrulama, eksik toplama nedenleri), sevkiyat, sayım, hareket, üretim/montaj ve kalite modülleri çalışır durumda.

## 3. Eksiklerimiz

- **Paketleme istasyonu yok:** "Sepet okut → bekleyen satırlar kırmızı → kutu okut → ürün okut → sipariş tamamlanınca fiş bas" akışının karşılığı bizde yok; paketleme şu an sevkiyat deftere nakil akışına gömülü. Mono-SKU ve bulk varyantları da yok.
- **Multi-order pick yok:** Siparişleri gruplayıp tek pick oluşturma ve çalışana atama mekanizması hiçbir katmanda yok; toplama tek doküman bazında yürüyor.
- **Bin yönlendirmeli akış yok:** Terminalde satır tamamlama ürün barkodu üzerinden; raf okutup o rafın satırlarını görme akışı yok.
- **Sepet–sipariş eşleştirme yok:** Pick başına tek aktif sepet tutuluyor; sistemin ürün başına "şu sepete koy" önerisi yapabilmesi için sipariş bazlı sepet ataması gerekiyor.
- **Paket anında fiş basımı yok:** Fiş/fatura yalnızca deftere nakil sırasında basılabiliyor.
- **Satır birleştirme kısmen var:** Birleştirme fonksiyonu kodda yazılı ve miktar dağıtımını da yapıyor, ancak şu an yalnızca Mal Kabul ekranına bağlı; müşteri talebi olan toplama/sevkiyat tarafına henüz bağlı değil.

## 4. Yapacaklarımız

Önceliklendirilmiş planım şu şekilde:

1. **Satır birleştirme (bin + ürün)** — doğrudan müşteri talebi; altyapı hazır olduğu için hızlı kazanım. Toplama ve sevkiyat ekranlarına bağlanacak.
2. **Sepet–sipariş eşleştirme** — toplama sırasında her siparişe bir sepet (reusable LP) atanması; mevcut LP altyapısının üzerine kurulacak.
3. **Paketleme istasyonu modülü** — sepet okut → kutu okut → ürün okut döngüsü, bekleyen satırların kırmızı gösterimi, bulk (sipariş payı takibi + yanlış ürün hatası) ve mono-SKU varyantları.
4. **Paket anında otomatik fiş/fatura basımı** — mevcut baskı yöneticisine bağlanarak, sipariş payı tamamlandığı anda istasyon yazıcısından basım.
5. **Multi-order pick** — BC/Ops Console tarafında "siparişleri seç → tek pick oluştur → ata" akışı; terminalde bin yönlendirmeli yürüyüş ve sepet önerisi.

**İlk maddenin (satır birleştirme) geliştirmesine bugün itibarıyla başladım.** İlerlemeyi ve ilk çıktıları **Perşembe günü (10 Temmuz)** size detaylı olarak sunacağım; paketleme istasyonu için de aynı bilgilendirmede taslak ekran akışını paylaşmayı hedefliyorum.

Detaylı gözlem raporu ve karşılaştırma tabloları ektedir. Sorularınız olursa memnuniyetle aktarırım.

Saygılarımla,
Kaan
