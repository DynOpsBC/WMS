#!/usr/bin/env python3
"""Kitoko / Element 4 Tablet (Shop Floor) kullanım kılavuzu (Azure DevOps #2696).

Kapsam: üretim emrinin başlatılması ve bitirilmesi, depodan malzeme talebi,
tüketim ve çıktı bildirimi, duruş kaydı.

Kaynak: DynamicsOps ShopFloor web uygulaması 1.3.0.18 (ShopFloor/web: app/, lib/),
Element4 kurulumu (Element4/build/shopfloor-element4-kurulum.sh: PRINT_MODE=disabled,
roller ShopFloor Operator / Manager / Executive) ve BC uzantısı (ShopFloor/src:
ShopFloor Hızlı Kurulum, ShopFloor Kullanıcı Ekle).

Tek sayfada kayan, içindekiler tıklanabilir HTML üretir; PDF'i Chrome basar.
Ekranlar uygulamanın yerel test modunda (SHOP_FLOOR_MODE=demo, örnek veri, BC/Azure
bağlantısı yok) headless Chrome ile alınmıştır: output/kilavuzlar/shopfloor-ekranlar.
Stil iskeleti generate-kitoko-guides.py ile aynıdır (CSS, page, BACK, render_pdf).
"""
import base64
import html
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/kilavuzlar'
SHOTS = OUT / 'shopfloor-ekranlar'
PRODUCT = 'DynamicsOps ShopFloor'
VERSION = '1.3.0.18'
DATE = '27 Ekim 2026'
APP_URL = 'https://dynops-shopfloor-element4-e4k7a2.azurewebsites.net'

CSS = """
*{box-sizing:border-box}body{margin:0;background:#eef2f5;color:#14263b;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.6}
.wrap{max-width:980px;margin:0 auto;padding:28px 22px 60px;display:grid;grid-template-columns:230px 1fr;gap:28px}
nav.toc{position:sticky;top:18px;align-self:start;background:#fff;border:1px solid #d9e2ea;border-radius:10px;padding:14px 14px 10px;font-size:13.5px}
nav.toc b{display:block;font-size:12px;letter-spacing:1.2px;color:#4e6986;text-transform:uppercase;margin-bottom:8px}
nav.toc a{display:block;color:#0f5f5b;text-decoration:none;padding:4px 6px;border-radius:6px}nav.toc a:hover{background:#e1f3f0}nav.toc a.sub{padding-left:18px;color:#3d5a6e;font-size:13px}
main{background:#fff;border:1px solid #d9e2ea;border-radius:12px;padding:30px 34px}
.eyebrow{font-size:12px;letter-spacing:1.6px;color:#4e6986;font-weight:700;text-transform:uppercase}
h1{font-size:31px;line-height:1.15;margin:6px 0 10px;letter-spacing:-.5px}h2{font-size:22px;margin:38px 0 10px;padding-top:14px;border-top:2px solid #158b86}h3{font-size:17px;margin:24px 0 8px;color:#114b5f}
p{margin:0 0 12px}.lead{font-size:16.5px;color:#42586b}.meta{font-size:13px;color:#5a6f82;margin-bottom:18px}
ol.steps{counter-reset:s;list-style:none;padding:0;margin:12px 0 18px}ol.steps>li{counter-increment:s;position:relative;padding:2px 0 10px 40px}
ol.steps>li:before{content:counter(s);position:absolute;left:0;top:0;width:27px;height:27px;border-radius:50%;background:#e1f3f0;color:#126b68;font-weight:700;display:grid;place-items:center;font-size:14px}
.note,.warn,.info{padding:12px 15px;border-radius:0 8px 8px 0;margin:12px 0 16px;font-size:14.5px}.note{border-left:4px solid #158b86;background:#eff8f7}.warn{border-left:4px solid #c98a12;background:#fff6e3}.info{border-left:4px solid #3d6fb4;background:#eef3fb}
table{border-collapse:collapse;width:100%;margin:10px 0 18px;font-size:14px}th,td{text-align:left;padding:9px 11px;border-bottom:1px solid #dbe4eb;vertical-align:top}th{background:#edf4f7;color:#3c596c;font-size:13px}
.shots{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:16px;margin:14px 0 18px}figure{margin:0}figure img{width:100%;max-width:300px;border:1px solid #d4dde5;border-radius:8px;display:block}figcaption{font-size:12.5px;color:#52677b;margin-top:6px;line-height:1.35}
kbd{background:#f1f4f7;border:1px solid #cdd8e1;border-radius:4px;padding:1px 6px;font-size:13px;font-family:inherit}
.back{font-size:12.5px;margin-top:6px}.back a{color:#4e6986}
footer{margin-top:34px;padding-top:12px;border-top:1px solid #dbe4eb;font-size:12.5px;color:#63778a}
@media (max-width:820px){.wrap{grid-template-columns:1fr;padding:14px}nav.toc{position:static}main{padding:20px}}
@media print{body{background:#fff;font-size:12.5px}.wrap{display:block;max-width:none;padding:0}nav.toc{display:none}main{border:0;padding:0}h2{break-after:avoid}figure,table,.note,.warn,.info{break-inside:avoid}.back{display:none}}
"""


def img(name):
    data = (SHOTS / name).read_bytes()
    return 'data:image/png;base64,' + base64.b64encode(data).decode()


def fig(name, caption, width=None):
    """Tablet ekranı yatay olduğu için görsel tam genişlikte gösterilir (CSS değişmeden, satır içi stil)."""
    limit = f'max-width:{width}px' if width else 'max-width:100%'
    return (f'<div class="shots" style="grid-template-columns:1fr"><figure><img style="{limit}" src="{img(name)}" '
            f'alt="{html.escape(caption)}"><figcaption>{caption}</figcaption></figure></div>')


def page(title, eyebrow, lead, toc, body, foot):
    links = ''.join(f'<a class="{"sub" if sub else ""}" href="#{a}">{html.escape(t)}</a>' for a, t, sub in toc)
    return (f'<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)}</title><style>{CSS}</style></head><body><div class="wrap">'
            f'<nav class="toc"><b>İçindekiler</b>{links}</nav><main id="top"><div class="eyebrow">{eyebrow}</div>'
            f'<h1>{html.escape(title)}</h1><p class="meta">{DATE} · {PRODUCT} {VERSION}</p><p class="lead">{lead}</p>'
            f'{body}<footer>{foot}</footer></main></div></body></html>')


BACK = '<p class="back"><a href="#top">↑ Başa dön</a></p>'

TEST_NOTE = ('Ekran görüntüleri uygulamanın yerel <strong>test modunda</strong> (örnek veri, Business Central bağlantısı yok) alınmıştır. '
             'Şirket adı, emir ve madde numaraları örnektir; üst çubuktaki “TEST” ve “TEST VERİSİ” ibareleri yerine sizin ekranınızda '
             'bağlı olduğunuz BC ortamı ve <strong>Bağlı</strong> durumu görünür.')

TOC = [('amac', 'Bu kılavuz ne anlatır?', False),
       ('giris', '1. Tablete giriş ve roller', False), ('acma', '1.1 Uygulamayı açma ve giriş', True),
       ('roller', '1.2 Roller ve yetkiler', True), ('ekran', '1.3 Operatör ekranını tanıyın', True),
       ('detayli', '1.4 Detaylı ekran ve yönetici panosu', True), ('hesap', '1.5 Kullanıcı değiştirme ve çıkış', True),
       ('kurulum', '1.6 Yönetici için: BC’de kullanıcı tanımlama', True),
       ('emir', '2. Üretim emrini başlatma ve bitirme', False), ('emir-sec', '2.1 Emri seçme', True),
       ('adim', '2.2 Rota ve adım seçimi', True), ('baslat', '2.3 Başlat', True),
       ('ara-bitir', '2.4 Ara adımı bitirme', True), ('son-adim', '2.5 Son adım: Bitir ve kaydet', True),
       ('kayitlar', '2.6 Kayıtlar ve nakil durumu', True), ('kilit', '2.7 Takılı oturum: Kilidi kaldır', True),
       ('talep', '3. Depodan malzeme talebi', False), ('talep-ac', '3.1 Talep oluşturma', True),
       ('talep-izle', '3.2 Talebi izleme', True),
       ('tuketim', '4. Tüketim ve çıktı bildirimi', False), ('recete', '4.1 Reçete tablosu', True),
       ('malzeme', '4.2 Malzeme çekmecesi', True), ('lot', '4.3 Tüketim lotu', True),
       ('cikti', '4.4 Çıktı, fire ve üretim lotu', True), ('yan-urun', '4.5 Yan ürünler', True),
       ('detay-bildirim', '4.6 Detaylı ekrandan bildirim', True),
       ('durus', '5. Duruş kaydı', False),
       ('sorun', '6. Sık mesajlar ve sorun giderme', False)]

BODY = f"""
<section id="amac"><h2>Bu kılavuz ne anlatır?</h2>
<p>Bu kılavuz, Element 4 atölyesinde tablet üzerinden çalışan <strong>DynamicsOps Üretim</strong> (Shop Floor) uygulamasının günlük kullanımını anlatır. Uygulama Business Central’daki serbest bırakılmış üretim emirlerini gösterir; sizin tabletten girdiğiniz başlatma, bitirme, tüketim ve çıktı bilgilerini Business Central üretim günlüğüne kaydeder. Stok ve kapasite kayıtları Business Central’ın standart nakil (posting) işlemiyle oluşur; tablet BC’deki veriyi doğrudan değiştirmez.</p>
<p>Kılavuz dört işi adım adım anlatır: <strong>üretim emrinin başlatılması ve bitirilmesi</strong>, <strong>depodan malzeme talebi</strong>, <strong>tüketim ve çıktı bildirimi</strong> ve <strong>duruş kaydı</strong>. Başta tablete nasıl gireceğiniz ve rolünüze göre neler yapabileceğiniz, sonda da sık görülen mesajlar yer alır.</p>
<div class="info"><strong>Bu kurulumda kapalı olanlar:</strong> Element 4 kurulumunda etiket yazdırma kapalıdır (<kbd>PRINT_MODE=disabled</kbd>). Bu yüzden <strong>Etiket</strong> çekmecesindeki <strong>Etiket yazıcısına gönder</strong> düğmesi pasif görünür, ekranda “Etiket yazdırma kapalı.” yazar ve kayıt fişinde <strong>Etiket bas</strong> düğmesi çıkmaz. Etiket konusu bu kılavuzun kapsamında değildir. Duruş kaydının bu sürümdeki durumu 5. bölümde ayrıca anlatılır.</div>
<div class="note">{TEST_NOTE}</div>
{BACK}</section>

<section id="giris"><h2>1. Tablete giriş ve roller</h2>
<section id="acma"><h3>1.1 Uygulamayı açma ve giriş</h3>
<p>Uygulama bir web uygulamasıdır; tablete ayrıca program kurmanız gerekmez. Giriş, <strong>Kitoko kurumsal Microsoft (Entra) hesabınızla</strong> yapılır; ayrı bir kullanıcı adı veya PIN yoktur.</p>
<ol class="steps">
<li>Tabletteki tarayıcıda Element 4 uygulama adresini açın: <kbd>{APP_URL}</kbd>. Sık kullanacağınız için adresi yer imlerine ekleyin; tarayıcınız sunuyorsa “Ana ekrana ekle / Uygulamayı yükle” seçeneğiyle simge olarak da yerleştirebilirsiniz.</li>
<li>Microsoft giriş sayfası açılır. Kitoko e-posta adresinizi ve parolanızı girin; kuruluşunuzun istediği ek doğrulamayı tamamlayın.</li>
<li>Giriş başarılıysa önce “Üretim emirleri hazırlanıyor…” yazısı, ardından <strong>Operatör ekranı</strong> gelir. Sağ üstte adınızı ve rolünüzü (ör. “Üretim Operatörü”) görmelisiniz.</li>
<li>Ekran açılmaz da bir mesaj çıkarsa mesajı okuyun. En sık iki durum: <em>“Bu kullanıcıya Shop Floor uygulama rolü atanmamış.”</em> (Entra’da rolünüz yok) ve <em>“Oturum açan kullanıcı Business Central çalışan kaydıyla eşleşmiyor.”</em> (BC’de çalışan kaydınız yok). İkisinde de yöneticinize başvurun (1.6). <strong>Tekrar dene</strong> ve <strong>Yeniden giriş yap</strong> düğmeleri yalnız bağlantı veya oturum süresi sorunlarını çözer.</li>
</ol>
<div class="note">Uygulama her 30 saniyede bir BC verisini kendiliğinden yeniler. Üst çubuktaki bağlantı düğmesi son yenileme saatini gösterir; dokunursanız ekran hemen yenilenir.</div></section>

<section id="roller"><h3>1.2 Roller ve yetkiler</h3>
<p>Uygulamaya girebilmek için Kitoko Entra’da size üç uygulama rolünden biri atanmış olmalıdır: <strong>ShopFloor Operator</strong>, <strong>ShopFloor Manager</strong> veya <strong>ShopFloor Executive</strong>. Bu rol yalnız kapıyı açar. Ekranda neleri yapabileceğinizi Business Central’daki <strong>çalışan kaydınızın görevi</strong> belirler; görev, yönetici tarafından <strong>ShopFloor Kullanıcı Ekle</strong> sayfasında seçilir.</p>
<table><thead><tr><th>Görev (BC)</th><th>Önerilen Entra rolü</th><th>Ekranda görünen</th><th>Neler yapabilir?</th></tr></thead><tbody>
<tr><td><strong>Operatör</strong></td><td>ShopFloor Operator</td><td>Üretim Operatörü</td><td>Emir seçer, adımı <strong>Başlat</strong>ır ve bitirir, tüketim ve çıktı girer, depodan malzeme ister, kendi kayıtlarını <strong>BC’de naklet</strong> ile hemen naklettirir. Detaylı ekranda Yönetim paneli ve Üretim planı görünmez.</td></tr>
<tr><td><strong>Vardiya sorumlusu</strong></td><td>ShopFloor Operator veya Manager</td><td>Vardiya Lideri</td><td>Operatörün yaptığı her şey; ayrıca detaylı ekranda <strong>Operatör / Yönetici</strong> görünüm geçişi, <strong>Yönetim paneli</strong> ve <strong>Üretim planı</strong>; başka çalışanın takılı oturumunda <strong>Kilidi kaldır</strong>; kurulum izin veriyorsa reçete düzenleme.</td></tr>
<tr><td><strong>Üretim yöneticisi / planlama</strong></td><td>ShopFloor Manager</td><td>Üretim Müdürü</td><td>Vardiya sorumlusunun yaptıkları; ayrıca <strong>＋ Yeni emir</strong> ile üretim emri açma ve reçete düzenleme.</td></tr>
<tr><td><strong>Yönetim izleme</strong> (yönetici panosu)</td><td>ShopFloor Executive</td><td>Yönetici</td><td><strong>Salt okunur.</strong> Detaylı ekranı, Yönetim panelini ve Üretim planını görür; üretim kaydı gönderemez. Kayıt denemesinde “Bu kullanıcı üretim bildirimi gönderemez.” mesajı çıkar.</td></tr>
</tbody></table>
<div class="note">Bütün operatörler varsayılan olarak tüm iş merkezlerinde çalışabilir; hangi iş merkezinde çalıştığınız üretim emrinin rotasından alınır. Çalışan kaydınızda iş merkezi kısıtı varsa başka iş merkezindeki adımda <strong>Başlat</strong> düğmesinde “Başka iş merkezi · …” yazar.</div></section>

<section id="ekran"><h3>1.3 Operatör ekranını tanıyın</h3>
<p>Giriş sonrası açılan <strong>Operatör ekranı</strong> günlük işin tamamının yapıldığı tek ekrandır. Ekran yatay tablet için tasarlanmıştır; aşağı kaydırdıkça seçili emrin ayrıntıları gelir.</p>
{fig('01-operator-ekrani.png', 'Operatör ekranı. Solda “Çalışma listesi” (üretim emirleri) ve alttaki hızlı düğmeler; sağda seçili emrin başlığı, Plan / Üretilen / Kalan kutuları ve rota şeridi.')}
<table><thead><tr><th>Ekran bölümü</th><th>Ne işe yarar?</th></tr></thead><tbody>
<tr><td>Üst çubuk: <strong>İşlerim · Operasyon · Üretim emirleri · Reçeteler · ＋ Yeni emir</strong></td><td><strong>Operasyon</strong> bu ekrandır. Diğerleri detaylı ekranın ilgili sayfasını açar. <strong>Reçeteler</strong> ve <strong>＋ Yeni emir</strong> yalnız yetkili rollerde görünür.</td></tr>
<tr><td>Üst çubuk sağ: <strong>Ortam</strong>, bağlantı düğmesi, adınız ve <strong>Hesap</strong></td><td>Ortam kutusu bağlı olduğunuz BC ortamını gösterir. Bağlantı düğmesinde normalde <strong>Bağlı</strong> ve son yenileme saati yazar; sorun varsa <strong>YENİDEN BAĞLANIYOR</strong> veya <strong>ÇEVRİMDIŞI</strong> görünür. <strong>Hesap</strong> kullanıcı değiştirme ve çıkış sayfasını açar.</td></tr>
<tr><td><strong>Çalışma listesi</strong></td><td>Serbest bırakılmış üretim emirleri. <strong>Emir veya ürün ara</strong> kutusu, <strong>Üretilecek</strong> / <strong>Tümü</strong> sekmeleri. Her satırda emir no, durum (<em>Çalışıyor, Hazır, Malzeme eksik, Tamamlandı</em>), ürün, üretilen / plan ve termin.</td></tr>
<tr><td>Hızlı düğmeler: <strong>Emir okut · Malzeme · Etiket</strong></td><td>Barkodla emir açma, seçili adımın malzeme çekmecesi ve etiket çekmecesi (etiket yazdırma bu kurulumda kapalı).</td></tr>
<tr><td>Emir başlığı ve kutular</td><td>Ürün adı, emir no, madde no, termin, öncelik, “Lot zorunlu”, depo, lot ve sorumlu. <strong>Plan</strong>, <strong>Üretilen</strong>, <strong>Kalan</strong> kutuları ve ilerleme çubuğu; nakli süren miktar “… BC’ye aktarılıyor” olarak ayrıca gösterilir.</td></tr>
<tr><td>Rota şeridi</td><td>Emrin operasyonları. Tamamlanan adımda ✓ ve “Bitti”, çalışan adımda “▶ Çalışıyor · N dk”, son adımda <strong>Son adım</strong> etiketi.</td></tr>
<tr><td><strong>Üretim emrinin reçetesi</strong></td><td>Tüketilecek malzemeler, yan ürünler ve bu üretimde tüketilecek miktarlar (4. bölüm).</td></tr>
<tr><td>Seçili adım kartı</td><td>Adımın durumu ya da son adımda <strong>Çıktı kaydı</strong>; altta tek büyük ana düğme: <strong>Başlat</strong>, <strong>Operasyonu bitir</strong> veya <strong>Bitir ve kaydet</strong>.</td></tr>
<tr><td><strong>Kayıtlar</strong></td><td>Bu emir için gönderilen kayıtlar ve nakil durumları (2.6).</td></tr>
</tbody></table></section>

<section id="detayli"><h3>1.4 Detaylı ekran ve yönetici panosu</h3>
<p>Operatör ekranının sağ üstündeki <strong>Detaylı ekran →</strong> bağlantısı, soldan menülü <strong>Detaylı üretim paneli</strong>ni açar. Depodan malzeme talebi (3. bölüm) bu panelden yapılır. Menüde şu sayfalar bulunur: <strong>Reçeteler</strong>, <strong>İşlerim</strong>, <strong>Üretim akışı</strong>, <strong>Üretim emirleri</strong>, <strong>Depo talepleri</strong>, <strong>Lot izlenebilirliği</strong>; yetkili rollerde ayrıca <strong>Üretim planı</strong> ve <strong>Yönetim paneli</strong>. Operatör ekranına üstteki <strong>← Operatör ekranı</strong> düğmesiyle dönersiniz.</p>
<p>Vardiya sorumlusu, üretim yöneticisi ve yönetim izleme rollerinde üst çubukta <strong>Operatör / Yönetici</strong> geçişi bulunur. <strong>Yönetici</strong> seçildiğinde Üretim planı açılır; menüdeki <strong>Yönetim paneli</strong> ise yönetici panosunu gösterir: bugünkü üretilen / plan, kuyrukta bekleyen, kontrol gerektiren kayıtlar, geciken emirler, açık depo talepleri, verimlilik, iş merkezleri, üretim günlüğü ve vardiya ekibi.</p>
{fig('15-yonetici-gorunumu.png', 'Detaylı üretim paneli, Yönetici görünümü. Sol menü sayfaları, üstte Ortam, ← Operatör ekranı, Operatör / Yönetici geçişi ve veri yenileme düğmesi.')}
<div class="note">Sağ altta görülen <strong>Saha asistanı</strong>, ekrandaki üretim verisi hakkında soru sormanızı sağlar; kayıt yapmaz.</div></section>

<section id="hesap"><h3>1.5 Kullanıcı değiştirme ve çıkış</h3>
<p>Tablet vardiyada birden fazla kişi tarafından kullanılıyorsa her çalışan kendi hesabıyla çalışmalıdır; kayıtlar giriş yapan kişinin adına yazılır.</p>
<ol class="steps">
<li>Üst çubukta adınızın yanındaki <strong>Hesap</strong>’a dokunun (detaylı ekranda sol altta <strong>⎋ Kullanıcı değiştir · Çıkış</strong>).</li>
<li>Vardiya devrinde <strong>Kullanıcı değiştir</strong> (“Bu tablette başka bir çalışanla devam et”): Microsoft hesap seçimi açılır, yeni çalışan kendi hesabıyla girer.</li>
<li>İş bitince <strong>Çıkış yap</strong> (“Oturumu kapat, ekranı kilitle”). “Çıkış yapıldı” sayfası açılır; sonraki çalışan <strong>Giriş yap</strong> ile girer.</li>
</ol>
{fig('16-hesap.png', 'Hesap sayfası: Kullanıcı değiştir, Çıkış yap ve ← Ekrana dön. Gerçek kullanımda burada adınız ve e-postanız yazar.', 480)}
<div class="warn">Başkasının oturumunda kayıt yapmayın. Çıkışta tabletteki önbellek temizlenir; bir sonraki kişi önceki kullanıcının ekranını görmez.</div></section>

<section id="kurulum"><h3>1.6 Yönetici için: BC’de kullanıcı tanımlama</h3>
<p>Bu adımlar BC güvenlik yöneticisi tarafından, kişisel yönetici hesabıyla bir kez yapılır. Operatörün yapması gereken bir şey yoktur.</p>
<ol class="steps">
<li>Kullanıcıya Kitoko Entra’da <strong>DynamicsOps ShopFloor Login - Element4</strong> uygulamasının rollerinden birini atayın (ShopFloor Operator / Manager / Executive).</li>
<li>Kullanıcının BC’de etkin bir kullanıcı olduğundan ve giriş e-postasının dolu olduğundan emin olun.</li>
<li>BC’de arama (<kbd>Alt</kbd>+<kbd>Q</kbd>) ile <strong>ShopFloor Kullanıcı Ekle</strong> sayfasını açın (ayrıca <em>DynOps Production Workers</em> listesindeki <strong>Kolay Kullanıcı Ekle</strong> eylemiyle de açılır).</li>
<li><strong>Business Central kullanıcısı</strong> alanından kişiyi seçin; <strong>Adı</strong> ve <strong>Giriş e-postası</strong> kendiliğinden dolar. <strong>Çalışan kodu (boşsa otomatik)</strong> alanını isterseniz doldurun.</li>
<li><strong>Görevi</strong> alanında <em>Operatör</em>, <em>Vardiya sorumlusu</em>, <em>Üretim yöneticisi / planlama</em> veya <em>Yönetim izleme</em> seçin ve <strong>Tamam</strong>’a basın. “Kullanıcı bu şirket için etkinleştirildi.” mesajı çıkar.</li>
</ol>
<p>Şirketin ilk kurulumu <strong>ShopFloor Hızlı Kurulum</strong> sayfasında yapılır (Şirket, <strong>Üretim deposu</strong>, <strong>Web uygulamasının Entra istemci kimliği</strong>, <strong>Tablet üretim ve reçete düzenlemeyi aç</strong>). Tamamlanınca “BC şirket kurulumu tamamlandı. Çalışanları ShopFloor Kullanıcı Ekle ekranından ekleyebilirsiniz.” mesajı görünür.</p>
{BACK}</section></section>

<section id="emir"><h2>2. Üretim emrini başlatma ve bitirme</h2>
<p>Tablette bir üretim emri, rotasındaki operasyonlar (adımlar) sırayla yürütülerek tamamlanır. Her adımda temel döngü aynıdır: <strong>emri seçin → adımı seçin → Başlat → işi yapın → bitirin</strong>. <strong>Başlat</strong> yalnız süreyi başlatır; tüketim, çıktı ve süre bilgileri adımı bitirdiğinizde birlikte BC’ye gider. Mamul (bitmiş ürün) çıktısı ve fire yalnız <strong>son adımda</strong> girilir.</p>
<section id="emir-sec"><h3>2.1 Emri seçme</h3>
<ol class="steps">
<li><strong>Barkodla:</strong> Sol alttaki <strong>Emir okut</strong>’a dokunun. Ekranın üstünde “İş emrini okutun” alanı açılır. İş kağıdındaki emir barkodunu okutun ya da emir numarasını yazıp <strong>Emri aç</strong>’a dokunun. Alan, emir numarasını ve madde numarasını tanır.</li>
<li><strong>Listeden:</strong> Soldaki <strong>Çalışma listesi</strong>nde emrin satırına dokunun. Aramak için <strong>Emir veya ürün ara</strong> kutusuna emir no, madde no veya ürün adının bir kısmını yazın. Tamamlanmış emirleri de görmek için <strong>Tümü</strong> sekmesine geçin.</li>
<li>Emir açılınca yeşil şeritte “… iş emri açıldı.” yazar ve emir başlığı, rota ve reçete gelir. Size ait çalışan bir adım varsa uygulama girişte o emri kendiliğinden açar.</li>
</ol>
{fig('02-emir-okut.png', 'Emir okut: “İş emrini okutun” alanı, Emri aç ve Listeden seç düğmeleri.')}
<div class="note">“Barkodla eşleşen açık iş emri bulunamadı.” mesajı, okutulan değerin listedeki bir emirle eşleşmediğini gösterir. Emrin BC’de <em>serbest bırakılmış</em> (Released) olduğunu ve doğru ortamda olduğunuzu kontrol edin.</div></section>

<section id="adim"><h3>2.2 Rota ve adım seçimi</h3>
<p>Rota şeridinde emrin adımları soldan sağa sıralanır. Uygulama sizin çalışan adımınızı, yoksa sıradaki açık adımı seçili getirir; başka bir adımla çalışacaksanız şeritte o adıma dokunun. Seçili adım mavi zeminle gösterilir.</p>
{fig('03-rota.png', 'Rota şeridi: tamamlanan adımlar ✓ “Bitti”, seçili adım 30, son adım 40 “Son adım” etiketiyle.')}
<p>Emirde hiç operasyon yoksa seçili adım kartı yerine “Rota gerekli · Bu emirde başlatılabilecek bir operasyon tanımlanmamış.” yazar; bu durumda planlamaya haber verin.</p></section>

<section id="baslat"><h3>2.3 Başlat</h3>
<ol class="steps">
<li>Doğru emri ve adımı seçtiğinizi kontrol edin. Seçili adım kartında adımın durumu (ör. <strong>Hazır</strong>) ve “Başlat ile süre tutulmaya başlar.” yazar.</li>
<li>İsterseniz önce reçetedeki tüketim miktarlarını ve lotları düzenleyin (4. bölüm). Ekranda bu not yer alır: “Miktarları ve lotları Başlat’tan önce düzenleyebilirsiniz. Başlat süreyi başlatır; stok hareketleri Bitir’de birlikte kaydedilir.”</li>
<li>Yeşil <strong>Başlat</strong> düğmesine dokunun. Düğmenin altında hangi adımı başlattığınız yazar (ör. “Op 30 · Nihai montaj ve test”).</li>
<li>Yeşil şeritte “Op 30 başladı.” mesajı çıkar. Rota şeridinde adım “▶ Çalışıyor · N dk” ve “Başladı SS:DD · Adınız” olarak görünür; kartta geçen dakika sayılır.</li>
</ol>
{fig('04-baslat.png', 'Başlatılmaya hazır ara adım: durum “Hazır”, ana düğme Başlat.', 720)}
<p>Başlat düğmesi gri ve pasifse altındaki açıklama nedenini söyler:</p>
<table><thead><tr><th>Düğmenin altında yazan</th><th>Anlamı ve yapılacak</th></tr></thead><tbody>
<tr><td>“Önce UEM-… · Op … adımını bitirin”</td><td>Aynı anda yalnız bir adım çalıştırabilirsiniz. Önce açık olan adımınızı bitirin.</td></tr>
<tr><td>“<em>Ad Soyad</em> çalışıyor”</td><td>Adımı başka bir çalışan başlatmış. Gerekirse onunla konuşun; takılı kaldıysa sorumlu <strong>Kilidi kaldır</strong> kullanır (2.7).</td></tr>
<tr><td>“Bu adım tamamlandı”</td><td>Adım bitmiş; şeritte sıradaki adımı seçin.</td></tr>
<tr><td>“Başka iş merkezi · …”</td><td>Çalışan kaydınız bu iş merkezine yetkili değil; sorumlunuza bildirin.</td></tr>
<tr><td>“Bu adım başlatılamaz”</td><td>Adım şu an başlatılabilir durumda değil (ör. bekliyor). Ekranı yenileyin; sürerse sorumluya bildirin.</td></tr>
</tbody></table>
<div class="note">Bağlantı doğrulanmadan (üst çubukta <strong>Bağlı</strong> görünmeden) ana düğmeler çalışmaz. Bu, aynı işin iki kez gönderilmesini önler.</div></section>

<section id="ara-bitir"><h3>2.4 Ara adımı bitirme</h3>
<p>Son adım olmayan her adım <strong>ara adım</strong>dır. Ara adımda mamul miktarı girilmez; adımın süresi ve (varsa) o adımda tüketilen malzemeler gönderilir. Kartta “Ara adım: süre BC’ye Bitir ile gider. Mamul son adımda kaydedilir.” yazar.</p>
<ol class="steps">
<li>İş bitince seçili adım kartındaki malzeme satırını kontrol edin. “Bu adımda tüketilecek malzeme yok”, “N malzeme · miktar girilmedi” veya “N malzeme girildi” yazar; düzenlemek için satıra dokunun (4.2).</li>
<li>Mavi <strong>Operasyonu bitir</strong> düğmesine dokunun. Düğmenin altında süre ve girilen malzeme sayısı görünür (ör. “42 dk · 1 malzeme”).</li>
<li>Kayıt BC üretim günlüğüne gönderilir. Nakil hemen tamamlanırsa “Üretim kaydedildi. Tüketimler, yan ürünler ve mamul stokları güncellendi.”, kuyrukta kalırsa “Op … bitti; süre kuyruğa alındı.” mesajı çıkar.</li>
<li>Rota şeridinde sıradaki adımı seçip aynı şekilde <strong>Başlat</strong> ile devam edin.</li>
</ol>
{fig('05-ara-adim-bitir.png', 'Çalışan ara adım: geçen süre ve Operasyonu bitir düğmesi.', 720)}</section>

<section id="son-adim"><h3>2.5 Son adım: Bitir ve kaydet</h3>
<p>Rotadaki son adım (şeritte <strong>Son adım</strong> etiketli) mamulün stoğa girdiği adımdır. Son adım seçildiğinde kartın başlığı <strong>Çıktı kaydı</strong> olur ve üretim alanları görünür; ancak ana düğme önce <strong>Başlat</strong>’tır. Son adımı da <strong>Başlat</strong> ile başlatın; ana düğme ancak oturum sizdeyken <strong>Bitir ve kaydet</strong>’e döner.</p>
<ol class="steps">
<li><strong>Üretilen</strong> alanına bu seferde ürettiğiniz sağlam miktarı girin (− / + düğmeleri veya klavye). Uygulama kalan miktarı önerir; sağ üstte “Kayıt sonrası kalan N …” yazar.</li>
<li>Hurdaya ayrılan miktar varsa <strong>Fire</strong> alanına girin. Fire yoksa 0 bırakın.</li>
<li>Ürün lot takipliyse <strong>Lot</strong> alanı açılır (“Okutmaya hazır”). Lot etiketini okutun, elle yazın ya da <strong>Otomatik ata</strong> ile BC’deki madde lot serisinden numara alın (4.4).</li>
<li>Bu adımda tüketilen malzemeleri ve yan ürünleri kontrol edin (4. bölüm). Üretilen miktarı değiştirdiğinizde, tüketimleri elle değiştirmediyseniz tüketimler reçeteye göre yeniden hesaplanır.</li>
<li>Mavi <strong>Bitir ve kaydet</strong> düğmesine dokunun. Düğmenin altında gönderilecekler özetlenir (ör. “4 ADET · fire 1 · yan ürün 0,32 KG”).</li>
<li>Kayıt fişi açılır. Fişte <strong>DURUM</strong>, <strong>KAYIT</strong> (kayıt no ve nakil tarihi), <strong>ÜRETİLEN</strong>, varsa <strong>FİRE</strong>, <strong>TÜKETİM</strong> (satır sayısı) ve <strong>SAAT</strong> yazar. Başlık “Deftere nakledildi.” ise stok hareketleri oluşmuştur; “Kuyruğa alındı.” ise kayıt alınmıştır ve nakli sistem yapacaktır. <strong>Yeni giriş</strong> ile fişi kapatın.</li>
</ol>
{fig('06-son-adim-cikti.png', 'Son adımda Çıktı kaydı: Üretilen, Fire, Lot (Otomatik ata) ve Bitir ve kaydet.', 720)}
{fig('08-kayit-fisi.png', 'Kayıt fişi “GÜNLÜĞE KAYDEDİLDİ”. Örnek veride durum “Sırada”; canlıda nakil çoğunlukla hemen tamamlanır ve “Deftere nakledildi.” yazar.')}
<div class="info"><strong>Kısmi üretim:</strong> Emrin tamamını tek seferde bitirmek zorunda değilsiniz. Ürettiğiniz kadarını kaydedin; emir kalan miktarla listede kalır. Girebileceğiniz en fazla miktar, plan eksi üretilen eksi henüz nakledilmemiş kayıtlardır. Fazlası girilirse “Girilebilecek en fazla miktar N …” uyarısı çıkar.</div>
<div class="note">Emrin kalan miktarı daha önceki kayıtlarla kapandıysa son adımın ana düğmesi <strong>Operasyonu bitir</strong> olur; adım üretim girmeden yalnız süreyle kapatılır (“Op … kapatıldı; süre kuyruğa alındı.”). Ana ürün bittiği halde girilecek yan ürün kaldıysa düğme <strong>Yan ürünleri kaydet</strong> olur (“Ana ürün tekrar üretilmez”).</div>
<div class="warn">Bitir ve kaydet’e bastıktan sonra yanıt gecikirse sayfayı kapatmayın ve yeni bir kayıt girmeyin. Uygulama aynı kaydı aynı işlem kimliğiyle saklar; tekrar basmanız güvenlidir ve BC kaydı ikinci kez almaz. Daha önce alınmış bir kayıt tekrar gönderilirse fişte “ZATEN GÖNDERİLMİŞ” ve “Bu kayıt zaten gönderilmişti (#…). Yeni kayıt oluşturulmadı.” yazar.</div></section>

<section id="kayitlar"><h3>2.6 Kayıtlar ve nakil durumu</h3>
<p>Seçili adım kartının altındaki <strong>Kayıtlar</strong> bölümüne dokunarak bu emir için gönderilen kayıtları açarsınız. Başlıkta bugünün özeti yer alır: “Bugün N nakledildi · N kuyrukta · N kontrol gerekli”. Kontrol gerektiren kayıtlar her zaman en üstte gösterilir.</p>
{fig('10-kayitlar.png', 'Kayıtlar: Sırada (BC’de naklet düğmesiyle), Nakil sürüyor ve Nakledildi satırları.', 760)}
<table><thead><tr><th>Durum</th><th>Anlamı</th><th>Ne yaparsınız?</th></tr></thead><tbody>
<tr><td><strong>Sırada</strong></td><td>Kayıt BC’ye ulaştı, nakil bekliyor.</td><td>Beklemeniz yeterlidir; arka plan işlemi naklettirir. Hemen işlenmesi gerekiyorsa kendi kaydınızda <strong>BC’de naklet</strong>’e dokunun.</td></tr>
<tr><td><strong>Nakil sürüyor</strong></td><td>BC kaydı şu anda deftere naklediyor.</td><td>Bekleyin; ekran kendiliğinden yenilenir.</td></tr>
<tr><td><strong>Nakledildi</strong></td><td>Stok ve kapasite kayıtları oluştu; satırda nakleden ve saat yazar.</td><td>Bir şey yapmanız gerekmez.</td></tr>
<tr><td><strong>Kontrol gerekli</strong></td><td>Nakil BC’de bir hatayla durdu; hata metni satırda kırmızı yazar.</td><td>Hatayı okuyun. Sebep giderildiyse <strong>Nakli tekrar dene</strong>; anlaşılmıyorsa vardiya sorumlusuna bildirin.</td></tr>
<tr><td><strong>İptal</strong></td><td>Kayıt iptal edildi.</td><td>—</td></tr>
</tbody></table>
<p>Satırlarda kaydın türü de yazar: miktarlı kayıtlar “N ADET”, ara adım kapanışları “Süre bildirimi · N dk”, yalnız malzeme içerenler “Tüketim bildirimi”. Beşten fazla kayıt varsa <strong>N kaydı daha göster</strong> ile tamamını açın. Operatör ekranında <strong>BC’de naklet</strong> ve <strong>Nakli tekrar dene</strong> yalnız sizin gönderdiğiniz kayıtlarda görünür; diğer kayıtlarda kayıt numarası (#…) yazar.</p></section>

<section id="kilit"><h3>2.7 Takılı oturum: Kilidi kaldır</h3>
<p>Bir çalışan adımı başlatıp bitirmeden ayrılırsa adım onun adına “çalışıyor” olarak kalır ve başkası başlatamaz. Vardiya sorumlusu ve yöneticiler bu durumda adımı seçtiğinde kartta <strong>Kilidi kaldır</strong> düğmesi görünür (“… oturumunu üretim göndermeden sıfırlar.”).</p>
<ol class="steps">
<li>Önce çalışanla konuşun; işi bitirdiyse kendi hesabıyla adımı bitirmesi en doğrusudur.</li>
<li>Gerekirse <strong>Kilidi kaldır</strong>’a dokunun ve “Op … için açık oturum üretim kaydı oluşturmadan kapatılacak. Kilit kaldırılsın mı?” sorusunu onaylayın.</li>
<li>“Op … oturumu sıfırlandı; kilit kaldırıldı.” mesajından sonra adım yeniden başlatılabilir.</li>
</ol>
{fig('11-kilidi-kaldir.png', 'Başka çalışanın açık oturumu: Kilidi kaldır düğmesi yalnız yetkili rollerde görünür; Başlat düğmesinde “… çalışıyor” yazar.', 720)}
<div class="warn">Kilidi kaldırmak o oturum için hiçbir üretim, tüketim veya süre kaydı oluşturmaz. Yapılmış iş varsa ayrıca kaydedilmelidir.</div>
{BACK}</section></section>

<section id="talep"><h2>3. Depodan malzeme talebi</h2>
<p>Üretim için gereken malzeme hatta yoksa depodan isteyebilirsiniz. Talep Business Central’da kalıcı bir <strong>üretim malzeme talebi</strong> olarak açılır; depo ekibi standart BC depo akışıyla (stok çekme, ambar çekme veya stok hareketi belgesi) malzemeyi hazırlar ve belge talebe bağlanır. Talep tabletten <strong>Detaylı ekran</strong>da yapılır.</p>
<section id="talep-ac"><h3>3.1 Talep oluşturma</h3>
<ol class="steps">
<li>Operatör ekranında malzeme isteyeceğiniz emri seçin, sonra sağ üstteki <strong>Detaylı ekran →</strong>’a dokunun.</li>
<li>Sol menüden <strong>Üretim emirleri</strong>’ni açın, listede emrin seçili olduğunu kontrol edin ve emir ayrıntısındaki <strong>Depodan iste</strong> düğmesine dokunun. Aynı pencere <strong>Depo talepleri</strong> sayfasındaki <strong>＋ Yeni depo talebi</strong> ile de açılır (seçili emir için).</li>
<li><strong>Depodan malzeme iste</strong> penceresinin üstünde <strong>KAYNAK DEPO → TESLİM NOKTASI</strong> özeti görünür: malzemenin çıkacağı depo ve teslim edilecek iş merkezi ile raf.</li>
<li><strong>Kaynak depo</strong> listesinden depoyu seçin. Malzemeleri birden fazla depodan gelen emirlerde her depo için ayrı talep açılır.</li>
<li><strong>Eksik reçete kalemleri</strong> listesini kontrol edin. Seçili depodaki, elle tüketilen ve kalan miktarı olan reçete satırları emrin kalan miktarıyla listelenir; altında uygun lot sayısı ve önerilen (FEFO) lot yazar. Miktar bu pencerede değiştirilmez.</li>
<li><strong>Öncelik</strong> seçin: <em>Normal</em>, <em>Yüksek</em> (varsayılan) veya <em>Kritik</em>.</li>
<li>Gerekirse <strong>Depoya not</strong> yazın (en çok 250 karakter; ör. “Rulman lotu öncelikli, 30 dakika içinde gerekli”).</li>
<li><strong>Malzeme talebi oluştur</strong>’a dokunun. “… malzeme talebi depoya gönderildi.” mesajı çıkar.</li>
</ol>
{fig('13-depodan-malzeme-iste.png', 'Depodan malzeme iste penceresi: KAYNAK DEPO → TESLİM NOKTASI, Kaynak depo, Eksik reçete kalemleri, Öncelik ve Depoya not.')}
<div class="note"><strong>Depodan iste</strong> düğmesi pasifse altında nedeni yazar; çoğunlukla “Açık malzeme yok”: emrin istenecek kalan malzemesi kalmamıştır. Otomatik (flushing) tüketilen malzemeler talep listesine girmez.</div></section>
<section id="talep-izle"><h3>3.2 Talebi izleme</h3>
<p>Sol menüdeki <strong>Depo talepleri</strong> sayfası talepleri üç sütunda gösterir: <strong>Açık</strong>, <strong>Hazırlanıyor</strong>, <strong>Tamamlandı</strong>; üstte her durumun sayısı yer alır. Menüdeki sayı açık taleplerin adedidir.</p>
{fig('12-depo-talepleri.png', 'Depo talepleri: Açık / Hazırlanıyor / Tamamlandı sütunları, Bu istasyon / Tümü filtresi ve ＋ Yeni depo talebi.')}
<ul>
<li>Her kartta talep no, öncelik (Yüksek / Kritik), ne kadar önce açıldığı, ilgili emir (dokununca emri açar), satır sayısı, depo belgesi oluştuysa türü ve numarası (ör. “Stok çekme …”) ve not yazar.</li>
<li>Üretim emri BC’de serbest bırakıldığında BC tarafından kendiliğinden açılan talepler “BC otomatik” ibaresi taşır (BC kurulumunda bu seçenek açıksa).</li>
<li>Depo tarafında bir sorun varsa kartta “Depo: …” satırı görünür; depo ekibine bildirin.</li>
<li><strong>Bileşen ve lotları göster</strong>, emrin güncel kalan miktarını ve kullanılabilir lotları açar.</li>
<li>Çalışan kaydınızda iş merkezi varsa <strong>Bu istasyon</strong> ile yalnız kendi iş merkezinizin taleplerini görürsünüz. İptal edilen talepler en altta <strong>İptal edilenler (N) ▸</strong> altında listelenir.</li>
</ul>
<p>Aynı bilgi emir ayrıntısındaki <strong>Depo talepleri</strong> bölümünde de görünür (ör. “Hazırlanıyor · 3 satır · HAMMADDE → MONTAJ-01 · Depo belgesi bekleniyor”). Talep, malzemeyi tüketmez: malzeme hatta gelince tüketimi 4. bölümdeki gibi bildirirsiniz.</p>
{BACK}</section></section>

<section id="tuketim"><h2>4. Tüketim ve çıktı bildirimi</h2>
<p>Tüketim (üretimde kullanılan malzeme) ve çıktı (üretilen ürün) adım bitirilirken birlikte gönderilir. Business Central’da iki tür malzeme vardır: <strong>elle tüketilen</strong> (Manual, Pick + Manual) malzemelerin miktarını siz girersiniz; <strong>otomatik tüketilen</strong> (Forward / Backward flushing) malzemeleri BC nakil sırasında kendisi düşer. Ekranda otomatik malzemelerde “BC otomatik tüketir” yazar ve miktar kutusu yoktur.</p>
<section id="recete"><h3>4.1 Reçete tablosu</h3>
<p>Operatör ekranındaki <strong>Üretim emrinin reçetesi · Tüketilecek malzemeler</strong> tablosu emrin bütün malzemelerini gösterir. Sağ üstte “Eksik malzeme yok” ya da “N malzemede eksik” yazar.</p>
{fig('09-recete-tuketim.png', 'Reçete tablosu: her satırda malzeme, bağlı adım (Op …), depo / raf, uygun lotlar, Plan / Tüketilen / Kalan / Stok ve “Bu üretimde tüketilecek” miktarı; altta stoğa girecek yan ürünler.')}
<ul>
<li><strong>Plan / Tüketilen / Kalan / Stok:</strong> reçetedeki toplam ihtiyaç, nakledilmiş tüketim, kalan ihtiyaç ve kullanılabilir stok. Kuyrukta bekleyen tüketim “… sırada” olarak yazar; stok yetmiyorsa “… eksik” kırmızı görünür.</li>
<li><strong>Op …</strong> etiketi malzemenin hangi adımda tüketileceğini gösterir; seçili adımın malzemeleri vurgulanır. Rotaya bağlanmamış malzemeler son adımda tüketilir.</li>
<li><strong>Bu üretimde tüketilecek:</strong> uygulama, girdiğiniz üretim + fire miktarına göre reçeteden miktar önerir (“… stoktan düşer”). Gerçekte kullandığınız miktar farklıysa düzeltin.</li>
</ul></section>
<section id="malzeme"><h3>4.2 Malzeme çekmecesi</h3>
<p>Seçili adımın tüketimini tek yerde girmek için sol alttaki <strong>Malzeme</strong>’ye, seçili adım kartındaki malzeme satırına ya da reçetenin altındaki <strong>Seçili adımın tüketimi →</strong>’ye dokunun. Sağdan <strong>Malzemeler · Op …</strong> çekmecesi açılır (“Kullandığınız miktarı girin. Malzemeler Bitir ile BC’ye gider.”).</p>
<ol class="steps">
<li>Her malzemede sağ üstte <strong>Gereken</strong> miktar yazar. Kullandığınız miktarı − / + düğmeleriyle veya klavyeyle girin.</li>
<li>Miktarları reçete önerisine döndürmek için üstteki <strong>↻ Reçeteye göre doldur</strong>’a dokunun (“Tüketimler reçeteye göre dolduruldu.”).</li>
<li>Lot takipli malzemede lotu seçin (4.3). Satırın altında stok ve uygun lot sayısı yazar; miktar kalanı veya stoğu aşarsa satır kırmızı olur.</li>
<li><strong>Tamam</strong> ile çekmeceyi kapatın. Tüketimler, adımı <strong>Operasyonu bitir</strong> veya <strong>Bitir ve kaydet</strong> ile bitirdiğinizde gönderilir.</li>
</ol>
{fig('07-malzeme-cekmecesi.png', 'Malzemeler · Op 20 çekmecesi: ↻ Reçeteye göre doldur, Gereken miktar, − / + ile tüketilen miktar ve tüketim lotu seçimi.')}
<p>Seçili adımda elle tüketilecek malzeme yoksa çekmecede “Bu adımda elle tüketilecek malzeme yok.” yazar.</p></section>
<section id="lot"><h3>4.3 Tüketim lotu</h3>
<p>Lot takipli malzemelerde tüketim lotu, reçete tablosundaki <strong>Tüketim lotu</strong> listesinden veya çekmecedeki lot listesinden seçilir. Listede her lot kullanılabilir miktarıyla yer alır (ör. “RL-250912-A · 30 ADET”). Lot seçmezseniz <strong>Otomatik lot dağıtımı</strong> geçerlidir: miktar uygun lotlara dağıtılır. Seçtiğiniz lotun stoğu girdiğiniz miktara yetmiyorsa “… lot stokunu aşıyor.” uyarısı çıkar.</p>
<p>Malzemenin bu depoda kullanılabilir lotu yoksa satırda “Kullanılabilir lot yok.” açıklaması belirir. Stok başka bir depoda veya varyantta görünüyorsa yetkili kullanıcılar <strong>Bu stoğu kullan</strong> ile reçete satırını o depoya / varyanta çevirebilir; yetkiniz yoksa “Depo/varyantı değiştirmek için planlama yetkisi gerekir; sorumluya haber verin.” yazar. Hiçbir yerde stok yoksa önce stok girişi yapılmalıdır.</p></section>
<section id="cikti"><h3>4.4 Çıktı, fire ve üretim lotu</h3>
<p>Mamul çıktısı ve fire yalnız son adımın <strong>Çıktı kaydı</strong> kartında girilir (2.5). Ara adımda bu alanlar görünmez; ekran “Mamul çıktısı yalnız son operasyonda (SON) gönderilir.” kuralını uygular.</p>
<ul>
<li><strong>Üretilen:</strong> sağlam ürün miktarı. Emrin kalan miktarını (kuyrukta bekleyen kayıtlar düşüldükten sonra) aşamaz.</li>
<li><strong>Fire:</strong> hurdaya ayrılan miktar; sıfır veya daha büyük olmalıdır.</li>
<li><strong>Lot:</strong> ürün lot takipliyse zorunludur (“Üretilen ürün için lot numarası girin.”). <strong>Otomatik ata</strong>, maddenin BC kartındaki <strong>Lot Nos.</strong> serisinden bir numara ayırır. Numara yalnız ayrılır; stok hareketi kaydı Bitir ve kaydet ile oluşur. Yanıt alınamazsa (“Lot atama yanıtı alınamadı. Aynı numarayı almak için tekrar deneyin.”) tekrar basmanız aynı numarayı getirir. Ayrılan numara, kaydı göndermeseniz de seriye geri dönmez.</li>
</ul></section>
<section id="yan-urun"><h3>4.5 Yan ürünler</h3>
<p>Reçetede yan ürün (ör. hurda, artık malzeme) tanımlıysa reçete tablosunun altında <strong>Stoğa girecek yan ürünler</strong> bölümü görünür. Her yan üründe <strong>Plan</strong> ve <strong>Çıkan</strong> miktar ile <strong>Bu üretimde çıkacak</strong> kutusu vardır (“… stoğa eklenir · depo”). Gerçek miktarı girin; yan ürün lot takipliyse lotunu yazın veya <strong>Otomatik ata</strong> kullanın. Yan ürünler adımı bitirdiğinizde stoğa giriş olarak kaydedilir; ana düğmenin özetinde “yan ürün …” olarak görünür.</p></section>
<section id="detay-bildirim"><h3>4.6 Detaylı ekrandan bildirim</h3>
<p>Aynı işler detaylı ekrandaki <strong>Üretim emirleri</strong> sayfasından da yapılabilir. Emir ayrıntısında <strong>■ Bitir</strong> / <strong>▶ Başlat</strong>, <strong>Üretim bildir</strong>, <strong>Malzeme tüket</strong>, <strong>Depodan iste</strong> ve <strong>Ek malzeme</strong> düğmeleri bulunur.</p>
{fig('14-detayli-emirler.png', 'Detaylı ekran → Üretim emirleri: solda emir listesi ve filtreler, sağda seçili emrin ayrıntısı.')}
<ul>
<li><strong>Malzeme tüket</strong> (veya reçete satırındaki <strong>Tüket →</strong>): malzeme için <strong>Tüketilecek miktar</strong> girilir, lot listeden seçilir (önerilen lot “Önerilen” işaretlidir) ya da <strong>Manuel lot / barkod</strong> alanına okutulur; <strong>Tüketimi deftere nakle gönder</strong> ile tüketim ayrı bir kayıt olarak gönderilir.</li>
<li><strong>Üretim bildir</strong>: yalnız son operasyonda kullanılabilir (aksi halde “Son operasyonda bildirilir (Op …)” yazar). Üretilecek miktar, fire ve lot girilip <strong>Üretimi ve yan ürünleri deftere nakle gönder</strong> ile gönderilir.</li>
<li><strong>■ Bitir</strong> / <strong>▶ Başlat</strong>: operasyonu başlatma ve bitirme penceresini açar. Başlatırken malzeme stoğu da kontrol edilir; stok eksikse düğmede “Stok eksik — başlatılamaz” yazar.</li>
<li><strong>Ek malzeme</strong>: reçetede olmayan ama üretimde gerçekten kullanılan bir malzemeyi emre ekler.</li>
</ul>
<div class="note">Günlük işte operatör ekranını kullanmanız önerilir: adım, tüketim ve çıktı tek düğmeyle birlikte gönderilir ve tutarlı kalır.</div>
{BACK}</section></section>

<section id="durus"><h2>5. Duruş kaydı</h2>
<div class="warn"><strong>Bu sürümde (ShopFloor {VERSION}) tablet ekranında ayrı bir duruş kaydı yoktur.</strong> Operatör ekranında veya detaylı ekranda “duruş başlat / bitir” ya da duruş nedeni seçme düğmesi bulunmaz. Business Central uzantısında duruş nedeni ve duruş kaydı altyapısı (kapasite kaydına <em>Stop Time</em> ve <em>Stop Code</em> yazan nakil) hazırdır, ancak tablet ekranına henüz bağlanmamıştır.</div>
<p>Bu nedenle bir makine veya hat durduğunda şu kurallara uyun:</p>
<ol class="steps">
<li><strong>Duruşu hemen vardiya sorumlunuza bildirin:</strong> hangi emir ve adımda, saat kaçta başladığını, nedenini (arıza, malzeme bekleme, ayar vb.) ve ne kadar sürdüğünü söyleyin.</li>
<li><strong>Tabletteki süre duruşu ayırmaz.</strong> Başlattığınız adımın sayacı duruş sırasında da işlemeye devam eder ve adımı bitirdiğinizde bu süre BC’ye çalışma süresi olarak gider. Sorumlunuz duruşu ayrıca kaydedeceği için duruş süresini not edin.</li>
<li>Duruş yüzünden adımı bitirmeniz veya başka bir adıma geçmeniz gerekip gerekmediğine sorumlunuz karar verir; kendi başınıza boş kayıt göndermeyin ve başkasının oturumunu sıfırlamaya çalışmayın.</li>
</ol>
<p><strong>Sorumlu ve yöneticiler için:</strong> Duruş süreleri Business Central’da standart yolla, üretim emrinin ilgili operasyonu için çıktı günlüğünde (Output Journal) <strong>Stop Time</strong> ve <strong>Stop Code</strong> alanlarıyla kaydedilebilir. BC’de nakledilmiş duruş süreleri, tablet uygulamasındaki <strong>Yönetim paneli</strong>nin <strong>Verimlilik</strong> oranlarına (iş merkezi ve vardiya bazında) yansır. Yönetim panelindeki “DURUŞTA” göstergesi bu sürümde canlı BC verisinden beslenmez; kılavuzdaki örnek ekranda görülen “Duruş” durumu test verisine aittir.</p>
{BACK}</section>

<section id="sorun"><h2>6. Sık mesajlar ve sorun giderme</h2>
<table><thead><tr><th>Ekranda gördüğünüz</th><th>Anlamı ve yapılacak</th></tr></thead><tbody>
<tr><td>“Bu kullanıcıya Shop Floor uygulama rolü atanmamış.”</td><td>Entra’da ShopFloor rolünüz yok. Yöneticiniz rol atamalı (1.6).</td></tr>
<tr><td>“Oturum açan kullanıcı Business Central çalışan kaydıyla eşleşmiyor.”</td><td>BC’de çalışan kaydınız yok veya e-postası farklı. Yönetici <strong>ShopFloor Kullanıcı Ekle</strong> ile tanımlamalı.</td></tr>
<tr><td>“Bu kullanıcı üretim bildirimi gönderemez.” / “Bu çalışan rolü üretim bildirimi gönderemez.”</td><td>Göreviniz “Yönetim izleme” (salt okunur). Kayıt yapmanız gerekiyorsa görevinizin değiştirilmesini isteyin.</td></tr>
<tr><td>Üst çubukta <strong>ÇEVRİMDIŞI</strong>; “Cihaz çevrimdışı. Girdiğiniz değerler korunuyor; bağlantı gelince ekran otomatik yenilenecek.”</td><td>Tablet Wi-Fi’sini kontrol edin. Girdiğiniz değerler kaybolmaz; bağlantı gelince ekran yenilenir.</td></tr>
<tr><td><strong>YENİDEN BAĞLANIYOR</strong>; “Bağlantı doğrulanıyor; gönderim bekletildi.” / “İşlem için BC bağlantısını yenileyin.”</td><td>Sarı şeritteki <strong>Yenile</strong>’ye dokunun. Bağlantı doğrulanmadan kayıt gönderilmez; değerleriniz ekranda kalır.</td></tr>
<tr><td>“Sunucuya ulaşılamadı. Bağlantıyı kontrol edip tekrar deneyin.”</td><td>Ağ bağlantısı yok. Bağlantıyı kontrol edip tekrar deneyin.</td></tr>
<tr><td><strong>Yeniden giriş yap</strong> bağlantısı görünüyor</td><td>Oturum süreniz doldu. Bağlantıya dokunup Microsoft hesabınızla yeniden girin.</td></tr>
<tr><td>“BC yanıtı gecikti. Aynı işlem kimliği korundu; güvenle tekrar deneyebilirsiniz.”</td><td>Kayıt BC’ye ulaşmış olabilir. Aynı düğmeye tekrar basmanız güvenlidir; BC aynı kaydı ikinci kez almaz.</td></tr>
<tr><td>“Bu kayıt zaten gönderilmişti (#…). Yeni kayıt oluşturulmadı.”</td><td>Bilgi mesajıdır; ilk kayıt geçerlidir. Kayıtlar bölümünden durumunu izleyin.</td></tr>
<tr><td>“Barkodla eşleşen açık iş emri bulunamadı.”</td><td>Okutulan değer açık bir emirle eşleşmiyor. Emir numarasını elle yazın veya listeden seçin; emir serbest bırakılmamış olabilir.</td></tr>
<tr><td>Başlat pasif: “Önce … adımını bitirin”</td><td>Aynı anda tek adım çalıştırabilirsiniz; açık adımınızı bitirin. Sunucu tarafında “Önce mevcut aktif operasyonunuzu bitirin.” olarak da görünebilir.</td></tr>
<tr><td>“Mamul ve fire miktarı yalnız son operasyonda bildirilir. Bu adımda yalnız süre ve malzeme tüketimi gönderilebilir.”</td><td>Ara adımda çıktı girilmez. Çıktıyı son adımda girin.</td></tr>
<tr><td>“Girilebilecek en fazla miktar N …”</td><td>Girdiğiniz miktar kalan miktarı aşıyor (kuyruktaki kayıtlar da düşülür). Miktarı düzeltin.</td></tr>
<tr><td>“Üretilen ürün için lot numarası girin.” / “… zorunludur.”</td><td>Lot etiketini okutun, yazın ya da <strong>Otomatik ata</strong> kullanın.</td></tr>
<tr><td>“… tüketimi kalan miktarı aşıyor.” / “… lot stokunu aşıyor.” / “… stoğu yetersiz.”</td><td>Tüketim miktarını, seçilen lotu ve stoğu kontrol edin; gerekirse depodan malzeme isteyin (3. bölüm).</td></tr>
<tr><td>“Kullanılabilir lot yok.”</td><td>Malzemenin bu depoda lotlu stoğu görünmüyor. Yetkiliyseniz <strong>Bu stoğu kullan</strong>; değilseniz sorumluya haber verin.</td></tr>
<tr><td>“… değişti; ekranı yenileyin.” (operasyon, iş merkezi, reçete satırları, lot miktarı vb.)</td><td>Emir BC’de siz çalışırken değişti. Bağlantı düğmesiyle ekranı yenileyin, değerleri kontrol edip tekrar gönderin.</td></tr>
<tr><td>Kayıtlarda <strong>Kontrol gerekli</strong> ve kırmızı hata metni</td><td>Nakil BC’de durdu. Hatayı okuyun; sebep giderildiyse <strong>Nakli tekrar dene</strong>, değilse vardiya sorumlusuna bildirin. Detaylı ekranda kırmızı “N gönderim kontrol gerekli” şeridi aynı kaydı gösterir.</td></tr>
<tr><td>“Bu kaydı … gönderdi; yalnızca kaydı gönderen kişi ya da vardiya sorumlusu hemen post edebilir.”</td><td>Başkasının kaydını naklettiremezsiniz. Kaydı gönderen kişi veya sorumlu naklettirebilir; aksi halde arka plan işlemi naklettirir.</td></tr>
<tr><td>Başlat düğmesinde “… çalışıyor”, adım uzun süredir açık</td><td>Başka çalışanın oturumu açık kalmış. Vardiya sorumlusu <strong>Kilidi kaldır</strong> kullanabilir (2.7).</td></tr>
<tr><td>“Rota gerekli”</td><td>Emirde operasyon yok. Planlamaya bildirin.</td></tr>
<tr><td>“Etiket yazdırma kapalı.” / <strong>Etiket yazıcısına gönder</strong> pasif</td><td>Bu kurulumda etiket yazdırma kapalıdır; hata değildir.</td></tr>
</tbody></table>
<p>Çözülmeyen durumlarda ekranın görüntüsünü alın; hangi emirde, hangi adımda ve hangi düğmeye bastığınızı da yazarak vardiya sorumlunuza veya destek ekibine iletin. Verileri Business Central’da elle düzeltmeye çalışmayın.</p>
{BACK}</section>
"""


def render_pdf(html_path, pdf_path):
    script = ("import {{ chromium }} from '{pw}';const b=await chromium.launch({{headless:true,channel:'chrome'}});"
              "const p=await b.newPage();await p.goto('{url}');await p.pdf({{path:'{pdf}',format:'A4',printBackground:true,"
              "margin:{{top:'14mm',right:'13mm',bottom:'14mm',left:'13mm'}}}});await b.close();").format(
        pw=(ROOT / 'web/node_modules/@playwright/test/index.mjs').as_uri(), url=html_path.as_uri(), pdf=pdf_path)
    subprocess.run(['node', '--input-type=module', '-e', script], check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    stem = 'KITOKO-Element4-Tablet-Shop-Floor-Kilavuzu'
    path = OUT / f'{stem}.html'
    path.write_text(page('Tablet (Shop Floor) Kullanım Kılavuzu', 'Kitoko / Element 4 · Tablet (Shop Floor)',
                         'Atölyede tabletle üretim emrini başlatmayı ve bitirmeyi, depodan malzeme istemeyi, tüketim ve çıktı '
                         'bildirmeyi ve duruşların nasıl ele alınacağını adım adım anlatır.',
                         TOC, BODY,
                         f'Hazırlayan: DynamicsOps · {DATE} · {PRODUCT} {VERSION} · Azure DevOps #2696. '
                         'Ekranlar uygulamanın yerel test modunda (örnek veri, BC bağlantısı yok) alınmıştır.'),
                    encoding='utf-8')
    render_pdf(path, OUT / f'{stem}.pdf')
    print(path)


if __name__ == '__main__':
    main()
