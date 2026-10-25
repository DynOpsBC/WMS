// Tasarım üzerinde değişmez (immutable) düzenleme işlemleri.
import { duplicateElement, nextElementId, sampleValues } from "./design";
import { barHeightFromBox, elementGeometry, isQuarterTurn, layoutContext, printBoundsDots, type LayoutContext } from "./layout";
import type { LabelDesign, LabelElement, LabelImage, Rotation } from "./types";
import { clamp, dotsPerMm, roundMm, snapMm } from "./units";

export type Handle = "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw";

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export function updateElement(design: LabelDesign, id: string, patch: Partial<LabelElement>): LabelDesign {
  let changed = false;
  const elements = design.elements.map((el) => {
    if (el.id !== id) return el;
    changed = true;
    return { ...el, ...patch };
  });
  return changed ? { ...design, elements } : design;
}

export function mapElements(design: LabelDesign, ids: readonly string[], fn: (el: LabelElement) => LabelElement): LabelDesign {
  const set = new Set(ids);
  let changed = false;
  const elements = design.elements.map((el) => {
    if (!set.has(el.id)) return el;
    const next = fn(el);
    if (next !== el) changed = true;
    return next;
  });
  return changed ? { ...design, elements } : design;
}

export function addElement(design: LabelDesign, el: LabelElement): LabelDesign {
  return { ...design, elements: [...design.elements, el] };
}

export function removeElements(design: LabelDesign, ids: readonly string[]): LabelDesign {
  const set = new Set(ids);
  const elements = design.elements.filter((el) => !set.has(el.id));
  return elements.length === design.elements.length ? design : { ...design, elements };
}

/** Seçili elemanları kopyalar (her kopya aslının hemen arkasına). Yeni kimlikleri döndürür. */
export function duplicateElements(design: LabelDesign, ids: readonly string[]): { design: LabelDesign; newIds: string[] } {
  const set = new Set(ids);
  const newIds: string[] = [];
  let working = design;
  const elements: LabelElement[] = [];
  for (const el of design.elements) {
    elements.push(el);
    if (set.has(el.id)) {
      const id = nextElementId({ ...working, elements: [...working.elements, ...elements] });
      const copy = duplicateElement(el, id);
      elements.push(copy);
      newIds.push(id);
      working = { ...working, elements: [...elements] };
    }
  }
  return { design: { ...design, elements }, newIds };
}

/** Konumu sınırla: sol/üst 0'ın altına inmez (ZPL ^FO negatif olamaz). */
export function clampPosition(x: number, y: number, design: LabelDesign): { x: number; y: number } {
  return {
    x: roundMm(clamp(x, 0, Math.max(0, design.widthMm - 0.5))),
    y: roundMm(clamp(y, 0, Math.max(0, design.heightMm - 0.5))),
  };
}

/** Başlangıç konumlarından dx/dy kadar taşı (ızgaraya ilk elemana göre yapışır). */
export function moveFrom(
  design: LabelDesign,
  starts: ReadonlyMap<string, { x: number; y: number }>,
  primaryId: string,
  dx: number,
  dy: number,
  step: number,
): LabelDesign {
  const primary = starts.get(primaryId);
  if (!primary) return design;
  // Birincil elemanı ızgaraya yapıştır, diğerleri aynı farkla gelsin.
  const px = snapMm(primary.x + dx, step);
  const py = snapMm(primary.y + dy, step);
  const ddx = px - primary.x;
  const ddy = py - primary.y;
  return mapElements(design, [...starts.keys()], (el) => {
    const s = starts.get(el.id);
    if (!s) return el;
    const p = clampPosition(s.x + ddx, s.y + ddy, design);
    return p.x === el.xMm && p.y === el.yMm ? el : { ...el, xMm: p.x, yMm: p.y };
  });
}

export function nudge(design: LabelDesign, ids: readonly string[], dx: number, dy: number): LabelDesign {
  return mapElements(design, ids, (el) => {
    const p = clampPosition(el.xMm + dx, el.yMm + dy, design);
    return { ...el, xMm: p.x, yMm: p.y };
  });
}

/** Döndürme merkezi koruyarak. Çizgi/kutu en-boy değiştirir, QR dönmez. */
export function rotateTo(el: LabelElement, rotation: Rotation, ctx: LayoutContext): LabelElement {
  if (el.type === "qr") return el;
  const geo = elementGeometry(el, ctx);
  const cx = geo.x + geo.w / 2;
  const cy = geo.y + geo.h / 2;
  if (el.type === "line" || el.type === "box") {
    const quarter = ((rotation - el.rotation + 360) % 180) === 90;
    if (!quarter) return el;
    return {
      ...el,
      wMm: el.hMm,
      hMm: el.wMm,
      xMm: roundMm(Math.max(0, cx - el.hMm / 2)),
      yMm: roundMm(Math.max(0, cy - el.wMm / 2)),
    };
  }
  if (rotation === el.rotation) return el;
  const next = { ...el, rotation, wMm: el.wMm > 0 ? el.wMm : geo.localW };
  const turned = isQuarterTurn(next);
  const nw = turned ? geo.localH : geo.localW;
  const nh = turned ? geo.localW : geo.localH;
  return { ...next, xMm: roundMm(Math.max(0, cx - nw / 2)), yMm: roundMm(Math.max(0, cy - nh / 2)) };
}

export function rotateClockwise(el: LabelElement, ctx: LayoutContext): LabelElement {
  return rotateTo(el, ((el.rotation + 90) % 360) as Rotation, ctx);
}

const MIN_SIZE = 1;
const MIN_LINE = 0.2;

/** Yeni sınır kutusunu (mm) tutamağa ve ızgaraya göre hesaplar. */
export function resizeBox(start: Box, handle: Handle, dx: number, dy: number, step: number, opts: { square?: boolean; keepAspect?: boolean; min?: number } = {}): Box {
  const min = opts.min ?? MIN_SIZE;
  let left = start.x;
  let top = start.y;
  let right = start.x + start.w;
  let bottom = start.y + start.h;
  if (handle.includes("w")) left = Math.min(snapMm(left + dx, step), right - min);
  if (handle.includes("e")) right = Math.max(snapMm(right + dx, step), left + min);
  if (handle.includes("n")) top = Math.min(snapMm(top + dy, step), bottom - min);
  if (handle.includes("s")) bottom = Math.max(snapMm(bottom + dy, step), top + min);
  let w = right - left;
  let h = bottom - top;
  const corner = handle.length === 2;
  if (opts.square) {
    const size = corner ? Math.max(w, h) : handle === "n" || handle === "s" ? h : w;
    w = size;
    h = size;
  } else if (opts.keepAspect && corner && start.w > 0 && start.h > 0) {
    const ratio = start.w / start.h;
    if (w / h > ratio) h = w / ratio;
    else w = h * ratio;
  }
  const x = handle.includes("w") ? start.x + start.w - w : start.x;
  const y = handle.includes("n") ? start.y + start.h - h : start.y;
  return { x: roundMm(Math.max(0, x)), y: roundMm(Math.max(0, y)), w: roundMm(w), h: roundMm(h) };
}

/**
 * Tutamakla boyutlandırma sonucu. Metinde dikey eksen (döndürmeye göre)
 * yazı boyunu büyütür/küçültür; diğerlerinde genişlik/yükseklik değişir.
 */
export function resizeElement(start: LabelElement, startGeo: Box, handle: Handle, dx: number, dy: number, step: number, ctx: LayoutContext): LabelElement {
  const turned = isQuarterTurn(start);
  if (start.type === "text" || start.type === "field") {
    const box = resizeBox(startGeo, handle, dx, dy, step, { min: 1 });
    const localW = turned ? box.h : box.w;
    const localH = turned ? box.w : box.h;
    const startLocalH = turned ? startGeo.w : startGeo.h;
    const verticalHandles = turned ? ["e", "w"] : ["n", "s"];
    const affectsFont = [...handle].some((c) => verticalHandles.includes(c));
    let next: LabelElement = { ...start, wMm: roundMm(localW) };
    if (affectsFont && startLocalH > 0) {
      const baseFont = start.fontMm > 0 ? start.fontMm : 2.75;
      const font = Math.max(1, Math.round(((baseFont * localH) / startLocalH) * 4) / 4);
      next = { ...next, fontMm: font };
    }
    const geo = elementGeometry(next, ctx);
    const x = handle.includes("w") ? startGeo.x + startGeo.w - geo.w : startGeo.x;
    const y = handle.includes("n") ? startGeo.y + startGeo.h - geo.h : startGeo.y;
    return { ...next, xMm: roundMm(Math.max(0, x)), yMm: roundMm(Math.max(0, y)), hMm: roundMm(geo.localH) };
  }
  const box = resizeBox(startGeo, handle, dx, dy, step, {
    square: start.type === "qr",
    keepAspect: start.type === "image",
    min: start.type === "line" ? MIN_LINE : MIN_SIZE,
  });
  const localW = turned ? box.h : box.w;
  const localH = turned ? box.w : box.h;
  const next: LabelElement = { ...start, xMm: box.x, yMm: box.y, wMm: roundMm(localW), hMm: roundMm(localH) };
  if (start.type === "line") next.thicknessMm = roundMm(Math.min(next.wMm, next.hMm));
  // Barkod kutusu alttaki yazıyı da kapsar; hMm çubuk yüksekliğidir.
  if (start.type === "barcode") next.hMm = roundMm(barHeightFromBox(next, localH, ctx));
  return next;
}

/** Elemanı bir noktaya ortalanmış yerleştir (paletten bırakma). */
export function placeAt(el: LabelElement, cxMm: number, cyMm: number, design: LabelDesign, ctx: LayoutContext, step: number): LabelElement {
  const geo = elementGeometry(el, ctx);
  const x = clamp(snapMm(cxMm - geo.w / 2, step), 0, Math.max(0, design.widthMm - geo.w));
  const y = clamp(snapMm(cyMm - geo.h / 2, step), 0, Math.max(0, design.heightMm - geo.h));
  return { ...el, xMm: roundMm(x), yMm: roundMm(y) };
}

/** Elemanı etikete sığacak şekilde küçült (yeni eleman). */
export function fitIntoLabel(el: LabelElement, design: LabelDesign): LabelElement {
  const maxW = Math.max(1, design.widthMm - 2);
  const maxH = Math.max(1, design.heightMm - 2);
  let { wMm, hMm } = el;
  if (el.type === "qr") {
    const s = Math.min(wMm, maxW, maxH);
    return { ...el, wMm: s, hMm: s };
  }
  if (wMm > maxW) {
    if (el.type === "image" && wMm > 0) hMm = (hMm * maxW) / wMm;
    wMm = maxW;
  }
  if (hMm > maxH && el.type !== "text" && el.type !== "field") {
    if (el.type === "image" && hMm > 0) wMm = (wMm * maxH) / hMm;
    hMm = maxH;
  }
  return { ...el, wMm: roundMm(wMm), hMm: roundMm(hMm) };
}

/** Gelen resimleri id'ye göre ekler/değiştirir. */
export function mergeImages(design: LabelDesign, incoming: readonly LabelImage[]): LabelDesign {
  if (incoming.length === 0) return design;
  const byId = new Map(design.images.map((i) => [i.id, i]));
  for (const img of incoming) byId.set(img.id, { ...byId.get(img.id), ...img });
  return { ...design, images: [...byId.values()] };
}

export function nextImageId(design: LabelDesign): string {
  const taken = new Set(design.images.map((i) => i.id));
  let n = 1;
  while (taken.has(`IMG${n}`)) n += 1;
  return `IMG${n}`;
}

/** Resim elemanının yüksekliğini resmin oranına göre ayarla (yerel, döndürülmemiş boyut). */
export function withImageAspect(el: LabelElement, naturalW: number, naturalH: number, design: LabelDesign): LabelElement {
  if (!(naturalW > 0 && naturalH > 0)) return el;
  const ratio = naturalH / naturalW;
  let w = el.wMm > 0 ? el.wMm : 20;
  let h = w * ratio;
  const maxH = Math.max(1, design.heightMm - (isQuarterTurn(el) ? 0 : el.yMm));
  if (h > maxH) {
    h = maxH;
    w = h / ratio;
  }
  return { ...el, wMm: roundMm(w), hMm: roundMm(h) };
}

/** Metin elemanında hMm'i yazı boyu ve satır sayısından günceller (BC'ye bilgi). */
export function syncTextHeight(el: LabelElement, ctx: LayoutContext): LabelElement {
  if (el.type !== "text" && el.type !== "field") return el;
  const h = roundMm(elementGeometry(el, ctx).localH);
  return h === el.hMm ? el : { ...el, hMm: h };
}

// ------------------------------------------------------------------ ölçü değişimi / sığdırma

/** 0,05 mm adımına yuvarla (yazı boyu gibi değerlerde gürültü kalmasın). */
const r05 = (mm: number) => Math.round(mm * 20) / 20;

/**
 * Elemanın ölçülerini oranlar (konumu değil). along = metin/barkod yönü (wMm),
 * across = ona dik eksen, s = yazı/QR/kalınlık gibi en-boy oranı korunan ölçüler.
 */
function scaleSize(el: LabelElement, along: number, across: number, s: number): LabelElement {
  switch (el.type) {
    case "text":
    case "field":
      return {
        ...el,
        wMm: el.wMm > 0 ? roundMm(el.wMm * along) : 0,
        fontMm: Math.max(1, r05((el.fontMm > 0 ? el.fontMm : 2.75) * s)),
        fontWidthMm: el.fontWidthMm > 0 ? Math.max(0.5, r05(el.fontWidthMm * s)) : 0,
        minFontMm: el.minFontMm > 0 ? Math.max(0.75, r05(el.minFontMm * s)) : 0,
      };
    case "barcode":
      return { ...el, wMm: el.wMm > 0 ? roundMm(el.wMm * along) : 0, hMm: Math.max(2, roundMm((el.hMm > 0 ? el.hMm : 10) * s)) };
    case "qr": {
      const side = Math.max(5, roundMm((el.wMm || el.hMm || 20) * s));
      return { ...el, wMm: side, hMm: side };
    }
    case "line": {
      const horizontal = el.wMm >= el.hMm;
      const thick = Math.max(0.13, roundMm(Math.min(el.wMm, el.hMm) * s));
      return horizontal
        ? { ...el, wMm: roundMm(el.wMm * along), hMm: thick, thicknessMm: thick }
        : { ...el, hMm: roundMm(el.hMm * across), wMm: thick, thicknessMm: thick };
    }
    case "box":
      return {
        ...el,
        wMm: Math.max(0.13, roundMm(el.wMm * along)),
        hMm: Math.max(0.13, roundMm(el.hMm * across)),
        thicknessMm: el.thicknessMm > 0 ? Math.max(0.13, roundMm(el.thicknessMm * s)) : 0,
      };
    case "image":
      return { ...el, wMm: Math.max(1, roundMm(el.wMm * s)), hMm: Math.max(1, roundMm(el.hMm * s)) };
    default:
      return el;
  }
}

/** Basılı alanın etiket koordinatında sınırı (mm): BC'nin ayırdığı kutu ∪ basılan kısım. */
function boundsMm(el: LabelElement, ctx: LayoutContext): { x0: number; y0: number; x1: number; y1: number } {
  const { box, ink } = printBoundsDots(el, ctx);
  const dpm = dotsPerMm(ctx.dpi);
  return {
    x0: Math.min(box.x0, ink.x0) / dpm,
    y0: Math.min(box.y0, ink.y0) / dpm,
    x1: Math.max(box.x1, ink.x1) / dpm,
    y1: Math.max(box.y1, ink.y1) / dpm,
  };
}

/**
 * Elemanı etiketin içine alır: önce kaydırır (güvenli kenara kadar, yer yoksa
 * etiket kenarına), etiketten büyükse küçültür. Sığan eleman değişmez.
 */
export function keepInside(el: LabelElement, design: LabelDesign, ctx: LayoutContext, marginMm = 0): LabelElement {
  const W = design.widthMm;
  const H = design.heightMm;
  let cur = el;
  for (let pass = 0; pass < 4; pass++) {
    const b = boundsMm(cur, ctx);
    const bw = b.x1 - b.x0;
    const bh = b.y1 - b.y0;
    if (bw > W + 0.01 || bh > H + 0.01) {
      const f = Math.min(1, (W - 2 * marginMm) / bw, (H - 2 * marginMm) / bh, W / bw, H / bh) * 0.98;
      const turned = isQuarterTurn(cur);
      const fx = Math.min(1, (W / bw) * 0.98);
      const fy = Math.min(1, (H / bh) * 0.98);
      const along = turned ? fy : fx;
      const across = turned ? fx : fy;
      cur = scaleSize(cur, along, across, Math.max(0.05, f));
      if (cur.type === "text" || cur.type === "field") cur = { ...cur, fit: true };
      continue;
    }
    const mx = bw <= W - 2 * marginMm ? marginMm : Math.max(0, (W - bw) / 2);
    const my = bh <= H - 2 * marginMm ? marginMm : Math.max(0, (H - bh) / 2);
    let dx = 0;
    let dy = 0;
    if (b.x0 < mx) dx = mx - b.x0;
    else if (b.x1 > W - mx) dx = W - mx - b.x1;
    if (b.y0 < my) dy = my - b.y0;
    else if (b.y1 > H - my) dy = H - my - b.y1;
    if (Math.abs(dx) < 0.005 && Math.abs(dy) < 0.005) break;
    cur = { ...cur, xMm: roundMm(Math.max(0, cur.xMm + dx)), yMm: roundMm(Math.max(0, cur.yMm + dy)) };
  }
  return syncTextHeight(cur, ctx);
}

/** Etiketten taşan elemanları (ya da verilenleri) içeri alır. */
export function fitElementsInside(design: LabelDesign, ctx: LayoutContext, marginMm = 0, ids?: readonly string[]): LabelDesign {
  const targets = ids ?? design.elements.map((e) => e.id);
  return mapElements(design, targets, (el) => {
    const next = keepInside(el, design, ctx, marginMm);
    return next.xMm === el.xMm && next.yMm === el.yMm && next.wMm === el.wMm && next.hMm === el.hMm && next.fontMm === el.fontMm ? el : next;
  });
}

/**
 * Etiket ölçüsünü değiştirir ve elemanları yeni ölçüye oranlar: konumlar eksene göre
 * (sx, sy), yazı/QR/kalınlık en küçük orana göre; sonra taşan kalırsa içeri alınır.
 * Kitoko (23 Eki 2026): 100×50 tasarımda 80×40 seçilince öğeler yerinde kalıp
 * etiketin dışına düşüyor, baskıda kesiliyordu.
 */
export function scaleDesignTo(design: LabelDesign, widthMm: number, heightMm: number): LabelDesign {
  if (!(design.widthMm > 0 && design.heightMm > 0)) return { ...design, widthMm, heightMm };
  const sx = widthMm / design.widthMm;
  const sy = heightMm / design.heightMm;
  const s = Math.min(sx, sy);
  const next: LabelDesign = { ...design, widthMm, heightMm };
  const ctx = layoutContext(next, sampleValues(next));
  const elements = design.elements.map((el) => {
    const turned = isQuarterTurn(el);
    let scaled = scaleSize(el, turned ? sy : sx, turned ? sx : sy, s);
    scaled = { ...scaled, xMm: roundMm(el.xMm * sx), yMm: roundMm(el.yMm * sy) };
    return keepInside(syncTextHeight(scaled, ctx), next, ctx, 0);
  });
  return { ...next, elements };
}

/**
 * Tüm tasarımı (öğelerin ortak sınır kutusunu) etiketin güvenli alanına oranlar:
 * tasarım küçülür ve kaydırılır, öğelerin birbirine göre yerleşimi korunur.
 */
export function fitAllToLabel(design: LabelDesign, ctx: LayoutContext, marginMm = 0): LabelDesign {
  const els = design.elements.filter((e) => e.enabled);
  if (els.length === 0) return design;
  const bs = els.map((e) => boundsMm(e, ctx));
  const x0 = Math.min(...bs.map((b) => b.x0));
  const y0 = Math.min(...bs.map((b) => b.y0));
  const x1 = Math.max(...bs.map((b) => b.x1));
  const y1 = Math.max(...bs.map((b) => b.y1));
  const W = design.widthMm;
  const H = design.heightMm;
  const f = Math.min(1, (W - 2 * marginMm) / (x1 - x0), (H - 2 * marginMm) / (y1 - y0));
  const ox = Math.max(marginMm, Math.min(x0, W - marginMm - (x1 - x0) * f));
  const oy = Math.max(marginMm, Math.min(y0, H - marginMm - (y1 - y0) * f));
  const moved: LabelDesign = {
    ...design,
    elements: design.elements.map((el) => {
      const scaled = f < 1 ? scaleSize(el, f, f, f) : el;
      return { ...scaled, xMm: roundMm(Math.max(0, ox + (el.xMm - x0) * f)), yMm: roundMm(Math.max(0, oy + (el.yMm - y0) * f)) };
    }),
  };
  return { ...moved, elements: moved.elements.map((el) => keepInside(syncTextHeight(el, ctx), moved, ctx, 0)) };
}

/** Ölçü değişince etiketin dışında kalacak eleman sayısı (yeni ölçüyle). */
export function countOutside(design: LabelDesign, widthMm: number, heightMm: number): number {
  const next: LabelDesign = { ...design, widthMm, heightMm };
  const ctx = layoutContext(next, sampleValues(next));
  return design.elements.filter((el) => {
    const b = boundsMm(el, ctx);
    return b.x0 < -0.01 || b.y0 < -0.01 || b.x1 > widthMm + 0.01 || b.y1 > heightMm + 0.01;
  }).length;
}

// ------------------------------------------------------------------ hizalama

export type AlignMode = "left" | "hcenter" | "right" | "top" | "vcenter" | "bottom";

/**
 * Hizalama: tek eleman etikete (güvenli kenar payıyla), birden çok eleman seçimin
 * sınır kutusuna göre hizalanır.
 */
export function alignElements(design: LabelDesign, ids: readonly string[], mode: AlignMode, ctx: LayoutContext, marginMm = 0): LabelDesign {
  const els = design.elements.filter((e) => ids.includes(e.id));
  if (els.length === 0) return design;
  const geos = new Map(els.map((e) => [e.id, elementGeometry(e, ctx)]));
  let ref: { x0: number; y0: number; x1: number; y1: number };
  if (els.length === 1) {
    ref = { x0: marginMm, y0: marginMm, x1: design.widthMm - marginMm, y1: design.heightMm - marginMm };
  } else {
    const all = [...geos.values()];
    ref = {
      x0: Math.min(...all.map((g) => g.x)),
      y0: Math.min(...all.map((g) => g.y)),
      x1: Math.max(...all.map((g) => g.x + g.w)),
      y1: Math.max(...all.map((g) => g.y + g.h)),
    };
  }
  return mapElements(design, ids, (el) => {
    const g = geos.get(el.id);
    if (!g) return el;
    let { xMm, yMm } = el;
    if (mode === "left") xMm = ref.x0;
    else if (mode === "right") xMm = ref.x1 - g.w;
    else if (mode === "hcenter") xMm = (ref.x0 + ref.x1) / 2 - g.w / 2;
    else if (mode === "top") yMm = ref.y0;
    else if (mode === "bottom") yMm = ref.y1 - g.h;
    else yMm = (ref.y0 + ref.y1) / 2 - g.h / 2;
    xMm = roundMm(Math.max(0, xMm));
    yMm = roundMm(Math.max(0, yMm));
    return xMm === el.xMm && yMm === el.yMm ? el : { ...el, xMm, yMm };
  });
}

/** En az üç elemanı yatay ya da dikey eşit aralıkla dağıtır (uçtakiler yerinde kalır). */
export function distributeElements(design: LabelDesign, ids: readonly string[], axis: "h" | "v", ctx: LayoutContext): LabelDesign {
  const items = design.elements
    .filter((e) => ids.includes(e.id))
    .map((e) => ({ el: e, g: elementGeometry(e, ctx) }))
    .sort((a, b) => (axis === "h" ? a.g.x + a.g.w / 2 - (b.g.x + b.g.w / 2) : a.g.y + a.g.h / 2 - (b.g.y + b.g.h / 2)));
  if (items.length < 3) return design;
  const size = (g: { w: number; h: number }) => (axis === "h" ? g.w : g.h);
  const start = axis === "h" ? items[0].g.x : items[0].g.y;
  const lastG = items[items.length - 1].g;
  const end = axis === "h" ? lastG.x + lastG.w : lastG.y + lastG.h;
  const total = items.reduce((sum, it) => sum + size(it.g), 0);
  const gap = (end - start - total) / (items.length - 1);
  const pos = new Map<string, number>();
  let cursor = start;
  for (const it of items) {
    pos.set(it.el.id, roundMm(Math.max(0, cursor)));
    cursor += size(it.g) + gap;
  }
  return mapElements(design, ids, (el) => {
    const p = pos.get(el.id);
    if (p === undefined) return el;
    return axis === "h" ? (p === el.xMm ? el : { ...el, xMm: p }) : p === el.yMm ? el : { ...el, yMm: p };
  });
}
