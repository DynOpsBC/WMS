import { useState } from "react";
import { openNode } from "./bridge";
import { Icon } from "./Icon";
import {
  docStateMeta,
  formatDate,
  formatDateTime,
  formatQty,
  formatSignedQty,
  formatTime,
  groupTimelineByDay,
  ledgerBadges,
  sourceColorIndex,
  sourceShares,
  statusMeta,
  timelineTitle,
} from "./model";
import type { LpHeader, TracePayload } from "./types";
import { DocumentFlow, Insights, LpChip, NavLink, Pill, Section } from "./ui";

type Props = { trace: TracePayload; onTrace: (text: string) => void };

export function LpView({ trace, onTrace }: Props) {
  const lp = trace.lp;
  if (!lp) return null;
  return (
    <div className="lt-view">
      <Insights insights={trace.insights} />
      <LpHero lp={lp} onTrace={onTrace} />
      <div className="lt-cols">
        <div className="lt-main">
          <Contents trace={trace} onTrace={onTrace} />
          <Timeline trace={trace} onTrace={onTrace} />
        </div>
        <aside className="lt-side">
          <Section title="Belge akışı" aside={<span className="lt-muted">{trace.documents.length} belge</span>}>
            <DocumentFlow documents={trace.documents} />
          </Section>
          <LedgerSection trace={trace} />
          <WarehouseSection trace={trace} />
        </aside>
      </div>
    </div>
  );
}

function LpHero({ lp, onTrace }: { lp: LpHeader; onTrace: (text: string) => void }) {
  const status = statusMeta(lp.status);
  const assigned = lp.assigned;
  const assignedState = assigned ? docStateMeta(assigned.state) : null;
  return (
    <section className={`lt-hero${lp.orphan ? " lt-hero--orphan" : ""}`}>
      <div className="lt-hero__title">
        <span className="lt-hero__icon">
          <Icon name="box" size={22} />
        </span>
        <div>
          <div className="lt-hero__no">
            {lp.no}
            <Pill tone={status.tone}>{status.label}</Pill>
            {lp.orphan ? <Pill tone="bad">Yetim</Pill> : null}
          </div>
          <div className="lt-hero__sub">
            {lp.locationCode || "–"} · {lp.binCode || "raf yok"}
            {lp.templateCode ? ` · ${lp.templateCode}` : ""}
          </div>
        </div>
        <button type="button" className="lt-btn lt-btn--ghost" onClick={() => openNode("lp", lp.no)}>
          LP kartı
        </button>
      </div>
      <dl className="lt-facts">
        <div>
          <dt>Toplam miktar</dt>
          <dd className="lt-big">{formatQty(lp.totalQty)}</dd>
        </div>
        <div>
          <dt>Satır</dt>
          <dd>{lp.lineCount}</dd>
        </div>
        <div>
          <dt>Atandığı belge</dt>
          <dd>
            {assigned && assigned.no ? (
              <span className="lt-assigned">
                <NavLink nav={assigned.nav}>
                  {assigned.typeCaption} {assigned.no}
                </NavLink>
                {assignedState?.label ? <Pill tone={assignedState.tone}>{assignedState.label}</Pill> : null}
              </span>
            ) : (
              <span className="lt-muted">Yok</span>
            )}
          </dd>
        </div>
        <div>
          <dt>SSCC</dt>
          <dd className="lt-mono">{lp.sscc || "–"}</dd>
        </div>
        <div>
          <dt>Oluşturan</dt>
          <dd>
            {lp.builtBy || "–"}
            <span className="lt-muted"> {formatDateTime(lp.builtAt)}</span>
          </dd>
        </div>
        {lp.pendingReceiptNo ? (
          <div>
            <dt>Bekleyen mal kabul</dt>
            <dd>{lp.pendingReceiptNo}</dd>
          </div>
        ) : null}
        {lp.parent ? (
          <div>
            <dt>Üst LP</dt>
            <dd>
              <LpChip no={lp.parent.no} onTrace={onTrace} />
            </dd>
          </div>
        ) : null}
        {lp.children.length > 0 ? (
          <div className="lt-facts__wide">
            <dt>Alt LP'ler ({lp.children.length})</dt>
            <dd className="lt-chiprow">
              {lp.children.map((child) => (
                <LpChip key={child.no} no={child.no} onTrace={onTrace} suffix={<span className="lt-muted">{formatQty(child.totalQty)}</span>} />
              ))}
            </dd>
          </div>
        ) : null}
      </dl>
    </section>
  );
}

function Contents({ trace, onTrace }: Props) {
  const shares = sourceShares(trace.sourceGroups);
  const unit = trace.lines[0]?.uom ?? "";
  return (
    <Section
      title="İçerik"
      aside={
        <span className="lt-muted">
          {trace.lines.length} satır · {formatQty(trace.lp?.totalQty)} {unit}
        </span>
      }
    >
      {trace.lines.length === 0 ? (
        <p className="lt-empty">LP boş. Geçmişte ne olduğunu aşağıdaki zaman çizelgesi gösterir.</p>
      ) : (
        <>
          {shares.length > 1 ? (
            <div className="lt-sources">
              <div className="lt-sources__title">
                <Icon name="split" size={14} /> Bu LP {shares.length} farklı kaynaktan doldu
              </div>
              <div className="lt-stack" role="img" aria-label="Kaynak payları">
                {shares.map((share) => (
                  <span key={share.key} className={`lt-stack__part lt-src-${share.colorIndex}`} style={{ width: `${share.pct}%` }} />
                ))}
              </div>
              <ul className="lt-legend">
                {shares.map((share) => (
                  <li key={share.key}>
                    <span className={`lt-swatch lt-src-${share.colorIndex}`} />
                    <span className="lt-legend__label">{share.label}</span>
                    <strong>{formatQty(share.qty)}</strong>
                    <span className="lt-muted">%{Math.round(share.pct)}</span>
                    {share.sourceLpNo ? (
                      <LpChip
                        no={share.sourceLpNo}
                        onTrace={onTrace}
                        tone={share.sourceLpStatus === "unbuilt" ? "bad" : "neutral"}
                        suffix={share.sourceLpStatus ? <span className="lt-muted">{statusMeta(share.sourceLpStatus).label}</span> : null}
                      />
                    ) : null}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          <div className="lt-tablewrap">
            <table className="lt-table">
              <thead>
                <tr>
                  <th aria-label="Kaynak rengi" />
                  <th>Madde</th>
                  <th>Lot</th>
                  <th className="lt-num">Miktar</th>
                  <th>Kaynak belge</th>
                  <th className="lt-num">Kaynak giriş</th>
                </tr>
              </thead>
              <tbody>
                {trace.lines.map((line) => {
                  const color = sourceColorIndex(trace.sourceGroups, line.groupKey);
                  const docState = docStateMeta(line.sourceDocState);
                  return (
                    <tr key={line.lineNo} className={trace.mixedSources ? "lt-row--mixed" : ""}>
                      <td className={`lt-stripe lt-src-${color}`} />
                      <td>
                        <button type="button" className="lt-link lt-strong" onClick={() => onTrace(line.itemNo)} title="Maddenin LP ağacı">
                          {line.itemNo}
                        </button>
                        <div className="lt-muted lt-small">{line.itemDescription}</div>
                      </td>
                      <td>
                        {line.lotNo ? (
                          <button type="button" className="lt-link" onClick={() => onTrace(`${line.itemNo} ${line.lotNo}`)} title="Lotun LP ağacı">
                            {line.lotNo}
                          </button>
                        ) : (
                          <span className="lt-muted">–</span>
                        )}
                        {line.expirationDate ? <div className="lt-muted lt-small">SKT {formatDate(line.expirationDate)}</div> : null}
                      </td>
                      <td className="lt-num lt-strong">
                        {formatQty(line.qty)} <span className="lt-muted">{line.uom}</span>
                      </td>
                      <td>
                        {line.sourceDocNo ? (
                          <span className="lt-cellrow">
                            <NavLink nav={line.nav}>
                              {line.sourceDocTypeCaption} {line.sourceDocNo}
                            </NavLink>
                            {docState.label && line.sourceDocState !== "open" ? <Pill tone={docState.tone}>{docState.label}</Pill> : null}
                          </span>
                        ) : (
                          <span className="lt-muted">–</span>
                        )}
                        {line.sourceLpNo ? (
                          <div className="lt-small">
                            ← <LpChip no={line.sourceLpNo} onTrace={onTrace} /> üzerinden
                          </div>
                        ) : null}
                      </td>
                      <td className="lt-num">
                        {line.sourceIleNo ? (
                          <NavLink nav={{ kind: "ile", key: String(line.sourceIleNo) }}>{line.sourceIleNo}</NavLink>
                        ) : (
                          <Pill tone="warn">bağlı değil</Pill>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </>
      )}
    </Section>
  );
}

function Timeline({ trace, onTrace }: Props) {
  const days = groupTimelineByDay(trace.timeline);
  return (
    <Section
      title="Geçmiş"
      aside={
        <button type="button" className="lt-link" onClick={() => trace.lp && openNode("lpLedger", trace.lp.no)}>
          LP hareket defteri ({trace.timeline.length})
        </button>
      }
    >
      {days.length === 0 ? (
        <p className="lt-empty">Bu LP için hareket kaydı yok.</p>
      ) : (
        <ol className="lt-timeline">
          {days.map((day) => (
            <li key={day.day} className="lt-timeline__day">
              <div className="lt-timeline__date">{day.day}</div>
              <ol>
                {day.entries.map((entry) => {
                  const meta = timelineTitle(entry);
                  const otherLp = entry.sourceLpNo && entry.sourceLpNo !== trace.lp?.no ? entry.sourceLpNo : entry.targetLpNo && entry.targetLpNo !== trace.lp?.no ? entry.targetLpNo : "";
                  return (
                    <li key={entry.entryNo} className={`lt-event lt-tone-${meta.tone}`}>
                      <span className="lt-event__icon">
                        <Icon name={meta.icon} size={15} />
                      </span>
                      <div className="lt-event__body">
                        <div className="lt-event__title">
                          <strong>{meta.label}</strong>
                          {entry.qty ? <span className="lt-event__qty">{formatSignedQty(entry.action === "itemRemoved" || entry.action === "transferOut" ? -Math.abs(entry.qty) : entry.qty)}</span> : null}
                          <span className="lt-muted lt-event__time">
                            {formatTime(entry.at)} · {entry.user || "?"}
                          </span>
                        </div>
                        <div className="lt-event__meta">
                          {entry.itemNo ? (
                            <span>
                              {entry.itemNo}
                              {entry.lotSerial ? ` · ${entry.lotSerial}` : ""}
                            </span>
                          ) : null}
                          {entry.fromBin || entry.toBin ? (
                            <span className="lt-bins">
                              {entry.fromBin || "–"} → {entry.toBin || "–"}
                            </span>
                          ) : null}
                          {entry.link && entry.link.kind !== "lp" ? (
                            <NavLink nav={{ kind: entry.link.kind, key: entry.link.key }}>
                              <Icon name="doc" size={13} /> {entry.link.label}
                            </NavLink>
                          ) : entry.missingDocNo ? (
                            <span className="lt-cellrow">
                              <span className="lt-strike">{entry.missingDocNo}</span>
                              <Pill tone="bad">bulunamadı</Pill>
                            </span>
                          ) : entry.relatedDocument && !otherLp ? (
                            <span className="lt-muted lt-mono">{entry.relatedDocument}</span>
                          ) : null}
                          {otherLp ? <LpChip no={otherLp} onTrace={onTrace} /> : null}
                        </div>
                      </div>
                    </li>
                  );
                })}
              </ol>
            </li>
          ))}
        </ol>
      )}
    </Section>
  );
}

function LedgerSection({ trace }: { trace: TracePayload }) {
  const [showAll, setShowAll] = useState(false);
  const rows = showAll ? trace.itemLedger : trace.itemLedger.slice(0, 8);
  return (
    <Section title="Madde girişleri" aside={<span className="lt-muted">{trace.itemLedger.length}</span>}>
      {trace.itemLedger.length === 0 ? (
        <p className="lt-empty">Bağlı madde girişi yok.</p>
      ) : (
        <ul className="lt-entries">
          {rows.map((entry) => (
            <li key={entry.entryNo} className={`lt-entry${entry.correction || entry.undoneByEntryNo ? " lt-entry--undo" : ""}`}>
              <div className="lt-entry__head">
                <NavLink nav={{ kind: "ile", key: String(entry.entryNo) }} className="lt-strong">
                  {entry.entryNo}
                </NavLink>
                <span className="lt-muted">{formatDate(entry.postingDate)}</span>
                <span className={`lt-entry__qty${entry.qty < 0 ? " lt-neg" : ""}`}>{formatSignedQty(entry.qty)}</span>
              </div>
              <div className="lt-entry__doc">
                {entry.entryType} · {entry.documentType} {entry.documentNo}
                {entry.lotNo ? <span className="lt-muted"> · lot {entry.lotNo}</span> : null}
              </div>
              <div className="lt-entry__nums">
                <span>
                  Kalan <strong>{formatQty(entry.remainingQty)}</strong>
                </span>
                {entry.thisLpQty ? (
                  <span>
                    Bu LP <strong>{formatQty(entry.thisLpQty)}</strong>
                  </span>
                ) : null}
                {entry.linkedLpQty ? (
                  <span>
                    Tüm LP'ler <strong>{formatQty(entry.linkedLpQty)}</strong>
                  </span>
                ) : null}
              </div>
              <div className="lt-chiprow">
                {ledgerBadges(entry).map((badge) => (
                  <Pill key={badge.label} tone={badge.tone}>
                    {badge.label}
                  </Pill>
                ))}
              </div>
            </li>
          ))}
        </ul>
      )}
      {trace.itemLedger.length > 8 ? (
        <button type="button" className="lt-link lt-more" onClick={() => setShowAll(!showAll)}>
          {showAll ? "Daha az göster" : `Tümünü göster (${trace.itemLedger.length})`}
        </button>
      ) : null}
    </Section>
  );
}

function WarehouseSection({ trace }: { trace: TracePayload }) {
  if (trace.warehouseEntries.length === 0) return null;
  return (
    <Section title="Ambar girişleri" aside={<span className="lt-muted">{trace.warehouseEntries.length}</span>}>
      <ul className="lt-entries">
        {trace.warehouseEntries.map((entry) => (
          <li key={entry.entryNo} className="lt-entry">
            <div className="lt-entry__head">
              <NavLink nav={{ kind: "whseEntry", key: String(entry.entryNo) }} className="lt-strong">
                {entry.entryNo}
              </NavLink>
              <span className="lt-muted">{formatDate(entry.registeringDate)}</span>
              <span className={`lt-entry__qty${entry.qty < 0 ? " lt-neg" : ""}`}>{formatSignedQty(entry.qty)}</span>
            </div>
            <div className="lt-entry__doc">
              {entry.entryType} · <span className="lt-mono">{entry.binCode}</span>
              {entry.whseDocumentNo ? ` · ${entry.whseDocumentType} ${entry.whseDocumentNo}` : ""}
              {entry.referenceNo ? <span className="lt-muted"> · {entry.referenceDocument} {entry.referenceNo}</span> : null}
            </div>
          </li>
        ))}
      </ul>
    </Section>
  );
}
