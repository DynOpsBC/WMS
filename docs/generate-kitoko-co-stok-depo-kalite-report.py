#!/usr/bin/env python3
"""Kitoko Stok, Depo ve Kalite — Kullanım Kılavuzu ve Karşılama Raporu (27 Ekim 2026).

Kapsam: Azure DevOps Epic 1045 "Stok, Depo ve Kalite — Kitoko", Feature 1199/1200/1201,
User Story 712–719, 1296, 1297 (metinler: Kitoko/outputs/kitoko-stok-depo-kalite-20261027/work-items.json).
Şirket: Kitoko Aydınlatma ve Müh. A.Ş.

Durum bilgileri BC'den yalnız GET ile okunmuştur (Sand2010 ve DemoSandbox/DemoV2; Production'a
istek atılmamıştır). Ayrıntılı bulgular: kitoko-setup-findings.json.
Ürün özellikleri BCWMS AL kaynağından (al/src) ve Android kaynağından (android/) okunmuştur.

Çıktılar:
  output/kilavuzlar-kitoko/KITOKO-Stok-Depo-Kalite-Kilavuz-ve-Karsilama-Raporu.html + .pdf
  Kitoko/outputs/kitoko-stok-depo-kalite-20261027/comment-drafts.json (DevOps yorum TASLAKLARI; gönderilmez)

CSS, page(), BACK ve render_pdf generate-kitoko-guides.py dosyasından aynen kopyalanmıştır
(o dosya import edildiğinde ekran görüntülerini okuduğu için import edilmez). Yalnız rapor
rozetleri için küçük bir ek stil (EXTRA_CSS) eklenmiştir.
"""
import html
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/kilavuzlar-kitoko'
VERSION = '1.14.201-kitoko'
DATE = '27 Ekim 2026'
DRAFTS = Path('/Users/kaanodabas/Desktop/Kitoko/outputs/kitoko-stok-depo-kalite-20261027/comment-drafts.json')
STEM = 'KITOKO-Stok-Depo-Kalite-Kilavuz-ve-Karsilama-Raporu'
TITLE = 'Kitoko Stok, Depo ve Kalite — Kullanım Kılavuzu ve Karşılama Raporu'
REPORT_NAME = 'Kitoko Stok, Depo ve Kalite Kılavuz ve Karşılama Raporu'

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

# Rapor rozetleri ve küçük tablo yardımcıları (ek stil; temel CSS değiştirilmedi).
EXTRA_CSS = """
.badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;font-weight:700;line-height:1.5;white-space:nowrap}
.b-ok{background:#dff3e6;color:#1d6b3a}.b-setup{background:#e6effb;color:#28518f}.b-dev{background:#fde8e4;color:#9c2f1c}.b-dec{background:#fff1d6;color:#8a5a00}
table.sum td,table.sum th{font-size:13px;padding:7px 8px}table.sum td:first-child{white-space:nowrap}table.sum .badge{white-space:normal;border-radius:8px}table.kv td:first-child{width:32%;font-weight:700;color:#2d4a5e}
h4{font-size:15px;margin:18px 0 6px;color:#0f5f5b}
@media print{table.sum{break-inside:auto}table.sum tr{break-inside:avoid}}
"""


def page(title, eyebrow, lead, toc, body, foot):
    links = ''.join(f'<a class="{"sub" if sub else ""}" href="#{a}">{html.escape(t)}</a>' for a, t, sub in toc)
    return (f'<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)}</title><style>{CSS}{EXTRA_CSS}</style></head><body><div class="wrap">'
            f'<nav class="toc"><b>İçindekiler</b>{links}</nav><main id="top"><div class="eyebrow">{eyebrow}</div>'
            f'<h1>{html.escape(title)}</h1><p class="meta">{DATE} · BCWMS Kitoko {VERSION}</p><p class="lead">{lead}</p>'
            f'{body}<footer>{foot}</footer></main></div></body></html>')


BACK = '<p class="back"><a href="#top">↑ Başa dön</a></p>'


def render_pdf(html_path, pdf_path):
    script = ("import {{ chromium }} from '{pw}';const b=await chromium.launch({{headless:true,channel:'chrome'}});"
              "const p=await b.newPage();await p.goto('{url}');await p.pdf({{path:'{pdf}',format:'A4',printBackground:true,"
              "margin:{{top:'14mm',right:'13mm',bottom:'14mm',left:'13mm'}}}});await b.close();").format(
        pw=(ROOT / 'web/node_modules/@playwright/test/index.mjs').as_uri(), url=html_path.as_uri(), pdf=pdf_path)
    subprocess.run(['node', '--input-type=module', '-e', script], check=True)


# ---------------------------------------------------------------- ortak tanımlar
AQ = '<kbd>Alt</kbd>+<kbd>Q</kbd>'
G_TERM = 'KITOKO-El-Terminali-Stok-Hareketleri-Kilavuzu'
G_COUNT = 'KITOKO-Sayim-ve-Etiket-Kilavuzu'
G_BC = 'KITOKO-BC-Depo-ve-Stok-Kilavuzu'
GUIDE_TITLES = {G_TERM: 'El Terminali Stok Hareketleri Kılavuzu (Kitoko)',
                G_COUNT: 'Sayım ve Etiket Kılavuzu (Kitoko)',
                G_BC: 'BC Depo ve Stok Kılavuzu (Kitoko)'}

STATUS = {
    'ok': ('b-ok', 'Karşılanıyor ve doğrulandı'),
    'setup': ('b-setup', 'Çözüm mevcut, Kitoko şirketinde kurulum gerekli'),
    'partial': ('b-dev', 'Kısmen mevcut, geliştirme gerekli'),
    'dev': ('b-dev', 'Geliştirme gerekli'),
    'decision': ('b-dec', 'Karar gerekli'),
    'setup-report': ('b-dec', 'Çözüm mevcut, kurulum gerekli; detay rapor kararı/geliştirmesi gerekli'),
    'setup-decision': ('b-dec', 'Çözüm mevcut (standart), kurulum gerekli; yöntem kararı gerekli'),
}


def badge(key):
    cls, label = STATUS[key]
    return f'<span class="badge {cls}">{html.escape(label)}</span>'


def gref(stem, section):
    return f'<a href="{stem}.html">{html.escape(GUIDE_TITLES[stem])}</a> → {html.escape(section)}'


def ul(items):
    return '<ul>' + ''.join(f'<li>{i}</li>' for i in items) + '</ul>'


def steps(items):
    return '<ol class="steps">' + ''.join(f'<li>{i}</li>' for i in items) + '</ol>'


def test_table(rows):
    body = ''.join(f'<tr><td>{n}</td><td>{s}</td><td>{e}</td></tr>' for n, (s, e) in enumerate(rows, 1))
    return f'<table><thead><tr><th>#</th><th>Test adımı</th><th>Beklenen sonuç</th></tr></thead><tbody>{body}</tbody></table>'


# ---------------------------------------------------------------- story içerikleri
# Her story: gereksinim, çözüm yöntemi, Kitoko'daki durum, kullanıcı adımları, test, açık iş.
STORIES = {}

STORIES['712'] = dict(
    code='KIT-008', feature='1199', anchor='s712',
    short='Ambar → Bölge → Konum (raf) kırılımıyla lokasyon bazlı stok',
    status='setup',
    method_short='BCWMS + Standart BC (Location / Zone / Bin)',
    open_short='Kitoko şirketinde lokasyon, bölge, raf tipi ve raflar kurulmalı; hangi depoların raf zorunlu/yönlendirilmiş olacağı kararı.',
    req=('Kitoko depolarında stok <strong>ambar (lokasyon) → bölge → konum (raf)</strong> kırılımıyla tutulacak ve her stok hareketi bu üç bilgiyle kaydedilecek. '
         'Süreç sahibi Tedarik Zinciri (Depo). <strong>Kabul kriteri:</strong> Her stok hareketinin ambar, bölge ve konum bilgisiyle kaydedilmesi.'),
    method=('<p><strong>Standart BC + DynamicsOps Warehouse Management App (BCWMS el terminali).</strong> BC’de ambar = <strong>Lokasyon</strong> (Location), bölge = <strong>Bölge</strong> (Zone), konum = <strong>Raf</strong> (Bin). '
            'Bölge kırılımı BC’de yalnız <strong>Yönlendirilmiş Yerleştirme ve Toplama</strong> (Directed Put-away and Pick) açık lokasyonlarda kullanılır; bu ayar açıkken <strong>Raf Zorunlu</strong>, <strong>Mal Kabul / Yerleştirme / Toplama / Sevkiyat Gerekli</strong> ayarları da açılır. '
            'Böylece her ambar hareketi (Warehouse Entry) lokasyon, bölge ve raf koduyla oluşur. Yerleştirme ve toplama önerileri <strong>Raf Tipi</strong> (RECEIVE, PUTPICK, QC, SHIP) ve raf/bölge sıralamasıyla (Bin Ranking, Zone Ranking) yönlendirilir.</p>'
            '<p>El terminali (BCWMS) mal kabul, yerleştirme, toplama, sevkiyat, raftan rafa taşıma ve sayımı barkodla yürütür; raf ve LP etiketleri terminalden basılır. Geliştirme gerekmez; iş <strong>kurulum ve ana veri</strong> işidir.</p>'),
    state=('<p><strong>Kitoko Aydınlatma ve Müh. A.Ş. (Sand2010):</strong> BCWMS uygulaması ortamda yüklü ve API yanıt veriyor; ancak şirkette <strong>hiç lokasyon, bölge ve raf yok</strong> (lokasyon 0, bölge 0, raf 0), <strong>madde kartı yok</strong> (0), el terminali ve terminal kullanıcısı tanımlı değil (0 / 0). Bu gereksinim Kitoko şirketinde bugün <strong>karşılanmıyor</strong>; kurulum bekliyor.</p>'
           '<p><strong>Demo şirket (DemoSandbox · KITOKO-TR-DEMO-V1):</strong> Gereksinimin örnek kurgusu burada var. <strong>KITWMS — “Kitoko Gelişmiş Depo (Ambar-Bölge-Raf)”</strong> lokasyonu raf zorunlu ve yönlendirilmiş; 6 bölge ve 7 raf tanımlı:</p>'
           '<table><thead><tr><th>Bölge</th><th>Raf tipi</th><th>Raflar</th><th>Amaç</th></tr></thead><tbody>'
           '<tr><td>KABUL</td><td>RECEIVE</td><td>K-01</td><td>Mal kabul rampası</td></tr>'
           '<tr><td>KALITE</td><td>QC</td><td>Q-01</td><td>Kalite kontrol / karantina bekleme</td></tr>'
           '<tr><td>DEPO-A</td><td>PUTPICK</td><td>A-01-01, A-01-02</td><td>Depolama A (raf blokları)</td></tr>'
           '<tr><td>DEPO-B</td><td>PUTPICK</td><td>B-01-01</td><td>Depolama B (yedek)</td></tr>'
           '<tr><td>SEVK</td><td>SHIP</td><td>S-01</td><td>Sevkiyat hazırlık</td></tr>'
           '<tr><td>AYAR</td><td>QC</td><td>AYAR-01</td><td>Sayım farkı / ayarlama</td></tr></tbody></table>'
           '<p>Demo şirketteki diğer yedi lokasyon (ANA, BVDEPO, IHRACKAYIT, MERKEZDEP, MUSTERI, TRANSIT, TRANSITTIC) <strong>raf zorunlu değil</strong>; bu lokasyonlardaki hareketler raf ve bölge bilgisi taşımaz. Demo şirketteki 111 madde hareketinin çoğu lokasyonsuzdur; KITWMS’te yalnız 1 satınalma girişi ve 1 ambar hareketi (K-01 / KABUL) var. Terminal KITOKO-01 ve iki terminal yöneticisi operatör yalnız bu demo şirkette tanımlı.</p>'),
    user=(steps([
        f'<strong>BC’de yapıyı görün:</strong> {AQ} → <strong>Lokasyonlar</strong> → depo kartı; <strong>Bölgeler</strong> (Zones) ve <strong>Raflar</strong> (Bins) eylemleriyle bölge ve rafları açın. Raf tiplerinin bayrakları <strong>Raf Tipleri</strong> (Bin Types) sayfasındadır.',
        '<strong>Raf etiketlerini basın:</strong> terminalde <strong>Etiket Çıkar → Raf Etiketi</strong> sekmesinde lokasyonu ve alanı (bölgeyi) seçip tek raf, toplu raf veya alan etiketi basın.',
        '<strong>Mal kabul ve yerleştirme:</strong> terminalde <strong>Mal Kabul</strong> ile malı kabul rafına (ör. K-01) alın, <strong>Yerleştirme</strong> ile hedef rafı okutarak stok rafına kaldırın.',
        '<strong>Raftan rafa taşıma:</strong> <strong>Ad-Hoc Hareket</strong> (belgesiz) veya <strong>Yönlendirilmiş</strong> (BC’de hazırlanmış taşıma) ekranını kullanın.',
        f'<strong>Kontrol:</strong> terminalde <strong>Bin Sorgu</strong> ile rafın içeriğini, <strong>Ambar Hareketleri</strong> ile geçmişi görün. BC’de {AQ} → <strong>Ambar Hareketleri</strong> (Warehouse Entries) sayfasında <strong>Lokasyon Kodu</strong>, <strong>Bölge Kodu</strong>, <strong>Raf Kodu</strong> sütunlarına bakın; <strong>Raf İçerikleri</strong> (Bin Contents) anlık stoğu raf bazında verir.',
    ]) + '<p>Ayrıntılı ekran adımları: ' + gref(G_TERM, 'Mal kabul, Yerleştirme, Raflar / depolar arası transfer, Barkodla sorgulama') + '; ' + gref(G_BC, 'Depo kurulumu, Alanlar ve raflar, Ambar belgeleri') + '; raf etiketi: ' + gref(G_COUNT, 'Raf ve alan etiketi') + '.</p>'),
    tests=[
        ('Kitoko şirketinde yönlendirilmiş lokasyonun kartını açın.', 'Raf Zorunlu ve Yönlendirilmiş Yerleştirme ve Toplama açık; Mal Kabul/Yerleştirme/Toplama/Sevkiyat Gerekli açık.'),
        ('Bölgeler ve Raflar sayfalarını açın.', 'Kabul, kalite, depolama, sevkiyat ve ayarlama bölgeleri ile her bölgenin rafları tanımlı; her rafın bölge kodu ve raf tipi dolu.'),
        ('Serbest bırakılmış bir satınalma siparişinden terminalde mal kabul yapın, ardından yerleştirmeyi stok rafına kaydedin.', 'Ambar Hareketleri’nde kabul rafına artı, ardından kabul rafından eksi / stok rafına artı kayıtları; her satırda Lokasyon, Bölge ve Raf Kodu dolu.'),
        ('Terminalde Ad-Hoc Hareket ile malı başka bir rafa taşıyın.', 'Ambar Hareketleri’nde hareket türü Taşıma; kaynak ve hedef raf satırlarında bölge ve raf dolu.'),
        ('Satış siparişinden ambar sevkiyatı ve toplama oluşturup terminalde toplayın ve sevk edin.', 'Toplama stok rafından sevk rafına, sevkiyat sevk rafından eksi kayıt; tümünde lokasyon/bölge/raf dolu.'),
        ('Ambar Hareketleri’nde Bölge Kodu veya Raf Kodu boş satır olup olmadığını filtreleyin (yalnız stok tutulan lokasyonlar).', 'Boş satır yok. Raf zorunlu olmayan bir lokasyonda stok tutuluyorsa test başarısızdır; o lokasyon kapsam dışı bırakılmalı veya raf zorunlu yapılmalıdır.'),
    ],
    open=[
        'Kitoko şirketinde (Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.) lokasyon, bölge, raf tipi ve raf ana verisinin kurulması (demo KITWMS kurgusu örnek alınabilir).',
        '<strong>Karar:</strong> Kitoko’nun hangi fiziksel depoları raf zorunlu + yönlendirilmiş olacak? Demo şirketteki ANA, MERKEZDEP, BVDEPO, IHRACKAYIT, MUSTERI lokasyonları rafsızdır; bu depolarda stok tutulursa kabul kriteri sağlanamaz.',
        'Gerçek bölge/raf listesi ve raf etiket planının depo ekibinden alınması (raf kod yapısı, raf sıralaması).',
        'Kitoko şirketinde BCWMS terminali, terminal kullanıcıları, kullanıcı profilleri ve etiket yazıcısının tanımlanması.',
        'Madde kartlarının (ve birimlerin) Kitoko şirketine aktarılması; bugün 0 madde.',
    ],
)

STORIES['713'] = dict(
    code='KIT-009', feature='1199', anchor='s713',
    short='Mal kabul + kalite kontrol zorunluluğu (Receipt → QC → Onay/Red)',
    status='partial',
    method_short='BCWMS Kalite Denetimi (GKK) + Standart BC Warehouse Receipt; eksikler geliştirme',
    open_short='Kalite emrinin mal kabulde otomatik oluşması ve QC bitmeden mal kabulün kapanmaması geliştirilmeli; BCWMS kalite emri mi MS Quality Management mı kararı.',
    req=('Satınalma mal kabulünden sonra kalite kontrol adımı zorunlu olacak: mal kabul → kalite kontrol → onay veya red. '
         '<strong>Kabul kriteri:</strong> Kalite kontrol adımı tamamlanmadan mal kabulün kapatılamaması.'),
    method=('<p><strong>Standart BC Ambar Mal Kabulü + BCWMS Kalite Denetimi (GKK).</strong> BCWMS’te <strong>Kalite Emri</strong> (Quality Order, tablo 72254) vardır: kaynak (mal kabul/üretim/sevkiyat/iade), madde, miktar, otomatik numune miktarı (~%10, en az 1, en çok 20), lokasyon, raf, LP, durum (Açık / Devam Ediyor / Geçti / Kaldı / Kapalı), denetçi, sonuç notu, red sebebi ve karantina rafı alanlarını taşır. '
            'Terminaldeki <strong>Kalite Denetimi</strong> ekranında açık emirler listelenir; denetçi notu, red sebebini ve karantina rafını girip <strong>KABUL</strong> veya <strong>RED</strong> verir.</p>'
            '<p>Bugünkü üründe kalite emri ile depo akışı arasındaki tek bağ <strong>yerleştirmededir</strong>: bir LP’nin açık kalite emri varsa terminal o LP’nin yerleştirmesini engeller (“… LP numarasının kalite kontrolü henüz tamamlanmadı. LP karantina gözünde kalmalıdır.”); emir reddedildiyse LP yalnız emirdeki karantina rafına yerleştirilebilir.</p>'
            '<div class="warn"><strong>Üründe olmayanlar (kaynak kodda doğrulandı):</strong> (1) Mal kabul kaydında kalite emri <strong>otomatik oluşmuyor</strong>; emir yalnız API ile (createOrder) açılabiliyor. (2) “Kalite tamamlanmadan mal kabul kapatılamaz” kuralı yok; ambar mal kabulü kalite emrinden bağımsız nakledilir. (3) Kontrol LP’siz satırlarda çalışmaz. (4) Microsoft Quality Management köprüsü (lot blokajı, toplama/taşıma engeli) BC 28 gerektirdiği için kodda devre dışıdır. (5) BC’de kalite emirleri için bir liste sayfası yok; emirler terminalden ve OData (DOPSWHSQualityOrders) ile görülür.</div>'
            '<p>Bu yüzden çözüm: mal kabulde (madde/tedarikçi/madde kategorisi kuralına göre) kalite emrinin otomatik açılması, kabul rafından çıkışın (yerleştirmenin) emir tamamlanana kadar LP’li ve LP’siz tüm satırlarda engellenmesi, BC’de Kalite Emirleri sayfası ve red sonrası iade/hurda akışı için <strong>geliştirme</strong> gerekir. Alternatif: BC 28 ile Microsoft Quality Management (Kalite Denetimi şablonları, otomatik denetim kuralları, lot blokajı) — <strong>karar</strong> gerekir.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Kalite emri 0; kalite bölgesi/karantina rafı yok (lokasyon ve raf hiç yok); terminal ve kullanıcı yok. Kullanıcı profillerinde kalite filtresi (Tümü / Yalnız Açık) varsayılan değerlerle duruyor. Gereksinim Kitoko şirketinde <strong>karşılanmıyor</strong>.</p>'
           '<p><strong>Demo (DemoSandbox · KITOKO-TR-DEMO-V1):</strong> KITWMS’te KALITE bölgesi ve Q-01 karantina rafı var; kalite emri yok (0). Kalite emirleri OData’da yayınlı (DOPSWHSQualityOrders, 0 kayıt). Uçtan uca QC akışı test edilmedi.</p>'
           '<p>Microsoft Quality Management uygulamasının ortamlarda kurulu olup olmadığı bu çalışmada <strong>doğrulanmadı</strong>.</p>'),
    user=(steps([
        'Terminalde <strong>Mal Kabul</strong> ile malı kabul edin; LP kullanıyorsanız <strong>LP Başlat</strong> ile LP açın ve etiketini basın.',
        '<strong>Bugün:</strong> kalite emri otomatik açılmaz; kalite sorumlusu emri açar (geliştirme sonrası mal kabulde kendiliğinden açılacak).',
        'Terminalde <strong>Kalite Denetimi</strong> ekranını açın. <strong>Açık</strong> filtresinde emirler listelenir (madde, adet, numune, kaynak). Emre dokunun.',
        'Numuneyi kontrol edin, <strong>Notlar</strong> alanını doldurun. Uygunsa <strong>KABUL</strong>; uygun değilse <strong>RED sebebi</strong> ve <strong>Karantina Bin</strong> (ör. Q-01) girip <strong>RED</strong>’e dokunun.',
        '<strong>KABUL</strong> sonrası <strong>Yerleştirme</strong> ekranında LP’yi stok rafına kaldırın. <strong>RED</strong> sonrası LP yalnız karantina rafına yerleştirilebilir; başka rafa yerleştirmede terminal hata verir.',
        f'BC’de: mal kabul {AQ} → <strong>Nakledilmiş Ambar Mal Kabulleri</strong>; yerleştirme <strong>Kayıtlı Yerleştirmeler</strong>; LP geçmişi <strong>LP İzlenebilirlik</strong> sayfası. Kalite emirleri bugün BC’de liste sayfası olmadığı için terminalden izlenir.',
    ]) + '<p>Ayrıntılı ekran adımları: ' + gref(G_TERM, 'Mal kabul, Yerleştirme') + '; ' + gref(G_BC, 'Ambar belgeleri — Mal kabul, Yerleştirme') + '.</p>'),
    tests=[
        ('Kalite kontrolü zorunlu bir madde için mal kabul yapın.', '(Geliştirme sonrası) Mal kabul kaydında kalite emri kendiliğinden açılır; numune miktarı hesaplanır, mal kabul/karantina rafında bekler.'),
        ('Kalite emri açıkken yerleştirmeyi kaydetmeyi deneyin (LP’li ve LP’siz iki satır).', 'İki satırda da yerleştirme engellenir: “kalite kontrolü henüz tamamlanmadı”. Bugünkü üründe yalnız LP’li satır engellenir.'),
        ('Mal kabul belgesini/sürecini kapatmayı deneyin (yerleştirme tamamlanmadan, kalite açıkken).', 'Kapatılamaz (kabul kriteri). Bugünkü üründe karşılığı yok — geliştirme.'),
        ('Terminalde emri KABUL edin, yerleştirmeyi stok rafına kaydedin.', 'Emir durumu Geçti; yerleştirme kaydedilir; Ambar Hareketleri’nde stok rafına artı.'),
        ('İkinci bir emri RED edin (red sebebi + karantina rafı) ve LP’yi stok rafına yerleştirmeyi deneyin.', 'Hata: yalnız karantina rafına yerleştirilebilir. Karantina rafına yerleştirme kaydedilir.'),
    ],
    open=[
        '<strong>Geliştirme:</strong> mal kabulde kural bazlı (madde / madde kategorisi / tedarikçi) otomatik kalite emri.',
        '<strong>Geliştirme:</strong> kalite emri tamamlanmadan kabul rafından çıkışın (yerleştirme, taşıma) LP’siz satırlarda da engellenmesi ve “mal kabul kapatılamaz” kuralı.',
        '<strong>Geliştirme:</strong> BC’de Kalite Emirleri liste/kart sayfası (bugün yalnız terminal ve OData).',
        '<strong>Karar:</strong> BCWMS kalite emri ile mi, BC 28 + Microsoft Quality Management ile mi ilerlenecek (köprü kodu hazır, BC 28 bekliyor)? Ortamlarda MS QM kurulumunun kontrolü.',
        '<strong>Karar:</strong> Hangi madde/tedarikçi gruplarında kalite kontrolü zorunlu; numune kuralı (%10 varsayılan) uygun mu; red sebebi kod listesi.',
        'Kitoko şirketinde KALITE bölgesi ve karantina rafı kurulumu (KIT-008 ile birlikte).',
    ],
)

STORIES['714'] = dict(
    code='KIT-010', feature='1199', anchor='s714',
    short='Kalite onayı olmadan kullanılabilir stok olmaması (QC lokasyon / blocked stock)',
    status='dev',
    method_short='Standart BC QC rafı + lot blokajı; otomatik geçişler için geliştirme',
    open_short='QC rafı/lot blokajı kurgusunun seçilmesi ve satış/üretim/montaj belgelerinde kullanım engelinin geliştirilip test edilmesi.',
    req=('Kalite onayı verilmemiş malzeme kullanılabilir stok sayılmayacak. '
         '<strong>Kabul kriteri:</strong> Kalite onayı verilmeyen malzemenin satış ve üretim belgelerinde kullanılamaması.'),
    method=('<p><strong>Standart BC yapı taşları:</strong> (a) Yönlendirilmiş lokasyonda <strong>QC raf tipli</strong> (toplama işaretsiz) bir kalite/karantina bölgesi: bu raftaki stok BC’nin toplama önerisine girmez, dolayısıyla ambar toplaması ile satış sevkiyatına veya üretim/montaj tüketimine çekilemez. '
            '(b) Lot takipli maddelerde <strong>Lot No. Bilgi Kartı → Engellendi</strong> (Blocked): engelli lot satış, üretim tüketimi, montaj ve transfer kayıtlarında kullanılamaz. (c) Ayrı bir karantina lokasyonu da alternatiftir.</p>'
            '<p><strong>BCWMS katkısı:</strong> Kalite emri açıkken LP’nin stok rafına yerleştirilmesini engeller ve reddedilen LP’yi karantina rafına zorlar (KIT-009). '
            'Kalite emri onaylandığında lot blokajının kalkması / reddedildiğinde konması, toplama ve taşımada kalite engeli bugün <strong>yok</strong> (MS Quality Management köprüsü devre dışı).</p>'
            '<div class="warn">QC rafındaki stok BC’de maddenin <strong>Stok</strong> toplamında görünür; satış siparişi satırı girilebilir ve raf zorunlu olmayan bir lokasyonda rezervasyon yapılabilir. Kabul kriterinin tam karşılanması için QC stoğunun yönlendirilmiş lokasyonda tutulması veya lot blokajı gerekir; satış ve üretim belgelerinde engel ayrıca test edilmelidir.</div>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Lokasyon, bölge, raf ve madde olmadığı için QC rafı ya da lot blokajı kurgusu <strong>yok</strong>. Karşılanmıyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> KITWMS’te KALITE bölgesi (QC raf tipi) ve Q-01 rafı var; QC raf tipinin toplama bayrağı API’den okunamadı (Raf Tipleri sayfasından kontrol edilmeli). Lot takipli iki test maddesi (ZZ-KIT-LOT, ZZ-KIT-ASM) var; lot blokajı denenmedi. Satış/üretim belgesinde engel testi yapılmadı.</p>'),
    user=(steps([
        'Mal kabul edilen mal kabul rafında veya kalite (karantina) rafında bekler; kalite onayı gelene kadar yerleştirmeyin.',
        f'Lot takipli maddede kalite bekliyorsa BC’de {AQ} → <strong>Lot No. Bilgileri</strong> → ilgili lot → <strong>Engellendi</strong> işaretini açın (geliştirme sonrası kalite emri ile otomatik olacak).',
        'Terminalde <strong>Kalite Denetimi</strong> ekranında KABUL verildiğinde malı <strong>Yerleştirme</strong> veya <strong>Ad-Hoc Hareket</strong> ile stok (PUTPICK) rafına taşıyın; lot engelini kaldırın.',
        'RED verildiğinde mal karantina rafında kalır; iade veya hurda kararı INV-010 ve satınalma iade akışıyla yürür.',
        f'Kontrol: terminalde <strong>Ürün Sorgu</strong> malın hangi rafta olduğunu gösterir; BC’de <strong>Raf İçerikleri</strong>’nde Bölge = KALITE filtresiyle karantinadaki stoğu görün.',
    ]) + '<p>Ayrıntı: ' + gref(G_TERM, 'Yerleştirme, Raflar arası transfer, Ürün Sorgu') + '; ' + gref(G_BC, 'Alanlar ve raflar, Toplama ve sevkiyat') + '.</p>'),
    tests=[
        ('Kalite emri açık, malı QC rafında olan bir madde için satış siparişi girin, ambar sevkiyatı ve toplama oluşturun.', 'Toplama QC rafından satır önermez (“toplanacak bir şey yok” / eksik miktar); mal sevk edilemez.'),
        ('Aynı madde için montaj veya üretim emri açıp tüketim/toplamayı deneyin.', 'QC rafındaki miktar tüketime/toplamaya gelmez.'),
        ('Lot takipli maddede lotu Engellendi yapın; satış sevkiyatında ve üretim tüketiminde o lotu seçmeyi deneyin.', 'Kayıt hata ile durur: lot engelli.'),
        ('Kalite onayı verin; malı stok rafına taşıyın, lot engelini kaldırın; tekrar toplayın.', 'Toplama önerisi gelir, sevkiyat ve tüketim kaydedilir.'),
        ('Raf zorunlu olmayan bir lokasyonda aynı senaryoyu deneyin.', 'Engel yoksa kabul kriteri sağlanmaz — kalite bekleyen stok bu lokasyonlarda tutulmamalıdır.'),
    ],
    open=[
        '<strong>Karar:</strong> Engelleme yöntemi: QC rafı (yönlendirilmiş lokasyon) mu, ayrı karantina lokasyonu mu, lot blokajı mı (lot takipli maddeler)?',
        '<strong>Geliştirme:</strong> Kalite emri sonucu ile lot blokajı ve raf geçişinin otomatik bağlanması; toplama/taşıma kayıtlarında kalite engeli (MS QM köprüsü BC 28 ile ya da BCWMS kalite emri üzerinden).',
        'Kitoko şirketinde kalite bölgesi, QC raf tipi (toplama kapalı) ve karantina raflarının kurulması.',
        'UAT: satış ve üretim/montaj belgelerinde engel testinin anahtar kullanıcı ile yapılması.',
    ],
)

STORIES['1296'] = dict(
    code='INV-009', feature='1200', anchor='s1296',
    short='Montaj/hızlı üretim çıkışında zorunlu son kontrol (final inspection)',
    status='dev',
    method_short='Standart BC Montaj Emri + BCWMS Montaj ekranı; son kontrol adımı geliştirme',
    open_short='Montaj emrine son kontrol onayı ve “onaysız tamamlanamaz” kuralı geliştirilmeli; montaj emri mi üretim emri mi kararı.',
    req=('Montaj / hızlı üretim hattı çıkışında zorunlu bir son kontrol (final inspection) adımı iş emrine eklenecek. '
         '<strong>Kabul kriteri:</strong> Son kontrol onayı olmadan montaj iş emrinin tamamlanamaması.'),
    method=('<p><strong>Standart BC Montaj Emri (Assembly Order) + BCWMS terminal Montaj ekranı.</strong> Terminal montaj emrinin bileşen tüketimini ve mamul çıktısını kaydeder (BCWMS AssemblyMgmt). '
            'Standart BC montaj emrinde ve BCWMS montaj akışında <strong>son kontrol adımı yoktur</strong>; BCWMS kalite emrinin kaynak tipleri arasında “Üretim” vardır ama montaj kaydına bağlı bir engel yoktur.</p>'
            '<p>Çözüm için <strong>geliştirme</strong> gerekir: montaj emrine “Son Kontrol” durumu/onayı (veya montaj çıktısı için otomatik kalite emri), onay yoksa montaj kaydının (Post) ve terminalden çıktı bildiriminin engellenmesi. Alternatif: BC 28 Microsoft Quality Management’ın montaj/üretim çıktısı denetim kuralları — karar gerekir. '
            'Hızlı üretim hattı üretim emri (Production Order) ile yürüyorsa standart BC’de rota adımına kalite adımı eklenebilir; ancak “onaysız tamamlanamaz” kuralı yine geliştirme ister.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Montaj emri 0, madde ve montaj ürün reçetesi yok. Karşılanmıyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> Montaj emri MN000001 (KTST-KIT01 “Armatür Montaj Paketi”, ANA lokasyonu, 5 adet, 2 kalan, Serbest Bırakıldı) var; 3 adet çıktı ve tüketimi kaydedilmiş (PM000001). Son kontrol adımı yok; montaj kontrolsüz tamamlanabiliyor. Lot takipli test mamulü ZZ-KIT-ASM tanımlı (stok 0).</p>'),
    user=(steps([
        f'BC’de {AQ} → <strong>Montaj Emirleri</strong> → emri açın, bileşenleri ve miktarı kontrol edin, <strong>Serbest Bırak</strong>.',
        'Terminalde <strong>Montaj</strong> ekranında emri seçin; bileşen tüketimini ve mamul çıktı miktarını girin.',
        '<strong>Geliştirme sonrası:</strong> çıktıdan önce son kontrol onayı istenir (Kalite Denetimi → KABUL/RED). Onay yoksa terminal ve BC kayıt düğmesi hata verir.',
        f'BC’de sonucu {AQ} → <strong>Nakledilmiş Montaj Emirleri</strong> ve <strong>Madde Hareketleri</strong>’nde (Montaj Çıktısı / Montaj Tüketimi) görün.',
    ]) + '<p>Ayrıntı: ' + gref(G_TERM, 'Üretime malzeme çıkışı / Montaj') + '; ' + gref(G_BC, 'Madde hareketleri') + '.</p>'),
    tests=[
        ('Son kontrol onayı verilmemiş bir montaj emrinin çıktısını terminalden ve BC’den kaydetmeyi deneyin.', 'Kayıt engellenir: son kontrol onayı yok. (Bugün engel yok — geliştirme.)'),
        ('Son kontrolü KABUL ile onaylayın ve kaydı tekrarlayın.', 'Montaj nakledilir; Montaj Çıktısı madde hareketi oluşur; kontrol kaydı (denetçi, tarih, sonuç) emre bağlıdır.'),
        ('Son kontrolü RED ile sonuçlandırın.', 'Montaj tamamlanamaz; hata kaydı INV-010 akışına (parti/seri + iade/hurda) bağlanır.'),
    ],
    open=[
        '<strong>Karar:</strong> Kitoko montaj/hızlı üretim hattı BC’de Montaj Emri ile mi, Üretim Emri ile mi yürüyecek?',
        '<strong>Geliştirme:</strong> Montaj emrinde son kontrol onayı ve onaysız kayıt engeli (BC + terminal Montaj ekranı).',
        '<strong>Karar:</strong> Kontrol listesi/ölçüm değerleri gerekiyor mu (gerekiyorsa MS Quality Management şablonları değerlendirilmeli).',
        'Kitoko şirketinde montaj ürün reçeteleri ve mamul kartlarının kurulması.',
    ],
)

STORIES['1297'] = dict(
    code='INV-010', feature='1200', anchor='s1297',
    short='Montaj hatası/red kaydının parti/seri ile ilişkilendirilip iade/hurda kararına bağlanması',
    status='dev',
    method_short='BCWMS kalite emri (red sebebi, karantina) + Standart BC iade/hurda; lot/seri bağı geliştirme',
    open_short='Kalite/hata kaydına lot/seri alanı ve iade/hurda karar akışı geliştirilmeli; hata kod listesi kararı.',
    req=('Montaj hattında tespit edilen hata veya red kaydı parti/seri numarasıyla ilişkilendirilecek ve iade/hurda kararına bağlanacak. '
         '<strong>Kabul kriteri:</strong> Montajda tespit edilen hatanın parti/seri numarasıyla ilişkilendirilip iade/hurda kararına bağlanması.'),
    method=('<p><strong>Bugünkü yapı taşları:</strong> BCWMS kalite emri <strong>RED</strong> sonucunda red sebebi kodu, not ve karantina rafı tutar ve LP ile ilişkilidir; ancak kalite emrinde <strong>lot/seri numarası alanı yoktur</strong> ve montaj emrine bağlı değildir. '
            'Standart BC’de karar sonuçları: <strong>hurda</strong> için Madde Günlüğü negatif düzeltme (neden kodu ile) veya montaj/üretimde fire; <strong>iade</strong> için Satınalma İade Siparişi (lot/seri madde izleme satırlarıyla). Lot/seri izi standart <strong>Madde İzleme</strong> (Item Tracing) ile alınır.</p>'
            '<p>Gereksinim için <strong>geliştirme</strong> gerekir: hata/red kaydına madde, lot/seri, montaj emri, hata kodu ve karar (iade / hurda / yeniden işleme) alanları; kararın ilgili BC belgesini (iade siparişi veya hurda günlüğü) oluşturması ve kayda geri bağlanması. Alternatif: BC 28 Microsoft Quality Management (denetimler lot/seri ile ilişkilidir).</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Madde, lot/seri izleme kurgusu ve kalite emri yok. Karşılanmıyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> Lot takipli 2 test maddesi var (ZZ-KIT-LOT, lot ZZ-LOT-001; ZZ-KIT-ASM); kalite emri 0; hata/red kaydı ve iade/hurda akışı test edilmedi.</p>'),
    user=(steps([
        'Montajda hata tespit edildiğinde terminalde <strong>Kalite Denetimi</strong> ekranında ilgili emri açın, <strong>RED sebebi</strong> ve not girip <strong>RED</strong> verin; malı karantina rafına alın.',
        '<strong>Geliştirme sonrası:</strong> kayıtta lot/seri numarası okutulur ve karar (iade / hurda / yeniden işleme) seçilir.',
        f'Hurda kararı: BC’de {AQ} → <strong>Madde Günlükleri</strong> → negatif düzeltme, neden kodu ve lot/seri ile. İade kararı: <strong>Satınalma İade Siparişi</strong> → madde izleme satırında lot/seri.',
        f'İz: {AQ} → <strong>Madde İzleme</strong> (Item Tracing) ile lot/seri; LP’li stokta <strong>LP İzlenebilirlik</strong> sayfası.',
    ]) + '<p>Ayrıntı: ' + gref(G_BC, 'Madde hareketleri, LP sayfaları') + '.</p>'),
    tests=[
        ('Lot takipli bir mamulün montajında hata kaydı açın; lot numarasını okutun, hata kodu ve “hurda” kararını seçin.', 'Hata kaydı madde + lot + montaj emri ile kaydolur; hurda günlüğü satırı aynı lotla oluşur ve nakledilir.'),
        ('İkinci hatada “iade” kararını seçin.', 'Satınalma iade siparişi lotlu satırla oluşur; hata kaydı iade belgesine bağlıdır.'),
        ('Madde İzleme’de lotu sorgulayın.', 'Giriş, montaj, hurda/iade hareketleri ve hata kaydı lot üzerinden görülür.'),
    ],
    open=[
        '<strong>Geliştirme:</strong> Hata/red kaydı (madde, lot/seri, montaj emri, hata kodu, karar) ve karar → iade/hurda belgesi bağlantısı.',
        '<strong>Karar:</strong> Hata kodu listesi, karar yetkisi (kim hurda/iade onaylar), yeniden işleme seçeneği.',
        'Lot/seri takibinin kritik maddelerde kurulması (KIT-011 ile ortak).',
    ],
)

STORIES['715'] = dict(
    code='KIT-011', feature='1201', anchor='s715',
    short='Kritik ürünlerde lot ve seri numarası izlenebilirliği',
    status='setup',
    method_short='Standart BC Item Tracking + BCWMS (LP İzlenebilirlik, terminalde lot/seri okutma)',
    open_short='Kritik madde gruplarının ve lot/seri kuralının belirlenmesi; madde izleme kodlarının Kitoko şirketinde kurulması.',
    req=('Kritik ürünlerde parti (lot) ve seri numarası izlenebilirliği. '
         '<strong>Kabul kriteri:</strong> Kritik bir ürünün lot/seri numarasıyla tedarikçiden müşteriye kadar izlenebilmesi.'),
    method=('<p><strong>Standart BC Madde İzleme (Item Tracking):</strong> Kritik madde gruplarına lot ve/veya seri zorunlu <strong>Madde İzleme Kodu</strong> (Item Tracking Code) atanır; lot/seri numara serileri tanımlanır. Satınalma girişinden satış çıkışına kadar her hareket lot/seri taşır. '
            'Uçtan uca iz standart <strong>Madde İzleme</strong> (Item Tracing) sayfasıyla alınır: lot/seri girildiğinde tedarikçi girişi, transferler, montaj/üretim tüketimi ve müşteri sevkiyatı ağaç olarak görülür.</p>'
            '<p><strong>BCWMS:</strong> Terminal mal kabulde lot/seri girer ve etiket basar, toplamada lot/seri okutur; <strong>Ürün Sorgu</strong> lotun rafını gösterir. BC’de <strong>LP İzlenebilirlik</strong> sayfası LP No., SSCC, lot, madde veya belge no ile arar; LP içeriğini, hareket geçmişini, bağlı madde/ambar hareketlerini, belgeleri ve lot ağacını gösterir. Geliştirme gerekmez.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Madde kartı 0; madde izleme kodları ve lot/seri numara serileri API’den okunamadı, madde olmadığı için kurgu kullanılmıyor. Karşılanmıyor; kurulum bekliyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> 9.389 maddeden yalnız 2’si lot takipli (ZZ-KIT-LOT, ZZ-KIT-ASM — test maddeleri), seri takipli madde 0. 111 madde hareketinden 1’i lotlu (ZZ-KIT-LOT, lot ZZ-LOT-001, KITWMS satınalma girişi). '
           '<strong>Gözlem:</strong> Aynı girişin BCWMS ambar hareketi ve kullanılabilir lot yanıtında lot alanı boş döndü; ambar hareketinde lotun kaydedildiği BC’de kontrol edilmeli.</p>'),
    user=(steps([
        f'BC’de {AQ} → <strong>Madde İzleme Kodları</strong> → lot/seri kurallarını görün; madde kartında <strong>Madde İzleme Kodu</strong> alanını kontrol edin.',
        'Terminalde <strong>Mal Kabul</strong> sırasında lot (ve gerekiyorsa seri) numarasını girin veya okutun; lot etiketini basın.',
        'Toplama ve sevkiyatta terminal lot/seri okutmanızı ister; okutulan lot sevkiyata yazılır.',
        f'İz: {AQ} → <strong>Madde İzleme</strong> (Item Tracing) → Lot No. veya Seri No. girin → <strong>İzle</strong>. Tedarikçi girişi ve müşteri sevkiyatı aynı ağaçta görünür. LP’li stokta <strong>LP İzlenebilirlik</strong> sayfasında lotu arayın.',
    ]) + '<p>Ayrıntı: ' + gref(G_TERM, 'Mal kabul, Sevkiyat, Ürün Sorgu') + '; ' + gref(G_BC, 'Madde hareketleri, LP sayfaları') + '; lot etiketi: ' + gref(G_COUNT, 'LP ve lot etiketi') + '.</p>'),
    tests=[
        ('Kritik (lot takipli) bir madde için tedarikçiden satınalma mal kabulü yapın; lot numarası girin.', 'Madde Hareketi ve Ambar Hareketi lot numarasıyla oluşur; lot bilgisi zorunludur (lotsuz kayıt engellenir).'),
        ('Malı rafa yerleştirin ve başka rafa taşıyın.', 'Ambar Hareketleri’nde lot korunur.'),
        ('Aynı lotu bir müşteriye satış sevkiyatıyla gönderin.', 'Sevkiyat satırında lot; Madde Hareketi’nde lot ile çıkış.'),
        ('Madde İzleme’de lotu izleyin.', 'Tedarikçi (satınalma girişi) → raf hareketleri → müşteri (satış sevkiyatı) tek ağaçta görülür.'),
        ('Seri takipli bir madde için aynı testi tekrarlayın.', 'Her birim kendi seri numarasıyla izlenir.'),
    ],
    open=[
        '<strong>Karar:</strong> Kritik madde grupları ve her grup için lot mu seri mi (ör. LED sürücü seri, armatür gövdesi lot) ve numara kuralı.',
        'Kitoko şirketinde madde izleme kodları, lot/seri numara serileri ve madde kartlarına atama.',
        'Lot/seri etiket tasarımının onayı.',
        'Demo gözlemi: lotlu girişte BCWMS ambar hareketi yanıtında lotun boş görünmesinin incelenmesi.',
    ],
)

STORIES['716'] = dict(
    code='KIT-012', feature='1201', anchor='s716',
    short='Direct delivery (doğrudan teslim) ile fiziksel sevkiyatın ayrıştırılması',
    status='setup',
    method_short='Standart BC Drop Shipment',
    open_short='Kitoko şirketinde satınalma kodu (Drop Shipment) ve proje boyutu aktarımının kurulup UAT’de test edilmesi.',
    req=('Doğrudan teslim (tedarikçiden müşteriye) siparişleri, depodan fiziksel sevkiyatlardan sistemsel olarak ayrışacak. '
         '<strong>Kabul kriteri:</strong> Direct delivery siparişinin depo hareketi yaratmadan maliyet ve gelirinin doğru oluşması.'),
    method=('<p><strong>Standart BC Drop Shipment (Doğrudan Sevkiyat).</strong> Satış siparişi satırında <strong>Satınalma Kodu</strong> (Drop Shipment işaretli) seçilir; satınalma siparişi <strong>Özel Sipariş / Doğrudan Sevkiyat → Satış Siparişini Getir</strong> ile ya da Talep Planlama sayfasıyla oluşturulur. '
            'Tedarikçi teslim ettiğinde satış siparişinde <strong>Sevk</strong> kaydı satınalma girişini de aynı anda nakleder.</p>'
            '<p>Sonuç: <strong>ambar belgesi, ambar hareketi ve raf hareketi oluşmaz</strong>; terminale iş düşmez. BC madde hareketinde birbirine uygulanmış bir satınalma girişi ve bir satış çıkışı oluşur (net stok etkisi sıfır); satış maliyeti tam olarak o satınalmanın maliyetidir. Satış siparişinin boyutları (proje dahil) satınalma satırına taşınır — UAT’de doğrulanmalı. Geliştirme gerekmez.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Müşteri 0, tedarikçi 0, madde 0; satınalma kodu ve PROJE boyutu yok. Kurgu kullanılmıyor; kurulum bekliyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> Doğrudan sevkiyat işaretli satış satırı 0; senaryo test edilmedi. PROJE boyutu ve 454 proje var.</p>'),
    user=(steps([
        'Satış siparişini girin; doğrudan teslim edilecek satırda <strong>Satınalma Kodu</strong> alanında doğrudan sevkiyat kodunu seçin (Drop Shipment işaretlenir). Lokasyon alanı depo hareketi oluşturmaz.',
        'Satınalma siparişini aynı tedarikçiyle açın; <strong>Eylemler → Doğrudan Sevkiyat → Satış Siparişini Getir</strong> ile satırları getirin ve siparişi tedarikçiye gönderin.',
        'Tedarikçi müşteriye teslim ettiğinde satış siparişinde <strong>Nakil → Sevk</strong> yapın (satınalma girişi otomatik nakledilir); faturaları ayrı ayrı kesin.',
        f'Kontrol: {AQ} → <strong>Madde Hareketleri</strong> → belge no filtresi: satınalma +, satış − (uygulanmış). <strong>Ambar Hareketleri</strong>’nde bu belgeler için kayıt yoktur. Terminalde bu sipariş için toplama/sevkiyat görünmez.',
    ]) + '<p>Fiziksel sevkiyatla farkı için: ' + gref(G_BC, 'Toplama ve sevkiyat') + '.</p>'),
    tests=[
        ('Satış siparişinde doğrudan sevkiyat satırı ve bağlı satınalma siparişi oluşturun.', 'Satınalma satırında Satış Siparişi No. dolu; satış satırında Satınalma Sipariş No. dolu.'),
        ('Satış siparişinden Sevk kaydı yapın.', 'Satınalma girişi ve satış sevkiyatı aynı anda nakledilir; ambar mal kabulü/sevkiyatı veya toplama oluşmaz.'),
        ('Ambar Hareketleri ve Raf İçerikleri’ni kontrol edin.', 'Bu belge için ambar hareketi yok; raf stoku değişmez.'),
        ('Satınalma ve satış faturalarını nakledip Değer Girişleri’ni / madde maliyetini kontrol edin.', 'Satış maliyeti = satınalma maliyeti; gelir satış faturası tutarı; proje boyutu her iki tarafta dolu.'),
    ],
    open=[
        'Kitoko şirketinde doğrudan sevkiyat satınalma kodu, müşteri/tedarikçi/madde ana verisi.',
        '<strong>Karar:</strong> Doğrudan teslim siparişlerinde lokasyon kodu boş mu, belirli bir “sanal” lokasyon mu kullanılacak (demo şirkette TRANSITTIC “Transit Ticaret (fiziksel olmayan)” lokasyonu var).',
        'Proje boyutunun satınalma tarafına aktarımının UAT’de doğrulanması (KIT-013 ile ortak).',
    ],
)

STORIES['717'] = dict(
    code='KIT-013', feature='1201', anchor='s717',
    short='Proje bazlı stok takibi; ürün-proje kullanım izleme',
    status='setup-report',
    method_short='Standart BC Projeler (Jobs) + PROJE boyutu; detay rapor geliştirme/karar',
    open_short='Projeler ve PROJE boyutu Kitoko’da kurulmalı; “BC_Proje_Zaman_Cizelgesi_1.html” benzeri detay rapor için örnek dosya ve rapor kararı/geliştirmesi.',
    req=('Proje bazlı stok takibi ve ürünün hangi projede ne kadar kullanıldığının izlenmesi. '
         '<strong>Kabul kriteri:</strong> Bir ürünün hangi projede ne kadar kullanıldığının raporlanabilmesi. '
         'Ek istek (kabul kriteri alanında): “BC_Proje_Zaman_Cizelgesi_1.html içerisindeki gibi bir detaylı rapor” görülmek isteniyor.'),
    method=('<p><strong>Standart BC Projeler (Jobs) + PROJE boyutu.</strong> Projeye malzeme kullanımı üç yolla kaydedilir: satınalma satırında <strong>Proje No. / Proje Görevi No.</strong> (doğrudan projeye alım), <strong>Proje Günlüğü</strong> ile stoktan projeye tüketim, proje planlama satırından ambar toplaması. '
            'Her kullanım <strong>Proje Defter Kaydı</strong> (Job Ledger Entry) ve proje no’lu <strong>Madde Hareketi</strong> oluşturur. Ürün-proje kullanımı standart olarak <strong>Proje Defter Kayıtları</strong> (madde filtresi), <strong>Projeler — Gerçekleşen/Bütçe</strong> raporları ve Power BI proje görünümleriyle alınır. Tüm stok hareketlerinde proje boyutunun zorunlu olması madde kartlarında <strong>Varsayılan Boyut → Kod Zorunlu</strong> ile sağlanır.</p>'
            '<div class="warn">BCWMS (el terminali) kaynak kodunda proje (Job) alanı yoktur; çözüm detayındaki “proje bazlı stok bakiyesi ve tüketim raporu Warehouse Management App görünümleriyle sunulur” ifadesinin üründe karşılığı <strong>yoktur</strong>. Proje raporu standart BC raporlarıyla ya da ayrı rapor geliştirmesiyle verilmelidir.</div>'
            '<p><strong>Detay rapor:</strong> İstenen “BC_Proje_Zaman_Cizelgesi_1.html” dosyası /Users/kaanodabas/Desktop/Kitoko ve kullanıcı klasörü altında aranmış, <strong>bulunamamıştır</strong>; yapısı incelenemedi. Raporun kapsamı (zaman ekseni, proje/görev kırılımı, madde, miktar, maliyet) örnek dosya alındıktan sonra netleşir; standart rapor yetmezse rapor geliştirmesi gerekir.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Proje 0; boyutlar yalnız PURCHASER ve SALESPERSON — <strong>PROJE boyutu yok</strong>; madde ve hareket yok. Karşılanmıyor; kurulum bekliyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> PROJE boyutu ve 454 proje var. Test projesi PR000001 “KIT-UAT Egis Tunel Aydinlatma Projesi”nde 3 proje defter kaydı, 1 madde planlama satırı (I-KTK19891G9, 100 adet) ve proje no’lu 2 madde hareketi (satınalma +100, negatif düzeltme −100) var. Ürün-proje kullanım verisi demo düzeyinde mevcut; rapor çalıştırılmadı.</p>'),
    user=(steps([
        f'Projeyi BC’de {AQ} → <strong>Projeler</strong> ile açın; proje görevlerini ve planlama satırlarını (madde) girin.',
        'Projeye doğrudan alım: satınalma siparişi satırında <strong>Proje No.</strong> ve <strong>Proje Görevi No.</strong> girin.',
        f'Stoktan projeye tüketim: {AQ} → <strong>Proje Günlükleri</strong> → madde, miktar, lokasyon/raf, proje ve görev → <strong>Nakil</strong>. Yönlendirilmiş depoda proje planlama satırından ambar toplaması oluşturulup terminalde <strong>Toplama</strong> ile toplanır.',
        f'Rapor: {AQ} → <strong>Proje Defter Kayıtları</strong> → Tür = Madde, No. = madde filtresi → proje bazında miktar ve maliyet; madde tarafında <strong>Madde Hareketleri</strong>’nde <strong>Proje No.</strong> sütunu.',
    ]) + '<p>Ayrıntı: ' + gref(G_BC, 'Madde hareketleri ve stok raporları') + '; toplama: ' + gref(G_TERM, 'Toplama') + '.</p>'),
    tests=[
        ('Bir maddeyi iki farklı projeye (biri satınalma ile doğrudan, biri proje günlüğü ile stoktan) kullanın.', 'Her kullanım proje defter kaydı ve proje no’lu madde hareketi oluşturur.'),
        ('Proje boyutu olmadan bir stok hareketi kaydetmeyi deneyin (proje zorunlu madde).', 'Kayıt engellenir: PROJE boyutu zorunlu.'),
        ('Proje Defter Kayıtları’nı madde filtresiyle açın.', 'Maddenin hangi projede ne kadar (miktar, maliyet) kullanıldığı görülür; toplamlar madde hareketleriyle tutar.'),
        ('İstenen detay raporu (örnek dosyaya göre) çalıştırın.', 'Rapor proje/görev/madde/miktar/tarih kırılımını örnekteki gibi verir. (Rapor kararı/geliştirmesi sonrası.)'),
    ],
    open=[
        '<strong>Eksik girdi:</strong> “BC_Proje_Zaman_Cizelgesi_1.html” örnek dosyasının paylaşılması (bulunamadı).',
        '<strong>Karar / geliştirme:</strong> Detay rapor standart raporlarla mı (Proje Defter Kayıtları, Power BI) yoksa özel rapor geliştirmesiyle mi verilecek.',
        '<strong>Karar:</strong> “Tüm stok hareketlerine proje boyutu zorunlu” kuralı genel stok alımlarında da uygulanacak mı (Kod Zorunlu yerine yalnız proje kullanımlarında zorunluluk önerilir).',
        'Kitoko şirketinde PROJE boyutu, projeler ve proje kayıt grupları kurulumu.',
        'Çözüm detayındaki “WMS görünümleri” ifadesinin düzeltilmesi (BCWMS’te proje görünümü yok).',
    ],
)

STORIES['718'] = dict(
    code='KIT-014', feature='1201', anchor='s718',
    short='Sayım süreçlerinin standartlaştırılması ve stok doğruluğu kontrolü',
    status='setup',
    method_short='BCWMS Sayım (sayım sayfası, turlar, fark raporu, onay) + Standart BC Fiziksel Envanter / Sayım Dönemleri',
    open_short='Kitoko şirketinde depo, raf ve madde kurulumundan sonra sayım ve çevrim sayımı sınıflarının tanımlanması ve UAT.',
    req=('Sayım süreçlerinin standartlaştırılması ve stok doğruluğu kontrolü; periyodik ve dönemsel sayım, el terminaliyle sayım girişi, fark analizi, onaylı fark fişi; kritik ürünlerde çevrim sayımı. '
         '<strong>Kabul kriteri:</strong> Sayım sonucunda fark raporunun üretilip düzeltme fişine dönüştürülebilmesi.'),
    method=('<p><strong>BCWMS Sayım modülü + Standart BC.</strong> BC’de <strong>Count Sheets</strong> (sayım sayfaları) lokasyon ve isteğe bağlı alan (bölge) filtresiyle açılır; en çok üç sayıcı atanabilir ve <strong>sayım turları</strong> (1., 2. tur, turları yan yana karşılaştırma) desteklenir. '
            'Terminalde <strong>Sayım</strong> ekranında alan → raf → LP/ürün/lot okutulur ve bulunan miktar girilir; <strong>Rafı bitir · sayılmayanları 0 yaz</strong> ile eksikler sıfırlanır. '
            'Fark analizi BC’de <strong>Count Variance</strong> raporu (sistem miktarı, 1./2./3. sayım, raf, LP, lot, seri) ve <strong>Count Variance Review</strong> sayfasıyla (<strong>Approve Variance</strong>, <strong>Supervisor Approve All</strong>) yapılır. Onaylanan farklar BC’nin <strong>Ambar Fiziksel Envanter Günlüğü</strong> ve <strong>Fiziksel Envanter Günlüğü</strong> satırlarına (düzeltme fişi) dönüştürülerek nakledilir.</p>'
            '<p>Çevrim sayımı (cycle counting) standart BC’de <strong>Fiziksel Envanter Sayım Dönemleri</strong> (Phys. Invt. Counting Periods) madde/SKU kartına atanarak ve <strong>Sayım Dönemini Hesapla</strong> ile kurulur. Raf/LP kullanılmayan depolar için terminalde <strong>İlk Sayım</strong> (yalnız madde okut) vardır; yönlendirilmiş lokasyonda kullanılamaz. Geliştirme gerekmez.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Sayım sayfası 0, İlk Sayım 0; sayılacak lokasyon, raf ve madde yok. Karşılanmıyor; kurulum bekliyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> Sayım sayfası 0, İlk Sayım 0; KITWMS’te AYAR bölgesi ve AYAR-01 ayarlama rafı tanımlı. Sayım akışı Kitoko şirketlerinde uçtan uca test edilmedi (aynı akış Element 4 şirketinde kullanılıyor).</p>'),
    user=(steps([
        f'Sorumlu BC’de {AQ} → <strong>Count Sheets</strong> → yeni sayım (lokasyon, alan filtresi, sayıcılar) açar; ya da terminalde <strong>Sayım</strong> → <strong>Yeni V2 Sayımı Oluştur</strong>.',
        'Sayıcı terminalde <strong>Sayım</strong> ekranında alanı, sonra rafı okutur; raftaki her LP/ürün/lot için bulunan miktarı girer; <strong>Rafı bitir</strong>.',
        'Gerekirse sorumlu <strong>Yeni Turu Başlat</strong> ile ikinci tur açar ve <strong>Turları Yan Yana Karşılaştır</strong> ile farkları inceler.',
        f'BC’de <strong>Count Variance</strong> raporunu yazdırın; <strong>Count Variance Review</strong> sayfasında farkları satır satır <strong>Approve Variance</strong> ile onaylayın.',
        'Onaylı farkları <strong>Onayla ve Stoklara İşle</strong> ile işleyin: düzeltme fiziksel envanter günlükleriyle nakledilir. Sonucu <strong>Ambar Hareketleri</strong> ve <strong>Madde Hareketleri</strong>’nde (Pozitif/Negatif Düzeltme) görün.',
    ]) + '<p>Ayrıntı: ' + gref(G_COUNT, 'Normal sayım, Onay ve stoklara işleme') + '; ' + gref(G_BC, 'Sayım') + '.</p>'),
    tests=[
        ('Bir alan için sayım sayfası açın; terminalde iki rafı sayın, bir rafta bir ürünü eksik, bir ürünü fazla girin.', 'Sayım satırlarında sistem miktarı ve sayılan miktar; farklı satırlar işaretli.'),
        ('Count Variance raporunu alın.', 'Rapor her fark satırını raf, madde, LP/lot, sistem ve sayılan miktarla listeler.'),
        ('Farkları Count Variance Review’da onaylayıp stoklara işleyin.', 'Fiziksel envanter günlüğü (düzeltme fişi) nakledilir; Madde Hareketleri’nde Pozitif/Negatif Düzeltme, Ambar Hareketleri’nde raf düzeltmesi; sayım belgesi kapanır.'),
        ('Kritik madde için sayım dönemi atayıp Sayım Dönemini Hesapla’yı çalıştırın.', 'Fiziksel envanter günlüğüne sayımı gelen kritik maddeler önerilir.'),
    ],
    open=[
        'Kitoko şirketinde lokasyon/raf/madde kurulumu (KIT-008) ve fiziksel envanter günlük şablonları.',
        '<strong>Karar:</strong> Sayım politikası: dönemsel tam sayım tarihi, kritik ürünlerde çevrim sayımı sıklığı (sayım dönemleri), fark onay yetkisi ve tolerans.',
        'Sayım öncesi raf ve ürün etiketlerinin basılması (Kitoko’da ürün olmadığı için bugün etiket basılamaz).',
        'Alt kayıt 1068 (bu raporun kapsamı dışında, içeriği incelenmedi).',
    ],
)

STORIES['719'] = dict(
    code='KIT-015', feature='1201', anchor='s719',
    short='Stok virmanı (stok kalemleri arası transfer) yönetimi',
    status='setup-decision',
    method_short='Standart BC (Madde Günlüğü negatif/pozitif düzeltme veya Montaj Emri); Madde Yeniden Sınıflandırma madde no değiştirmez',
    open_short='Virman yöntemi kararı (çift satırlı madde günlüğü mü, montaj emri mi), neden kodları ve yetki kurulumu.',
    req=('Bir stok kaleminden (maddeden) başka bir stok kalemine virman süreçlerinin sistemden, yetki ve neden kodlarıyla yönetilmesi; muhasebe yansıması otomatik. '
         '<strong>Kabul kriteri:</strong> Virman sonrası her iki stok kaleminin miktar ve maliyet bakiyesinin doğru olması.'),
    method=('<div class="warn"><strong>Önemli düzeltme:</strong> Çözüm detayında önerilen BC <strong>Madde Yeniden Sınıflandırma Günlüğü</strong> (Item Reclassification Journal) lokasyon, raf, boyut ve lot/seri değiştirir; <strong>madde numarasını değiştirmez</strong>. “Madde A’dan madde B’ye” virman bu günlükle yapılamaz.</div>'
            '<p>Standart BC’de iki yol vardır:</p>'
            '<ul><li><strong>Madde Günlüğü (çift satır):</strong> A maddesi için <strong>Negatif Düzeltme</strong>, B maddesi için <strong>Pozitif Düzeltme</strong>, aynı belge no ve <strong>Neden Kodu</strong> ile. B’nin birim maliyeti A’nın çıkış maliyetine eşit girilmelidir (elle); aksi halde maliyet bakiyesi tutmaz. Muhasebe yansıması stok ayarlama hesapları üzerinden otomatik oluşur.</li>'
            '<li><strong>Montaj Emri (dönüştürme):</strong> B mamulü, A bileşen olarak; montaj kaydı A’yı tüketir, B’yi A’nın gerçek maliyetiyle üretir. Maliyet otomatik taşınır; terminalde <strong>Montaj</strong> ekranıyla yapılabilir.</li></ul>'
            '<p>Yetki: virman günlük şablonu/toplu işi için izin seti ve kullanıcı kısıtı; neden kodları <strong>Neden Kodları</strong> sayfasında tanımlanır. Geliştirme gerekmez; yöntem <strong>kararı</strong> gerekir. Aynı madde içinde depo/raf/lot değişikliği için Madde Yeniden Sınıflandırma Günlüğü ve terminalde <strong>Ad-Hoc Hareket</strong> kullanılır.</p>'),
    state=('<p><strong>Kitoko (Sand2010):</strong> Madde 0; neden kodları ve virman günlük şablonu kontrol edilemedi (API’de yok), stok olmadığı için kullanılmıyor. Karşılanmıyor; kurulum bekliyor.</p>'
           '<p><strong>Demo (DemoSandbox):</strong> BCWMS madde yeniden sınıflandırma günlüğü OData’da yayınlı; virman senaryosu test edilmedi.</p>'),
    user=(steps([
        f'<strong>Madde Günlüğü yolu:</strong> {AQ} → <strong>Madde Günlükleri</strong> → virman toplu işi; 1. satır A maddesi Negatif Düzeltme, 2. satır B maddesi Pozitif Düzeltme; aynı Belge No., <strong>Neden Kodu</strong>, lokasyon/raf; B’nin <strong>Birim Tutar</strong>’ını A’nın maliyetine eşitleyin → <strong>Nakil</strong>.',
        f'<strong>Montaj yolu:</strong> {AQ} → <strong>Montaj Emirleri</strong> → mamul B, bileşen A → Serbest Bırak; terminalde <strong>Montaj</strong> ekranında tüketim ve çıktıyı kaydedin.',
        f'Kontrol: <strong>Madde Hareketleri</strong> (iki madde, aynı belge), <strong>Değer Girişleri</strong> (maliyet), madde kartında <strong>Stok</strong> ve <strong>Birim Maliyet</strong>; muhasebe için <strong>Genel Muhasebe Kayıtları</strong>.',
    ]) + '<p>Ayrıntı: ' + gref(G_BC, 'Madde hareketleri ve stok raporları') + '; aynı madde içinde raf/depo değişikliği: ' + gref(G_TERM, 'Raflar / depolar arası transfer') + '.</p>'),
    tests=[
        ('A maddesinden 10 adet B maddesine virman yapın (seçilen yöntemle).', 'A stoğu 10 azalır, B stoğu 10 artar.'),
        ('Değer Girişleri’ni kontrol edin.', 'A’nın çıkış maliyeti = B’nin giriş maliyeti; toplam stok değeri değişmez.'),
        ('Maliyet Ayarla (Adjust Cost) çalıştırıp tekrar kontrol edin.', 'Maliyet farkı oluşmaz (montaj yolunda otomatik; madde günlüğü yolunda birim tutar doğru girildiyse).'),
        ('Yetkisiz kullanıcıyla virman toplu işini nakletmeyi deneyin; neden kodsuz satır girin.', 'Yetkisiz nakil engellenir; neden kodu zorunluysa satır kaydedilmez.'),
    ],
    open=[
        '<strong>Karar:</strong> Virman yöntemi: çift satırlı madde günlüğü mü (maliyet elle) yoksa montaj emri ile dönüştürme mi (maliyet otomatik)?',
        'Çözüm detayındaki “Madde yeniden sınıflandırma fişleri (kalem-kalem virman)” ifadesinin düzeltilmesi.',
        'Kitoko şirketinde neden kodları, virman günlük şablonu/toplu işi ve izin setleri.',
        '<strong>Karar:</strong> Neden kodu zorunluluğu ve virman onay yetkisi (Muhasebe & Finans).',
    ],
)

FEATURES = [
    ('1199', 'f1199', 'KIT-INV — Depo Yapısı ve Mal Kabul', ['712', '713', '714'],
     'Depo hiyerarşisi (ambar → bölge → raf), mal kabul ve kalite kontrol ile kalite onayı olmayan stoğun kullanılamaması.'),
    ('1200', 'f1200', 'KIT-INV — Montaj Kalite Kontrolü', ['1296', '1297'],
     'Montaj/hızlı üretim çıkışında son kontrol ile hata/red kaydının lot/seri ve iade/hurda kararına bağlanması.'),
    ('1201', 'f1201', 'KIT-INV — İzlenebilirlik, Sayım ve Stok Hareketleri', ['715', '716', '717', '718', '719'],
     'Lot/seri izlenebilirliği, doğrudan teslim, proje bazlı stok, sayım ve stok virmanı.'),
]


# ---------------------------------------------------------------- bölümler
def story_section(sid):
    s = STORIES[sid]
    rows = ''.join(f'<tr><td>{n}</td><td>{st}</td><td>{ex}</td></tr>' for n, (st, ex) in enumerate(s['tests'], 1))
    return (f'<section id="{s["anchor"]}"><h3>{s["code"]} · #{sid} — {html.escape(s["short"])}</h3>'
            f'<p>Durum: {badge(s["status"])}</p>'
            f'<h4>1. Gereksinim</h4><p>{s["req"]}</p>'
            f'<h4>2. Çözüm yöntemi</h4><p><strong>{html.escape(s["method_short"])}</strong></p>{s["method"]}'
            f'<h4>3. Kitoko’da bugünkü durum</h4>{s["state"]}'
            f'<h4>4. Kullanıcı adımları</h4>{s["user"]}'
            f'<h4>5. Kabul kriterinin testi</h4>{test_table(s["tests"])}'
            f'<p>Doğrulama: UAT ortamında test edilir ve müşteri anahtar kullanıcısı tarafından yazılı olarak onaylanır.</p>'
            f'<h4>6. Açık iş ve kararlar</h4>{ul(s["open"])}{BACK}</section>')


def summary_table():
    rows = []
    for fid, anchor, ftitle, sids, _ in FEATURES:
        for sid in sids:
            s = STORIES[sid]
            rows.append(f'<tr><td><a href="#{s["anchor"]}">{s["code"]}</a><br>#{sid}</td><td>{html.escape(s["short"])}</td>'
                        f'<td>{html.escape(s["method_short"])}</td><td>{badge(s["status"])}</td><td>{html.escape(s["open_short"])}</td></tr>')
    return ('<table class="sum"><thead><tr><th>Story</th><th>Gereksinim</th><th>Çözüm</th><th>Durum</th><th>Açık iş</th></tr></thead><tbody>'
            + ''.join(rows) + '</tbody></table>')


EVIDENCE = [
    ('Sand2010 · api/v2.0/companies', '3 şirket: Kitoko Aydınlatma ve Müh. A.Ş. (5fa2a93d…), Element 4, Citus.'),
    ('Sand2010 · Kitoko · api/v2.0 items, locations, vendors, customers, projects, itemLedgerEntries ($count)', 'Hepsi 0. dimensions: PURCHASER, SALESPERSON. accounts 273, unitsOfMeasure 52.'),
    ('Sand2010 · api/dynops/warehouse/v2.0/$metadata', '200; 69 varlık kümesi (BCWMS yüklü).'),
    ('Sand2010 · Kitoko · BCWMS items, locations, zones, bins, binContents, qualityOrders, wmsTerminals, localUsers, printers, licensePlates, countSheets, firstCounts, receipts, assemblies', 'Hepsi 0. appUserProfiles 3 (BCADMİN, Fallback, SYSTEM — DEFAULT yapılandırma).'),
    ('DemoSandbox · KITOKO-TR-DEMO-V1 · api/v2.0 items / locations / projects / dimensions / itemCategories', '9.389 madde, 8 lokasyon, 454 proje, 14 boyut (PROJE dahil), 31 madde kategorisi.'),
    ('DemoSandbox · BCWMS locations, zones, bins', 'KITWMS raf zorunlu + yönlendirilmiş; 6 bölge (KABUL, KALITE, DEPO-A, DEPO-B, SEVK, AYAR), 7 raf. Diğer 7 lokasyon rafsız.'),
    ('DemoSandbox · BCWMS items ($select lotTrackingRequired, serialTrackingRequired)', 'Lot takipli 2 (ZZ-KIT-LOT, ZZ-KIT-ASM), seri takipli 0; stoğu sıfırdan farklı 35 madde (çoğu eksi).'),
    ('DemoSandbox · BCWMS itemLedgerEntries / warehouseEntries / availableLots', '111 madde hareketi, 1’i lotlu (ZZ-LOT-001, KITWMS); 1 ambar hareketi (K-01/KABUL) — lot alanı boş döndü.'),
    ('DemoSandbox · BCWMS wmsTerminals, localUsers, printers, qualityOrders, countSheets, receipts, assemblies', 'Terminal KITOKO-01; 2 terminal yöneticisi operatör; ZD230 ZPL yazıcı (agent Offline, son görülme 20.10.2026); kalite emri 0; sayım 0; mal kabul WA000001 (MERKEZDEP, %40); montaj MN000001 (ANA, kalan 2).'),
    ('DemoSandbox · ODataV4 JobLedgerEntries, ItemLedgerEntries (Job_No ne \'\'), Job_Planning_Lines', 'PR000001 “KIT-UAT Egis Tunel Aydinlatma Projesi”: 3 proje defter kaydı, 2 proje no’lu madde hareketi, 1 madde planlama satırı.'),
    ('DemoSandbox · ODataV4 salesDocumentLines (dropShipment eq true)', '0 satır.'),
    ('DemoSandbox · ODataV4 service document', 'DOPSWHSQualityOrders (0 kayıt), DOPSWHSItemReclassJournal ve diğer DOPSWHS servisleri yayınlı.'),
    ('DemoV2 · BCWMS $metadata', '62 varlık kümesi; locations, zones, wmsTerminals, firstCounts, labelLayouts, terminalLayouts yok (eski BCWMS sürümü). KITOKO-TR-DEMO-V1: 5.312 madde, raf 0, kalite emri 0.'),
    ('BCWMS AL kaynağı (al/src, 1.14.3.22)', 'Quality/QualityMgmt + QualityOrder (kalite emri), PutAway/PutAwayLineApi.VerifyQualityPlacement (yalnız LP’li yerleştirme engeli), QualityMgmt/QualityMgmtBridge (BC 28 bekliyor, yorum satırında), Pick/Movement QC engeli devre dışı, Panels/LpTrace (LP İzlenebilirlik), Count (Count Variance 72093, Variance Review), Assembly (son kontrol yok); proje (Job) alanı yok.'),
    ('Android kaynağı (1.14.201-kitoko)', 'Kitoko menüsünde Kalite Denetimi ve MS Kalite ekranları; Sayım (V2) + İlk Sayım; Montaj ekranı.'),
    ('find BC_Proje_Zaman_Cizelgesi_1.html', 'Bulunamadı (/Users/kaanodabas/Desktop/Kitoko ve /Users/kaanodabas).'),
]


def build_html():
    toc = [('ozet', 'Özet ve durum tablosu', False), ('ortam', 'Ortam ve şirket durumu', False),
           ('statuler', 'Statüler nasıl okunur?', True)]
    body = []
    # Özet
    body.append('<section id="ozet"><h2>Özet ve durum tablosu</h2>'
                '<p>Bu belge, Azure DevOps’taki <strong>Stok, Depo ve Kalite — Kitoko</strong> epic’inin (#1045) üç feature’ı ve on user story’si için gereksinimi, çözüm yöntemini, Kitoko Aydınlatma ve Müh. A.Ş. şirketindeki bugünkü gerçek durumu, kullanıcı adımlarını, kabul kriteri testini ve açık işleri bir arada verir. Kullanım adımları için ilgili Kitoko kılavuzlarına bağlantı verilir.</p>'
                '<div class="warn"><strong>Ana bulgu:</strong> Hedef şirket <strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong>’de depo ve stok kurulumu <strong>henüz yapılmamıştır</strong>: lokasyon, bölge, raf, madde, tedarikçi, müşteri, proje, PROJE boyutu, el terminali ve terminal kullanıcısı yoktur (BCWMS uygulaması ortamda yüklü ve çalışıyor). Bu nedenle hiçbir story bugün Kitoko şirketinde “Karşılanıyor ve doğrulandı” değildir. Örnek kurgu yalnız demo şirkette (DemoSandbox · KITOKO-TR-DEMO-V1) vardır.</div>'
                + summary_table() +
                '<p>Statü dağılımı: 4 story “Çözüm mevcut, kurulum gerekli” (KIT-008, KIT-011, KIT-012, KIT-014), 1 story kurulum + rapor kararı (KIT-013), 1 story kurulum + yöntem kararı (KIT-015), 1 story kısmen mevcut + geliştirme (KIT-009), 3 story geliştirme gerekli (KIT-010, INV-009, INV-010).</p>'
                f'{BACK}</section>')
    # Ortam
    body.append('<section id="ortam"><h2>Ortam ve şirket durumu</h2>'
                '<p>Bilgiler 27.10.2026, 17:15–17:50 arasında BC’den yalnız okuma (GET) ile alınmıştır. Production ortamına istek atılmamıştır.</p>'
                '<table><thead><tr><th>Ortam · şirket</th><th>Ne var?</th><th>Bu rapordaki yeri</th></tr></thead><tbody>'
                '<tr><td><strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong></td><td>BCWMS yüklü (API 69 varlık). Madde 0, lokasyon 0, bölge 0, raf 0, tedarikçi 0, müşteri 0, proje 0, madde hareketi 0, terminal 0, terminal kullanıcısı 0, yazıcı 0, kalite emri 0, sayım 0. Boyutlar: PURCHASER, SALESPERSON. Hesap planı 273 hesap. 3 varsayılan kullanıcı profili.</td><td>Kitoko’nun <strong>hedef şirketi</strong>; durum sütunu bu şirkete göre verilir.</td></tr>'
                '<tr><td><strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong></td><td>9.389 madde, 8 lokasyon (KITWMS yönlendirilmiş, 6 bölge, 7 raf), 454 proje, PROJE boyutu, terminal KITOKO-01, 2 operatör, 1 etiket yazıcısı, 2 lot takipli test maddesi, KIT-UAT test projesi PR000001.</td><td>Demo/UAT hazırlığı; örnek kurgu ve test verisi. Okuma sırasında veri değişiyordu (27.10.2026 tarihli test kayıtları ekleniyordu).</td></tr>'
                '<tr><td><strong>DemoV2 · KITOKO-TR-DEMO-V1</strong></td><td>5.312 madde, raf 0, kalite emri 0; BCWMS eski sürüm (lokasyon/bölge/terminal uç noktaları yok).</td><td>Kullanılmamalı; terminal bu ortamda tam çalışmaz.</td></tr>'
                '<tr><td><strong>Production</strong></td><td>Kontrol edilmedi (talimat gereği istek atılmadı). “BCWMS kurulu değil” bilgisi bu çalışmada doğrulanmadı.</td><td>—</td></tr>'
                '</tbody></table>'
                '<p>Kitoko terminalleri bugün yalnız DemoSandbox · KITOKO-TR-DEMO-V1 bağlantısında kullanılabilir. Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş. şirketinde terminal ve kullanıcı tanımlanmadan terminal girişi yapılamaz.</p>'
                '<section id="statuler"><h3>Statüler nasıl okunur?</h3><table><tbody>'
                f'<tr><td>{badge("ok")}</td><td>Kitoko şirketinde kurulu ve kabul kriteri test edilmiş. (Bugün bu statüde story yok.)</td></tr>'
                f'<tr><td>{badge("setup")}</td><td>Ürün (standart BC veya BCWMS) gereksinimi karşılıyor; Kitoko şirketinde kurulum ve ana veri bekliyor.</td></tr>'
                f'<tr><td>{badge("partial")}</td><td>Ürünün bir kısmı karşılıyor; kabul kriteri için geliştirme gerekiyor.</td></tr>'
                f'<tr><td>{badge("dev")}</td><td>Kabul kriteri bugünkü ürünle karşılanmıyor; geliştirme (ve tasarım kararı) gerekiyor.</td></tr>'
                f'<tr><td>{badge("decision")}</td><td>Yöntem veya kapsam müşteri/proje kararına bağlı.</td></tr>'
                '</tbody></table></section>'
                f'{BACK}</section>')
    # Feature bölümleri
    for fid, anchor, ftitle, sids, fdesc in FEATURES:
        toc.append((anchor, f'Feature #{fid} — {ftitle.split("— ")[1]}', False))
        items = ''.join(f'<li><a href="#{STORIES[s]["anchor"]}">{STORIES[s]["code"]} · #{s}</a> — {html.escape(STORIES[s]["short"])}: {badge(STORIES[s]["status"])}</li>' for s in sids)
        body.append(f'<section id="{anchor}"><h2>Feature #{fid} — {html.escape(ftitle)}</h2><p>{fdesc}</p><ul>{items}</ul>')
        for sid in sids:
            toc.append((STORIES[sid]['anchor'], f'{STORIES[sid]["code"]} · #{sid}', True))
            body.append(story_section(sid))
        body.append(f'{BACK}</section>')
    # Açık işler
    toc.append(('acik-isler', 'Açık işler ve kararlar', False))
    rows = []
    for fid, anchor, ftitle, sids, _ in FEATURES:
        for sid in sids:
            s = STORIES[sid]
            for o in s['open']:
                kind = 'Karar' if '<strong>Karar' in o else ('Geliştirme' if '<strong>Geliştirme' in o or '<strong>Karar / geliştirme' in o else ('Girdi' if 'Eksik girdi' in o else 'Kurulum / diğer'))
                if '<strong>Karar / geliştirme' in o:
                    kind = 'Karar / Geliştirme'
                rows.append(f'<tr><td><a href="#{s["anchor"]}">{s["code"]}</a></td><td>{kind}</td><td>{o}</td></tr>')
    common = ('<p><strong>Ortak ön koşul (tüm story’ler):</strong> Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş. şirketine madde, birim, tedarikçi, müşteri, lokasyon/bölge/raf, proje ve boyut ana verisinin aktarılması; BCWMS kurulum kartı, terminal, terminal kullanıcıları, kullanıcı profilleri ve etiket yazıcısının (Print Agent) tanımlanması. '
              'Bu yapılmadan hiçbir kabul kriteri Kitoko şirketinde test edilemez.</p>')
    body.append('<section id="acik-isler"><h2>Açık işler ve kararlar</h2>' + common +
                '<table><thead><tr><th>Story</th><th>Tür</th><th>Açık iş / karar</th></tr></thead><tbody>' + ''.join(rows) + '</tbody></table>'
                f'{BACK}</section>')
    # Kanıtlar
    toc.append(('kanitlar', 'Kullanılan kanıtlar', False))
    ev = ''.join(f'<tr><td>{html.escape(q)}</td><td>{html.escape(r)}</td></tr>' for q, r in EVIDENCE)
    body.append('<section id="kanitlar"><h2>Kullanılan kanıtlar</h2>'
                '<p>Tüm BC sorguları GET’tir; uç nokta kökü <code>https://api.businesscentral.dynamics.com/v2.0/&lt;tenant&gt;/&lt;ortam&gt;/</code>. Ayrıntılı ham bulgular: <code>Kitoko/outputs/kitoko-stok-depo-kalite-20261027/kitoko-setup-findings.json</code>.</p>'
                f'<table><thead><tr><th>Sorgu / kaynak</th><th>Sonuç (kısa)</th></tr></thead><tbody>{ev}</tbody></table>'
                '<p><strong>Doğrulanamayanlar:</strong> Production ortamı (istek atılmadı); Microsoft Quality Management uygulamasının kurulu olup olmadığı; madde izleme kodları, neden kodları, raf tipi bayrakları, lokasyon kartı “Gerekli” ayarları ve fiziksel envanter sayım dönemleri (standart API’de yok); demo şirkette uçtan uca akışlar (yalnız mevcut kayıtlar okundu, işlem yapılmadı).</p>'
                f'{BACK}</section>')
    return toc, ''.join(body)


# ---------------------------------------------------------------- DevOps yorum taslakları
def strip_links(s):
    import re
    return re.sub(r'<a [^>]*>(.*?)</a>', r'\1', s)


def plain_status(key):
    return STATUS[key][1]


def story_comment(sid):
    s = STORIES[sid]
    tests = ''.join(f'<li>{strip_links(st)}<br><strong>Beklenen:</strong> {strip_links(ex)}</li>' for st, ex in s['tests'])
    opens = ''.join(f'<li>{strip_links(o)}</li>' for o in s['open'])
    state_short = {
        '712': 'Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş. şirketinde lokasyon, bölge, raf ve madde yok (hepsi 0); terminal ve terminal kullanıcısı tanımlı değil. BCWMS ortamda yüklü. Örnek kurgu yalnız DemoSandbox · KITOKO-TR-DEMO-V1’de: KITWMS (raf zorunlu, yönlendirilmiş), 6 bölge (KABUL, KALITE, DEPO-A, DEPO-B, SEVK, AYAR), 7 raf; diğer 7 demo lokasyon rafsız.',
        '713': 'Kitoko şirketinde kalite emri, kalite bölgesi ve karantina rafı yok. Üründe kalite emri ve terminal Kalite Denetimi ekranı var; kalite emri açık LP’nin yerleştirmesi engelleniyor. Ancak mal kabulde kalite emri otomatik açılmıyor ve “QC bitmeden mal kabul kapanamaz” kuralı yok; MS Quality Management köprüsü BC 28 beklediği için devre dışı.',
        '714': 'Kitoko şirketinde QC rafı / lot blokajı kurgusu yok (lokasyon ve madde yok). Demo KITWMS’te KALITE bölgesi ve Q-01 rafı var; satış/üretim belgesinde engel testi yapılmadı. Kalite sonucu ile lot blokajı ve toplama engeli üründe yok.',
        '1296': 'Kitoko şirketinde montaj emri ve reçete yok. Demo şirkette MN000001 montaj emri son kontrol olmadan kısmen nakledilmiş; standart BC’de ve BCWMS Montaj ekranında son kontrol adımı yok.',
        '1297': 'Kitoko şirketinde madde/lot kurgusu ve kalite emri yok. BCWMS kalite emri red sebebi ve karantina rafı tutar ama lot/seri alanı ve montaj bağı yok; iade/hurda kararı akışı yok.',
        '715': 'Kitoko şirketinde madde yok; lot/seri kurgusu kullanılmıyor. Demo şirkette 9.389 maddeden 2 test maddesi lot takipli, seri takipli 0; 1 lotlu giriş var (BCWMS ambar hareketi yanıtında lot boş göründü, incelenmeli).',
        '716': 'Kitoko şirketinde müşteri, tedarikçi, madde ve doğrudan sevkiyat satınalma kodu yok. Demo şirkette doğrudan sevkiyat satırı 0; senaryo test edilmedi.',
        '717': 'Kitoko şirketinde proje 0 ve PROJE boyutu yok. Demo şirkette PROJE boyutu, 454 proje ve KIT-UAT test projesi PR000001 (3 proje defter kaydı, proje no’lu 2 madde hareketi) var. BCWMS’te proje görünümü yok. İstenen “BC_Proje_Zaman_Cizelgesi_1.html” dosyası bulunamadı.',
        '718': 'Kitoko şirketinde sayım belgesi yok; sayılacak lokasyon/raf/madde yok. Ürün (BCWMS sayım, Count Variance raporu, fark onayı, fiziksel envanter günlüğüyle işleme) hazır.',
        '719': 'Kitoko şirketinde madde yok. Not: Madde Yeniden Sınıflandırma Günlüğü madde numarasını değiştirmez; madde A → B virmanı çift satırlı madde günlüğü veya montaj emriyle yapılır — yöntem kararı gerekli.',
    }[sid]
    sec = f'Feature #{s["feature"]} → {s["code"]} · #{sid}'
    return ('<p>Bu kayıt için gereksinim, çözüm, Kitoko şirketindeki güncel durum ve test adımları aşağıda özetlenmiştir (27.10.2026, BC’den yalnız okuma ile).</p>'
            f'<p><strong>Gereksinim:</strong> {strip_links(s["req"])}</p>'
            f'<p><strong>Çözüm:</strong> {html.escape(s["method_short"])}.</p>'
            f'<p><strong>Kitoko’daki durum:</strong> {plain_status(s["status"])}.<br>{state_short}</p>'
            f'<p><strong>Test adımları:</strong></p><ol>{tests}</ol>'
            f'<p><strong>Açık iş:</strong></p><ul>{opens}</ul>'
            f'<p>Ayrıntı: ekteki {REPORT_NAME}, {sec}. Kullanım adımları: ilgili Kitoko kılavuzları (KITOKO-El-Terminali-Stok-Hareketleri-Kilavuzu, KITOKO-Sayim-ve-Etiket-Kilavuzu, KITOKO-BC-Depo-ve-Stok-Kilavuzu).</p>')


def feature_comment(fid):
    f = next(x for x in FEATURES if x[0] == fid)
    items = ''.join(f'<li><strong>{STORIES[s]["code"]} (#{s})</strong> — {html.escape(STORIES[s]["short"])}: {plain_status(STORIES[s]["status"])}. Açık iş: {html.escape(STORIES[s]["open_short"])}</li>' for s in f[3])
    return (f'<p>Bu feature altındaki story’lerin 27.10.2026 durumu (Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş. şirketine göre):</p><ul>{items}</ul>'
            '<p>Ortak ön koşul: Kitoko şirketinde lokasyon/bölge/raf, madde ve BCWMS terminal/kullanıcı kurulumu henüz yapılmadı; kabul kriterleri bu kurulumdan sonra test edilebilir.</p>'
            f'<p>Ayrıntı: ekteki {REPORT_NAME}, Feature #{fid} — {html.escape(f[2].split("— ")[1])}.</p>')


def epic_comment():
    lines = ''.join(f'<li><strong>Feature #{fid}</strong> ({html.escape(ft.split("— ")[1])}): ' + ', '.join(f'{STORIES[s]["code"]} — {plain_status(STORIES[s]["status"])}' for s in sids) + '</li>' for fid, _, ft, sids, _ in FEATURES)
    return ('<p>Stok, Depo ve Kalite — Kitoko epic’i için karşılama durumu (27.10.2026, BC’den yalnız okuma ile):</p>'
            '<p><strong>Ana bulgu:</strong> Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş. şirketinde depo ve stok kurulumu henüz yapılmadı (lokasyon, raf, madde, tedarikçi, müşteri, proje, terminal, terminal kullanıcısı: 0). BCWMS uygulaması ortamda yüklü. Örnek kurgu yalnız DemoSandbox · KITOKO-TR-DEMO-V1 demo şirketinde var (KITWMS: 6 bölge, 7 raf; terminal KITOKO-01). Bugün hiçbir story Kitoko şirketinde “Karşılanıyor ve doğrulandı” değildir.</p>'
            f'<ul>{lines}</ul>'
            '<p><strong>Özet:</strong> 4 story standart BC/BCWMS ile karşılanıyor ve kurulum bekliyor (KIT-008, KIT-011, KIT-012, KIT-014); KIT-013 kurulum + detay rapor kararı (örnek rapor dosyası bulunamadı); KIT-015 kurulum + virman yöntemi kararı; KIT-009 kısmen mevcut, geliştirme gerekli; KIT-010, INV-009, INV-010 geliştirme gerekli (kalite emri otomasyonu, lot blokajı, montaj son kontrolü, lot/seri bağlı hata kaydı). Kalite tarafında BCWMS kalite emri ile BC 28 Microsoft Quality Management arasında karar gerekir.</p>'
            f'<p>Ayrıntı: ekteki {REPORT_NAME}, Özet ve durum tablosu; açık işler: Açık işler ve kararlar bölümü.</p>')


def build_drafts():
    d = {'1045': {'html': epic_comment()}}
    for fid, _, _, sids, _ in FEATURES:
        d[fid] = {'html': feature_comment(fid)}
        for sid in sids:
            d[sid] = {'html': story_comment(sid)}
    return d


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    toc, body = build_html()
    path = OUT / f'{STEM}.html'
    path.write_text(page(
        TITLE, 'Kitoko Aydınlatma ve Müh. A.Ş. · Stok, Depo ve Kalite',
        'Azure DevOps Epic #1045 kapsamındaki on gereksinim için çözüm yöntemini, Kitoko şirketindeki bugünkü gerçek durumu, '
        'kullanıcı adımlarını, kabul kriteri testlerini ve açık işleri bir arada verir.',
        toc, body,
        f'Hazırlayan: DynamicsOps · {DATE} · BCWMS Kitoko {VERSION}. Durum bilgileri BC’den yalnız okuma (GET) ile alınmıştır; '
        'Production ortamına istek atılmamıştır. Statüler kurulumu yapılmamış hiçbir şeyi “karşılanıyor” göstermez.'),
        encoding='utf-8')
    render_pdf(path, OUT / f'{STEM}.pdf')
    DRAFTS.write_text(json.dumps(build_drafts(), ensure_ascii=False, indent=2), encoding='utf-8')
    print(path)
    print(DRAFTS)


if __name__ == '__main__':
    main()
