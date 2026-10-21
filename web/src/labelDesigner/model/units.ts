// mm ↔ ekran pikseli ↔ yazıcı noktası dönüşümleri.

/** CSS piksel / mm (96 dpi ekran): %100 yakınlaştırma = gerçek boyut. */
export const CSS_PX_PER_MM = 96 / 25.4;

/** Ekrandaki mm başına CSS piksel (zoom 1 = gerçek boyut). */
export function pxPerMm(zoom: number): number {
  return CSS_PX_PER_MM * zoom;
}

export function mmToPx(mm: number, zoom: number): number {
  return mm * pxPerMm(zoom);
}

export function pxToMm(px: number, zoom: number): number {
  return px / pxPerMm(zoom);
}

/** BC ile aynı: 203 dpi = 8 nokta/mm, 300 dpi = 12 nokta/mm (Round(Dpi / 25,4)). */
export function dotsPerMm(dpi: number): number {
  const d = dpi > 0 ? dpi : 203;
  return Math.max(1, Math.round(d / 25.4));
}

/** BC "MmToDots" ile aynı: 0 ve negatif = 0. */
export function mmToDots(mm: number, dpi: number): number {
  if (!(mm > 0)) return 0;
  return Math.round(mm * dotsPerMm(dpi));
}

export function dotsToMm(dots: number, dpi: number): number {
  return dots / dotsPerMm(dpi);
}

/** mm değerini 0,01 mm'ye yuvarlar (kayan nokta gürültüsü kalmasın). */
export function roundMm(mm: number): number {
  return Math.round(mm * 100) / 100;
}

/** step > 0 ise en yakın ızgara çizgisine yapıştırır. */
export function snapMm(mm: number, step: number): number {
  if (!(step > 0)) return roundMm(mm);
  return roundMm(Math.round(mm / step) * step);
}

export function clamp(value: number, min: number, max: number): number {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/** Kullanıcı girdisi: "2,5" ve "2.5" kabul edilir; geçersizse null. */
export function parseDecimal(input: string): number | null {
  const s = input.trim().replace(",", ".");
  if (s === "" || s === "-" || s === ".") return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/** Türkçe gösterim: 2.5 → "2,5" (en fazla 2 ondalık). */
export function formatDecimal(n: number): string {
  const r = Math.round(n * 100) / 100;
  return String(r).replace(".", ",");
}
