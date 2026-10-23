// Kitoko (23 Eki 2026): "8x4 (80×40 mm) seçiyorum, çıkarırken tam sığmıyor".
// Taşma yazıcı noktasıyla (BC ^PW/^LL) ölçülür; ölçü değişince öğeler oranlanır.
import { describe, expect, it } from "vitest";
import { createElement, normalizeDesign, sampleValues } from "../model/design";
import { edgeClearanceMm, labelDots, layoutContext, overflowDots, printBoundsDots } from "../model/layout";
import { alignElements, countOutside, distributeElements, fitAllToLabel, fitElementsInside, scaleDesignTo } from "../model/ops";
import type { LabelDesign } from "../model/types";
import { DEFAULT_SAFE_MARGIN_MM, validateDesign } from "../model/validate";
import { fieldsForKind, TEMPLATES, templatePreviewDesign } from "../templates";

const LOGO = { id: "COMPANY", name: "Şirket logosu", dataUrl: "data:image/png;base64,AAAA" };

function fromTemplate(id: string): LabelDesign {
  const t = TEMPLATES.find((x) => x.id === id);
  if (!t) throw new Error(id);
  const base = normalizeDesign({ kind: t.kind, code: "X", fields: fieldsForKind(t.kind, []), images: [LOGO] });
  return templatePreviewDesign(base, t);
}

const ctxOf = (d: LabelDesign) => layoutContext(d, sampleValues(d));
const overflowing = (d: LabelDesign) => d.elements.filter((el) => overflowDots(el, ctxOf(d)) > 0).map((el) => el.id);

describe("baskı ölçüsü (nokta)", () => {
  it("80×40 mm @203 dpi = ^PW640 ^LL320; 100×50 = 800×400; 100×100 = 800×800; 300 dpi = 12 nokta/mm", () => {
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, dpi: 203 });
    expect(labelDots(ctxOf(d))).toEqual({ w: 640, h: 320 });
    expect(labelDots(ctxOf({ ...d, widthMm: 100, heightMm: 50 }))).toEqual({ w: 800, h: 400 });
    expect(labelDots(ctxOf({ ...d, widthMm: 100, heightMm: 100 }))).toEqual({ w: 800, h: 800 });
    expect(labelDots(ctxOf({ ...d, dpi: 300 }))).toEqual({ w: 960, h: 480 });
  });

  it("203 dışındaki dpi uyarılır (300 dpi tasarım 203 dpi yazıcıda 1,5 kat büyük basılır)", () => {
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, dpi: 300 });
    expect(validateDesign(d, ctxOf(d)).some((w) => w.level === "warn" && w.message.includes("1,5 kat"))).toBe(true);
    const ok = normalizeDesign({ widthMm: 80, heightMm: 40, dpi: 203 });
    expect(validateDesign(ok, ctxOf(ok)).some((w) => w.message.includes("dpi"))).toBe(false);
  });

  it("QR sembolü ^FO'nun 10 nokta altından başlar; alttaki taşma bu payla ölçülür", () => {
    const qr = { ...createElement("qr", "q", { field: "ItemNo" }), xMm: 60, yMm: 19, wMm: 20, hMm: 20 };
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, fields: [{ key: "ItemNo", label: "Ürün", sample: "SK-10025" }], elements: [qr] });
    const { ink, box } = printBoundsDots(d.elements[0], ctxOf(d));
    expect(box).toEqual({ x0: 480, y0: 152, x1: 640, y1: 312 });
    expect(ink.y0).toBe(162);
    expect(overflowDots(d.elements[0], ctxOf(d))).toBe(0);
    const lower = { ...d, elements: [{ ...d.elements[0], yMm: 21 }] };
    // y 21 mm = 168 nokta + 160 nokta (20 mm) kutu = 328 > 320 → 8 nokta = 1 mm taşar.
    expect(overflowDots(lower.elements[0], ctxOf(lower))).toBe(8);
    expect(validateDesign(lower, ctxOf(lower)).some((w) => w.code === "overflow" && w.level === "error" && w.message.includes("640 × 320 nokta"))).toBe(true);
  });

  it("80 mm'lik kutu tam sığar; 0,05 mm fazlası (1 nokta) yuvarlamada kaybolmaz ama 0,25 mm taşar", () => {
    const box = { ...createElement("box", "b"), xMm: 0, yMm: 0, wMm: 80, hMm: 5 };
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, elements: [box] });
    expect(overflowDots(d.elements[0], ctxOf(d))).toBe(0);
    const wide = { ...d, elements: [{ ...d.elements[0], wMm: 80.25 }] };
    expect(overflowDots(wide.elements[0], ctxOf(wide))).toBe(2);
  });

  it("güvenli kenar: yazı kenara 0,5 mm yakınsa öneri; ters yazı ve kutu muaf", () => {
    const text = { ...createElement("text", "t"), text: "ÜRÜN", xMm: 0.5, yMm: 10, wMm: 30, fontMm: 3 };
    const band = { ...createElement("box", "b"), xMm: 0, yMm: 0, wMm: 80, hMm: 5 };
    const title = { ...createElement("text", "w"), text: "BAŞLIK", inverted: true, xMm: 0.5, yMm: 0.5, wMm: 30, fontMm: 3 };
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, elements: [text, band, title] });
    const ctx = ctxOf(d);
    expect(edgeClearanceMm(d.elements[0], ctx)).toBeCloseTo(0.5, 2);
    const w = validateDesign(d, ctx, { safeMarginMm: DEFAULT_SAFE_MARGIN_MM });
    expect(w.filter((x) => x.code === "margin").map((x) => x.elementId)).toEqual(["t"]);
    expect(w.find((x) => x.code === "margin")?.level).toBe("info");
    expect(validateDesign(d, ctx).some((x) => x.code === "margin")).toBe(false);
  });
});

describe("ölçü değişimi", () => {
  for (const id of ["lp-qr-lot", "lp-standard", "item-big-no-qr", "bin-arrow-up", "lp-qr-contents", "lp-a6"]) {
    it(`${id}: 80×40 seçilince öğeler oranlanır, hiçbiri dışarıda kalmaz`, () => {
      const d = fromTemplate(id);
      expect(countOutside(d, 80, 40)).toBeGreaterThan(0);
      const scaled = scaleDesignTo(d, 80, 40);
      expect(scaled.widthMm).toBe(80);
      expect(scaled.heightMm).toBe(40);
      expect(scaled.elements.length).toBe(d.elements.length);
      expect(overflowing(scaled)).toEqual([]);
    });
  }

  it("100×50 → 80×40: konum ve yazı boyu 0,8 kat", () => {
    const d = fromTemplate("lp-qr-lot");
    const scaled = scaleDesignTo(d, 80, 40);
    const lp = scaled.elements.find((e) => e.field === "LPNo" && e.type === "field");
    const src = d.elements.find((e) => e.field === "LPNo" && e.type === "field");
    expect(lp?.xMm).toBeCloseTo((src?.xMm ?? 0) * 0.8, 1);
    expect(lp?.fontMm).toBeCloseTo((src?.fontMm ?? 0) * 0.8, 1);
    const qr = scaled.elements.find((e) => e.type === "qr");
    expect(qr?.wMm).toBe(24);
  });

  it("“Etikete sığdır”: taşan öğe güvenli kenara çekilir, sığan öğe yerinde kalır", () => {
    const inside = { ...createElement("text", "a"), text: "A", xMm: 5, yMm: 5, wMm: 20, fontMm: 3 };
    const out = { ...createElement("text", "b"), text: "B", xMm: 70, yMm: 38, wMm: 20, fontMm: 3 };
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, elements: [inside, out] });
    const fixed = fitElementsInside(d, ctxOf(d), DEFAULT_SAFE_MARGIN_MM);
    expect(fixed.elements[0]).toBe(d.elements[0]);
    expect(overflowing(fixed)).toEqual([]);
    expect(edgeClearanceMm(fixed.elements[1], ctxOf(fixed))).toBeGreaterThanOrEqual(DEFAULT_SAFE_MARGIN_MM - 0.13);
  });

  it("“Tümünü oranla”: 100×50 tasarım 60×40 etikete yerleşimi korunarak sığar", () => {
    const d = { ...fromTemplate("item-big-no-qr"), widthMm: 60, heightMm: 40 };
    expect(overflowing(d).length).toBeGreaterThan(0);
    const fitted = fitAllToLabel(d, ctxOf(d), DEFAULT_SAFE_MARGIN_MM);
    expect(overflowing(fitted)).toEqual([]);
    const xs = (x: LabelDesign) => x.elements.map((e) => e.xMm);
    // sıralama (soldan sağa) korunur
    const order = (v: number[]) => v.map((_, i) => i).sort((a, b) => v[a] - v[b]).join(",");
    expect(order(xs(fitted))).toBe(order(xs(d)));
  });

  it("etiketten büyük öğe küçültülür", () => {
    const qr = { ...createElement("qr", "q"), text: "X", xMm: 0, yMm: 0, wMm: 60, hMm: 60 };
    const d = normalizeDesign({ widthMm: 80, heightMm: 40, elements: [qr] });
    const fixed = fitElementsInside(d, ctxOf(d), 0);
    expect(fixed.elements[0].wMm).toBeLessThan(40);
    expect(overflowing(fixed)).toEqual([]);
  });
});

describe("hizalama", () => {
  const a = { ...createElement("box", "a"), xMm: 10, yMm: 5, wMm: 10, hMm: 4 };
  const b = { ...createElement("box", "b"), xMm: 30, yMm: 15, wMm: 6, hMm: 6 };
  const c = { ...createElement("box", "c"), xMm: 60, yMm: 25, wMm: 8, hMm: 8 };
  const d = normalizeDesign({ widthMm: 80, heightMm: 40, elements: [a, b, c] });

  it("tek öğe etikete (güvenli kenarla) hizalanır", () => {
    const ctx = ctxOf(d);
    expect(alignElements(d, ["b"], "right", ctx, 1.5).elements[1].xMm).toBe(72.5);
    expect(alignElements(d, ["b"], "hcenter", ctx).elements[1].xMm).toBe(37);
    expect(alignElements(d, ["b"], "bottom", ctx, 1.5).elements[1].yMm).toBe(32.5);
  });

  it("çoklu seçim seçimin kutusuna hizalanır ve eşit dağıtılır", () => {
    const ctx = ctxOf(d);
    const left = alignElements(d, ["a", "b", "c"], "left", ctx);
    expect(left.elements.map((e) => e.xMm)).toEqual([10, 10, 10]);
    const top = alignElements(d, ["a", "c"], "top", ctx);
    expect(top.elements[2].yMm).toBe(5);
    const spread = distributeElements(d, ["a", "b", "c"], "h", ctx);
    // a: 10..20, c: 60..68 → aralık (58 - 24) / 2 = 17 → b.x = 37
    expect(spread.elements[1].xMm).toBe(37);
  });
});
