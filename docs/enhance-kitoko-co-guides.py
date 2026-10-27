#!/usr/bin/env python3
"""Kitoko kılavuzlarını görsellerle zenginleştirir (27 Ekim 2026).

generate-kitoko-co-*.py çıktılarını (output/kilavuzlar-kitoko/*.html) okur; kapak
bandı, akış şemaları (satır içi SVG) ve DemoSandbox · KITOKO-TR-DEMO-V1'den alınmış
gerçek BC ekranlarını ilgili bölümlere ekler, PDF'i yeniden basar. Üreticiler yeniden
çalıştırılırsa bu betik de yeniden çalıştırılır. Ekleme iki kez yapılmaz.
"""
import base64
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/kilavuzlar-kitoko'
SHOTS = Path.home() / 'Desktop/Kitoko/outputs/kitoko-stok-depo-kalite-20261027/screens'
MARK = '<!-- kitoko-enhanced -->'

CSS = """<style>
.hero{margin:6px 0 22px;padding:22px 24px;border-radius:14px;color:#fff;background:linear-gradient(120deg,#0f4c5c 0%,#158b86 55%,#4fb3a9 100%);box-shadow:0 6px 18px rgba(15,76,92,.18)}
.hero .kind{font-size:12px;letter-spacing:1.6px;text-transform:uppercase;opacity:.85;font-weight:700}
.hero .co{font-size:22px;font-weight:700;margin:4px 0 14px}
.hero .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
.hero .card{background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.25);border-radius:10px;padding:10px 12px;font-size:13.5px;line-height:1.35}
.hero .card b{display:block;font-size:20px;margin-bottom:2px}
h2{border-top:0!important;padding:10px 14px!important;background:linear-gradient(90deg,#e7f5f3,#fff);border-left:5px solid #158b86;border-radius:0 8px 8px 0}
h3{color:#0f4c5c}
.diagram{margin:14px 0 18px;padding:14px;border:1px solid #d9e6ea;border-radius:12px;background:#fbfdfd}
.diagram svg{width:100%;height:auto;display:block}
.diagram .cap,.shot figcaption{font-size:12.5px;color:#52677b;margin-top:8px}
.shot{margin:14px 0 18px}.shot img{width:100%;max-width:820px;border:1px solid #d4dde5;border-radius:10px;box-shadow:0 4px 14px rgba(20,38,59,.10);display:block}
table tr:nth-child(even) td{background:#f7fafb}
@media print{.hero{box-shadow:none}.shot img{box-shadow:none}.diagram,.shot{break-inside:avoid}}
</style>"""


def box(x, y, w, h, title, sub='', fill='#e1f3f0', stroke='#158b86'):
    t = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>'
    t += f'<text x="{x + w / 2}" y="{y + (h / 2 - 4 if sub else h / 2 + 5)}" text-anchor="middle" font-family="Arial" font-size="14" font-weight="700" fill="#0f2f3a">{title}</text>'
    if sub:
        t += f'<text x="{x + w / 2}" y="{y + h / 2 + 14}" text-anchor="middle" font-family="Arial" font-size="11.5" fill="#3c596c">{sub}</text>'
    return t


def arrow(x1, y1, x2, y2):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#158b86" stroke-width="2" marker-end="url(#a)"/>'


DEFS = '<defs><marker id="a" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#158b86"/></marker></defs>'


def flow(steps, caption, width=900):
    n = len(steps); gap = 26; w = (width - gap * (n - 1)) / n; h = 64
    body = ''.join(box(i * (w + gap), 8, w, h, t, s) + (arrow(i * (w + gap) + w + 2, 40, (i + 1) * (w + gap) - 4, 40) if i < n - 1 else '')
                   for i, (t, s) in enumerate(steps))
    return f'<div class="diagram"><svg viewBox="-2 0 {width + 4} 82" xmlns="http://www.w3.org/2000/svg">{DEFS}{body}</svg><div class="cap">{caption}</div></div>'


def hierarchy():
    zones = [('KABUL', 'K-01'), ('KALITE', 'Q-01'), ('DEPO-A', 'A-01-01 · A-01-02'), ('DEPO-B', 'B-01-01'), ('SEVK', 'S-01'), ('AYAR', 'AYAR-01')]
    w = 138; gap = 14; total = len(zones) * w + (len(zones) - 1) * gap
    s = box(total / 2 - 170, 6, 340, 52, 'KITWMS · Kitoko Gelişmiş Depo', 'Ambar (raf zorunlu, yönlendirilmiş)', '#0f4c5c', '#0f4c5c')
    s = s.replace('fill="#0f2f3a"', 'fill="#ffffff"').replace('fill="#3c596c"', 'fill="#d9f1ee"')
    for i, (z, b) in enumerate(zones):
        x = i * (w + gap)
        s += f'<path d="M{total / 2} 58 V78 H{x + w / 2} V96" fill="none" stroke="#9cc9c3" stroke-width="1.6"/>'
        s += box(x, 96, w, 46, z, 'Bölge')
        s += f'<line x1="{x + w / 2}" y1="142" x2="{x + w / 2}" y2="158" stroke="#9cc9c3" stroke-width="1.6"/>'
        s += box(x, 158, w, 40, b, '', '#ffffff', '#9cc9c3')
    return (f'<div class="diagram"><svg viewBox="-2 0 {total + 4} 204" xmlns="http://www.w3.org/2000/svg">{s}</svg>'
            '<div class="cap">Ambar → Bölge → Raf kırılımı. Kodlar DemoSandbox · KITOKO-TR-DEMO-V1 demo şirketinden alındı; '
            'Kitoko’nun gerçek şirketinde kurulumda kesinleşecek.</div></div>')


def status_bar():
    parts = [(4, 'Çözüm mevcut, kurulum gerekli', '#2f9e8f'), (2, 'Kurulum + karar gerekli', '#e0a43a'),
             (1, 'Kısmen mevcut, geliştirme gerekli', '#d9812f'), (3, 'Geliştirme gerekli', '#c8553d')]
    x = 0; bar = ''; leg = ''; W = 900
    for i, (n, label, c) in enumerate(parts):
        w = W * n / 10
        bar += f'<rect x="{x}" y="0" width="{w}" height="34" fill="{c}"/><text x="{x + w / 2}" y="22" text-anchor="middle" font-family="Arial" font-size="14" font-weight="700" fill="#fff">{n}</text>'
        leg += f'<rect x="{(i % 2) * 450}" y="{50 + (i // 2) * 24}" width="14" height="14" rx="3" fill="{c}"/><text x="{(i % 2) * 450 + 22}" y="{62 + (i // 2) * 24}" font-family="Arial" font-size="13" fill="#14263b">{label} ({n})</text>'
        x += w
    return (f'<div class="diagram"><svg viewBox="0 0 {W} 100" xmlns="http://www.w3.org/2000/svg"><clipPath id="r"><rect width="{W}" height="34" rx="8"/></clipPath>'
            f'<g clip-path="url(#r)">{bar}</g>{leg}</svg><div class="cap">10 user story’nin bugünkü durumu (27.10.2026). '
            'Hiçbiri henüz “karşılanıyor ve doğrulandı” değil; Kitoko şirketinde depo kurulumu yapılmadı.</div></div>')


def shot(name, caption):
    p = SHOTS / name
    if not p.exists():
        return ''
    data = base64.b64encode(p.read_bytes()).decode()
    return (f'<figure class="shot"><img src="data:image/png;base64,{data}" alt="{caption}"><figcaption>{caption} '
            '— Business Central · DemoSandbox · KITOKO-TR-DEMO-V1 (demo şirketi, gerçek Kitoko verisi değildir).</figcaption></figure>')


def hero(kind, cards):
    c = ''.join(f'<div class="card"><b>{i}</b>{t}</div>' for i, t in cards)
    return f'<div class="hero"><div class="kind">{kind}</div><div class="co">Kitoko Aydınlatma ve Müh. A.Ş.</div><div class="cards">{c}</div></div>'


INBOUND = flow([('Satınalma siparişi', 'tedarikçi sevki'), ('Ambar mal kabul', 'raf K-01'), ('Kalite kontrol', 'raf Q-01'),
                ('Yerleştirme', 'DEPO-A / DEPO-B'), ('Kullanılabilir stok', 'satış ve üretim')],
               'Hedef giriş akışı. Kalite adımının zorunlu hale getirilmesi Kitoko’da kurulum ve geliştirme bekliyor (bkz. karşılama raporu, KIT-009 / KIT-010).')
OUTBOUND = flow([('Satış siparişi', ''), ('Ambar sevkiyatı', 'BC belgesi'), ('Toplama', 'terminalde okut'), ('Sevk rafı', 'S-01'), ('Sevkiyat kaydı', 'irsaliye')],
                'Çıkış akışı: terminalde toplanan mal sevk rafına gelir, sevkiyat kaydedilir.')
COUNT = flow([('Alanı okut', ''), ('Rafı okut', ''), ('LP / ürün okut', 'adedi gir'), ('Rafı bitir', 'sayılmayan = 0'), ('Sorumlu onayı', 'stoklara işlenir')],
             'Sayım akışı (terminal). Farklar yalnız sorumlu onayından sonra stoklara işlenir.')
LABEL = flow([('Terminal', 'etiket ister'), ('Business Central', 'yazdırma işi'), ('Azure kuyruğu', 'istasyon oturumu'), ('Print Agent', 'yazıcı bilgisayarı'), ('Etiket yazıcısı', 'ZPL')],
             'Bir etiketin yolculuğu. Terminalde seçilen yazıcı, işin hangi istasyona gideceğini belirler.')

PLAN = {
    'KITOKO-BC-Depo-ve-Stok-Kilavuzu.html': (
        hero('Business Central · Depo ve stok kılavuzu', [('📦', 'Madde kartı ve stok sorgulama'), ('📥', 'Mal kabul, yerleştirme, sevkiyat'), ('🔁', 'Transfer ve raf hareketleri'), ('📋', 'Sayım ve stok raporları')]),
        {'lokasyonlar': shot('01-lokasyonlar.png', 'Konumlar listesi'), 'alanlar': hierarchy() + shot('02-lokasyon-kitwms.png', 'KITWMS konum kartı'),
         'urun-sorgu': shot('04-madde-lotlu.png', 'Lot izlemeli test maddesi ZZ-KIT-LOT'), 'mal-kabul': INBOUND + shot('05-mal-kabul.png', 'Ambar alış irsaliyesi WA000001 (kısmen alındı)'),
         'sevkiyat': OUTBOUND, 'sayim': COUNT}),
    'KITOKO-El-Terminali-Stok-Hareketleri-Kilavuzu.html': (
        hero('El terminali · Stok hareketleri kılavuzu', [('📥', 'Mal kabul'), ('🗄️', 'Yerleştirme'), ('🏭', 'Üretime çıkış'), ('🚚', 'Sevkiyat'), ('🔁', 'Transfer'), ('🔎', 'Sorgulama')]),
        {'mal-kabul': INBOUND, 'yerlestirme': hierarchy(), 'sevkiyat': OUTBOUND}),
    'KITOKO-Sayim-ve-Etiket-Kilavuzu.html': (
        hero('El terminali · Sayım ve etiket kılavuzu', [('🏷️', 'Sayım etiketleri (aralık)'), ('🖨️', 'Normal etiketler'), ('📋', 'Sayım ve İlk Sayım'), ('✅', 'Onay ve stoklara işleme')]),
        {'fark': LABEL, 'sayim-v2': COUNT}),
    'KITOKO-Stok-Depo-Kalite-Kilavuz-ve-Karsilama-Raporu.html': (
        hero('Karşılama raporu · Stok, Depo ve Kalite', [('10', 'user story'), ('3', 'feature'), ('4', 'kurulumla karşılanabilir'), ('4', 'geliştirme gerektiriyor')]),
        {'ozet': status_bar(), 's712': hierarchy() + shot('01-lokasyonlar.png', 'Konumlar listesi'), 's713': INBOUND + shot('05-mal-kabul.png', 'Ambar alış irsaliyesi WA000001'),
         's715': shot('04-madde-lotlu.png', 'Lot izlemeli test maddesi ZZ-KIT-LOT'), 's718': COUNT}),
}


def insert_after_heading(html, sid, block):
    m = re.search(rf'<section id="{re.escape(sid)}"><h([23])>.*?</h\1>', html, re.S)
    if not m:
        raise SystemExit(f'bölüm bulunamadı: {sid}')
    return html[:m.end()] + block + html[m.end():]


def render_pdf(html_path, pdf_path):
    pw = (ROOT / 'web/node_modules/@playwright/test/index.mjs').as_uri()
    script = (f"import {{ chromium }} from '{pw}';const b=await chromium.launch({{headless:true,channel:'chrome'}});"
              f"const p=await b.newPage();await p.goto('{html_path.as_uri()}');await p.pdf({{path:'{pdf_path}',format:'A4',printBackground:true,"
              "margin:{top:'14mm',right:'13mm',bottom:'14mm',left:'13mm'}});await b.close();")
    subprocess.run(['node', '--input-type=module', '-e', script], check=True)


def main():
    for name, (hero_html, sections) in PLAN.items():
        path = OUT / name
        html = path.read_text(encoding='utf-8')
        if MARK in html:
            print(name, 'zaten zenginleştirilmiş'); continue
        html = html.replace('</head>', CSS + '</head>', 1)
        html = re.sub(r'(<p class="lead">.*?</p>)', lambda m: m.group(1) + hero_html, html, count=1, flags=re.S)
        for sid, block in sections.items():
            if block:
                html = insert_after_heading(html, sid, block)
        html = html.replace('</main>', MARK + '</main>', 1)
        path.write_text(html, encoding='utf-8')
        render_pdf(path, path.with_suffix('.pdf'))
        print(name, 'zenginleştirildi')


if __name__ == '__main__':
    main()
