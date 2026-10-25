// DesignJson okuma/yazma ve eleman yardımcıları. Bilinmeyen anahtarlar
// spread ile korunur: BC'nin eklediği alanlar kayıtta kaybolmaz.
import {
  ELEMENT_TYPES,
  LABEL_KINDS,
  ROTATIONS,
  SYMBOLOGIES,
  type Align,
  type Dpi,
  type ElementType,
  type LabelDesign,
  type LabelElement,
  type LabelField,
  type LabelImage,
  type LabelKind,
  type Rotation,
  type Symbology,
} from "./types";
import { roundMm } from "./units";

type Raw = Record<string, unknown>;

function isObject(v: unknown): v is Raw {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function num(v: unknown, fallback: number): number {
  const n = typeof v === "string" ? Number(v.replace(",", ".")) : typeof v === "number" ? v : NaN;
  return Number.isFinite(n) ? n : fallback;
}

function str(v: unknown, fallback = ""): string {
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return fallback;
}

function bool(v: unknown, fallback: boolean): boolean {
  if (typeof v === "boolean") return v;
  if (v === "true" || v === 1) return true;
  if (v === "false" || v === 0) return false;
  return fallback;
}

function oneOf<T extends string | number>(v: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(v as T) ? (v as T) : fallback;
}

export const ELEMENT_DEFAULTS: Omit<LabelElement, "id" | "type"> = {
  lineNo: 0,
  xMm: 0,
  yMm: 0,
  wMm: 0,
  hMm: 0,
  rotation: 0,
  fontMm: 0,
  fontWidthMm: 0,
  minFontMm: 0,
  bold: false,
  align: "left",
  field: "",
  text: "",
  prefix: "",
  suffix: "",
  maxLines: 1,
  fit: false,
  inverted: false,
  symbology: "code128",
  showText: true,
  thicknessMm: 0,
  imageId: "",
  imageGf: "",
  enabled: true,
};

export function normalizeElement(raw: unknown, index: number): LabelElement {
  const r: Raw = isObject(raw) ? raw : {};
  const d = ELEMENT_DEFAULTS;
  const rotation = num(r.rotation, 0);
  const type = (typeof r.type === "string" && r.type ? r.type : "text") as ElementType;
  return {
    ...r,
    id: str(r.id) || `e${index + 1}`,
    lineNo: Math.trunc(num(r.lineNo, d.lineNo)),
    type,
    xMm: num(r.xMm, d.xMm),
    yMm: num(r.yMm, d.yMm),
    wMm: Math.max(0, num(r.wMm, d.wMm)),
    hMm: Math.max(0, num(r.hMm, d.hMm)),
    // QR her zaman 0 (BC kayıtta 0'a çeker).
    rotation: type === "qr" ? 0 : oneOf<Rotation>(((rotation % 360) + 360) % 360 as Rotation, ROTATIONS, 0),
    fontMm: Math.max(0, num(r.fontMm, d.fontMm)),
    fontWidthMm: Math.max(0, num(r.fontWidthMm, d.fontWidthMm)),
    minFontMm: Math.max(0, num(r.minFontMm, d.minFontMm)),
    bold: bool(r.bold, d.bold),
    align: oneOf<Align>(r.align, ["left", "center", "right"], d.align),
    field: str(r.field),
    text: str(r.text),
    prefix: str(r.prefix),
    suffix: str(r.suffix),
    maxLines: Math.max(0, Math.trunc(num(r.maxLines, d.maxLines))),
    fit: bool(r.fit, d.fit),
    inverted: bool(r.inverted, d.inverted),
    symbology: oneOf<Symbology>(r.symbology, SYMBOLOGIES, d.symbology),
    showText: bool(r.showText, d.showText),
    thicknessMm: Math.max(0, num(r.thicknessMm, d.thicknessMm)),
    imageId: str(r.imageId),
    imageGf: str(r.imageGf),
    enabled: bool(r.enabled, d.enabled),
  };
}

function normalizeField(raw: unknown): LabelField | null {
  if (!isObject(raw)) return null;
  const key = str(raw.key);
  if (!key) return null;
  return { ...raw, key, label: str(raw.label) || key, sample: str(raw.sample) };
}

function normalizeImage(raw: unknown): LabelImage | null {
  if (!isObject(raw)) return null;
  const id = str(raw.id);
  if (!id) return null;
  const img: LabelImage = { ...raw, id, name: str(raw.name) || id, dataUrl: str(raw.dataUrl) };
  if (raw.widthPx !== undefined) img.widthPx = num(raw.widthPx, 0);
  if (raw.heightPx !== undefined) img.heightPx = num(raw.heightPx, 0);
  return img;
}

export function normalizeDesign(raw: unknown): LabelDesign {
  const r: Raw = isObject(raw) ? raw : {};
  const elementsRaw = Array.isArray(r.elements) ? r.elements : [];
  const seen = new Set<string>();
  const elements = elementsRaw.map((e, i) => {
    const el = normalizeElement(e, i);
    if (seen.has(el.id)) el.id = uniqueId(seen);
    seen.add(el.id);
    return el;
  });
  const widthMm = num(r.widthMm, 80);
  const heightMm = num(r.heightMm, 40);
  return {
    ...r,
    version: Math.trunc(num(r.version, 1)) || 1,
    code: str(r.code),
    description: str(r.description),
    kind: oneOf<LabelKind>(r.kind, LABEL_KINDS, "Item"),
    widthMm: widthMm > 0 ? widthMm : 80,
    heightMm: heightMm > 0 ? heightMm : 40,
    dpi: oneOf<Dpi>(Math.trunc(num(r.dpi, 203)) as Dpi, [203, 300, 600], 203),
    active: bool(r.active, false),
    readOnly: bool(r.readOnly, false),
    elements,
    fields: (Array.isArray(r.fields) ? r.fields : []).map(normalizeField).filter((f): f is LabelField => f !== null),
    images: (Array.isArray(r.images) ? r.images : []).map(normalizeImage).filter((i): i is LabelImage => i !== null),
  };
}

/** JSON metni → tasarım. Geçersiz JSON'da hata fırlatır. */
export function parseDesign(json: string): LabelDesign {
  return parseIncoming(json).design;
}

/**
 * BC'den gelen LoadDesign: `"merge": "images"` (CompanyLogoRequested yanıtı)
 * ise tasarımcı yalnız images[]'i birleştirir. merge anahtarı tasarımda tutulmaz.
 */
export function parseIncoming(json: string): { design: LabelDesign; merge: string } {
  const raw: unknown = JSON.parse(json);
  if (!isObject(raw)) throw new Error("Tasarım JSON bir nesne olmalı");
  const { merge, ...rest } = raw;
  return { design: normalizeDesign(rest), merge: str(merge) };
}

/** Tasarım → JSON (elemanlar dizi sırasıyla; bilinmeyen alanlar dahil). */
export function serializeDesign(design: LabelDesign): string {
  return JSON.stringify(design);
}

function uniqueId(taken: Set<string>): string {
  let n = taken.size + 1;
  while (taken.has(`e${n}`)) n += 1;
  return `e${n}`;
}

/** Tasarımda kullanılmayan yeni eleman kimliği. */
export function nextElementId(design: LabelDesign): string {
  let max = 0;
  for (const el of design.elements) {
    const m = /^e(\d+)$/.exec(el.id);
    if (m) max = Math.max(max, Number(m[1]));
  }
  const taken = new Set(design.elements.map((e) => e.id));
  let n = max + 1;
  while (taken.has(`e${n}`)) n += 1;
  return `e${n}`;
}

export function isKnownType(type: string): type is ElementType {
  return (ELEMENT_TYPES as readonly string[]).includes(type);
}

/** Paletten eklenen elemanın varsayılanları (mm). */
export function createElement(type: ElementType, id: string, opts: { field?: string; imageId?: string } = {}): LabelElement {
  const base: LabelElement = { ...ELEMENT_DEFAULTS, id, type };
  switch (type) {
    case "text":
      return { ...base, wMm: 30, fontMm: 3, hMm: 3, text: "Yeni metin" };
    case "field":
      return { ...base, wMm: 40, fontMm: 3, hMm: 3, field: opts.field ?? "" };
    case "barcode":
      return { ...base, wMm: 50, hMm: 10, field: opts.field ?? "", symbology: "code128", showText: true };
    case "qr":
      return { ...base, wMm: 20, hMm: 20, field: opts.field ?? "" };
    case "line":
      return { ...base, wMm: 40, hMm: 0.5, thicknessMm: 0.5 };
    case "box":
      return { ...base, wMm: 30, hMm: 15, thicknessMm: 0.5 };
    case "image":
      return { ...base, wMm: 20, hMm: 20, imageId: opts.imageId ?? "" };
  }
}

/** Aynı ayarlarla kopya: yeni kimlik, lineNo 0, 2 mm kaydırılmış. */
export function duplicateElement(el: LabelElement, id: string): LabelElement {
  return { ...el, id, lineNo: 0, xMm: roundMm(el.xMm + 2), yMm: roundMm(el.yMm + 2) };
}

/** BC ResolveValue: alan seçiliyse alan değeri, değilse sabit metin; boşsa boş. */
export function resolveValue(el: LabelElement, values: ReadonlyMap<string, string>): string {
  const raw = el.field ? values.get(el.field) ?? "" : el.text;
  if (raw === "") return "";
  return el.prefix + raw + el.suffix;
}

export function sampleValues(design: LabelDesign): Map<string, string> {
  return new Map(design.fields.map((f) => [f.key, f.sample]));
}

export const TYPE_LABELS: Record<ElementType, string> = {
  text: "Metin",
  field: "Veri alanı",
  barcode: "Barkod",
  qr: "QR kod",
  line: "Çizgi",
  box: "Kutu",
  image: "Resim",
};

export const KIND_LABELS: Record<LabelKind, string> = {
  Item: "Ürün etiketi",
  Bin: "Raf etiketi",
  Zone: "Alan etiketi",
  LP: "LP / Palet etiketi",
  Lot: "Lot etiketi",
};

export const SYMBOLOGY_LABELS: Record<Symbology, string> = {
  code128: "Code128 (genel)",
  ean13: "EAN-13 (ürün barkodu)",
  "gs1-128": "GS1-128 (lojistik)",
};

export function fieldLabel(design: LabelDesign, key: string): string {
  return design.fields.find((f) => f.key === key)?.label ?? key;
}

/** Uyarı ve listelerde elemanın kısa adı. */
export function elementName(design: LabelDesign, el: LabelElement): string {
  const typeLabel = isKnownType(el.type) ? TYPE_LABELS[el.type] : el.type;
  if (el.field) return `${typeLabel}: ${fieldLabel(design, el.field)}`;
  if (el.type === "text" || el.type === "barcode" || el.type === "qr") {
    const t = el.text.trim();
    if (t) return `${typeLabel}: “${t.length > 18 ? `${t.slice(0, 18)}…` : t}”`;
  }
  if (el.type === "image" && el.imageId) {
    const img = design.images.find((i) => i.id === el.imageId);
    return `${typeLabel}: ${img?.name ?? el.imageId}`;
  }
  return typeLabel;
}
