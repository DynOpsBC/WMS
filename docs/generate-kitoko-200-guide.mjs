import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { chromium } from '../web/node_modules/@playwright/test/index.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'output/kitoko-1.14.200-release');
// Update screens exist only after the release is on the channel; until then a
// clearly marked placeholder stands in for them.
const missing = (name) => `data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="720" height="1280"><rect width="100%" height="100%" fill="#f3f6f8" stroke="#c9d6df" stroke-width="6" stroke-dasharray="24 16"/><text x="50%" y="48%" font-family="Arial" font-size="40" fill="#52677b" text-anchor="middle">Ekran yayından sonra</text><text x="50%" y="53%" font-family="Arial" font-size="40" fill="#52677b" text-anchor="middle">eklenecek</text><text x="50%" y="62%" font-family="Arial" font-size="28" fill="#8396a6" text-anchor="middle">${name}</text></svg>`)}`;
const img = async (name) => {
  try { return `data:image/png;base64,${(await readFile(path.join(output, 'screenshots', name))).toString('base64')}`; }
  catch (error) { if (error.code === 'ENOENT') return missing(name); throw error; }
};
const check = await img('01-guncelleme-kontrol.png');
const prompt = await img('02-yeni-surum.png');
const install = await img('04-android-guncelle.png');
const ranges = await img('03-urun-etiketi-araliklar.png');
const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kitoko · Element 4 | Sayım için ürün etiketleri</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#e9edf1;color:#14263b;font-family:Arial,sans-serif;font-size:10.5pt;line-height:1.48}
.page{width:210mm;min-height:297mm;margin:18px auto;background:white;padding:14mm 15mm 12mm;position:relative;break-after:page}
.eyebrow{font-size:9pt;letter-spacing:1.6px;color:#4e6986;font-weight:700;text-transform:uppercase}.top{display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #158b86;padding-bottom:8px;margin-bottom:16px}.version{font-size:9pt;color:#486176}
h1{font-size:25pt;line-height:1.12;letter-spacing:-.7px;margin:0 0 9px}h2{font-size:15pt;line-height:1.2;margin:0 0 8px}p{margin:0 0 10px}.lead{font-size:12pt;color:#42586b}.steps{list-style:none;padding:0;margin:14px 0}.steps li{display:flex;gap:10px;margin-bottom:10px}.number{flex:0 0 25px;height:25px;display:grid;place-items:center;border-radius:50%;background:#e1f3f0;color:#126b68;font-weight:700}.steptext{padding-top:1px}.shots{display:grid;grid-template-columns:repeat(3,1fr);gap:5mm;margin:14px 0 10px}figure{margin:0}figure img{width:100%;height:auto;border:1px solid #d4dde5;border-radius:6px;display:block}figcaption{font-size:8pt;line-height:1.3;margin-top:6px;color:#52677b}strong{color:#102a41}.note{padding:10px 12px;border-left:3px solid #158b86;background:#eff8f7;border-radius:0 5px 5px 0;font-size:9.5pt}.small{font-size:8.5pt;color:#536879}.footer{font-size:8pt;color:#63778a;border-top:1px solid #dbe4eb;padding-top:7px;display:flex;justify-content:space-between;margin-top:16px}.print-grid{display:grid;grid-template-columns:60mm 1fr;gap:9mm;margin:16px 0}.print-grid .steps{margin-top:0}.print-grid .steps li{margin-bottom:14px}table{border-collapse:collapse;width:100%;margin:10px 0 14px;font-size:10pt}td,th{text-align:left;padding:8px 10px;border-bottom:1px solid #dbe4eb}th{background:#edf4f7;color:#3c596c;font-size:9pt}.help{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:14px}.help p{font-size:9pt}.help strong{display:block;margin-bottom:4px}.tag{color:#10756f;font-size:9pt;font-weight:700;margin-top:9px}.toc{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}.toc a{font-size:9pt;color:#0f5f5b;background:#e1f3f0;border-radius:14px;padding:4px 11px;text-decoration:none;font-weight:700}.toc a:hover{background:#c9ebe6}.test{padding:10px 12px;border-left:3px solid #c98a12;background:#fff6e3;border-radius:0 5px 5px 0;font-size:9.5pt;margin:0 0 12px}
@page{size:A4;margin:0}@media print{body{background:white}.page{margin:0;height:297mm;min-height:0}.page:last-child{break-after:auto}}@media screen and (max-width:800px){.page{width:100%;min-height:0;margin:0;padding:22px}.shots{gap:8px}.print-grid{grid-template-columns:minmax(140px,40%) 1fr;gap:15px}h1{font-size:25px}.version{font-size:10px}.help{grid-template-columns:1fr}}
</style></head><body>
<section class="page" id="guncelleme">
<div class="top"><div class="eyebrow">Kitoko / Element 4</div><div class="version">27 Ekim 2026 · 1.14.200-kitoko</div></div>
<h1>Sayım için ürün etiketleri</h1>
<nav class="toc"><a href="#guncelleme">1. Terminali güncelleyin</a><a href="#yazdirma">2. Sayım etiketlerini yazdırın</a><a href="#sorun">Sorun olursa</a></nav>
<div class="test"><strong>Bu kılavuz sayımda kullandığımız ürün etiketleri içindir.</strong> 1251–2250 arasındaki aralık butonları, sayım sırasında ürünlere etiketi sırayla ve toplu basmak için kondu. Genel etiket akışı (etiket tasarımı, raf/LP etiketi, yazıcı ve print agent ayarı) ayrı “Etiket Yazıcı Kılavuzu”nda anlatılır.</div>
<h2>1. Terminali güncelleyin</h2>
<p class="lead">Wi-Fi açık olsun. BCWMS Kitoko uygulamasını açın.</p>
<ol class="steps">
<li><span class="number">1</span><div class="steptext">Uygulama açılırken <strong>Yeni sürüm hazır</strong> penceresi çıkarsa doğrudan 3. adıma geçin. Çıkmazsa <strong>Uygulamayı güncelle</strong> düğmesine dokunun; Microsoft girişi veya PIN gerekmez.</div></li>
<li><span class="number">2</span><div class="steptext"><strong>Güncellemeyi Kontrol Et</strong> düğmesine dokunun.</div></li>
<li><span class="number">3</span><div class="steptext"><strong>1.14.200-kitoko</strong> görününce <strong>İndir &amp; yükle</strong> düğmesine dokunun.</div></li>
<li><span class="number">4</span><div class="steptext">Android ekranında <strong>Güncelle</strong> düğmesine dokunun.<br>Kurulum bitince <strong>Aç</strong> ile uygulamaya dönün.</div></li>
</ol>
<div class="shots">
<figure><img src="${check}" alt="Kurulu 1.14.199 sürümündeki Güncellemeyi Kontrol Et düğmesi"><figcaption><b>A.</b> Güncellemeyi Kontrol Et</figcaption></figure>
<figure><img src="${prompt}" alt="Yeni 1.14.200-kitoko sürümü ve İndir & yükle düğmesi"><figcaption><b>B.</b> İndir &amp; yükle</figcaption></figure>
<figure><img src="${install}" alt="Android uygulama güncellemesini onaylama ekranı"><figcaption><b>C.</b> Güncelle (bu emülatör İngilizce olduğu için “Update” yazıyor; Türkçe terminalde “Güncelle”)</figcaption></figure>
</div>
<div class="note"><strong>Kontrol:</strong> Güncelleme ekranında mevcut sürüm <strong>1.14.200-kitoko</strong> olmalı. Uygulamayı kaldırmanız gerekmez.</div>
<p class="small" style="margin-top:9px">Kurulum izni sorulursa Ayarlar → Bu kaynaktan izin ver seçeneğini açın, geri dönüp Güncelle’ye dokunun. Menü adı cihazın Android sürümüne göre değişebilir.</p>
<div class="footer"><span>Gerçek uygulama ekranları · Android emülatörü</span><span>1 / 2</span></div>
</section>
<section class="page" id="yazdirma">
<div class="top"><div class="eyebrow">Kitoko / Element 4</div><div class="version">QR + madde no etiketi</div></div>
<h2>2. Sayım etiketlerini yazdırın</h2>
<p class="lead">Etiket yazıcısı, bağlı olduğu bilgisayar ve yazıcı ajanı açık olsun.</p>
<div class="print-grid">
<figure><img src="${ranges}" alt="Ürün Etiketi ekranında yalnız 1251–1500, 1501–1750, 1751–2000 ve 2001–2250 butonları"><figcaption>Etiket Çıkar → Ürün Etiketi.<br>Yeni sürümde yalnız bu dört aralık görünür. Görüntü çevrimdışı test uygulamasından alınmıştır; canlı ürün verisi içermez.</figcaption></figure>
<ol class="steps">
<li><span class="number">1</span><div class="steptext">Girişte doğru ortamı ve <strong>Element 4 Dizayn Müh. End. A.Ş.</strong> şirketini kontrol edin. Kendi terminaliniz ve PIN’inizle giriş yapın.</div></li>
<li><span class="number">2</span><div class="steptext"><strong>Yazıcılar</strong> ekranında kullanacağınız etiket yazıcısını seçin. ZPL yazıcısında <strong>Etiket</strong> düğmesine dokunun.</div></li>
<li><span class="number">3</span><div class="steptext">Ana menüden <strong>Etiket Çıkar → Ürün Etiketi</strong> yolunu açın.</div></li>
<li><span class="number">4</span><div class="steptext"><strong>Etiket tasarımı</strong> görünüyorsa QR + madde no için kullanılan <strong>ETIKETV2</strong> tasarımını seçin. Seçici görünmüyorsa aralık butonları ETIKETV2 akışını kullanır.</div></li>
<li><span class="number">5</span><div class="steptext">İstediğiniz aralığa dokunun. Açılan pencerede etiket sayısını kontrol edip <strong>Yazdır</strong> düğmesine dokunun.</div></li>
<li><span class="number">6</span><div class="steptext"><strong>Tamamlandı</strong> mesajını bekleyin ve çıkan etiketi kontrol edin. Sonra gerekiyorsa diğer aralığı başlatın.</div></li>
</ol>
</div>
<table><thead><tr><th>Aralık butonu</th><th>Listede seçilen ürünler</th><th>Tam blok</th></tr></thead><tbody>
<tr><td>1251–1500</td><td>1251. ile 1500. ürün</td><td>250 etiket</td></tr>
<tr><td>1501–1750</td><td>1501. ile 1750. ürün</td><td>250 etiket</td></tr>
<tr><td>1751–2000</td><td>1751. ile 2000. ürün</td><td>250 etiket</td></tr>
<tr><td>2001–2250</td><td>2001. ile 2250. ürün</td><td>250 etiket</td></tr>
</tbody></table>
<div class="note">Aralıklar, bloke olmayan ürünlerin <strong>madde numarasına göre sıralanmış listesindeki sıra numaralarıdır.</strong> Ürün sayısı azsa yalnız bulunan ürünlerin etiketi basılır. Her ürün için bir etiket gönderilir.</div>
<div class="help" id="sorun"><p><strong>Çıktı gelmiyorsa</strong>Yazıcı seçimini, ruloyu, bilgisayarı ve yazıcı ajanını kontrol edin. Kuyruktaki işi kontrol etmeden aynı aralığı yeniden başlatmayın.</p><p><strong>Durdur’a basarsanız</strong>Gönderilmekte olan paket tamamlanınca yeni gönderim durur. Yazıcı kuyruğundaki etiketler basılmaya devam edebilir.</p></div>
<div class="footer"><span>İlk fiziksel etikette QR’ı ve madde numarasını kontrol edin.</span><span>2 / 2</span></div>
</section></body></html>`;
const htmlPath = path.join(output, 'KITOKO-Element4-Sayim-Urun-Etiketleri-1.14.200.html');
await writeFile(htmlPath, html);
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
try {
  const page = await browser.newPage({ viewport: { width: 1000, height: 1300 }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(htmlPath).href);
  await page.evaluate(() => document.fonts.ready);
  const layout = await page.locator('.page').evaluateAll(nodes => nodes.map(node => ({ id: node.id, height: node.getBoundingClientRect().height, scrollHeight: node.scrollHeight })));
  // 297 mm at 96 dpi: a taller page would print onto an extra sheet.
  for (const row of layout) if (row.scrollHeight > row.height + 1 || row.height > 1123) throw new Error(`Guide overflow: ${JSON.stringify(row)}`);
  await page.pdf({ path: path.join(output, 'KITOKO-Element4-Sayim-Urun-Etiketleri-1.14.200.pdf'), printBackground: true, preferCSSPageSize: true });
  for (const id of ['guncelleme', 'yazdirma']) await page.locator(`#${id}`).screenshot({ path: path.join(output, `guide-preview-${id}.png`) });
  console.log(JSON.stringify({ htmlPath, layout }));
} finally { await browser.close(); }
