import { useCallback, useEffect, useMemo, useState } from "react";
import { bc, listen } from "./bridge";
import {
  type FixResult,
  type HealthCategory,
  type HealthData,
  type HealthIssue,
  type Severity,
  SEVERITY_LABEL,
  categorySeverity,
  filterBySeverity,
  formatQty,
  formatTime,
  hiddenCount,
  normalizeHealth,
  normalizeResult,
  sortCategories,
  totalIssues,
} from "./data";

type ConfirmState = {
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
} | null;

type SeverityFilter = Severity | "all";

export type HealthPanelProps = {
  /** Test/önizleme için başlangıç verisi; BC'de SetData ile gelir. */
  initialData?: HealthData | null;
  /** false ise BC'ye ControlReady gönderilmez (test/önizleme). */
  connect?: boolean;
};

export function HealthPanelApp({ initialData = null, connect = true }: HealthPanelProps) {
  const [data, setData] = useState<HealthData | null>(initialData);
  const [busy, setBusy] = useState<boolean>(initialData == null);
  const [filter, setFilter] = useState<SeverityFilter>("all");
  const [confirm, setConfirm] = useState<ConfirmState>(null);
  const [toast, setToast] = useState<FixResult | null>(null);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!connect) return;
    const off = listen((m) => {
      if (m.type === "setData") {
        setData(normalizeHealth(m.payload));
        setBusy(false);
      } else if (m.type === "notifyResult") {
        const r = normalizeResult(m.payload);
        if (r.message) setToast(r);
      } else if (m.type === "setBusy") {
        setBusy(m.busy);
      }
    });
    bc.ready();
    return off;
  }, [connect]);

  useEffect(() => {
    if (!toast) return;
    const t = window.setTimeout(() => setToast(null), toast.ok ? 6000 : 12000);
    return () => window.clearTimeout(t);
  }, [toast]);

  const refresh = useCallback((locationFilter: string) => {
    setBusy(true);
    bc.refresh(locationFilter);
  }, []);

  const askFix = useCallback((issue: HealthIssue) => {
    setConfirm({
      title: issue.fixCaption || "Düzelt",
      message: issue.fixConfirm || "Bu düzeltme uygulansın mı?",
      confirmLabel: issue.fixCaption || "Düzelt",
      onConfirm: () => {
        setBusy(true);
        bc.fixIssue(issue.id);
      },
    });
  }, []);

  const askFixAll = useCallback((c: HealthCategory) => {
    const fixable = c.issues.filter((i) => i.canFix).length;
    const scope = c.key === "orphanAssignment" ? c.total : fixable;
    setConfirm({
      title: c.fixAllCaption,
      message:
        c.key === "orphanAssignment"
          ? `${scope} yetim LP ataması serbest bırakılacak. Stok ve göz değişmez. Devam edilsin mi?`
          : `Listelenen ${scope} bulgu düzeltilecek. Devam edilsin mi?`,
      confirmLabel: c.fixAllCaption,
      onConfirm: () => {
        setBusy(true);
        bc.fixCategory(c.key);
      },
    });
  }, []);

  const toggle = useCallback((key: string) => {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  const sorted = useMemo(() => (data ? sortCategories(data.categories) : []), [data]);
  const withIssues = sorted.filter((c) => c.total > 0);
  const clean = sorted.filter((c) => c.total === 0);
  const total = data ? totalIssues(data) : 0;

  return (
    <div className="hp" aria-busy={busy}>
      <header className="hp-head">
        <div className="hp-titles">
          <h1>Depo Sağlık Paneli</h1>
          <p className="hp-sub">
            Sorun Merkezi
            {data?.generatedAt ? <> · Son tarama {formatTime(data.generatedAt)}</> : null}
          </p>
        </div>
        <div className="hp-controls">
          <label className="hp-field">
            <span>Depo</span>
            <select
              value={data?.locationFilter ?? ""}
              onChange={(e) => refresh(e.target.value)}
              disabled={busy && !data}
              aria-label="Depo filtresi"
            >
              <option value="">Tüm depolar</option>
              {data?.locations.map((l) => (
                <option key={l.code} value={l.code}>
                  {l.name ? `${l.code} · ${l.name}` : l.code}
                </option>
              ))}
              {data?.locationFilter && !data.locations.some((l) => l.code === data.locationFilter) ? (
                <option value={data.locationFilter}>{data.locationFilter}</option>
              ) : null}
            </select>
          </label>
          <button type="button" className="hp-btn hp-btn-ghost" onClick={() => refresh(data?.locationFilter ?? "")} disabled={busy}>
            <RefreshIcon spinning={busy} /> Yenile
          </button>
        </div>
      </header>

      {data ? (
        <>
          <section className={`hp-status ${total === 0 ? "ok" : data.summary.critical > 0 ? "critical" : "warning"}`}>
            <div className="hp-status-text">
              {total === 0 ? (
                <>
                  <CheckIcon /> <strong>Açık sorun yok.</strong>
                </>
              ) : (
                <>
                  <AlertIcon /> <strong>{total} sorun bulundu.</strong>
                </>
              )}
            </div>
            <div className="hp-tiles" role="group" aria-label="Önem filtresi">
              <SeverityTile label="Tümü" value={total} active={filter === "all"} onClick={() => setFilter("all")} tone="all" />
              {(["critical", "warning", "info"] as Severity[]).map((s) => (
                <SeverityTile
                  key={s}
                  label={SEVERITY_LABEL[s]}
                  value={data.summary[s]}
                  active={filter === s}
                  onClick={() => setFilter(filter === s ? "all" : s)}
                  tone={s}
                />
              ))}
            </div>
          </section>

          <main className="hp-cats">
            {withIssues.map((c) => (
              <CategoryCard
                key={c.key}
                category={c}
                filter={filter}
                collapsed={collapsed.has(c.key)}
                busy={busy}
                onToggle={() => toggle(c.key)}
                onFix={askFix}
                onFixAll={() => askFixAll(c)}
              />
            ))}
            {clean.length > 0 ? (
              <section className="hp-clean" aria-label="Sorunsuz kontroller">
                <h2>Sorunsuz kontroller</h2>
                <ul>
                  {clean.map((c) => (
                    <li key={c.key} title={c.description}>
                      <CheckIcon /> {c.title}
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}
          </main>
        </>
      ) : (
        <div className="hp-loading">
          <RefreshIcon spinning /> Depo taranıyor…
        </div>
      )}

      {busy && data ? <div className="hp-busy" aria-live="polite">Güncelleniyor…</div> : null}

      {confirm ? (
        <div className="hp-modal-back" role="presentation" onClick={() => setConfirm(null)}>
          <div
            className="hp-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="hp-modal-title"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 id="hp-modal-title">{confirm.title}</h3>
            <p>{confirm.message}</p>
            <div className="hp-modal-actions">
              <button type="button" className="hp-btn hp-btn-ghost" onClick={() => setConfirm(null)} autoFocus>
                Vazgeç
              </button>
              <button
                type="button"
                className="hp-btn hp-btn-primary"
                onClick={() => {
                  const c = confirm;
                  setConfirm(null);
                  c.onConfirm();
                }}
              >
                {confirm.confirmLabel}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {toast ? (
        <div className={`hp-toast ${toast.ok ? "ok" : "err"}`} role="status">
          {toast.ok ? <CheckIcon /> : <AlertIcon />}
          <span>{toast.message}</span>
          <button type="button" aria-label="Kapat" onClick={() => setToast(null)}>
            ×
          </button>
        </div>
      ) : null}
    </div>
  );
}

function SeverityTile(props: { label: string; value: number; active: boolean; onClick: () => void; tone: Severity | "all" }) {
  return (
    <button
      type="button"
      className={`hp-tile tone-${props.tone}${props.active ? " active" : ""}`}
      aria-pressed={props.active}
      onClick={props.onClick}
    >
      <span className="hp-tile-val">{props.value}</span>
      <span className="hp-tile-lbl">{props.label}</span>
    </button>
  );
}

function CategoryCard(props: {
  category: HealthCategory;
  filter: SeverityFilter;
  collapsed: boolean;
  busy: boolean;
  onToggle: () => void;
  onFix: (i: HealthIssue) => void;
  onFixAll: () => void;
}) {
  const { category: c, filter, collapsed, busy } = props;
  const sev = categorySeverity(c) ?? "info";
  const visible = filterBySeverity(c, filter);
  const hidden = hiddenCount(c);
  const fixableCount = c.issues.filter((i) => i.canFix).length;
  if (filter !== "all" && visible.length === 0) return null;
  return (
    <section className={`hp-cat sev-${sev}`} data-category={c.key}>
      <header className="hp-cat-head">
        <button type="button" className="hp-cat-toggle" onClick={props.onToggle} aria-expanded={!collapsed}>
          <span className={`hp-dot sev-${sev}`} aria-hidden="true" />
          <span className="hp-cat-title">{c.title}</span>
          <span className={`hp-count sev-${sev}`}>{c.total}</span>
          <span className={`hp-chevron${collapsed ? "" : " open"}`} aria-hidden="true">
            ›
          </span>
        </button>
        {c.fixAllCaption && fixableCount > 1 ? (
          <span title={c.canFix ? "" : c.fixDeniedReason}>
            <button type="button" className="hp-btn hp-btn-outline" disabled={!c.canFix || busy} onClick={props.onFixAll}>
              {c.fixAllCaption}
            </button>
          </span>
        ) : null}
      </header>
      {!collapsed ? (
        <>
          <p className="hp-cat-desc">{c.description}</p>
          {c.scanLimited ? (
            <p className="hp-note">Tarama sınırına ulaşıldı; sonuçlar eksik olabilir.</p>
          ) : null}
          <div className="hp-issues">
            {visible.map((i) => (
              <IssueCard key={i.id} issue={i} categoryKey={c.key} denied={c.fixDeniedReason} busy={busy} onFix={props.onFix} />
            ))}
          </div>
          {hidden > 0 ? (
            <p className="hp-more">
              +{hidden} bulgu daha var (ilk {c.issues.length} gösteriliyor).
            </p>
          ) : null}
        </>
      ) : null}
    </section>
  );
}

function IssueCard(props: { issue: HealthIssue; categoryKey: string; denied: string; busy: boolean; onFix: (i: HealthIssue) => void }) {
  const { issue: i, categoryKey, denied, busy } = props;
  const isStock = categoryKey === "stockMismatch";
  const isSource = categoryKey === "lpSourceEntry";
  const diff = i.qtyLp - i.qtyBin;
  const chips: Array<[string, string]> = [];
  if (i.location) chips.push(["Depo", i.location]);
  if (i.bin && !isStock) chips.push(["Göz", i.bin]);
  if (i.lot && !isStock) chips.push(["Lot", i.lot]);
  if (i.lpNo) chips.push(["LP", i.lpNo]);
  if (isSource && i.count > 1) chips.push(["LP satırı", String(i.count)]);
  if (i.docNo) chips.push([categoryKey === "printerMapping" ? "Yazıcı" : "Belge", i.docNo]);
  if (i.ref && categoryKey === "printJob") chips.push(["Yazıcı", i.ref]);
  if (i.ref && categoryKey === "printerMapping") chips.push(["Cihaz", i.ref]);
  return (
    <article className={`hp-issue sev-${i.severity}`} data-issue={i.id}>
      <div className="hp-issue-main">
        <div className="hp-issue-top">
          <span className={`hp-pill sev-${i.severity}`}>{SEVERITY_LABEL[i.severity]}</span>
          <h3 className="hp-issue-title">{i.title}</h3>
        </div>
        <p className="hp-issue-detail">{i.detail}</p>
        {isStock ? (
          <div className="hp-metrics">
            <Metric label={i.bin ? "Gözde (BC)" : "Lokasyonda (BC)"} value={formatQty(i.qtyBin)} />
            <Metric label="Aktif LP'lerde" value={formatQty(i.qtyLp)} />
            <Metric
              label="Fark"
              value={`${diff > 0 ? "+" : ""}${formatQty(diff)}`}
              tone={diff > 0 ? "critical" : "warning"}
            />
          </div>
        ) : null}
        {isSource && i.docNo ? (
          <div className="hp-metrics">
            <Metric label="Girişte kalan" value={formatQty(i.qtyBin)} />
            <Metric label="Bağlı LP'lerde" value={formatQty(i.qtyLp)} />
          </div>
        ) : null}
        {chips.length > 0 ? (
          <ul className="hp-chips">
            {chips.map(([k, v]) => (
              <li key={k + v}>
                <span>{k}</span> {v}
              </li>
            ))}
          </ul>
        ) : null}
      </div>
      <div className="hp-issue-actions">
        {i.fixAvailable ? (
          <span title={i.canFix ? "" : denied || "Bu düzeltme için yazma yetkiniz yok."}>
            <button type="button" className="hp-btn hp-btn-primary" disabled={!i.canFix || busy} onClick={() => props.onFix(i)}>
              {i.fixCaption || "Düzelt"}
            </button>
          </span>
        ) : null}
        {i.showCaption ? (
          <button type="button" className="hp-btn hp-btn-ghost" onClick={() => bc.showIssue(i.id, "main")}>
            {i.showCaption}
          </button>
        ) : null}
        {i.compareAvailable ? (
          <button type="button" className="hp-btn hp-btn-ghost" onClick={() => bc.showIssue(i.id, "compare")}>
            Karşılaştır
          </button>
        ) : null}
        {i.traceAvailable ? (
          <button type="button" className="hp-btn hp-btn-ghost" onClick={() => bc.showIssue(i.id, "trace")}>
            LP izini aç
          </button>
        ) : null}
      </div>
    </article>
  );
}

function Metric(props: { label: string; value: string; tone?: Severity }) {
  return (
    <div className={`hp-metric${props.tone ? ` tone-${props.tone}` : ""}`}>
      <span className="hp-metric-lbl">{props.label}</span>
      <span className="hp-metric-val">{props.value}</span>
    </div>
  );
}

function RefreshIcon({ spinning = false }: { spinning?: boolean }) {
  return (
    <svg className={`hp-icon${spinning ? " spin" : ""}`} viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
      <path
        fill="currentColor"
        d="M17.65 6.35A7.95 7.95 0 0 0 12 4a8 8 0 1 0 7.75 10h-2.08A6 6 0 1 1 12 6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"
      />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg className="hp-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
      <path fill="currentColor" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" />
    </svg>
  );
}

function AlertIcon() {
  return (
    <svg className="hp-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
      <path fill="currentColor" d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" />
    </svg>
  );
}
