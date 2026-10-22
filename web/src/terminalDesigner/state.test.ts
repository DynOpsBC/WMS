import { describe, expect, it } from "vitest";
import { sampleCatalog, sampleLayouts } from "./sampleData";
import { changedCount, defaultLine, editorReducer, initEditor, isDirty, reorder, screenItems, step } from "./state";
import type { Layout } from "./types";

const reduce = editorReducer(sampleCatalog);
const fresh = (): Layout => ({
  code: "T", description: "", appliesTo: "all", appliesToCode: "", active: true,
  lines: sampleCatalog.map(defaultLine),
});
const order = (l: Layout, group: string) =>
  screenItems(l, sampleCatalog, "HOME", true).filter((x) => x.item.group === group).map((x) => x.item.key);

describe("terminal designer state", () => {
  it("reorders within a category and keeps the category's sort band", () => {
    const l = fresh();
    const lines = reorder(l.lines, sampleCatalog, "HOME", "SHIPPING", "PICKING", "before");
    const next = { ...l, lines };
    expect(order(next, "Giden")).toEqual(["SHIPPING", "PICKING", "PACKING"]);
    const sorts = lines.filter((x) => ["PICKING", "PACKING", "SHIPPING"].includes(x.key)).map((x) => x.sort).sort((a, b) => a - b);
    expect(sorts).toEqual([30, 40, 50]);
    // Diğer kategoriler etkilenmez.
    expect(order(next, "Gelen")).toEqual(["RECEIVING", "PUTAWAY"]);
  });

  it("ignores moves across categories or screens", () => {
    const l = fresh();
    expect(reorder(l.lines, sampleCatalog, "HOME", "RECEIVING", "PICKING")).toBe(l.lines);
    expect(reorder(l.lines, sampleCatalog, "HOME", "RECEIVING", "LABELS.RANGES")).toBe(l.lines);
  });

  it("steps up/down and stops at the edges", () => {
    const l = fresh();
    const down = step(l.lines, sampleCatalog, "HOME", "PICKING", 1);
    expect(order({ ...l, lines: down }, "Giden")).toEqual(["PACKING", "PICKING", "SHIPPING"]);
    expect(step(l.lines, sampleCatalog, "HOME", "PICKING", -1)).toBe(l.lines);
  });

  it("toggles visibility but never hides a locked item", () => {
    let s = initEditor(fresh());
    s = reduce(s, { type: "toggle", screen: "LABELS", key: "LABELS.RANGES" });
    expect(s.layout.lines.find((x) => x.key === "LABELS.RANGES")?.visible).toBe(false);
    expect(isDirty(s)).toBe(true);
    const locked = reduce(s, { type: "toggle", screen: "HOME", key: "CONNECTION" });
    expect(locked).toBe(s);
    expect(screenItems(s.layout, sampleCatalog, "LABELS", false).map((x) => x.item.key)).not.toContain("LABELS.RANGES");
  });

  it("undo/redo restores state and clears dirtiness", () => {
    let s = initEditor(fresh());
    s = reduce(s, { type: "label", screen: "HOME", key: "RECEIVING", value: "Giriş" });
    s = reduce(s, { type: "flag", screen: "HOME", key: "RECEIVING", flag: "LOT", value: true });
    expect(s.past).toHaveLength(2);
    s = reduce(s, { type: "undo" });
    expect(s.layout.lines.find((x) => x.key === "RECEIVING")?.requireLot).toBe(false);
    s = reduce(s, { type: "undo" });
    expect(isDirty(s)).toBe(false);
    s = reduce(s, { type: "redo" });
    expect(s.layout.lines.find((x) => x.key === "RECEIVING")?.label).toBe("Giriş");
    // Yeni değişiklik yinele geçmişini temizler.
    s = reduce(s, { type: "toggle", screen: "HOME", key: "PICKING" });
    expect(s.future).toHaveLength(0);
  });

  it("reset item returns to catalog defaults", () => {
    let s = initEditor(fresh());
    s = reduce(s, { type: "move", screen: "HOME", key: "SHIPPING", targetKey: "PICKING" });
    s = reduce(s, { type: "toggle", screen: "HOME", key: "SHIPPING" });
    const shipping = sampleCatalog.find((c) => c.key === "SHIPPING")!;
    s = reduce(s, { type: "resetItem", screen: "HOME", key: "SHIPPING", defaults: shipping });
    const line = s.layout.lines.find((x) => x.key === "SHIPPING")!;
    expect(line.visible).toBe(true);
    expect(line.sort).toBe(50);
  });

  it("counts differences from the standard", () => {
    expect(changedCount(fresh(), sampleCatalog)).toBe(0);
    const depocu = sampleLayouts.find((l) => l.code === "DEPOCU")!;
    expect(changedCount(depocu, sampleCatalog)).toBeGreaterThan(5);
  });

  it("header changes are undoable", () => {
    let s = initEditor(fresh());
    s = reduce(s, { type: "header", patch: { appliesTo: "role", appliesToCode: "PICKER" } });
    expect(isDirty(s)).toBe(true);
    s = reduce(s, { type: "undo" });
    expect(s.layout.appliesTo).toBe("all");
  });
});
