// Sol panel: öğeler (metin, barkod, QR, çizgi, kutu, resim) ve bu etiket türünün veri alanları.
// Etikete sürükle-bırak ya da tıkla (etiketin ortasına eklenir).
import { useMemo, useState, type DragEvent } from "react";
import type { ElementType, LabelField } from "../model/types";
import { IconBuilding, IconSearch, IconUpload, TypeIcon } from "./icons";

export const DRAG_MIME = "application/x-dops-label-element";

export interface PalettePayload {
  type: ElementType;
  field?: string;
}

interface PaletteProps {
  fields: LabelField[];
  defaultCodeField: string;
  onAdd: (payload: PalettePayload) => void;
  onUploadImage: () => void;
  onRequestLogo: () => void;
  logoPending: boolean;
}

interface ToolDef {
  type: ElementType;
  label: string;
  hint: string;
}

const TOOLS: ToolDef[] = [
  { type: "text", label: "Metin", hint: "Sabit yazı (ör. “ÜRÜN ETİKETİ”)" },
  { type: "barcode", label: "Barkod", hint: "Code128 / EAN-13 / GS1-128" },
  { type: "qr", label: "QR", hint: "Karekod" },
  { type: "line", label: "Çizgi", hint: "Yatay veya dikey çizgi" },
  { type: "box", label: "Kutu", hint: "Çerçeve ya da dolu (siyah) kutu" },
  { type: "image", label: "Resim", hint: "Logo veya simge (siyah-beyaz basılır)" },
];

export function Palette({ fields, defaultCodeField, onAdd, onUploadImage, onRequestLogo, logoPending }: PaletteProps) {
  const [query, setQuery] = useState("");
  const shown = useMemo(() => {
    const q = query.trim().toLocaleLowerCase("tr");
    if (!q) return fields;
    return fields.filter((f) => `${f.label} ${f.key} ${f.sample}`.toLocaleLowerCase("tr").includes(q));
  }, [fields, query]);

  const start = (e: DragEvent, payload: PalettePayload) => {
    e.dataTransfer.setData(DRAG_MIME, JSON.stringify(payload));
    e.dataTransfer.setData("text/plain", payload.type);
    e.dataTransfer.effectAllowed = "copy";
  };

  const payloadFor = (type: ElementType): PalettePayload =>
    type === "barcode" || type === "qr" ? { type, field: defaultCodeField } : { type };

  const activate = (payload: PalettePayload) => (payload.type === "image" ? onUploadImage() : onAdd(payload));

  return (
    <aside className="ld-palette" aria-label="Öğeler ve alanlar">
      <section className="ld-pal-section">
        <h2 className="ld-pal-title">Öğeler</h2>
        <div className="ld-tools">
          {TOOLS.map((t) => (
            <div
              key={t.type}
              className="ld-tool ld-tool-main"
              draggable
              role="button"
              tabIndex={0}
              title={`${t.hint} — sürükleyin ya da tıklayın`}
              onDragStart={(e) => start(e, payloadFor(t.type))}
              onClick={() => activate(payloadFor(t.type))}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  activate(payloadFor(t.type));
                }
              }}
            >
              <span className="ld-tool-icon"><TypeIcon type={t.type} size={18} /></span>
              <span className="ld-tool-label">{t.label}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="ld-pal-section ld-pal-fields">
        <h2 className="ld-pal-title">
          Veri alanları <span className="ld-pal-count">{fields.length}</span>
        </h2>
        {fields.length > 8 ? (
          <label className="ld-search">
            <IconSearch size={14} />
            <input type="search" value={query} placeholder="Alan ara" aria-label="Alan ara" onChange={(e) => setQuery(e.currentTarget.value)} />
          </label>
        ) : null}
        <ul className="ld-field-list">
          {shown.map((f) => (
            <li key={f.key}>
              <div
                className="ld-field-item"
                draggable
                role="button"
                tabIndex={0}
                title={`${f.label} (${f.key}) — sürükleyin ya da tıklayın`}
                onDragStart={(e) => start(e, { type: "field", field: f.key })}
                onClick={() => onAdd({ type: "field", field: f.key })}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onAdd({ type: "field", field: f.key });
                  }
                }}
              >
                <span className="ld-field-name">{f.label}</span>
                {f.sample ? <span className="ld-field-sample">{f.sample}</span> : null}
              </div>
            </li>
          ))}
          {shown.length === 0 ? <li className="ld-muted ld-small ld-field-empty">Eşleşen alan yok.</li> : null}
        </ul>
      </section>

      <section className="ld-pal-section">
        <h2 className="ld-pal-title">Resim</h2>
        <div className="ld-palette-images">
          <button type="button" className="ld-btn ld-btn-ghost ld-btn-sm ld-btn-block" onClick={onUploadImage}>
            <IconUpload size={16} /> Resim yükle
          </button>
          <button type="button" className="ld-btn ld-btn-ghost ld-btn-sm ld-btn-block" onClick={onRequestLogo} disabled={logoPending}>
            <IconBuilding size={16} /> {logoPending ? "Logo isteniyor…" : "Şirket logosu"}
          </button>
        </div>
      </section>

      <details className="ld-palette-help ld-small ld-muted">
        <summary>Kısayollar</summary>
        <p><kbd>Del</kbd> sil · <kbd>Ctrl</kbd>+<kbd>D</kbd> çoğalt</p>
        <p><kbd>Ctrl</kbd>+<kbd>Z</kbd> / <kbd>Y</kbd> geri / ileri al</p>
        <p><kbd>R</kbd> 90° döndür</p>
        <p><kbd>←</kbd><kbd>→</kbd> ızgara kadar kaydır, <kbd>Shift</kbd> 5 mm, <kbd>Alt</kbd> 1 nokta</p>
        <p><kbd>Alt</kbd> ile sürükleme ızgaraya yapışmaz</p>
      </details>
    </aside>
  );
}
