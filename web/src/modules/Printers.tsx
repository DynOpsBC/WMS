import React, { useEffect, useState } from "react";
import * as BcApi from "../lib/bcApi";
import { DocHeader, EmptyState, Field, Modal, Pill, StatusText } from "../ui/primitives";

type Printer = {
  code: string;
  description?: string;
  locationCode?: string;
  format?: string;
  printerHandle?: string;
  hostname?: string;
  port?: number;
  active?: boolean;
  defaultCopies?: number;
  lastSeenAt?: string | null;
  tokenIssuedAt?: string | null;
  comment?: string;
};

const PREF_KEY = "bcwms.defaultPrinter";
export const getDefaultPrinter = (): string => localStorage.getItem(PREF_KEY) ?? "";
export const setDefaultPrinter = (code: string): void => {
  if (code) localStorage.setItem(PREF_KEY, code);
  else localStorage.removeItem(PREF_KEY);
};

export function Printers() {
  const [rows, setRows] = useState<Printer[]>([]);
  const [status, setStatus] = useState("");
  const [loading, setLoading] = useState(false);
  const [editing, setEditing] = useState<Printer | null>(null);
  const [defaultCode, setDefaultCodeState] = useState(getDefaultPrinter());

  async function load() {
    setLoading(true);
    setStatus("Yükleniyor...");
    const r = await BcApi.get(`printers?$top=100&$orderby=code`);
    setLoading(false);
    const arr = r.ok ? (BcApi.parseValueArray(r.body) as unknown as Printer[]) : [];
    setRows(arr);
    setStatus(
      !r.ok
        ? `HATA: Printer listesi alınamadı (HTTP ${r.httpCode}) — ${BcApi.errorMessage(r.body).slice(0, 140)}`
        : arr.length === 0
        ? `EMPTY: kayıtlı printer yok (HTTP ${r.httpCode})`
        : `PASS: ${arr.length} printer (HTTP ${r.httpCode})`,
    );
  }
  useEffect(() => { load(); }, []);

  function chooseDefault(code: string) {
    setDefaultPrinter(code);
    setDefaultCodeState(code);
  }

  async function generateToken(p: Printer) {
    if (!confirm(`${p.code} için yeni bir agent token üretilecek. Mevcut agent'lar yeniden yapılandırılana kadar çalışmayacak. Devam?`)) return;
    const r = await BcApi.boundAction("printers", `'${p.code}'`, "generateToken", "{}");
    if (r.ok) {
      const token = BcApi.scalarValue(r.body) || r.body;
      alert(`Token (yalnızca şimdi gösterilir):\n\n${token}`);
      load();
    } else {
      alert(`HATA: ${BcApi.errorMessage(r.body)}`);
    }
  }

  async function testPrint(p: Printer) {
    const r = await BcApi.boundAction("printers", `'${p.code}'`, "testPrint", "{}");
    if (r.ok) alert(`Self-test job ${p.code} için kuyruğa alındı.`);
    else alert(`HATA: ${BcApi.errorMessage(r.body)}`);
  }

  return (
    <div>
      <DocHeader
        title="🖨 Yazıcılar"
        subtitle="Self-Hosted Print Bridge — register printers, generate agent tokens, set the default for this workstation."
      />
      <div className="toolbar">
        <button className="primary" onClick={load} disabled={loading}>{loading ? "..." : "🔄 Yenile"}</button>
        <button onClick={() => setEditing({ code: "", active: true, format: "ZPL", port: 9100, defaultCopies: 1 })}>+ Yeni Printer</button>
      </div>
      <StatusText status={status} />
      <div className="list">
        {rows.length === 0 && status.startsWith("EMPTY") && (
          <EmptyState message="Henüz printer yok — Yeni Printer ile başlayın, token üretip lokal agent'ı yapılandırın." />
        )}
        {rows.map((p) => (
          <div key={p.code} className="card">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div>
                <div style={{ fontWeight: 600 }}>
                  {p.code} {defaultCode === p.code && <Pill text="Default" tone="ok" />}
                  {!p.active && <Pill text="Pasif" tone="warn" />}
                </div>
                <div style={{ fontSize: 12, color: "var(--text-muted)" }}>
                  {p.description ?? ""} · {p.format ?? "-"} · {p.printerHandle ?? p.hostname ?? "-"} · son aktiflik {p.lastSeenAt ?? "—"}
                </div>
              </div>
              <div style={{ display: "flex", gap: 6 }}>
                <button onClick={() => chooseDefault(p.code)}>{defaultCode === p.code ? "✓ Default" : "Default yap"}</button>
                <button onClick={() => setEditing(p)}>Düzenle</button>
                <button onClick={() => generateToken(p)}>🔑 Token</button>
                <button onClick={() => testPrint(p)}>🧪 Test</button>
              </div>
            </div>
          </div>
        ))}
      </div>
      {editing && (
        <PrinterEditor
          row={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load(); }}
        />
      )}
    </div>
  );
}

function PrinterEditor({ row, onClose, onSaved }: { row: Printer; onClose: () => void; onSaved: () => void }) {
  const isNew = !row.code || row.code.length === 0;
  const [draft, setDraft] = useState<Printer>({ ...row });
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");

  async function save() {
    if (!draft.code) { setMsg("Code zorunlu"); return; }
    setBusy(true);
    setMsg("");
    const body = JSON.stringify({
      code: draft.code,
      description: draft.description ?? "",
      locationCode: draft.locationCode ?? "",
      format: draft.format ?? "ZPL",
      printerHandle: draft.printerHandle ?? "",
      hostname: draft.hostname ?? "",
      port: draft.port ?? 9100,
      active: draft.active ?? true,
      defaultCopies: draft.defaultCopies ?? 1,
      comment: draft.comment ?? "",
    });
    const r = isNew
      ? await BcApi.post("printers", body)
      : await BcApi.patch(`printers('${draft.code}')`, body);
    setBusy(false);
    if (r.ok) onSaved();
    else setMsg(BcApi.errorMessage(r.body).slice(0, 200));
  }

  return (
    <Modal title={isNew ? "Yeni Printer" : `Printer ${row.code}`} onClose={onClose}>
      <Field label="Code" value={draft.code} onChange={(v) => setDraft({ ...draft, code: v.toUpperCase() })} />
      <Field label="Açıklama" value={draft.description ?? ""} onChange={(v) => setDraft({ ...draft, description: v })} />
      <Field label="Location Code" value={draft.locationCode ?? ""} onChange={(v) => setDraft({ ...draft, locationCode: v.toUpperCase() })} />
      <div>
        <label className="field">Format</label>
        <select
          aria-label="Format"
          value={draft.format ?? "ZPL"}
          onChange={(e) => setDraft({ ...draft, format: e.target.value })}
        >
          <option value="ZPL">ZPL (Zebra)</option>
          <option value="PDF">PDF</option>
          <option value="ESCPOS">ESC/POS</option>
          <option value="RAW">Raw</option>
        </select>
      </div>
      <Field label="Printer Handle (OS adı)" value={draft.printerHandle ?? ""} onChange={(v) => setDraft({ ...draft, printerHandle: v })} />
      <Field label="Hostname / IP" value={draft.hostname ?? ""} onChange={(v) => setDraft({ ...draft, hostname: v })} />
      <Field label="Port" type="number" value={String(draft.port ?? 9100)} onChange={(v) => setDraft({ ...draft, port: Number(v) })} />
      <Field label="Default Copies" type="number" value={String(draft.defaultCopies ?? 1)} onChange={(v) => setDraft({ ...draft, defaultCopies: Number(v) })} />
      <div>
        <label className="field" htmlFor="printer-active">Aktif</label>
        <input
          id="printer-active"
          type="checkbox"
          checked={draft.active ?? true}
          onChange={(e) => setDraft({ ...draft, active: e.target.checked })}
        />
      </div>
      <Field label="Not" value={draft.comment ?? ""} onChange={(v) => setDraft({ ...draft, comment: v })} />
      {msg && <div style={{ color: "var(--text-danger)", fontSize: 12 }}>{msg}</div>}
      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
        <button onClick={onClose}>Vazgeç</button>
        <button className="primary" onClick={save} disabled={busy}>{busy ? "..." : "Kaydet"}</button>
      </div>
    </Modal>
  );
}
