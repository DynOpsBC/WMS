import React, { useEffect, useState } from "react";
import * as BcApi from "../lib/bcApi";
import { DocHeader, EmptyState, Pill, StatusText } from "../ui/primitives";

type Row = Record<string, any>;

export function Count() {
  const [rows, setRows] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setStatus("Yükleniyor...");
    const r = await BcApi.get(
      "countSheets?$top=30&$select=no,locationCode,status,mode,createdDateTime",
    );
    setLoading(false);
    const arr = r.ok ? BcApi.parseValueArray(r.body) : [];
    setRows(arr);
    setStatus(
      !r.ok
        ? `HATA: Count listesi alınamadı (HTTP ${r.httpCode})`
        : arr.length === 0
        ? `EMPTY: Sayım yok (HTTP ${r.httpCode})`
        : `PASS: ${arr.length} sayfa (HTTP ${r.httpCode})`,
    );
  }
  useEffect(() => { load(); }, []);

  if (selected) {
    return <CountDocument no={selected} onBack={() => { setSelected(null); load(); }} />;
  }

  return (
    <div>
      <div className="toolbar">
        <button className="primary" onClick={load} disabled={loading}>{loading ? "..." : "🔄 Yenile"}</button>
      </div>
      <StatusText status={status} />
      <div className="list">
        {rows.map((d) => (
          <div key={String(d.no)} className="card clickable" onClick={() => setSelected(String(d.no))}>
            <div className="row-between">
              <div className="card-title">{String(d.no)}</div>
              <Pill text={String(d.status ?? "") + " · " + String(d.mode ?? "")} tone="neutral" />
            </div>
            <div className="card-meta">
              Lokasyon: {BcApi.firstValue(d, "locationCode")} · Oluşturma: {BcApi.firstValue(d, "createdDateTime") || "-"}
            </div>
          </div>
        ))}
        {rows.length === 0 && !loading && <EmptyState message="Açık sayım yok." />}
      </div>
    </div>
  );
}

function CountDocument({ no, onBack }: { no: string; onBack: () => void }) {
  const [header, setHeader] = useState<Row | null>(null);
  const [lines, setLines] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  async function reload() {
    setBusy(true);
    const h = await BcApi.get(`countSheets('${no}')`);
    if (h.ok) setHeader(JSON.parse(h.body));
    const l = await BcApi.get(`countSheetLines?$filter=sheetNo eq '${no}'&$top=200`);
    setLines(l.ok ? BcApi.parseValueArray(l.body) : []);
    setBusy(false);
  }
  useEffect(() => { reload(); }, [no]);

  async function action(name: string, body: string, okMsg: string) {
    setBusy(true);
    setStatus(`${name}…`);
    const r = await BcApi.boundAction("countSheets", no, name, body);
    setBusy(false);
    setStatus(
      r.ok
        ? `PASS: ${okMsg} (HTTP ${r.httpCode})`
        : `HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})`,
    );
    if (r.ok) reload();
  }

  return (
    <div>
      <button className="ghost" onClick={onBack}>‹ Sayfa Listesi</button>
      <DocHeader
        title={no}
        subtitle={`Lokasyon: ${BcApi.firstValue(header, "locationCode")} · Mode: ${BcApi.firstValue(header, "mode")} · ${BcApi.firstValue(header, "status")}`}
      />
      <StatusText status={status} />
      <h3 style={{ marginTop: 16 }}>Satırlar ({lines.length})</h3>
      <div className="list">
        {lines.map((ln) => (
          <div key={String(ln.lineNo)} className="card">
            <div className="card-title">{String(ln.itemNo)} · Bin: {BcApi.firstValue(ln, "binCode")}</div>
            <div className="card-meta">
              Sistem: {Number(ln.systemQty ?? 0)} · Sayılan: {Number(ln.countedQty ?? 0)} · Variance: {Number(ln.variance ?? 0)}
            </div>
          </div>
        ))}
        {lines.length === 0 && !busy && <EmptyState message="Bu sayımda satır yok." />}
      </div>
      <div className="actions">
        <button className="outline" disabled={busy} onClick={() => action("recount", "{}", "Recount tetiklendi")}>
          🔁 Recount
        </button>
        <button className="primary big" disabled={busy} onClick={() => action("post", "{}", "Sayım post edildi")}>
          ✅ Post
        </button>
      </div>
    </div>
  );
}
