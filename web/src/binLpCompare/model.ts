import type {
  CompareData,
  CompareFilter,
  CompareReason,
  CompareRow,
  CompareStatus,
  CompareSummary,
  LpLine,
} from "./types";

// ---------------------------------------------------------------- meta

export type Tone = "green" | "red" | "crimson" | "orange" | "amber" | "purple";

export const STATUS_META: Record<CompareStatus, { label: string; short: string; tone: Tone; hint: string }> = {
  lpOver: {
    label: "LP fazla",
    short: "LP > stok",
    tone: "red",
    hint: "LP'lerde gözdeki BC stoğundan fazla miktar var (hayalet LP miktarı).",
  },
  lpNoStock: {
    label: "Stok yok, LP var",
    short: "Stok 0",
    tone: "crimson",
    hint: "Gözde BC stoğu yok ama aktif LP miktar taşıyor.",
  },
  stockOver: {
    label: "Stok fazla",
    short: "Stok > LP",
    tone: "orange",
    hint: "Gözdeki stoğun bir kısmı hiçbir LP'de değil.",
  },
  stockNoLp: {
    label: "LP'siz stok",
    short: "LP yok",
    tone: "amber",
    hint: "Gözde stok var, hiçbir aktif LP'de değil.",
  },
  negativeStock: {
    label: "Eksi stok",
    short: "Stok < 0",
    tone: "purple",
    hint: "BC göz stoğu eksi; depo girişlerini kontrol edin.",
  },
  equal: {
    label: "Eşit",
    short: "Eşit",
    tone: "green",
    hint: "BC stoğu ile LP miktarı aynı.",
  },
};

export const STATUS_ORDER: CompareStatus[] = ["lpOver", "lpNoStock", "stockOver", "stockNoLp", "negativeStock", "equal"];

export const REASON_META: Record<Exclude<CompareReason, "none">, { label: string; advice: string }> = {
  undoneReceipt: {
    label: "Geri alınan mal kabul",
    advice:
      "Mal kabul BC'de geri alınmış ama LP'ler dolu kalmış. Boşaltma yalnız geri alınan miktar kadar yapılır; gerçek stoğu olan LP'ye dokunulmaz.",
  },
  orphanAssignment: {
    label: "Yetim atama",
    advice:
      "LP, artık bulunmayan bir belgeye atanmış görünüyor. Serbest bırakınca LP Oluşturuldu durumuna döner; stok ve göz değişmez.",
  },
  lotMismatch: {
    label: "Lot uyuşmazlığı",
    advice:
      "Aynı gözde aynı madde farklı lotlarla duruyor. LP lotu yanlış girilmiş olabilir: LP kartında lotu kontrol edin ya da gözü sayın.",
  },
  otherBin: {
    label: "Başka gözde",
    advice:
      "Aynı madde/lot başka bir gözde eşleşmeyen miktarla duruyor. LP fiziksel olarak taşınmış ama sistemde taşınmamış olabilir: LP'yi doğru göze taşıyın.",
  },
};

export function statusAdvice(status: CompareStatus): string {
  switch (status) {
    case "lpOver":
    case "lpNoStock":
      return "LP içeriğini fiziksel olarak doğrulayın. LP'de fazla görünen miktar gözde yoksa LP'den düşün; LP başka göze taşındıysa taşımayı sisteme işleyin.";
    case "stockOver":
    case "stockNoLp":
      return "Gözde LP'siz stok var. Ürünü bir LP'ye koyun (LP oluştur) ya da göz içeriğini sayarak BC stoğunu düzeltin.";
    case "negativeStock":
      return "BC göz stoğu eksi. Göz içeriği ve depo girişlerini kontrol edin; çoğunlukla eksik bir yerleştirme veya hatalı düzeltme kaydıdır.";
    default:
      return "Stok ve LP miktarı eşit; işlem gerekmiyor.";
  }
}

// ---------------------------------------------------------------- numbers

const qtyFormatter = new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 5 });

export function formatQty(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0";
  return qtyFormatter.format(Math.abs(n) < 0.000005 ? 0 : n);
}

/** İşaretli fark: +45.000 / −20 / 0 */
export function formatSigned(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n) || Math.abs(n) < 0.000005) return "0";
  return (n > 0 ? "+" : "−") + qtyFormatter.format(Math.abs(n));
}

export function formatDateTime(iso: string | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString("tr-TR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function formatDate(iso: string | undefined): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("tr-TR");
}

// ---------------------------------------------------------------- lists

/** "LP1, LP2" ya da "1,2" → ["LP1","LP2"] (boşlar ve tekrarlar atılır). */
export function splitList(value: string | undefined | null): string[] {
  if (!value) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const part of value.split(",")) {
    const v = part.trim();
    if (v && !seen.has(v)) {
      seen.add(v);
      out.push(v);
    }
  }
  return out;
}

export type LpGroup = {
  lpNo: string;
  lpStatus: string;
  assignedDocType: string;
  assignedDocNo: string;
  pendingReceiptNo: string;
  parentLpNo: string;
  orphan: boolean;
  builtAt: string;
  totalBase: number;
  lines: LpLine[];
};

/** Satırın LP satırlarını LP bazında gruplar (ilk görülme sırası korunur). */
export function groupLinesByLp(lines: LpLine[]): LpGroup[] {
  const map = new Map<string, LpGroup>();
  for (const line of lines) {
    let group = map.get(line.lpNo);
    if (!group) {
      group = {
        lpNo: line.lpNo,
        lpStatus: line.lpStatus,
        assignedDocType: line.assignedDocType ?? "",
        assignedDocNo: line.assignedDocNo ?? "",
        pendingReceiptNo: line.pendingReceiptNo ?? "",
        parentLpNo: line.parentLpNo ?? "",
        orphan: Boolean(line.orphan),
        builtAt: line.builtAt ?? "",
        totalBase: 0,
        lines: [],
      };
      map.set(line.lpNo, group);
    }
    group.totalBase = round5(group.totalBase + Number(line.qtyBase ?? 0));
    group.lines.push(line);
  }
  return [...map.values()];
}

function round5(n: number): number {
  return Math.round(n * 100000) / 100000;
}

// ---------------------------------------------------------------- filters

export type StatusFilter = CompareStatus | "all" | "action";

/** Ekranda gösterilecek satırlar: durum çipi + hızlı arama. */
export function filterRows(rows: CompareRow[], status: StatusFilter, search: string): CompareRow[] {
  const q = fold(search.trim());
  return rows.filter((row) => {
    if (status === "action") {
      if (row.reason === "none") return false;
    } else if (status !== "all" && row.status !== status) {
      return false;
    }
    if (!q) return true;
    const haystack = [row.bin, row.item, row.description, row.lot, row.variant, ...splitList(lpNosOf(row))]
      .join(" ");
    return fold(haystack).includes(q);
  });
}

export function lpNosOf(row: CompareRow): string {
  return groupLinesByLp(row.lines).map((g) => g.lpNo).join(", ");
}

/** Arama için büyük/küçük harf ve Türkçe i/ı/İ farkını yok sayan biçim. */
export function fold(value: string): string {
  return value.toUpperCase().replace(/İ/g, "I");
}

/** BC'ye giden filtre: boşluklar kırpılır, kodlar BC gibi (kültürden bağımsız) büyük harfe çevrilir. */
export function buildFilterPayload(filter: CompareFilter): CompareFilter {
  const up = (v: string) => v.trim().toUpperCase();
  return {
    location: up(filter.location),
    zone: up(filter.zone),
    binFrom: up(filter.binFrom),
    binTo: up(filter.binTo),
    item: up(filter.item),
    onlyDiff: Boolean(filter.onlyDiff),
  };
}

// ---------------------------------------------------------------- summary chips

export type Chip = { key: StatusFilter; label: string; tone: Tone | "neutral" | "blue"; count: number; qty?: number };

export function summaryChips(summary: CompareSummary): Chip[] {
  return [
    { key: "lpOver", label: STATUS_META.lpOver.label, tone: "red", count: summary.lpOver },
    { key: "lpNoStock", label: STATUS_META.lpNoStock.label, tone: "crimson", count: summary.lpNoStock },
    { key: "stockOver", label: STATUS_META.stockOver.label, tone: "orange", count: summary.stockOver },
    { key: "stockNoLp", label: STATUS_META.stockNoLp.label, tone: "amber", count: summary.stockNoLp },
    { key: "negativeStock", label: STATUS_META.negativeStock.label, tone: "purple", count: summary.negativeStock },
    { key: "equal", label: STATUS_META.equal.label, tone: "green", count: summary.equal },
    { key: "action", label: "Önerilen düzeltme", tone: "blue", count: summary.reasonRows },
  ];
}

/** Ekrandaki satırlardan özet (örnek veri ve yerel önizleme için; BC kendi özetini gönderir). */
export function summarize(rows: CompareRow[]): CompareSummary {
  const s: CompareSummary = {
    rows: rows.length, equal: 0, lpOver: 0, lpNoStock: 0, stockOver: 0, stockNoLp: 0, negativeStock: 0,
    stockTotal: 0, lpTotal: 0, lpSurplusQty: 0, stockSurplusQty: 0, bins: 0, lps: 0, orphanLps: 0,
    undoneReceiptRows: 0, reasonRows: 0,
  };
  const bins = new Set<string>();
  const lps = new Set<string>();
  const orphans = new Set<string>();
  for (const row of rows) {
    s[row.status] += 1;
    s.stockTotal = round5(s.stockTotal + row.stock);
    s.lpTotal = round5(s.lpTotal + row.lp);
    // Eksi stok satırı ne LP fazlası ne LP'siz stoktur; ayrı sayılır.
    if (row.status !== "negativeStock") {
      if (row.diff > 0) s.lpSurplusQty = round5(s.lpSurplusQty + row.diff);
      else s.stockSurplusQty = round5(s.stockSurplusQty - row.diff);
    }
    bins.add(row.bin);
    row.lines.forEach((l) => lps.add(l.lpNo));
    splitList(row.orphanLpNos).forEach((lp) => orphans.add(lp));
    if (row.reason === "undoneReceipt") s.undoneReceiptRows += 1;
    if (row.reason !== "none") s.reasonRows += 1;
  }
  s.bins = bins.size;
  s.lps = lps.size;
  s.orphanLps = orphans.size;
  return s;
}

// ---------------------------------------------------------------- normalize

const STATUSES = new Set<CompareStatus>(STATUS_ORDER);
const REASONS = new Set<CompareReason>(["none", "undoneReceipt", "orphanAssignment", "lotMismatch", "otherBin"]);

const str = (v: unknown) => (v == null ? "" : String(v));
const num = (v: unknown) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

export function emptySummary(): CompareSummary {
  return summarize([]);
}

/** BC'den gelen JSON'u (metin ya da nesne) güvenli biçimde ekran modeline çevirir. */
export function normalizeData(raw: unknown): CompareData {
  let input: Record<string, unknown> = {};
  if (typeof raw === "string") {
    try {
      input = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      input = {};
    }
  } else if (raw && typeof raw === "object") {
    input = raw as Record<string, unknown>;
  }
  const rows = Array.isArray(input.rows) ? (input.rows as Record<string, unknown>[]).map(normalizeRow) : [];
  const summaryRaw = (input.summary ?? {}) as Record<string, unknown>;
  const base = emptySummary();
  const summary = Object.fromEntries(
    Object.keys(base).map((k) => [k, summaryRaw[k] == null ? base[k as keyof CompareSummary] : num(summaryRaw[k])]),
  ) as CompareSummary;
  const opts = (v: unknown) =>
    Array.isArray(v)
      ? (v as Record<string, unknown>[]).map((o) => ({
          code: str(o.code),
          name: str(o.name),
          ...(o.binMandatory == null ? {} : { binMandatory: Boolean(o.binMandatory) }),
        }))
      : [];
  return {
    location: str(input.location),
    zone: str(input.zone),
    binFrom: str(input.binFrom),
    binTo: str(input.binTo),
    item: str(input.item),
    onlyDiff: input.onlyDiff == null ? true : Boolean(input.onlyDiff),
    generatedAt: str(input.generatedAt),
    traceabilityAvailable: Boolean(input.traceabilityAvailable),
    binMandatory: input.binMandatory == null ? true : Boolean(input.binMandatory),
    needsLocation: Boolean(input.needsLocation) || !str(input.location),
    locations: opts(input.locations),
    zones: opts(input.zones),
    summary,
    rows,
    truncated: Boolean(input.truncated),
    maxRows: input.maxRows == null ? undefined : num(input.maxRows),
  };
}

function normalizeRow(r: Record<string, unknown>): CompareRow {
  const status = str(r.status) as CompareStatus;
  const reason = str(r.reason) as CompareReason;
  return {
    id: num(r.id),
    bin: str(r.bin),
    zone: str(r.zone),
    item: str(r.item),
    description: str(r.description),
    variant: str(r.variant),
    lot: str(r.lot),
    uom: str(r.uom),
    stock: num(r.stock),
    lp: num(r.lp),
    diff: num(r.diff),
    lpCount: num(r.lpCount),
    status: STATUSES.has(status) ? status : "equal",
    reason: REASONS.has(reason) ? reason : "none",
    reasonDetail: str(r.reasonDetail),
    undoEntryNos: str(r.undoEntryNos),
    orphanLpNos: str(r.orphanLpNos),
    repairableLines: num(r.repairableLines),
    lines: Array.isArray(r.lines) ? (r.lines as Record<string, unknown>[]).map(normalizeLine) : [],
  };
}

function normalizeLine(l: Record<string, unknown>): LpLine {
  return {
    lpNo: str(l.lpNo),
    lpStatus: str(l.lpStatus),
    assignedDocType: str(l.assignedDocType),
    assignedDocNo: str(l.assignedDocNo),
    pendingReceiptNo: str(l.pendingReceiptNo),
    parentLpNo: str(l.parentLpNo),
    orphan: Boolean(l.orphan),
    builtAt: str(l.builtAt),
    lineNo: num(l.lineNo),
    qty: num(l.qty),
    uom: str(l.uom),
    qtyBase: num(l.qtyBase),
    uomMissing: Boolean(l.uomMissing),
    lot: str(l.lot),
    serial: str(l.serial),
    expirationDate: str(l.expirationDate),
    sourceEntryNo: num(l.sourceEntryNo),
    sourceDocType: str(l.sourceDocType),
    sourceDocNo: str(l.sourceDocNo),
    sourceDocLineNo: num(l.sourceDocLineNo),
    sourceBin: str(l.sourceBin),
    sourceLpNo: str(l.sourceLpNo),
  };
}
