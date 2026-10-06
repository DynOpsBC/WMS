import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('WMS/docs/sayim-kilavuzu-guncel');
const file = path.resolve('teslim/BCWMS-SAYIM-ADRES-BAZLI-KULLANICI-KILAVUZU-1.14.9.html');
const html = fs.readFileSync(file, 'utf8');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

assert.ok(html.startsWith('<!doctype html>'), 'doctype eksik');
assert.equal((html.match(/<\/html>/g) ?? []).length, 1, 'HTML kapanışı hatalı');
assert.doesNotMatch(html, /(?:src|data-full)="assets\//, 'yerel görsel referansı kaldı');
assert.doesNotMatch(html, /<script[^>]+src=|<link[^>]+href=|https?:\/\//, 'harici bağımlılık kaldı');
assert.match(html, /Adres Bazlı Sayım/);
assert.match(html, /Satır Üret düğmesi operatör düğmesi değildir/);
assert.match(html, /İlk raf ataması ile stok hareketini karıştırmayın/);
assert.match(html, /Local WMS Users/);
assert.match(html, /LP → raf bağlandı/);

const assetMatch = html.match(/const __BCWMS_ASSETS__=(\{.*\});document/);
assert.ok(assetMatch, 'gömülü varlık paketi bulunamadı');
const assets = JSON.parse(assetMatch[1]);
const referenced = [...new Set([...html.matchAll(/data-asset="([^"]+)"/g)].map(match => match[1]))].sort();
assert.deepEqual(referenced, Object.keys(assets).sort(), 'görsel listesi eşleşmiyor');

for (const [assetPath, dataUri] of Object.entries(assets)) {
  const embedded = Buffer.from(dataUri.slice(dataUri.indexOf(',') + 1), 'base64');
  const original = fs.readFileSync(path.join(root, assetPath));
  assert.equal(hash(embedded), hash(original), `${assetPath} gömülü veri eşleşmiyor`);
}

for (const script of [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1])) new Function(script);
console.log(`Doğrulandı: ${path.basename(file)} · ${Object.keys(assets).length} görsel · harici bağımlılık yok`);
