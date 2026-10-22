// LP İzlenebilirlik — saf (DOM'suz) yardımcılar. Bileşenler yalnız bunları çağırır;
// vitest bu dosyayı doğrudan test eder.
import type {
  DocState,
  GroupEntry,
  GroupState,
  Insight,
  InsightLevel,
  LedgerEntry,
  SourceGroup,
  TimelineEntry,
  TraceDocument,
  TraceMode,
  TracePayload,
} from "./types";

export type Tone = "neutral" | "accent" | "good" | "warn" | "bad" | "muted";

export type IconName =
  | "box"
  | "plus"
  | "minus"
  | "link"
  | "unlink"
  | "arrow"
  | "in"
  | "out"
  | "layers"
  | "split"
  | "broken"
  | "check"
  | "doc"
  | "undo"
  | "dot";

const MODES: TraceMode[] = ["empty", "lp", "lot", "item", "document", "notFound", "error"];

function arr<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

/** BC'den gelen metni ya da nesneyi güvenli bir TracePayload'a çevirir. */
export function normalizeTrace(raw: unknown): TracePayload {
  let data: Record<string, unknown> = {};
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (parsed && typeof parsed === "object") data = parsed as Record<string, unknown>;
    } catch {
      return { ...emptyTrace(), mode: "error", message: "BC'den gelen veri okunamadı." };
    }
  } else if (raw && typeof raw === "object") {
    data = raw as Record<string, unknown>;
  }
  const mode = MODES.includes(data.mode as TraceMode) ? (data.mode as TraceMode) : "empty";
  const lp = data.lp && typeof data.lp === "object" ? (data.lp as TracePayload["lp"]) : undefined;
  if (lp) {
    lp.children = arr(lp.children);
  }
  return {
    version: Number(data.version ?? 1),
    mode,
    query: String(data.query ?? ""),
    generatedAt: String(data.generatedAt ?? ""),
    message: data.message === undefined ? undefined : String(data.message),
    title: data.title === undefined ? undefined : String(data.title),
    lp,
    lines: arr(data.lines),
    sourceGroups: arr(data.sourceGroups),
    mixedSources: Boolean(data.mixedSources),
    timeline: arr(data.timeline),
    itemLedger: arr(data.itemLedger),
    warehouseEntries: arr(data.warehouseEntries),
    groups: arr<TracePayload["groups"][number]>(data.groups).map((group) => ({
      ...group,
      lps: arr(group.lps),
      entries: arr(group.entries),
    })),
    historicLps: arr(data.historicLps),
    totals: (data.totals as TracePayload["totals"]) ?? undefined,
    documents: arr(data.documents),
    insights: arr(data.insights),
    truncated: (data.truncated && typeof data.truncated === "object" ? data.truncated : {}) as Record<string, boolean>,
  };
}

export function emptyTrace(): TracePayload {
  return {
    version: 1,
    mode: "empty",
    query: "",
    generatedAt: "",
    lines: [],
    sourceGroups: [],
    mixedSources: false,
    timeline: [],
    itemLedger: [],
    warehouseEntries: [],
    groups: [],
    historicLps: [],
    documents: [],
    insights: [],
    truncated: {},
  };
}

const qtyFormat = new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 5 });

export function formatQty(value: number | undefined | null): string {
  if (value === undefined || value === null || Number.isNaN(value)) return "–";
  return qtyFormat.format(value);
}

export function formatSignedQty(value: number): string {
  if (value > 0) return `+${formatQty(value)}`;
  return formatQty(value);
}

const MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];

function parseDate(iso: string): Date | null {
  if (!iso) return null;
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? null : date;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "2026-10-21T13:44:47Z" → "21.10.2026 16:44" (tarayıcı saat dilimiyle). */
export function formatDateTime(iso: string): string {
  const date = parseDate(iso);
  if (!date) return "";
  return `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function formatTime(iso: string): string {
  const date = parseDate(iso);
  return date ? `${pad(date.getHours())}:${pad(date.getMinutes())}` : "";
}

/** "2026-10-21" ya da ISO tarih-saat → "21.10.2026". */
export function formatDate(iso: string): string {
  if (!iso) return "";
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (m) return `${m[3]}.${m[2]}.${m[1]}`;
  const date = parseDate(iso);
  return date ? `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()}` : "";
}

export function dayLabel(iso: string): string {
  const date = parseDate(iso);
  if (!date) return "Tarihsiz";
  return `${date.getDate()} ${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

export interface ActionMeta {
  label: string;
  icon: IconName;
  tone: Tone;
}

const ACTIONS: Record<string, ActionMeta> = {
  built: { label: "Oluşturuldu", icon: "box", tone: "accent" },
  moved: { label: "Taşındı", icon: "arrow", tone: "neutral" },
  assigned: { label: "Belgeye atandı", icon: "link", tone: "accent" },
  released: { label: "Serbest bırakıldı", icon: "unlink", tone: "neutral" },
  transferIn: { label: "Aktarım geldi", icon: "in", tone: "good" },
  transferOut: { label: "Aktarım gitti", icon: "out", tone: "warn" },
  nestIn: { label: "Üst LP'ye kondu", icon: "layers", tone: "neutral" },
  unnest: { label: "Üst LP'den çıktı", icon: "split", tone: "neutral" },
  unbuilt: { label: "Bozuldu", icon: "broken", tone: "bad" },
  itemAdded: { label: "Ürün eklendi", icon: "plus", tone: "good" },
  itemRemoved: { label: "Ürün çıkarıldı", icon: "minus", tone: "warn" },
  sourceLinked: { label: "Kaynak giriş bağlandı", icon: "link", tone: "neutral" },
};

export function actionMeta(action: string, fallbackCaption = ""): ActionMeta {
  return ACTIONS[action] ?? { label: fallbackCaption || action || "Hareket", icon: "dot", tone: "neutral" };
}

/** Zaman çizelgesi satırının bağlama göre etiketi (ör. "BIN-MOVE" ⇒ "Raf değişti"). */
export function timelineTitle(entry: TimelineEntry): ActionMeta {
  const base = actionMeta(entry.action, entry.actionCaption);
  if (entry.undo) return { label: "Geri alınan mal kabul ile boşaltıldı", icon: "undo", tone: "bad" };
  if (entry.action === "itemRemoved" && entry.relatedDocument === "EMPTIED") {
    return { label: "Boşaldı · kullanıldı", icon: "check", tone: "muted" };
  }
  if (entry.action === "transferOut" && (entry.relatedDocument === "BIN-MOVE" || entry.relatedDocument === "BIN-ASSIGN")) {
    return { label: "Raf değişti", icon: "arrow", tone: "neutral" };
  }
  return base;
}

export interface StatusMeta {
  label: string;
  tone: Tone;
}

const STATUSES: Record<string, StatusMeta> = {
  open: { label: "Açık", tone: "neutral" },
  built: { label: "Oluşturuldu", tone: "good" },
  assigned: { label: "Atandı", tone: "accent" },
  used: { label: "Kullanıldı", tone: "muted" },
  unbuilt: { label: "Bozuldu", tone: "bad" },
  missing: { label: "Kayıt yok", tone: "bad" },
};

export function statusMeta(status: string): StatusMeta {
  return STATUSES[status] ?? { label: status || "?", tone: "neutral" };
}

export function docStateMeta(state: DocState | string): StatusMeta {
  switch (state) {
    case "open":
      return { label: "Açık", tone: "accent" };
    case "posted":
      return { label: "Kaydedildi", tone: "good" };
    case "missing":
      return { label: "Bulunamadı", tone: "bad" };
    default:
      return { label: "", tone: "muted" };
  }
}

export function insightOrder(level: InsightLevel): number {
  return level === "error" ? 0 : level === "warning" ? 1 : 2;
}

export function sortInsights(insights: Insight[]): Insight[] {
  return [...insights].sort((a, b) => insightOrder(a.level) - insightOrder(b.level));
}

export interface TimelineDay {
  day: string;
  entries: TimelineEntry[];
}

/** Kronolojik (AL sırası korunur) satırları güne göre gruplar. */
export function groupTimelineByDay(timeline: TimelineEntry[]): TimelineDay[] {
  const days: TimelineDay[] = [];
  for (const entry of timeline) {
    const day = dayLabel(entry.at);
    const last = days[days.length - 1];
    if (last && last.day === day) last.entries.push(entry);
    else days.push({ day, entries: [entry] });
  }
  return days;
}

export interface SourceShare extends SourceGroup {
  pct: number;
  colorIndex: number;
}

/** Kaynak gruplarının LP içindeki payı (yığılmış çubuk için). */
export function sourceShares(groups: SourceGroup[]): SourceShare[] {
  const total = groups.reduce((sum, group) => sum + Math.max(group.qty, 0), 0);
  return groups.map((group, index) => ({
    ...group,
    pct: total > 0 ? (Math.max(group.qty, 0) / total) * 100 : 0,
    colorIndex: index % 6,
  }));
}

export function sourceColorIndex(groups: SourceGroup[], groupKey: string): number {
  const index = groups.findIndex((group) => group.key === groupKey);
  return index < 0 ? 0 : index % 6;
}

export interface DocumentLane {
  id: string;
  label: string;
  documents: TraceDocument[];
}

const LANES: Array<{ id: string; label: string; kinds: string[] }> = [
  { id: "receipt", label: "Mal kabul", kinds: ["purchaseOrder", "whseReceipt", "postedWhseReceipt", "purchRcpt"] },
  { id: "putaway", label: "Yerine koyma", kinds: ["whsePutaway", "regPutaway"] },
  { id: "movement", label: "Hareket", kinds: ["whseMovement", "regMovement"] },
  { id: "production", label: "Üretim / montaj", kinds: ["prodOrder", "assemblyOrder", "postedAssembly"] },
  { id: "pick", label: "Toplama", kinds: ["whsePick", "regPick"] },
  { id: "shipment", label: "Sevkiyat", kinds: ["whseShipment", "postedWhseShipment", "salesShipment"] },
];

/** Belgeleri süreç şeritlerine böler (AL "stage" sırasını korur). */
export function documentLanes(documents: TraceDocument[]): DocumentLane[] {
  const lanes: DocumentLane[] = LANES.map((lane) => ({ id: lane.id, label: lane.label, documents: [] }));
  const other: DocumentLane = { id: "other", label: "Diğer", documents: [] };
  const sorted = [...documents].sort((a, b) => a.stage - b.stage);
  for (const doc of sorted) {
    const laneIndex = LANES.findIndex((lane) => lane.kinds.includes(doc.kind));
    (laneIndex < 0 ? other : lanes[laneIndex]).documents.push(doc);
  }
  return [...lanes, other].filter((lane) => lane.documents.length > 0);
}

export interface Badge {
  label: string;
  tone: Tone;
}

const MATCHED: Record<string, Badge> = {
  sourceLine: { label: "LP satırının kaynağı", tone: "accent" },
  lpNo: { label: "LP No. damgalı", tone: "neutral" },
  lpNos: { label: "LP listesinde", tone: "neutral" },
  undo: { label: "Geri alma", tone: "bad" },
  undone: { label: "Geri alınan giriş", tone: "warn" },
};

export function ledgerBadges(entry: LedgerEntry): Badge[] {
  const badges: Badge[] = [];
  if (MATCHED[entry.matchedBy]) badges.push(MATCHED[entry.matchedBy]);
  if (entry.correction) badges.push({ label: "Düzeltme", tone: "bad" });
  if (entry.undoneByEntryNo) badges.push({ label: `Geri alındı → ${entry.undoneByEntryNo}`, tone: "bad" });
  if (entry.positive && entry.linkedLpQty > entry.remainingQty && !entry.undoneByEntryNo) {
    badges.push({ label: "LP > kalan", tone: "warn" });
  }
  if (entry.open) badges.push({ label: "Açık", tone: "good" });
  return badges;
}

export function groupEntryTone(entry: GroupEntry): Tone {
  if (!entry.positive) return "muted";
  if (entry.undoneByEntryNo && entry.lpQty > 0) return "bad";
  if (entry.diff < 0) return "warn";
  return "neutral";
}

export function groupStateMeta(state: GroupState, diff: number): StatusMeta {
  if (state === "excess") return { label: `LP fazlası ${formatQty(-diff)}`, tone: "bad" };
  if (state === "partial") return { label: `LP'siz stok ${formatQty(diff)}`, tone: "warn" };
  return { label: "LP = BC stoğu", tone: "good" };
}

/** LP toplamı ve BC kalan miktarının karşılaştırma çubuğu oranları (0-100). */
export function compareBars(lpQty: number, bcQty: number): { lp: number; bc: number } {
  const max = Math.max(lpQty, bcQty, 0);
  if (max === 0) return { lp: 0, bc: 0 };
  return { lp: (Math.max(lpQty, 0) / max) * 100, bc: (Math.max(bcQty, 0) / max) * 100 };
}

export function modeTitle(trace: TracePayload): string {
  switch (trace.mode) {
    case "lp":
      return trace.lp ? `LP ${trace.lp.no}` : "LP";
    case "lot":
    case "item":
    case "document":
      return trace.title ?? trace.query;
    default:
      return "";
  }
}

export function modeLabel(mode: TraceMode): string {
  switch (mode) {
    case "lp":
      return "LP";
    case "lot":
      return "Lot";
    case "item":
      return "Madde";
    case "document":
      return "Belge";
    default:
      return "";
  }
}

export const TRUNCATED_LABELS: Record<string, string> = {
  timeline: "zaman çizelgesi (en yeni 500 kayıt)",
  itemLedger: "madde girişleri",
  warehouseEntries: "ambar girişleri",
  documents: "belgeler",
  children: "alt LP'ler",
  lpLines: "LP satırları",
  groups: "lot grupları",
  lps: "LP listesi",
  entries: "madde girişleri",
  historicLps: "geçmiş LP'ler",
};

export function truncatedSections(truncated: Record<string, boolean>): string[] {
  return Object.keys(truncated)
    .filter((key) => truncated[key])
    .map((key) => TRUNCATED_LABELS[key] ?? key);
}

/** Basit arama metni temizliği (AL de aynısını yapar). */
export function cleanSearch(text: string): string {
  return text.trim().replace(/\s+/g, " ").toUpperCase();
}
