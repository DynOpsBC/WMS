// Depo Sağlık Paneli — BC'den (codeunit "DOPSWHS Health Detector".BuildJson)
// gelen yükün tipleri ve güvenli normalizasyonu. Eksik/yanlış tipli alanlar
// panelin çökmesine yol açmaz; bilinmeyen önem "info" sayılır.

export type Severity = "critical" | "warning" | "info";

export type HealthIssue = {
  id: number;
  severity: Severity;
  title: string;
  detail: string;
  location: string;
  bin: string;
  item: string;
  variant: string;
  lot: string;
  lpNo: string;
  docNo: string;
  ref: string;
  qtyBin: number;
  qtyLp: number;
  count: number;
  fixAvailable: boolean;
  canFix: boolean;
  fixCaption: string;
  fixConfirm: string;
  showCaption: string;
  compareAvailable: boolean;
  /** LP İzlenebilirlik açılabilir (LP no ya da madde biliniyor). */
  traceAvailable: boolean;
};

export type HealthCategory = {
  key: string;
  title: string;
  description: string;
  total: number;
  scanLimited: boolean;
  fixable: boolean;
  canFix: boolean;
  fixDeniedReason: string;
  fixAllCaption: string;
  issues: HealthIssue[];
};

export type HealthLocation = { code: string; name: string };

export type HealthData = {
  generatedAt: string;
  locationFilter: string;
  locations: HealthLocation[];
  maxRowsPerCategory: number;
  compareAvailable: boolean;
  summary: Record<Severity, number>;
  categories: HealthCategory[];
};

export type FixResult = { ok: boolean; message: string };

const SEVERITY_RANK: Record<Severity, number> = { critical: 3, warning: 2, info: 1 };

function obj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}
function str(v: unknown): string {
  return v == null ? "" : String(v);
}
function num(v: unknown): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
function bool(v: unknown): boolean {
  return v === true || v === "true" || v === 1;
}
function arr(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

export function toSeverity(v: unknown): Severity {
  const s = str(v).toLowerCase();
  return s === "critical" || s === "warning" ? s : "info";
}

/** JSON metni ya da nesne kabul eder; bozuk metin boş veri döndürür. */
export function parsePayload(payload: unknown): unknown {
  if (typeof payload !== "string") return payload;
  try {
    return JSON.parse(payload);
  } catch {
    return {};
  }
}

export function normalizeIssue(v: unknown): HealthIssue {
  const o = obj(v);
  return {
    id: num(o.id),
    severity: toSeverity(o.severity),
    title: str(o.title),
    detail: str(o.detail),
    location: str(o.location),
    bin: str(o.bin),
    item: str(o.item),
    variant: str(o.variant),
    lot: str(o.lot),
    lpNo: str(o.lpNo),
    docNo: str(o.docNo),
    ref: str(o.ref),
    qtyBin: num(o.qtyBin),
    qtyLp: num(o.qtyLp),
    count: num(o.count),
    fixAvailable: bool(o.fixAvailable),
    canFix: bool(o.canFix),
    fixCaption: str(o.fixCaption),
    fixConfirm: str(o.fixConfirm),
    showCaption: str(o.showCaption),
    compareAvailable: bool(o.compareAvailable),
    traceAvailable: bool(o.traceAvailable),
  };
}

export function normalizeCategory(v: unknown): HealthCategory {
  const o = obj(v);
  const issues = arr(o.issues).map(normalizeIssue);
  return {
    key: str(o.key),
    title: str(o.title),
    description: str(o.description),
    total: Math.max(num(o.total), issues.length),
    scanLimited: bool(o.scanLimited),
    fixable: bool(o.fixable),
    canFix: bool(o.canFix),
    fixDeniedReason: str(o.fixDeniedReason),
    fixAllCaption: str(o.fixAllCaption),
    issues,
  };
}

export function normalizeHealth(payload: unknown): HealthData {
  const p = obj(parsePayload(payload));
  const s = obj(p.summary);
  return {
    generatedAt: str(p.generatedAt),
    locationFilter: str(p.locationFilter),
    locations: arr(p.locations)
      .map((l) => {
        const o = obj(l);
        return { code: str(o.code), name: str(o.name) };
      })
      .filter((l) => l.code !== ""),
    maxRowsPerCategory: num(p.maxRowsPerCategory) || 50,
    compareAvailable: bool(p.compareAvailable),
    summary: { critical: num(s.critical), warning: num(s.warning), info: num(s.info) },
    categories: arr(p.categories).map(normalizeCategory).filter((c) => c.key !== ""),
  };
}

export function normalizeResult(payload: unknown): FixResult {
  const o = obj(parsePayload(payload));
  return { ok: bool(o.ok), message: str(o.message) };
}

/** Kategorideki en yüksek önem; bulgu yoksa null. */
export function categorySeverity(c: HealthCategory): Severity | null {
  let best: Severity | null = null;
  for (const i of c.issues) {
    if (!best || SEVERITY_RANK[i.severity] > SEVERITY_RANK[best]) best = i.severity;
  }
  return best;
}

/** Gösterilmeyen ("devamı") bulgu sayısı. */
export function hiddenCount(c: HealthCategory): number {
  return Math.max(0, c.total - c.issues.length);
}

/** Bulgulu kategoriler önce (önem, sonra sayı); temiz kategoriler sonda, BC sırasıyla. */
export function sortCategories(categories: HealthCategory[]): HealthCategory[] {
  return categories
    .map((c, index) => ({ c, index }))
    .sort((a, b) => {
      const sa = categorySeverity(a.c);
      const sb = categorySeverity(b.c);
      const ra = sa ? SEVERITY_RANK[sa] : 0;
      const rb = sb ? SEVERITY_RANK[sb] : 0;
      if (ra !== rb) return rb - ra;
      if (a.c.total !== b.c.total && ra > 0) return b.c.total - a.c.total;
      return a.index - b.index;
    })
    .map((x) => x.c);
}

export function filterBySeverity(c: HealthCategory, filter: Severity | "all"): HealthIssue[] {
  if (filter === "all") return c.issues;
  return c.issues.filter((i) => i.severity === filter);
}

const qtyFormat = new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 5 });
export function formatQty(n: number): string {
  return qtyFormat.format(n);
}

export function formatTime(iso: string): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleTimeString("tr-TR", { hour: "2-digit", minute: "2-digit" });
}

export function totalIssues(d: HealthData): number {
  return d.summary.critical + d.summary.warning + d.summary.info;
}

export const SEVERITY_LABEL: Record<Severity, string> = {
  critical: "Kritik",
  warning: "Uyarı",
  info: "Bilgi",
};
