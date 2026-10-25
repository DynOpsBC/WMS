// Resim → 1 bit (eşik %50) → ZPL ^GFA onaltılık verisi.
import type { Rotation } from "../model/types";

export interface MonoBitmap {
  width: number;
  height: number;
  /** satır satır, 1 = siyah nokta */
  bits: Uint8Array;
}

/**
 * RGBA → 1 bit. Saydam pikseller beyaz zemine karıştırılır; parlaklık
 * eşiğin altındaysa siyah (varsayılan eşik 128 = %50).
 */
export function rgbaToMono(rgba: Uint8ClampedArray | Uint8Array, width: number, height: number, threshold = 128): MonoBitmap {
  const bits = new Uint8Array(width * height);
  for (let i = 0; i < width * height; i += 1) {
    const r = rgba[i * 4];
    const g = rgba[i * 4 + 1];
    const b = rgba[i * 4 + 2];
    const a = rgba[i * 4 + 3];
    // Tamsayı ağırlıklar: 128 gri tam eşikte kalsın (kayan nokta sapması olmasın).
    const lum = ((299 * r + 587 * g + 114 * b) * a + 255000 * (255 - a)) / 255000;
    bits[i] = lum < threshold ? 1 : 0;
  }
  return { width, height, bits };
}

/** Saat yönünde döndürme (ZPL R = 90, I = 180, B = 270). */
export function rotateMono(src: MonoBitmap, rotation: Rotation): MonoBitmap {
  if (rotation === 0) return src;
  const { width: w, height: h, bits } = src;
  const outW = rotation === 180 ? w : h;
  const outH = rotation === 180 ? h : w;
  const out = new Uint8Array(outW * outH);
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      const v = bits[y * w + x];
      if (!v) continue;
      let nx: number;
      let ny: number;
      if (rotation === 90) { nx = h - 1 - y; ny = x; }
      else if (rotation === 180) { nx = w - 1 - x; ny = h - 1 - y; }
      else { nx = y; ny = w - 1 - x; }
      out[ny * outW + nx] = 1;
    }
  }
  return { width: outW, height: outH, bits: out };
}

const HEX = "0123456789ABCDEF";

/** `^GFA,<toplam>,<toplam>,<satır byte>,<HEX>` (sıkıştırmasız). */
export function monoToGfa(bmp: MonoBitmap): string {
  const bytesPerRow = Math.ceil(bmp.width / 8);
  const total = bytesPerRow * bmp.height;
  const parts: string[] = [];
  for (let y = 0; y < bmp.height; y += 1) {
    let row = "";
    for (let bx = 0; bx < bytesPerRow; bx += 1) {
      let byte = 0;
      for (let bit = 0; bit < 8; bit += 1) {
        const x = bx * 8 + bit;
        if (x < bmp.width && bmp.bits[y * bmp.width + x]) byte |= 0x80 >> bit;
      }
      row += HEX[byte >> 4] + HEX[byte & 15];
    }
    parts.push(row);
  }
  return `^GFA,${total},${total},${bytesPerRow},${parts.join("")}`;
}

/** ^GFA verisini çözer (genişlik satır byte × 8 olarak döner). */
export function parseGfa(gf: string): MonoBitmap | null {
  const m = /^\^GFA,(\d+),(\d+),(\d+),([0-9A-Fa-f]*)$/.exec(gf.trim());
  if (!m) return null;
  const total = Number(m[1]);
  const bytesPerRow = Number(m[3]);
  const hex = m[4];
  if (bytesPerRow <= 0 || hex.length !== total * 2) return null;
  const height = total / bytesPerRow;
  const width = bytesPerRow * 8;
  const bits = new Uint8Array(width * height);
  for (let i = 0; i < total; i += 1) {
    const byte = parseInt(hex.substr(i * 2, 2), 16);
    for (let bit = 0; bit < 8; bit += 1) bits[i * 8 + bit] = byte & (0x80 >> bit) ? 1 : 0;
  }
  return { width, height, bits };
}
