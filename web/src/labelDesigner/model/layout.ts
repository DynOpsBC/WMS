// Elemanların yazıcı noktası (dot) cinsinden yerleşimi — BC "DOPSWHS Label
// Layout Engine"in ZPL'de yaptığı hesapların aynısı (BC 1.14.3.13). Çizim
// (renderLabel), seçim kutuları (Stage) ve uyarılar (validate) bunu kullanır.
//
// Yerel koordinat: elemanın döndürülmemiş hali, (0,0) = sol üst. Etikette
// ^FO (xMm,yMm) döndürülmüş alanın sol üst köşesidir; 90/270'te alan h × w.
import { encodeCode128, encodeEan13, encodeGs1128, hasNonAsciiForCode128 } from "../render/barcode";
import { qrMatrix, type QrMatrix } from "../render/qr";
import { resolveValue } from "./design";
import type { LabelDesign, LabelElement } from "./types";
import { dotsPerMm, mmToDots } from "./units";
import {
  code128ModulesEstimate,
  fitFontMeasured,
  fitModuleWidth,
  glyphUnit,
  HUMAN_TEXT_GAP_DOTS,
  LINE_GAP_DOTS,
  maxChars,
  measuredWidth,
  QR_TOP_OFFSET_DOTS,
  qrMagnification,
  smallFontDots,
  wrapText,
} from "./zplMetrics";

export interface LayoutContext {
  dpi: number;
  labelWidthMm: number;
  labelHeightMm: number;
  values: ReadonlyMap<string, string>;
}

export function layoutContext(design: LabelDesign, values: ReadonlyMap<string, string>): LayoutContext {
  return { dpi: design.dpi, labelWidthMm: design.widthMm, labelHeightMm: design.heightMm, values };
}

const div = (a: number, b: number) => Math.trunc(a / b);

export function isQuarterTurn(el: LabelElement): boolean {
  return el.rotation === 90 || el.rotation === 270;
}

/** Yazı/barkod yönündeki uzunluk (nokta); 0 = etiket kenarına kadar (BC). */
function autoLength(el: LabelElement, ctx: LayoutContext, reserve: number): number {
  const w = mmToDots(el.wMm, ctx.dpi);
  if (w > 0) return w;
  if (isQuarterTurn(el)) return mmToDots(ctx.labelHeightMm, ctx.dpi) - mmToDots(el.yMm, ctx.dpi) - reserve;
  return mmToDots(ctx.labelWidthMm, ctx.dpi) - mmToDots(el.xMm, ctx.dpi) - reserve;
}

// ------------------------------------------------------------------ metin

export interface TextRun {
  text: string;
  /** yerel x (nokta) */
  x: number;
  /** yerel y (nokta) — satırın üstü */
  y: number;
  /** basılı genişlik (nokta) */
  width: number;
}

export interface TextLayout {
  boxW: number;
  fontH: number;
  fontW: number;
  runs: TextRun[];
  /** basılan satır sayısı */
  lineCount: number;
  /** basılan bloğun yüksekliği (nokta) */
  actualH: number;
  /** en çok satıra göre ayrılan yükseklik (nokta, yazı boyu küçülmeden) */
  reservedH: number;
  /** ^FB taşması: yazı kutuya sığmıyor, satırlar üst üste basılır */
  overflow: boolean;
  /** en çok satıra sığmadığı için sonu atılan metin */
  truncated: boolean;
}

function unitsOf(s: string): number {
  let u = 0;
  for (const ch of s) u += glyphUnit(ch);
  return u;
}

/** ^FB W,1 davranışı: genişliğe sığmayan metin alt satıra geçer (kelime, gerekirse karakter). */
function fbWrap(line: string, boxW: number, fontW: number): string[] {
  if (measuredWidth(line, fontW) <= boxW) return [line];
  const out: string[] = [];
  let current = "";
  for (const word of line.split(" ")) {
    const candidate = current === "" ? word : `${current} ${word}`;
    if (measuredWidth(candidate, fontW) <= boxW) {
      current = candidate;
      continue;
    }
    if (current !== "") out.push(current);
    current = "";
    let piece = "";
    for (const ch of word) {
      if (piece !== "" && div((unitsOf(piece) + glyphUnit(ch)) * fontW, 100) > boxW) {
        out.push(piece);
        piece = "";
      }
      piece += ch;
    }
    current = piece;
  }
  if (current !== "") out.push(current);
  return out.length > 0 ? out : [line];
}

/** Yazı boyu (nokta): 0 ise BC varsayılanı 2,75 mm. */
export function textFontDots(el: LabelElement, dpi: number): number {
  return mmToDots(el.fontMm, dpi) || mmToDots(2.75, dpi);
}

export function textBoxWidthDots(el: LabelElement, ctx: LayoutContext): number {
  return Math.max(8, autoLength(el, ctx, 0));
}

export function reservedTextHeightDots(el: LabelElement, dpi: number): number {
  const lines = Math.max(1, el.maxLines);
  return lines * textFontDots(el, dpi) + (lines - 1) * LINE_GAP_DOTS;
}

export function layoutText(el: LabelElement, value: string, ctx: LayoutContext): TextLayout {
  const boxW = textBoxWidthDots(el, ctx);
  let fontH = textFontDots(el, ctx.dpi);
  let fontW = mmToDots(el.fontWidthMm, ctx.dpi) || fontH;
  // ^A0'da kalın yok: kalın = genişlik ×1,2; sığdırma 1/1,2 genişliğe göre ölçülür.
  const fitW = el.bold ? div(boxW * 10, 12) : boxW;
  if (el.fit && value !== "") {
    let minH = mmToDots(el.minFontMm, ctx.dpi);
    if (minH === 0 || minH > fontH) minH = div(fontH, 2);
    const fitSize = fitFontMeasured(value, fitW, fontH, minH);
    fontW = fitFontMeasured(value, fitW, fitSize, 10);
    fontH = fitSize;
  }
  if (el.bold) fontW = Math.round(fontW * 1.2);
  const reservedH = reservedTextHeightDots(el, ctx.dpi);
  const runs: TextRun[] = [];
  let overflow = false;
  let truncated = false;
  let lines: string[] = [];
  if (value !== "") {
    if (el.maxLines > 1) {
      lines = wrapText(value, maxChars(fitW, fontH), el.maxLines);
      const normalized = value.replace(/^ +/, "").replace(/ +$/, "").replace(/ {2,}/g, " ");
      truncated = lines.join(" ").length < normalized.length;
    } else {
      lines = [value];
    }
    lines.forEach((line, index) => {
      const y = index * (fontH + LINE_GAP_DOTS);
      const segments = fbWrap(line, boxW, fontW);
      if (segments.length > 1) overflow = true;
      for (const seg of segments) {
        const width = measuredWidth(seg, fontW);
        const x = el.align === "center" ? div(boxW - width, 2) : el.align === "right" ? boxW - width : 0;
        runs.push({ text: seg, x, y, width });
      }
    });
  }
  const n = Math.max(1, lines.length);
  const actualH = n * fontH + (n - 1) * LINE_GAP_DOTS;
  return { boxW, fontH, fontW, runs, lineCount: lines.length, actualH, reservedH, overflow, truncated };
}

// ------------------------------------------------------------------ barkod

export type BarcodeKind = "code128" | "ean13" | "gs1-128";

export interface BarcodeLayout {
  /** basılan simge (EAN-13 verisi rakam değilse BC Code128 basar) */
  printed: BarcodeKind;
  boxW: number;
  barH: number;
  modules: string;
  moduleWidth: number;
  /** çubukların yerel x başlangıcı (nokta) */
  barX: number;
  barWidth: number;
  /** insan okunur yazı: BC (Label Canvas) mı, yazıcının kendi yorum satırı mı */
  humanSource: "canvas" | "printer" | "none";
  humanText: string;
  humanFont: number;
  /** yazı satırının yerel y'si */
  humanY: number;
  /** yazının ortalandığı aralık (yerel x) */
  humanBoxX: number;
  humanBoxW: number;
  /** yerel toplam yükseklik (çubuk + yazı) */
  totalH: number;
  nonAscii: boolean;
}

/** Yazıcının barkod yorum satırı (yaklaşık): yazı boyu modül genişliğiyle büyür. */
export function printerHumanFontDots(moduleWidth: number): number {
  return Math.min(60, Math.max(10, moduleWidth * 9));
}
const PRINTER_HUMAN_GAP_DOTS = 3;

export function barcodeBoxDots(el: LabelElement, ctx: LayoutContext): { w: number; h: number } {
  const w = autoLength(el, ctx, 16);
  const h = mmToDots(el.hMm, ctx.dpi) || mmToDots(10, ctx.dpi);
  return { w: Math.max(1, w), h };
}

/** BC Code128Modules: yalnız rakamsa çift hane sıkıştırma tahmini. */
function bcCode128Modules(data: string): number {
  return code128ModulesEstimate(data);
}

/** Yazı payı (nokta): değer boşsa da kutu kararlı kalsın diye tahmini değer. */
function humanExtraDots(el: LabelElement, ctx: LayoutContext, moduleWidth: number): number {
  if (!el.showText) return 0;
  if (el.rotation === 0 && el.symbology === "code128") return HUMAN_TEXT_GAP_DOTS + smallFontDots(ctx.labelHeightMm);
  return PRINTER_HUMAN_GAP_DOTS + printerHumanFontDots(moduleWidth);
}

export function layoutBarcode(el: LabelElement, value: string, ctx: LayoutContext): BarcodeLayout | null {
  if (value === "") return null;
  const { w: boxW, h: barH } = barcodeBoxDots(el, ctx);
  let printed: BarcodeKind = el.symbology;
  let modules: string;
  let humanText = value;
  let estimate: number;
  if (el.symbology === "ean13") {
    const digits = value.replace(/ /g, "");
    const enc = /^\d{12,13}$/.test(digits) ? encodeEan13(digits) : null;
    if (enc) {
      modules = enc.modules;
      humanText = enc.text;
      estimate = 95;
    } else {
      // BC: rakam değilse EAN-13 yerine Code128 basılır.
      printed = "code128";
      modules = encodeCode128(value).modules;
      estimate = bcCode128Modules(value);
    }
  } else if (el.symbology === "gs1-128") {
    const enc = encodeGs1128(value);
    modules = enc.modules;
    humanText = enc.text;
    estimate = bcCode128Modules(value.replace(/[() ]/g, "")) + 11;
  } else {
    modules = encodeCode128(value).modules;
    estimate = bcCode128Modules(value);
  }
  const moduleWidth = fitModuleWidth(estimate, boxW);
  const estWidth = estimate * moduleWidth;
  const barX = estWidth < boxW ? div(boxW - estWidth, 2) : 0;
  const barWidth = modules.length * moduleWidth;
  const canvasText = el.rotation === 0 && el.symbology === "code128";
  const humanSource: BarcodeLayout["humanSource"] = !el.showText ? "none" : canvasText ? "canvas" : "printer";
  const humanFont = canvasText ? smallFontDots(ctx.labelHeightMm) : printerHumanFontDots(moduleWidth);
  const humanY = barH + (canvasText ? HUMAN_TEXT_GAP_DOTS : PRINTER_HUMAN_GAP_DOTS);
  return {
    printed,
    boxW,
    barH,
    modules,
    moduleWidth,
    barX,
    barWidth,
    humanSource,
    humanText,
    humanFont,
    humanY,
    // BC kendi yazısını tahmini çubuk genişliğinde ortalar; yazıcı gerçek sembolün altında.
    humanBoxX: barX,
    humanBoxW: canvasText ? estWidth : barWidth,
    totalH: barH + humanExtraDots(el, ctx, moduleWidth),
    nonAscii: printed !== "ean13" && hasNonAsciiForCode128(value),
  };
}

// ------------------------------------------------------------------ QR

export interface QrLayout {
  side: number;
  magnification: number;
  matrix: QrMatrix | null;
  /** sembolün kutu içindeki üst boşluğu (Zebra ~10 nokta) */
  offsetY: number;
  symbolSize: number;
}

export function qrSideDots(el: LabelElement, ctx: LayoutContext): number {
  return mmToDots(el.wMm, ctx.dpi) || mmToDots(el.hMm, ctx.dpi) || mmToDots(20, ctx.dpi);
}

export function layoutQr(el: LabelElement, value: string, ctx: LayoutContext): QrLayout | null {
  if (value === "") return null;
  const side = qrSideDots(el, ctx);
  const magnification = qrMagnification(value, side);
  const matrix = qrMatrix(value);
  return { side, magnification, matrix, offsetY: QR_TOP_OFFSET_DOTS, symbolSize: (matrix?.size ?? 21) * magnification };
}

// ------------------------------------------------------------------ eleman

export interface ElementLayout {
  value: string;
  /** çizimde kullanılan yerel boyut (nokta, döndürülmemiş) */
  w: number;
  h: number;
  /** seçim kutusu yerel yüksekliği (nokta): metinde en çok satıra göre */
  boxH: number;
  text?: TextLayout;
  barcode?: BarcodeLayout;
  qr?: QrLayout;
}

export function layoutElement(el: LabelElement, ctx: LayoutContext): ElementLayout {
  const value = resolveValue(el, ctx.values);
  switch (el.type) {
    case "text":
    case "field": {
      const text = layoutText(el, value, ctx);
      return { value, w: text.boxW, h: text.actualH, boxH: Math.max(text.reservedH, text.actualH), text };
    }
    case "barcode": {
      const box = barcodeBoxDots(el, ctx);
      const barcode = layoutBarcode(el, value, ctx) ?? undefined;
      const h = barcode ? barcode.totalH : box.h + humanExtraDots(el, ctx, 2);
      return { value, w: box.w, h, boxH: h, barcode };
    }
    case "qr": {
      const side = qrSideDots(el, ctx);
      return { value, w: side, h: side, boxH: side, qr: layoutQr(el, value, ctx) ?? undefined };
    }
    default: {
      const w = mmToDots(el.wMm, ctx.dpi) || 1;
      const h = mmToDots(el.hMm, ctx.dpi) || 1;
      return { value, w, h, boxH: h };
    }
  }
}

// ------------------------------------------------------------------ geometri (mm)

export interface ElementGeometry {
  /** döndürülmemiş yerel boyut (mm) — seçim kutusu */
  localW: number;
  localH: number;
  /** etiket üzerindeki sınır kutusu (mm, döndürme dahil) */
  x: number;
  y: number;
  w: number;
  h: number;
  /** basılı içeriğin taştığı alan dahil sınır (mm): QR ofseti vb. */
  extent: { x: number; y: number; w: number; h: number };
}

/** Elemanın etiketteki kutusu (mm). */
export function elementGeometry(el: LabelElement, ctx: LayoutContext): ElementGeometry {
  const dpm = dotsPerMm(ctx.dpi);
  const lay = layoutElement(el, ctx);
  const localW = lay.w / dpm;
  const localH = lay.boxH / dpm;
  let extraBelow = 0;
  if (el.type === "qr" && lay.qr) extraBelow = Math.max(0, lay.qr.offsetY + lay.qr.symbolSize - lay.qr.side) / dpm;
  const turned = isQuarterTurn(el);
  const w = turned ? localH : localW;
  const h = turned ? localW : localH;
  return { localW, localH, x: el.xMm, y: el.yMm, w, h, extent: { x: el.xMm, y: el.yMm, w, h: h + extraBelow } };
}

/** Barkod kutusunun yerel yüksekliğinden (yazı dahil) çubuk yüksekliği (mm). */
export function barHeightFromBox(el: LabelElement, boxLocalHmm: number, ctx: LayoutContext): number {
  const dpm = dotsPerMm(ctx.dpi);
  const lay = layoutElement(el, ctx);
  const extraDots = lay.barcode ? lay.barcode.totalH - lay.barcode.barH : lay.h - (mmToDots(el.hMm, ctx.dpi) || mmToDots(10, ctx.dpi));
  return Math.max(1, boxLocalHmm - extraDots / dpm);
}

// ------------------------------------------------------------------ baskı sınırı (nokta)

/** Etiketin yazıcı noktası ölçüsü: BC ^PW / ^LL (203 dpi = 8 nokta/mm → 80×40 = 640×320). */
export function labelDots(ctx: LayoutContext): { w: number; h: number } {
  return { w: mmToDots(ctx.labelWidthMm, ctx.dpi), h: mmToDots(ctx.labelHeightMm, ctx.dpi) };
}

export interface DotBounds {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

/**
 * Elemanın yazıcıda kapladığı alan (nokta, etiket koordinatı). `box` BC'nin ayırdığı
 * kutudur (yazı kutusu ^FB × en çok satır, barkod + altındaki yazı, QR kenarı);
 * `ink` basılan kısımdır (QR sembolü ^FO'nun 10 nokta altından başlar).
 * Taşma `box ∪ ink` ile, güvenli kenar `ink` ile ölçülür.
 */
export function printBoundsDots(el: LabelElement, ctx: LayoutContext): { box: DotBounds; ink: DotBounds } {
  const lay = layoutElement(el, ctx);
  const x0 = mmToDots(el.xMm, ctx.dpi);
  const y0 = mmToDots(el.yMm, ctx.dpi);
  const turned = isQuarterTurn(el);
  const w = turned ? lay.boxH : lay.w;
  const h = turned ? lay.w : lay.boxH;
  const box = { x0, y0, x1: x0 + w, y1: y0 + h };
  if (el.type === "qr" && lay.qr) {
    const s = lay.qr.symbolSize;
    return { box, ink: { x0, y0: y0 + lay.qr.offsetY, x1: x0 + s, y1: y0 + lay.qr.offsetY + s } };
  }
  return { box, ink: box };
}

/** Etiketin dışına en çok taşan miktar (nokta; 0 = sığıyor). */
export function overflowDots(el: LabelElement, ctx: LayoutContext): number {
  const { box, ink } = printBoundsDots(el, ctx);
  const L = labelDots(ctx);
  const x0 = Math.min(box.x0, ink.x0);
  const y0 = Math.min(box.y0, ink.y0);
  const x1 = Math.max(box.x1, ink.x1);
  const y1 = Math.max(box.y1, ink.y1);
  return Math.max(0, -x0, -y0, x1 - L.w, y1 - L.h);
}

/** Basılan kısmın en yakın etiket kenarına uzaklığı (mm; negatif = taşıyor). */
export function edgeClearanceMm(el: LabelElement, ctx: LayoutContext): number {
  const { ink } = printBoundsDots(el, ctx);
  const L = labelDots(ctx);
  return Math.min(ink.x0, ink.y0, L.w - ink.x1, L.h - ink.y1) / dotsPerMm(ctx.dpi);
}
