#!/usr/bin/env python3
"""Business Central Depo ve Stok Kılavuzu — Kitoko / Element 4 (Azure DevOps #2695).

El terminalinde yapılan depo ve stok işlemlerinin Business Central ekranlarındaki
karşılığını anlatır: madde kartı ve stok sorgulama, ambar belgeleri (mal kabul,
yerleştirme, toplama/sevkiyat), transfer ve raf hareketleri, sayım, madde
hareketleri ve stok raporları. 20.10.2026 saha eğitimine destek içindir.

Kurulum bilgileri Sand2010 · Element 4 Dizayn Müh. End. A.Ş. şirketinden yalnız
okuma (GET) ile alındı (27 Ekim 2026): standart API v2.0 ve BCWMS API
(dynops/warehouse/v2.0). Sayfa ve eylem adları BCWMS AL kaynağındaki Caption'lardır.

Stil, page(), BACK ve render_pdf generate-kitoko-guides.py ile aynıdır.
Tek sayfada kayan, içindekiler tıklanabilir HTML üretir; PDF'i Chrome basar.
"""
import html
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/kilavuzlar'
VERSION = '1.14.201-kitoko'
DATE = '27 Ekim 2026'

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


def page(title, eyebrow, lead, toc, body, foot):
    links = ''.join(f'<a class="{"sub" if sub else ""}" href="#{a}">{html.escape(t)}</a>' for a, t, sub in toc)
    return (f'<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)}</title><style>{CSS}</style></head><body><div class="wrap">'
            f'<nav class="toc"><b>İçindekiler</b>{links}</nav><main id="top"><div class="eyebrow">{eyebrow}</div>'
            f'<h1>{html.escape(title)}</h1><p class="meta">{DATE} · BCWMS Kitoko {VERSION}</p><p class="lead">{lead}</p>'
            f'{body}<footer>{foot}</footer></main></div></body></html>')


BACK = '<p class="back"><a href="#top">↑ Başa dön</a></p>'

# Alt+Q kısayolu
AQ = '<kbd>Alt</kbd>+<kbd>Q</kbd>'

TOC = [('amac', 'Bu kılavuz ne anlatır?', False),
       ('kurulum', '1. Element 4 deposu BC’de nasıl kurulu?', False),
       ('alanlar', '1.1 Alanlar ve raflar', True),
       ('stok-durum', '1.2 Bugünkü stok durumu', True),
       ('esleme', '1.3 Terminal ekranı → BC sayfası', True),
       ('gezinme', '1.4 BC’de sayfa bulma (Alt+Q)', True),
       ('madde', '2. Madde kartı ve stok sorgulama', False),
       ('urun-sorgu', '2.1 Ürün Sorgu → Madde Kartı', True),
       ('bin-sorgu', '2.2 Bin Sorgu → Raf İçerikleri', True),
       ('stok-kontrol', '2.3 Stok tutarlılık kontrolü', True),
       ('ambar', '3. Ambar belgeleri', False),
       ('mal-kabul', '3.1 Mal kabul', True),
       ('yerlestirme', '3.2 Yerleştirme', True),
       ('sevkiyat', '3.3 Toplama ve sevkiyat', True),
       ('belge-ozet', '3.4 Belgelerin yaşam döngüsü', True),
       ('transfer', '4. Transfer ve raf hareketleri', False),
       ('adhoc', '4.1 Ad-Hoc Hareket (raftan rafa)', True),
       ('yonlendirilmis', '4.2 Yönlendirilmiş hareket', True),
       ('transfer-emri', '4.3 Transfer Emirleri', True),
       ('sayim', '5. Sayım', False),
       ('sayim-terminal', '5.1 Terminalde sayım → Count Sheets', True),
       ('sayim-isleme', '5.2 Sayımı stoklara işleme', True),
       ('sayim-standart', '5.3 BC’nin standart sayım yolu', True),
       ('ilk-sayim', '5.4 İlk Sayım bu depoda kullanılmaz', True),
       ('hareket', '6. Madde hareketleri ve stok raporları', False),
       ('madde-hareket', '6.1 Madde Hareketleri', True),
       ('ambar-hareket', '6.2 Ambar Hareketleri', True),
       ('lp-sayfalar', '6.3 LP sayfaları', True),
       ('raporlar', '6.4 Stok raporları', True),
       ('gunluk', '6.5 Günlük kontrol listesi', True),
       ('sorun', '7. Sorun giderme ve sık sorular', False)]

BODY = f"""
<section id="amac"><h2>Bu kılavuz ne anlatır?</h2>
<p>Element 4 kafes depodaki sayım tamamlandı ve stoklar Business Central’a (BC) girildi. Bundan sonra depoya giren ve depodan çıkan her ürün <strong>el terminaliyle</strong> kaydedilecek. Terminalde yaptığınız her işlem BC’de bir belge, bir günlük satırı ya da bir hareket kaydı olarak oluşur. Bu kılavuz, terminalde yaptığınız işin BC’de <strong>hangi sayfada görüldüğünü</strong> ve <strong>doğru kaydedildiğini nasıl kontrol edeceğinizi</strong> anlatır.</p>
<p>Kılavuz, 20.10.2026 saha eğitiminde anlatılan terminal adımlarının BC tarafını tamamlar. Terminalde etiket basma ve sayım adımları ayrı “Sayım ve Etiket Kılavuzu”nda anlatılır; burada aynı işlerin BC’deki izini sürersiniz.</p>
<p>Her bölüm aynı sırayla ilerler:</p>
<table><thead><tr><th>Adım</th><th>Ne anlatılır?</th></tr></thead><tbody>
<tr><td><strong>Terminalde ne yapılır?</strong></td><td>Hangi terminal ekranının kullanıldığı ve işlemin kısa özeti.</td></tr>
<tr><td><strong>BC’de nerede görülür?</strong></td><td>İşlemin BC’de oluşturduğu belge, günlük ya da hareket kaydı ve bu kaydın sayfası.</td></tr>
<tr><td><strong>Nasıl kontrol edilir?</strong></td><td>Kaydın doğru olduğunu anlamak için bakmanız gereken alanlar ve filtreler.</td></tr>
</tbody></table>
<div class="info"><strong>Bağlantı:</strong> Bu kılavuzdaki bilgiler <strong>Sand2010 · Element 4 Dizayn Müh. End. A.Ş.</strong> şirketine aittir. Terminalde ve BC’de aynı ortam ile şirketin seçili olduğunu her zaman kontrol edin. Başka bir ortamda (ör. DemoSandbox) gördüğünüz stoklar Element 4’ün gerçek stoğu değildir.</div>
{BACK}</section>

<section id="kurulum"><h2>1. Element 4 deposu BC’de nasıl kurulu?</h2>
<p>BC’de bir depo bir <strong>lokasyon</strong> olarak tanımlanır. Element 4’te tek bir lokasyon vardır: <strong>ELM4-WMS</strong> (adı ELEMENT4-WMS). Bütün stok, bütün raflar ve bütün ambar belgeleri bu lokasyondadır. Lokasyonun kartını BC’de {AQ} ile <strong>Lokasyonlar</strong> listesini açıp ELM4-WMS satırından görebilirsiniz.</p>
<p>Lokasyon kartındaki iki ayar, depodaki her işin nasıl yapılacağını belirler:</p>
<table><thead><tr><th>Ayar (Lokasyon Kartı)</th><th>ELM4-WMS’te</th><th>Sizin için anlamı</th></tr></thead><tbody>
<tr><td><strong>Raf Zorunlu</strong> (Bin Mandatory)</td><td>Açık</td><td>Her stok bir rafta durur. Stok girişi, çıkışı ve taşıması her zaman bir raf koduyla yapılır; rafsız stok olmaz.</td></tr>
<tr><td><strong>Yönlendirilmiş Yerleştirme ve Toplama</strong> (Directed Put-away and Pick)</td><td>Açık</td><td>BC’nin gelişmiş ambar yönetimi kullanılır. Bu ayar açıkken BC <strong>Mal Kabul Gerekli</strong>, <strong>Yerleştirme Gerekli</strong>, <strong>Sevkiyat Gerekli</strong> ve <strong>Toplama Gerekli</strong> ayarlarını da kendiliğinden açar ve kapatılmasına izin vermez. Yani giriş için ambar mal kabulü ve yerleştirme, çıkış için ambar toplaması ve ambar sevkiyatı <strong>zorunludur</strong>.</td></tr>
<tr><td><strong>Transit lokasyonu olarak kullan</strong></td><td>Kapalı</td><td>ELM4-WMS gerçek bir depodur. Şirkette transit lokasyon tanımlı değildir (4.3’e bakın).</td></tr>
</tbody></table>
<div class="note">Yönlendirilmiş lokasyonda satınalma siparişini ya da satış siparişini doğrudan <strong>Nakletmek</strong> stok hareketi oluşturmaz; BC sizi ambar belgesine yönlendirir. Stok yalnız ambar belgeleri (mal kabul, yerleştirme, toplama, sevkiyat), ambar günlükleri ya da sayım ile değişir. Terminal tam olarak bu belgeleri işler.</div>

<section id="alanlar"><h3>1.1 Alanlar ve raflar</h3>
<p>ELM4-WMS’te raflar <strong>alanlara</strong> (BC’deki adı <strong>Bölge / Zone</strong>) gruplanmıştır. Terminal bu gruplara “alan” der; BC’de raf kartındaki <strong>Bölge Kodu</strong> alanı aynı bilgidir. Her rafın bir <strong>raf tipi</strong> vardır; raf tipi o rafın mal kabulde, yerleştirmede, toplamada ya da sevkiyatta kullanılıp kullanılmayacağını belirler. Lokasyonda 11 alan ve 30 raf tanımlıdır:</p>
<table><thead><tr><th>Alan (Bölge)</th><th>Raflar</th><th>Raf tipi</th><th>Ne için?</th></tr></thead><tbody>
<tr><td>MAL KABUL</td><td>G1, G2, G3</td><td>RECEIVE</td><td>Gelen malın ambar mal kabulüyle ilk girdiği raflar.</td></tr>
<tr><td>HAMMADDE</td><td>HM1, HM2</td><td>PUT-PICK</td><td>Hammadde stok rafları (yerleştirme ve toplama).</td></tr>
<tr><td>MAMUL</td><td>D1, D2, D3</td><td>PUT-PICK</td><td>Mamul stok rafları.</td></tr>
<tr><td>YARI MAMUL</td><td>F1, F2, F3</td><td>PUT-PICK</td><td>Yarı mamul stok rafları.</td></tr>
<tr><td>EKSTRÜZYON</td><td>A1, A2, A3</td><td>PICK</td><td>Toplama rafları.</td></tr>
<tr><td>BORU/PROFİL</td><td>B1, B2, B3</td><td>PICK</td><td>Toplama rafları.</td></tr>
<tr><td>SAC</td><td>E1, E2, E3</td><td>PICK</td><td>Toplama rafları.</td></tr>
<tr><td>SEVKİYAT</td><td>H1, H2, H3</td><td>SHIP</td><td>Toplanan malın sevkiyattan önce beklediği raflar.</td></tr>
<tr><td>BEKLEME ALANI</td><td>C1, C2, C3</td><td>QC</td><td>Bekletme / kontrol rafları.</td></tr>
<tr><td>ÜRETİM</td><td>URT-1, URT-2, URT-3</td><td>QC</td><td>Üretime verilen malın raf alanı.</td></tr>
<tr><td>AYARLAMA</td><td>AYARLAMA</td><td>QC</td><td>BC’nin <strong>ayarlama rafı</strong>. Sayım ve stok düzeltmelerinde fark önce bu rafa yazılır (5.3’e bakın). Bu rafa elle mal koymayın.</td></tr>
</tbody></table>
<div class="warn">BC’de standart raf tipi ayarlarında <strong>PICK</strong> tipli raflar (A, B, E rafları) yerleştirme önerisinde çıkmaz; BC yerleştirme için PUT-PICK tipli rafları (HM, D, F) önerir. Malı A, B veya E raflarına koymanız gerekiyorsa yerleştirmede hedef rafı değiştirin ya da yerleştirmeden sonra Ad-Hoc Hareket yapın. Raf tiplerinin bayrakları (Yerleştirme / Toplama / Mal Kabul / Sevkiyat) BC’de <strong>Raf Tipleri</strong> (Bin Types) sayfasından kontrol edilir.</div>
<p>Rafların listesi BC’de {AQ} → <strong>Raflar</strong> (Bins) sayfasındadır; lokasyon kartından da <strong>Raflar</strong> eylemiyle açılır. BCWMS bu listeye <strong>Raf Etiketi Yazdır</strong> eylemini ekler.</p></section>

<section id="stok-durum"><h3>1.2 Bugünkü stok durumu</h3>
<p>Kafes depo sayımının sonucu BC’ye <strong>23.10.2026</strong> tarihinde, <strong>STOK-GIRIS</strong> belge numarasıyla girildi. Bu kılavuz hazırlanırken (27.10.2026) BC’de okunan durum şöyledir:</p>
<table><thead><tr><th>Bilgi</th><th>Değer</th></tr></thead><tbody>
<tr><td>Madde kartı sayısı</td><td>2.500 (P-00001 … P-02500), hiçbiri engelli değil</td></tr>
<tr><td>Stoğu olan madde</td><td>265 madde, toplam 3.339 ADET</td></tr>
<tr><td>Stoğun bulunduğu raf</td><td>Sayım stoğunun tamamı <strong>HAMMADDE alanı, HM1 rafında</strong></td></tr>
<tr><td>Madde hareketleri</td><td>265 kayıt; tamamı 23.10.2026 tarihli, STOK-GIRIS belge no’lu <strong>pozitif düzeltme</strong></td></tr>
<tr><td>Ambar hareketleri</td><td>795 kayıt: her madde için AYARLAMA rafından eksi, HM1 rafına artı ve AYARLAMA rafını sıfırlayan artı kayıt</td></tr>
<tr><td>Lot / seri takibi</td><td>Hiçbir maddede lot veya seri takibi yok</td></tr>
<tr><td>LP (taşıma kabı / palet)</td><td>Henüz LP oluşturulmamış; stok LP’siz (gevşek) durur</td></tr>
<tr><td>Açık ambar belgesi</td><td>Açık mal kabul, yerleştirme, toplama, sevkiyat, taşıma ve sayım belgesi yok</td></tr>
</tbody></table>
<p>Ambar hareketlerindeki düzen, BC’nin yönlendirilmiş lokasyondaki standart stok giriş yoludur: önce ambar günlüğüyle stok rafa (HM1) yazılır, karşılığı ayarlama rafına (AYARLAMA) düşer; ardından madde günlüğündeki <strong>Ambar Ayarlamasını Hesapla</strong> ile ayarlama rafındaki fark madde hareketine (STOK-GIRIS) taşınır ve AYARLAMA rafı sıfırlanır. 5.3’te bu yol ayrıntılı anlatılır.</p>
<div class="warn"><strong>2.235 madde kartında Temel Birim boş.</strong> Stoğu olan 265 maddenin temel birimi <strong>ADET</strong>’tir; diğer madde kartlarında <strong>Temel Ölçü Birimi</strong> alanı boştur. Temel birimi olmayan bir madde mal kabulde, sayımda ya da günlükte kaydedilemez. Bu maddelerden biri ilk kez depoya girecekse önce madde kartında temel birimi doldurun (7. bölüme bakın).</div></section>

<section id="esleme"><h3>1.3 Terminal ekranı → BC sayfası</h3>
<p>Terminal ana menüsündeki her depo ekranının BC’de bir karşılığı vardır. Aşağıdaki tablo bu kılavuzun haritasıdır.</p>
<table><thead><tr><th>Terminal ekranı</th><th>BC’de oluşan / işlenen kayıt</th><th>BC’de bakacağınız sayfa</th></tr></thead><tbody>
<tr><td><strong>Mal Kabul</strong></td><td>Ambar mal kabulü nakledilir; mal MAL KABUL rafına girer, yerleştirme belgesi oluşur.</td><td>Ambar Mal Kabulleri → Nakledilmiş Ambar Mal Kabulleri</td></tr>
<tr><td><strong>Yerleştirme</strong></td><td>Ambar yerleştirmesi kaydedilir; mal MAL KABUL rafından stok rafına taşınır.</td><td>Ambar Yerleştirmeleri → Kayıtlı Yerleştirmeler</td></tr>
<tr><td><strong>Toplama</strong></td><td>Ambar toplaması kaydedilir; mal stok rafından SEVKİYAT rafına taşınır.</td><td>Ambar Toplamaları → Kayıtlı Toplamalar</td></tr>
<tr><td><strong>Sevkiyat</strong></td><td>Ambar sevkiyatı nakledilir; mal stoktan düşer.</td><td>Ambar Sevkiyatları → Nakledilmiş Ambar Sevkiyatları</td></tr>
<tr><td><strong>Ad-Hoc Hareket</strong></td><td>Ambar yeniden sınıflandırma günlüğü kaydedilir; mal raftan rafa taşınır.</td><td>Ambar Hareketleri (hareket türü: Taşıma)</td></tr>
<tr><td><strong>Yönlendirilmiş</strong></td><td>BC’de hazırlanmış ambar taşıması kaydedilir.</td><td>Ambar Taşımaları → Kayıtlı Taşımalar</td></tr>
<tr><td><strong>Sayım</strong></td><td>BCWMS sayım belgesi (Count Sheet); onayda ambar fiziksel envanter ve fiziksel envanter günlükleri kaydedilir.</td><td>Count Sheets → Ambar Hareketleri / Madde Hareketleri</td></tr>
<tr><td><strong>Ürün Sorgu</strong></td><td>Kayıt oluşturmaz, yalnız okur.</td><td>Madde Kartı, Raf İçerikleri</td></tr>
<tr><td><strong>Bin Sorgu</strong></td><td>Kayıt oluşturmaz, yalnız okur.</td><td>Raf İçerikleri</td></tr>
<tr><td><strong>Ambar Hareketleri</strong></td><td>Kayıt oluşturmaz, yalnız okur.</td><td>Ambar Hareketleri</td></tr>
<tr><td><strong>LP</strong>, <strong>Kutu ve Palet</strong></td><td>BCWMS LP kayıtları (stok hareketi değil, stoğun hangi kapta olduğu).</td><td>License Plates, LP İzlenebilirlik</td></tr>
</tbody></table></section>

<section id="gezinme"><h3>1.4 BC’de sayfa bulma (Alt+Q)</h3>
<p>BC’de bir sayfayı en hızlı açmanın yolu aramadır. <strong>Ekranın sağ üstündeki büyüteç</strong> simgesine tıklayın ya da klavyede {AQ} tuşlarına basın, sayfanın adını yazmaya başlayın ve listeden seçin.</p>
<ol class="steps">
<li>{AQ} ile arama kutusunu açın.</li>
<li>Sayfanın Türkçe adını yazın (ör. <strong>Raf İçerikleri</strong>). BC arayüzünüz İngilizceyse ya da Türkçe adı bulamazsanız bu kılavuzda parantez içinde verilen İngilizce adı yazın (ör. <strong>Bin Contents</strong>).</li>
<li>Sonuçlarda <strong>Sayfalara ve raporlara git</strong> başlığı altındaki satırı seçin.</li>
<li>Listede bir alana filtre koymak için sütun başlığındaki oka tıklayıp <strong>Filtrele…</strong> seçin ya da filtre bölmesini açın. En çok kullanacağınız filtreler <strong>Lokasyon Kodu = ELM4-WMS</strong>, <strong>Madde No.</strong>, <strong>Raf Kodu</strong> ve tarihtir.</li>
</ol>
<div class="info"><strong>BCWMS sayfalarının adları:</strong> El terminali uygulamasının BC’ye eklediği bazı sayfalar (ör. <strong>License Plates</strong>, <strong>Count Sheets</strong>, <strong>Count Variance Review</strong>, <strong>Shipment Queue</strong>) BC’de İngilizce adlarıyla görünür; bazıları Türkçedir (ör. <strong>İlk Sayımlar</strong>, <strong>LP İzlenebilirlik</strong>, <strong>Depo Sağlık Paneli</strong>, <strong>Toplama Kuyruğu</strong>). Aramada bu kılavuzda yazıldığı gibi arayın. Bu sayfaların hepsine <strong>Warehouse Manager</strong> rol merkezinden de ulaşılır.</div></section>
{BACK}</section>

<section id="madde"><h2>2. Madde kartı ve stok sorgulama</h2>
<p>Bir ürünün depoda ne kadar olduğunu ve hangi rafta durduğunu terminalde <strong>Ürün Sorgu</strong> ve <strong>Bin Sorgu</strong> ekranlarıyla görürsünüz. BC’de aynı bilgi iki seviyede tutulur ve bu ayrım önemlidir:</p>
<table><thead><tr><th>Seviye</th><th>Ne gösterir?</th><th>BC’de nerede?</th></tr></thead><tbody>
<tr><td><strong>Madde (stok) seviyesi</strong></td><td>Maddenin lokasyondaki toplam miktarı. Değerleme ve muhasebe bu seviyeden yapılır.</td><td>Madde Kartı → <strong>Stok</strong> alanı; Madde Hareketleri</td></tr>
<tr><td><strong>Ambar (raf) seviyesi</strong></td><td>Toplam miktarın hangi rafta ne kadar olduğu.</td><td>Raf İçerikleri; Ambar Hareketleri</td></tr>
</tbody></table>
<p>Doğru çalışan bir depoda iki seviye aynı toplamı verir. Fark varsa bir işlem yarım kalmıştır (2.3’e bakın).</p>

<section id="urun-sorgu"><h3>2.1 Ürün Sorgu → Madde Kartı</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Ürün Sorgu</strong>’yu açar, ürünün barkodunu okutur ya da madde numarasını yazarsınız. Ekranda ürünün açıklaması, birimi, bulunduğu raflar ve raf bazında miktarı görünür.</p>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li>{AQ} ile <strong>Maddeler</strong> (Items) listesini açın ve madde numarasını arayın (ör. P-00003). Satıra tıklayınca <strong>Madde Kartı</strong> açılır.</li>
<li>Kartın <strong>Stok</strong> alanı maddenin bütün lokasyonlardaki toplam miktarıdır; Element 4’te tek lokasyon olduğu için ELM4-WMS’teki miktara eşittir. Rakama tıklarsanız o miktarı oluşturan <strong>Madde Hareketleri</strong> açılır.</li>
<li><strong>Satınalma Siparişindeki Miktar</strong>, <strong>Satış Siparişindeki Miktar</strong> ve <strong>Üretim Emrindeki Miktar</strong> alanları gelecek giriş ve çıkışları gösterir; bunlar henüz stok değildir.</li>
<li>Maddenin hangi rafta durduğunu görmek için kartta <strong>İlgili → Ambar → Raf İçerikleri</strong> eylemini kullanın. Kartın sağındaki <strong>License Plates</strong> bilgi kutusu, maddenin bulunduğu LP’leri gösterir (BCWMS).</li>
<li>Maddenin lokasyona göre dağılımı için kartta <strong>Madde Kullanılabilirliği → Lokasyona Göre</strong> (Item Availability by Location) kullanılabilir.</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong> Terminaldeki toplam miktar ile Madde Kartı’ndaki <strong>Stok</strong> aynı olmalıdır. Madde kartında <strong>Temel Ölçü Birimi</strong>’nin dolu olduğunu, <strong>Engellendi</strong> seçeneğinin kapalı olduğunu ve terminalde okuttuğunuz barkodun bu maddeye ait olduğunu kontrol edin. Ürün etiketini BC’den basmanız gerekirse <strong>Maddeler</strong> listesindeki <strong>Ürün Etiketi Yazdır</strong> eylemi terminaldeki ürün etiketiyle aynı çıktıyı verir.</p></section>

<section id="bin-sorgu"><h3>2.2 Bin Sorgu → Raf İçerikleri</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Bin Sorgu</strong>’yu açar ve rafın etiketini okutursunuz. Ekranda o raftaki ürünler ve miktarları listelenir.</p>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li>{AQ} ile <strong>Raf İçerikleri</strong> (Bin Contents) sayfasını açın.</li>
<li>Filtre bölmesinde <strong>Lokasyon Kodu</strong>’nu ELM4-WMS, <strong>Raf Kodu</strong>’nu okuttuğunuz raf (ör. HM1) yapın. Bir ürünün bütün raflarını görmek için raf filtresi yerine <strong>Madde No.</strong> filtresi koyun.</li>
<li>Her satırda raf, bölge, madde, birim ve <strong>Miktar</strong> görünür. Raf İçerikleri, rafta stoğu olan ya da rafa sabit atanmış madde satırlarını gösterir.</li>
<li>BCWMS bu sayfaya LP bilgisini ekler: <strong>Güncel LP No.ları</strong> ve <strong>Güncel LP Miktarı</strong> sütunları satırdaki stoğun hangi LP’lerde olduğunu gösterir. Üstteki <strong>LP Filtreleri</strong> bölümünden LP numarasıyla arayabilir; <strong>LP Raf İçeriği</strong>, <strong>Raftaki LP’ler</strong>, <strong>LP Numarasına Göre Ara</strong>, <strong>LP Hareketlerini Gör</strong> ve <strong>Göz ve LP karşılaştırma</strong> eylemlerini kullanabilirsiniz.</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong> Terminaldeki raf listesi ile Raf İçerikleri’ndeki satırlar aynı olmalıdır. Bugünkü kurulumda sayım stoğu HM1 rafındadır: Raf Kodu = HM1 filtresiyle 265 satır ve toplam 3.339 ADET görürsünüz. LP kullanılmaya başlandığında raftaki miktar ile <strong>Güncel LP Miktarı</strong> farklıysa <strong>Göz ve LP karşılaştırma</strong> ile farkın nedenini görün; rafta LP’siz (gevşek) stok olması kendi başına hata değildir.</p></section>

<section id="stok-kontrol"><h3>2.3 Stok tutarlılık kontrolü</h3>
<p>Madde seviyesi ile raf seviyesi arasında fark olup olmadığını şöyle kontrol edersiniz:</p>
<ol class="steps">
<li>Madde Kartı’nda <strong>Stok</strong> miktarını not edin.</li>
<li>Raf İçerikleri’nde aynı madde için <strong>Madde No.</strong> filtresi koyun ve bütün rafların miktarını toplayın (AYARLAMA rafı dahil).</li>
<li>İki toplam eşitse kayıtlar tutarlıdır.</li>
<li>Fark AYARLAMA rafındaysa bir ambar günlüğü kaydedilmiş ama madde günlüğündeki <strong>Ambar Ayarlamasını Hesapla</strong> adımı yapılmamıştır (5.3). Fark başka bir raftaysa ambar hareketlerini o raf ve madde için açıp son işlemi inceleyin.</li>
</ol>
<div class="note">BCWMS’in <strong>Depo Sağlık Paneli</strong> ({AQ} ile ya da License Plates listesinden açılır) depodaki sorunları (ör. LP ile raf stoğu arasındaki farkları) tek ekranda listeler. Günlük kontrol için kullanabilirsiniz.</div></section>
{BACK}</section>

<section id="ambar"><h2>3. Ambar belgeleri</h2>
<p>ELM4-WMS yönlendirilmiş bir lokasyon olduğu için depoya giriş ve depodan çıkış her zaman iki adımlıdır ve dört ambar belgesinin dördü de kullanılır:</p>
<table><thead><tr><th></th><th>1. adım</th><th>2. adım</th></tr></thead><tbody>
<tr><td><strong>Giriş</strong></td><td><strong>Ambar Mal Kabulü</strong>: mal gelir, MAL KABUL rafına (G1–G3) girer, stok artar.</td><td><strong>Ambar Yerleştirme</strong>: mal MAL KABUL rafından stok rafına taşınır.</td></tr>
<tr><td><strong>Çıkış</strong></td><td><strong>Ambar Toplama</strong>: mal stok rafından SEVKİYAT rafına (H1–H3) taşınır.</td><td><strong>Ambar Sevkiyatı</strong>: mal depodan çıkar, stok azalır.</td></tr>
</tbody></table>
<p>Belgeyi hazırlamak (siparişten ambar belgesi oluşturmak) çoğunlukla ofiste BC’de yapılır; belgedeki işi yapmak (okutmak, miktarı onaylamak, kaydetmek) terminalde yapılır.</p>

<section id="mal-kabul"><h3>3.1 Mal kabul</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Mal Kabul</strong>’ü açarsınız. Listede açık ambar mal kabulleri görünür; <strong>Bana atanan</strong> filtresiyle size atananları süzebilir, <strong>PO no ile ara</strong> ile satınalma sipariş numarasından bulabilirsiniz. Belgeyi açıp her ürünü okutur, gelen miktarı onaylarsınız. Gerekirse araç plakası, sürücü ve <strong>Tedarikçi İrsaliye No</strong> girersiniz. Ürünler palete konacaksa <strong>LP Başlat</strong> ile bir LP açıp satırları <strong>LP’ye Ekle</strong>, iş bitince <strong>LP Kapat</strong>. Son olarak belgeyi kaydedersiniz.</p>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li><strong>Belge hazırlığı:</strong> Satınalma siparişi ELM4-WMS lokasyonuyla girilir ve <strong>Serbest Bırak</strong> ile serbest bırakılır. Ardından siparişte <strong>Ambar Mal Kabulü Oluştur</strong> (Create Whse. Receipt) eylemiyle ya da {AQ} → <strong>Ambar Mal Kabulleri</strong> → <strong>Yeni</strong> → <strong>Kaynak Belgeleri Getir</strong> ile mal kabul belgesi oluşturulur. Terminal de serbest bırakılmış satınalma siparişinden ambar mal kabulü oluşturabilir.</li>
<li>Açık belgeler {AQ} → <strong>Ambar Mal Kabulleri</strong> (Warehouse Receipts) listesindedir. Belge kartında <strong>Raf Kodu</strong> malın gireceği MAL KABUL rafıdır. BCWMS kartın <strong>DOPSWHS Mobile</strong> grubunda <strong>Atanan Kullanıcı</strong>, <strong>% Complete</strong> (tamamlanma yüzdesi) alanlarını ve <strong>Start LP</strong>, <strong>Stop LP</strong>, <strong>Assign to User</strong> eylemlerini gösterir. Terminalde okuttuğunuz miktar satırdaki <strong>Alınacak Miktar</strong> (Qty. to Receive) alanına yazılır.</li>
<li>Terminalde kaydettikten sonra açık belge listeden çıkar (kısmi kabulde kalan miktarla listede kalır). Kaydedilmiş belge {AQ} → <strong>Nakledilmiş Ambar Mal Kabulleri</strong> (Posted Whse. Receipts) listesindedir.</li>
<li>Aynı anda satınalma siparişi satırında <strong>Teslim Alınan Miktar</strong> artar ve bir <strong>Nakledilmiş Satınalma İrsaliyesi</strong> oluşur.</li>
<li>BC, kaydedilen mal kabul için bir <strong>Ambar Yerleştirme</strong> belgesi oluşturur (3.2).</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong></p>
<table><thead><tr><th>Bakılacak yer</th><th>Görmeniz gereken</th></tr></thead><tbody>
<tr><td>Madde Hareketleri (Madde No. filtresiyle)</td><td>Hareket türü <strong>Satınalma</strong> (Purchase), pozitif miktar, Lokasyon ELM4-WMS, belge no satınalma irsaliyesi.</td></tr>
<tr><td>Ambar Hareketleri</td><td>MAL KABUL rafına (G1–G3) <strong>pozitif düzeltme</strong> (Positive Adjmt.) satırı; LP kullandıysanız <strong>Hareket Anındaki LP No.</strong> dolu.</td></tr>
<tr><td>Raf İçerikleri</td><td>Malın yerleştirme yapılana kadar MAL KABUL rafında görünmesi.</td></tr>
<tr><td>Ambar Yerleştirmeleri</td><td>Bu mal kabule bağlı yeni bir yerleştirme belgesi.</td></tr>
</tbody></table>
<div class="note">Mal kabul satırında terminaldeki miktardan fazlası okutulamaz; eksik gelen mal için yalnız gelen miktarı onaylayın, kalan miktar belgede açık kalır. Lot veya seri takibi şu an hiçbir maddede yoktur; ileride lot takipli madde gelirse terminal lot numarasını da ister.</div></section>

<section id="yerlestirme"><h3>3.2 Yerleştirme</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Yerleştirme</strong>’yi açarsınız. Mal kabulün oluşturduğu yerleştirme belgesini seçersiniz. Ekran sırayla <strong>Bulunduğunuz rafı okutun</strong> (alınacak raf, MAL KABUL rafı), ürün veya <strong>Palet/LP etiketini okutun</strong>, <strong>Koyacağınız rafı okutun</strong> ve <strong>Miktarı onaylayın</strong> der. LP’li mallarda <strong>Raf Bazlı Toplu LP Yerleştirme</strong> ile birden fazla LP’yi tek seferde aynı rafa koyabilirsiniz. Bütün satırlar bitince belge kaydedilir.</p>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li>Açık yerleştirmeler {AQ} → <strong>Ambar Yerleştirmeleri</strong> (Warehouse Put-aways) listesindedir. Her belgede satırlar çift olarak gelir: <strong>Al</strong> (Take) satırı malın alınacağı MAL KABUL rafını, <strong>Koy</strong> (Place) satırı malın konacağı stok rafını gösterir.</li>
<li>Koy satırındaki raf BC’nin önerisidir. Terminalde başka bir raf okutursanız satırdaki raf okuttuğunuz rafa değişir. BCWMS kartta <strong>Suggest Bin</strong> (raf öner) ve <strong>Register Activity</strong> (kaydet) eylemlerini gösterir.</li>
<li>Kaydedilen yerleştirme listeden çıkar ve {AQ} → <strong>Kayıtlı Yerleştirmeler</strong> (Registered Put-aways) listesine geçer.</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong> Ambar Hareketleri’nde yerleştirme belge numarasıyla iki satır görürsünüz: MAL KABUL rafından eksi, hedef raftan artı, hareket türü <strong>Taşıma</strong> (Movement). <strong>Madde Hareketleri değişmez</strong>; yerleştirme stok miktarını değil, yalnız rafı değiştirir. Raf İçerikleri’nde mal artık hedef rafta görünmeli, MAL KABUL rafında kalmamalıdır. MAL KABUL rafında günlerce bekleyen mal, yerleştirmesi yapılmamış mal kabulü demektir.</p>
<div class="info">BC’de yerleştirmeler mal kabulle birlikte kendiliğinden oluşur. Lokasyonda <strong>Yerleştirme Çalışma Sayfası Kullan</strong> ayarı açıksa yerleştirme otomatik oluşmaz, önce <strong>Yerleştirme Çalışma Sayfası</strong>’ndan oluşturulması gerekir. Bu ayar API ile okunamadığı için doğrulanmadı; mal kabulden sonra yerleştirme belgesi görmüyorsanız önce bu ayarı kontrol edin.</div></section>

<section id="sevkiyat"><h3>3.3 Toplama ve sevkiyat</h3>
<p><strong>Terminalde ne yapılır?</strong> Çıkış iki ekranda yapılır:</p>
<ul>
<li><strong>Toplama:</strong> Açık toplamalar listelenir; <strong>Belge no ile ara</strong> ile bulursunuz. Toplamayı açınca ekran <strong>SIRADAKİ RAF</strong>’ı gösterir; <strong>Bu rafın barkodunu okutun</strong>, ürünü ya da LP’yi okutun, miktarı onaylayın. Malın tamamını bulamazsanız <strong>Eksik Toplama</strong> ile eksik miktarı ve sebebini bildirirsiniz. Başkasına atanmış bir toplamayı terminal size vermez (“Bu toplama başkasında”); devralma sorumlu tarafından yapılır.</li>
<li><strong>Sevkiyat:</strong> Toplaması biten sevkiyat belgesini açar, gerekiyorsa <strong>Sevkiyat Acentesi</strong>’ni seçer ve <strong>Sevkiyatı kaydet</strong> ile kaydedersiniz. Ekranda “Sevkiyat kaydedildi” görünür.</li>
</ul>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li><strong>Belge hazırlığı:</strong> Satış siparişi ELM4-WMS lokasyonuyla girilir ve serbest bırakılır. Siparişte <strong>Ambar Sevkiyatı Oluştur</strong> (Create Whse. Shipment) ile sevkiyat belgesi oluşur. Sevkiyat kartında <strong>Toplama Oluştur</strong> (Create Pick) ile toplama belgesi oluşturulur; terminal de sevkiyattan toplama oluşturabilir.</li>
<li>Açık toplamalar {AQ} → <strong>Ambar Toplamaları</strong> (Warehouse Picks) listesindedir. Her toplamada <strong>Al</strong> satırı stok rafını, <strong>Koy</strong> satırı SEVKİYAT rafını gösterir. BCWMS kartta <strong>Assigned User (WMS)</strong> alanını ve <strong>Assign to WMS Operator</strong>, <strong>Clear Assignment</strong>, <strong>Mark Short</strong> eylemlerini ekler. Toplamayı bir operatörden diğerine vermek yalnız buradan yapılır. Bütün açık toplamaları operatöre göre görmek için BCWMS’in <strong>Toplama Kuyruğu</strong> ve <strong>Toplama Atama Panosu</strong> sayfaları kullanılır.</li>
<li>Kaydedilen toplama {AQ} → <strong>Kayıtlı Toplamalar</strong> (Registered Picks) listesine geçer; sevkiyat satırında <strong>Toplanan Miktar</strong> artar.</li>
<li>Açık sevkiyatlar {AQ} → <strong>Ambar Sevkiyatları</strong> (Warehouse Shipments) listesindedir. Kartın sağındaki <strong>Shipping LPs</strong> kutusu sevkiyata bağlı LP’leri, <strong>DOPSWHS Mobile</strong> grubu <strong>Post Mobile</strong> ve <strong>Print Packing Slip</strong> eylemlerini gösterir. Terminal sevkiyatları için BCWMS’in <strong>Shipment Queue</strong> sayfası da vardır.</li>
<li>Kaydedilen sevkiyat {AQ} → <strong>Nakledilmiş Ambar Sevkiyatları</strong> (Posted Whse. Shipments) listesine geçer; satış siparişinde <strong>Sevk Edilen Miktar</strong> artar ve bir <strong>Nakledilmiş Satış İrsaliyesi</strong> oluşur.</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong></p>
<table><thead><tr><th>Adım</th><th>Ambar Hareketleri</th><th>Madde Hareketleri</th></tr></thead><tbody>
<tr><td>Toplama kaydedildi</td><td>Stok rafından eksi, SEVKİYAT rafına artı (Taşıma)</td><td>Değişmez</td></tr>
<tr><td>Sevkiyat kaydedildi</td><td>SEVKİYAT rafından eksi (negatif düzeltme)</td><td>Hareket türü <strong>Satış</strong> (Sale), negatif miktar</td></tr>
</tbody></table>
<p>SEVKİYAT rafında (H1–H3) bekleyen mal, toplaması yapılmış ama sevkiyatı kaydedilmemiş maldır. Gün sonunda Raf İçerikleri’nde H1–H3 raflarını kontrol edin.</p>
<div class="note">Kitoko terminalinde <strong>Paketleme</strong> ekranı da vardır; paketleme toplanan malı kolilere/LP’lere ayırır ve stok miktarını değiştirmez. Paketlemenin BC karşılığı BCWMS’in paketleme sayfalarıdır (Pack Station, Packing Orders). Bu kılavuzun kapsamı dışındadır.</div></section>

<section id="belge-ozet"><h3>3.4 Belgelerin yaşam döngüsü</h3>
<table><thead><tr><th>Belge</th><th>Açıkken (iş bekliyor)</th><th>Terminalde bitince</th><th>Stok etkisi</th></tr></thead><tbody>
<tr><td>Ambar Mal Kabulü</td><td>Ambar Mal Kabulleri</td><td>Nakledilmiş Ambar Mal Kabulleri</td><td>Stok artar (MAL KABUL rafı)</td></tr>
<tr><td>Ambar Yerleştirme</td><td>Ambar Yerleştirmeleri</td><td>Kayıtlı Yerleştirmeler</td><td>Yalnız raf değişir</td></tr>
<tr><td>Ambar Toplama</td><td>Ambar Toplamaları</td><td>Kayıtlı Toplamalar</td><td>Yalnız raf değişir</td></tr>
<tr><td>Ambar Sevkiyatı</td><td>Ambar Sevkiyatları</td><td>Nakledilmiş Ambar Sevkiyatları</td><td>Stok azalır (SEVKİYAT rafı)</td></tr>
<tr><td>Ambar Taşıma</td><td>Ambar Taşımaları</td><td>Kayıtlı Taşımalar</td><td>Yalnız raf değişir</td></tr>
</tbody></table>
<div class="warn">Açık bir ambar belgesini BC’de silmek terminalde o belge üzerinde yapılmış ama kaydedilmemiş işi de siler. Bir belgeyi silmeden ya da yeniden oluşturmadan önce terminalde kimsenin o belgeyle çalışmadığından emin olun.</div></section>
{BACK}</section>

<section id="transfer"><h2>4. Transfer ve raf hareketleri</h2>
<p>“Transfer” iki farklı işi anlatabilir: aynı depo içinde malı <strong>raftan rafa taşımak</strong> ya da malı <strong>bir lokasyondan başka bir lokasyona göndermek</strong>. Element 4’te bugün yalnız ilki kullanılır.</p>

<section id="adhoc"><h3>4.1 Ad-Hoc Hareket (raftan rafa)</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Ad-Hoc Hareket</strong>’i açarsınız. Bu ekran belgesiz taşıma içindir. Üstte <strong>Ürün ile</strong> ya da <strong>LP ile</strong> seçersiniz. Ürün ile taşımada kaynak rafı, ürünü ve miktarı, sonra hedef rafı okutursunuz. LP ile taşımada kaynak raftaki LP’yi seçip (<strong>Bu Bindeki LP’leri Listele</strong>) hedef rafı okutursunuz; <strong>Hedefi Doğrula</strong> okuttuğunuz değerin raf mı LP mi olduğunu kontrol eder. İşlem bitince “Hareket kaydedildi” görünür.</p>
<p><strong>BC’de nerede görülür?</strong> ELM4-WMS yönlendirilmiş lokasyon olduğu için terminal taşımayı BC’nin <strong>Ambar Yeniden Sınıflandırma Günlüğü</strong> (Whse. Reclassification Journal) ile kaydeder (şablon RECLASS, BCWMS’in kendi günlük sayfası). Günlük satırı kayıttan hemen sonra silindiği için günlükte bir şey görmezsiniz; sonuç <strong>Ambar Hareketleri</strong>’ndedir.</p>
<p><strong>Nasıl kontrol edilir?</strong></p>
<ol class="steps">
<li>{AQ} → <strong>Ambar Hareketleri</strong>’ni açın; <strong>Madde No.</strong> ve tarih filtresi koyun.</li>
<li>Aynı işlem için iki satır görmelisiniz: kaynak raftan eksi, hedef rafa artı; hareket türü <strong>Taşıma</strong> (Movement). LP ile taşıdıysanız iki satırda da <strong>Hareket Anındaki LP No.</strong> dolu olur.</li>
<li>Raf İçerikleri’nde miktarın kaynak raftan hedef rafa geçtiğini görün.</li>
<li><strong>Madde Hareketleri değişmez</strong>; mal aynı lokasyonda kaldığı için stok toplamı ve değeri aynıdır.</li>
</ol>
<div class="warn">Ad-Hoc Hareket’i AYARLAMA, MAL KABUL ve SEVKİYAT raflarına ya da bu raflardan yapmayın. Bu raflar belgeli akış içindir; buradaki bir elle taşıma açık mal kabul, yerleştirme ya da toplama belgesinin miktarlarıyla çelişebilir.</div></section>

<section id="yonlendirilmis"><h3>4.2 Yönlendirilmiş hareket</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Yönlendirilmiş</strong>’i açarsınız. Listede BC’de hazırlanmış ambar taşıma belgeleri görünür. Belgeyi açıp her satırda alınacak rafı ve ürünü okutur, konacak rafı okutur ve miktarı onaylarsınız; sonunda belgeyi kaydedersiniz.</p>
<p><strong>BC’de nerede görülür?</strong> Ofiste ambar sorumlusu {AQ} → <strong>Taşıma Çalışma Sayfası</strong> (Movement Worksheet) ile hangi malın hangi raftan hangi rafa taşınacağını hazırlar ve <strong>Taşıma Oluştur</strong> ile belge oluşturur. Açık belgeler {AQ} → <strong>Ambar Taşımaları</strong> (Warehouse Movements), kaydedilenler {AQ} → <strong>Kayıtlı Taşımalar</strong> (Registered Movements) listesindedir.</p>
<p><strong>Nasıl kontrol edilir?</strong> Ambar Hareketleri’nde taşıma belge numarasıyla Al ve Koy satırları (Taşıma türünde) görünür; Madde Hareketleri değişmez. Yönlendirilmiş hareket, Ad-Hoc Hareket’in planlı ve onaylı halidir: hangi taşımanın yapılacağına ofis karar verir, terminal uygular.</p></section>

<section id="transfer-emri"><h3>4.3 Transfer Emirleri</h3>
<p><strong>Bugünkü kurulumda kullanılmaz.</strong> BC’de bir lokasyondan diğerine mal göndermek için <strong>Transfer Emirleri</strong> (Transfer Orders) kullanılır ve bunun için en az iki gerçek lokasyon ile bir <strong>transit lokasyon</strong> gerekir. Element 4 şirketinde yalnız ELM4-WMS lokasyonu vardır ve transit lokasyon tanımlı değildir; bu yüzden lokasyonlar arası transfer yapılmaz. Depo içindeki bütün yer değişiklikleri 4.1 ve 4.2’deki raf hareketleriyle yapılır.</p>
<p>İleride ikinci bir lokasyon (ör. ayrı bir üretim deposu) açılırsa transfer şöyle çalışır:</p>
<table><thead><tr><th>Adım</th><th>Terminalde</th><th>BC’de</th></tr></thead><tbody>
<tr><td>Transfer emri hazırlanır</td><td>—</td><td>{AQ} → Transfer Emirleri → Yeni; çıkış ve varış lokasyonu, transit lokasyon; Serbest Bırak.</td></tr>
<tr><td>Gönderen depodan çıkış</td><td>Gönderen lokasyon yönlendirilmişse Toplama ve Sevkiyat (3.3)</td><td>Ambar Sevkiyatı → Nakledilmiş Transfer Sevkiyatı; mal transit lokasyonda görünür.</td></tr>
<tr><td>Alan depoya giriş</td><td>Mal Kabul ve Yerleştirme (3.1, 3.2)</td><td>Ambar Mal Kabulü → Nakledilmiş Transfer Alımı; Madde Hareketleri’nde hareket türü <strong>Transfer</strong>.</td></tr>
</tbody></table>
<p>BCWMS, Transfer Emri kartına <strong>DOPSWHS Mobile</strong> grubunda <strong>Receive via Mobile</strong>, <strong>Start LP</strong> ve <strong>Stop LP</strong> eylemlerini ekler. Bu eylemler ancak ikinci lokasyon kurulduğunda anlam kazanır.</p></section>
{BACK}</section>

<section id="sayim"><h2>5. Sayım</h2>
<p>Kafes depodaki ilk sayım tamamlandı. Bundan sonraki sayımlar (dönemsel sayım, raf sayımı, fark kontrolü) terminalin <strong>Sayım</strong> ekranıyla yapılır. Sayım sonucu stokları değiştirdiği için son adım her zaman sorumlu onayıyla yapılır.</p>

<section id="sayim-terminal"><h3>5.1 Terminalde sayım → Count Sheets</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüden <strong>Sayım</strong>’ı açarsınız. Size atanmış sayım belgesini seçer ya da sorumlu yeni bir sayım açar (lokasyon ELM4-WMS, isteğe bağlı alan filtresi). Alanı, sonra rafı okutur; raftaki her ürünün ya da LP’nin barkodunu okutup bulduğunuz miktarı girersiniz. Raf bitince <strong>Rafı bitir</strong>; bulamadığınız kalemler için <strong>Rafı bitir · sayılmayanları 0 yaz</strong>. Ayrıntılı terminal adımları “Sayım ve Etiket Kılavuzu”ndadır.</p>
<p><strong>BC’de nerede görülür?</strong></p>
<ol class="steps">
<li>{AQ} → <strong>Count Sheets</strong> (sayım fişleri) listesini açın. Terminalde açılan her sayım burada <strong>CNT-</strong> ile başlayan bir numarayla görünür. Listede lokasyon, durum ve sayım modu yer alır.</li>
<li>Satırı açınca <strong>Count Sheet</strong> kartı gelir. <strong>Sayım Durumu</strong> bölümünde <strong>Toplam Satır</strong>, <strong>Sayılan</strong>, <strong>Kalan</strong> ve <strong>Farklı Satır</strong> sayıları sayımın ne kadar ilerlediğini gösterir. Satırlarda raf, madde, LP, sistem miktarı ve sayılan miktar görünür. Sayıcılar kartın sayıcı bölümünde atanır; terminalde “atanmış sayıcı slotu yok” uyarısı alan kullanıcıyı buradan ekleyin.</li>
<li>Farkları incelemek için kartta <strong>Raf Farklarını İncele</strong> ve <strong>Count Variance Review</strong> (sayım farkı inceleme) sayfaları, yazdırmak için <strong>Print Variance Report</strong> kullanılır. LP’nin başka rafta bulunduğu durumlar <strong>LP Raf Düzeltme Listesi</strong>’nde listelenir.</li>
<li>Farkı büyük bir raf için ikinci sayım gerekiyorsa kartta yeni tur açılır (terminalde <strong>Yeni Turu Başlat</strong>); turlar terminalde <strong>Turları Yan Yana Karşılaştır</strong> ile karşılaştırılır. Önceki turun sonuçları kartta korunur.</li>
</ol>
<p><strong>Nasıl kontrol edilir?</strong> Kartta <strong>Kalan</strong> sıfır olmalı ve <strong>Farklı Satır</strong>’daki her fark açıklanmış olmalıdır. Farklı rafta bulunan LP’ler varsa sayım bu bulgular çözülmeden stoklara işlenemez; bu durumda önce LP’yi doğru rafa taşıyın (4.1) ve sayımı yeni turla tamamlayın.</p></section>

<section id="sayim-isleme"><h3>5.2 Sayımı stoklara işleme</h3>
<p>Sayım iki yoldan stoklara işlenebilir:</p>
<table><thead><tr><th>Yol</th><th>Nerede?</th><th>Ne zaman?</th></tr></thead><tbody>
<tr><td><strong>BC’den</strong></td><td>Count Sheet kartında ya da Count Sheets listesinde <strong>Post</strong></td><td>Her zaman kullanılabilir.</td></tr>
<tr><td><strong>Terminalden</strong></td><td>Sayım ekranında <strong>Onayla ve Stoklara İşle</strong></td><td>Yalnız BCWMS kurulumunda (<strong>Advanced WMS Setup</strong>) <strong>Terminal Count Posting</strong> açıksa. Bu ayar varsayılan olarak kapalıdır; kapalıyken terminal “Sayım stoklara yalnız Business Central’den işlenir” uyarısı verir.</td></tr>
</tbody></table>
<p>Hangi yoldan işlerseniz işleyin, arka planda aynı kayıtlar oluşur. ELM4-WMS yönlendirilmiş olduğu için işleme iki adımda yapılır:</p>
<ol class="steps">
<li><strong>Ambar Fiziksel Envanter Günlüğü</strong> kaydedilir (şablon PHYSINV, toplu iş DOPS-CNT): sayılan raf düzeltilir, fark AYARLAMA rafına yazılır.</li>
<li><strong>Fiziksel Envanter Günlüğü</strong> nakledilir (şablon PHYS. INV., belgeye özel toplu iş): AYARLAMA rafındaki fark madde hareketine taşınır. Belge numarası sayım numarasıdır (CNT-…).</li>
</ol>
<p>İşlemden sonra sayım belgesinin durumu <strong>Posted</strong> olur ve belge artık değiştirilemez. Sistem miktarıyla aynı sayılan satırlar için kayıt oluşmaz; yalnız farklar işlenir. LP’li stoklarda LP içeriği de sayılan miktara eşitlenir.</p>
<p><strong>Nasıl kontrol edilir?</strong></p>
<table><thead><tr><th>Bakılacak yer</th><th>Görmeniz gereken</th></tr></thead><tbody>
<tr><td>Madde Hareketleri (Belge No. = CNT-…)</td><td>Fazla çıkan maddeler için <strong>pozitif düzeltme</strong>, eksik çıkanlar için <strong>negatif düzeltme</strong>; miktar = fark.</td></tr>
<tr><td>Ambar Hareketleri (aynı tarih)</td><td>Sayılan rafta fark kadar artı/eksi, AYARLAMA rafında karşılığı, ardından AYARLAMA rafını sıfırlayan satır.</td></tr>
<tr><td>Raf İçerikleri (Raf Kodu = AYARLAMA)</td><td>Miktar sıfır. AYARLAMA rafında miktar kalmışsa ikinci adım tamamlanmamıştır.</td></tr>
<tr><td>Count Sheets</td><td>Belgenin durumu Posted.</td></tr>
</tbody></table>
<div class="warn">“Cevap alınamadı” gibi bir uyarı görürseniz işleme düğmesine ikinci kez basmayın. Önce Count Sheets’te belgenin durumunun Posted olup olmadığını ve Madde Hareketleri’nde CNT- belge numarasıyla kayıt oluşup oluşmadığını kontrol edin.</div></section>

<section id="sayim-standart"><h3>5.3 BC’nin standart sayım yolu</h3>
<p>Terminal kullanılmadan, yalnız BC’de sayım ya da stok düzeltmesi yapmanız gerekirse yönlendirilmiş lokasyonda standart yol şudur. 23.10.2026’daki STOK-GIRIS girişi de bu yolla yapıldı.</p>
<ol class="steps">
<li>{AQ} → <strong>Ambar Fiziksel Envanter Günlüğü</strong> (Whse. Phys. Invt. Journal) sayfasını açın; lokasyonu ELM4-WMS seçin.</li>
<li><strong>Envanteri Hesapla</strong> (Calculate Inventory) ile sayılacak raf ve maddeleri getirin. Raf veya madde filtresiyle yalnız saydığınız alanı getirebilirsiniz.</li>
<li>Her satırda <strong>Fiziksel Miktar</strong> (Qty. (Phys. Inventory)) alanına saydığınız miktarı yazın. Sayım listesi için <strong>Yazdır</strong> ile Ambar Fiziksel Envanter Listesi basılabilir.</li>
<li><strong>Kaydet</strong> (Register) ile günlüğü kaydedin. Rafların miktarı düzelir; fark AYARLAMA rafına yazılır. Bu noktada madde stoku henüz değişmemiştir.</li>
<li>{AQ} → <strong>Madde Günlükleri</strong> (Item Journals) sayfasını açın, <strong>Ambar Ayarlamasını Hesapla</strong> (Calculate Whse. Adjustment) çalıştırın. BC, AYARLAMA rafındaki farkları madde günlüğü satırı olarak getirir.</li>
<li>Satırları kontrol edip <strong>Naklet</strong> ile nakledin. Madde Hareketleri’nde pozitif/negatif düzeltme oluşur ve AYARLAMA rafı sıfırlanır.</li>
</ol>
<div class="note">Yönlendirilmiş lokasyonda <strong>Fiziksel Envanter Günlüğü</strong>’ndeki <strong>Envanteri Hesapla</strong> rafı düzeltemez; stok farkını raf bazında işlemek için mutlaka önce <strong>Ambar Fiziksel Envanter Günlüğü</strong> kullanılır. Aynı kural stok girişi ve çıkışı düzeltmelerinde de geçerlidir: önce <strong>Ambar Madde Günlüğü</strong> (Whse. Item Journal), sonra madde günlüğünde <strong>Ambar Ayarlamasını Hesapla</strong>.</div>
<p>BCWMS’in BC tarafında açtığı sayım belgeleri ile bu standart günlükler arasındaki bağ, <strong>Fiziksel Envanter Günlüğü</strong> sayfasında BCWMS’in eklediği <strong>Source Count Sheet</strong> alanı ve <strong>Open Count Sheet Card</strong> eylemiyle görülür.</p></section>

<section id="ilk-sayim"><h3>5.4 İlk Sayım bu depoda kullanılmaz</h3>
<p>Terminal menüsünde <strong>İlk Sayım</strong> ekranı da görünür ve BC’de karşılığı <strong>İlk Sayımlar</strong> sayfasıdır (satırlar için <strong>Satırlar</strong>, işlemek için <strong>Stoğa İşle</strong>). Ancak İlk Sayım yönlendirilmiş lokasyonlarda çalışmaz: ELM4-WMS için İlk Sayım açmaya çalışırsanız “… lokasyonu yönlendirilmiş (Directed Put-away and Pick); İlk Sayım burada kullanılamaz. Sayım ekranını kullanın.” uyarısı alırsınız. Element 4’te bütün sayımlar <strong>Sayım</strong> ekranıyla yapılır. BC’de İlk Sayımlar sayfasında Element 4 için kayıt yoktur.</p></section>
{BACK}</section>

<section id="hareket"><h2>6. Madde hareketleri ve stok raporları</h2>
<p>BC’de stoğu değiştiren her işlem silinemeyen bir hareket kaydı bırakır. Terminalde bir işlemin yapılıp yapılmadığından emin olmak istediğinizde son başvuracağınız yer bu kayıtlardır.</p>

<section id="madde-hareket"><h3>6.1 Madde Hareketleri</h3>
<p><strong>Terminalde ne yapılır?</strong> Terminal madde hareketlerini doğrudan göstermez; mal kabul, sevkiyat ve sayım işlemleri bu kayıtları oluşturur.</p>
<p><strong>BC’de nerede görülür?</strong> {AQ} → <strong>Madde Hareketleri</strong> (Item Ledger Entries). Madde Kartı’nda <strong>Stok</strong> rakamına tıklayarak ya da kartta <strong>İlgili → Geçmiş → Hareketler → Hareketler</strong> ile de açılır. Önemli sütunlar:</p>
<table><thead><tr><th>Sütun</th><th>Anlamı</th></tr></thead><tbody>
<tr><td><strong>Nakil Tarihi</strong></td><td>Hareketin stoğa işlendiği tarih.</td></tr>
<tr><td><strong>Hareket Türü</strong></td><td>Satınalma (mal kabul), Satış (sevkiyat), Pozitif / Negatif Düzeltme (sayım, stok düzeltmesi), Transfer, Tüketim, Çıktı (üretim).</td></tr>
<tr><td><strong>Belge No.</strong></td><td>İşlemin belgesi: irsaliye no, sayım no (CNT-…), ilk stok girişi için STOK-GIRIS.</td></tr>
<tr><td><strong>Lokasyon Kodu</strong>, <strong>Miktar</strong></td><td>ELM4-WMS ve işaretli miktar (giriş artı, çıkış eksi).</td></tr>
<tr><td><strong>Kalan Miktar</strong>, <strong>Açık</strong></td><td>Giriş hareketinden henüz çıkış yapılmamış kısım.</td></tr>
<tr><td><strong>LP No.</strong>, <strong>LP No.leri</strong> (BCWMS)</td><td>Hareketin ilişkili olduğu LP; birden fazla LP’den toplanan çıkışlarda bütün LP’ler.</td></tr>
</tbody></table>
<p>BCWMS bu sayfaya <strong>LP İzlenebilirlik</strong>, <strong>LP Bilgisini Yenile</strong> ve <strong>Tüm LP MTE Etiketleri</strong> eylemlerini ekler.</p>
<p><strong>Nasıl kontrol edilir?</strong> Madde No. filtresi koyup hareketleri tarihe göre sıralayın. Bir maddenin <strong>Miktar</strong> sütununun toplamı Madde Kartı’ndaki <strong>Stok</strong>’a eşittir. Terminalde yaptığınız bir mal kabul ya da sevkiyat burada görünmüyorsa işlem BC’ye ulaşmamıştır; terminalde aynı işlemi tekrarlamadan önce açık belgeye bakın.</p></section>

<section id="ambar-hareket"><h3>6.2 Ambar Hareketleri</h3>
<p><strong>Terminalde ne yapılır?</strong> Ana menüdeki <strong>Ambar Hareketleri</strong> ekranı geçmiş raf hareketlerini terminalde gösterir.</p>
<p><strong>BC’de nerede görülür?</strong> {AQ} → <strong>Ambar Hareketleri</strong> (Warehouse Entries). Madde hareketlerinden farkı, <strong>raf</strong> bilgisini taşıması ve stok miktarını değiştirmeyen taşımaları (yerleştirme, toplama, Ad-Hoc Hareket) da göstermesidir. Önemli sütunlar: <strong>Kayıt Tarihi</strong>, <strong>Hareket Türü</strong> (Pozitif Düzeltme, Negatif Düzeltme, Taşıma), <strong>Bölge Kodu</strong>, <strong>Raf Kodu</strong>, <strong>Madde No.</strong>, <strong>Miktar</strong>, <strong>Belge No.</strong>. BCWMS üç sütun ekler: <strong>Hareket Anındaki LP No.</strong> (hareket olduğunda yazılan LP; sonradan değişmez), <strong>Güncel LP No.ları</strong> ve <strong>Güncel LP Miktarı</strong> (aynı raf ve maddenin bugünkü LP dağılımı).</p>
<p><strong>Nasıl kontrol edilir?</strong> Bir rafın bütün hareketlerini görmek için <strong>Raf Kodu</strong> filtresi koyun; miktarların toplamı Raf İçerikleri’ndeki miktara eşittir. Bir taşımayı doğrularken iki satırın (eksi ve artı) da olduğunu kontrol edin.</p></section>

<section id="lp-sayfalar"><h3>6.3 LP sayfaları</h3>
<p>LP (License Plate) bir palet, koli ya da taşıma kabıdır. Bugün Element 4’te LP oluşturulmamıştır; stok rafta LP’siz durur. LP kullanılmaya başlandığında (ör. mal kabulde <strong>LP Başlat</strong>) BC’de şu sayfalar kullanılır:</p>
<table><thead><tr><th>Sayfa ({AQ} ile arayın)</th><th>Ne gösterir?</th></tr></thead><tbody>
<tr><td><strong>License Plates</strong></td><td>Bütün LP’ler: lokasyon, raf, durum, içerik satırı sayısı, toplam miktar. <strong>LP Stok Mutabakat Raporu</strong> ve <strong>Seçili LP’lerin MTE Etiketleri</strong> eylemleri buradadır.</td></tr>
<tr><td><strong>License Plate</strong> (kart)</td><td>Tek LP’nin içeriği; <strong>MTE Etiketi</strong> ve <strong>İzlenebilirlik</strong> eylemleri.</td></tr>
<tr><td><strong>LP İzlenebilirlik</strong></td><td>LP’nin içeriği, hareket geçmişi, bağlı madde hareketleri ve BC kalan miktarıyla karşılaştırma.</td></tr>
<tr><td><strong>LP Hareket Geçmişi</strong></td><td>LP’lerin hangi tarihte hangi raftan hangi rafa taşındığı.</td></tr>
<tr><td><strong>Güncel LP Dağılımı</strong>, <strong>LP Raf İçeriği</strong></td><td>Bir rafta ya da maddede stoğun LP’lere göre dağılımı.</td></tr>
<tr><td><strong>Göz ve LP Karşılaştırma</strong></td><td>Raftaki BC stoğu ile aktif LP miktarlarının karşılaştırması.</td></tr>
<tr><td><strong>Depo Sağlık Paneli</strong></td><td>Depodaki sorunların listesi.</td></tr>
</tbody></table>
<div class="info">LP bir stok hareketi değildir; stoğun hangi kapta olduğunu gösterir. Stok miktarı her zaman Madde Hareketleri ve Ambar Hareketleri’nden gelir. LP ile raf stoğu farklıysa Göz ve LP Karşılaştırma ile nedenini bulun.</div></section>

<section id="raporlar"><h3>6.4 Stok raporları</h3>
<p>Aşağıdaki standart raporlar {AQ} ile adlarıyla aranır. Her raporun istek sayfasında <strong>Lokasyon Filtresi</strong>’ni ELM4-WMS, gerekirse <strong>Tarih Filtresi</strong>’ni dönem olarak girin; sonra <strong>Önizle</strong> ya da <strong>Yazdır</strong>. BC sürümüne göre Türkçe adlar küçük farklarla görünebilir; bulamazsanız İngilizce adla arayın.</p>
<table><thead><tr><th>Rapor / sayfa</th><th>Ne için?</th></tr></thead><tbody>
<tr><td><strong>Raf İçerikleri</strong> (Bin Contents) sayfası → Excel’de aç</td><td>Raf bazında anlık stok listesi. Sayfadaki <strong>Paylaş → Excel’de Aç</strong> ile dışa aktarılır.</td></tr>
<tr><td><strong>Ambar Raf Listesi</strong> (Warehouse Bin List)</td><td>Raflar ve içerikleri, raf bazında basılı liste.</td></tr>
<tr><td><strong>Stok Değerleme</strong> (Inventory Valuation)</td><td>Dönem başı, giriş, çıkış ve dönem sonu stok miktarı ve tutarı.</td></tr>
<tr><td><strong>Madde Kullanılabilirliği – Lokasyona Göre</strong> (Item Availability by Location)</td><td>Stok, gelecek giriş ve çıkışlarla birlikte kullanılabilir miktar.</td></tr>
<tr><td><strong>Stok – İşlem Ayrıntısı</strong> (Inventory - Transaction Detail)</td><td>Madde bazında dönem içindeki her hareket ve yürüyen bakiye.</td></tr>
<tr><td><strong>Ambar Fiziksel Envanter Listesi</strong> (Whse. Phys. Inventory List)</td><td>Sayım için raf bazında boş sayım listesi.</td></tr>
<tr><td><strong>Print Variance Report</strong> (Count Sheet kartında)</td><td>BCWMS sayımının fark raporu.</td></tr>
<tr><td><strong>LP Stok Mutabakat Raporu</strong> (License Plates)</td><td>LP miktarları ile BC stoğunun mutabakatı.</td></tr>
</tbody></table></section>

<section id="gunluk"><h3>6.5 Günlük kontrol listesi</h3>
<p>Terminalle çalışılan her günün sonunda ambar sorumlusunun BC’de yapacağı kısa kontrol:</p>
<ol class="steps">
<li><strong>Ambar Mal Kabulleri</strong>: bugün gelen ama kaydedilmemiş belge var mı?</li>
<li><strong>Raf İçerikleri</strong>, Raf Kodu = G1|G2|G3: yerleştirilmeden MAL KABUL rafında bekleyen mal var mı? Varsa <strong>Ambar Yerleştirmeleri</strong>’nde açık belgeye bakın.</li>
<li><strong>Ambar Toplamaları</strong> ve <strong>Raf İçerikleri</strong>, Raf Kodu = H1|H2|H3: toplanmış ama sevk edilmemiş mal var mı?</li>
<li><strong>Raf İçerikleri</strong>, Raf Kodu = AYARLAMA: miktar sıfır mı? Değilse yarım kalmış bir düzeltme vardır (5.3).</li>
<li><strong>Count Sheets</strong>: açık sayım var mı, kalan satırı var mı?</li>
<li><strong>Madde Hareketleri</strong>, tarih = bugün: günün giriş ve çıkışları terminalde yapılan işlerle uyuşuyor mu?</li>
</ol></section>
{BACK}</section>

<section id="sorun"><h2>7. Sorun giderme ve sık sorular</h2>
<table><thead><tr><th>Durum / soru</th><th>Ne yapın?</th></tr></thead><tbody>
<tr><td>Terminalde mal kabulü kaydettim ama BC’de stok artmadı.</td><td>Ambar Mal Kabulleri’nde belgenin hâlâ açık olup olmadığına bakın. Açıksa kayıt BC’ye ulaşmamıştır; terminalde belgeyi yenileyip durumunu görün. Kapandıysa Nakledilmiş Ambar Mal Kabulleri ve Madde Hareketleri’nde (Satınalma) kaydı bulun. Aynı belgeyi kontrol etmeden ikinci kez kaydetmeyin.</td></tr>
<tr><td>Mal kabul kaydedildi ama yerleştirme belgesi yok.</td><td>Ambar Yerleştirmeleri’nde kaynak belge numarasıyla arayın. Yoksa lokasyonda Yerleştirme Çalışma Sayfası kullanımı açık olabilir; Yerleştirme Çalışma Sayfası’ndan belge oluşturun ya da ambar sorumlusuna bildirin.</td></tr>
<tr><td>Satınalma siparişini BC’de doğrudan nakletmek istiyorum, izin vermiyor.</td><td>ELM4-WMS’te mal kabul zorunludur. Siparişi serbest bırakıp Ambar Mal Kabulü Oluştur ile belge oluşturun; teslim almayı terminalde yapın.</td></tr>
<tr><td>Madde Kartı’ndaki stok ile Raf İçerikleri toplamı farklı.</td><td>Farkın hangi rafta olduğunu Raf İçerikleri’nde bulun. AYARLAMA rafındaysa madde günlüğünde Ambar Ayarlamasını Hesapla çalıştırılıp nakledilmelidir (5.3). Başka bir raftaysa Ambar Hareketleri’nde o raf ve maddenin son kayıtlarını inceleyin.</td></tr>
<tr><td>Raf İçerikleri’nde bir raf eksi miktar gösteriyor.</td><td>Yönlendirilmiş lokasyonda raf normalde eksiye düşmez. Ambar Hareketleri’nde o rafın son kayıtlarını bulun ve destek ekibine bildirin; elle düzeltme yapmadan önce nedeni öğrenin.</td></tr>
<tr><td>Yeni bir maddeyi kabul edemiyorum: birim hatası.</td><td>Madde kartında Temel Ölçü Birimi boş olabilir (2.235 kartta boş). Kartta birimi (ör. ADET) seçin; gerekiyorsa Madde Birimleri’nde ek birimleri tanımlayın, sonra tekrar deneyin.</td></tr>
<tr><td>Terminal “… için ürün veya LP bulunamadı” diyor.</td><td>Okutulan barkod BC’deki bir madde numarasıyla eşleşmiyor ya da terminal başka bir ortama bağlı. Madde Kartı’nda numarayı arayın; terminalde Sand2010 · Element 4 Dizayn Müh. End. A.Ş. bağlantısını kontrol edin.</td></tr>
<tr><td>Yerleştirmede BC benim istediğim rafı önermiyor.</td><td>Öneri raf tipine göre yapılır; PICK tipli raflar (A, B, E) önerilmez. Terminalde koyacağınız rafı okutarak hedefi değiştirin ya da yerleştirmeden sonra Ad-Hoc Hareket yapın.</td></tr>
<tr><td>Ad-Hoc Hareket yaptım, Madde Hareketleri’nde göremiyorum.</td><td>Doğrudur. Raftan rafa taşıma stok miktarını değiştirmez; yalnız Ambar Hareketleri’nde Taşıma türünde iki satır oluşur.</td></tr>
<tr><td>Transfer Emri açmak istiyorum.</td><td>Element 4’te tek lokasyon var ve transit lokasyon tanımlı değil; lokasyonlar arası transfer bu kurulumda yapılmaz. Depo içi yer değişikliği için Ad-Hoc Hareket ya da Yönlendirilmiş hareket kullanın (4. bölüm).</td></tr>
<tr><td>İlk Sayım açılmıyor, “yönlendirilmiş” uyarısı çıkıyor.</td><td>İlk Sayım ELM4-WMS’te kullanılmaz. Sayım ekranını kullanın (5.4).</td></tr>
<tr><td>Terminalde “Sayım stoklara yalnız Business Central’den işlenir” uyarısı.</td><td>Terminalden işleme kapalı. Sorumlu, BC’de Count Sheet kartında <strong>Post</strong> ile işler (5.2).</td></tr>
<tr><td>Sayım işlendi ama AYARLAMA rafında miktar kaldı.</td><td>Sayımın ikinci adımı (fiziksel envanter günlüğü) tamamlanmamış olabilir. Madde Hareketleri’nde CNT- belge numarasıyla kayıt olup olmadığına bakın; yoksa destek ekibine bildirin. AYARLAMA rafına Ad-Hoc Hareket yapmayın.</td></tr>
<tr><td>Toplama başka bir operatörde kaldı.</td><td>BC’de Ambar Toplamaları’nda belgeyi açın, <strong>Assign to WMS Operator</strong> ile yeni operatöre verin ya da <strong>Clear Assignment</strong> ile atamayı kaldırın.</td></tr>
<tr><td>BC’de bir belgeyi elle düzelteyim mi?</td><td>Terminalde işlenmekte olan bir belgeyi BC’de değiştirmeyin ya da silmeyin. Önce terminalde işi bitirin veya bırakın, sonra ambar sorumlusuyla birlikte düzeltin.</td></tr>
<tr><td>BCWMS sayfasını aramada bulamıyorum.</td><td>Sayfayı İngilizce adıyla arayın (ör. Count Sheets, License Plates) ya da Warehouse Manager rol merkezinden açın. Sayfa hiç görünmüyorsa kullanıcınızın BCWMS izin kümesi eksik olabilir; yöneticinize bildirin.</td></tr>
</tbody></table>
<p>Çözülmeyen durumlarda terminal ekranının görüntüsünü, BC’de baktığınız sayfanın adını ve belge/madde numarasını destek ekibine iletin.</p>
<div class="info"><strong>Bu kılavuzda doğrulanamayan kurulum noktaları:</strong> Lokasyon kartındaki varsayılan mal kabul ve sevkiyat rafları, Yerleştirme Çalışma Sayfası Kullan ve çapraz sevk ayarları, raf tiplerinin bayrakları, yerleştirme şablonu, BCWMS kurulumundaki Terminal Count Posting değeri ve kullanıcıların ambar çalışanı tanımları API ile okunamadığı için genel anlatıldı. Eğitimden önce bu ayarlar BC’de Lokasyon Kartı, Raf Tipleri, Ambar Çalışanları ve Advanced WMS Setup sayfalarından kontrol edilmelidir.</div>
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
    stem = 'KITOKO-Element4-BC-Depo-ve-Stok-Kilavuzu'
    path = OUT / f'{stem}.html'
    path.write_text(page('Business Central Depo ve Stok Kılavuzu', 'Kitoko / Element 4 · Business Central',
                         'El terminalinde yapılan mal kabul, yerleştirme, sevkiyat, raf hareketi ve sayım işlemlerinin '
                         'Business Central’daki karşılığını, kaydın hangi sayfada görüldüğünü ve nasıl kontrol edileceğini anlatır.',
                         TOC, BODY,
                         f'Hazırlayan: DynamicsOps · {DATE} · BCWMS Kitoko {VERSION}. Azure DevOps #2695. '
                         'Kurulum bilgileri Sand2010 · Element 4 Dizayn Müh. End. A.Ş. şirketinden 27.10.2026’da okunmuştur.'),
                    encoding='utf-8')
    render_pdf(path, OUT / f'{stem}.pdf')
    print(path)


if __name__ == '__main__':
    main()
