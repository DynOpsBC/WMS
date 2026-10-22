import type { ReactNode } from "react";
import { openNode } from "./bridge";
import { Icon } from "./Icon";
import { docStateMeta, sortInsights, type Tone } from "./model";
import type { Insight, Nav, TraceDocument } from "./types";
import { documentLanes } from "./model";

export function Pill({ tone = "neutral", children, title }: { tone?: Tone; children: ReactNode; title?: string }) {
  return (
    <span className={`lt-pill lt-tone-${tone}`} title={title}>
      {children}
    </span>
  );
}

export function Section({ title, aside, children, id }: { title: string; aside?: ReactNode; children: ReactNode; id?: string }) {
  return (
    <section className="lt-section" aria-labelledby={id}>
      <header className="lt-section__head">
        <h2 id={id}>{title}</h2>
        {aside ? <div className="lt-section__aside">{aside}</div> : null}
      </header>
      <div className="lt-section__body">{children}</div>
    </section>
  );
}

/** BC sayfası açan bağlantı düğmesi (nav yoksa düz metin). */
export function NavLink({ nav, children, className = "" }: { nav: Nav | undefined; children: ReactNode; className?: string }) {
  if (!nav) return <span className={`lt-navtext ${className}`}>{children}</span>;
  return (
    <button type="button" className={`lt-link ${className}`} onClick={() => openNode(nav.kind, nav.key)} title="BC'de aç">
      {children}
    </button>
  );
}

export function LpChip({ no, onTrace, tone = "neutral", suffix }: { no: string; onTrace: (no: string) => void; tone?: Tone; suffix?: ReactNode }) {
  return (
    <button type="button" className={`lt-lpchip lt-tone-${tone}`} onClick={() => onTrace(no)} title={`${no} izlenebilirliğini aç`}>
      <Icon name="box" size={13} />
      <span>{no}</span>
      {suffix}
    </button>
  );
}

export function Insights({ insights }: { insights: Insight[] }) {
  if (insights.length === 0) return null;
  return (
    <ul className="lt-insights" aria-label="Bulgular">
      {sortInsights(insights).map((insight, index) => (
        <li key={`${insight.code}-${index}`} className={`lt-insight lt-insight--${insight.level}`}>
          <span className="lt-insight__mark" aria-hidden="true">
            {insight.level === "error" ? "!" : insight.level === "warning" ? "▲" : "i"}
          </span>
          <span className="lt-insight__text">{insight.text}</span>
          {insight.nav ? (
            <NavLink nav={insight.nav} className="lt-insight__nav">
              Aç
            </NavLink>
          ) : null}
        </li>
      ))}
    </ul>
  );
}

const ROLE_LABELS: Record<string, string> = {
  assigned: "atandığı belge",
  source: "kaynak",
  activity: "LP satırı var",
  ledger: "defter",
  warehouse: "ambar girişi",
  related: "bağlı",
  query: "aranan",
};

export function DocumentFlow({ documents }: { documents: TraceDocument[] }) {
  const lanes = documentLanes(documents);
  if (lanes.length === 0) return <p className="lt-empty">Bağlı belge bulunamadı.</p>;
  return (
    <ol className="lt-flow">
      {lanes.map((lane) => (
        <li key={lane.id} className="lt-flow__lane">
          <div className="lt-flow__label">{lane.label}</div>
          <div className="lt-flow__docs">
            {lane.documents.map((doc) => {
              const state = docStateMeta(doc.state);
              const body = (
                <>
                  <span className="lt-doc__kind">{doc.kindCaption}</span>
                  <span className="lt-doc__no">{doc.no}</span>
                  <span className="lt-doc__meta">
                    {state.label ? <Pill tone={state.tone}>{state.label}</Pill> : null}
                    {ROLE_LABELS[doc.role] ? <span className="lt-doc__role">{ROLE_LABELS[doc.role]}</span> : null}
                  </span>
                  {doc.note ? <span className="lt-doc__note">{doc.note}</span> : null}
                </>
              );
              return doc.nav ? (
                <button key={doc.key} type="button" className={`lt-doc lt-doc--${doc.state}`} onClick={() => openNode(doc.nav!.kind, doc.nav!.key)} title="BC'de aç">
                  {body}
                </button>
              ) : (
                <div key={doc.key} className={`lt-doc lt-doc--${doc.state}`}>
                  {body}
                </div>
              );
            })}
          </div>
        </li>
      ))}
    </ol>
  );
}
