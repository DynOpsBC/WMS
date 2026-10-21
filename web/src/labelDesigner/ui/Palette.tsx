// Sol palet: öğeyi etikete sürükle-bırak ya da tıkla (etiketin ortasına eklenir).
import { useState, type DragEvent } from "react";
import type { ElementType, LabelField } from "../model/types";
import { IconBuilding, IconUpload, TypeIcon } from "./icons";

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
  { type: "box", label: "Kutu", hint: "Çerçeve ya da dolu kutu" },
  { type: "image", label: "Resim", hint: "Logo veya simge (siyah-beyaz basılır)" },
];

export function Palette({ fields, defaultCodeField, onAdd, onUploadImage, onRequestLogo, logoPending }: PaletteProps) {
  const [field, setField] = useState(fields[0]?.key ?? "");
  const selectedField = fields.some((f) => f.key === field) ? field : fields[0]?.key ?? "";

  const start = (e: DragEvent, payload: PalettePayload) => {
    e.dataTransfer.setData(DRAG_MIME, JSON.stringify(payload));
    e.dataTransfer.setData("text/plain", payload.type);
    e.dataTransfer.effectAllowed = "copy";
  };

  const payloadFor = (type: ElementType): PalettePayload =>
    type === "barcode" || type === "qr" ? { type, field: defaultCodeField } : { type };

  const sample = fields.find((f) => f.key === selectedField)?.sample ?? "";

  return (
    <aside className="ld-palette" aria-label="Öğeler">
      <h2 className="ld-panel-title">Öğe ekle</h2>
      <p className="ld-muted ld-small">Etikete sürükleyin ya da tıklayın.</p>

      <div className="ld-tool ld-tool-field">
        <div
          className="ld-tool-main"
          draggable
          role="button"
          tabIndex={0}
          title="Veri alanı: BC'den gelen bilgi (ürün no, açıklama…)"
          onDragStart={(e) => start(e, { type: "field", field: selectedField })}
          onClick={() => onAdd({ type: "field", field: selectedField })}
          onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onAdd({ type: "field", field: selectedField }); } }}
        >
          <span className="ld-tool-icon"><TypeIcon type="field" /></span>
          <span className="ld-tool-text">
            <strong>Veri alanı</strong>
            <span className="ld-muted ld-small">Ürün no, açıklama…</span>
          </span>
        </div>
        <select
          className="ld-select ld-tool-select"
          aria-label="Eklenecek veri alanı"
          value={selectedField}
          onChange={(e) => setField(e.currentTarget.value)}
        >
          {fields.map((f) => (
            <option key={f.key} value={f.key}>{f.label}</option>
          ))}
        </select>
        {sample ? <div className="ld-tool-sample" title="Örnek değer">Örnek: {sample}</div> : null}
      </div>

      <div className="ld-tools">
        {TOOLS.map((t) => (
          <div
            key={t.type}
            className="ld-tool ld-tool-main"
            draggable
            role="button"
            tabIndex={0}
            title={t.hint}
            onDragStart={(e) => start(e, payloadFor(t.type))}
            onClick={() => (t.type === "image" ? onUploadImage() : onAdd(payloadFor(t.type)))}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                if (t.type === "image") onUploadImage();
                else onAdd(payloadFor(t.type));
              }
            }}
          >
            <span className="ld-tool-icon"><TypeIcon type={t.type} /></span>
            <span className="ld-tool-text"><strong>{t.label}</strong></span>
          </div>
        ))}
      </div>

      <div className="ld-palette-images">
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-block" onClick={onUploadImage}>
          <IconUpload /> Resim yükle
        </button>
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-block" onClick={onRequestLogo} disabled={logoPending}>
          <IconBuilding /> {logoPending ? "Logo isteniyor…" : "Şirket logosunu getir"}
        </button>
      </div>

      <div className="ld-palette-help ld-small ld-muted">
        <p><kbd>Del</kbd> sil</p>
        <p><kbd>Ctrl</kbd>+<kbd>D</kbd> çoğalt</p>
        <p><kbd>Ctrl</kbd>+<kbd>Z</kbd> geri al</p>
        <p><kbd>R</kbd> 90° döndür</p>
        <p><kbd>←</kbd><kbd>→</kbd> kaydır (<kbd>Shift</kbd> 5 mm)</p>
      </div>
    </aside>
  );
}
