import { Fragment, useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { bc, subscribe } from "./bridge";
import {
  REASON_META,
  STATUS_META,
  buildFilterPayload,
  filterRows,
  formatDate,
  formatDateTime,
  formatQty,
  formatSigned,
  groupLinesByLp,
  normalizeData,
  splitList,
  statusAdvice,
  summaryChips,
  type LpGroup,
  type StatusFilter,
} from "./model";
import type { CompareData, CompareFilter, CompareRow, Notice } from "./types";

const EMPTY_FILTER: CompareFilter = { location: "", zone: "", binFrom: "", binTo: "", item: "", onlyDiff: true };

export function BinLpCompareApp() {
  const [data, setData] = useState<CompareData | null>(null);
  const [filter, setFilter] = useState<CompareFilter>(EMPTY_FILTER);
  // Seçili lokasyon göz zorunlu mu: önce lokasyon listesindeki bayrak, yoksa son verinin bayrağı.
  const selectedLocation = data?.locations.find((l) => l.code === filter.location);
  const binMode =
    selectedLocation?.binMandatory ?? (data && data.location === filter.location ? data.binMandatory : true);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState(true);
  const [notice, setNotice] = useState<Notice | null>(null);

  useEffect(() => {
    const off = subscribe((event) => {
      if (event.type === "data") {
        const next = normalizeData(event.payload);
        setData(next);
        setFilter({
          location: next.location,
          zone: next.zone,
          binFrom: next.binFrom,
          binTo: next.binTo,
          item: next.item,
          onlyDiff: next.onlyDiff,
        });
        setExpanded((prev) => new Set([...prev].filter((id) => next.rows.some((r) => r.id === id))));
        setBusy(false);
      } else if (event.type === "notice") {
        setNotice(event.payload);
        setBusy(false);
      }
    });
    bc.ready();
    return () => {
      off();
    };
  }, []);

  useEffect(() => {
    if (!notice || notice.kind === "error") return;
    const timer = window.setTimeout(() => setNotice(null), 6000);
    return () => window.clearTimeout(timer);
  }, [notice]);

  const runCompare = useCallback((next: CompareFilter) => {
    const payload = buildFilterPayload(next);
    if (!payload.location) {
      setNotice({ kind: "error", message: "Karşılaştırma için bir lokasyon seçin." });
      return;
    }
    setBusy(true);
    setNotice(null);
    bc.compare(payload);
  }, []);

  const currentFilter = useCallback(() => buildFilterPayload(filter), [filter]);

  const rows = useMemo(() => filterRows(data?.rows ?? [], statusFilter, search), [data, statusFilter, search]);
  const chips = useMemo(() => (data ? summaryChips(data.summary) : []), [data]);

  const toggleRow = (id: number) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    runCompare(filter);
  };

  const summary = data?.summary;
  const hiddenEqual = data?.onlyDiff ? summary?.equal ?? 0 : 0;

  return (
    <div className={`blc${busy ? " is-busy" : ""}`}>
      <div className="blc-progress" aria-hidden={!busy} />
      <header className="blc-head">
        <div className="blc-title">
          <h1>Göz ve LP Karşılaştırma</h1>
          <p>
            BC göz stoğu ile gözdeki aktif LP miktarı (Açık, Oluşturuldu, Atandı) · madde, varyant ve lot bazında, temel
            birimde
          </p>
        </div>
        <div className="blc-head-actions">
          {data?.generatedAt && !data.needsLocation && (
            <span className="blc-stamp">Son hesap {formatDateTime(data.generatedAt)}</span>
          )}
          <button
            type="button"
            className="blc-btn blc-btn--ghost"
            disabled={busy || !data || data.needsLocation}
            onClick={() => bc.exportExcel(currentFilter())}
          >
            <IconDownload /> Excel'e aktar
          </button>
          <button
            type="button"
            className="blc-btn blc-btn--ghost"
            disabled={busy || !filter.location}
            onClick={() => runCompare(filter)}
          >
            <IconRefresh /> Yenile
          </button>
        </div>
      </header>

      {!binMode && filter.location && (
        <p className="blc-note" role="note">
          {filter.location} göz kullanmıyor: karşılaştırma lokasyon düzeyinde (madde/varyant/lot), BC stoğu madde
          girişlerinden okunur. Bölge ve göz filtreleri kullanılmaz.
        </p>
      )}
      <form className="blc-filters" onSubmit={onSubmit}>
        <label className="blc-field">
          <span>
            Lokasyon <em aria-hidden>*</em>
          </span>
          <select
            value={filter.location}
            required
            onChange={(e) => setFilter({ ...filter, location: e.target.value, zone: "" })}
          >
            <option value="">Seçin…</option>
            {(data?.locations ?? []).map((l) => (
              <option key={l.code} value={l.code}>
                {l.code}
                {l.name ? ` · ${l.name}` : ""}
              </option>
            ))}
          </select>
        </label>
        {binMode && (<>
        <label className="blc-field">
          <span>Bölge</span>
          <select value={filter.zone} onChange={(e) => setFilter({ ...filter, zone: e.target.value })}>
            <option value="">Tümü</option>
            {(data?.location === filter.location ? data?.zones ?? [] : []).map((z) => (
              <option key={z.code} value={z.code}>
                {z.code}
                {z.name ? ` · ${z.name}` : ""}
              </option>
            ))}
          </select>
        </label>
        <div className="blc-field blc-field--range">
          <span>Göz aralığı</span>
          <div className="blc-range">
            <input
              value={filter.binFrom}
              placeholder="K.K03.01 veya K.K03*"
              aria-label="Başlangıç gözü"
              onChange={(e) => setFilter({ ...filter, binFrom: e.target.value })}
            />
            <span aria-hidden>–</span>
            <input
              value={filter.binTo}
              placeholder="K.K03.99"
              aria-label="Bitiş gözü"
              onChange={(e) => setFilter({ ...filter, binTo: e.target.value })}
            />
          </div>
        </div>
        </>)}
        <label className="blc-field">
          <span>Madde</span>
          <input
            value={filter.item}
            placeholder="ITM-1042* veya A|B"
            onChange={(e) => setFilter({ ...filter, item: e.target.value })}
          />
        </label>
        <label className="blc-switch">
          <input
            type="checkbox"
            disabled={!data}
            checked={filter.onlyDiff}
            onChange={(e) => {
              const next = { ...filter, onlyDiff: e.target.checked };
              setFilter(next);
              if (data && !data.needsLocation && next.location) runCompare(next);
            }}
          />
          <span className="blc-switch-track" aria-hidden />
          <span>Yalnız farklar</span>
        </label>
        <button type="submit" className="blc-btn blc-btn--primary" disabled={busy}>
          Karşılaştır
        </button>
      </form>

      {notice && (
        <div className={`blc-notice blc-notice--${notice.kind}`} role={notice.kind === "error" ? "alert" : "status"}>
          <span>{notice.message}</span>
          <button type="button" aria-label="Kapat" onClick={() => setNotice(null)}>
            ×
          </button>
        </div>
      )}

      {!data ? (
        <div className="blc-empty">
          <div className="blc-spinner" />
          <p>Karşılaştırma hazırlanıyor…</p>
        </div>
      ) : data.needsLocation ? (
        <div className="blc-empty">
          <h2>Bir lokasyon seçin</h2>
          <p>Lokasyonu seçip Karşılaştır'a basın. Göz aralığı ve madde filtresi isteğe bağlıdır.</p>
        </div>
      ) : (
        <>
          <section className="blc-summary" aria-label="Özet">
            <div className="blc-totals">
              <Total label="Göz" value={formatQty(summary?.bins)} />
              <Total label="Aktif LP" value={formatQty(summary?.lps)} />
              <Total label="BC stok" value={formatQty(summary?.stockTotal)} />
              <Total label="LP miktarı" value={formatQty(summary?.lpTotal)} />
              <Total label="LP fazlası" value={formatSigned(summary?.lpSurplusQty)} tone="red" />
              <Total label="LP'siz stok" value={formatSigned(-(summary?.stockSurplusQty ?? 0))} tone="orange" />
            </div>
            <div className="blc-chips" role="toolbar" aria-label="Durum süzgeci">
              <button
                type="button"
                className={`blc-chip blc-chip--neutral${statusFilter === "all" ? " is-active" : ""}`}
                onClick={() => setStatusFilter("all")}
              >
                Tümü <b>{formatQty(data.rows.length)}</b>
              </button>
              {chips.map((chip) => {
                const hidden = chip.key === "equal" && data.onlyDiff;
                return (
                  <button
                    key={chip.key}
                    type="button"
                    className={`blc-chip blc-chip--${chip.tone}${statusFilter === chip.key ? " is-active" : ""}${
                      chip.count === 0 ? " is-zero" : ""
                    }`}
                    title={hidden ? "Yalnız farklar açıkken eşit satırlar gizlenir" : undefined}
                    onClick={() => setStatusFilter(statusFilter === chip.key ? "all" : chip.key)}
                  >
                    <i aria-hidden />
                    {chip.label} <b>{formatQty(chip.count)}</b>
                    {hidden && chip.count > 0 && <small>gizli</small>}
                  </button>
                );
              })}
            </div>
          </section>

          <div className="blc-toolbar">
            <div className="blc-search">
              <IconSearch />
              <input
                value={search}
                placeholder="Tabloda ara: göz, madde, lot, LP"
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <span className="blc-count">
              {formatQty(rows.length)} satır
              {hiddenEqual > 0 && ` · ${formatQty(hiddenEqual)} eşit satır gizli`}
            </span>
          </div>

          {data.truncated && (
            <div className="blc-notice blc-notice--info">
              <span>
                İlk {formatQty(data.maxRows ?? rows.length)} satır gösteriliyor. Daha dar bir göz aralığı veya madde
                filtresi seçin; Excel'e aktar tüm satırları indirir.
              </span>
            </div>
          )}

          {rows.length === 0 ? (
            <div className="blc-empty blc-empty--ok">
              <IconCheck />
              <h2>Fark yok</h2>
              <p>
                {statusFilter === "all" && !search
                  ? "Seçilen filtrelerde BC göz stoğu ile aktif LP miktarı eşit."
                  : "Bu süzgece uyan satır yok."}
              </p>
            </div>
          ) : (
            <div className="blc-table-wrap">
              <table className="blc-table">
                <thead>
                  <tr>
                    <th className="c-exp" aria-label="Aç/kapat" />
                    <th>Durum</th>
                    <th>{binMode ? "Göz" : "Yer"}</th>
                    <th>Madde</th>
                    <th>Lot</th>
                    <th className="num">BC stok</th>
                    <th className="num">LP</th>
                    <th className="num">Fark</th>
                    <th className="num">LP sayısı</th>
                    <th>Olası neden</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const open = expanded.has(row.id);
                    const meta = STATUS_META[row.status];
                    return (
                      <Fragment key={row.id}>
                        <tr
                          className={`blc-row tone-${meta.tone}${open ? " is-open" : ""}`}
                          tabIndex={0}
                          aria-expanded={open}
                          onClick={() => toggleRow(row.id)}
                          onKeyDown={(e) => {
                            if (e.key === "Enter" || e.key === " ") {
                              e.preventDefault();
                              toggleRow(row.id);
                            }
                          }}
                        >
                          <td className="c-exp">
                            <IconChevron />
                          </td>
                          <td>
                            <span className={`blc-pill tone-${meta.tone}`} title={meta.hint}>
                              {meta.label}
                            </span>
                          </td>
                          <td className="mono strong">
                            {row.bin || <span className="muted">{binMode ? "(gözsüz LP)" : "Lokasyon"}</span>}
                            {row.zone && <small className="muted"> {row.zone}</small>}
                          </td>
                          <td>
                            <div className="mono strong">{row.item}</div>
                            <div className="muted ellipsis">{row.description}</div>
                          </td>
                          <td className="mono">
                            {row.lot || <span className="muted">—</span>}
                            {row.variant && <div className="muted">Varyant {row.variant}</div>}
                          </td>
                          <td className="num">
                            {formatQty(row.stock)} <small className="muted">{row.uom}</small>
                          </td>
                          <td className="num">{formatQty(row.lp)}</td>
                          <td
                            className={`num diff ${
                              row.status === "negativeStock" ? "negstock" : row.diff > 0 ? "pos" : row.diff < 0 ? "neg" : "zero"
                            }`}
                          >
                            {formatSigned(row.diff)}
                          </td>
                          <td className="num">{row.lpCount}</td>
                          <td>
                            {row.reason !== "none" ? (
                              <span className={`blc-reason reason-${row.reason}`}>{REASON_META[row.reason].label}</span>
                            ) : (
                              <span className="muted">—</span>
                            )}
                          </td>
                        </tr>
                        {open && (
                          <tr className="blc-detail-row">
                            <td colSpan={10}>
                              <RowDetail
                                row={row}
                                location={data.location}
                                binMode={data.binMandatory}
                                traceability={data.traceabilityAvailable}
                                busy={busy}
                                onRepair={() => {
                                  setBusy(true);
                                  bc.repairUndoneReceipt(row.undoEntryNos, currentFilter());
                                }}
                                onRelease={() => {
                                  setBusy(true);
                                  bc.releaseOrphans(splitList(row.orphanLpNos).join(","), currentFilter());
                                }}
                              />
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function Total({ label, value, tone }: { label: string; value: string; tone?: "red" | "orange" }) {
  return (
    <div className={`blc-total${tone ? ` tone-${tone}` : ""}`}>
      <span>{label}</span>
      <b>{value}</b>
    </div>
  );
}

function RowDetail({
  row,
  location,
  traceability,
  busy,
  onRepair,
  onRelease,
  binMode = true,
}: {
  row: CompareRow;
  location: string;
  binMode?: boolean;
  traceability: boolean;
  busy: boolean;
  onRepair: () => void;
  onRelease: () => void;
}) {
  const groups = useMemo(() => groupLinesByLp(row.lines), [row.lines]);
  const meta = STATUS_META[row.status];
  const reason = row.reason !== "none" ? REASON_META[row.reason] : null;
  const singleLp = groups.length === 1 ? groups[0].lpNo : "";

  return (
    <div className="blc-detail">
      <aside className={`blc-cause tone-${meta.tone}`}>
        <div className="blc-eyebrow">{reason ? "Olası neden" : "Durum"}</div>
        <h3>{reason ? reason.label : meta.label}</h3>
        <p>{row.reasonDetail || meta.hint}</p>
        <p className="muted">{reason ? reason.advice : statusAdvice(row.status)}</p>
        <div className="blc-cause-actions">
          {row.reason === "undoneReceipt" && (
            <button type="button" className="blc-btn blc-btn--danger" disabled={busy} onClick={onRepair}>
              Geri alınan mal kabul LP'lerini boşalt
              {row.repairableLines > 0 && <small> · {row.repairableLines} satır</small>}
            </button>
          )}
          {row.reason === "orphanAssignment" && (
            <button type="button" className="blc-btn blc-btn--primary" disabled={busy} onClick={onRelease}>
              Yetim atamayı serbest bırak
            </button>
          )}
          {singleLp && (
            <button type="button" className="blc-btn blc-btn--ghost" onClick={() => bc.openLp(singleLp)}>
              LP'yi aç
            </button>
          )}
          <button
            type="button"
            className="blc-btn blc-btn--ghost"
            onClick={() => bc.openBinContent(location, row.bin, row.item, row.variant)}
          >
            {binMode ? "Göz içeriğini aç" : "Madde girişlerini aç"}
          </button>
        </div>
      </aside>

      <section className="blc-lps">
        <div className="blc-eyebrow">
          Bu satırdaki LP'ler <b>{groups.length}</b>
        </div>
        {groups.length === 0 ? (
          <p className="blc-nolp">
            Bu gözde bu madde{row.lot ? `/lot (${row.lot})` : ""} için aktif LP yok. Stok gözde LP'siz duruyor.
          </p>
        ) : (
          groups.map((group) => (
            <LpCard key={group.lpNo} group={group} item={row.item} lot={row.lot} traceability={traceability} />
          ))
        )}
      </section>
    </div>
  );
}

function LpCard({ group, item, lot, traceability }: { group: LpGroup; item: string; lot: string; traceability: boolean }) {
  return (
    <div className={`blc-lp${group.orphan ? " is-orphan" : ""}`}>
      <div className="blc-lp-head">
        <button type="button" className="blc-link mono" onClick={() => bc.openLp(group.lpNo)}>
          {group.lpNo}
        </button>
        <span className="blc-tag">{group.lpStatus}</span>
        {group.assignedDocNo && (
          <span className="blc-assign">
            {group.assignedDocType} <b className="mono">{group.assignedDocNo}</b>
          </span>
        )}
        {group.orphan && <span className="blc-tag blc-tag--warn">Belge artık yok</span>}
        {group.pendingReceiptNo && <span className="blc-tag">Mal kabul bekliyor {group.pendingReceiptNo}</span>}
        {group.parentLpNo && <span className="blc-tag">Üst LP {group.parentLpNo}</span>}
        <span className="blc-lp-qty">{formatQty(group.totalBase)}</span>
        <div className="blc-lp-actions">
          <button type="button" className="blc-btn blc-btn--small" onClick={() => bc.openLp(group.lpNo)}>
            LP'yi aç
          </button>
          {traceability && (
            <button
              type="button"
              className="blc-btn blc-btn--small"
              onClick={() => bc.openTraceability(group.lpNo, item, lot)}
            >
              İzlenebilirlik
            </button>
          )}
        </div>
      </div>
      <table className="blc-lines">
        <thead>
          <tr>
            <th>Satır</th>
            <th className="num">Miktar</th>
            <th className="num">Temel</th>
            <th>Lot</th>
            <th>SKT</th>
            <th>Kaynak giriş</th>
            <th>Kaynak belge</th>
            <th>Kaynak göz</th>
          </tr>
        </thead>
        <tbody>
          {group.lines.map((l) => (
            <tr key={`${l.lpNo}-${l.lineNo}`}>
              <td className="mono">{l.lineNo}</td>
              <td className="num">
                {formatQty(l.qty)} <small className="muted">{l.uom}</small>
                {l.uomMissing && <span className="blc-tag blc-tag--warn">birim yok</span>}
              </td>
              <td className="num">{formatQty(l.qtyBase)}</td>
              <td className="mono">{l.lot || l.serial || <span className="muted">—</span>}</td>
              <td>{formatDate(l.expirationDate) || <span className="muted">—</span>}</td>
              <td className="mono">{l.sourceEntryNo ? l.sourceEntryNo : <span className="muted">—</span>}</td>
              <td>
                {l.sourceDocNo ? (
                  <>
                    <span className="muted">{l.sourceDocType}</span> <span className="mono">{l.sourceDocNo}</span>
                  </>
                ) : l.sourceLpNo ? (
                  <>
                    <span className="muted">LP</span> <span className="mono">{l.sourceLpNo}</span>
                  </>
                ) : (
                  <span className="muted">—</span>
                )}
              </td>
              <td className="mono">{l.sourceBin || <span className="muted">—</span>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------- icons

function IconChevron() {
  return (
    <svg className="blc-chevron" width="14" height="14" viewBox="0 0 16 16" aria-hidden>
      <path d="M6 3.5 10.5 8 6 12.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IconRefresh() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden>
      <path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 2.5v3h-3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IconDownload() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden>
      <path d="M8 2.5v8m0 0L4.8 7.3M8 10.5l3.2-3.2M3 13.5h10" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IconSearch() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden>
      <circle cx="7" cy="7" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="m10.5 10.5 3 3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

function IconCheck() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="m7.5 12.5 3 3 6-6.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
