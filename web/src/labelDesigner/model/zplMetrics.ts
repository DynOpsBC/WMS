// BC "DOPSWHS Label Canvas" ölçümlerinin birebir karşılığı: önizleme, BC'nin
// ürettiği ZPL ile aynı yazı boyutlarını, satır kırmayı ve barkod/QR
// büyüklüğünü kullanır (tamsayı bölme = AL "div").

const div = (a: number, b: number) => Math.trunc(a / b);

export function clampInt(value: number, min: number, max: number): number {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/** Zebra font 0'ın harf genişliği (font genişliğinin yüzdesi, Labelary ölçümü). */
export function glyphUnit(ch: string): number {
  if ("Iİijlıft".includes(ch)) return 28;
  if (" .,/:;()!|'".includes(ch)) return 30;
  if ("Jacksvxyzrçş?".includes(ch)) return 46;
  if ('0123456789eoö*#"'.includes(ch)) return 48;
  if ("EFLTZbdghnpquğü_".includes(ch)) return 50;
  if ("ABCKPSVXYÇŞ".includes(ch)) return 56;
  if ("DGOQRĞÖ".includes(ch)) return 59;
  if ("HNUÜ&".includes(ch)) return 61;
  if ("Mmw".includes(ch)) return 76;
  if (ch === "W") return 82;
  if ("-+%=@~".includes(ch)) return 91;
  return 60;
}

export function glyphUnits(value: string): number {
  let units = 0;
  for (const ch of value) units += glyphUnit(ch);
  return units;
}

/** Değerin font genişliğinde (nokta) basılı genişliği. */
export function measuredWidth(value: string, fontWidth: number): number {
  return div(glyphUnits(value) * fontWidth, 100);
}

/** Minimum..Preferred arasında MaxWidth'e sığan en büyük font. */
export function fitFontMeasured(value: string, maxWidth: number, preferred: number, minimum: number): number {
  const units = glyphUnits(value);
  if (units <= 0) return preferred;
  return clampInt(div(maxWidth * 100, units), minimum, preferred);
}

/** Kutuya sığan karakter sayısı (font 0 ortalama 0,55 × boy). */
export function maxChars(boxWidth: number, font: number): number {
  if (font <= 0) return 0;
  return div(boxWidth * 100, font * 55);
}

/** BC WrapText: kelime sınırında böler, MaxLines'tan fazlası atılır. */
export function wrapText(value: string, maxCharsPerLine: number, maxLines: number): string[] {
  const lines: string[] = [];
  if (maxCharsPerLine <= 0) return lines;
  let v = value.replace(/^ +/, "").replace(/ +$/, "");
  while (v.includes("  ")) v = v.split("  ").join(" ");
  while (v !== "" && lines.length < maxLines) {
    if (v.length <= maxCharsPerLine) {
      lines.push(v);
      v = "";
    } else {
      // 1 tabanlı AL indekslerini 0 tabanlıya çeviriyoruz.
      let cut = maxCharsPerLine + 1;
      while (cut > 1 && v[cut - 1] !== " ") cut -= 1;
      if (cut <= div(maxCharsPerLine, 2)) cut = maxCharsPerLine + 1;
      lines.push(v.slice(0, cut - 1).replace(/ +$/, ""));
      v = v.slice(cut - 1).replace(/^ +/, "");
    }
  }
  return lines;
}

/** Bayt kipinde QR modül sayısı (sürüm 1..6, hata düzeltme L) — BC tahmini. */
export function qrModules(data: string): number {
  const n = data.length;
  if (n <= 17) return 21;
  if (n <= 32) return 25;
  if (n <= 53) return 29;
  if (n <= 78) return 33;
  if (n <= 106) return 37;
  return 41;
}

/** ^BQ büyütmesi (2..8): sembol MaxSide noktayı geçmesin. */
export function qrMagnification(data: string, maxSide: number): number {
  return clampInt(div(maxSide, qrModules(data)), 2, 8);
}

/** Zebra/Labelary QR sembolünü ^FO noktasının ~10 nokta altına çizer. */
export const QR_TOP_OFFSET_DOTS = 10;

export function isDigits(value: string): boolean {
  return value !== "" && /^[0-9]+$/.test(value);
}

/** BC Code128 modül tahmini (yalnız rakamsa C alt kümesi). */
export function code128ModulesEstimate(data: string): number {
  let modules = isDigits(data) ? 11 * (div(data.length + 1, 2) + 1) + 35 : 11 * data.length + 35;
  if (modules <= 0) modules = 35;
  return modules;
}

/**
 * BC Code128 modül genişliği: çubuklar kolonun %85'ine kadar büyür, en çok 6
 * nokta; asla MaxWidth'i aşmaz (uzun kodda 1 noktaya düşer).
 */
export function fitModuleWidth(modules: number, maxWidth: number): number {
  let mw = div(div(maxWidth * 85, 100), modules);
  if (mw < 1) mw = 1;
  if (mw > 6) mw = 6;
  while (mw > 1 && modules * mw > maxWidth) mw -= 1;
  return mw;
}

/** BC Label Canvas "SmallSize" (nokta): barkod altı yazının boyu. */
export function smallFontDots(labelHeightMm: number): number {
  let h = labelHeightMm;
  if (h < 20 || h > 400) h = 40;
  const heightDots = Math.round(h * 8);
  return clampInt(div(heightDots, 14), 20, 28) - 4;
}

/** Çok satırlı metinde satır aralığı: FontHeight + 6 nokta. */
export const LINE_GAP_DOTS = 6;
/** Barkod altı yazı, çubukların 4 nokta altında. */
export const HUMAN_TEXT_GAP_DOTS = 4;
