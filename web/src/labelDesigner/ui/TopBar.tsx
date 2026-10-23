// Üst çubuk (tek satır): tasarım adı + durum | etiket ölçüsü + dpi | şablonlar, geri/ileri al |
// Önizle (Labelary), Test baskı, Kaydet.
import { KIND_LABELS } from "../model/design";
import { LIMITS, type Dpi, type LabelDesign } from "../model/types";
import { formatDecimal } from "../model/units";
import { NumberField } from "./controls";
import { IconPrinter, IconRedo, IconSave, IconSearch, IconTemplates, IconUndo } from "./icons";

export const SIZE_PRESETS: { w: number; h: number; note?: string }[] = [
  { w: 80, h: 40 },
  { w: 100, h: 50 },
  { w: 101.6, h: 50.8, note: "4 × 2 inç" },
  { w: 100, h: 100 },
  { w: 100, h: 150, note: "A6" },
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
  /** Hazır ölçü seçildi: öğeler yeni ölçüye oranlanır. */
  onPreset: (w: number, h: number) => void;
  /** Elle girilen ölçü: öğeler yerinde kalır (taşan öğe kırmızı gösterilir). */
  onSize: (w: number, h: number) => void;
  onDpi: (dpi: Dpi) => void;
  onSave: () => void;
  onTestPrint: () => void;
  onPreview: () => void;
  onTemplates: () => void;
}

const presetValue = (w: number, h: number) => `${w}x${h}`;

export function TopBar(p: TopBarProps) {
  const { design } = p;
  const preset = SIZE_PRESETS.find((s) => s.w === design.widthMm && s.h === design.heightMm);
  const sizeValue = preset ? presetValue(preset.w, preset.h) : "custom";
  return (
    <header className="ld-topbar">
      <div className="ld-brand">
        <span className="ld-brand-title">Etiket tasarımı</span>
        <span className="ld-brand-sub">
          {design.code ? <span className="ld-code">{design.code}</span> : null}
          <span className="ld-muted">{KIND_LABELS[design.kind]}</span>
          {p.readOnly ? (
            <span className="ld-pill ld-pill-warn">Salt okunur</span>
          ) : p.dirty ? (
            <span className="ld-pill">Kaydedilmedi</span>
          ) : (
            <span className="ld-pill ld-pill-ok">Kayıtlı</span>
          )}
        </span>
      </div>

      <div className="ld-sizebox" role="group" aria-label="Etiket ölçüsü">
        <select
          id="ld-size"
          className="ld-select ld-select-compact ld-size-select"
          value={sizeValue}
          disabled={p.readOnly}
          title="Hazır ölçü: öğeler yeni ölçüye oranlanır (Geri Al ile döner)"
          aria-label="Hazır etiket ölçüsü"
          onChange={(e) => {
            const v = e.currentTarget.value;
            const s = SIZE_PRESETS.find((x) => presetValue(x.w, x.h) === v);
            if (s) p.onPreset(s.w, s.h);
          }}
        >
          {SIZE_PRESETS.map((s) => (
            <option key={presetValue(s.w, s.h)} value={presetValue(s.w, s.h)}>
              {formatDecimal(s.w)} × {formatDecimal(s.h)} mm{s.note ? ` (${s.note})` : ""}
            </option>
          ))}
          <option value="custom">Özel ölçü</option>
        </select>
        <fieldset className="ld-fieldset ld-size-fields" disabled={p.readOnly}>
          <NumberField value={design.widthMm} min={LIMITS.minSizeMm} max={LIMITS.widthMm} step={1} width={64} suffix="" ariaLabel="Genişlik (mm)" onChange={(v) => p.onSize(v, design.heightMm)} />
          <span className="ld-muted">×</span>
          <NumberField value={design.heightMm} min={LIMITS.minSizeMm} max={LIMITS.heightMm} step={1} width={84} suffix="mm" ariaLabel="Yükseklik (mm)" onChange={(v) => p.onSize(design.widthMm, v)} />
        </fieldset>
        <select
          className="ld-select ld-select-compact"
          aria-label="Yazıcı çözünürlüğü"
          title="Yazıcının çözünürlüğü. Zebra ZD230 / ZD220 / ZQ630 = 203 dpi. Yanlış dpi etiketi yanlış ölçüde basar."
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
        <button type="button" className="ld-btn ld-btn-ghost" onClick={p.onTemplates} disabled={p.readOnly} title="Hazır tasarımlardan birini seçin">
          <IconTemplates /> <span className="ld-btn-text">Şablonlar</span>
        </button>
        <span className="ld-divider" aria-hidden="true" />
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-icon" onClick={p.onUndo} disabled={!p.canUndo || p.readOnly} title="Geri al (Ctrl+Z)" aria-label="Geri al">
          <IconUndo />
        </button>
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-icon" onClick={p.onRedo} disabled={!p.canRedo || p.readOnly} title="İleri al (Ctrl+Y)" aria-label="İleri al">
          <IconRedo />
        </button>
      </div>

      <div className="ld-topbar-spacer" />

      <div className="ld-topbar-group ld-actions">
        <button type="button" className="ld-btn ld-btn-ghost" onClick={p.onPreview} disabled={p.previewBusy} title="Yazıcının basacağı görüntü (Labelary, örnek verilerle)">
          <IconSearch /> Önizle
        </button>
        <button type="button" className="ld-btn ld-btn-secondary" onClick={p.onTestPrint} title="Kaydedilmemiş tasarımı örnek verilerle yazıcıya gönderir">
          <IconPrinter /> Test baskı
        </button>
        <button type="button" className="ld-btn ld-btn-primary" onClick={p.onSave} disabled={p.readOnly} title="Kaydet (Ctrl+S)">
          <IconSave /> Kaydet
        </button>
      </div>
    </header>
  );
}
