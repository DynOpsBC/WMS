#!/usr/bin/env python3
"""KITOKO şirketi (Kitoko Aydınlatma ve Müh. A.Ş.) Sayım ve Etiket Kılavuzu
(27 Ekim 2026, Android 1.14.201-kitoko).

generate-kitoko-guides.py'deki Element 4 sayım kılavuzundan uyarlanmıştır; yalnız
sayım ve etiket kılavuzunu üretir. Terminal ekran adımları aynıdır; şirket, bağlantı
ve kurulum durumu Kitoko'ya göredir.

Kurulum durumu (27.10.2026, yalnız GET ile doğrulandı; BCWMS items: blocked eq false):
- Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.: 0 ürün, 0 lokasyon, 0 raf, 0 sayım sayfası.
- DemoSandbox · KITOKO-TR-DEMO-V1: 9389 ürün (1251–2250 aralıklarının dördü de dolu,
  250'şer), 8 lokasyon, KITWMS lokasyonunda 7 raf, 0 sayım sayfası.

Tek sayfada kayan, içindekiler tıklanabilir HTML üretir; PDF'i Chrome basar.
Ekranlar gerçek uygulama ekranlarıdır (output/kitoko-1.14.200-release/screenshots).
"""
import base64
import html
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/kilavuzlar-kitoko'
SHOTS = ROOT / 'output/kitoko-1.14.200-release/screenshots'
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


def img(name):
    data = (SHOTS / name).read_bytes()
    return 'data:image/png;base64,' + base64.b64encode(data).decode()


def page(title, eyebrow, lead, toc, body, foot):
    links = ''.join(f'<a class="{"sub" if sub else ""}" href="#{a}">{html.escape(t)}</a>' for a, t, sub in toc)
    return (f'<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)}</title><style>{CSS}</style></head><body><div class="wrap">'
            f'<nav class="toc"><b>İçindekiler</b>{links}</nav><main id="top"><div class="eyebrow">{eyebrow}</div>'
            f'<h1>{html.escape(title)}</h1><p class="meta">{DATE} · BCWMS Kitoko {VERSION}</p><p class="lead">{lead}</p>'
            f'{body}<footer>{foot}</footer></main></div></body></html>')


BACK = '<p class="back"><a href="#top">↑ Başa dön</a></p>'

# ---------------------------------------------------------------- 1. Sayım ve etiket
SAYIM_TOC = [('amac', 'Bu kılavuz ne anlatır?', False), ('guncelle', '1. Terminali güncelleyin', False),
             ('fark', '2. İki tür etiket ve farkı', False), ('sayim-etiket', '3. Sayım etiketlerini basma', False),
             ('normal-etiket', '4. Normal etiket basma', False), ('urun', '4.1 Ürün etiketi', True),
             ('raf', '4.2 Raf ve alan etiketi', True), ('lp', '4.3 LP ve lot etiketi', True),
             ('sayim', '5. Normal sayım', False), ('sayim-v2', '5.1 Sayım (raf ve LP ile)', True),
             ('ilk-sayim', '5.2 İlk Sayım (yalnız madde)', True), ('onay', '5.3 Onay ve stoklara işleme', True),
             ('sorun', '6. Sorun olursa', False)]

SAYIM = f"""
<div class="warn"><strong>Kurulum bekliyor.</strong> 27 Ekim 2026 kontrolüne göre Kitoko’nun <strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong> şirketinde ürün, lokasyon, raf ve sayım kurulumu yok (0 ürün, 0 lokasyon, 0 raf). Bu şirkette sayım etiketi basılamaz ve sayım açılamaz; kurulum tamamlanınca kılavuz güncellenecektir. Bugün ürün verisi olan tek Kitoko bağlantısı <strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong> demo şirketidir: 9.389 engellenmemiş ürün, 8 lokasyon, <strong>KITWMS</strong> (Kitoko Gelişmiş Depo) lokasyonunda 7 raf. Bu şirkette de henüz açılmış bir sayım sayfası yoktur; ilk sayımı sorumlu açar.</div>
<section id="amac"><h2>Bu kılavuz ne anlatır?</h2>
<p>Kitoko Aydınlatma ve Müh. A.Ş. deposunda el terminaliyle yapılan iki işi anlatır: <strong>etiket basmak</strong> ve <strong>sayım yapmak</strong>. Terminalde etiket iki farklı amaçla basılır. Sayım hazırlığında çok sayıda ürüne sırayla etiket basmak için <em>sayım etiketleri</em> (aralık butonları) kullanılır. Günlük işte tek bir ürüne, rafa ya da LP’ye etiket basmak için <em>normal etiketler</em> kullanılır. Bu ikisinin farkı 2. bölümde anlatılır.</p>
<p>Sayım için de iki ekran vardır. <strong>Sayım</strong> ekranında raf ve LP okutularak adres bazlı sayım yapılır. <strong>İlk Sayım</strong> ekranında yalnız madde okutulup adet girilir. Her iki sayımın sonunda farklar ancak sorumlu onayıyla stoklara işlenir.</p>
<div class="info"><strong>Başlamadan önce:</strong> Terminal Wi-Fi’ye bağlı olsun. Etiket basacaksanız etiket yazıcısı, bağlı olduğu bilgisayar ve o bilgisayardaki BCWMS Print Agent açık olsun. Yazıcı kurulumu ayrı “Etiket Yazıcı Genel Kılavuzu”nda anlatılır.</div>
{BACK}</section>

<section id="guncelle"><h2>1. Terminali güncelleyin</h2>
<p>Bu kılavuzdaki ekranlar <strong>{VERSION}</strong> sürümüne aittir. Terminaliniz daha eski bir sürümdeyse önce güncelleyin. Güncelleme için Microsoft girişi veya PIN gerekmez; yalnız internet bağlantısı yeterlidir. Uygulamayı kaldırmanız gerekmez, kayıtlı ayarlarınız korunur.</p>
<ol class="steps">
<li>BCWMS Kitoko uygulamasını açın. Açılışta <strong>Yeni sürüm hazır</strong> penceresi çıkarsa doğrudan 3. adıma geçin.</li>
<li>Pencere çıkmazsa giriş ekranındaki <strong>Uygulamayı güncelle</strong> düğmesine, ardından <strong>Güncellemeyi Kontrol Et</strong> düğmesine dokunun.</li>
<li>Pencerede en güncel sürümü (bu kılavuz hazırlanırken <strong>v{VERSION}</strong>) görün ve <strong>İndir &amp; yükle</strong> düğmesine dokunun. İndirme birkaç saniye sürer. Görseldeki sürüm numarası farklı olabilir.</li>
<li>Android’in onay penceresinde <strong>Güncelle</strong>’ye dokunun. Kurulum bitince <strong>Aç</strong> ile uygulamaya dönün.</li>
</ol>
<div class="shots">
<figure><img src="{img('01-guncelleme-kontrol.png')}" alt="Güncellemeyi Kontrol Et düğmesi"><figcaption>A. Uygulama güncellemesi ekranı</figcaption></figure>
<figure><img src="{img('02-yeni-surum.png')}" alt="Yeni sürüm hazır penceresi"><figcaption>B. Yeni sürüm hazır → İndir &amp; yükle</figcaption></figure>
<figure><img src="{img('04-android-guncelle.png')}" alt="Android güncelleme onayı"><figcaption>C. Android onayı. Bu görüntü İngilizce bir emülatörden alındı; Türkçe terminalde düğme “Güncelle” yazar.</figcaption></figure>
</div>
<div class="note">Kurulum izni sorulursa <strong>Ayarlar → Bu kaynaktan izin ver</strong> seçeneğini açın, geri dönüp Güncelle’ye dokunun. Bu izin terminal başına bir kez sorulur.</div>
<p>Güncellemeden sonra giriş ekranında <strong>ortamı</strong> ve <strong>Kitoko</strong> şirketini kontrol edin, kendi terminal kullanıcınız ve PIN’inizle giriş yapın. Kitoko için iki bağlantı vardır:</p>
<table><thead><tr><th>Bağlantı</th><th>Durum (27.10.2026)</th></tr></thead><tbody>
<tr><td><strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong></td><td><strong>Kurulum bekliyor.</strong> 0 ürün, 0 lokasyon, 0 raf; sayım etiketi basılamaz, sayım açılamaz.</td></tr>
<tr><td><strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong></td><td>Demo şirketi. 9.389 ürün; KITWMS lokasyonunda 7 raf. Sayım etiketleri bu bağlantıda basılabilir.</td></tr>
</tbody></table>
<p>Sand2010’daki Kitoko kurulumu tamamlanana kadar etiket ve sayım denemeleri <strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong> bağlantısında yapılır. Bağlantıyı ana menüdeki <strong>Ortam / şirket değiştir</strong> ile değiştirebilirsiniz.</p>
{BACK}</section>

<section id="fark"><h2>2. İki tür etiket ve farkı</h2>
<p>İki etiket türü de aynı yerden basılır: ana menüde <strong>Etiket Çıkar</strong>. Fark, kaç etiket bastığınızda ve bunu ne için yaptığınızdadır.</p>
<table><thead><tr><th></th><th>Sayım etiketleri</th><th>Normal etiketler</th></tr></thead><tbody>
<tr><td><strong>Ne için?</strong></td><td>Sayım hazırlığında, rafta etiketi olmayan ürünlere sırayla toplu etiket basmak.</td><td>Günlük işte tek bir ürüne, rafa, alana ya da LP’ye etiket basmak (yeni gelen ürün, yıpranmış etiket, yeni raf).</td></tr>
<tr><td><strong>Nereden?</strong></td><td>Etiket Çıkar → <strong>Ürün Etiketi</strong> sekmesindeki aralık butonları (1251–1500, 1501–1750, 1751–2000, 2001–2250).</td><td>Etiket Çıkar → <strong>Raf Etiketi</strong>, <strong>Ürün Etiketi</strong> (ürün okutarak) veya <strong>LP Etiketi</strong> sekmesi.</td></tr>
<tr><td><strong>Hangi ürünler?</strong></td><td>Engellenmemiş ürünlerin madde numarasına göre sıralı listesinde, butonda yazan sıradaki ürünler. Tam blok 250 ürün.</td><td>Yalnız okuttuğunuz veya seçtiğiniz kayıt.</td></tr>
<tr><td><strong>Kaç etiket?</strong></td><td>Ürün başına bir etiket; bir butonla en fazla 250.</td><td>Seçtiğiniz adet kadar.</td></tr>
<tr><td><strong>Etiket görünümü</strong></td><td>ETIKETV2: QR + madde numarası (seçilen tasarım varsa o).</td><td>BC’de o etiket türü için etkin tasarım.</td></tr>
</tbody></table>
{BACK}</section>

<section id="sayim-etiket"><h2>3. Sayım etiketlerini basma</h2>
<p>Bu butonlar, sayım öncesinde ürünlerin etiketlerini toplu ve sıralı basmak için kondu. İlk 1250 ürünün etiketleri daha önce basıldığı için o aralıklar ekrandan kaldırıldı; ekranda yalnız sıradaki dört blok görünür.</p>
<ol class="steps">
<li><strong>Yazıcılar</strong> ekranında kullanacağınız etiket yazıcısını seçin. ZPL yazıcısında <strong>Etiket</strong> düğmesine dokunun.</li>
<li>Ana menüden <strong>Etiket Çıkar → Ürün Etiketi</strong> sekmesini açın.</li>
<li>Ekranın üstünde <strong>Etiket tasarımı</strong> seçicisi görünüyorsa QR + madde no için kullanılan <strong>ETIKETV2</strong> tasarımını seçin. Seçici görünmüyorsa butonlar ETIKETV2 ile basar.</li>
<li>Basmak istediğiniz aralığın butonuna dokunun. Terminal önce ürün listesini BC’den alır (“Ürün listesi alınıyor…”).</li>
<li>Açılan pencerede <strong>kaç etiket basılacağını</strong> kontrol edin ve <strong>Yazdır</strong>’a dokunun. Etiketler 50’şerlik paketler halinde ve sırayla gönderilir; bir paket yazıcıya ulaşmadan sonrakine geçilmez.</li>
<li><strong>Tamamlandı</strong> mesajını bekleyin. İlk etikette QR’ı ve madde numarasını kontrol edin, sonra bir sonraki aralığa geçin.</li>
</ol>
<div class="shots"><figure><img src="{img('03-urun-etiketi-araliklar.png')}" alt="Ürün Etiketi sekmesindeki dört aralık butonu"><figcaption>Etiket Çıkar → Ürün Etiketi. Üstte sayım etiketlerinin dört aralık butonu, altta tek ürün sorgusu.</figcaption></figure></div>
<table><thead><tr><th>Buton</th><th>Listede seçilen ürünler</th><th>Tam blok</th></tr></thead><tbody>
<tr><td>Ürün 1251–1500 etiketi</td><td>1251. ile 1500. ürün</td><td>250 etiket</td></tr>
<tr><td>Ürün 1501–1750 etiketi</td><td>1501. ile 1750. ürün</td><td>250 etiket</td></tr>
<tr><td>Ürün 1751–2000 etiketi</td><td>1751. ile 2000. ürün</td><td>250 etiket</td></tr>
<tr><td>Ürün 2001–2250 etiketi</td><td>2001. ile 2250. ürün</td><td>250 etiket</td></tr>
</tbody></table>
<div class="warn"><strong>Aynı aralığı iki kez başlatmayın.</strong> Çıktı gecikirse önce yazıcıya ve kuyruğa bakın. <strong>Durdur</strong>’a basarsanız gönderilmekte olan paket tamamlanır, sonra yeni gönderim durur; yazıcı kuyruğuna ulaşmış etiketler basılmaya devam edebilir.</div>
<p>Aralıklar madde numarasının kendisi değil, <strong>sıralı listedeki sıra numarasıdır</strong>. Örneğin “1251–1500” butonu, madde numarası 1251 olan ürünü değil, listede 1251. sıradaki ürünü basar. Listede o kadar ürün yoksa yalnız bulunan ürünler basılır.</p>
<div class="info"><strong>Kitoko’da aralıklar dolu mu?</strong> (27.10.2026, engellenmemiş ürünler, madde numarasına göre sıralı)<br>
<strong>DemoSandbox · KITOKO-TR-DEMO-V1:</strong> 9.389 ürün; dört aralığın dördü de tam blok (her biri 250 etiket, toplam 1.000).<br>
<strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.:</strong> 0 ürün; dört aralığın hiçbirinde ürün yok, butonlar “Bu aralıkta ürün yok” uyarısı verir. Kurulum bekliyor.</div>
{BACK}</section>

<section id="normal-etiket"><h2>4. Normal etiket basma</h2>
<p>Günlük işte tek bir kayda etiket basmak için Etiket Çıkar ekranındaki üç sekme kullanılır. Hepsinde önce yazıcının seçili olduğunu kontrol edin; yazıcı ve adet çoğunlukla bir sonraki adımda sorulur.</p>
<section id="urun"><h3>4.1 Ürün etiketi (tek ürün)</h3>
<ol class="steps">
<li>Etiket Çıkar → <strong>Ürün Etiketi</strong> sekmesini açın.</li>
<li>Aralık butonlarının altındaki <strong>Ürün No / LP No</strong> alanına ürünün barkodunu okutun ya da madde numarasını yazıp <strong>Sorgula</strong>’ya dokunun.</li>
<li>Ürün bulununca ürün bilgisi ve yazdırma düğmesi açılır. Yazıcıyı ve adedi seçip yazdırın.</li>
<li>Başka bir ürün için alanı temizleyip yeni barkodu okutun.</li>
</ol>
<div class="note">“… için ürün veya LP bulunamadı” mesajı, okutulan değerin BC’de bir madde ya da LP numarasıyla eşleşmediğini gösterir. Okuttuğunuz etiketin madde numarasını içerdiğini ve terminalin doğru ortam ile şirkete bağlı olduğunu kontrol edin.</div></section>
<section id="raf"><h3>4.2 Raf ve alan etiketi</h3>
<ol class="steps">
<li>Etiket Çıkar → <strong>Raf Etiketi</strong> sekmesini açın.</li>
<li><strong>Depo / lokasyon seç</strong> ile lokasyonu, ardından alanı seçin. Alanın rafları listelenir.</li>
<li>Tek raf için listeden rafı seçip <strong>Raf etiketini yazdır</strong>’a dokunun. Alanın tüm rafları için <strong>Toplu raf etiketi</strong>, alanın kendisi için <strong>Alan etiketini yazdır</strong> kullanılır.</li>
<li>Yazıcı ve adet sonraki adımda seçilir; <strong>Yazdırmaya hazır</strong> görününce onaylayın.</li>
</ol></section>
<section id="lp"><h3>4.3 LP ve lot etiketi</h3>
<ol class="steps">
<li>Etiket Çıkar → <strong>LP Etiketi</strong> sekmesini açın.</li>
<li>LP’nin QR’ını ya da SSCC barkodunu okutun. Okutmak yerine listeden de seçebilirsiniz: arama kutusuna LP no, ürün, lot veya raf yazın; en yeni LP’ler üstte gelir. Pasif LP’leri görmek için “Tümü”nü seçin.</li>
<li>LP kartı içeriğiyle açılır. LP’nin kendisi için <strong>LP Etiketi Yazdır</strong>’a, içindeki lotlar için <strong>Lot Etiketi Bas</strong>’a dokunun ve lot başına adedi girin.</li>
<li>Kartı kapatıp sıradaki LP’yi okutun. Ekran açıkken okutulan yeni LP doğrudan açılır.</li>
</ol></section>
{BACK}</section>

<section id="sayim"><h2>5. Normal sayım</h2>
<p>Kitoko terminalinde iki sayım ekranı vardır. Hangisini kullanacağınızı sorumlunuz belirler.</p>
<div class="warn">Sayım kurulumu bekliyor: Sand2010 Kitoko şirketinde lokasyon ve raf yok; DemoSandbox · KITOKO-TR-DEMO-V1’de KITWMS lokasyonu ve 7 raf var, ancak henüz açılmış sayım sayfası yok. Aşağıdaki adımlar sorumlu sayımı açtıktan sonra geçerlidir.</div>
<table><thead><tr><th>Ekran</th><th>Ne zaman?</th><th>Ne okutulur?</th></tr></thead><tbody>
<tr><td><strong>Sayım</strong></td><td>Rafları ve LP’leri belli olan depoda, adres bazlı sayım.</td><td>Alan → raf → LP / ürün / lot barkodu, sonra bulunan adet.</td></tr>
<tr><td><strong>İlk Sayım</strong></td><td>Depodaki ilk sayım; ürünler henüz raf/LP ile takip edilmiyorsa.</td><td>Yalnız maddenin QR’ı ve sayılan adet (raf zorunlu lokasyonda önce raf).</td></tr>
</tbody></table>
<section id="sayim-v2"><h3>5.1 Sayım (raf ve LP ile)</h3>
<ol class="steps">
<li>Ana menüden <strong>Sayım</strong>’ı açın. Size atanmış sayım sayfası listelenir; yoksa sorumlu <strong>Yeni V2 Sayımı Oluştur</strong> ile lokasyon kodunu girip sayımı açar.</li>
<li>Sayacağınız <strong>alanın etiketini okutun</strong> ya da <strong>Alanları Getir</strong> ile alanı seçin. Ekranda “Rafı okutun, sonra LP / ürün / lot barkodunu okutun” yazar.</li>
<li><strong>Rafın etiketini okutun.</strong> Ekranda o rafta sistemde görünen miktar ve rafın kalemleri gelir.</li>
<li>Raftaki her LP’nin, ürünün veya lotun barkodunu okutun ve <strong>bu rafta fiziksel olarak bulduğunuz miktarı</strong> girin. Stok bir LP içinde kayıtlıysa terminal sizden LP etiketini okutmanızı ister.</li>
<li>Raf bitince <strong>Rafı bitir</strong>’e dokunun. Rafta olması gerekip bulamadığınız kalemler için <strong>Rafı bitir · sayılmayanları 0 yaz</strong> kullanılır. Yanlış rafa geçtiyseniz <strong>Rafı değiştir</strong>.</li>
<li>Başka bir rafta bulduğunuz LP “Farklı rafta bulunan LP” olarak işaretlenir; diğer raftan otomatik düşülmez, fark onaydan sonra işlenir.</li>
<li>Bütün raflar bitince turu tamamlayın. Gerekirse sorumlu <strong>Yeni Turu Başlat</strong> ile ikinci sayım turunu açar ve <strong>Turları Yan Yana Karşılaştır</strong> ile farkları inceler.</li>
</ol>
<div class="note">Bağlantı koparsa okutma terminalde güvenle saklanır. Aynı işlemi tekrar göndermeden önce <strong>Yenile</strong> ile durumu kontrol edin. Ekrandaki “HATA:” satırı ne yapılması gerektiğini söyler; mesajı okuyup nedenini çözmeden okutmayı tekrarlamayın.</div></section>
<section id="ilk-sayim"><h3>5.2 İlk Sayım (yalnız madde)</h3>
<ol class="steps">
<li>Ana menüden <strong>İlk Sayım</strong>’ı açın. Açık bir İlk Sayım yoksa <strong>Yeni İlk Sayım</strong> → <strong>Oluştur ve Aç</strong> ile lokasyonu seçerek başlatın.</li>
<li>Lokasyon raf zorunluysa önce <strong>rafı okutun</strong>; ekranda “Raf: … · şimdi madde okutun” yazar.</li>
<li><strong>Maddenin QR’ını okutun</strong> ve <strong>sayılan adedi</strong> girin. Her okutma “TAMAM: madde +adet · toplam …” olarak onaylanır ve aynı maddenin adetleri toplanır.</li>
<li>Yanlış bir okutmayı silmek için <strong>Okutmalar</strong> listesinde satıra dokunun ve silmeyi onaylayın.</li>
<li>Sayım bitince <strong>Sayılanlar</strong> listesini kontrol edin. Stoklara işleme sorumlu tarafından yapılır (5.3).</li>
</ol>
<div class="warn">İlk Sayım’da seri takipli maddeler sayılamaz; LP etiketi okutursanız terminal maddenin QR’ını ister.</div></section>
<section id="onay"><h3>5.3 Onay ve stoklara işleme</h3>
<p>Sayım sonucu stokları değiştirir. Bu yüzden son adım yalnız sorumlu onayıyla yapılır: Sayım’da <strong>Onayla ve Stoklara İşle</strong>, İlk Sayım’da <strong>Stoğa İşle</strong> / <strong>Onayla ve İşle</strong>. Terminal “Bu farklar stoklara işlenecek ve belge kapanacak” diye sorar; onaydan sonra belge kapanır ve kayıt değiştirilemez. Onaydan önce farkları kontrol edin; yanlış okutmayı onaydan önce düzeltin.</p>
<div class="info">“Cevap alınamadı” uyarısı çıkarsa işleme düğmesine tekrar basmayın; <strong>Yenile</strong> ile işlemin BC’ye ulaşıp ulaşmadığını kontrol edin.</div></section>
{BACK}</section>

<section id="sorun"><h2>6. Sorun olursa</h2>
<table><thead><tr><th>Ne görüyorsunuz?</th><th>Ne yapın?</th></tr></thead><tbody>
<tr><td>Etiket çıkmıyor</td><td>Yazıcının açık ve rulosunun takılı olduğunu, bağlı bilgisayarın ve Print Agent’ın açık olduğunu, terminalde doğru yazıcının seçili olduğunu kontrol edin. Kuyruğa bakmadan aynı aralığı yeniden başlatmayın.</td></tr>
<tr><td>“Bu aralıkta ürün yok: … bağlantısında N ürün var” veya “BC’de etiket basılacak ürün bulunamadı”</td><td>Terminal ürünü olmayan bir bağlantıya bağlı. Kitoko’da bu, kurulumu bekleyen <strong>Sand2010 · Kitoko Aydınlatma ve Müh. A.Ş.</strong> bağlantısında beklenen durumdur (0 ürün). Ana menüden <strong>Ortam / şirket değiştir</strong> ile <strong>DemoSandbox · KITOKO-TR-DEMO-V1</strong> bağlantısını seçin.</td></tr>
<tr><td>“Ürün listesi alınamadı”</td><td>Bağlantı sorunu. Wi-Fi’yi kontrol edip tekrar deneyin.</td></tr>
<tr><td>“… için ürün veya LP bulunamadı”</td><td>Okutulan barkod BC’de bir maddeyle eşleşmiyor. Etiketi kontrol edin veya madde numarasını elle yazın.</td></tr>
<tr><td>Sayımda “rafı bu sayımın lokasyon/alan filtresinde bulunamadı”</td><td>Okuttuğunuz raf bu sayımın kapsamında değil. Doğru alanda olduğunuzu kontrol edin veya sorumluya bildirin.</td></tr>
<tr><td>“Etiket birden fazla stok kaydıyla eşleşiyor”</td><td>Ürün ve lot bilgisini içeren etiketi okutun.</td></tr>
</tbody></table>
<p>Çözülmeyen durumlarda ekranın görüntüsünü alıp, hangi ekranda hangi düğmeye bastığınızı da yazarak destek ekibine iletin.</p>
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
    docs = [
        ('KITOKO-Sayim-ve-Etiket-Kilavuzu', 'Sayım ve Etiket Kılavuzu', 'Kitoko · El terminali',
         'Kitoko Aydınlatma ve Müh. A.Ş. için el terminaliyle sayım etiketlerini ve normal etiketleri basmayı, adres bazlı sayımı ve İlk Sayım’ı adım adım anlatır.',
         SAYIM_TOC, SAYIM),
    ]
    for stem, title, eyebrow, lead, toc, body in docs:
        path = OUT / f'{stem}.html'
        path.write_text(page(title, eyebrow, lead, toc, body,
                             f'Hazırlayan: DynamicsOps · {DATE} · BCWMS Kitoko {VERSION}. Ekranlar gerçek uygulama ekranlarıdır.'),
                        encoding='utf-8')
        render_pdf(path, OUT / f'{stem}.pdf')
        print(path)


if __name__ == '__main__':
    main()
