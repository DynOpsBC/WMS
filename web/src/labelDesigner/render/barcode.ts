// Code128 / GS1-128 / EAN-13 kodlayıcıları. Çıktı: modül dizisi
// ("1" = çubuk, "0" = boşluk). Sessiz bölge eklenmez (ZPL ^FO çubukla başlar).

const CODE128_PATTERNS: readonly string[] = [
  "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
  "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
  "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
  "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
  "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
  "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
  "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
  "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
  "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
  "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
  "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
];

const START_A = 103;
const START_B = 104;
const START_C = 105;
const STOP = 106;
const FNC1_VALUE = 102;
const SHIFT = 98;
const TO_C = 99;

/** Kodlayıcıya FNC1 (GS1 ayırıcı) geçmek için kullanılan özel karakter. */
export const FNC1 = "";

type Subset = "A" | "B" | "C";

export interface EncodedBarcode {
  modules: string;
  /** İnsan okunur metin (barkod altı). */
  text: string;
  /** Sembol değerleri (başlangıç, veri, kontrol, bitiş) — test için. */
  symbols: number[];
}

function isDigitAt(s: string, i: number): boolean {
  const c = s.charCodeAt(i);
  return c >= 48 && c <= 57;
}

/** i konumundan başlayan ardışık rakam sayısı (FNC1 C kümesinde de kodlanır, sayılmaz). */
function digitRun(s: string, i: number): number {
  let n = 0;
  while (i + n < s.length && isDigitAt(s, i + n)) n += 1;
  return n;
}

function valueInA(code: number): number {
  return code < 32 ? code + 64 : code - 32;
}

function valueInB(code: number): number {
  return code - 32;
}

/** Code128'de kodlanamayan karakterleri (ASCII dışı) "?" ile değiştirir. */
export function sanitizeCode128(data: string): string {
  let out = "";
  for (const ch of data) {
    const c = ch.charCodeAt(0);
    out += ch === FNC1 || (c >= 0 && c <= 127) ? ch : "?";
  }
  return out;
}

export function hasNonAsciiForCode128(data: string): boolean {
  for (const ch of data) {
    if (ch !== FNC1 && ch.charCodeAt(0) > 127) return true;
  }
  return false;
}

/**
 * Otomatik alt küme seçimli Code128 (ZPL ^BC "A" kipine yakın): 4+ rakamla
 * başlıyorsa C, ortada 6+ (sonda 4+) rakam dizisinde C'ye geçer.
 */
export function code128Symbols(input: string): number[] {
  const data = sanitizeCode128(input);
  const values: number[] = [];
  let subset: Subset;
  const firstRun = digitRun(data, 0);
  const startsWithFnc1 = data.startsWith(FNC1);
  const runAfterFnc1 = startsWithFnc1 ? digitRun(data, 1) : 0;
  if ((firstRun >= 4 || (firstRun >= 2 && firstRun === data.length && firstRun % 2 === 0)) ||
      (startsWithFnc1 && runAfterFnc1 >= 2)) {
    subset = "C";
    values.push(START_C);
  } else {
    // Kontrol karakteri küçük harften önce geliyorsa A, yoksa B.
    let useA = false;
    for (const ch of data) {
      const c = ch.charCodeAt(0);
      if (ch === FNC1) continue;
      if (c < 32) { useA = true; break; }
      if (c >= 96) break;
    }
    subset = useA ? "A" : "B";
    values.push(useA ? START_A : START_B);
  }

  let i = 0;
  while (i < data.length) {
    const ch = data[i];
    if (ch === FNC1) {
      values.push(FNC1_VALUE);
      i += 1;
      continue;
    }
    if (subset === "C") {
      if (digitRun(data, i) >= 2) {
        values.push(Number(data.substr(i, 2)));
        i += 2;
        continue;
      }
      // C'den çık: sıradaki karakter için A/B.
      const c = data.charCodeAt(i);
      if (c < 32) { values.push(101); subset = "A"; } else { values.push(100); subset = "B"; }
      continue;
    }
    // A veya B
    const run = digitRun(data, i);
    const atEnd = i + run === data.length;
    if (run >= 6 || (atEnd && run >= 4)) {
      if (run % 2 === 1) {
        // Tek sayılı dizi: ilk rakamı mevcut kümede yaz, sonra C'ye geç.
        const c = data.charCodeAt(i);
        values.push(subset === "A" ? valueInA(c) : valueInB(c));
        i += 1;
      }
      values.push(TO_C);
      subset = "C";
      continue;
    }
    const c = data.charCodeAt(i);
    if (subset === "B") {
      if (c < 32) {
        // Tek kontrol karakteri: SHIFT ile A.
        const nextIsCtrl = i + 1 < data.length && data.charCodeAt(i + 1) < 32;
        if (nextIsCtrl) { values.push(101); subset = "A"; continue; }
        values.push(SHIFT, valueInA(c));
      } else {
        values.push(valueInB(c));
      }
    } else {
      if (c >= 96) {
        const nextIsLower = i + 1 < data.length && data.charCodeAt(i + 1) >= 96;
        if (nextIsLower) { values.push(100); subset = "B"; continue; }
        values.push(SHIFT, valueInB(c));
      } else {
        values.push(valueInA(c));
      }
    }
    i += 1;
  }

  let checksum = values[0];
  for (let k = 1; k < values.length; k += 1) checksum += k * values[k];
  values.push(checksum % 103, STOP);
  return values;
}

export function symbolsToModules(symbols: number[]): string {
  let out = "";
  for (const v of symbols) {
    const pattern = CODE128_PATTERNS[v];
    for (let k = 0; k < pattern.length; k += 1) {
      out += (k % 2 === 0 ? "1" : "0").repeat(Number(pattern[k]));
    }
  }
  return out;
}

export function encodeCode128(data: string): EncodedBarcode {
  const symbols = code128Symbols(data);
  return { modules: symbolsToModules(symbols), text: data.split(FNC1).join(""), symbols };
}

// ---------------------------------------------------------------- GS1-128

/** Sabit uzunluklu GS1 AI'ları (veri uzunluğu); listede olmayanlar değişken uzunluklu. */
const GS1_FIXED: Record<string, number> = {
  "00": 18, "01": 14, "02": 14, "03": 14, "04": 16,
  "11": 6, "12": 6, "13": 6, "14": 6, "15": 6, "16": 6, "17": 6, "18": 6, "19": 6,
  "20": 2,
  "31": 7, "32": 7, "33": 7, "34": 7, "35": 7, "36": 7,
  "41": 13,
};

export interface Gs1Part {
  ai: string;
  data: string;
}

/** "(01)0869...(10)LOT" → parçalar; parantez yoksa null. */
export function parseGs1(value: string): Gs1Part[] | null {
  const re = /\((\d{2,4})\)([^(]*)/g;
  if (!value.trim().startsWith("(")) return null;
  const parts: Gs1Part[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(value)) !== null) parts.push({ ai: m[1], data: m[2] });
  return parts.length > 0 ? parts : null;
}

export function encodeGs1128(value: string): EncodedBarcode {
  const parts = parseGs1(value);
  if (!parts) {
    // Parantezsiz: tüm değer FNC1 sonrası eleman dizisi kabul edilir.
    const enc = encodeCode128(FNC1 + value);
    return { ...enc, text: value };
  }
  let data = FNC1;
  parts.forEach((p, index) => {
    data += p.ai + p.data;
    const fixed = GS1_FIXED[p.ai.slice(0, 2)];
    if (fixed === undefined && index < parts.length - 1) data += FNC1;
  });
  const enc = encodeCode128(data);
  return { ...enc, text: parts.map((p) => `(${p.ai})${p.data}`).join("") };
}

// ---------------------------------------------------------------- EAN-13

const EAN_L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"];
const EAN_G = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"];
const EAN_R = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"];
const EAN_PARITY = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"];

/** 12 haneli verinin EAN-13 kontrol hanesi. */
export function ean13CheckDigit(first12: string): number {
  if (!/^\d{12}$/.test(first12)) throw new Error("EAN-13 için 12 rakam gerekli");
  let sum = 0;
  for (let i = 0; i < 12; i += 1) sum += Number(first12[i]) * (i % 2 === 0 ? 1 : 3);
  return (10 - (sum % 10)) % 10;
}

export function isValidEan13(code: string): boolean {
  if (!/^\d{13}$/.test(code)) return false;
  return ean13CheckDigit(code.slice(0, 12)) === Number(code[12]);
}

export type Ean13Status = "ok" | "computed" | "badCheck" | "invalid";

/** EAN-13 durumu: 12 hane (kontrol eklenecek), 13 hane doğru/yanlış, diğer = geçersiz. */
export function ean13Status(value: string): Ean13Status {
  if (/^\d{12}$/.test(value)) return "computed";
  if (/^\d{13}$/.test(value)) return isValidEan13(value) ? "ok" : "badCheck";
  return "invalid";
}

/**
 * EAN-13 kodlar; ZPL ^BE gibi kontrol hanesini ilk 12 haneden kendisi
 * hesaplar. Geçersiz veride null.
 */
export function encodeEan13(value: string): EncodedBarcode | null {
  const status = ean13Status(value);
  if (status === "invalid") return null;
  const first12 = value.slice(0, 12);
  const full = first12 + String(ean13CheckDigit(first12));
  const parity = EAN_PARITY[Number(full[0])];
  let modules = "101";
  for (let i = 1; i <= 6; i += 1) {
    const d = Number(full[i]);
    modules += parity[i - 1] === "L" ? EAN_L[d] : EAN_G[d];
  }
  modules += "01010";
  for (let i = 7; i <= 12; i += 1) modules += EAN_R[Number(full[i])];
  modules += "101";
  return { modules, text: full, symbols: [] };
}
