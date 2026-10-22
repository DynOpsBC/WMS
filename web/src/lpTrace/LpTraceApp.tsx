import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { invokeBc, requestSearch, useHostState } from "./bridge";
import { Icon } from "./Icon";
import { LpView } from "./LpView";
import { cleanSearch, formatDateTime, modeLabel, normalizeTrace, truncatedSections } from "./model";
import { TreeView } from "./TreeView";
import type { TracePayload } from "./types";

const EXAMPLES = [
  { text: "LP001737", hint: "LP" },
  { text: "A102511", hint: "lot" },
  { text: "AB.01740", hint: "madde" },
  { text: "RE001191", hint: "mal kabul" },
  { text: "PU001130", hint: "silinmiş belge" },
];

export function LpTraceApp() {
  const host = useHostState();
  const trace = useMemo<TracePayload>(() => normalizeTrace(host.payload), [host.payload]);
  const [text, setText] = useState("");
  const [recent, setRecent] = useState<string[]>([]);
  const lastQuery = useRef("");
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    invokeBc("ControlReady", []);
  }, []);

  // BC yeni sonuç gönderince arama kutusunu ve son aramaları güncelle.
  useEffect(() => {
    if (!trace.query || trace.query === lastQuery.current) return;
    lastQuery.current = trace.query;
    setText(trace.query);
    if (trace.mode !== "notFound" && trace.mode !== "error") {
      setRecent((current) => [trace.query, ...current.filter((item) => item !== trace.query)].slice(0, 6));
    }
    rootRef.current?.scrollTo?.({ top: 0 });
  }, [trace]);

  const search = (value: string) => {
    const cleaned = cleanSearch(value);
    if (!cleaned) return;
    setText(cleaned);
    requestSearch(cleaned);
  };

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    search(text);
  };

  const truncated = truncatedSections(trace.truncated);

  return (
    <div className="lt-root" ref={rootRef}>
      <header className="lt-top">
        <div className="lt-brand">
          <span className="lt-brand__icon">
            <Icon name="layers" size={18} />
          </span>
          <div>
            <div className="lt-brand__title">LP İzlenebilirlik</div>
            <div className="lt-brand__sub">LP, lot, madde ya da belge no ile ara</div>
          </div>
        </div>
        <form className="lt-search" onSubmit={onSubmit} role="search">
          <input
            className="lt-search__input"
            value={text}
            onChange={(event) => setText(event.target.value)}
            placeholder="ör. LP001737, A102452, AB.01740, RE001191"
            aria-label="Arama"
            spellCheck={false}
            autoComplete="off"
          />
          <button type="submit" className="lt-btn" disabled={host.busy}>
            {host.busy ? "Aranıyor…" : "Ara"}
          </button>
        </form>
        {recent.length > 1 ? (
          <div className="lt-recent" aria-label="Son aramalar">
            {recent.slice(1).map((item) => (
              <button key={item} type="button" className="lt-recent__chip" onClick={() => search(item)}>
                {item}
              </button>
            ))}
          </div>
        ) : null}
      </header>

      <main className={`lt-content${host.busy ? " lt-content--busy" : ""}`} aria-busy={host.busy}>
        {trace.mode === "lp" ? <LpView trace={trace} onTrace={search} /> : null}
        {trace.mode === "lot" || trace.mode === "item" || trace.mode === "document" ? <TreeView trace={trace} onTrace={search} /> : null}
        {trace.mode === "empty" ? <EmptyState onSearch={search} /> : null}
        {trace.mode === "notFound" ? (
          <div className="lt-card lt-state">
            <h2>“{trace.query}” bulunamadı</h2>
            <p>LP numarası, SSCC, lot, madde ya da belge numarası (mal kabul, irsaliye, yerine koyma, toplama, sevkiyat, üretim emri) deneyin.</p>
          </div>
        ) : null}
        {trace.mode === "error" ? (
          <div className="lt-card lt-state lt-state--error">
            <h2>Veri alınamadı</h2>
            <p>{trace.message}</p>
          </div>
        ) : null}
        {trace.mode !== "empty" && trace.generatedAt ? (
          <footer className="lt-foot">
            {modeLabel(trace.mode) ? `${modeLabel(trace.mode)} araması · ` : ""}
            {formatDateTime(trace.generatedAt)}
            {truncated.length ? <span className="lt-foot__warn"> · Sınır aşıldı, kısaltıldı: {truncated.join(", ")}</span> : null}
          </footer>
        ) : null}
      </main>
    </div>
  );
}

function EmptyState({ onSearch }: { onSearch: (text: string) => void }) {
  return (
    <div className="lt-card lt-state lt-welcome">
      <h2>Bir LP'nin hikâyesini izleyin</h2>
      <p>
        LP numarası girince bugünkü durumu, içeriği (hangi kaynaktan geldiği), hareket geçmişi, bağlı madde/ambar girişleri ve belgeler tek ekranda
        görünür. Lot, madde ya da belge numarası girince LP ağacı ve BC kalan miktarıyla karşılaştırma gelir.
      </p>
      <div className="lt-examples">
        {EXAMPLES.map((example) => (
          <button key={example.text} type="button" className="lt-example" onClick={() => onSearch(example.text)}>
            <strong>{example.text}</strong>
            <span>{example.hint}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
