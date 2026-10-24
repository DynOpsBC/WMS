import { useState } from "react";
import { Icon } from "./Icon";
import { compareBars, formatDate, formatDateTime, formatQty, groupEntryTone, groupStateMeta, modeLabel, statusMeta } from "./model";
import type { HistoricLp, TraceDocument, TracePayload, TreeGroup, TreeLp } from "./types";
import { DocumentFlow, Insights, LpChip, NavLink, Pill, Section } from "./ui";

type Props = { trace: TracePayload; onTrace: (text: string) => void };

const LP_PAGE = 12;

export function TreeView({ trace, onTrace }: Props) {
  const totals = trace.totals;
  const diff = (totals?.bcRemainingQty ?? 0) - (totals?.lpQty ?? 0);
  return (
    <div className="lt-view">
      <Insights insights={trace.insights} />
      <section className="lt-summary">
        <div className="lt-summary__title">
          <Pill tone="accent">{modeLabel(trace.mode)}</Pill>
          <h1>{trace.title ?? trace.query}</h1>
        </div>
        {totals ? (
          <div className="lt-kpis">
            <Kpi label="Madde / lot" value={String(totals.groupCount)} />
            <Kpi label="Dolu LP" value={String(totals.lpCount)} />
            <Kpi label="LP toplamı" value={formatQty(totals.lpQty)} />
            <Kpi label="BC kalan" value={formatQty(totals.bcRemainingQty)} />
            <Kpi label="Fark (BC − LP)" value={formatQty(diff)} tone={diff < 0 ? "bad" : diff > 0 ? "warn" : "good"} />
            {totals.historicLpCount ? <Kpi label="Boşalmış LP" value={String(totals.historicLpCount)} tone="muted" /> : null}
          </div>
        ) : null}
      </section>
      <div className="lt-cols">
        <div className="lt-main">
          {trace.groups.length === 0 ? <p className="lt-empty lt-card">Bu aramada dolu LP ya da stok bulunamadı.</p> : null}
          {trace.groups.map((group) => (
            <GroupCard key={group.key} group={group} onTrace={onTrace} />
          ))}
          <HistoricLps lps={trace.historicLps} onTrace={onTrace} />
        </div>
        <aside className="lt-side">
          <Section title="Belge akışı" aside={<span className="lt-muted">{trace.documents.length} belge</span>}>
            <DocumentFlow documents={trace.documents as TraceDocument[]} />
          </Section>
        </aside>
      </div>
    </div>
  );
}

function Kpi({ label, value, tone = "neutral" }: { label: string; value: string; tone?: string }) {
  return (
    <div className={`lt-kpi lt-tone-${tone}`}>
      <span className="lt-kpi__label">{label}</span>
      <span className="lt-kpi__value">{value}</span>
    </div>
  );
}

function GroupCard({ group, onTrace }: { group: TreeGroup; onTrace: (text: string) => void }) {
  const [showAll, setShowAll] = useState(false);
  const state = groupStateMeta(group.state, group.diff);
  const bars = compareBars(group.lpQty, group.bcRemainingQty);
  const lps = showAll ? group.lps : group.lps.slice(0, LP_PAGE);
  return (
    <section className={`lt-group lt-group--${group.state}`}>
      <header className="lt-group__head">
        <div>
          <button type="button" className="lt-link lt-strong" onClick={() => onTrace(group.itemNo)}>
            {group.itemNo}
          </button>
          <span className="lt-muted"> {group.itemDescription}</span>
          {group.lotNo ? (
            <button type="button" className="lt-lotchip" onClick={() => onTrace(`${group.itemNo} ${group.lotNo}`)}>
              Lot {group.lotNo}
            </button>
          ) : (
            <span className="lt-lotchip lt-lotchip--none">lotsuz</span>
          )}
        </div>
        <Pill tone={state.tone}>{state.label}</Pill>
      </header>
      <div className="lt-compare">
        <div className="lt-compare__row">
          <span className="lt-compare__label">LP'lerde</span>
          <span className="lt-compare__bar">
            <span className="lt-compare__fill lt-compare__fill--lp" style={{ width: `${bars.lp}%` }} />
          </span>
          <strong>{formatQty(group.lpQty)}</strong>
          <span className="lt-muted">{group.lpCount} LP</span>
        </div>
        <div className="lt-compare__row">
          <span className="lt-compare__label">BC kalan</span>
          <span className="lt-compare__bar">
            <span className="lt-compare__fill lt-compare__fill--bc" style={{ width: `${bars.bc}%` }} />
          </span>
          <strong>{formatQty(group.bcRemainingQty)}</strong>
          {group.unlinkedLpQty ? <Pill tone="warn">kaynaksız {formatQty(group.unlinkedLpQty)}</Pill> : <span />}
        </div>
      </div>

      {group.lps.length > 0 ? (
        <ul className="lt-lptree">
          {lps.map((lp) => (
            <LpRow key={lp.no} lp={lp} onTrace={onTrace} />
          ))}
        </ul>
      ) : null}
      {group.lps.length > LP_PAGE ? (
        <button type="button" className="lt-link lt-more" onClick={() => setShowAll(!showAll)}>
          {showAll ? "Daha az göster" : `Tüm LP'leri göster (${group.lps.length})`}
        </button>
      ) : null}

      {group.entries.length > 0 ? (
        <div className="lt-tablewrap">
          <table className="lt-table lt-table--compact">
            <thead>
              <tr>
                <th>Madde girişi</th>
                <th>Tarih</th>
                <th>Belge</th>
                <th className="lt-num">Miktar</th>
                <th className="lt-num">Kalan</th>
                <th className="lt-num">LP'lerde</th>
                <th className="lt-num">Fark</th>
              </tr>
            </thead>
            <tbody>
              {group.entries.map((entry) => {
                const tone = groupEntryTone(entry);
                return (
                  <tr key={entry.entryNo} className={`lt-row--${tone}`}>
                    <td>
                      <NavLink nav={{ kind: "ile", key: String(entry.entryNo) }} className="lt-strong">
                        {entry.entryNo}
                      </NavLink>
                      {entry.correction ? <Pill tone="bad">düzeltme</Pill> : null}
                      {entry.undoneByEntryNo ? <Pill tone="bad">geri alındı → {entry.undoneByEntryNo}</Pill> : null}
                    </td>
                    <td>{formatDate(entry.postingDate)}</td>
                    <td>
                      <span className="lt-muted">{entry.entryType}</span> {entry.documentNo}
                    </td>
                    <td className="lt-num">{formatQty(entry.qty)}</td>
                    <td className="lt-num">{formatQty(entry.remainingQty)}</td>
                    <td className="lt-num">{entry.positive ? formatQty(entry.lpQty) : ""}</td>
                    <td className={`lt-num lt-diff lt-tone-${tone}`}>{entry.positive ? formatQty(entry.diff) : ""}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      ) : null}
    </section>
  );
}

function LpRow({ lp, onTrace }: { lp: TreeLp; onTrace: (text: string) => void }) {
  const [open, setOpen] = useState(false);
  const status = statusMeta(lp.status);
  return (
    <li className={`lt-lprow${lp.orphan || lp.onUndoneEntry ? " lt-lprow--orphan" : ""}`}>
      <div className="lt-lprow__main">
        <button type="button" className="lt-twisty" aria-expanded={open} onClick={() => setOpen(!open)} title="Satırlar">
          {open ? "▾" : "▸"}
        </button>
        <LpChip no={lp.no} onTrace={onTrace} />
        <Pill tone={status.tone}>{status.label}</Pill>
        <span className="lt-mono lt-muted">{lp.binCode}</span>
        {lp.orphan ? (
          <Pill tone="bad" title={`${lp.assignedDocNo} artık yok`}>
            Yetim · {lp.assignedDocNo}
          </Pill>
        ) : lp.assignedDocNo ? (
          <span className="lt-muted lt-small">→ {lp.assignedDocNo}</span>
        ) : null}
        {lp.onUndoneEntry ? <Pill tone="bad">geri alınan girişte</Pill> : null}
        {lp.mixedSources ? <Pill tone="accent">karma kaynak</Pill> : null}
        {lp.sourceIleNo ? <span className="lt-muted lt-small">giriş {lp.sourceIleNo}</span> : null}
        <span className="lt-lprow__qty">{formatQty(lp.qty)}</span>
      </div>
      {open ? (
        <ul className="lt-lplines">
          {lp.lines.map((line) => (
            <li key={line.lineNo}>
              <span className="lt-strong">{formatQty(line.qty)}</span> <span className="lt-muted">{line.uom}</span>
              <span className="lt-lplines__src">{line.sourceLabel}</span>
              {line.sourceIleNo ? (
                <NavLink nav={{ kind: "ile", key: String(line.sourceIleNo) }}>giriş {line.sourceIleNo}</NavLink>
              ) : (
                <Pill tone="warn">kaynak giriş yok</Pill>
              )}
              {line.sourceUndoneBy ? <Pill tone="bad">geri alındı → {line.sourceUndoneBy}</Pill> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  );
}

const HISTORIC_PAGE = 30;

function HistoricLps({ lps, onTrace }: { lps: HistoricLp[]; onTrace: (text: string) => void }) {
  const [showAll, setShowAll] = useState(false);
  if (lps.length === 0) return null;
  const visible = showAll ? lps : lps.slice(0, HISTORIC_PAGE);
  const undoCount = lps.filter((lp) => lp.emptiedByUndo).length;
  return (
    <Section
      title="Boşalmış / geçmiş LP'ler"
      aside={
        <span className="lt-muted">
          {lps.length} LP{undoCount ? ` · ${undoCount} geri alma ile boşaltıldı` : ""}
        </span>
      }
    >
      <p className="lt-hint">
        <Icon name="undo" size={13} /> Dolu satırı kalmayan LP'ler; son hareketleriyle.
      </p>
      <ul className="lt-history">
        {visible.map((lp) => {
          const status = statusMeta(lp.status);
          return (
            <li key={lp.no} className={lp.emptiedByUndo ? "lt-history--undo" : ""} title={lp.lastRelatedDocument}>
              <LpChip no={lp.no} onTrace={onTrace} tone={lp.emptiedByUndo ? "bad" : "neutral"} />
              <span className="lt-small">
                <Pill tone={status.tone}>{status.label}</Pill>
                {lp.orphan ? <Pill tone="bad">yetim</Pill> : null}
              </span>
              <span className="lt-muted lt-small">{lp.emptiedByUndo ? "geri alma" : formatDateTime(lp.lastAt)}</span>
            </li>
          );
        })}
      </ul>
      {lps.length > HISTORIC_PAGE ? (
        <button type="button" className="lt-link lt-more" onClick={() => setShowAll(!showAll)}>
          {showAll ? "Daha az göster" : `Tümünü göster (${lps.length})`}
        </button>
      ) : null}
    </Section>
  );
}
