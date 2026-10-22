import { describe, expect, it } from "vitest";
import {
  actionMeta,
  compareBars,
  documentLanes,
  formatDate,
  formatQty,
  groupStateMeta,
  groupTimelineByDay,
  ledgerBadges,
  normalizeTrace,
  sortInsights,
  sourceShares,
  timelineTitle,
  truncatedSections,
  cleanSearch,
} from "./model";
import { sampleLotTrace, sampleLpTrace } from "./sample";

describe("normalizeTrace", () => {
  it("parses the JSON text sent by AL and fills missing arrays", () => {
    const trace = normalizeTrace('{"mode":"lp","query":"LP001740","lp":{"no":"LP001740"}}');
    expect(trace.mode).toBe("lp");
    expect(trace.lines).toEqual([]);
    expect(trace.timeline).toEqual([]);
    expect(trace.lp?.children).toEqual([]);
  });

  it("turns unreadable text into an error state and unknown modes into empty", () => {
    expect(normalizeTrace("{oops").mode).toBe("error");
    expect(normalizeTrace({ mode: "weird" }).mode).toBe("empty");
    expect(normalizeTrace(null).mode).toBe("empty");
  });

  it("keeps the round trip of the sample payload", () => {
    const trace = normalizeTrace(JSON.stringify(sampleLotTrace));
    expect(trace.groups[0].lps).toHaveLength(90);
    expect(trace.totals?.lpQty).toBe(90000);
  });
});

describe("formatting", () => {
  it("uses Turkish number and date formats", () => {
    expect(formatQty(45000)).toBe("45.000");
    expect(formatQty(2.5)).toBe("2,5");
    expect(formatQty(undefined)).toBe("–");
    expect(formatDate("2026-10-21")).toBe("21.10.2026");
    expect(cleanSearch("  lp001737 ")).toBe("LP001737");
    expect(cleanSearch("ab.01740   a102452")).toBe("AB.01740 A102452");
  });
});

describe("timeline", () => {
  it("keeps the AL order and groups by day", () => {
    const days = groupTimelineByDay(sampleLpTrace.timeline);
    expect(days).toHaveLength(1);
    expect(days[0].entries.map((entry) => entry.action)).toEqual(["built", "itemAdded", "transferIn", "assigned"]);
  });

  it("labels actions in Turkish and marks undo removals", () => {
    expect(actionMeta("unbuilt").label).toBe("Bozuldu");
    expect(actionMeta("somethingNew", "Fallback").label).toBe("Fallback");
    const undo = timelineTitle({ ...sampleLpTrace.timeline[0], action: "itemRemoved", undo: true });
    expect(undo.tone).toBe("bad");
    expect(undo.icon).toBe("undo");
    const emptied = timelineTitle({ ...sampleLpTrace.timeline[0], action: "itemRemoved", relatedDocument: "EMPTIED" });
    expect(emptied.label).toContain("Boşaldı");
  });
});

describe("sources and documents", () => {
  it("computes the share of each source group (2812 + 188)", () => {
    const shares = sourceShares(sampleLpTrace.sourceGroups);
    expect(shares.map((share) => Math.round(share.pct))).toEqual([94, 6]);
    expect(shares[1].colorIndex).toBe(1);
  });

  it("puts documents into process lanes in stage order", () => {
    const lanes = documentLanes(sampleLpTrace.documents);
    expect(lanes.map((lane) => lane.id)).toEqual(["receipt", "putaway"]);
    expect(lanes[0].documents.map((doc) => doc.no)).toEqual(["SAS000512", "RE001191", "KAB000845", "109304"]);
    expect(lanes[1].documents[0].state).toBe("missing");
  });

  it("orders insights error → warning → info", () => {
    expect(sortInsights(sampleLotTrace.insights).map((insight) => insight.level)).toEqual(["error", "warning"]);
    expect(sortInsights(sampleLpTrace.insights)[0].code).toBe("orphanAssignment");
  });
});

describe("ledger and tree helpers", () => {
  it("badges an undone receipt entry and an LP excess", () => {
    const entry = { ...sampleLpTrace.itemLedger[0], undoneByEntryNo: 15412, remainingQty: 0, open: false };
    const labels = ledgerBadges(entry).map((badge) => badge.label);
    expect(labels).toContain("Geri alındı → 15412");
    expect(labels).not.toContain("LP > kalan");
    const excess = ledgerBadges({ ...sampleLpTrace.itemLedger[0], remainingQty: 100, linkedLpQty: 300 });
    expect(excess.map((badge) => badge.label)).toContain("LP > kalan");
  });

  it("describes group states and comparison bars", () => {
    expect(groupStateMeta("excess", -45000)).toEqual({ label: "LP fazlası 45.000", tone: "bad" });
    expect(groupStateMeta("partial", 500).tone).toBe("warn");
    expect(groupStateMeta("ok", 0).tone).toBe("good");
    expect(compareBars(90000, 45000)).toEqual({ lp: 100, bc: 50 });
    expect(compareBars(0, 0)).toEqual({ lp: 0, bc: 0 });
  });

  it("names truncated sections", () => {
    expect(truncatedSections({ timeline: true, lps: false })).toEqual(["zaman çizelgesi (en yeni 500 kayıt)"]);
  });
});
