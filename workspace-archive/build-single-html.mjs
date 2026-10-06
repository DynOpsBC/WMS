import fs from 'node:fs';
import path from 'node:path';

const sourceRoot = path.resolve('single-file-build/BCWMS-Guncel-Raporlar-1.14.5');
const outputRoot = path.resolve('teslim');
const separateRoot = path.join(outputRoot, 'ayri-kilavuzlar');

const manuals = [
  {
    id: 'terminal',
    folder: '01-El-Terminali-Kilavuzu',
    file: 'BCWMS-EL-TERMINALI-KILAVUZU.html',
    label: 'El Terminali Kılavuzu',
    shortLabel: 'El Terminali',
  },
  {
    id: 'sayim',
    folder: '02-Sayim-Kilavuzu',
    file: 'BCWMS-SAYIM-KILAVUZU.html',
    label: 'Envanter Sayım Kılavuzu',
    shortLabel: 'Sayım',
  },
];

const mimeTypes = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
};

function inlineManual(manual) {
  const manualRoot = path.join(sourceRoot, manual.folder);
  const inputPath = path.join(manualRoot, 'index.html');
  let html = fs.readFileSync(inputPath, 'utf8');
  const assetPattern = /assets\/[A-Za-z0-9._/-]+/g;
  const assetPaths = [...new Set(html.match(assetPattern) ?? [])].sort();
  const embeddedAssets = {};

  for (const assetPath of assetPaths) {
    const absoluteAssetPath = path.resolve(manualRoot, assetPath);
    if (!absoluteAssetPath.startsWith(`${manualRoot}${path.sep}`)) {
      throw new Error(`Güvenli olmayan varlık yolu: ${assetPath}`);
    }
    const mimeType = mimeTypes[path.extname(assetPath).toLowerCase()];
    if (!mimeType) throw new Error(`Desteklenmeyen varlık türü: ${assetPath}`);
    embeddedAssets[assetPath] = `data:${mimeType};base64,${fs.readFileSync(absoluteAssetPath).toString('base64')}`;
  }

  html = html.replace(/<img\s+src="(assets\/[^"]+)"/g, '<img data-asset="$1"');
  html = html.replace(/\sdata-full="assets\/[^"]+"/g, '');
  html = html.replace(/([A-Za-z_$][\w$]*)\.dataset\.full/g, "$1.querySelector('img').src");

  const loader = `<script>
  const __BCWMS_ASSETS__=${JSON.stringify(embeddedAssets)};
  document.querySelectorAll('img[data-asset]').forEach(img=>{img.src=__BCWMS_ASSETS__[img.dataset.asset]});
</script>`;
  html = html.replace('</body>', `${loader}\n</body>`);

  if (/(?:src|data-full)="assets\/[^"]+"/.test(html)) {
    throw new Error(`${manual.label} içinde yerel varlık referansı kaldı.`);
  }
  return html;
}

function escapeForInlineScript(value) {
  return JSON.stringify(value)
    .replace(/<\/script/gi, '<\\/script')
    .replace(/<!--/g, '<\\!--');
}

function buildCombinedManual(inlinedManuals) {
  const guideObject = Object.fromEntries(inlinedManuals.map(({ manual, html }) => [manual.id, html]));
  const guideLabels = Object.fromEntries(inlinedManuals.map(({ manual }) => [manual.id, manual.label]));

  return `<!doctype html>
<html lang="tr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="BCWMS El Terminali ve Envanter Sayım Kılavuzları — internetsiz çalışan tek HTML dosyası.">
  <title>BCWMS Kullanıcı Kılavuzları</title>
  <style>
    :root{color-scheme:light;--navy:#14213d;--blue:#246bfd;--paper:#f5f7fb;--line:#dce2ec;--muted:#667085}
    *{box-sizing:border-box}
    html,body{height:100%;margin:0}
    body{display:flex;flex-direction:column;background:var(--paper);font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:var(--navy)}
    .toolbar{min-height:68px;display:flex;align-items:center;gap:14px;padding:10px 18px;background:#fff;border-bottom:1px solid var(--line);box-shadow:0 2px 10px rgba(20,33,61,.08);z-index:1}
    .brand{display:flex;flex-direction:column;min-width:max-content;margin-right:6px}
    .brand strong{font-size:15px;letter-spacing:.01em}.brand span{font-size:11px;color:var(--muted);margin-top:2px}
    .tabs{display:flex;gap:8px}
    button{border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--navy);font:inherit;font-weight:700;padding:10px 14px;cursor:pointer}
    button:hover{border-color:#aab5c6;background:#f8faff}
    button.active{border-color:var(--blue);background:var(--blue);color:#fff}
    .actions{display:flex;gap:8px;margin-left:auto}.actions button{font-size:13px;font-weight:650}
    iframe{flex:1;width:100%;border:0;background:#fff}
    .noscript{margin:auto;max-width:620px;padding:24px;text-align:center}
    @media(max-width:760px){.toolbar{align-items:stretch;flex-wrap:wrap}.brand{width:100%}.tabs{flex:1}.tabs button{flex:1}.actions{margin-left:0}.actions button{padding:9px 10px}}
    @media print{.toolbar{display:none}iframe{height:100vh}}
  </style>
</head>
<body>
  <header class="toolbar">
    <div class="brand"><strong>BCWMS Kullanıcı Kılavuzları</strong><span>Android 1.14.5 · AL 1.14.0.20</span></div>
    <nav class="tabs" aria-label="Kılavuz seçimi">
      ${inlinedManuals.map(({ manual }, index) => `<button type="button" data-guide="${manual.id}"${index === 0 ? ' class="active"' : ''}>${manual.shortLabel}</button>`).join('\n      ')}
    </nav>
    <div class="actions">
      <button type="button" id="open-guide">Yeni sekmede aç</button>
      <button type="button" id="print-guide">Yazdır / PDF</button>
    </div>
  </header>
  <iframe id="guide" title="${inlinedManuals[0].manual.label}"></iframe>
  <noscript><div class="noscript">Bu tek-dosya kılavuzu göstermek için tarayıcıda JavaScript açık olmalıdır.</div></noscript>
  <script>
    const GUIDES=${escapeForInlineScript(guideObject)};
    const LABELS=${escapeForInlineScript(guideLabels)};
    const frame=document.getElementById('guide');
    let activeGuide='${inlinedManuals[0].manual.id}';
    const showGuide=id=>{
      activeGuide=id;
      frame.title=LABELS[id];
      frame.srcdoc=GUIDES[id];
      document.querySelectorAll('[data-guide]').forEach(button=>button.classList.toggle('active',button.dataset.guide===id));
    };
    document.querySelectorAll('[data-guide]').forEach(button=>button.addEventListener('click',()=>showGuide(button.dataset.guide)));
    document.getElementById('open-guide').addEventListener('click',()=>{
      const url=URL.createObjectURL(new Blob([GUIDES[activeGuide]],{type:'text/html;charset=utf-8'}));
      window.open(url,'_blank','noopener');
      setTimeout(()=>URL.revokeObjectURL(url),60000);
    });
    document.getElementById('print-guide').addEventListener('click',()=>frame.contentWindow.print());
    showGuide(activeGuide);
  </script>
</body>
</html>`;
}

fs.mkdirSync(separateRoot, { recursive: true });
const inlinedManuals = manuals.map(manual => ({ manual, html: inlineManual(manual) }));

for (const { manual, html } of inlinedManuals) {
  fs.writeFileSync(path.join(separateRoot, manual.file), html);
}

fs.writeFileSync(
  path.join(outputRoot, 'BCWMS-KILAVUZLAR-TEK-DOSYA.html'),
  buildCombinedManual(inlinedManuals),
);

for (const filePath of [
  path.join(outputRoot, 'BCWMS-KILAVUZLAR-TEK-DOSYA.html'),
  ...manuals.map(manual => path.join(separateRoot, manual.file)),
]) {
  const size = fs.statSync(filePath).size;
  console.log(`${path.relative(process.cwd(), filePath)}\t${(size / 1024 / 1024).toFixed(2)} MB`);
}
