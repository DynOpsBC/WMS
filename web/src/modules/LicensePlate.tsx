import React, { useEffect, useState } from "react";
import * as BcApi from "../lib/bcApi";
import { DocHeader, EmptyState, Field, Modal, Pill, StatusText } from "../ui/primitives";

type Row = Record<string, any>;

export function LicensePlate() {
  const [rows, setRows] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setStatus("Yükleniyor...");
    const filter = search.trim() ? `&$filter=contains(no,'${search.trim()}')` : "";
    const r = await BcApi.get(
      `licensePlates?$top=30${filter}&$select=no,templateCode,status,locationCode,binCode,sscc,parentLpNo,assignedDocumentType,assignedDocumentNo`,
    );
    setLoading(false);
    const arr = r.ok ? BcApi.parseValueArray(r.body) : [];
    setRows(arr);
    setStatus(
      !r.ok
        ? `HATA: LP listesi alınamadı (HTTP ${r.httpCode})`
        : `PASS: ${arr.length} LP (HTTP ${r.httpCode})`,
    );
  }
  useEffect(() => { load(); }, []);

  if (selected) {
    return <LpDetail no={selected} onBack={() => { setSelected(null); load(); }} />;
  }

  return (
    <div>
      <div className="toolbar">
        <button className="primary" onClick={load} disabled={loading}>
          {loading ? "..." : "🔄 Yenile"}
        </button>
        <div style={{ flex: 1, maxWidth: 320 }}>
          <input
            type="text"
            placeholder="LP No ara (örn. LP000)"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && load()}
          />
        </div>
      </div>
      <StatusText status={status} />
      <div className="list">
        {rows.map((d) => (
          <div key={String(d.no)} className="card clickable" onClick={() => setSelected(String(d.no))}>
            <div className="row-between">
              <div className="card-title">{String(d.no)}</div>
              <Pill text={String(d.status ?? "")} tone={String(d.status) === "Built" ? "ok" : "neutral"} />
            </div>
            <div className="card-meta">
              {BcApi.firstValue(d, "templateCode")} · Lokasyon: {BcApi.firstValue(d, "locationCode")}/{BcApi.firstValue(d, "binCode") || "-"}
              <br />
              SSCC: {BcApi.firstValue(d, "sscc") || "-"} · Parent: {BcApi.firstValue(d, "parentLpNo") || "-"}{BcApi.firstValue(d, "assignedDocumentNo") && ` · Atanan: ${BcApi.firstValue(d, "assignedDocumentType")}/${BcApi.firstValue(d, "assignedDocumentNo")}`}
            </div>
          </div>
        ))}
        {rows.length === 0 && !loading && <EmptyState message="Hiç LP yok." />}
      </div>
    </div>
  );
}

function LpDetail({ no, onBack }: { no: string; onBack: () => void }) {
  const [header, setHeader] = useState<Row | null>(null);
  const [lines, setLines] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [showTransfer, setShowTransfer] = useState(false);

  async function reload() {
    setBusy(true);
    const h = await BcApi.get(`licensePlates('${no}')`);
    if (h.ok) setHeader(JSON.parse(h.body));
    const l = await BcApi.get(`licensePlateLines?$filter=lpNo eq '${no}'&$top=200`);
    setLines(l.ok ? BcApi.parseValueArray(l.body) : []);
    setBusy(false);
  }
  useEffect(() => { reload(); }, [no]);

  async function action(name: string, body: string, okMsg: string) {
    setBusy(true);
    setStatus(`${name}…`);
    const r = await BcApi.boundAction("licensePlates", no, name, body);
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
      <button className="ghost" onClick={onBack}>‹ LP Listesi</button>
      <DocHeader
        title={no}
        subtitle={`${BcApi.firstValue(header, "templateCode")} · ${BcApi.firstValue(header, "status")}\nLokasyon: ${BcApi.firstValue(header, "locationCode")}/${BcApi.firstValue(header, "binCode") || "-"} · SSCC: ${BcApi.firstValue(header, "sscc") || "-"}`}
      />
      <StatusText status={status} />
      <h3 style={{ marginTop: 16 }}>Satırlar ({lines.length})</h3>
      <div className="list">
        {lines.map((ln) => (
          <div key={`${ln.lpNo}-${ln.lineNo}`} className="card">
            <div className="card-title">{String(ln.itemNo)}</div>
            <div className="card-meta">
              Qty: {Number(ln.quantity ?? 0)} {BcApi.firstValue(ln, "unitOfMeasureCode")} · Lot: {BcApi.firstValue(ln, "lotNo") || "-"} · Serial: {BcApi.firstValue(ln, "serialNo") || "-"}
            </div>
          </div>
        ))}
        {lines.length === 0 && !busy && <EmptyState message="Bu LP'de satır yok." />}
      </div>
      <div className="actions">
        <button className="outline" disabled={busy} onClick={() => action("stop", JSON.stringify({ printLabel: true }), "LP kapatıldı + etiket")}>
          🔚 Stop
        </button>
        <button className="outline" disabled={busy} onClick={() => action("printLabel", "{}", "Etiket yazdırıldı")}>
          🖨️ Print Label
        </button>
        <button className="outline" disabled={busy} onClick={() => setShowTransfer(true)}>
          ↔️ Transfer
        </button>
      </div>
      {showTransfer && (
        <TransferModal
          onClose={() => setShowTransfer(false)}
          onSubmit={(target) => {
            setShowTransfer(false);
            action("transferAll", JSON.stringify({ targetLpNo: target }), `LP içeriği ${target}'a taşındı`);
          }}
        />
      )}
    </div>
  );
}

function TransferModal({ onClose, onSubmit }: { onClose: () => void; onSubmit: (target: string) => void }) {
  const [target, setTarget] = useState("");
  return (
    <Modal title="LP Transfer" meta="Tüm satırları hedef LP'ye taşı" onClose={onClose}>
      <Field label="Hedef LP No" value={target} onChange={setTarget} placeholder="LP000123" />
      <div className="actions" style={{ borderTop: "none", marginTop: 16 }}>
        <button className="outline" onClick={onClose}>İptal</button>
        <button className="primary" onClick={() => onSubmit(target.trim())} disabled={target.trim().length === 0}>
          Transfer Et
        </button>
      </div>
    </Modal>
  );
}
