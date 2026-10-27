#!/usr/bin/env python3
"""Kitoko · El Terminali Stok Hareketleri Kılavuzu (Kitoko Aydınlatma ve Müh. A.Ş. uyarlaması).

generate-kitoko-stock-guide.py (Element 4 sürümü) kopyalanıp uyarlanmıştır; Element 4 dosyası değiştirilmez.
Terminal ekran adımları aynıdır (aynı uygulama). Şirket / bağlantı / lokasyon bilgileri 27.10.2026 tarihinde
BC standart API ve BCWMS API (dynops/warehouse/v2.0) üzerinden yalnız GET ile doğrulanmıştır:
  Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.: BCWMS ürün 0, lokasyon 0, raf 0, terminal 0 → kurulum bekliyor.
  DemoSandbox · KITOKO-TR-DEMO-V1: 8 lokasyon (KITWMS raf zorunlu + yönlendirilmiş), 6 bölge, 7 raf,
  terminal KITOKO-01 → demo verisi. Hangi ortamın canlı depo işi için kullanılacağı henüz teyit edilmemiştir.

Kapsam: mal kabul (satınalma siparişine göre) ve yerleştirme; üretime malzeme çıkışı ve sevkiyat;
depolar / raflar arası transfer; barkod okutarak madde ve stok sorgulama. Sayım ve etiket ayrı
kılavuzdadır ("Sayım ve Etiket Kılavuzu"); burada yalnız bağlantı notu verilir.

Ekran metinleri Android uygulamasının kodundan alınmıştır (customer/kitoko, 1.14.201-kitoko):
AppRoot.kt (Kitoko ana menüsü), feature/ReceivingModule.kt, feature/PutAwayShipModules.kt,
feature/ProductionAssemblyModules.kt, feature/PalletPickSheet.kt, feature/MoveAndCountModules.kt,
feature/AdHocMovementWorkflow.kt, feature/LicensePlateModule.kt, feature/LpContentCard.kt,
feature/InquiryModules.kt. Görsel kullanılmaz; ekranlar metinle anlatılır.

Stil, sayfa iskeleti (page), BACK bağlantısı ve PDF basımı (render_pdf) generate-kitoko-guides.py
dosyasından aynen alınır.
"""
import importlib.util
from pathlib import Path

_BASE = Path(__file__).resolve().parent / 'generate-kitoko-guides.py'
_spec = importlib.util.spec_from_file_location('kitoko_guides', _BASE)
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)

page, BACK, render_pdf = _g.page, _g.BACK, _g.render_pdf
VERSION, DATE = _g.VERSION, _g.DATE

OUT = _g.ROOT / 'output/kilavuzlar-kitoko'
STEM = 'KITOKO-El-Terminali-Stok-Hareketleri-Kilavuzu'
TITLE = 'El Terminali Stok Hareketleri Kılavuzu'

TOC = [
    ('amac', 'Bu kılavuz ne anlatır?', False),
    ('baslangic', '1. Başlamadan önce', False),
    ('baglanti', '1.1 Bağlantı ve giriş', True),
    ('menu', '1.2 Ana menü', True),
    ('ortak', '1.3 Tüm ekranlarda ortak kurallar', True),
    ('mal-kabul', '2. Mal kabul', False),
    ('mk-siparis', '2.1 Satınalma siparişinden', True),
    ('mk-ambar', '2.2 Ambar mal kabul belgesiyle', True),
    ('mk-etiket', '2.3 Kayıt sonrası etiketler', True),
    ('mk-mesaj', '2.4 Sık mesajlar', True),
    ('yerlestirme', '3. Yerleştirme (rafa kaldırma)', False),
    ('yr-tek', '3.1 Adım adım yerleştirme', True),
    ('yr-lp', '3.2 Raf + LP okutarak toplu', True),
    ('yr-bin', '3.3 Tümünü bir rafa', True),
    ('yr-mesaj', '3.4 Sık mesajlar', True),
    ('uretim', '4. Üretime malzeme çıkışı', False),
    ('ur-cekme', '4.1 Ambar çekme açma', True),
    ('ur-toplama', '4.2 Üretim çekmesini toplama', True),
    ('ur-sarfiyat', '4.3 Doğrudan sarfiyat', True),
    ('ur-mesaj', '4.4 Sık mesajlar', True),
    ('sevkiyat', '5. Sevkiyat', False),
    ('sv-belge', '5.1 Ambar sevkiyatı ve toplama', True),
    ('sv-toplama', '5.2 Toplama', True),
    ('sv-kayit', '5.3 Sevkiyatı kaydetme', True),
    ('sv-siparis', '5.4 Siparişten doğrudan sevk', True),
    ('sv-mesaj', '5.5 Sık mesajlar', True),
    ('transfer', '6. Raflar / depolar arası transfer', False),
    ('tr-lp', '6.1 Ad-Hoc: LP ile', True),
    ('tr-urun', '6.2 Ad-Hoc: ürün ile', True),
    ('tr-yonlendirilmis', '6.3 Yönlendirilmiş hareket', True),
    ('tr-lp-lp', '6.4 LP’den LP’ye aktarma', True),
    ('tr-mesaj', '6.5 Sık mesajlar', True),
    ('sorgu', '7. Barkodla madde ve stok sorgulama', False),
    ('sq-lp', '7.1 Ana menüde LP okutma', True),
    ('sq-urun', '7.2 Ürün Sorgu', True),
    ('sq-bin', '7.3 Bin Sorgu', True),
    ('sq-hareket', '7.4 Ambar Hareketleri', True),
    ('sayim', '8. Sayım', False),
    ('sorun', '9. Genel sorun giderme', False),
]

BODY = """
<section id="amac"><h2>Bu kılavuz ne anlatır?</h2>
<p>Bu kılavuz, Kitoko Aydınlatma ve Müh. A.Ş. deposunda el terminaliyle yapılan stok hareketlerini anlatır: satınalma siparişine göre <strong>mal kabul</strong> ve malın <strong>rafa yerleştirilmesi</strong>; depodan çıkış olarak <strong>üretime malzeme çıkışı</strong> ve <strong>sevkiyat</strong>; <strong>raflar ve depolar arası transfer</strong>; barkod okutarak <strong>madde ve stok sorgulama</strong>.</p>
<p>Her bölümde sırasıyla ekranın ne zaman kullanıldığı, başlamadan önce nelerin hazır olması gerektiği, numaralı adımlar ve sık görülen mesajlar verilir. Kalın yazılan ve tırnak içindeki metinler terminal ekranında gördüğünüz düğme, alan ve mesaj metinleridir. En sonda genel bir sorun giderme tablosu vardır.</p>
<div class="warn"><strong>Kurulum durumu (27.10.2026):</strong> Kitoko için el terminali depo kurulumu <strong>henüz tamamlanmamıştır</strong>. Hangi BC ortamında çalışacağınız kesinleşmemiştir; <strong>ortam: sorumlunuzdan teyit edin</strong>. Ayrıntı 1.1’dedir.</div>
<div class="info">Etiket basma ve sayım bu kılavuzda anlatılmaz; bunlar için “Sayım ve Etiket Kılavuzu”na, yazıcı kurulumu için “Etiket Yazıcı Genel Kılavuzu”na bakın.</div>
%%BACK%%</section>

<section id="baslangic"><h2>1. Başlamadan önce</h2>
<section id="baglanti"><h3>1.1 Bağlantı ve giriş</h3>
<p>Terminal, <strong>Kitoko Aydınlatma ve Müh. A.Ş.</strong> şirketine ait bir Business Central bağlantısında kullanılır. Kitoko için iki bağlantı vardır; 27.10.2026 tarihindeki durumları şöyledir:</p>
<table><thead><tr><th>Ortam · şirket</th><th>Durum</th><th>Ne anlama gelir?</th></tr></thead><tbody>
<tr><td><strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong></td><td><strong>Kurulum bekliyor</strong></td><td>Terminal (BCWMS) tarafında ürün, lokasyon, raf ve terminal tanımı yok (0 ürün). Bu bağlantıda belge ve ürün listeleri boş gelir; stok hareketi yapılamaz.</td></tr>
<tr><td><strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong></td><td>Demo verisi</td><td>Terminal tanımı (<strong>KITOKO-01</strong>), lokasyonlar ve <strong>KITWMS</strong> deposunun bölge/raf yapısı kurulu; ürünler demo amaçlıdır. Eğitim ve deneme içindir; gerçek stok değildir.</td></tr>
</tbody></table>
<div class="warn">Hangi ortamın Kitoko’nun günlük depo işi için kullanılacağı henüz kesinleşmemiştir. <strong>Çalışmaya başlamadan önce bağlanacağınız ortamı ve şirketi sorumlunuzdan teyit edin.</strong> Teyit edilmemiş bir ortamda mal kabul, sevkiyat ya da transfer kaydı yapmayın.</div>
<p><strong>Demo ortamındaki depo yapısı (KITOKO-TR-DEMO-V1):</strong> Raf (göz) okutmalı ekranlar yalnız <strong>KITWMS · Kitoko Gelişmiş Depo (Ambar-Bölge-Raf)</strong> lokasyonunda kullanılır; bu lokasyonda raf zorunludur ve yerleştirme/toplama BC tarafından yönlendirilir. Diğer lokasyonlar (<strong>ANA</strong> Ana Depo, <strong>MERKEZDEP</strong> Merkez Depo, <strong>BVDEPO</strong> BV Merkez Depo, <strong>IHRACKAYIT</strong> İhraç Kayıtlı Stok Alanı, <strong>MUSTERI</strong> Müşteri Sahası / Emanet) raf kullanmaz; <strong>TRANSIT</strong> ve <strong>TRANSITTIC</strong> yolda/transit lokasyonlarıdır ve terminalde okutulmaz.</p>
<table><thead><tr><th>Bölge</th><th>Raf</th><th>Kullanım</th></tr></thead><tbody>
<tr><td>KABUL</td><td><strong>K-01</strong></td><td>Mal kabul rampası (malın ilk indiği göz)</td></tr>
<tr><td>DEPO-A</td><td><strong>A-01-01</strong>, <strong>A-01-02</strong></td><td>Ana depolama rafları (yerleştirme ve toplama)</td></tr>
<tr><td>DEPO-B</td><td><strong>B-01-01</strong></td><td>Yedek depolama rafı</td></tr>
<tr><td>KALITE</td><td><strong>Q-01</strong></td><td>Karantina / kalite bekleme</td></tr>
<tr><td>SEVK</td><td><strong>S-01</strong></td><td>Sevkiyat hazırlık alanı</td></tr>
<tr><td>AYAR</td><td><strong>AYAR-01</strong></td><td>Sayım farkı / ayarlama gözü</td></tr>
</tbody></table>
<div class="note">Bu tablo demo ortamının yapısıdır; Kitoko’nun gerçek depo, bölge ve raf kodları kurulum tamamlandığında kesinleşecektir. Kılavuzdaki örneklerde geçen raf ve belge numaraları temsilidir.</div>
<ol class="steps">
<li>Terminalin Wi-Fi’ye bağlı olduğunu kontrol edin ve <strong>BCWMS Kitoko</strong> uygulamasını açın.</li>
<li>Kendi terminal kullanıcınızla ve PIN’inizle giriş yapın.</li>
<li>Ana menünün üstündeki renkli başlıkta şirket adını ve altındaki <strong>“Ortam: …”</strong> satırını okuyun. Şirket ve ortam, sorumlunuzun teyit ettiği bağlantı olmalıdır (ör. <strong>Kitoko Aydınlatma ve Müh. A.Ş.</strong> · Sand2010 ya da eğitim için <strong>KITOKO-TR-DEMO-V1</strong> · DemoSandbox).</li>
<li>Farklıysa başlıktaki <strong>Ortam / şirket değiştir</strong> düğmesine dokunun ve doğru ortamı ve şirketi seçin.</li>
<li>Başlığın altındaki şeritte <strong>“Aktif kullanıcı · …”</strong> satırında kendi adınızı, yanında <strong>“Yazıcı: …”</strong> bilgisini görürsünüz. Yazıcı “Seçilmemiş” görünüyorsa ve etiket basacaksanız önce <strong>Yazıcılar</strong> ekranından etiket yazıcınızı seçin.</li>
</ol>
<div class="note">İşiniz bitince ya da terminali başka birine bırakırken ana menünün sağ üstündeki <strong>Kullanıcı çıkışı</strong> ile çıkın. Terminalde yapılan her işlem giriş yapan kullanıcı adına kaydedilir.</div></section>

<section id="menu"><h3>1.2 Ana menü</h3>
<p>Kitoko terminalinde ana menü kategorilere ayrılmıştır. Bu kılavuzda kullanılan kutucuklar şunlardır:</p>
<table><thead><tr><th>Kategori</th><th>Kutucuk</th><th>Bu kılavuzda</th></tr></thead><tbody>
<tr><td>Gelen</td><td><strong>Mal Kabul</strong>, <strong>Yerleştirme</strong></td><td>2. ve 3. bölüm</td></tr>
<tr><td>Giden</td><td><strong>Sevkiyat</strong>, <strong>Toplama</strong></td><td>5. bölüm (üretim çekmeleri de Sevkiyat ekranında toplanır, 4. bölüm)</td></tr>
<tr><td>İç Operasyon</td><td><strong>LP</strong>, <strong>Ad-Hoc Hareket</strong>, <strong>Yönlendirilmiş</strong></td><td>6. bölüm</td></tr>
<tr><td>Üretim</td><td><strong>Üretim</strong></td><td>4. bölüm</td></tr>
<tr><td>Sorgu</td><td><strong>Ürün Sorgu</strong>, <strong>Bin Sorgu</strong>, <strong>Ambar Hareketleri</strong></td><td>7. bölüm</td></tr>
<tr><td>İç Operasyon</td><td><strong>Sayım</strong>, <strong>İlk Sayım</strong></td><td>“Sayım ve Etiket Kılavuzu”</td></tr>
</tbody></table>
<p>Ana menüde ayrıca Paketleme, Fason İşlemler, Montaj, Kalite Denetimi, MS Kalite, Etiket Çıkar, Yazıcılar ve Bağlantı kutucukları bulunur; bunlar bu kılavuzun konusu değildir.</p>
<div class="note">Kutucukların sırası, adı ya da görünürlüğü Business Central’daki terminal ekran düzeniyle değiştirilebilir. Bir kutucuğu göremiyorsanız sorumlunuza bildirin. Ana menünün en altındaki <strong>Terminali Nasıl Kullanırım?</strong> düğmesi terminal içi yardımı açar.</div></section>

<section id="ortak"><h3>1.3 Tüm ekranlarda ortak kurallar</h3>
<table><thead><tr><th>Konu</th><th>Nasıl çalışır?</th></tr></thead><tbody>
<tr><td><strong>Barkod okutma</strong></td><td>Okutma alanlarına terminalin tarayıcısıyla okutun. Barkod okunmuyorsa alandaki <kbd>⌨</kbd> ile klavyeyi açıp değeri yazın ve <kbd>OK</kbd>’a dokunun; kamera simgesiyle telefon kamerasından da okutabilirsiniz.</td></tr>
<tr><td><strong>Belge listesinde okutma</strong></td><td>Mal kabul, yerleştirme, toplama ve sevkiyat listelerinde bir ürünün barkodunu okutursanız terminal o ürünü içeren açık belgeyi bulur. Tek belge varsa doğrudan açılır; birden fazlaysa liste o belgelere daralır.</td></tr>
<tr><td><strong>Belge içinde okutma</strong></td><td>Açık bir belgede ürün barkodu okuttuğunuzda eşleşen satır açılır. Birden fazla satır eşleşirse “… için birden fazla satır — birini seçin” yazar; listeden doğru satıra dokunun.</td></tr>
<tr><td><strong>Bana atanan / Tümü</strong></td><td>Listeler açılışta size atanmış belgeleri gösterir. Diğer açık belgeleri görmek için <strong>Tümü</strong>’ne dokunun.</td></tr>
<tr><td><strong>Bana Ata</strong></td><td>Bir belgede işlem yapabilmek için belge sizin üzerinizde olmalıdır. Belge atanmamışsa ya da başkasındaysa ekranda <strong>Bana Ata</strong> (veya <strong>👤 Bana Ata</strong>, <strong>✋ Üzerime Al</strong>) düğmesi görünür. Başka kullanıcıdaki toplamayı devralırken terminal “Belgeyi devralmak istediğinize emin misiniz?” diye sorar; <strong>Evet, Bana Ata</strong> derseniz önceki kullanıcı bu belgede çalışamaz.</td></tr>
<tr><td><strong>Satır renkleri</strong></td><td>Miktarın tamamı girilen satır yeşil, bir kısmı girilen satır sarı görünür. Dokunulmamış satır renksiz kalır.</td></tr>
<tr><td><strong>Durum satırı</strong></td><td>Her işlemden sonra ekranda bir durum satırı çıkar. <strong>TAMAM:</strong> işlemin yapıldığını, <strong>HATA:</strong> yapılmadığını ve nedenini, <strong>UYARI:</strong> kısmen yapıldığını, <strong>BOŞ:</strong> gösterilecek kayıt olmadığını söyler. Mesajı okuyun; nedenini çözmeden aynı işlemi tekrarlamayın.</td></tr>
<tr><td><strong>Yenile</strong></td><td>Listelerde ve belgelerde yenile düğmesi BC’deki güncel durumu yeniden okur. Bağlantı koptuğunda ya da “Cevap alınamadı / doğrulanamadı” türü bir mesajda önce yenileyin, sonra gerekiyorsa işlemi tekrarlayın.</td></tr>
<tr><td><strong>Geri dönmek</strong></td><td>Belgeden listeye <strong>‹ Belge Listesi</strong> (ekranına göre <strong>‹ PO Listesi</strong>, <strong>‹ SO Listesi</strong>, <strong>‹ Hareket Listesi</strong>) ile, ana menüye üstteki <strong>‹ Menü</strong> ile dönersiniz. Terminalin geri tuşu da bir üst ekrana döner.</td></tr>
<tr><td><strong>Kolonlar / Birleştir</strong></td><td>Satır tablolarında <strong>Kolonlar</strong> ile hangi bilgilerin görüneceğini seçebilirsiniz. <strong>🔗 Birleştir</strong>, aynı ürün ve rafa ait satırları tek grupta gösterir; girdiğiniz miktar gruptaki satırlara dağıtılır.</td></tr>
</tbody></table>
<div class="warn">Kayıt düğmeleri (Naklet, Kaydet, Yerleştirmeyi Kaydet, Toplamayı Kaydet, Sevkiyatı Kaydet, Hareketi Onayla) işlemi Business Central’a <strong>kesin olarak</strong> kaydeder ve terminalden geri alınamaz. Basmadan önce satırları ve miktarları kontrol edin.</div></section>
%%BACK%%</section>

<section id="mal-kabul"><h2>2. Mal kabul</h2>
<p><strong>Ne zaman kullanılır?</strong> Tedarikçiden gelen malı satınalma siparişine göre depoya almak için. Ana menüde <strong>Mal Kabul</strong> kutucuğu iki sekmeyle açılır:</p>
<table><thead><tr><th>Sekme</th><th>Ne zaman?</th></tr></thead><tbody>
<tr><td><strong>Satın Alma Siparişi</strong></td><td>Lokasyon ambar mal kabul belgesi istemiyorsa ve siparişte lot/seri takipli ürün yoksa; mal doğrudan sipariş satırlarından alınır (2.1).</td></tr>
<tr><td><strong>Ambar Mal Kabul</strong></td><td>Lokasyon ambar mal kabul belgesi istiyorsa, siparişte lot/seri takipli ürün varsa ya da mal paletlere (LP) alınacaksa (2.2).</td></tr>
</tbody></table>
<p><strong>Başlamadan önce:</strong> Satınalma siparişi BC’de serbest bırakılmış (Released) olmalıdır. Malın irsaliyesini ve sipariş numarasını yanınızda bulundurun. Kayıttan sonra LP etiketi basılacaksa terminalde etiket yazıcısının seçili olduğunu kontrol edin.</p>

<section id="mk-siparis"><h3>2.1 Satınalma siparişinden mal kabul</h3>
<ol class="steps">
<li>Ana menüden <strong>Mal Kabul</strong>’ü açın ve <strong>Satın Alma Siparişi</strong> sekmesine geçin. Serbest bırakılmış siparişler listelenir (<strong>Sadece Serbest</strong>). Bütün durumları görmek için bu düğmeye dokunup <strong>Tüm Durumlar</strong>’a geçebilirsiniz.</li>
<li>Siparişi bulun: <strong>PO no ile ara (örn: 106040)</strong> alanına sipariş numarasını, tedarikçi adını veya ürün numarasını yazıp aramaya dokunun ya da listede bir ürün barkodu okutun. Kartta tedarikçi, lokasyon, satır sayısı ve kalan miktar görünür. Kartta <strong>“⚠ Ambar Girişi”</strong> yazıyorsa bu sipariş 2.2’deki Ambar Mal Kabul akışıyla alınır.</li>
<li>Siparişe dokunun. Başlıkta tedarikçi, lokasyon ve durum, altında <strong>“0/N satır hazır · Kaydedilecek miktar: 0”</strong> özeti görünür.</li>
<li>Gelen ürünün barkodunu okutun ya da <strong>Ürün Tara</strong>’ya dokunun. Satırı listeden seçmek için satıra dokunabilirsiniz.</li>
<li>Açılan <strong>Alınacak Miktar</strong> penceresinde <strong>Miktar</strong> alanına fiziksel olarak gelen miktarı girin (<kbd>−</kbd> / <kbd>+</kbd> / <kbd>+1</kbd> ile de değiştirebilirsiniz) ve <strong>Onayla</strong>’ya dokunun. “TAMAM: Satır miktarı güncellendi.” mesajını görürsünüz; satır yeşil ya da sarı olur.</li>
<li>Gelen her ürün için 4. ve 5. adımları tekrarlayın. Bu aşamada kayıt yapılmaz; yalnız miktarlar hazırlanır.</li>
<li>Faturanın da aynı anda işlenmesi isteniyorsa (bunu sorumlunuz söyler) <strong>Aynı zamanda faturalandır</strong> kutusunu işaretleyin.</li>
<li>Alttaki <strong>Kaydet (post) — N satır</strong> düğmesine dokunun. <strong>PO mal kabulünü kaydet</strong> penceresinde “İşlediğiniz satır”, “Kaydedilecek satır” ve “Toplam miktar” bilgilerini kontrol edin ve <strong>Kaydet</strong>’e dokunun.</li>
<li>“TAMAM: Satınalma mal kabulü kaydedildi.” mesajını bekleyin.</li>
</ol>
<div class="note">Kayıttan önce terminal, sizin bu oturumda dokunmadığınız satırların alınacak miktarını sıfırlar; böylece yalnız sizin girdiğiniz miktarlar kaydedilir.</div>
<p>Sipariş doğrudan alınamıyorsa ekranda sarı bir kutu çıkar ve kayıt düğmesi <strong>Doğrudan mal kabul kapalı</strong> yazar:</p>
<ul>
<li>“Bu siparişte lot/seri izlemeli ürün var. Lot ve seri kaydını korumak için Ambar Mal Kabul ekranındaki belgeyi kullanın.”</li>
<li>“Bu lokasyon (…) için Ambar Mal Kabul belgesi zorunlu. İlgili belgeyi Ambar Mal Kabul ekranından tamamlayın.”</li>
</ul>
<p>Bu durumda kutudaki <strong>📥 Ambar Kabulü Oluştur</strong> düğmesine dokunun. “TAMAM: … ambar mal kabul belgesi hazır — 'Ambar Mal Kabul' sekmesinden açıp okutmaya başlayın.” mesajından sonra 2.2’deki adımlarla devam edin.</p></section>

<section id="mk-ambar"><h3>2.2 Ambar mal kabul belgesiyle</h3>
<ol class="steps">
<li><strong>Mal Kabul → Ambar Mal Kabul</strong> sekmesini açın. Size atanan belgeler listelenir; diğerleri için <strong>Tümü</strong>’ne dokunun. Belgeyi <strong>Mal kabul no ile ara</strong> alanıyla ya da bir ürün barkodu okutarak bulun ve açın.</li>
<li>Belge size atanmamışsa alttaki <strong>Bana Ata</strong>’ya dokunun. “TAMAM: Bana atandı” mesajından sonra düğmeler açılır.</li>
<li><strong>Mal paletle (LP ile) alınacaksa</strong> ilk paleti okutmadan önce <strong>LP Başlat</strong>’a dokunun. Terminal uygun palet şablonuyla yeni bir LP açar; “TAMAM: … başlatıldı” mesajı çıkar ve başlıkta <strong>“Aktif LP: …”</strong> görünür. Bundan sonra girdiğiniz miktarlar bu LP’ye yazılır.</li>
<li>Paletteki ürünün barkodunu okutun ya da <strong>Tara</strong>’ya dokunun. <strong>Alınan Miktar</strong> penceresinde:
<ul>
<li><strong>Miktar</strong>: fiziksel olarak aldığınız miktar.</li>
<li><strong>Lot No (zorunlu)</strong>: lot takipli üründe lotu girin. İç lot numarası verilecekse <strong>Lot No Ata</strong>’ya dokunun; BC numarayı üretir ve düğme “Lot No Atandı” olur. Tedarikçi lotu alanı açıksa tedarikçinin lot numarasını yazın.</li>
<li><strong>Seri No (zorunlu)</strong>: seri takipli üründe her seri numarası 1 birimdir.</li>
<li>SKT alanı açıksa son kullanma tarihini <strong>GG.AA.YYYY</strong> biçiminde girin.</li>
</ul>
<strong>Onayla</strong>’ya dokunun; “TAMAM: Satır güncellendi” mesajı çıkar.</li>
<li>Palet dolunca <strong>LP Kapat</strong>’a dokunun. “TAMAM: … kapatıldı. Sonraki palet için LP Başlat'a, bitince Naklet'e basın.” yazar. Sonraki palet için 3.–5. adımları tekrarlayın.</li>
<li>LP başlatmadan önce miktar girdiyseniz, LP Başlat’tan sonra terminal <strong>“Satırlar …’ye eklensin mi?”</strong> diye sorar. Bu miktarlar o palete aitse <strong>LP’ye Ekle</strong>, değilse <strong>Şimdi Değil</strong> deyin.</li>
<li>Bütün paletler bitince alttaki <strong>Naklet · N</strong> düğmesine dokunun (aktif LP açıksa düğme <strong>LP + Naklet</strong> yazar). Açılan <strong>Deftere naklet</strong> penceresinde satır sayılarını ve toplam miktarı kontrol edin. Pencerede “Kayıt, belgeyi Business Central'da postalar ve geri alınamaz.” uyarısı ve etiket seçenekleri (“Kayıttan sonra her LP'ye 1 LP etiketi basılır”, <strong>Lot etiketi de bas</strong>) görünür.</li>
<li><strong>Deftere Naklet</strong>’e (aktif LP varsa <strong>LP’yi Kapat ve Naklet</strong>) dokunun. Terminal önce “Mal kabul hazırlanıyor...”, sonra kayıt ve etiket mesajlarını gösterir.</li>
</ol>
<p><strong>Alttaki seçenekler:</strong> <strong>Yazdırmadan kaydet</strong> işaretliyse kayıtta etiket basılmaz. <strong>Belgeyi yazdır</strong> işaretliyse mal kabul belgesi de yazdırılır.</p>
<div class="info"><strong>Palet LP:</strong> Tek bir ürünü çok sayıda palete bölerek almak için LP başlatmadan önce <strong>Palet LP</strong>’ye dokunun ve satırı seçin. <strong>Palet LP'lerini Oluştur</strong> ekranında <strong>Kabul miktarı</strong> ve <strong>Palet sayısı</strong>nı girip <strong>Eşit Böl ve N LP Hazırla</strong>’ya dokunun ya da paletleri <strong>+ LP Ekle</strong> ile tek tek girip <strong>N LP Taslağı Hazırla</strong>’ya dokunun. Hazırlanan LP’lere ürün ve miktar, belge naklettiğinde yazılır. BC destekliyorsa aynı listede birden çok ürünü aynı paletlere almak için “Karma palet · birden çok ürün aynı palette” seçeneği de görünür. Bu yöntemi kullanıp kullanmayacağınızı sorumlunuz belirler.</div>
<div class="note">BC araç bilgisi istiyorsa belgede araç kartı görünür ve kayıt düğmesi <strong>Araç → Naklet</strong> yazar. Önce plaka ve sürücüyü girip kaydedin, sonra nakledin.</div></section>

<section id="mk-etiket"><h3>2.3 Kayıt sonrası etiketler</h3>
<p>Kitoko terminalinde LP etiketleri kayıttan sonra terminal tarafından gönderilir. Kayıt bitince <strong>Etiketler</strong> penceresi açılır; pencerede belge numarası, kayıt sırasında gönderilen etiketlerin özeti ve bu mal kabule bağlı LP’lerin listesi görünür.</p>
<ol class="steps">
<li>Özet satırını okuyun. Örneğin: “TAMAM: Mal kabul kaydedildi. 3 LP etiketi … kuyruğuna alındı.”</li>
<li>Yazıcıdan çıkan etiketleri paletlerle karşılaştırın.</li>
<li>Eksik bir etiket varsa yalnız o LP’yi işaretleyin ve <strong>LP etiketi</strong>’ne dokunun. Lot takipli ürünlerde lot etiketi için <strong>Lot etiketi</strong>, ikisi için <strong>İkisini de bas (LP + lot)</strong> kullanılır. <strong>LP etiketi adedi</strong> ve <strong>Lot başına lot etiketi</strong> alanlarıyla adet seçilir.</li>
<li>İşiniz bitince <strong>Devam Et</strong>’e dokunun.</li>
</ol>
<div class="warn">Liste, aynı belgenin önceki kısmi kabullerine ait LP’leri de içerebilir. Bütün listeyi yeniden basmayın; yalnız eksik olanları seçin. Etiket gönderimi hata verirse terminal otomatik tekrar denemez; önce yazıcıdan çıkanı kontrol edin.</div></section>

<section id="mk-mesaj"><h3>2.4 Sık mesajlar</h3>
<table><thead><tr><th>Mesaj</th><th>Ne yapmalı?</th></tr></thead><tbody>
<tr><td>“BOŞ: Size atanmış mal kabul yok”</td><td><strong>Tümü</strong>’ne dokunun. Belge yine yoksa siparişten 2.1’deki <strong>📥 Ambar Kabulü Oluştur</strong> ile oluşturun ya da sorumluya bildirin.</td></tr>
<tr><td>“⚠️ '…' bu belgede yok” / “… bu PO'da yok”</td><td>Okuttuğunuz ürün bu belgede değil. Doğru belgede olduğunuzu ve etiketi kontrol edin.</td></tr>
<tr><td>“Belge henüz bir kullanıcıya atanmadı. Önce belgeyi üzerinize alın.”</td><td><strong>Bana Ata</strong>’ya dokunun.</td></tr>
<tr><td>“Bu belge … kullanıcısına atanmış. İşlem yapılamaz.”</td><td>Belge başka bir çalışanın üzerinde. O kişiyle ya da sorumlunuzla görüşün.</td></tr>
<tr><td>“Lot takipli ürün için lot numarası girilmelidir.”</td><td>Lot No alanını doldurun ya da <strong>Lot No Ata</strong>’ya dokunun.</td></tr>
<tr><td>“Miktar kalan … değerini aşamaz.”</td><td>Siparişte kalan miktardan fazlasını giremezsiniz. Fazla gelen mal için sorumlunuza bildirin.</td></tr>
<tr><td>“HATA: Uygun palet şablonu belirlenemedi. BC'de PALLET-EUR şablonunu kontrol edin.”</td><td>LP açılamadı. Sorumluya bildirin; BC’de palet şablonu kontrol edilmelidir.</td></tr>
<tr><td>“HATA: Mal kabul kaydedilmedi. Neden: …”</td><td>Kayıt yapılmadı. Nedeni okuyun, düzeltin, belgeyi yenileyip tekrar deneyin.</td></tr>
<tr><td>“UYARI: … satır sıfırlandı, kalan satırlar işlenemedi. … mal kabul kaydedilmedi.”</td><td>Kayıt yapılmadı. Belgeyi yenileyin ve takılan satırı kontrol edin.</td></tr>
<tr><td>“TAMAM: Mal kabul tamamlandı; belge BC'de kapandı.”</td><td>Bütün satırlar alındı; belge listeden kalkar. Yerleştirme adımına geçin.</td></tr>
<tr><td>“UYARI: Mal kabul kaydedildi, LP etiketi basılmadı: …”</td><td>Mal kabul kaydedildi, etiket çıkmadı. Mal kabulü tekrar kaydetmeyin; etiketleri Etiketler penceresinden basın.</td></tr>
</tbody></table></section>
%%BACK%%</section>

<section id="yerlestirme"><h2>3. Yerleştirme (rafa kaldırma)</h2>
<p><strong>Ne zaman kullanılır?</strong> Mal kabulden sonra malı kabul alanından rafına kaldırmak için. Yerleştirme belgeleri BC’de mal kabulden sonra oluşur; terminalde <strong>Yerleştirme</strong> kutucuğundan açılır.</p>
<p><strong>Başlamadan önce:</strong> Mal kabul kaydedilmiş, yerleştirme belgesi oluşmuş olmalıdır. Kaldıracağınız palet ya da ürün yanınızda olsun; hedef rafların etiketleri okunabilir olmalıdır.</p>

<section id="yr-tek"><h3>3.1 Adım adım yerleştirme</h3>
<ol class="steps">
<li>Ana menüden <strong>Yerleştirme</strong>’yi açın. <strong>Bana atanan</strong> belgeler listelenir; diğerleri için <strong>Tümü</strong>. Belgeyi arayın ya da paletteki ürün/LP barkodunu listede okutun.</li>
<li>Belgeyi açın. Başlıkta lokasyon, atanan kullanıcı ve “% … tamamlandı” görünür. Belge kimseye atanmamışsa alttaki <strong>👤 Bana Ata</strong>’ya dokunun.</li>
<li><strong>Yerleştirmeler</strong> listesinde her kart bir taşımayı gösterir: ürün, kaynak raf → hedef raf ve varsa LP. Kartın sağında <strong>Dokunun</strong> yazar. İlgili karta dokunun ya da ürün/LP barkodunu okutun.</li>
<li>Açılan <strong>Yerleştirme · Adım n/m</strong> penceresi sizi sırayla yönlendirir. Belgeye ve kuruluma göre şu adımlar sorulur:
<ul>
<li><strong>“Palet/LP etiketini okutun veya LP numarasını yazın”</strong>: taşıdığınız paletin etiketini okutun.</li>
<li><strong>“Bulunduğunuz rafı okutun”</strong>: malı aldığınız rafı okutun (“Beklenen: …” yazan raf).</li>
<li><strong>“Ürünü okutun”</strong>: palet okutma istenmiyorsa ürün barkodunu okutun.</li>
<li><strong>“Koyacağınız rafı okutun”</strong>: malı bıraktığınız rafın etiketini okutun. Rafı listeden seçmek için <strong>📍 Bin Listesinden Seç</strong>, öneri almak için <strong>🎯 Bin Öner</strong> kullanılır. Elle yazdıysanız <strong>Doğrula</strong>’ya dokunun.</li>
<li><strong>“Miktarı onaylayın”</strong>: <strong>Miktar</strong> alanını kontrol edin.</li>
</ul></li>
<li><strong>✅ Yerleştirmeyi Onayla</strong>’ya dokunun. “TAMAM: Satır hazırlandı. Diğer satırları tamamlayın veya Yerleştirmeyi Kaydet'e basın.” mesajı çıkar; kart <strong>✓ Hazır</strong> olur.</li>
<li>Diğer kartlar için 3.–5. adımları tekrarlayın.</li>
<li>Alttaki <strong>✅ Yerleştirmeyi Kaydet</strong>’e dokunun. Tamamı kaydedildiyse “TAMAM: Tüm satırlar yerleştirildi — belge tamamlandı ✅”, bir kısmı kaydedildiyse “TAMAM: Kısmi kayıt yapıldı — kalan … adet listede” yazar.</li>
</ol>
<div class="note">Hedef raf BC’nin önerdiği raf olmak zorunda değildir; aynı lokasyondaki geçerli herhangi bir rafa yerleştirebilirsiniz. Kaynak raf, palet ve ürün ise belgedekiyle aynı olmalıdır; farklı okutursanız adım ilerlemez.</div></section>

<section id="yr-lp"><h3>3.2 Raf + LP okutarak toplu yerleştirme</h3>
<p>Belgede LP’li satırlar varsa ekranda “Hedef rafı okutun, ardından o rafa bırakacağınız LP'leri peş peşe okutun.” yazar ve alttaki düğme <strong>📍 Raf + LP Okut</strong> olur. Bu yöntemle aynı rafa giden birçok paleti tek seferde kaydedersiniz.</p>
<ol class="steps">
<li><strong>📍 Raf + LP Okut</strong>’a dokunun. <strong>Raf Bazlı Toplu LP Yerleştirme</strong> penceresi açılır.</li>
<li><strong>Hedef raf okut veya yaz</strong> alanına rafın etiketini okutun. “TAMAM: Hedef raf … — LP'leri peş peşe okutun.” yazar ve raf <strong>AKTİF HEDEF RAF</strong> olarak görünür.</li>
<li>O rafa bıraktığınız paletlerin LP etiketlerini sırayla okutun. Her okutmada “TAMAM: … → … (n/m LP)” yazar.</li>
<li>Başka bir rafa geçecekseniz yeni rafın etiketini okutun; sonraki LP’ler o rafa atanır.</li>
<li><strong>✅ Okutulan N LP'yi Yerleştir</strong>’e dokunun. Terminal LP’leri hazırlar ve yerleştirmeyi kaydeder.</li>
</ol>
<div class="warn">Kalite onayı bekleyen ya da reddedilmiş LP’ler bu yöntemle rafa kaldırılamaz: “… kalite onayı bekliyor; karantina gözünde kalmalı.” veya “… reddedildi; … taşınmalı.” mesajı çıkar. Bu paletleri ayırın ve sorumlunuza bildirin.</div></section>

<section id="yr-bin"><h3>3.3 Tümünü bir rafa</h3>
<p>Belgede LP yoksa ve palet okutma zorunlu değilse alttaki düğme <strong>📦 Tümünü Bir Bine</strong> olur. <strong>Tümünü Bir Bine Yerleştir</strong> penceresinde rafı okutun ya da <strong>📍 Bin Listesinden Seç</strong> ile seçin ve <strong>Tümüne Uygula (N)</strong>’ya dokunun. Ardından <strong>✅ Yerleştirmeyi Kaydet</strong> ile kaydedin. Palet okutma zorunluysa düğme <strong>📦 Satırdan palet okutun</strong> yazar ve pasif kalır; bu durumda 3.1’deki gibi satır satır ilerleyin.</p></section>

<section id="yr-mesaj"><h3>3.4 Sık mesajlar</h3>
<table><thead><tr><th>Mesaj</th><th>Ne yapmalı?</th></tr></thead><tbody>
<tr><td>“BOŞ: Üzerinize atanmış yerleştirme yok — 'Tümü' ile bakabilirsiniz”</td><td><strong>Tümü</strong>’ne dokunun.</td></tr>
<tr><td>“❌ Yanlış raf. Beklenen: … · Okuttuğunuz: …”</td><td>Malı belgede yazan raftan aldığınızı kontrol edin ve doğru rafı okutun.</td></tr>
<tr><td>“❌ Yanlış LP. Beklenen: … · Okuttuğunuz: …”</td><td>Okuttuğunuz palet bu satıra ait değil. Doğru paleti bulun.</td></tr>
<tr><td>“❌ Yanlış ürün. Beklenen: …”</td><td>Doğru ürünü aldığınızı kontrol edin.</td></tr>
<tr><td>“❌ … rafı … lokasyonunda bulunamadı.”</td><td>Okuttuğunuz raf bu depoda tanımlı değil. Raf etiketini kontrol edin ya da listeden seçin.</td></tr>
<tr><td>“HATA: LP'den önce hedef rafı okutun.”</td><td>Toplu yerleştirmede önce rafı, sonra LP’leri okutun.</td></tr>
<tr><td>“🔬 Kalite kontrolü bekliyor — lot/seri kullanılamıyor.”</td><td>Lot kalite kontrolünde. Ekrandaki <strong>🧫 MS Quality Mgmt'i Aç</strong> düğmesiyle durumu görebilirsiniz; karar için kalite sorumlusuna bildirin.</td></tr>
<tr><td>“UYARI: …/… satır yazıldı; kalanı başarısız. Sebep: …”</td><td>Belge yenilendi. Sebebi okuyun ve kalan satırı yeniden deneyin.</td></tr>
</tbody></table></section>
%%BACK%%</section>

<section id="uretim"><h2>4. Üretime malzeme çıkışı</h2>
<p><strong>Ne zaman kullanılır?</strong> Serbest bırakılmış bir üretim emrinin bileşenlerini (malzemelerini) depodan üretim alanına göndermek için. Terminalde iki yol vardır: üretim emrine bağlı <strong>ambar çekme</strong> açıp malzemeyi raftan toplayarak üretim gözüne taşımak (4.1–4.2) ya da bileşeni doğrudan <strong>sarfiyat</strong> olarak kaydetmek (4.3). Hangi yolun kullanılacağını sorumlunuz belirler.</p>
<p><strong>Başlamadan önce:</strong> Üretim emri BC’de serbest bırakılmış olmalıdır. Malzemenin hangi raflarda ve LP’lerde olduğunu bilmiyorsanız önce <strong>Ürün Sorgu</strong> ile bakın (7.2).</p>

<section id="ur-cekme"><h3>4.1 Üretim emrinden ambar çekme açma</h3>
<ol class="steps">
<li>Ana menüden <strong>Üretim</strong>’i açın. <strong>Sarfiyat</strong> sekmesinde açık üretim emirleri listelenir. Kartta üretilen ürün, “Üretim miktarı”, “Bileşen kalan”, lokasyon ve termin görünür. Emri <strong>PÜ no ile ara</strong> alanıyla bulabilirsiniz.</li>
<li>Üretim emrine dokunun. Başlıkta emir ve ürün, altında <strong>Bileşenler</strong> listesi görünür.</li>
<li><strong>Ambar Çekme Aç</strong>’a dokunun. “Üretim emrine bağlı ambar çekme hazırlanıyor...” yazar. Çekme açılınca terminal sizi doğrudan <strong>Sevkiyat → Toplama</strong> sekmesinde bu belgeye götürür (“TAMAM: … ambar çekmesi hazır”).</li>
<li>Üretim için daha önce hazırlanmış tek bir palet varsa bunun yerine <strong>Hazır LP ile Ambar Çekme</strong>’ye dokunun. <strong>Hazırlanan LP</strong> alanına paletin etiketini okutun, <strong>LP İçeriğini Göster</strong> ile içeriği ve “Üretim hedefi”ni kontrol edin, <strong>Bu LP ile Ambar Çekmesini Aç</strong>’a dokunun. Bu yöntemde yalnız o LP’nin miktarları hazırlanır ve toplamayı kaydettiğinizde LP bütün olarak üretim gözüne taşınır.</li>
</ol></section>

<section id="ur-toplama"><h3>4.2 Üretim çekmesini toplama</h3>
<p>Üretim çekmesi Sevkiyat ekranının <strong>Toplama</strong> sekmesinde açılır. Başlıkta <strong>“Üretim emri: …”</strong> ve <strong>“Hedef: …”</strong> (üretim gözü) yazar. Satırlar raf ve palet okutularak toplanır; her satır kartında “Paletleri okutmak için dokunun” yazar.</p>
<p><strong>A) Hazır paleti bütün olarak göndermek:</strong></p>
<ol class="steps">
<li>Satır kartına dokunun. <strong>Palet Okutarak Toplama</strong> penceresi açılır; kaynak raf, lot ve <strong>Toplanacak miktar</strong> görünür.</li>
<li><strong>“1. Kaynak rafın kodunu okut”</strong>: paletin bulunduğu rafı okutun. “RAF DOĞRULANDI” yazar.</li>
<li><strong>“2. Paletin QR kodunu okut”</strong>: <strong>SIRADAKİ PALET</strong> kutusunda yazan paleti okutun. Kutuda “Bu paletten al: …” miktarı görünür. Birden fazla palet varsa sırayla okutun.</li>
<li><strong>Okutulan Paletleri Onayla</strong>’ya dokunun.</li>
<li>Bütün satırlar bitince alttaki <strong>✅ Toplamayı Kaydet</strong>’e dokunun.</li>
</ol>
<p><strong>B) Farklı paletlerden kısmi toplayıp yeni bir üretim paleti hazırlamak:</strong></p>
<ol class="steps">
<li>Satırları okutmadan önce alttaki <strong>Yeni Üretim LP</strong>’ye dokunun. “TAMAM: Üretim LP … açıldı. Kaynak rafları ve paletleri doğrulayın.” yazar; düğme <strong>Üretim LP: …</strong> olur.</li>
<li>Her satırda A’daki 1.–4. adımlarla kaynak rafı ve paletleri okutun. Gereken miktarlar yeni üretim LP’sinde birleştirilir.</li>
<li>Alttaki <strong>LP Hazırla</strong>’ya dokunun. <strong>Üretim LP Hazırla</strong> penceresinde “Paleti bıraktığınız hazırlık gözünü okutun. Bu adım üretime teslim sayılmaz.” yazar. <strong>Depo gözü</strong> alanına paleti bıraktığınız hazırlık gözünü okutun ve <strong>Onayla</strong>’ya dokunun. “TAMAM: LP hazırlık gözünde. Üretime teslimde bu LP'yi yeniden okutun.”</li>
<li>Gerekirse <strong>LP Etiketi Yazdır</strong> ile hazırlanan paletin etiketini basın.</li>
<li>Palet üretime götürülünce satırlarda hazırlık rafını ve LP etiketini yeniden doğrulayın, ardından <strong>Üretime Teslim Et</strong>’e dokunun. Pencerede “Teslim gözü: …” yazar; <strong>Depo gözü</strong> alanına üretim gözünü okutup <strong>Onayla</strong>’ya dokunun. “TAMAM: Üretime teslim kaydedildi.” mesajından sonra belge kapanır.</li>
</ol>
<div class="note">Yanlış açılmış bir çekmeyi belgenin sağ üstündeki <strong>Pick'i İptal Et</strong> ile iptal edebilirsiniz. Yalnız kaydedilmemiş toplama iptal edilir; üretim emri ve LP içeriği korunur, çekmeyi yeniden açabilirsiniz. Rafta bulunamayan malzeme için <strong>📉 Eksik Bildir</strong> kullanılır (4.4).</div></section>

<section id="ur-sarfiyat"><h3>4.3 Doğrudan sarfiyat</h3>
<p>Sarfiyat, bileşenin üretim emrine tüketim olarak kaydedilmesidir; kayıtla stok düşer.</p>
<ol class="steps">
<li><strong>Üretim → Sarfiyat</strong> sekmesinde üretim emrine dokunun.</li>
<li>Bileşenin barkodunu okutun ya da <strong>Bileşenler</strong> listesinde satıra dokunun. Barkod yalnız seçili emrin bileşenlerinde aranır.</li>
<li><strong>Sarfiyat — …</strong> penceresinde <strong>Bileşen / LP</strong> alanına bileşeni ya da LP’yi okutun, <strong>Miktar</strong>, <strong>Bin</strong> (bileşenin alındığı göz) ve gerekiyorsa <strong>Lot No (opsiyonel)</strong> / <strong>Seri No (opsiyonel)</strong> alanlarını doldurun.</li>
<li><strong>Sarfiyatı Onayla</strong>’ya dokunun. “TAMAM: Sarfiyat kaydedildi” mesajını bekleyin.</li>
</ol>
<div class="info"><strong>✅ Üretim Emrini Bitir</strong> düğmesi emri “Bitti” durumuna alır ve geri alınamaz. Açık toplama varsa BC işlemi reddeder. Bu düğmeyi yalnız sorumlunuz söylediğinde kullanın.</div></section>

<section id="ur-mesaj"><h3>4.4 Sık mesajlar</h3>
<table><thead><tr><th>Mesaj</th><th>Ne yapmalı?</th></tr></thead><tbody>
<tr><td>“BOŞ: Serbest üretim bileşeni yok.”</td><td>Serbest bırakılmış üretim emri yok. Planlamaya bildirin.</td></tr>
<tr><td>“Bu LP'nin ürünleri seçilen emirde bulunamadı.”</td><td>Okuttuğunuz palet bu üretim emrinin malzemesini içermiyor. Doğru paleti ve emri kontrol edin.</td></tr>
<tr><td>“LP içinde taşınacak ürün yok.”</td><td>Palet boş. Doğru paleti okutun.</td></tr>
<tr><td>“Hazırlamadan önce kaynak rafı ve paleti doğrulayın.”</td><td>LP Hazırla’dan önce açılan satırda rafı ve paleti okutun.</td></tr>
<tr><td>“Teslimden önce hazırlık rafını ve … etiketini doğrulayın.”</td><td>Üretime Teslim Et’ten önce açılan satırda hazırlık rafını ve LP’yi okutun.</td></tr>
<tr><td>“Bu çekme BC'de silinmiş veya kapatılmış. İşlem yapılamaz; belge listesine dönün.”</td><td>Belge kaydedilmiş ya da silinmiş. Listeye dönüp yenileyin.</td></tr>
<tr><td>Rafta malzeme yok ya da eksik</td><td><strong>📉 Eksik Bildir</strong>’e dokunun, <strong>Eksik Bildir — …</strong> penceresinde eksik miktarı girip onaylayın. “TAMAM: … için … eksik bildirildi” mesajını bekleyin ve sorumlunuza haber verin.</td></tr>
</tbody></table></section>
%%BACK%%</section>

<section id="sevkiyat"><h2>5. Sevkiyat</h2>
<p><strong>Ne zaman kullanılır?</strong> Satış siparişindeki malı depodan çıkarıp müşteriye göndermek için. Ana menüde <strong>Sevkiyat</strong> kutucuğu üç sekmeyle açılır: <strong>Toplama</strong> (ambar çekmeleri), <strong>Sevkiyat</strong> (ambar sevkiyatları) ve <strong>Sipariş</strong> (satış siparişinden doğrudan sevk). Sipariş sekmesi BC kurulumunda kapatılmışsa görünmez.</p>
<p><strong>Başlamadan önce:</strong> Satış siparişi serbest bırakılmış, ambar sevkiyatı kullanılan lokasyonda sevkiyat belgesi BC’de oluşturulmuş olmalıdır. İrsaliye yazdırılacaksa belge yazıcısının seçili olduğunu kontrol edin.</p>

<section id="sv-belge"><h3>5.1 Ambar sevkiyatı ve toplama açma</h3>
<ol class="steps">
<li><strong>Sevkiyat</strong> ekranında <strong>Sevkiyat</strong> sekmesine geçin. Belgeyi arayın ya da ürün barkoduyla bulun ve açın. Başlıkta “Sevk: …”, durum ve “👤 Atanan Kullanıcı: …” görünür.</li>
<li>Belge sizde değilse <strong>👤 Bana Ata</strong>’ya dokunun.</li>
<li>Mal henüz toplanmadıysa <strong>📦 Pick Oluştur</strong>’a dokunun. Terminal toplama belgesini açar (“TAMAM: Ambar Toplama … açıldı”) ve sizi <strong>Toplama</strong> sekmesinde bu belgeye götürür. Ürün birden fazla paletteyse terminal önce “Hangi paletten başlansın?” ya da “Birden fazla paletten topla” diye sorar; <strong>🧭 Raf sırasına göre topla</strong> seçeneğiyle devam edebilirsiniz.</li>
</ol></section>

<section id="sv-toplama"><h3>5.2 Toplama</h3>
<ol class="steps">
<li><strong>Sevkiyat → Toplama</strong> sekmesinde toplama belgesini açın (Pick Oluştur’dan geldiyseniz zaten açıktır). Satırlar varsayılan olarak raf sırasına göre dizilir (<strong>🧭 Bin</strong>).</li>
<li>Bir rafın etiketini okutursanız liste o raftan alınacak satırlara iner (“📍 Raf … — bu raftan alınacak satırlar”).</li>
<li><strong>Palet okutma zorunluysa</strong> satır kartında “Paletleri okutmak için dokunun” yazar. Karta dokunun; <strong>Palet Okutarak Toplama</strong> penceresinde önce <strong>“1. Kaynak rafın kodunu okut”</strong>, sonra <strong>“2. Paletin QR kodunu okut”</strong> adımlarını yapın ve <strong>Okutulan Paletleri Onayla</strong>’ya dokunun.</li>
<li><strong>Palet okutma zorunlu değilse</strong> ürünü okutun ya da satıra dokunun. <strong>Çekme Miktarı</strong> penceresinde miktarı ve gerekiyorsa lotu girip <strong>Onayla</strong>’ya dokunun. Kaynak LP alanı açıksa aldığınız paleti okutun.</li>
<li>Birden çok kaynak paletten toplanan ürünü tek bir sevk paletinde birleştirecekseniz okutmadan önce <strong>📦 Yeni Sevk LP</strong>’ye dokunun. Tam paletleri olduğu gibi sevk edecekseniz bu düğmeyi kullanmayın.</li>
<li>Bütün satırlar bitince <strong>✅ Toplamayı Kaydet</strong>’e dokunun. “Toplama kaydedildi.” mesajını bekleyin.</li>
</ol>
<div class="note">Ana menüdeki <strong>Toplama</strong> kutucuğu toplama işlerini türlerine göre ayrı kuyruklarda gösterir (<strong>Toplama türü</strong>: Multi, Mono, Tek SKU). Sevkiyattan <strong>Pick Oluştur</strong> ile açılan toplamalar Multi kuyruğunda listelenir. Aynı toplamayı Sevkiyat ekranının Toplama sekmesinden de tamamlayabilirsiniz.</div></section>

<section id="sv-kayit"><h3>5.3 Sevkiyatı kaydetme</h3>
<ol class="steps">
<li>Toplama kaydedildikten sonra <strong>Sevkiyat</strong> sekmesine dönün ve sevkiyat belgesini açın. Satırlarda sevk edilecek miktarlar görünür.</li>
<li>Lot takipsiz bir satırın miktarını değiştirmek için satıra dokunun ve <strong>Sevk Miktarı + Lot</strong> penceresinde miktarı girin. Lot takipli satıra dokunduğunuzda terminal lot/raf ayrımı için toplama akışını açar.</li>
<li>İrsaliye basılacaksa <strong>İrsaliye yazdır</strong>, fatura da kesilecekse <strong>Faturalandır</strong> kutusunu işaretleyin (bunu sorumlunuz söyler).</li>
<li>BC sevkiyat acentesi istiyorsa belgede <strong>Sevkiyat Acentesi</strong> kartı görünür; boşsa kayıt düğmesine bastığınızda önce acente seçimi açılır. Acenteyi seçip <strong>Kaydet</strong>’e dokunun.</li>
<li><strong>✅ Sevkiyatı Kaydet</strong>’e dokunun. “TAMAM: Sevkiyat kaydedildi” mesajından sonra liste ekranına dönülür.</li>
</ol>
<div class="warn">“TAMAM: Sevkiyat BC'de kaydedildi. UYARI: …” penceresi çıkarsa sevkiyat kaydedilmiştir; uyarı başka bir adımla (ör. belge numarası, yazdırma) ilgilidir. Sevkiyatı tekrar kaydetmeye çalışmayın, uyarıyı sorumlunuza iletin.</div></section>

<section id="sv-siparis"><h3>5.4 Satış siparişinden doğrudan sevk</h3>
<p>Lokasyon ambar sevkiyatı istemiyorsa ve siparişte lot/seri takipli ürün yoksa sevkiyat doğrudan siparişten yapılabilir.</p>
<ol class="steps">
<li><strong>Sevkiyat → Sipariş</strong> sekmesini açın. Siparişi <strong>SO no ile ara</strong> alanıyla ya da ürün barkoduyla bulun. Kartta <strong>“⚠ Ambar Sevk”</strong> yazıyorsa bu sipariş 5.1’deki ambar sevkiyatıyla gönderilir.</li>
<li>Siparişi açın, ürünü okutun ya da <strong>Ürün Tara</strong>’ya dokunun. <strong>Sevk Edilecek Miktar</strong> penceresinde miktarı girip onaylayın.</li>
<li>Gerekirse <strong>Aynı zamanda faturalandır</strong>’ı işaretleyin.</li>
<li><strong>✅ Sevk Et</strong>’e (faturayla <strong>✅ Sevk Et ve Faturalandır</strong>) dokunun. <strong>Sevkiyatı kaydet</strong> penceresinde “… satır sevk edilecek. Devam edilsin mi?” sorusunu <strong>Sevk Et</strong> ile onaylayın.</li>
</ol>
<p>Sipariş doğrudan sevk edilemiyorsa düğme <strong>Direkt sevkiyat yapılamaz</strong> yazar ve sarı kutuda nedeni görünür (“Bu lokasyon (…) için Ambar Sevkiyatı zorunlu …” ya da lot/seri izlemeli ürün uyarısı).</p></section>

<section id="sv-mesaj"><h3>5.5 Sık mesajlar</h3>
<table><thead><tr><th>Mesaj</th><th>Ne yapmalı?</th></tr></thead><tbody>
<tr><td>“Size atanmış sevkiyat yok. Tümünü görmek için "Tümü" seçin.”</td><td><strong>Tümü</strong>’ne dokunun.</td></tr>
<tr><td>“⚠️ '…' bu ambar çekmede yok”</td><td>Okutulan ürün ya da raf bu toplamada değil. Doğru belgede olduğunuzu kontrol edin.</td></tr>
<tr><td>Kayıt düğmesi “Miktar girin” / “Önce satırlara miktar girin”</td><td>Henüz hiçbir satıra miktar girilmedi.</td></tr>
<tr><td>Kayıt düğmesi “Satır yazımı bekleniyor”</td><td>Son girdiğiniz satır BC’ye yazılıyor; birkaç saniye bekleyin.</td></tr>
<tr><td>Kayıt düğmesi “Belge salt okunur”</td><td>Belge sizde değil. <strong>Bana Ata</strong> ile üzerinize alın.</td></tr>
<tr><td>“HATA: Kaynak palet listesi eksik geldi. Yanlış raftan toplama açılmadı; yenileyip tekrar deneyin.”</td><td>Bağlantı sorunu. Belgeyi yenileyip Pick Oluştur’u tekrar deneyin.</td></tr>
<tr><td>“🔬 Kalite kontrolü bekliyor — lot/seri kullanılamıyor.”</td><td>Bu lot sevk edilemez. Kalite sorumlusuna bildirin.</td></tr>
</tbody></table></section>
%%BACK%%</section>

<section id="transfer"><h2>6. Raflar / depolar arası transfer</h2>
<p><strong>Ne zaman kullanılır?</strong> Stoğu bir raftan başka bir rafa, bir LP’den başka bir LP’ye ya da bir lokasyondan başka bir lokasyona taşımak için. Terminalde üç yol vardır:</p>
<table><thead><tr><th>Ekran</th><th>Ne zaman?</th></tr></thead><tbody>
<tr><td><strong>Ad-Hoc Hareket</strong></td><td>Belgesiz, o an karar verilen taşımalar: palet (LP) ya da serbest ürün; aynı lokasyonda raftan rafa veya LP ile lokasyonlar arası.</td></tr>
<tr><td><strong>Yönlendirilmiş</strong></td><td>Ofisin BC’de hazırladığı hareket belgesini (Movement) uygulamak.</td></tr>
<tr><td><strong>LP</strong> ekranı</td><td>Bir LP’nin içeriğini aynı raftaki başka bir LP’ye aktarmak.</td></tr>
</tbody></table>
<p><strong>Başlamadan önce:</strong> Taşınacak stoğun bulunduğu rafı ve hedef rafı bilin. Raf ve LP etiketlerinin okunabilir olduğunu kontrol edin. Emin değilseniz önce <strong>Bin Sorgu</strong> ile kaynak rafın içeriğine bakın (7.3).</p>

<section id="tr-lp"><h3>6.1 Ad-Hoc Hareket: LP ile</h3>
<p>Ekran açıldığında <strong>🧺 LP ile</strong> modu seçilidir. Bu ekranda bir alana dokunmadan doğrudan okutabilirsiniz; üstteki 📷 kutusu sıradaki okutmayı söyler (“Okutun: kaynak raf (ya da doğrudan LP)”, “Okutun: LP (ya da başka raf / ürün)”, “Okutun: hedef raf ya da hedef LP”).</p>
<ol class="steps">
<li>Ana menüden <strong>Ad-Hoc Hareket</strong>’i açın.</li>
<li><strong>1) Kaynak Bin okut</strong>: paletin bulunduğu rafı okutun. O raftaki LP’ler listelenir (“TAMAM: … bininde N LP — dokunarak seçin”). Liste gelmezse <strong>📋 2) Bu Bindeki LP'leri Listele</strong>’ye dokunun.</li>
<li>Taşıyacağınız LP’ye listede dokunun (<strong>Seç ›</strong>) ya da LP etiketini okutun. Elle yazdıysanız <strong>📥 LP İçeriğini Getir</strong>’e dokunun.</li>
<li><strong>3) LP içeriği</strong> bölümünde ürünleri, miktarları ve lotları kontrol edin. Boş LP de taşınabilir (“3) LP boş — yine de taşınabilir”).</li>
<li><strong>4) Hedef okut (LP veya Bin)</strong>:
<ul>
<li>Paleti başka bir rafa koyacaksanız <strong>hedef rafı</strong> okutun. Düğme <strong>✅ LP'yi … Rafına Taşı</strong> olur.</li>
<li>İçeriği aynı raftaki başka bir LP’ye boşaltacaksanız <strong>hedef LP</strong>’yi okutun. Düğme <strong>✅ İçeriği … LP'sine Aktar</strong> olur.</li>
<li>Elle yazdıysanız <strong>🔎 Hedefi Doğrula (LP mi bin mi?)</strong>’ya dokunun.</li>
</ul></li>
<li>Düğmeye dokunun. Rafa taşımada “TAMAM: LP … ve stok içeriği atomik olarak … rafına taşındı”, LP’ye aktarmada “TAMAM: … içeriği aynı raftaki … LP'sine aktarıldı” mesajı çıkar.</li>
</ol>
<p><strong>Başka lokasyona (depoya) taşıma:</strong> LP içeriği yüklendikten sonra <strong>Hedef lokasyon:</strong> düğmesi görünür; varsayılan olarak paletin kendi lokasyonu “(aynı)” seçilidir.</p>
<ol class="steps">
<li><strong>Hedef lokasyon:</strong> düğmesine dokunun ve listeden hedef lokasyonu seçin. Düğmede “(lokasyon değişir)” yazar.</li>
<li><strong>📋 … raflarını listele</strong> ile hedef lokasyonun raflarını getirin ve rafa dokunun ya da <strong>4) Hedef raf okut (…)</strong> alanına raf etiketini okutun. Hedef lokasyonda raf yoksa alanı boş bırakabilirsiniz.</li>
<li><strong>✅ LP'yi …'e taşı (lokasyon değişir)</strong> düğmesine dokunun. “TAMAM: LP … ve içeriği … → … taşındı (madde yeniden sınıflandırma)” mesajını bekleyin.</li>
</ol>
<div class="note">Lokasyonlar arası taşıma belgesiz yapılır ve BC’de madde yeniden sınıflandırma kaydı olarak işlenir. Bu taşımayı yalnız sorumlunuzun belirlediği durumlarda yapın.</div></section>

<section id="tr-urun"><h3>6.2 Ad-Hoc Hareket: ürün ile</h3>
<p>Bu mod yalnız LP’ye atanmamış serbest stoğu taşır. Rafta LP varsa LP ile modunu kullanın; sistem LP’yi otomatik bölmez.</p>
<ol class="steps">
<li><strong>Ad-Hoc Hareket</strong> ekranında <strong>📦 Ürün ile</strong>’ye dokunun.</li>
<li><strong>Kaynak Bin</strong>: ürünü aldığınız rafı okutun (“TAMAM: Kaynak raf … — ürünü okutun”).</li>
<li><strong>Ürün / LP</strong>: ürün barkodunu okutun (“TAMAM: Ürün … — hedef rafı okutun”).</li>
<li><strong>Hedef Bin</strong>: ürünü koyacağınız rafı okutun.</li>
<li><strong>Miktar</strong>: taşıdığınız miktarı girin.</li>
<li>Lot takipli üründe <strong>Lot No (lot izlemeli üründe)</strong> alanına lotu okutun ya da <strong>📋 Kaynak Bindeki Lotları Göster</strong> ile listeden seçin.</li>
<li><strong>✅ Hareketi Onayla</strong>’ya dokunun. Ekranda “✅ Hareket kaydedildi” özeti çıkar. Yeni taşıma için <strong>Tamam — Yeni Hareket</strong>’e dokunun.</li>
</ol>
<div class="note">Ürün ile modunda bir LP etiketi okutursanız terminal LP ile moduna geçer. LP ile modunda bir ürün okutursanız “📦 Ürün okutuldu (…) — “Ürün ile” moduna geçildi. Hedef rafı okutun.” yazar.</div></section>

<section id="tr-yonlendirilmis"><h3>6.3 Yönlendirilmiş hareket</h3>
<p>Yönlendirilmiş hareket belgeleri ofiste BC’de (Movement Worksheet → Create Movement) hazırlanır. Belgede her taşıma için bir <strong>📤 Al</strong> (kaynak) ve bir <strong>📥 Bırak</strong> (hedef) satırı bulunur.</p>
<ol class="steps">
<li>Ana menüden <strong>Yönlendirilmiş</strong>’i açın. Size atanan belgeler listelenir (<strong>👤 Bana atanan</strong> / <strong>Tümü</strong>). Belge sizde değilse kartındaki <strong>✋ Üzerime Al</strong>’a dokunun.</li>
<li>Belgeyi açın. Ekranda “Satırlar (N) — Al satırına dokunun; kaynak rafı ve LP'yi doğrulayın” yazar.</li>
<li>Bir <strong>📤 Al</strong> satırına dokunun. <strong>Yönlendirilmiş Al Doğrulaması</strong> penceresinde taşınacak madde, miktar, kaynak raf ve hedef raf görünür.</li>
<li><strong>1) Kaynak rafı okutun</strong>: “Beklenen raf: …” yazan rafı okutun. “✓ … doğru raf” görünür.</li>
<li><strong>2) Bu raftan alınacak LP'yi okutun</strong>: <strong>Kaynak LP</strong> alanına paleti okutun. Terminal LP’nin madde, lot ve miktarını kontrol eder; “✓ LP doğrulandı: …” ile birlikte madde, lot ve LP miktarı görünür.</li>
<li><strong>✓ LP ile Al Satırını Onayla</strong>’ya dokunun. “TAMAM: … LP doğrulandı; Al/Bırak miktarı … olarak hazırlandı.”</li>
<li>Bütün Al satırları için 3.–6. adımları tekrarlayın. Ardından <strong>✅ Hareketi Kaydet</strong>’e dokunun. “TAMAM: … kaydedildi — stok taşındı” mesajını bekleyin.</li>
</ol>
<div class="warn">“UYARI: Kayıt sonucunun sunucudaki durumu doğrulanamadı. Tekrar kaydetmeyin; güncel durum okunuyor.” mesajında düğmeye yeniden basmayın; terminalin belgeyi yeniden okumasını bekleyin.</div></section>

<section id="tr-lp-lp"><h3>6.4 LP’den LP’ye aktarma (LP ekranı)</h3>
<ol class="steps">
<li>Ana menüden <strong>LP</strong>’yi açın ve kaynak LP’yi listeden seçin ya da etiketini okutun. Ana menüde LP okutup açılan kartta <strong>LP İşlemleri</strong>’ne dokunarak da gelebilirsiniz.</li>
<li>LP ekranında <strong>Diğer İşlemler ▾</strong> → <strong>Transfer (başka LP'ye aktar)</strong>’ı seçin.</li>
<li><strong>LP Transferi</strong> penceresinde “Seçilen miktarı aynı raftaki hedef LP'ye taşır. Kısmi taşımak için miktarı azaltın; kalan bu LP'de durur.” yazar. <strong>Hedef LP No</strong> alanına hedef LP’yi okutun.</li>
<li>Her satırın miktarı varsayılan olarak tamamıdır; kısmi aktaracaksanız miktarı azaltın.</li>
<li><strong>Transfer Et</strong>’e dokunun.</li>
</ol>
<div class="note">Mal kabulü bekleyen LP’de Transfer seçeneği görünmez. Hedef LP kaynak LP ile aynı rafta olmalıdır; değilse önce hedef LP’yi aynı rafa taşıyın.</div></section>

<section id="tr-mesaj"><h3>6.5 Sık mesajlar</h3>
<table><thead><tr><th>Mesaj</th><th>Ne yapmalı?</th></tr></thead><tbody>
<tr><td>“HATA: …, … rafında kayıtlı. Kaynak rafı kontrol edin.”</td><td>Okuttuğunuz LP sistemde başka rafta görünüyor. Kaynak rafı doğru okutun; LP gerçekten bu raftaysa sorumluya bildirin.</td></tr>
<tr><td>“HATA: Hedef LP kaynak LP ile aynı rafta değil. Önce hedef LP’yi aynı rafa taşıyın.”</td><td>İçerik aktarımı yalnız aynı raftaki LP’ler arasında yapılır.</td></tr>
<tr><td>“HATA: Kaynak ve hedef LP aynı olamaz.”</td><td>Hedef olarak farklı bir LP ya da raf okutun.</td></tr>
<tr><td>“HATA: '…' geçerli bir LP veya raf değil.”</td><td>Hedef etiketini kontrol edip yeniden okutun.</td></tr>
<tr><td>“HATA: '…' … lokasyonunda bir raf değil.”</td><td>Okuttuğunuz raf seçtiğiniz hedef lokasyonda yok. Lokasyonu ya da rafı kontrol edin.</td></tr>
<tr><td>“Hedef olarak raf okutun. LP taşımak için “LP ile” modunu kullanın.”</td><td>Ürün ile modunda hedefe LP okutuldu. LP ile moduna geçin.</td></tr>
<tr><td>“EKSİK: …”</td><td>Ürün ile modunda eksik alan var (kaynak raf, ürün, hedef raf veya miktar). Yazan alanı doldurun.</td></tr>
<tr><td>“⏳ Önceki işlem sürüyor — bitince yeniden okutun.”</td><td>Terminalin bir önceki işlemi bitirmesini bekleyin.</td></tr>
<tr><td>Yönlendirilmiş: “HATA: Yanlış raf. Beklenen …, okutulan …”</td><td>Belgede yazan kaynak rafa gidin.</td></tr>
<tr><td>Yönlendirilmiş: “HATA: … içinde … var; hareket … istiyor.”</td><td>LP’deki miktar hareketin istediğinden az. Başka bir LP seçin ya da sorumluya bildirin.</td></tr>
<tr><td>Yönlendirilmiş: “HATA: … rafında … için … miktar kullanılabilir stok yok.”</td><td>Kayıt yapılmadı. Raf stoğunu Bin Sorgu ile kontrol edin, sorumluya bildirin.</td></tr>
</tbody></table></section>
%%BACK%%</section>

<section id="sorgu"><h2>7. Barkodla madde ve stok sorgulama</h2>
<p><strong>Ne zaman kullanılır?</strong> Bir ürünün nerede ve ne kadar olduğunu, bir rafta ya da LP’de ne bulunduğunu ya da geçmiş stok hareketlerini görmek için. Sorgu ekranları stoğu değiştirmez.</p>
<p><strong>Başlamadan önce:</strong> Okutacağınız ürün, raf ya da LP etiketinin okunabilir olduğunu kontrol edin. Bin Sorgu için lokasyon kodunu bilin.</p>

<section id="sq-lp"><h3>7.1 Ana menüde LP okutma</h3>
<p>Ana menü açıkken bir LP’nin QR kodunu ya da SSCC barkodunu okutursanız LP ekranında o LP’nin içerik kartı açılır. Kartta <strong>LP …</strong> başlığı ve durumu, <strong>Depo / Göz</strong>, <strong>Atandığı belge</strong>, <strong>Bekleyen mal kabul</strong>, <strong>SSCC</strong>, <strong>Toplam</strong> ve <strong>İçerik (N satır)</strong> görünür. <strong>İçeriği Yenile</strong> güncel durumu getirir, <strong>LP İşlemleri</strong> LP ekranını açar. Etiket düğmeleri “Sayım ve Etiket Kılavuzu”nda anlatılır.</p></section>

<section id="sq-urun"><h3>7.2 Ürün Sorgu</h3>
<ol class="steps">
<li>Ana menüden <strong>Ürün Sorgu</strong>’yu açın.</li>
<li><strong>Ürün No / LP No</strong> alanına ürünün barkodunu okutun ya da numarasını yazıp <strong>🔎 Sorgula</strong>’ya dokunun. LP etiketi okutursanız o LP’nin içeriği gelir.</li>
<li>Ürün kartında şunları görürsünüz:
<ul>
<li><strong>Stok</strong>, <strong>Müsait</strong> ve <strong>Rezerve</strong> kutuları ile altında “Gelen … · Giden … · Üretim …” satırı.</li>
<li><strong>Temel UOM</strong>, kategori, LP şablonu ve <strong>LP'lerdeki toplam</strong>.</li>
<li><strong>LP'lerde (N)</strong>: ürünün bulunduğu her LP; lot, seri, yer (depo/göz) ve miktar.</li>
<li><strong>Son Hareketler (N)</strong>: hareket türü, belge no, tarih, lokasyon ve lot.</li>
</ul></li>
<li>Bir LP’nin içeriğini görmek için ilgili kartta <strong>LP içeriği ve etiketi ›</strong>’ye dokunun.</li>
</ol>
<div class="note">“BOŞ: '…' için ürün veya LP bulunamadı.” mesajı, okutulan değerin BC’de bir ürün ya da LP ile eşleşmediğini gösterir. Etiketi ve terminalin sorumlunuzun teyit ettiği Kitoko bağlantısında olduğunu kontrol edin. Sand2010 · Kitoko bağlantısında terminal ürün listesi henüz boştur (kurulum bekliyor); bu bağlantıda her sorgu bu mesajı verir. “Bu ürün hiçbir LP'de bulunmuyor.” ürünün LP’siz (serbest) stokta olduğunu ya da stokta olmadığını gösterir; Stok kutusuna bakın.</div></section>

<section id="sq-bin"><h3>7.3 Bin Sorgu</h3>
<ol class="steps">
<li>Ana menüden <strong>Bin Sorgu</strong>’yu açın. Ekranda “Lokasyon + Bin girin.” yazar.</li>
<li><strong>Lokasyon</strong> alanına lokasyon kodunu yazın ya da okutun.</li>
<li><strong>Bin</strong> alanına rafın etiketini okutun ve <strong>🔎 Sorgula</strong>’ya dokunun. İki alan da dolu olmadan sorgu yapılmaz.</li>
<li>Raf kartında lokasyon / raf kodu, bölge ve tip görünür. Altında:
<ul>
<li><strong>Bin İçeriği (N)</strong>: raftaki ürünler ve miktarları.</li>
<li><strong>LP'ler (N)</strong>: raftaki aktif LP’ler, durumları ve SSCC’leri.</li>
<li><strong>Ambar Kayıtları (N)</strong>: rafın son ambar hareketleri (ürün, hareket türü, tarih, lot, LP).</li>
</ul></li>
</ol>
<div class="note">“BOŞ: '…/…' için içerik yok.” mesajı rafın boş olduğunu ya da lokasyon / raf kodunun yanlış girildiğini gösterir.</div></section>

<section id="sq-hareket"><h3>7.4 Ambar Hareketleri</h3>
<ol class="steps">
<li>Ana menüden <strong>Ambar Hareketleri</strong>’ni açın. Son hareketler en yeni üstte listelenir (“TAMAM: N kayıt (en yeni üstte)”).</li>
<li>Daraltmak için <strong>Filtrele</strong>’ye dokunun ve <strong>Bin</strong>, <strong>Ürün</strong> veya <strong>Lot</strong> alanlarından birine ya da birkaçına okutun; <strong>Ara</strong>’ya dokunun.</li>
<li>Filtre açıkken başlıkta “Filtreler · açık” ve seçtiğiniz değerler görünür. Filtreleri kaldırmak için <strong>Temizle</strong>’ye dokunun.</li>
</ol>
<p>“BOŞ: Filtreye uyan hareket yok” mesajında filtreyi değiştirin ya da yenileyin.</p></section>
%%BACK%%</section>

<section id="sayim"><h2>8. Sayım</h2>
<p>Sayım (<strong>Sayım</strong> ve <strong>İlk Sayım</strong> ekranları) ve farkların stoklara işlenmesi bu kılavuzda anlatılmaz. Adımlar için “Sayım ve Etiket Kılavuzu”nun <em>5. Normal sayım</em> bölümüne bakın.</p>
%%BACK%%</section>

<section id="sorun"><h2>9. Genel sorun giderme</h2>
<table><thead><tr><th>Ne görüyorsunuz?</th><th>Ne yapın?</th></tr></thead><tbody>
<tr><td>Belgeler, ürünler ya da stoklar eksik veya farklı görünüyor</td><td>Ana menü başlığında şirketin ve ortamın sorumlunuzun teyit ettiği Kitoko bağlantısı olduğunu kontrol edin. Değilse <strong>Ortam / şirket değiştir</strong> ile düzeltin. Sand2010 · Kitoko bağlantısı kurulum beklediği için orada listeler boş gelir.</td></tr>
<tr><td>“Henüz bağlanmadınız. Bağlantı ekranından giriş yapın.”</td><td>Wi-Fi’yi kontrol edin ve yeniden giriş yapın.</td></tr>
<tr><td>“Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın.”</td><td><strong>Kullanıcı çıkışı</strong> yapıp kendi kullanıcınız ve PIN’inizle yeniden girin.</td></tr>
<tr><td>Ana menüde bir kutucuk yok</td><td>Kutucuk BC’deki terminal ekran düzeninde gizlenmiş olabilir. Sorumlunuza bildirin.</td></tr>
<tr><td>“Bu bölüm Production ortamında yalnızca Yönetici erişimine açıktır.”</td><td>Terminal canlı (Production) ortama bağlı ve bu ekran orada yöneticiye açık. Ortamı kontrol edin; gerekiyorsa yöneticinize başvurun.</td></tr>
<tr><td>Düğmeler pasif, belgede kırmızı “… kullanıcısına atanmış” yazısı</td><td>Belge başkasında. <strong>Bana Ata</strong> ile devralmadan önce belgedeki kişiyle konuşun.</td></tr>
<tr><td>“HATA: … listesinin tamamı alınamadı. Yenileyin.” / “Belgenin tüm satırları yüklenemedi.”</td><td>Bağlantı zayıf. Wi-Fi’nin iyi çektiği bir yerde yenileyin. Satırlar tam yüklenmeden kayıt yapılmaz.</td></tr>
<tr><td>Okutma tepki vermiyor</td><td>Ekranda açık bir pencere ya da sürmekte olan işlem olabilir; bitmesini bekleyin. Barkod okunmuyorsa <kbd>⌨</kbd> ile değeri yazıp <kbd>OK</kbd>’a dokunun.</td></tr>
<tr><td>“⚠️ '…' bu belgede yok”</td><td>Okuttuğunuz ürün açtığınız belgede değil. Belgeyi ve etiketi kontrol edin.</td></tr>
<tr><td>“🔬 Kalite kontrolü bekliyor …”</td><td>Lot kalite kontrolünde; kullanılamaz. Kalite sorumlusuna bildirin.</td></tr>
<tr><td>“UYARI: … doğrulanamadı. Tekrar kaydetmeyin …” ya da kayıttan sonra cevap gelmedi</td><td>Kayıt düğmesine yeniden basmayın. Belgeyi yenileyin ve kaydın BC’ye ulaşıp ulaşmadığını görün.</td></tr>
<tr><td>Etiket çıkmıyor</td><td>Başlıktaki “Yazıcı: …” bilgisini kontrol edin; yazıcı, bağlı bilgisayar ve Print Agent açık olmalıdır (“Etiket Yazıcı Genel Kılavuzu”). Kaydı tekrar yapmayın; etiketi ilgili ekrandan yeniden basın.</td></tr>
<tr><td>Fiziksel stok ile terminaldeki stok farklı</td><td>Terminalde düzeltme yapmaya çalışmayın. Ürün Sorgu / Bin Sorgu ekranının görüntüsünü alıp sorumlunuza bildirin; fark sayımla düzeltilir.</td></tr>
</tbody></table>
<p>Çözülmeyen durumlarda ekranın görüntüsünü alın; hangi ekranda, hangi belgede ve hangi düğmeye bastığınızı da yazarak destek ekibine iletin.</p>
%%BACK%%</section>
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    body = BODY.replace('%%BACK%%', BACK)
    path = OUT / f'{STEM}.html'
    path.write_text(page(
        TITLE, 'Kitoko · El terminali',
        'El terminaliyle mal kabulü, rafa yerleştirmeyi, üretime malzeme çıkışını, sevkiyatı, raflar ve depolar arası '
        'transferi ve barkodla stok sorgulamayı adım adım anlatır.',
        TOC, body,
        f'Hazırlayan: DynamicsOps · {DATE} · BCWMS Kitoko {VERSION} · Kitoko Aydınlatma ve Müh. A.Ş. Ekran metinleri uygulamanın bu sürümünden alınmıştır; kurulum durumu 27.10.2026 tarihinde BC üzerinde doğrulanmıştır.'),
        encoding='utf-8')
    render_pdf(path, OUT / f'{STEM}.pdf')
    print(path)


if __name__ == '__main__':
    main()
