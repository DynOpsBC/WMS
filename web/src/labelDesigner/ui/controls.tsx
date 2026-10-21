// Form denetimleri: mm sayı kutusu (virgül kabul eder), seçim, onay kutusu, segment.
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { formatDecimal, parseDecimal } from "../model/units";

export function Row({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return (
    <div className="ld-row">
      <span className="ld-row-label">{label}</span>
      <div className="ld-row-control">{children}</div>
      {hint ? <div className="ld-row-hint">{hint}</div> : null}
    </div>
  );
}

interface NumberFieldProps {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  step?: number;
  suffix?: string;
  integer?: boolean;
  disabled?: boolean;
  ariaLabel?: string;
  width?: number;
}

/** Yazarken serbest; geçerli sayı her tuşta, sınırlar odak çıkınca uygulanır. */
export function NumberField({ value, onChange, min, max, step = 0.5, suffix = "mm", integer, disabled, ariaLabel, width }: NumberFieldProps) {
  const [text, setText] = useState(formatDecimal(value));
  const focused = useRef(false);
  useEffect(() => {
    if (!focused.current) setText(formatDecimal(value));
  }, [value]);
  const clampValue = (n: number) => {
    let v = integer ? Math.round(n) : Math.round(n * 100) / 100;
    if (min !== undefined && v < min) v = min;
    if (max !== undefined && v > max) v = max;
    return v;
  };
  const commit = (raw: string, final: boolean) => {
    const n = parseDecimal(raw);
    if (n === null) {
      if (final) setText(formatDecimal(value));
      return;
    }
    const v = final ? clampValue(n) : n;
    if (!final && ((min !== undefined && v < min) || (max !== undefined && v > max))) return;
    if (v !== value) onChange(integer ? Math.round(v) : Math.round(v * 100) / 100);
    if (final) setText(formatDecimal(clampValue(n)));
  };
  const bump = (dir: 1 | -1) => {
    const v = clampValue(value + dir * step);
    onChange(v);
    setText(formatDecimal(v));
  };
  return (
    <span className={`ld-num${disabled ? " is-disabled" : ""}`} style={width ? { width } : undefined}>
      <input
        type="text"
        inputMode="decimal"
        aria-label={ariaLabel}
        value={text}
        disabled={disabled}
        onFocus={(e) => {
          focused.current = true;
          e.currentTarget.select();
        }}
        onBlur={(e) => {
          focused.current = false;
          commit(e.currentTarget.value, true);
        }}
        onChange={(e) => {
          setText(e.currentTarget.value);
          commit(e.currentTarget.value, false);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit(e.currentTarget.value, true);
          else if (e.key === "ArrowUp") { e.preventDefault(); bump(1); }
          else if (e.key === "ArrowDown") { e.preventDefault(); bump(-1); }
        }}
      />
      {suffix ? <span className="ld-num-suffix">{suffix}</span> : null}
    </span>
  );
}

export function Toggle({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  const id = useId();
  return (
    <label className={`ld-toggle${disabled ? " is-disabled" : ""}`} htmlFor={id}>
      <input id={id} type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.currentTarget.checked)} />
      <span className="ld-toggle-track" aria-hidden="true"><span className="ld-toggle-thumb" /></span>
      <span>{label}</span>
    </label>
  );
}

export function Segmented<T extends string | number>({ value, options, onChange, ariaLabel }: { value: T; options: { value: T; label: ReactNode; title?: string }[]; onChange: (v: T) => void; ariaLabel?: string }) {
  return (
    <div className="ld-seg" role="radiogroup" aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={String(o.value)}
          type="button"
          role="radio"
          aria-checked={o.value === value}
          title={o.title}
          className={o.value === value ? "is-on" : ""}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Section({ title, children, aside }: { title: string; children: ReactNode; aside?: ReactNode }) {
  return (
    <section className="ld-section">
      <header className="ld-section-head">
        <h3>{title}</h3>
        {aside}
      </header>
      <div className="ld-section-body">{children}</div>
    </section>
  );
}
