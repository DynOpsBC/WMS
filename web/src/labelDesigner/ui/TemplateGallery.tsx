// "Hazır şablonlar" penceresi: türe göre şablonlar, canlı küçük resimler
// (kendi çizicimizle, örnek değerlerle), onay sonrası geri alınabilir uygulama.
import { useEffect, useMemo, useState } from "react";
import { KIND_LABELS, sampleValues } from "../model/design";
import { layoutContext } from "../model/layout";
import type { LabelDesign, LabelElement } from "../model/types";
import { mmToDots } from "../model/units";
import type { MonoBitmap } from "../render/gf";
import { renderLabel } from "../render/renderLabel";
import { templatePreviewDesign, templatesFor, templateUsesLogo, type LabelTemplate } from "../templates";
import { IconClose, IconImage, IconWarn } from "./icons";

const THUMB_W = 560;
const THUMB_H = 320;

interface Props {
  open: boolean;
  mode: "browse" | "start";
  design: LabelDesign;
  bitmapFor: (d: LabelDesign) => (el: LabelElement) => MonoBitmap | null;
  imageVersion: number;
  onApply: (template: LabelTemplate) => void;
  onBlank: () => void;
  onClose: () => void;
}

function thumbnail(design: LabelDesign, bitmap: (el: LabelElement) => MonoBitmap | null): string {
  const wDots = mmToDots(design.widthMm, design.dpi);
  const hDots = mmToDots(design.heightMm, design.dpi);
  const scale = Math.min(THUMB_W / wDots, THUMB_H / hDots);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(wDots * scale));
  canvas.height = Math.max(1, Math.round(hDots * scale));
  const g = canvas.getContext("2d");
  if (!g) return "";
  renderLabel(g, design, { scale, ctx: layoutContext(design, sampleValues(design)), imageBitmap: bitmap, showDisabled: false });
  return canvas.toDataURL("image/png");
}

const fmt = (n: number) => String(n).replace(".", ",");

export function TemplateGallery({ open, mode, design, bitmapFor, imageVersion, onApply, onBlank, onClose }: Props) {
  const [pending, setPending] = useState<LabelTemplate | null>(null);
  // Mevcut etiket ölçüsündeki şablonlar önce (ölçü değişmeden uygulanır).
  const templates = useMemo(() => {
    const all = templatesFor(design.kind);
    const same = (t: LabelTemplate) => t.widthMm === design.widthMm && t.heightMm === design.heightMm;
    return [...all.filter(same), ...all.filter((t) => !same(t))];
  }, [design.kind, design.widthMm, design.heightMm]);
  const hasLogo = design.images.some((i) => i.id === "COMPANY" && i.dataUrl);

  const thumbs = useMemo(() => {
    if (!open) return new Map<string, string>();
    const m = new Map<string, string>();
    for (const t of templates) {
      const preview = templatePreviewDesign(design, t);
      m.set(t.id, thumbnail(preview, bitmapFor(preview)));
    }
    return m;
    // imageVersion: logo çözülünce küçük resimleri yenile
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, templates, design.fields, design.images, bitmapFor, imageVersion]);

  useEffect(() => {
    if (!open) setPending(null);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (pending) setPending(null);
        else onClose();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, pending, onClose]);

  if (!open) return null;

  const pick = (t: LabelTemplate) => {
    if (design.elements.length === 0) onApply(t);
    else setPending(t);
  };

  return (
    <div className="ld-modal-backdrop" role="presentation" onPointerDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="ld-modal ld-gallery" role="dialog" aria-modal="true" aria-labelledby="ld-gallery-title">
        <header className="ld-modal-head">
          <div>
            <h2 id="ld-gallery-title">{mode === "start" ? "Nasıl başlamak istersiniz?" : "Hazır şablonlar"}</h2>
            <p className="ld-muted ld-small ld-gallery-sub">
              {KIND_LABELS[design.kind]} için hazır tasarımlar. Birini seçin, sonra dilediğiniz gibi değiştirin.
            </p>
          </div>
          <button type="button" className="ld-icon-btn" onClick={onClose} aria-label="Kapat"><IconClose /></button>
        </header>
        <div className="ld-modal-body">
          {templates.length === 0 ? (
            <p className="ld-muted">Bu etiket türü için hazır şablon yok.</p>
          ) : (
            <div className="ld-gallery-grid">
              {templates.map((t) => {
                const src = thumbs.get(t.id);
                const selected = pending?.id === t.id;
                return (
                  <button
                    key={t.id}
                    type="button"
                    className={`ld-tpl${selected ? " is-selected" : ""}`}
                    onClick={() => pick(t)}
                    title={`${t.name} — kullanmak için tıklayın`}
                  >
                    <span className="ld-tpl-thumb">
                      {src ? <img src={src} alt="" style={{ aspectRatio: `${t.widthMm} / ${t.heightMm}` }} /> : null}
                    </span>
                    <span className="ld-tpl-meta">
                      <span className="ld-tpl-name">{t.name.replace(/\s*\([^)]*\)\s*$/, "")}</span>
                      {t.widthMm === design.widthMm && t.heightMm === design.heightMm ? (
                        <span className="ld-tpl-current" title="Etiketinizle aynı ölçü">{fmt(t.widthMm)} × {fmt(t.heightMm)} mm · bu ölçü</span>
                      ) : (
                        <span className="ld-tpl-size">{fmt(t.widthMm)} × {fmt(t.heightMm)} mm</span>
                      )}
                    </span>
                    <span className="ld-tpl-desc">{t.description}</span>
                    {templateUsesLogo(t) && !hasLogo ? (
                      <span className="ld-tpl-note"><IconImage size={14} /> Şirket logosu kullanır</span>
                    ) : null}
                  </button>
                );
              })}
            </div>
          )}
        </div>
        <footer className="ld-modal-foot">
          {pending ? (
            <>
              <span className="ld-confirm"><IconWarn /> <strong>Mevcut tasarım değiştirilsin mi?</strong> <span className="ld-muted">“{pending.name}” öğeleri ve ölçüsü gelir. Geri Al ile dönebilirsiniz.</span></span>
              <span className="ld-topbar-spacer" />
              <button type="button" className="ld-btn ld-btn-ghost" onClick={() => setPending(null)}>Vazgeç</button>
              <button type="button" className="ld-btn ld-btn-primary" onClick={() => onApply(pending)}>Evet, değiştir</button>
            </>
          ) : (
            <>
              <span className="ld-muted ld-small">Önizlemeler örnek verilerle çizilir; şablon seçince ölçü ve dpi da değişir.</span>
              <span className="ld-topbar-spacer" />
              {mode === "start" ? (
                <button type="button" className="ld-btn ld-btn-ghost" onClick={onBlank}>Boş tasarımla başla</button>
              ) : (
                <button type="button" className="ld-btn ld-btn-ghost" onClick={onClose}>Kapat</button>
              )}
            </>
          )}
        </footer>
      </div>
    </div>
  );
}
