// Etiketi canvas'a yazıcı noktası (dot) ölçeğinde çizer: BC'nin ZPL'de
// koyacağı konum, yazı boyu, barkod modülü ve QR büyütmesiyle aynı.
import { isKnownType } from "../model/design";
import { layoutElement, type LayoutContext } from "../model/layout";
import type { LabelDesign, LabelElement } from "../model/types";
import { mmToDots } from "../model/units";
import { measuredWidth } from "../model/zplMetrics";
import type { MonoBitmap } from "./gf";

/** Zebra font 0'a (CG Triumvirate Bold Condensed) yakın; genişlik her satırda ölçüyle ayarlanır. */
export const ZEBRA_FONT_STACK = '"Arial Narrow", "Roboto Condensed", "Helvetica Neue", Arial, "Liberation Sans", sans-serif';
/** Satır üstünden taban çizgisine oran (font 0). */
const BASELINE_RATIO = 0.8;
const PLACEHOLDER = "#9aa3b2";

export interface RenderOptions {
  /** canvas pikseli / nokta */
  scale: number;
  ctx: LayoutContext;
  /** resim elemanının basılacak 1 bit hali (döndürülmüş); yoksa null */
  imageBitmap: (el: LabelElement) => MonoBitmap | null;
  /** pasif elemanları soluk çiz */
  showDisabled: boolean;
}

export function renderLabel(g: CanvasRenderingContext2D, design: LabelDesign, opts: RenderOptions): void {
  const wDots = mmToDots(design.widthMm, design.dpi);
  const hDots = mmToDots(design.heightMm, design.dpi);
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.globalAlpha = 1;
  g.globalCompositeOperation = "source-over";
  g.clearRect(0, 0, g.canvas.width, g.canvas.height);
  g.setTransform(opts.scale, 0, 0, opts.scale, 0, 0);
  g.fillStyle = "#fff";
  g.fillRect(0, 0, wDots, hDots);
  for (const el of design.elements) {
    if (el.enabled && isKnownType(el.type)) drawElement(g, el, opts);
  }
  if (opts.showDisabled) {
    g.globalAlpha = 0.18;
    for (const el of design.elements) {
      if (!el.enabled && isKnownType(el.type)) drawElement(g, el, opts);
    }
    g.globalAlpha = 1;
  }
}

/** Döndürme: ^FO noktası, döndürülmüş alanın sol üst köşesidir (R = saat yönünde 90°). */
function applyRotation(g: CanvasRenderingContext2D, el: LabelElement, x: number, y: number, w: number, h: number) {
  g.translate(x, y);
  switch (el.rotation) {
    case 90:
      g.translate(h, 0);
      g.rotate(Math.PI / 2);
      break;
    case 180:
      g.translate(w, h);
      g.rotate(Math.PI);
      break;
    case 270:
      g.translate(0, w);
      g.rotate(-Math.PI / 2);
      break;
    default:
      break;
  }
}

/** Bir satır yazıyı font 0 ölçüsünde (genişlik = BC ölçümü) çizer. */
export function drawTextRun(g: CanvasRenderingContext2D, text: string, x: number, y: number, fontH: number, width: number) {
  if (text === "" || width <= 0) return;
  g.font = `700 ${fontH}px ${ZEBRA_FONT_STACK}`;
  g.textBaseline = "alphabetic";
  g.textAlign = "left";
  const natural = g.measureText(text).width;
  if (natural <= 0) return;
  g.save();
  g.translate(x, y + fontH * BASELINE_RATIO);
  g.scale(width / natural, 1);
  g.fillText(text, 0, 0);
  g.restore();
}

function drawElement(g: CanvasRenderingContext2D, el: LabelElement, opts: RenderOptions) {
  const { ctx } = opts;
  const x = mmToDots(el.xMm, ctx.dpi);
  const y = mmToDots(el.yMm, ctx.dpi);
  g.save();
  g.fillStyle = "#000";
  g.globalCompositeOperation = "source-over";

  if (el.type === "image") {
    // BC resmi döndürmez: bitmap zaten döndürülmüş, ^FO noktasına olduğu gibi.
    const bmp = opts.imageBitmap(el);
    if (bmp) {
      drawMono(g, bmp, x, y);
    } else {
      const w = mmToDots(el.wMm, ctx.dpi) || 1;
      const h = mmToDots(el.hMm, ctx.dpi) || 1;
      const turned = el.rotation === 90 || el.rotation === 270;
      if (el.imageId) drawLogoPlaceholder(g, x, y, turned ? h : w, turned ? w : h, el.imageId === "COMPANY" ? "LOGO" : "RESİM");
      else drawPlaceholder(g, x, y, turned ? h : w, turned ? w : h);
    }
    g.restore();
    return;
  }

  const lay = layoutElement(el, ctx);
  applyRotation(g, el, x, y, lay.w, lay.h);

  switch (el.type) {
    case "text":
    case "field": {
      const t = lay.text;
      if (!t) break;
      if (el.inverted) {
        // ^FR: siyah üstünde beyaz, beyaz üstünde siyah.
        g.globalCompositeOperation = "difference";
        g.fillStyle = "#fff";
      }
      for (const run of t.runs) drawTextRun(g, run.text, run.x, run.y, t.fontH, run.width);
      break;
    }
    case "barcode": {
      const b = lay.barcode;
      if (!b) break;
      let i = 0;
      while (i < b.modules.length) {
        if (b.modules[i] === "1") {
          let j = i;
          while (j < b.modules.length && b.modules[j] === "1") j += 1;
          g.fillRect(b.barX + i * b.moduleWidth, 0, (j - i) * b.moduleWidth, b.barH);
          i = j;
        } else {
          i += 1;
        }
      }
      if (b.humanSource !== "none") {
        const tw = measuredWidth(b.humanText, b.humanFont);
        const tx = b.humanBoxX + Math.trunc((b.humanBoxW - tw) / 2);
        drawTextRun(g, b.humanText, tx, b.humanY, b.humanFont, tw);
      }
      break;
    }
    case "qr": {
      const q = lay.qr;
      if (!q) break;
      if (!q.matrix) {
        drawPlaceholder(g, 0, 0, q.side, q.side, "#d14343");
        break;
      }
      const { size, dark } = q.matrix;
      const m = q.magnification;
      for (let r = 0; r < size; r += 1) {
        for (let c = 0; c < size; c += 1) {
          if (dark[r * size + c]) g.fillRect(c * m, q.offsetY + r * m, m, m);
        }
      }
      break;
    }
    case "line":
      g.fillRect(0, 0, lay.w, lay.h);
      break;
    case "box": {
      const { w, h } = lay;
      const minSide = Math.min(w, h);
      let t = mmToDots(el.thicknessMm, ctx.dpi);
      if (t === 0) t = minSide;
      if (t * 2 >= minSide) {
        g.fillRect(0, 0, w, h);
      } else {
        g.fillRect(0, 0, w, t);
        g.fillRect(0, h - t, w, t);
        g.fillRect(0, t, t, h - 2 * t);
        g.fillRect(w - t, t, t, h - 2 * t);
      }
      break;
    }
    default:
      break;
  }
  g.restore();
}

/** Henüz gelmemiş resim (ör. şirket logosu): açık gri kutu + yazı (basılmaz). */
function drawLogoPlaceholder(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, label: string) {
  g.save();
  g.globalCompositeOperation = "source-over";
  g.fillStyle = "#eef0f3";
  g.fillRect(x, y, w, h);
  g.strokeStyle = "#b8bec9";
  g.lineWidth = Math.max(1, Math.min(w, h) / 50);
  g.setLineDash([6, 4]);
  g.strokeRect(x + 1, y + 1, Math.max(0, w - 2), Math.max(0, h - 2));
  g.setLineDash([]);
  const fontH = Math.max(8, Math.min(h * 0.4, w / (label.length * 0.75)));
  g.fillStyle = "#9aa3b2";
  g.font = `700 ${fontH}px ${ZEBRA_FONT_STACK}`;
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillText(label, x + w / 2, y + h / 2);
  g.restore();
}

function drawPlaceholder(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color = PLACEHOLDER) {
  g.save();
  g.globalCompositeOperation = "source-over";
  g.strokeStyle = color;
  g.lineWidth = Math.max(1, Math.min(w, h) / 40);
  g.setLineDash([4, 3]);
  g.strokeRect(x + 0.5, y + 0.5, Math.max(0, w - 1), Math.max(0, h - 1));
  g.beginPath();
  g.moveTo(x, y);
  g.lineTo(x + w, y + h);
  g.moveTo(x + w, y);
  g.lineTo(x, y + h);
  g.stroke();
  g.restore();
}

const monoCanvasCache = new WeakMap<MonoBitmap, HTMLCanvasElement>();

function monoCanvas(bmp: MonoBitmap): HTMLCanvasElement {
  let c = monoCanvasCache.get(bmp);
  if (c) return c;
  c = document.createElement("canvas");
  c.width = Math.max(1, bmp.width);
  c.height = Math.max(1, bmp.height);
  const cg = c.getContext("2d");
  if (cg) {
    const img = cg.createImageData(c.width, c.height);
    for (let i = 0; i < bmp.width * bmp.height; i += 1) {
      if (bmp.bits[i]) img.data[i * 4 + 3] = 255; // siyah, opak
    }
    cg.putImageData(img, 0, 0);
  }
  monoCanvasCache.set(bmp, c);
  return c;
}

function drawMono(g: CanvasRenderingContext2D, bmp: MonoBitmap, x: number, y: number) {
  g.imageSmoothingEnabled = false;
  g.drawImage(monoCanvas(bmp), x, y, bmp.width, bmp.height);
}
