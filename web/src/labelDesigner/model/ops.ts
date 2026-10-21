// Tasarım üzerinde değişmez (immutable) düzenleme işlemleri.
import { duplicateElement, nextElementId } from "./design";
import { barHeightFromBox, elementGeometry, isQuarterTurn, type LayoutContext } from "./layout";
import type { LabelDesign, LabelElement, LabelImage, Rotation } from "./types";
import { clamp, roundMm, snapMm } from "./units";

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
