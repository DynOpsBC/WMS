import fs from 'node:fs';
import path from 'node:path';

const sourceRoot = path.resolve('WMS/docs/sayim-kilavuzu-guncel');
const inputPath = path.join(sourceRoot, 'index.html');
const outputPath = path.resolve('teslim/BCWMS-SAYIM-ADRES-BAZLI-KULLANICI-KILAVUZU-1.14.9.html');
const customerOutputPath = path.resolve('teslim/BCWMS-SAYIM-ADRES-BAZLI-KULLANICI-KILAVUZU.html');
const mimeTypes = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml' };

let html = fs.readFileSync(inputPath, 'utf8');
const assetPattern = /assets\/[A-Za-z0-9._/-]+/g;
const assetPaths = [...new Set(html.match(assetPattern) ?? [])].sort();
const embeddedAssets = {};

for (const assetPath of assetPaths) {
  const absolute = path.resolve(sourceRoot, assetPath);
  if (!absolute.startsWith(`${sourceRoot}${path.sep}`)) throw new Error(`Güvenli olmayan varlık yolu: ${assetPath}`);
  const mime = mimeTypes[path.extname(assetPath).toLowerCase()];
  if (!mime) throw new Error(`Desteklenmeyen varlık türü: ${assetPath}`);
  embeddedAssets[assetPath] = `data:${mime};base64,${fs.readFileSync(absolute).toString('base64')}`;
}

html = html.replace(/<img\s+src="(assets\/[^"]+)"/g, '<img data-asset="$1"');
html = html.replace(/\sdata-full="assets\/[^"]+"/g, '');
const loader = `<script>const __BCWMS_ASSETS__=${JSON.stringify(embeddedAssets)};document.querySelectorAll('img[data-asset]').forEach(img=>{img.src=__BCWMS_ASSETS__[img.dataset.asset]});</script>`;
html = html.replace('</body>', `${loader}\n</body>`);

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, html);
fs.writeFileSync(customerOutputPath, html);
console.log(`${path.relative(process.cwd(), customerOutputPath)}\t${(fs.statSync(customerOutputPath).size / 1024 / 1024).toFixed(2)} MB\t${assetPaths.length} görsel`);
