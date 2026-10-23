import { describe, expect, it } from "vitest";
import { normalizeDesign, sampleValues } from "../model/design";
import { elementGeometry, layoutContext } from "../model/layout";
import { DEFAULT_SAFE_MARGIN_MM, validateDesign } from "../model/validate";
import { applyTemplate, fieldsForKind, KIND_FIELD_KEYS, TEMPLATES, templatePreviewDesign, templatesFor } from "../templates";

const LOGO = { id: "COMPANY", name: "Şirket logosu", dataUrl: "data:image/png;base64,AAAA" };

describe("hazır şablonlar", () => {
  it("istenen şablonlar var", () => {
    const names = TEMPLATES.map((t) => t.name);
    for (const n of [
      "QR + Ürün No (80×40)",
      "Barkod + Açıklama (80×40)",
      "Büyük Ürün No + QR (100×50)",
      "Küçük ürün etiketi (60×40)",
      "Logo + Ürün + Barkod (100×50)",
      "Raf kodu büyük + QR (80×40)",
      "Raf + Alan + Barkod (100×50)",
      "LP Standart 4x2 (101.6×50.8)",
      "Palet A6 (100×150) SSCC + içerik",
      "Karma palet özet (100×100)",
      "LP QR + Lot (100×50)",
      "LP QR + içerik (100×100)",
      "Lot etiketi (80×40)",
    ]) {
      expect(names).toContain(n);
    }
    expect(names.some((n) => n.startsWith("Ok işaretli raf etiketi"))).toBe(true);
    expect(templatesFor("LP").every((t) => t.kind === "LP")).toBe(true);
    expect(new Set(TEMPLATES.map((t) => t.id)).size).toBe(TEMPLATES.length);
  });

  for (const t of TEMPLATES) {
    it(`${t.name}: alanlar türe ait, öğeler etiket içinde, uyarı yok`, () => {
      const keys = new Set(KIND_FIELD_KEYS[t.kind]);
      for (const el of t.elements) if (el.field) expect(keys, `${el.field}`).toContain(el.field);

      const base = normalizeDesign({ kind: t.kind, code: "X", fields: fieldsForKind(t.kind, []), images: [LOGO] });
      const design = templatePreviewDesign(base, t);
      const ctx = layoutContext(design, sampleValues(design));
      for (const el of design.elements) {
        const e = elementGeometry(el, ctx).extent;
        expect(e.x, `${el.id} x`).toBeGreaterThanOrEqual(0);
        expect(e.y, `${el.id} y`).toBeGreaterThanOrEqual(0);
        expect(e.x + e.w, `${el.id} sağ`).toBeLessThanOrEqual(design.widthMm + 0.05);
        expect(e.y + e.h, `${el.id} alt`).toBeLessThanOrEqual(design.heightMm + 0.05);
      }
      // Güvenli kenar (1,5 mm) dahil: şablonlar yazıcı kaydırsa da kesilmez.
      expect(validateDesign(design, ctx, { safeMarginMm: DEFAULT_SAFE_MARGIN_MM }).map((w) => w.message)).toEqual([]);
    });
  }

  it("LP QR şablonlarında QR yalnız LP No taşır (terminal LP okutma alanları kabul etsin)", () => {
    for (const id of ["lp-qr-lot", "lp-qr-contents"]) {
      const t = TEMPLATES.find((x) => x.id === id);
      expect(t, id).toBeDefined();
      const qrs = t?.elements.filter((e) => e.type === "qr") ?? [];
      expect(qrs.length, id).toBe(1);
      expect(qrs[0].field).toBe("LPNo");
      expect(qrs[0].prefix ?? "").toBe("");
      expect(qrs[0].suffix ?? "").toBe("");
    }
    const contents = TEMPLATES.find((x) => x.id === "lp-qr-contents");
    for (const key of ["ContentsLine1", "ContentsLine2", "ContentsLine3", "ItemCount", "TotalQuantity"]) {
      expect(contents?.elements.some((e) => e.field === key), key).toBe(true);
    }
    const lot = TEMPLATES.find((x) => x.id === "lp-qr-lot");
    for (const key of ["LPNo", "ItemNo", "Description", "Lots", "ExpirationDate", "TotalQuantity", "UoM", "BinCode", "Company", "Today", "SSCC"]) {
      expect(lot?.elements.some((e) => e.field === key), key).toBe(true);
    }
  });

  it("Lot etiketi: QR = ürün no, barkod = lot no", () => {
    const t = TEMPLATES.find((x) => x.id === "lot-standard");
    expect(t?.kind).toBe("Lot");
    expect(t?.elements.find((e) => e.type === "qr")?.field).toBe("ItemNo");
    expect(t?.elements.find((e) => e.type === "barcode")?.field).toBe("LotNo");
    expect(normalizeDesign({ kind: "Lot", code: "LOT" }).kind).toBe("Lot");
  });

  it("şablon uygulanınca öğeler + ölçü + dpi değişir, kod/alanlar/resimler kalır", () => {
    const t = TEMPLATES.find((x) => x.id === "lp-a6");
    expect(t).toBeDefined();
    if (!t) return;
    const before = normalizeDesign({ kind: "LP", code: "LP", dpi: 300, widthMm: 80, heightMm: 40, extra: 1, images: [LOGO], fields: fieldsForKind("LP", []), elements: [{ type: "text", text: "eski" }] });
    const after = applyTemplate(before, t);
    expect(after.widthMm).toBe(100);
    expect(after.heightMm).toBe(150);
    expect(after.dpi).toBe(203);
    expect(after.code).toBe("LP");
    expect(after.images).toEqual(before.images);
    expect((after as unknown as { extra: number }).extra).toBe(1);
    expect(after.elements.length).toBe(t.elements.length);
    expect(after.elements.every((e) => e.lineNo === 0)).toBe(true);
    expect(after.elements[0].id).toBe("e1");
  });
});
