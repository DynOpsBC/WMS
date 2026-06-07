import React, { useEffect, useState } from "react";
import * as BcApi from "../lib/bcApi";
import { DocHeader, EmptyState, Modal, NumberField, Pill, StatusText } from "../ui/primitives";

type Row = Record<string, any>;

export function Picking() {
  const [rows, setRows] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setStatus("Yükleniyor...");
    const r = await BcApi.get("picks?$top=30&$select=no,locationCode,assignedUserId,status,sourceNo,dueDate,percentComplete");
    setLoading(false);
    const arr = r.ok ? BcApi.parseValueArray(r.body) : [];
    setRows(arr);
    setStatus(
      !r.ok
        ? `HATA: Pick listesi alınamadı (HTTP ${r.httpCode})`
        : arr.length === 0
        ? `EMPTY: Açık pick yok (HTTP ${r.httpCode})`
        : `PASS: ${arr.length} pick (HTTP ${r.httpCode})`,
    );
  }
  useEffect(() => { load(); }, []);

  if (selected) {
    return <PickDocument no={selected} onBack={() => { setSelected(null); load(); }} />;
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
              <Pill text={String(d.status ?? "")} tone="neutral" />
            </div>
            <div className="card-meta">
              Lokasyon: {BcApi.firstValue(d, "locationCode")} · Atanan: {BcApi.firstValue(d, "assignedUserId") || "-"} · Kaynak: {BcApi.firstValue(d, "sourceNo") || "-"}
            </div>
          </div>
        ))}
        {rows.length === 0 && !loading && <EmptyState message="Açık pick yok." />}
      </div>
    </div>
  );
}

function PickDocument({ no, onBack }: { no: string; onBack: () => void }) {
  const [header, setHeader] = useState<Row | null>(null);
  const [lines, setLines] = useState<Row[]>([]);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [qtyLine, setQtyLine] = useState<Row | null>(null);

  async function reload() {
    setBusy(true);
    const h = await BcApi.get(`picks('${no}')`);
    if (h.ok) setHeader(JSON.parse(h.body));
    const l = await BcApi.get(`pickLines?$filter=no eq '${no}'&$top=200`);
    setLines(l.ok ? BcApi.parseValueArray(l.body) : []);
    setBusy(false);
  }
  useEffect(() => { reload(); }, [no]);

  async function action(name: string, body: string, okMsg: string) {
    setBusy(true);
    setStatus(`${name}…`);
    const r = await BcApi.boundAction("picks", no, name, body);
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
      <button className="ghost" onClick={onBack}>‹ Pick Listesi</button>
      <DocHeader
        title={no}
        subtitle={`Lokasyon: ${BcApi.firstValue(header, "locationCode")} · Atanan: ${BcApi.firstValue(header, "assignedUserId") || "-"}\nDurum: ${BcApi.firstValue(header, "status")}`}
      />
      <StatusText status={status} />
      <h3 style={{ marginTop: 16 }}>Satırlar ({lines.length})</h3>
      <div className="list">
        {lines.map((ln) => (
          <div key={String(ln.lineNo)} className="card clickable" onClick={() => setQtyLine(ln)}>
            <div className="card-title">{String(ln.itemNo)}</div>
            <div className="card-meta">
              Action: {BcApi.firstValue(ln, "actionType")} · Bin: {BcApi.firstValue(ln, "binCode")} · İşlenecek: {Number(ln.qtyToHandle ?? 0)} / {Number(ln.qty ?? 0)}
            </div>
          </div>
        ))}
        {lines.length === 0 && !busy && <EmptyState message="Bu pick'te satır yok." />}
      </div>
      <div className="actions">
        <button className="outline" disabled={busy} onClick={() => action("assignToMe", "{}", "Pick atandı")}>
          ✋ Assign to Me
        </button>
        <button className="primary big" disabled={busy} onClick={() => action("register", "{}", "Pick register edildi")}>
          ✅ Register Pick
        </button>
      </div>
      {qtyLine && (
        <PickQtyModal
          line={qtyLine}
          onClose={() => setQtyLine(null)}
          onSubmit={async (qty) => {
            setQtyLine(null);
            setBusy(true);
            setStatus("Satır güncelleniyor...");
            const actType = BcApi.firstValue(qtyLine, "activityType") || "Pick";
            const r = await BcApi.patch(
              `pickLines(activityType='${actType}',no='${no}',lineNo=${qtyLine.lineNo})`,
              JSON.stringify({ qtyToHandle: qty }),
            );
            setBusy(false);
            setStatus(
              r.ok
                ? `PASS: Satır güncellendi qty=${qty} (HTTP ${r.httpCode})`
                : `HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})`,
            );
            if (r.ok) reload();
          }}
        />
      )}
    </div>
  );
}

function PickQtyModal({
  line,
  onClose,
  onSubmit,
}: {
  line: Row;
  onClose: () => void;
  onSubmit: (qty: number) => void;
}) {
  const [qty, setQty] = useState(String(Number(line.qtyToHandle ?? line.qty ?? 1)));
  return (
    <Modal
      title="Toplama Miktarı"
      meta={`Item: ${line.itemNo} · Bin: ${line.binCode ?? "-"}`}
      onClose={onClose}
    >
      <NumberField label="İşlenecek qty" value={qty} onChange={setQty} />
      <div className="actions" style={{ borderTop: "none", marginTop: 16 }}>
        <button className="outline" onClick={onClose}>İptal</button>
        <button className="primary" onClick={() => onSubmit(Number(qty) || 0)}>Onayla</button>
      </div>
    </Modal>
  );
}
