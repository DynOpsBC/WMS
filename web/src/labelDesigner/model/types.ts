// BC ↔ tasarımcı sözleşmesi (docs/label-designer-contract.md, v1).
// Bilinmeyen anahtarlar çalışma zamanında nesnelerde korunur (spread ile),
// tipler yalnız bilinen alanları tanımlar.

export type LabelKind = "Item" | "Bin" | "Zone" | "LP";
export type ElementType = "text" | "field" | "barcode" | "qr" | "line" | "box" | "image";
export type Rotation = 0 | 90 | 180 | 270;
export type Align = "left" | "center" | "right";
export type Symbology = "code128" | "ean13" | "gs1-128";
/** 203 ve 300 seçilebilir; BC 600'ü tolere eder (gelirse korunur). */
export type Dpi = 203 | 300 | 600;

export interface LabelElement {
  id: string;
  lineNo: number;
  type: ElementType;
  xMm: number;
  yMm: number;
  wMm: number;
  hMm: number;
  rotation: Rotation;
  fontMm: number;
  fontWidthMm: number;
  minFontMm: number;
  bold: boolean;
  align: Align;
  field: string;
  text: string;
  prefix: string;
  suffix: string;
  maxLines: number;
  fit: boolean;
  inverted: boolean;
  symbology: Symbology;
  showText: boolean;
  thicknessMm: number;
  imageId: string;
  imageGf: string;
  enabled: boolean;
}

export interface LabelField {
  key: string;
  label: string;
  sample: string;
}

export interface LabelImage {
  id: string;
  name: string;
  dataUrl: string;
  /** opsiyonel: BC saklar ve geri gönderir */
  widthPx?: number;
  heightPx?: number;
}

export interface LabelDesign {
  version: number;
  code: string;
  description: string;
  kind: LabelKind;
  widthMm: number;
  heightMm: number;
  dpi: Dpi;
  active: boolean;
  /** BC → tasarımcı → BC: yüklemedeki Aktif; BC Aktif'i yalnız active ≠ activeAtLoad ise yazar. */
  activeAtLoad?: boolean;
  elements: LabelElement[];
  fields: LabelField[];
  images: LabelImage[];
  /** BC → tasarımcı: yazma izni yoksa true (düzenleme ve kayıt kapalı) */
  readOnly?: boolean;
}

/** BC sınırları (aşan değer BC kaydını hatayla durdurur). */
export const LIMITS = {
  id: 50,
  text: 100,
  field: 30,
  prefix: 30,
  suffix: 30,
  imageId: 20,
  widthMm: 300,
  heightMm: 400,
  minSizeMm: 10,
} as const;

export const ELEMENT_TYPES: readonly ElementType[] = ["text", "field", "barcode", "qr", "line", "box", "image"];
export const LABEL_KINDS: readonly LabelKind[] = ["Item", "Bin", "Zone", "LP"];
export const ROTATIONS: readonly Rotation[] = [0, 90, 180, 270];
export const SYMBOLOGIES: readonly Symbology[] = ["code128", "ean13", "gs1-128"];
