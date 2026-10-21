// BC dışında (geliştirme / statik HTML) gösterilen örnek tasarım: BC'deki
// varsayılan ITEM tasarımının (80×40 mm, 203 dpi) aynısı.
import { ELEMENT_DEFAULTS } from "./model/design";
import type { LabelDesign, LabelElement } from "./model/types";

function el(id: string, lineNo: number, props: Partial<LabelElement> & Pick<LabelElement, "type">): LabelElement {
  return { ...ELEMENT_DEFAULTS, id, lineNo, ...props };
}

export const SAMPLE_DESIGN: LabelDesign = {
  version: 1,
  code: "ITEM",
  description: "Ürün etiketi (örnek)",
  kind: "Item",
  widthMm: 80,
  heightMm: 40,
  dpi: 203,
  active: true,
  elements: [
    el("e1", 10000, { type: "box", xMm: 0, yMm: 0, wMm: 80, hMm: 5.5, thicknessMm: 0 }),
    el("e2", 20000, { type: "text", xMm: 2, yMm: 1, wMm: 76, hMm: 3.5, text: "ÜRÜN ETİKETİ", fontMm: 3.5, inverted: true }),
    el("e3", 30000, { type: "field", xMm: 2, yMm: 1.5, wMm: 76, hMm: 2.75, field: "Company", fontMm: 2.75, align: "right", inverted: true }),
    el("e4", 40000, { type: "qr", xMm: 57, yMm: 6.5, wMm: 21, hMm: 21, field: "ItemNo" }),
    el("e5", 50000, { type: "field", xMm: 2, yMm: 6.5, wMm: 53, hMm: 4, field: "ItemNo", fontMm: 4, fit: true, minFontMm: 2.25 }),
    el("e6", 60000, { type: "field", xMm: 2, yMm: 11.5, wMm: 53, hMm: 6.25, field: "Description", fontMm: 2.75, maxLines: 2 }),
    el("e7", 70000, { type: "field", xMm: 2, yMm: 18.5, wMm: 18, hMm: 2.25, field: "UoM", prefix: "BİRİM: ", fontMm: 2.25, fit: true }),
    el("e8", 80000, { type: "field", xMm: 20, yMm: 18.5, wMm: 35, hMm: 2.25, field: "Gtin", prefix: "GTIN: ", fontMm: 2.25, fit: true, minFontMm: 1.5 }),
    el("e9", 90000, { type: "barcode", xMm: 2, yMm: 21.75, wMm: 53, hMm: 11.1, field: "ItemNo", symbology: "code128", showText: true }),
  ],
  fields: [
    { key: "ItemNo", label: "Ürün No", sample: "SK-10025" },
    { key: "Description", label: "Açıklama", sample: "ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE" },
    { key: "Description2", label: "Açıklama 2", sample: "İKİNCİ AÇIKLAMA" },
    { key: "UoM", label: "Birim", sample: "ADET" },
    { key: "Gtin", label: "GTIN", sample: "8690000012343" },
    { key: "Barcode", label: "Barkod", sample: "8690000012343" },
    { key: "Category", label: "Kategori", sample: "KOZMETİK" },
    { key: "VariantCode", label: "Varyant", sample: "MAVİ" },
    { key: "Company", label: "Şirket adı", sample: "ÖRNEK ŞİRKET A.Ş." },
    { key: "Today", label: "Bugünün tarihi", sample: "21.10.2026" },
  ],
  images: [],
};
