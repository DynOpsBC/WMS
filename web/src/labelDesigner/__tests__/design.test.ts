import { describe, expect, it } from "vitest";
import { normalizeDesign, parseDesign, parseIncoming, serializeDesign } from "../model/design";
import { layoutContext } from "../model/layout";
import { duplicateElements, nudge, rotateTo, updateElement } from "../model/ops";
import { sampleValues } from "../model/design";
import { SAMPLE_DESIGN } from "../sampleDesign";
import { buildDesignJson } from "../state/exportDesign";

const INCOMING = {
  version: 1,
  code: "ITEM",
  description: "Ürün etiketi",
  kind: "Item",
  widthMm: 80,
  heightMm: 40,
  dpi: 203,
  active: true,
  bcRevision: "7", // bilinmeyen üst düzey alan
  elements: [
    { id: "e1", lineNo: 10000, type: "field", xMm: 2, yMm: 2, wMm: 50, hMm: 6, rotation: 0, fontMm: 4, field: "ItemNo", fit: true, enabled: true, bcNote: { keep: true } },
    { id: "e2", lineNo: 20000, type: "qr", xMm: 57, yMm: 6.5, wMm: 21, hMm: 21, rotation: 90, field: "ItemNo" },
  ],
  fields: [{ key: "ItemNo", label: "Ürün No", sample: "AB.00175", group: "item" }],
  images: [{ id: "COMPANY", name: "Şirket logosu", dataUrl: "data:image/png;base64,AAAA", widthPx: 300, heightPx: 120, source: "bc" }],
};

describe("DesignJson gidiş-dönüş", () => {
  it("yükle → düzenle → kaydet: bilinmeyen alanlar korunur", () => {
    const design = parseDesign(JSON.stringify(INCOMING));
    let edited = updateElement(design, "e1", { xMm: 5, text: "x" });
    edited = nudge(edited, ["e1"], 1, 0);
    edited = { ...edited, description: "Yeni açıklama" };
    const out = JSON.parse(serializeDesign(edited));

    expect(out.bcRevision).toBe("7");
    expect(out.description).toBe("Yeni açıklama");
    expect(out.elements[0].bcNote).toEqual({ keep: true });
    expect(out.elements[0].xMm).toBe(6);
    expect(out.elements[0].lineNo).toBe(10000);
    expect(out.fields[0].group).toBe("item");
    expect(out.images[0]).toMatchObject({ id: "COMPANY", source: "bc", widthPx: 300, heightPx: 120 });
    // eksik bilinen alanlar varsayılanla tamamlanır
    expect(out.elements[1]).toMatchObject({ symbology: "code128", showText: true, enabled: true, maxLines: 1 });
  });

  it("QR her zaman 0 derece, geçersiz değerler düzeltilir", () => {
    const d = normalizeDesign({ elements: [{ type: "qr", rotation: 90 }, { type: "text", rotation: -90, align: "bogus", dpi: 1 }], dpi: 999 });
    expect(d.elements[0].rotation).toBe(0);
    expect(d.elements[1].rotation).toBe(270);
    expect(d.elements[1].align).toBe("left");
    expect(d.dpi).toBe(203);
    expect(d.elements.map((e) => e.id)).toEqual(["e1", "e2"]);
  });

  it("activeAtLoad BC'ye geri gider, readOnly gitmez", async () => {
    const { design } = parseIncoming(JSON.stringify({ ...INCOMING, active: true, activeAtLoad: true, readOnly: false }));
    expect(design.activeAtLoad).toBe(true);
    const out = JSON.parse(await buildDesignJson({ ...design, active: false }, async () => null));
    expect(out.activeAtLoad).toBe(true);
    expect(out.active).toBe(false);
    expect("readOnly" in out).toBe(false);
  });

  it("merge: images ayrı okunur ve tasarımda kalmaz", () => {
    const { design, merge } = parseIncoming(JSON.stringify({ ...INCOMING, merge: "images" }));
    expect(merge).toBe("images");
    expect("merge" in design).toBe(false);
  });

  it("çoğaltma yeni kimlik ve lineNo 0 verir, sıra korunur", () => {
    const design = parseDesign(JSON.stringify(INCOMING));
    const { design: d2, newIds } = duplicateElements(design, ["e1"]);
    expect(newIds).toEqual(["e3"]);
    expect(d2.elements.map((e) => e.id)).toEqual(["e1", "e3", "e2"]);
    expect(d2.elements[1].lineNo).toBe(0);
  });

  it("döndürme merkezi korur, 90°'de kutu yer değiştirir", () => {
    const d = normalizeDesign(SAMPLE_DESIGN);
    const ctx = layoutContext(d, sampleValues(d));
    const bar = d.elements.find((e) => e.type === "barcode");
    expect(bar).toBeDefined();
    if (!bar) return;
    const r = rotateTo(bar, 90, ctx);
    expect(r.rotation).toBe(90);
    expect(r.wMm).toBe(bar.wMm);
    // QR dönmez
    const qr = d.elements.find((e) => e.type === "qr");
    if (qr) expect(rotateTo(qr, 90, ctx)).toBe(qr);
  });
});
