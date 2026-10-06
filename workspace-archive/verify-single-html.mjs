import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('single-file-build/BCWMS-Guncel-Raporlar-1.14.5');
const output = path.resolve('teslim');
const manuals = [
  ['terminal', '01-El-Terminali-Kilavuzu', 'BCWMS-EL-TERMINALI-KILAVUZU.html'],
  ['sayim', '02-Sayim-Kilavuzu', 'BCWMS-SAYIM-KILAVUZU.html'],
];

const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const standaloneHtml = {};

for (const [id, folder, file] of manuals) {
  const filePath = path.join(output, 'ayri-kilavuzlar', file);
  const html = fs.readFileSync(filePath, 'utf8');
  standaloneHtml[id] = html;

  assert.ok(html.startsWith('<!doctype html>'), `${file}: doctype eksik`);
  assert.equal((html.match(/<\/html>/g) ?? []).length, 1, `${file}: HTML kapanışı hatalı`);
  assert.doesNotMatch(html, /(?:src|data-full)="assets\//, `${file}: yerel görsel referansı kaldı`);
  assert.doesNotMatch(html, /<script[^>]+src=|<link[^>]+href=|https?:\/\//, `${file}: harici bağımlılık kaldı`);

  const assetMatch = html.match(/const __BCWMS_ASSETS__=(\{.*\});/);
  assert.ok(assetMatch, `${file}: gömülü varlık paketi bulunamadı`);
  const assets = JSON.parse(assetMatch[1]);
  const referencedAssets = [...new Set([...html.matchAll(/data-asset="([^"]+)"/g)].map(match => match[1]))];
  assert.deepEqual(referencedAssets.sort(), Object.keys(assets).sort(), `${file}: görsel listesi eşleşmiyor`);

  for (const [assetPath, dataUri] of Object.entries(assets)) {
    const encoded = dataUri.slice(dataUri.indexOf(',') + 1);
    const embedded = Buffer.from(encoded, 'base64');
    const original = fs.readFileSync(path.join(root, folder, assetPath));
    assert.equal(hash(embedded), hash(original), `${file}: ${assetPath} verisi eşleşmiyor`);
  }

  for (const script of [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1])) {
    new Function(script);
  }
  console.log(`${file}: ${Object.keys(assets).length} görsel doğrulandı`);
}

const combinedPath = path.join(output, 'BCWMS-KILAVUZLAR-TEK-DOSYA.html');
const combined = fs.readFileSync(combinedPath, 'utf8');
assert.doesNotMatch(combined, /<script[^>]+src=|<link[^>]+href=|https?:\/\//, 'Birleşik dosyada harici bağımlılık kaldı');
const guideMatch = combined.match(/const GUIDES=(\{.*\});\n    const LABELS=/);
assert.ok(guideMatch, 'Birleşik dosyada kılavuz paketi bulunamadı');
const guides = JSON.parse(guideMatch[1]);
assert.deepEqual(guides, standaloneHtml, 'Birleşik dosyadaki kılavuzlar bağımsız sürümlerle eşleşmiyor');

const outerScriptStart = combined.indexOf('<script>\n    const GUIDES=');
const outerScriptEnd = combined.lastIndexOf('</script>');
assert.ok(outerScriptStart >= 0 && outerScriptEnd > outerScriptStart, 'Birleşik dosya betiği bulunamadı');
new Function(combined.slice(outerScriptStart + '<script>'.length, outerScriptEnd));
console.log('BCWMS-KILAVUZLAR-TEK-DOSYA.html: iki kılavuz ve betik yapısı doğrulandı');
