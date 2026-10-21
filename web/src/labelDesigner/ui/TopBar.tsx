// Üst çubuk: etiket ölçüsü, dpi, geri al/ileri al, kaydet, test baskı, Labelary kontrolü.
import { KIND_LABELS } from "../model/design";
import { LIMITS, type Dpi, type LabelDesign } from "../model/types";
import { NumberField } from "./controls";
import { IconPrinter, IconRedo, IconSave, IconSearch, IconTemplates, IconUndo } from "./icons";

export const SIZE_PRESETS: { w: number; h: number }[] = [
  { w: 80, h: 40 },
  { w: 100, h: 50 },
  { w: 100, h: 100 },
  { w: 60, h: 40 },
  { w: 50, h: 30 },
];

interface TopBarProps {
  design: LabelDesign;
  readOnly: boolean;
  dirty: boolean;
  canUndo: boolean;
  canRedo: boolean;
  previewBusy: boolean;
  onUndo: () => void;
  onRedo: () => void;
  onSize: (w: number, h: number) => void;
  onDpi: (dpi: Dpi) => void;
  onSave: () => void;
  onTestPrint: () => void;
  onPreview: () => void;
  onTemplates: () => void;
}

export function TopBar(p: TopBarProps) {
  const { design } = p;
  const presetKey = SIZE_PRESETS.find((s) => s.w === design.widthMm && s.h === design.heightMm);
  const sizeValue = presetKey ? `${presetKey.w}x${presetKey.h}` : "custom";
  return (
    <header className="ld-topbar">
      <div className="ld-brand">
        <span className="ld-brand-title">Etiket Tasarımcısı</span>
        <span className="ld-brand-sub">
          {design.code ? <span className="ld-code">{design.code}</span> : null}
          <span className="ld-muted">{KIND_LABELS[design.kind]}</span>
          {p.readOnly ? <span className="ld-pill ld-pill-warn">Salt okunur</span> : p.dirty ? <span className="ld-pill">Kaydedilmedi</span> : <span className="ld-pill ld-pill-ok">Kayıtlı</span>}
        </span>
      </div>

      <div className="ld-topbar-group" aria-label="Etiket ölçüsü">
        <label className="ld-top-label" htmlFor="ld-size">Etiket</label>
        <select
          id="ld-size"
          className="ld-select ld-select-compact"
          value={sizeValue}
          disabled={p.readOnly}
          onChange={(e) => {
            const v = e.currentTarget.value;
            if (v === "custom") return;
            const [w, h] = v.split("x").map(Number);
            p.onSize(w, h);
          }}
        >
          {SIZE_PRESETS.map((s) => (
            <option key={`${s.w}x${s.h}`} value={`${s.w}x${s.h}`}>{s.w} × {s.h} mm</option>
          ))}
          <option value="custom">Özel ölçü</option>
        </select>
        <fieldset className="ld-fieldset ld-size-fields" disabled={p.readOnly}>
          <NumberField value={design.widthMm} min={LIMITS.minSizeMm} max={LIMITS.widthMm} step={1} width={88} ariaLabel="Genişlik (mm)" onChange={(v) => p.onSize(v, design.heightMm)} />
          <span className="ld-muted">×</span>
          <NumberField value={design.heightMm} min={LIMITS.minSizeMm} max={LIMITS.heightMm} step={1} width={88} ariaLabel="Yükseklik (mm)" onChange={(v) => p.onSize(design.widthMm, v)} />
        </fieldset>
        <select
          className="ld-select ld-select-compact"
          aria-label="Yazıcı çözünürlüğü"
          title="Yazıcının çözünürlüğü (çoğu Zebra 203 dpi)"
          value={design.dpi}
          disabled={p.readOnly}
          onChange={(e) => p.onDpi(Number(e.currentTarget.value) as Dpi)}
        >
          <option value={203}>203 dpi</option>
          <option value={300}>300 dpi</option>
          {design.dpi === 600 ? <option value={600}>600 dpi</option> : null}
        </select>
      </div>

      <div className="ld-topbar-group">
        <button type="button" className="ld-btn ld-btn-secondary" onClick={p.onTemplates} disabled={p.readOnly} title="Hazır tasarımlardan birini seçin">
          <IconTemplates /> Hazır şablonlar
        </button>
      </div>

      <div className="ld-topbar-group">
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-icon" onClick={p.onUndo} disabled={!p.canUndo || p.readOnly} title="Geri Al (Ctrl+Z)" aria-label="Geri Al">
          <IconUndo />
        </button>
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-icon" onClick={p.onRedo} disabled={!p.canRedo || p.readOnly} title="İleri Al (Ctrl+Y)" aria-label="İleri Al">
          <IconRedo />
        </button>
      </div>

      <div className="ld-topbar-spacer" />

      <div className="ld-topbar-group">
        <button type="button" className="ld-btn ld-btn-ghost" onClick={p.onPreview} disabled={p.previewBusy} title="Labelary ile yazıcının basacağı gerçek görüntüyü örnek verilerle gösterir">
          <IconSearch /> Gerçek çıktıyı kontrol et (Labelary)
        </button>
        <button type="button" className="ld-btn ld-btn-secondary" onClick={p.onTestPrint} title="Kaydedilmemiş tasarımı örnek verilerle yazıcıya gönderir">
          <IconPrinter /> Test Baskı
        </button>
        <button type="button" className="ld-btn ld-btn-primary" onClick={p.onSave} disabled={p.readOnly} title="Kaydet (Ctrl+S)">
          <IconSave /> Kaydet
        </button>
      </div>
    </header>
  );
}
