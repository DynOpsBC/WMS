// Hazır şablonlar: türe göre seçilebilen tasarımlar (paket içinde TS verisi,
// BC değişikliği gerektirmez). Yalnız sözleşmedeki alan anahtarları kullanılır.
import { ELEMENT_DEFAULTS } from "./model/design";
import { layoutContext } from "./model/layout";
import { syncTextHeight } from "./model/ops";
import type { Dpi, LabelDesign, LabelElement, LabelField, LabelKind } from "./model/types";

export type TemplateElement = Partial<LabelElement> & Pick<LabelElement, "type">;

export interface LabelTemplate {
  id: string;
  kind: LabelKind;
  name: string;
  description: string;
  widthMm: number;
  heightMm: number;
  dpi: Dpi;
  elements: TemplateElement[];
}

/** Sözleşme / BC "Label Layout Fields": türe göre geçerli alan anahtarları. */
export const KIND_FIELD_KEYS: Record<LabelKind, readonly string[]> = {
  Item: ["ItemNo", "Description", "Description2", "UoM", "Gtin", "Barcode", "Category", "VariantCode", "Company", "Today"],
  Bin: ["BinCode", "LocationCode", "ZoneCode", "BinTypeCode", "Description", "Company", "Today"],
  Zone: ["ZoneCode", "LocationCode", "Description", "Company", "Today"],
  LP: [
    "LPNo", "SSCC", "BarcodeData", "ItemNo", "Description", "LotNo", "ExpirationDate", "Quantity", "TotalQuantity", "UoM",
    "LocationCode", "BinCode", "ItemCount", "LineCount", "ExtraLines", "Company", "Today",
  ],
};

const FIELD_LABELS: Record<string, string> = {
  ItemNo: "Ürün No", Description: "Açıklama", Description2: "Açıklama 2", UoM: "Birim", Gtin: "GTIN", Barcode: "Barkod",
  Category: "Kategori", VariantCode: "Varyant", BinCode: "Raf Kodu", LocationCode: "Lokasyon", ZoneCode: "Bölge Kodu",
  BinTypeCode: "Raf Tipi", LPNo: "LP No", SSCC: "SSCC", LotNo: "Lot No", ExpirationDate: "Son Kullanma Tarihi",
  Quantity: "Miktar", ItemCount: "Ürün Çeşidi Sayısı", Company: "Şirket", Today: "Bugünün Tarihi",
  BarcodeData: "Barkod Verisi (SSCC, yoksa LP No)", TotalQuantity: "Toplam Miktar", LineCount: "Satır Sayısı",
  ExtraLines: "Diğer Satırlar (+N DİĞER SATIR)",
};

function today(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()}`;
}

/** BC SampleValues ile aynı örnekler (BC alan listesinde örnek yoksa kullanılır). */
function fallbackSample(kind: LabelKind, key: string): string {
  const common: Record<string, string> = {
    ItemNo: "SK-10025", Description: "ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE", Description2: "İKİNCİ AÇIKLAMA", UoM: "ADET",
    Gtin: "8690000012345", Barcode: "8690000012345", Category: "KOZMETİK", VariantCode: "MAVİ", BinCode: "K.K03.11.UST",
    LocationCode: "ANA", ZoneCode: "K", BinTypeCode: "PICK", LPNo: "LP000123", SSCC: "386900000000012345",
    LotNo: "LOT-2026-001", ExpirationDate: "31.12.2027", Quantity: "48", ItemCount: "3", Company: "ÖRNEK ŞİRKET A.Ş.", Today: today(),
    BarcodeData: "386900000000012345", TotalQuantity: "60", LineCount: "2", ExtraLines: "+1 DİĞER SATIR",
  };
  if (kind === "Bin" && key === "Description") return "KOZMETİK ÜST RAF";
  if (kind === "Zone" && key === "Description") return "KOZMETİK ALANI";
  if (kind === "LP" && key === "UoM") return "KOLİ";
  return common[key] ?? "";
}

/** Türün alanları: BC'nin gönderdiği (etiket + örnek) önce, eksikler yedek örnekle. */
export function fieldsForKind(kind: LabelKind, provided: readonly LabelField[]): LabelField[] {
  const byKey = new Map(provided.map((f) => [f.key, f]));
  return KIND_FIELD_KEYS[kind].map((key) => {
    const f = byKey.get(key);
    return f && f.sample ? f : { key, label: f?.label ?? FIELD_LABELS[key] ?? key, sample: fallbackSample(kind, key) };
  });
}

// ------------------------------------------------------------ yardımcılar
const box = (x: number, y: number, w: number, h: number, thicknessMm = 0): TemplateElement => ({ type: "box", xMm: x, yMm: y, wMm: w, hMm: h, thicknessMm });
const line = (x: number, y: number, w: number, h: number): TemplateElement => ({ type: "line", xMm: x, yMm: y, wMm: w, hMm: h, thicknessMm: Math.min(w, h) });
const text = (t: string, x: number, y: number, w: number, fontMm: number, more: Partial<LabelElement> = {}): TemplateElement => ({ type: "text", text: t, xMm: x, yMm: y, wMm: w, fontMm, ...more });
const field = (key: string, x: number, y: number, w: number, fontMm: number, more: Partial<LabelElement> = {}): TemplateElement => ({ type: "field", field: key, xMm: x, yMm: y, wMm: w, fontMm, ...more });
const qr = (key: string, x: number, y: number, size: number): TemplateElement => ({ type: "qr", field: key, xMm: x, yMm: y, wMm: size, hMm: size });
const barcode = (key: string, x: number, y: number, w: number, h: number, more: Partial<LabelElement> = {}): TemplateElement => ({ type: "barcode", field: key, xMm: x, yMm: y, wMm: w, hMm: h, symbology: "code128", showText: true, ...more });
const fit = (minFontMm = 0): Partial<LabelElement> => ({ fit: true, minFontMm });

/** Basamaklı kutulardan ok (ZPL'de çapraz çizgi yok): yukarı ya da aşağı. */
function arrow(cx: number, top: number, dir: "up" | "down"): TemplateElement[] {
  const steps = [4, 8, 12, 16, 20, 24];
  const stepH = 2.5;
  const shaftW = 9;
  const shaftH = 22;
  const out: TemplateElement[] = [];
  if (dir === "up") {
    steps.forEach((w, i) => out.push(box(cx - w / 2, top + i * stepH, w, stepH)));
    out.push(box(cx - shaftW / 2, top + steps.length * stepH, shaftW, shaftH));
  } else {
    out.push(box(cx - shaftW / 2, top, shaftW, shaftH));
    [...steps].reverse().forEach((w, i) => out.push(box(cx - w / 2, top + shaftH + i * stepH, w, stepH)));
  }
  return out;
}

function arrowBinTemplate(dir: "up" | "down"): LabelTemplate {
  return {
    id: `bin-arrow-${dir}`,
    kind: "Bin",
    name: dir === "up" ? "Ok işaretli raf etiketi ↑ (100×50)" : "Ok işaretli raf etiketi ↓ (100×50)",
    description: dir === "up" ? "Üstteki rafı gösteren ok, büyük raf kodu ve barkod." : "Alttaki rafı gösteren ok, büyük raf kodu ve barkod.",
    widthMm: 100,
    heightMm: 50,
    dpi: 203,
    elements: [
      ...arrow(16, 4, dir),
      line(31, 3, 0.5, 44),
      field("BinCode", 34, 3.5, 63, 13, { ...fit(6), bold: true }),
      barcode("BinCode", 34, 20.5, 63, 13),
      field("ZoneCode", 34, 40, 30, 3.5, { prefix: "BÖLGE: ", bold: true }),
      field("LocationCode", 66, 40, 31, 3.5, { prefix: "DEPO: ", align: "right" }),
      field("Description", 34, 45, 63, 2.75, fit(2)),
    ],
  };
}

export const TEMPLATES: readonly LabelTemplate[] = [
  // ---------------------------------------------------------------- Ürün
  {
    id: "item-qr-no",
    kind: "Item",
    name: "QR + Ürün No (80×40)",
    description: "Ortada büyük QR, altında ürün no ve açıklama.",
    widthMm: 80,
    heightMm: 40,
    dpi: 203,
    elements: [
      qr("ItemNo", 29.5, 0.75, 21),
      field("ItemNo", 2, 24.5, 76, 6, { ...fit(3), bold: true, align: "center" }),
      field("Description", 2, 32.5, 76, 2.75, { maxLines: 2, align: "center" }),
    ],
  },
  {
    id: "item-barcode-desc",
    kind: "Item",
    name: "Barkod + Açıklama (80×40)",
    description: "Açıklama üstte, geniş Code128 barkod, altta GTIN ve tarih.",
    widthMm: 80,
    heightMm: 40,
    dpi: 203,
    elements: [
      field("Description", 2, 2, 76, 3.5, { maxLines: 2, bold: true }),
      field("ItemNo", 2, 11, 50, 4.5, { ...fit(2.5), bold: true }),
      field("UoM", 54, 11.5, 24, 3, { align: "right" }),
      barcode("ItemNo", 2, 17.5, 76, 13),
      field("Gtin", 2, 36, 46, 2.25, { prefix: "GTIN: " }),
      field("Today", 48, 36, 30, 2.25, { align: "right" }),
    ],
  },
  {
    id: "item-big-no-qr",
    kind: "Item",
    name: "Büyük Ürün No + QR (100×50)",
    description: "Siyah başlık şeridi, çok büyük ürün no, QR ve barkod.",
    widthMm: 100,
    heightMm: 50,
    dpi: 203,
    elements: [
      box(0, 0, 100, 7),
      text("ÜRÜN", 3, 1.5, 40, 4, { inverted: true, bold: true }),
      field("Company", 40, 1.75, 57, 3.5, { ...fit(2), align: "right", inverted: true }),
      field("ItemNo", 3, 9, 66, 12, { ...fit(6), bold: true }),
      field("Description", 3, 23, 66, 3.5, { maxLines: 2 }),
      line(3, 32.5, 66, 0.4),
      field("UoM", 3, 34.5, 30, 3, { prefix: "BİRİM: " }),
      field("Category", 34, 34.5, 35, 3, { ...fit(2), align: "right" }),
      barcode("ItemNo", 3, 39.5, 66, 7, { showText: false }),
      qr("ItemNo", 74, 10.5, 21),
      field("Today", 71, 36, 27, 2.5, { align: "center" }),
    ],
  },
  {
    id: "item-small",
    kind: "Item",
    name: "Küçük ürün etiketi (60×40)",
    description: "Raf önü için: ürün no, açıklama, barkod ve küçük QR.",
    widthMm: 60,
    heightMm: 40,
    dpi: 203,
    elements: [
      field("ItemNo", 2, 2, 56, 5, { ...fit(3), bold: true }),
      field("Description", 2, 8.5, 56, 2.75, { maxLines: 2 }),
      barcode("ItemNo", 2, 16, 38, 12),
      qr("ItemNo", 42, 15, 16),
      line(2, 34, 56, 0.3),
      field("UoM", 2, 35.5, 28, 2.5, { prefix: "BİRİM: " }),
      field("Today", 30, 35.5, 28, 2.5, { align: "right" }),
    ],
  },
  {
    id: "item-logo",
    kind: "Item",
    name: "Logo + Ürün + Barkod (100×50)",
    description: "Sol üstte şirket logosu, ürün no, açıklama, barkod ve birim.",
    widthMm: 100,
    heightMm: 50,
    dpi: 203,
    elements: [
      { type: "image", imageId: "COMPANY", xMm: 3, yMm: 3, wMm: 30, hMm: 15 },
      field("ItemNo", 36, 3, 61, 8, { ...fit(4), bold: true }),
      field("Description", 36, 12.5, 61, 3, { maxLines: 2 }),
      line(3, 21, 94, 0.5),
      barcode("ItemNo", 3, 24, 60, 14),
      text("BİRİM", 66, 24, 31, 2.5, { align: "center" }),
      field("UoM", 66, 28, 31, 6, { ...fit(3), bold: true, align: "center" }),
      box(66, 23, 31, 13, 0.4),
      field("Gtin", 3, 44.5, 50, 2.5, { prefix: "GTIN: " }),
      field("Today", 53, 44.5, 44, 2.5, { align: "right" }),
    ],
  },

  // ---------------------------------------------------------------- Raf
  {
    id: "bin-big-qr",
    kind: "Bin",
    name: "Raf kodu büyük + QR (80×40)",
    description: "Uzaktan okunur büyük raf kodu, sağda QR, altta bölge ve depo.",
    widthMm: 80,
    heightMm: 40,
    dpi: 203,
    elements: [
      field("BinCode", 2, 3, 52, 12, { ...fit(5), bold: true }),
      qr("BinCode", 57, 2, 21),
      line(2, 27, 76, 0.4),
      field("ZoneCode", 2, 29, 25, 3.5, { prefix: "BÖLGE: ", bold: true }),
      field("LocationCode", 28, 29, 25, 3.5, { prefix: "DEPO: " }),
      field("BinTypeCode", 57, 29, 21, 3.5, { align: "right" }),
      field("Description", 2, 34.5, 76, 2.75, fit(2)),
    ],
  },
  {
    id: "bin-zone-barcode",
    kind: "Bin",
    name: "Raf + Alan + Barkod (100×50)",
    description: "Başlıkta depo ve bölge, ortada büyük raf kodu, geniş barkod.",
    widthMm: 100,
    heightMm: 50,
    dpi: 203,
    elements: [
      box(0, 0, 100, 8),
      field("LocationCode", 3, 1.75, 45, 4.5, { prefix: "DEPO ", inverted: true, bold: true }),
      field("ZoneCode", 50, 1.75, 47, 4.5, { prefix: "BÖLGE ", inverted: true, bold: true, align: "right" }),
      field("BinCode", 3, 10, 94, 14, { ...fit(6), bold: true, align: "center" }),
      barcode("BinCode", 3, 27, 94, 13),
      field("Description", 3, 45.5, 94, 3, { ...fit(2), align: "center" }),
    ],
  },
  arrowBinTemplate("up"),
  arrowBinTemplate("down"),

  // ---------------------------------------------------------------- Alan
  {
    id: "zone-big-qr",
    kind: "Zone",
    name: "Alan kodu büyük + QR (80×40)",
    description: "Başlık şeridi, büyük alan kodu ve QR.",
    widthMm: 80,
    heightMm: 40,
    dpi: 203,
    elements: [
      box(0, 0, 80, 6),
      text("ALAN", 2, 1.25, 40, 3.5, { inverted: true, bold: true }),
      field("LocationCode", 40, 1.5, 38, 3, { align: "right", inverted: true }),
      field("ZoneCode", 2, 8, 52, 16, { ...fit(6), bold: true }),
      qr("ZoneCode", 57, 7.5, 21),
      field("Description", 2, 33, 76, 3, fit(2)),
    ],
  },

  // ---------------------------------------------------------------- LP / palet
  {
    id: "lp-standard",
    kind: "LP",
    name: "LP Standart 4x2 (101.6×50.8)",
    description: "Mevcut sabit LP etiketinin aynısı: büyük LP no, QR, ürün, lot, SKT, miktar, barkod.",
    widthMm: 101.6,
    heightMm: 50.8,
    dpi: 203,
    elements: [
      box(0, 0, 101.6, 6.5),
      text("PALET / LP ETİKETİ", 3, 1.25, 55, 4, { inverted: true }),
      field("LocationCode", 58.75, 1.5, 20, 3.25, { align: "right", inverted: true }),
      field("BinCode", 79, 1.5, 19.75, 3.25, { prefix: " / ", ...fit(2.25), inverted: true }),
      field("LPNo", 3, 7.75, 70, 10, { fontWidthMm: 9.5, ...fit(7) }),
      qr("LPNo", 75.5, 7.75, 24),
      field("ItemNo", 3, 18.75, 22, 3.25, fit(2.25)),
      field("Description", 26, 18.75, 47, 3.25, fit(2.25)),
      field("LotNo", 3, 23.25, 30, 3.25, { prefix: "LOT: ", ...fit(2.25) }),
      // Sabit LP etiketindeki gibi lotun yanında "+N DİĞER SATIR" (BC varsayılan LP tasarımı ile aynı).
      field("ExtraLines", 34, 23.25, 19, 3.25, fit(2.25)),
      field("ExpirationDate", 54, 23.25, 19, 3.25, { prefix: "SKT: ", ...fit(2.25) }),
      field("TotalQuantity", 3, 27.75, 46, 5.5, { prefix: "MİKTAR: ", ...fit(3.5) }),
      field("UoM", 50, 27.75, 23, 5.5, fit(3.5)),
      // Sabit LP etiketi gibi: SSCC varsa SSCC, yoksa LP No.
      barcode("BarcodeData", 3, 34.25, 70, 10.5, { showText: false }),
      text("QR = LP NO", 75.5, 40, 24, 2.75, { align: "center" }),
      field("Today", 3, 46.25, 40, 2.5),
      field("ItemCount", 44, 46.25, 29, 2.5, { prefix: "ÜRÜN ÇEŞİDİ: ", align: "right" }),
    ],
  },
  {
    id: "lp-a6",
    kind: "LP",
    name: "Palet A6 (100×150) SSCC + içerik",
    description: "Dikey palet etiketi: SSCC, ürün, lot, SKT, miktar, GS1-128 barkod ve QR.",
    widthMm: 100,
    heightMm: 150,
    dpi: 203,
    elements: [
      box(0, 0, 100, 10),
      text("PALET ETİKETİ", 4, 2, 50, 6, { inverted: true, bold: true }),
      field("Company", 52, 3, 44, 4, { ...fit(2.5), align: "right", inverted: true }),
      text("SSCC", 4, 13, 30, 3.5),
      field("SSCC", 4, 17, 92, 7, { prefix: "(00) ", ...fit(4), bold: true }),
      line(4, 26.5, 92, 0.5),
      text("ÜRÜN", 4, 29, 30, 3),
      field("ItemNo", 4, 33, 92, 7, { ...fit(4), bold: true }),
      field("Description", 4, 41.5, 92, 4, { maxLines: 2 }),
      line(4, 52, 92, 0.5),
      text("LOT", 4, 54.5, 40, 3),
      field("LotNo", 4, 58.5, 44, 5.5, { ...fit(3), bold: true }),
      text("SKT", 52, 54.5, 40, 3),
      field("ExpirationDate", 52, 58.5, 44, 5.5, { ...fit(3), bold: true }),
      text("MİKTAR", 4, 66.5, 40, 3),
      field("Quantity", 4, 70.5, 28, 8, { ...fit(4), bold: true }),
      field("UoM", 33, 73.5, 15, 4.5, fit(2.5)),
      text("LP NO", 52, 66.5, 40, 3),
      field("LPNo", 52, 70.5, 44, 5.5, { ...fit(3), bold: true }),
      line(4, 80.5, 92, 0.5),
      barcode("SSCC", 4, 84, 92, 30, { symbology: "gs1-128", prefix: "(00)" }),
      qr("LPNo", 4, 121, 25),
      field("LocationCode", 34, 123, 62, 4, { prefix: "DEPO: " }),
      field("BinCode", 34, 129, 62, 4, { prefix: "RAF: ", ...fit(2.5) }),
      field("Today", 34, 135, 62, 4, { prefix: "TARİH: " }),
      field("ItemCount", 34, 141, 62, 3.5, { prefix: "ÜRÜN ÇEŞİDİ: " }),
    ],
  },
  {
    id: "lp-mixed",
    kind: "LP",
    name: "Karma palet özet (100×100)",
    description: "Karışık palet: büyük ürün çeşidi sayısı, konum, LP no, QR ve SSCC barkodu.",
    widthMm: 100,
    heightMm: 100,
    dpi: 203,
    elements: [
      box(0, 0, 100, 10),
      text("KARMA PALET", 4, 2, 56, 6, { inverted: true, bold: true }),
      field("Today", 60, 3, 36, 3.5, { align: "right", inverted: true }),
      field("LPNo", 4, 13, 64, 10, { ...fit(5), bold: true }),
      qr("LPNo", 74, 11, 22),
      box(4, 34, 44, 28, 0.6),
      text("ÜRÜN ÇEŞİDİ", 6, 36.5, 40, 3.5, { align: "center" }),
      field("ItemCount", 6, 42, 40, 16, { ...fit(8), bold: true, align: "center" }),
      box(52, 34, 44, 28, 0.6),
      text("KONUM", 54, 36.5, 40, 3.5, { align: "center" }),
      field("LocationCode", 54, 42.5, 40, 7, { ...fit(3), bold: true, align: "center" }),
      field("BinCode", 54, 52.5, 40, 4.5, { ...fit(2.5), align: "center" }),
      line(4, 65, 92, 0.5),
      text("SSCC", 4, 67, 30, 3),
      barcode("SSCC", 4, 71, 92, 17, { symbology: "gs1-128", prefix: "(00)" }),
      field("Company", 4, 95, 92, 3, { ...fit(2), align: "center" }),
    ],
  },
];

export function templatesFor(kind: LabelKind): LabelTemplate[] {
  return TEMPLATES.filter((t) => t.kind === kind);
}

/** Şablonun öğeleri (yeni kimlikler e1.., lineNo 0; metin yükseklikleri hesaplanmış). */
export function templateElements(template: LabelTemplate, values: ReadonlyMap<string, string>): LabelElement[] {
  const ctx = layoutContext({ dpi: template.dpi, widthMm: template.widthMm, heightMm: template.heightMm } as LabelDesign, values);
  return template.elements.map((props, i) => syncTextHeight({ ...ELEMENT_DEFAULTS, ...props, id: `e${i + 1}`, lineNo: 0 }, ctx));
}

/** Tasarımı şablonla değiştirir: öğeler + ölçü + dpi (kod, açıklama, alanlar, resimler kalır). */
export function applyTemplate(design: LabelDesign, template: LabelTemplate): LabelDesign {
  const values = new Map(design.fields.map((f) => [f.key, f.sample]));
  return {
    ...design,
    widthMm: template.widthMm,
    heightMm: template.heightMm,
    dpi: template.dpi,
    elements: templateElements(template, values),
  };
}

/** Küçük resim için: şablonu mevcut tasarımın alanları/resimleriyle (eksik örnekler dolu) gösterir. */
export function templatePreviewDesign(design: LabelDesign, template: LabelTemplate): LabelDesign {
  const fields = fieldsForKind(template.kind, design.fields);
  const values = new Map(fields.map((f) => [f.key, f.sample]));
  return {
    ...design,
    kind: template.kind,
    widthMm: template.widthMm,
    heightMm: template.heightMm,
    dpi: template.dpi,
    fields,
    elements: templateElements(template, values),
  };
}

export function templateUsesLogo(template: LabelTemplate): boolean {
  return template.elements.some((e) => e.type === "image" && e.imageId === "COMPANY");
}
