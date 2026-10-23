// Önizleme penceresi (Labelary), bildirimler ve uyarı çubuğu.
import { useEffect } from "react";
import type { Warning } from "../model/validate";
import { IconCheck, IconClose, IconInfo, IconWarn } from "./icons";

export interface PreviewState {
  open: boolean;
  status: "loading" | "ready" | "error";
  designPng: string;
  realPng: string;
  error: string;
}

export function PreviewModal({ state, onClose, onRetry }: { state: PreviewState; onClose: () => void; onRetry: () => void }) {
  useEffect(() => {
    if (!state.open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [state.open, onClose]);
  if (!state.open) return null;
  return (
    <div className="ld-modal-backdrop" role="presentation" onPointerDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="ld-modal" role="dialog" aria-modal="true" aria-labelledby="ld-preview-title">
        <header className="ld-modal-head">
          <h2 id="ld-preview-title">Gerçek çıktı kontrolü</h2>
          <button type="button" className="ld-icon-btn" onClick={onClose} aria-label="Kapat"><IconClose /></button>
        </header>
        <div className="ld-modal-body ld-compare">
          <figure>
            <figcaption>Tasarımcı</figcaption>
            <div className="ld-compare-img">{state.designPng ? <img src={state.designPng} alt="Tasarımcı önizlemesi" /> : null}</div>
          </figure>
          <figure>
            <figcaption>Yazıcı (Labelary)</figcaption>
            <div className="ld-compare-img">
              {state.status === "loading" ? (
                <div className="ld-spinner-wrap"><span className="ld-spinner" aria-hidden="true" /> Labelary'den görüntü alınıyor…</div>
              ) : state.status === "error" ? (
                <div className="ld-preview-error"><IconWarn /> {state.error || "Önizleme alınamadı."}</div>
              ) : (
                <img src={state.realPng} alt="Labelary önizlemesi" />
              )}
            </div>
          </figure>
        </div>
        <footer className="ld-modal-foot">
          <span className="ld-muted ld-small">Labelary'e yalnız örnek veriler gönderilir. İki görüntü farklıysa sağdaki yazıcıya yakındır.</span>
          <span className="ld-topbar-spacer" />
          {state.status === "error" ? <button type="button" className="ld-btn ld-btn-ghost" onClick={onRetry}>Tekrar dene</button> : null}
          <button type="button" className="ld-btn ld-btn-primary" onClick={onClose}>Kapat</button>
        </footer>
      </div>
    </div>
  );
}

export interface Toast {
  id: number;
  kind: "info" | "error" | "success";
  text: string;
  action?: { label: string; run: () => void };
}

export function Toasts({ toasts, onDismiss }: { toasts: Toast[]; onDismiss: (id: number) => void }) {
  return (
    <div className="ld-toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div key={t.id} className={`ld-toast ld-toast-${t.kind}`}>
          <span className="ld-toast-icon">{t.kind === "error" ? <IconWarn /> : t.kind === "success" ? <IconCheck /> : null}</span>
          <span className="ld-toast-text">
            {t.text}
            {t.action ? (
              <button type="button" className="ld-btn ld-btn-secondary ld-btn-sm ld-toast-action" onClick={() => { t.action?.run(); onDismiss(t.id); }}>
                {t.action.label}
              </button>
            ) : null}
          </span>
          <button type="button" className="ld-icon-btn" onClick={() => onDismiss(t.id)} aria-label="Kapat"><IconClose size={14} /></button>
        </div>
      ))}
    </div>
  );
}

export function WarningsBar({ warnings, open, onToggle, onPick }: { warnings: Warning[]; open: boolean; onToggle: () => void; onPick: (id: string) => void }) {
  const errors = warnings.filter((w) => w.level === "error").length;
  const warns = warnings.filter((w) => w.level === "warn").length;
  const infos = warnings.filter((w) => w.level === "info").length;
  if (errors + warns === 0 && infos === 0) {
    return (
      <footer className="ld-warnbar is-ok">
        <IconCheck /> <span>Sorun yok — tasarım etikete sığıyor ve basılmaya hazır.</span>
      </footer>
    );
  }
  const tone = errors > 0 ? "is-error" : warns > 0 ? "is-warn" : "is-info";
  return (
    <footer className={`ld-warnbar ${tone}${open ? " is-open" : ""}`}>
      <button type="button" className="ld-warnbar-toggle" onClick={onToggle} aria-expanded={open}>
        {errors + warns > 0 ? <IconWarn /> : <IconInfo />}
        {errors > 0 ? <span className="ld-count ld-count-error">{errors} taşma / hata</span> : null}
        {warns > 0 ? <span className="ld-count ld-count-warn">{warns} uyarı</span> : null}
        {infos > 0 ? <span className="ld-count ld-count-info">{infos} öneri</span> : null}
        <span className="ld-muted ld-small">— kaydı engellemez</span>
        <span className="ld-warnbar-caret">{open ? "Gizle ▾" : "Göster ▴"}</span>
      </button>
      {open ? (
        <ul className="ld-warnlist">
          {warnings.map((w, i) => (
            <li key={i} className={`ld-warn-${w.level}`}>
              <span className="ld-warn-dot" aria-hidden="true" />
              {w.elementId ? (
                <button type="button" className="ld-link" onClick={() => onPick(w.elementId as string)}>{w.message}</button>
              ) : (
                <span>{w.message}</span>
              )}
            </li>
          ))}
        </ul>
      ) : null}
    </footer>
  );
}
