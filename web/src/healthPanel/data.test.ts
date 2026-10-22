import { describe, expect, it } from "vitest";
import {
  categorySeverity,
  filterBySeverity,
  formatQty,
  hiddenCount,
  normalizeHealth,
  normalizeResult,
  sortCategories,
  toSeverity,
  totalIssues,
} from "./data";
import { SAMPLE_PAYLOAD } from "./sample";

describe("normalizeHealth", () => {
  it("parses the BC JSON string payload", () => {
    const d = normalizeHealth(JSON.stringify(SAMPLE_PAYLOAD));
    expect(d.locationFilter).toBe("BADE");
    expect(d.locations).toHaveLength(2);
    expect(d.categories).toHaveLength(7);
    expect(d.summary).toEqual({ critical: 3, warning: 4, info: 2 });
    const stock = d.categories[0];
    expect(stock.key).toBe("stockMismatch");
    expect(stock.issues[0].qtyBin).toBe(45000);
    expect(stock.issues[0].qtyLp).toBe(90000);
    expect(stock.issues[0].compareAvailable).toBe(true);
  });

  it("survives broken or partial payloads", () => {
    expect(normalizeHealth("{not json").categories).toEqual([]);
    expect(normalizeHealth(null).summary).toEqual({ critical: 0, warning: 0, info: 0 });
    const d = normalizeHealth({
      categories: [{ key: "x", total: "3", issues: [{ id: "7", severity: "BOGUS", qtyBin: "12,5", canFix: "true" }] }, { title: "no key" }],
    });
    expect(d.categories).toHaveLength(1);
    const issue = d.categories[0].issues[0];
    expect(issue.id).toBe(7);
    expect(issue.severity).toBe("info");
    expect(issue.qtyBin).toBe(12.5);
    expect(issue.canFix).toBe(true);
    expect(d.maxRowsPerCategory).toBe(50);
  });

  it("never reports fewer total than shown issues", () => {
    const d = normalizeHealth({ categories: [{ key: "k", total: 0, issues: [{ id: 1 }, { id: 2 }] }] });
    expect(d.categories[0].total).toBe(2);
    expect(hiddenCount(d.categories[0])).toBe(0);
  });
});

describe("helpers", () => {
  const d = normalizeHealth(SAMPLE_PAYLOAD);

  it("computes hidden (devamı) count", () => {
    const orphan = d.categories.find((c) => c.key === "orphanAssignment")!;
    expect(hiddenCount(orphan)).toBe(15);
  });

  it("sorts categories by severity then size, clean ones last", () => {
    const keys = sortCategories(d.categories).map((c) => c.key);
    expect(keys.slice(0, 3)).toEqual(["stockMismatch", "printJob", "lpSourceEntry"]);
    expect(keys[keys.length - 1]).toBe("printerMapping");
  });

  it("derives category severity and filters", () => {
    const stock = d.categories[0];
    expect(categorySeverity(stock)).toBe("critical");
    expect(filterBySeverity(stock, "warning")).toHaveLength(1);
    expect(filterBySeverity(stock, "all")).toHaveLength(2);
    expect(categorySeverity(d.categories[6])).toBeNull();
  });

  it("formats quantities in Turkish", () => {
    expect(formatQty(45000)).toBe("45.000");
    expect(formatQty(12.5)).toBe("12,5");
  });

  it("totals and result parsing", () => {
    expect(totalIssues(d)).toBe(9);
    expect(toSeverity("Critical")).toBe("critical");
    expect(normalizeResult('{"ok":true,"message":"LP serbest bırakıldı."}')).toEqual({ ok: true, message: "LP serbest bırakıldı." });
    expect(normalizeResult("x")).toEqual({ ok: false, message: "" });
  });
});
