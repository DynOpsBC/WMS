import { describe, expect, it } from "vitest";
import {
  buildFilterPayload,
  filterRows,
  formatQty,
  formatSigned,
  groupLinesByLp,
  normalizeData,
  splitList,
  summarize,
  summaryChips,
} from "./model";
import { localCompare, sampleRows } from "./sampleData";
import type { LpLine } from "./types";

const line = (lpNo: string, qtyBase: number, extra: Partial<LpLine> = {}): LpLine => ({
  lpNo,
  lpStatus: "Oluşturuldu",
  assignedDocType: "",
  assignedDocNo: "",
  orphan: false,
  lineNo: 10000,
  qty: qtyBase,
  uom: "ADET",
  qtyBase,
  lot: "",
  sourceEntryNo: 0,
  sourceDocType: "",
  sourceDocNo: "",
  sourceBin: "",
  ...extra,
});

describe("formatQty / formatSigned", () => {
  it("Türkçe binlik ayırıcı ve ondalık", () => {
    expect(formatQty(45000)).toBe("45.000");
    expect(formatQty(1234.5)).toBe("1.234,5");
    expect(formatQty(0.000001)).toBe("0");
    expect(formatQty(undefined)).toBe("0");
  });

  it("işaretli fark", () => {
    expect(formatSigned(45000)).toBe("+45.000");
    expect(formatSigned(-20)).toBe("−20");
    expect(formatSigned(0)).toBe("0");
    expect(formatSigned(Number.NaN)).toBe("0");
  });
});

describe("groupLinesByLp", () => {
  it("satırları LP bazında toplar, ilk görülme sırası korunur", () => {
    const groups = groupLinesByLp([
      line("LP2", 30, { lineNo: 10000 }),
      line("LP1", 10, { orphan: true, assignedDocNo: "PA1", assignedDocType: "Depo Yerleştirme" }),
      line("LP2", 0.1, { lineNo: 20000 }),
      line("LP2", 0.2, { lineNo: 30000 }),
    ]);
    expect(groups.map((g) => g.lpNo)).toEqual(["LP2", "LP1"]);
    expect(groups[0].lines).toHaveLength(3);
    expect(groups[0].totalBase).toBe(30.3);
    expect(groups[1].orphan).toBe(true);
    expect(groups[1].assignedDocNo).toBe("PA1");
  });

  it("boş liste", () => {
    expect(groupLinesByLp([])).toEqual([]);
  });
});

describe("splitList", () => {
  it("virgüllü listeyi kırpar ve tekrarları atar", () => {
    expect(splitList("LP1, LP2,LP1, ,LP3")).toEqual(["LP1", "LP2", "LP3"]);
    expect(splitList("")).toEqual([]);
    expect(splitList(undefined)).toEqual([]);
  });
});

describe("filterRows", () => {
  const rows = sampleRows();

  it("durum çipi", () => {
    const red = filterRows(rows, "lpOver", "");
    expect(red.length).toBeGreaterThan(0);
    expect(red.every((r) => r.status === "lpOver")).toBe(true);
  });

  it("önerilen düzeltme çipi yalnız nedenli satırlar", () => {
    const action = filterRows(rows, "action", "");
    expect(action.every((r) => r.reason !== "none")).toBe(true);
    expect(action.some((r) => r.reason === "orphanAssignment" && r.status === "equal")).toBe(true);
  });

  it("arama göz, madde, lot ve LP no içinde (büyük/küçük harf duyarsız)", () => {
    expect(filterRows(rows, "all", "k.k03.11").map((r) => r.bin)).toEqual(["K.K03.11"]);
    expect(filterRows(rows, "all", "lp0001907").map((r) => r.bin)).toEqual(["K.K03.11"]);
    expect(filterRows(rows, "all", "LT-0913")).toHaveLength(1);
    expect(filterRows(rows, "all", "itm-620015")).toHaveLength(2);
    expect(filterRows(rows, "all", "yok-böyle-bir-şey")).toHaveLength(0);
  });
});

describe("buildFilterPayload", () => {
  it("kırpar ve büyük harfe çevirir (Türkçe i)", () => {
    expect(
      buildFilterPayload({ location: " merkez ", zone: "pick", binFrom: "k.k03.01", binTo: "", item: "itm-1*", onlyDiff: true }),
    ).toEqual({ location: "MERKEZ", zone: "PICK", binFrom: "K.K03.01", binTo: "", item: "ITM-1*", onlyDiff: true });
  });
});

describe("summarize / summaryChips", () => {
  it("sayılar ve toplamlar", () => {
    const s = summarize(sampleRows());
    expect(s.rows).toBe(12);
    expect(s.lpOver).toBe(2);
    expect(s.equal).toBe(4);
    expect(s.orphanLps).toBe(1);
    expect(s.undoneReceiptRows).toBe(1);
    expect(s.lpSurplusQty).toBe(45000 + 300 + 360 + 200);
    expect(s.stockSurplusQty).toBe(240 + 360 + 200);
    const chips = summaryChips(s);
    expect(chips.find((c) => c.key === "lpOver")?.count).toBe(2);
    expect(chips.find((c) => c.key === "action")?.count).toBe(s.reasonRows);
  });
});

describe("normalizeData", () => {
  it("BC JSON metnini güvenle ayrıştırır, bilinmeyen değerleri düzeltir", () => {
    const data = normalizeData(
      JSON.stringify({
        location: "MERKEZ",
        onlyDiff: false,
        summary: { rows: 1, lpOver: 1 },
        rows: [{ id: 7, bin: "A", status: "garip", reason: "??", stock: "5", lp: 10, diff: 5, lines: [{ lpNo: "LP1", qtyBase: "10" }] }],
      }),
    );
    expect(data.needsLocation).toBe(false);
    expect(data.onlyDiff).toBe(false);
    expect(data.summary.lpOver).toBe(1);
    expect(data.summary.equal).toBe(0);
    expect(data.rows[0].status).toBe("equal");
    expect(data.rows[0].reason).toBe("none");
    expect(data.rows[0].stock).toBe(5);
    expect(data.rows[0].lines[0].qtyBase).toBe(10);
  });

  it("bozuk JSON boş ve lokasyon isteyen veri döner", () => {
    const data = normalizeData("{bozuk");
    expect(data.needsLocation).toBe(true);
    expect(data.rows).toEqual([]);
  });
});

describe("localCompare (önizleme süzgeci)", () => {
  it("yalnız farklar eşit ve nedensiz satırları gizler, özet tüm satırları sayar", () => {
    const data = localCompare({ location: "MERKEZ", onlyDiff: true });
    expect(data.rows.some((r) => r.status === "equal" && r.reason === "none")).toBe(false);
    expect(data.summary.equal).toBe(4);
  });

  it("göz aralığı ve madde süzgeci", () => {
    const data = localCompare({ location: "MERKEZ", binFrom: "K.K03.01", binTo: "K.K03.99", item: "ITM-104233", onlyDiff: false });
    expect(data.rows.map((r) => r.bin)).toEqual(["K.K03.11", "K.K03.12"]);
  });
});

describe("normalizeData — göz zorunlu olmayan lokasyon (Kitoko)", () => {
  it("binMandatory bayrağını ve lokasyon bayraklarını okur; yoksa göz modu varsayılır", () => {
    const d = normalizeData({
      location: "KTK",
      binMandatory: false,
      locations: [
        { code: "KTK", name: "Kitoko", binMandatory: false },
        { code: "WH1", name: "Raflı", binMandatory: true },
      ],
      rows: [{ id: 1, bin: "", item: "A", stock: 10, lp: 12, diff: 2, status: "lpOver", reason: "none", lines: [] }],
    });
    expect(d.binMandatory).toBe(false);
    expect(d.locations.map((l) => l.binMandatory)).toEqual([false, true]);
    expect(d.rows[0].bin).toBe("");
    expect(normalizeData({ location: "WH1" }).binMandatory).toBe(true);
    expect(normalizeData({ locations: [{ code: "X" }] }).locations[0]).toEqual({ code: "X", name: "" });
  });
});
