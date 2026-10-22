// Saf (React'tan bağımsız) düzenleyici durumu: sırala, gizle, yeniden adlandır,
// zorunlu okutma, geri al / yinele. Vitest ile test edilir.
import type { CatalogItem, Layout, LayoutHeader, LayoutLine, ScanFlag } from "./types";

export interface EditorState {
  layout: Layout;
  past: Layout[];
  future: Layout[];
  /** Son kaydedilen/yüklenen yerleşimin normalize JSON'u (kirli mi kontrolü). */
  baseline: string;
}

export type EditorAction =
  | { type: "load"; layout: Layout }
  | { type: "move"; screen: string; key: string; targetKey: string; place?: "before" | "after" }
  | { type: "step"; screen: string; key: string; delta: -1 | 1 }
  | { type: "toggle"; screen: string; key: string }
  | { type: "label"; screen: string; key: string; value: string }
  | { type: "note"; screen: string; key: string; value: string }
  | { type: "flag"; screen: string; key: string; flag: ScanFlag; value: boolean }
  | { type: "resetItem"; screen: string; key: string; defaults: CatalogItem }
  | { type: "header"; patch: Partial<LayoutHeader> }
  | { type: "undo" }
  | { type: "redo" };

const HISTORY_LIMIT = 100;

export function normalize(layout: Layout): string {
  const lines = [...layout.lines]
    .map((l) => ({ ...l, label: l.label.trim(), note: l.note.trim() }))
    .sort((a, b) => (a.screen + "|" + a.key).localeCompare(b.screen + "|" + b.key));
  return JSON.stringify({
    code: layout.code,
    description: layout.description,
    appliesTo: layout.appliesTo,
    appliesToCode: layout.appliesTo === "all" ? "" : layout.appliesToCode,
    active: layout.active,
    lines,
  });
}

export function initEditor(layout: Layout): EditorState {
  return { layout, past: [], future: [], baseline: normalize(layout) };
}

export function isDirty(state: EditorState): boolean {
  return normalize(state.layout) !== state.baseline;
}

/** Bir öğenin "kardeşleri": aynı ekran ve (ana menüde) aynı kategori. */
export function siblingsOf(lines: LayoutLine[], catalog: CatalogItem[], screen: string, key: string): LayoutLine[] {
  const group = catalog.find((c) => c.screen === screen && c.key === key)?.group ?? "";
  const inGroup = new Set(catalog.filter((c) => c.screen === screen && c.group === group).map((c) => c.key));
  return lines.filter((l) => l.screen === screen && inGroup.has(l.key)).sort(bySort);
}

export function bySort(a: LayoutLine, b: LayoutLine): number {
  return a.sort - b.sort || a.key.localeCompare(b.key);
}

/**
 * Bir öğeyi kardeşleri içinde yeni konuma taşır. Grubun mevcut sıra numaraları
 * (küçükten büyüğe) yeni diziye yeniden dağıtılır; böylece kategoriler arası
 * sıra bantları karışmaz ve terminaldeki kategori düzeni korunur.
 */
export function reorder(lines: LayoutLine[], catalog: CatalogItem[], screen: string, key: string, targetKey: string, place: "before" | "after" = "before"): LayoutLine[] {
  if (key === targetKey) return lines;
  const siblings = siblingsOf(lines, catalog, screen, key);
  if (!siblings.some((s) => s.key === targetKey)) return lines;
  const slots = siblings.map((s) => s.sort).sort((a, b) => a - b);
  const moving = siblings.find((s) => s.key === key);
  if (!moving) return lines;
  const rest = siblings.filter((s) => s.key !== key);
  let idx = rest.findIndex((s) => s.key === targetKey);
  if (place === "after") idx += 1;
  rest.splice(idx, 0, moving);
  return applySlots(lines, screen, rest, uniqueSlots(slots));
}

export function step(lines: LayoutLine[], catalog: CatalogItem[], screen: string, key: string, delta: -1 | 1): LayoutLine[] {
  const siblings = siblingsOf(lines, catalog, screen, key);
  const i = siblings.findIndex((s) => s.key === key);
  const j = i + delta;
  if (i < 0 || j < 0 || j >= siblings.length) return lines;
  return reorder(lines, catalog, screen, key, siblings[j].key, delta > 0 ? "after" : "before");
}

function uniqueSlots(slots: number[]): number[] {
  // Eşit sıra numaraları varsa (elle girilmiş veri) 10'ar artan yeni bant üret.
  const out: number[] = [];
  slots.forEach((s, i) => out.push(i === 0 ? s : Math.max(s, out[i - 1] + 1)));
  return out;
}

function applySlots(lines: LayoutLine[], screen: string, ordered: LayoutLine[], slots: number[]): LayoutLine[] {
  const next = new Map<string, number>();
  ordered.forEach((l, i) => next.set(l.key, slots[i]));
  return lines.map((l) => (l.screen === screen && next.has(l.key) ? { ...l, sort: next.get(l.key)! } : l));
}

function patchLine(lines: LayoutLine[], screen: string, key: string, patch: Partial<LayoutLine>): LayoutLine[] {
  return lines.map((l) => (l.screen === screen && l.key === key ? { ...l, ...patch } : l));
}

function withLines(layout: Layout, lines: LayoutLine[]): Layout {
  return lines === layout.lines ? layout : { ...layout, lines };
}

export function editorReducer(catalog: CatalogItem[]) {
  return function reduce(state: EditorState, action: EditorAction): EditorState {
    const commit = (layout: Layout): EditorState => {
      if (layout === state.layout) return state;
      return { ...state, layout, past: [...state.past, state.layout].slice(-HISTORY_LIMIT), future: [] };
    };
    const lines = state.layout.lines;
    switch (action.type) {
      case "load":
        return initEditor(action.layout);
      case "move":
        return commit(withLines(state.layout, reorder(lines, catalog, action.screen, action.key, action.targetKey, action.place)));
      case "step":
        return commit(withLines(state.layout, step(lines, catalog, action.screen, action.key, action.delta)));
      case "toggle": {
        const item = catalog.find((c) => c.screen === action.screen && c.key === action.key);
        const line = lines.find((l) => l.screen === action.screen && l.key === action.key);
        if (!line || (item?.locked && line.visible)) return state;
        return commit(withLines(state.layout, patchLine(lines, action.screen, action.key, { visible: !line.visible })));
      }
      case "label":
        return commit(withLines(state.layout, patchLine(lines, action.screen, action.key, { label: action.value.slice(0, 50) })));
      case "note":
        return commit(withLines(state.layout, patchLine(lines, action.screen, action.key, { note: action.value.slice(0, 250) })));
      case "flag": {
        const field = action.flag === "LP" ? "requireLp" : action.flag === "LOT" ? "requireLot" : "requireBin";
        return commit(withLines(state.layout, patchLine(lines, action.screen, action.key, { [field]: action.value })));
      }
      case "resetItem":
        return commit(withLines(state.layout, patchLine(lines, action.screen, action.key, {
          visible: true, label: "", note: "", requireLp: false, requireLot: false, requireBin: false, sort: action.defaults.sort,
        })));
      case "header":
        return commit({ ...state.layout, ...action.patch });
      case "undo": {
        const prev = state.past[state.past.length - 1];
        if (!prev) return state;
        return { ...state, layout: prev, past: state.past.slice(0, -1), future: [state.layout, ...state.future] };
      }
      case "redo": {
        const [next, ...future] = state.future;
        if (!next) return state;
        return { ...state, layout: next, past: [...state.past, state.layout], future };
      }
    }
  };
}

/** Telefon önizlemesi için bir ekranın öğeleri, katalog sırası + yerleşim sırası. */
export function screenItems(layout: Layout, catalog: CatalogItem[], screen: string, includeHidden: boolean) {
  const byKey = new Map(layout.lines.filter((l) => l.screen === screen).map((l) => [l.key, l]));
  return catalog
    .filter((c) => c.screen === screen)
    .map((c) => ({ item: c, line: byKey.get(c.key) ?? defaultLine(c) }))
    .filter((x) => includeHidden || x.line.visible)
    .sort((a, b) => a.line.sort - b.line.sort || a.item.key.localeCompare(b.item.key));
}

export function defaultLine(c: CatalogItem): LayoutLine {
  return { screen: c.screen, key: c.key, visible: true, sort: c.sort, label: "", note: "", requireLp: false, requireLot: false, requireBin: false };
}

/** Kategoriler, terminaldeki sabit sırayla (katalogdaki ilk görünüş). */
export function groupsOf(catalog: CatalogItem[], screen: string): string[] {
  const out: string[] = [];
  catalog.filter((c) => c.screen === screen).forEach((c) => { if (!out.includes(c.group)) out.push(c.group); });
  return out;
}

export function displayLabel(item: CatalogItem, line: LayoutLine): string {
  return line.label.trim() || item.label;
}

export function changedCount(layout: Layout, catalog: CatalogItem[]): number {
  return layout.lines.filter((l) => {
    const c = catalog.find((x) => x.screen === l.screen && x.key === l.key);
    if (!c) return false;
    return !l.visible || l.label.trim() !== "" || l.note.trim() !== "" || l.requireLp || l.requireLot || l.requireBin || l.sort !== c.sort;
  }).length;
}
