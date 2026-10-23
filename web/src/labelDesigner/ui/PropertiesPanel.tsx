// Sağ panel: seçili öğenin özellikleri (Türkçe), seçim yoksa etiket bilgisi ve öğe listesi.
import { useEffect, useRef, type ReactNode } from "react";
import { elementName, isKnownType, KIND_LABELS, resolveValue, SYMBOLOGY_LABELS, TYPE_LABELS } from "../model/design";
import { elementGeometry, labelDots, printBoundsDots, type LayoutContext } from "../model/layout";
import type { AlignMode } from "../model/ops";
import { LIMITS, type Align, type LabelDesign, type LabelElement, type Rotation, type Symbology } from "../model/types";
import { formatDecimal, roundMm } from "../model/units";
import type { Warning } from "../model/validate";
import { NumberField, Row, Section, Segmented, Toggle } from "./controls";
import {
  IconAlignBottom,
  IconAlignHCenter,
  IconAlignLeft,
  IconAlignRight,
  IconAlignTop,
  IconAlignVCenter,
  IconBuilding,
  IconCopy,
  IconDistH,
  IconDistV,
  IconEye,
  IconEyeOff,
  IconFit,
  IconInfo,
  IconRotate,
  IconTrash,
  IconUpload,
  IconWarn,
  TypeIcon,
} from "./icons";

export interface AlignActions {
  onAlign: (mode: AlignMode) => void;
  onDistribute: (axis: "h" | "v") => void;
  onFit: () => void;
  /** seçili öğe sayısı: 1 = etikete göre, 2+ = seçime göre, 3+ = dağıt */
  count: number;
}

const ALIGN_BUTTONS: { mode: AlignMode; label: string; icon: ReactNode }[] = [
  { mode: "left", label: "Sola hizala", icon: <IconAlignLeft /> },
  { mode: "hcenter", label: "Yatayda ortala", icon: <IconAlignHCenter /> },
  { mode: "right", label: "Sağa hizala", icon: <IconAlignRight /> },
  { mode: "top", label: "Üste hizala", icon: <IconAlignTop /> },
  { mode: "vcenter", label: "Dikeyde ortala", icon: <IconAlignVCenter /> },
  { mode: "bottom", label: "Alta hizala", icon: <IconAlignBottom /> },
];

/** Hizalama çubuğu: tek öğe etikete (güvenli kenarla), çoklu seçim seçimin kutusuna. */
function AlignBar({ a, readOnly }: { a: AlignActions; readOnly: boolean }) {
  const scope = a.count > 1 ? "seçime göre" : "etikete göre";
  return (
    <div className="ld-alignbar" role="group" aria-label={`Hizala (${scope})`}>
      {ALIGN_BUTTONS.map((b) => (
        <button key={b.mode} type="button" className="ld-icon-btn" disabled={readOnly} onClick={() => a.onAlign(b.mode)} title={`${b.label} (${scope})`} aria-label={b.label}>
          {b.icon}
        </button>
      ))}
      <span className="ld-alignbar-sep" aria-hidden="true" />
      <button type="button" className="ld-icon-btn" disabled={readOnly || a.count < 3} onClick={() => a.onDistribute("h")} title="Yatayda eşit dağıt (en az 3 öğe)" aria-label="Yatayda eşit dağıt"><IconDistH /></button>
      <button type="button" className="ld-icon-btn" disabled={readOnly || a.count < 3} onClick={() => a.onDistribute("v")} title="Dikeyde eşit dağıt (en az 3 öğe)" aria-label="Dikeyde eşit dağıt"><IconDistV /></button>
      <button type="button" className="ld-icon-btn" disabled={readOnly} onClick={a.onFit} title="Etiketin güvenli alanına al (taşıyorsa küçültür)" aria-label="Etikete sığdır"><IconFit /></button>
    </div>
  );
}

export type ElementPatcher = (patch: Partial<LabelElement>, key?: string) => void;

interface ElementPanelProps {
  design: LabelDesign;
  element: LabelElement;
  ctx: LayoutContext;
  warnings: Warning[];
  readOnly: boolean;
  focusToken: number;
  onPatch: ElementPatcher;
  onRotate: (rotation: Rotation) => void;
  onDuplicate: () => void;
  onDelete: () => void;
  onUploadImage: () => void;
  onRequestLogo: () => void;
  onImageAspect: () => void;
  logoPending: boolean;
  align: AlignActions;
}

const FONT_PRESETS: { label: string; mm: number }[] = [
  { label: "Küçük", mm: 2.25 },
  { label: "Orta", mm: 3 },
  { label: "Büyük", mm: 4 },
  { label: "Çok büyük", mm: 6 },
];

const STATIC_SOURCE = "__static__";

export function ElementPanel(props: ElementPanelProps) {
  const { design, element: el, ctx, warnings, readOnly, onPatch } = props;
  const mainInput = useRef<HTMLInputElement | HTMLSelectElement | null>(null);
  useEffect(() => {
    if (props.focusToken > 0) mainInput.current?.focus();
  }, [props.focusToken]);

  if (!isKnownType(el.type)) {
    return (
      <div className="ld-props">
        <p className="ld-muted">Bu öğe türü (“{el.type}”) tasarımcıda düzenlenemez; kayıtta olduğu gibi korunur.</p>
      </div>
    );
  }

  const geo = elementGeometry(el, ctx);
  const isText = el.type === "text" || el.type === "field";
  const isCode = el.type === "barcode" || el.type === "qr";
  const value = resolveValue(el, ctx.values);
  const k = (prop: string) => `${el.id}:${prop}`;
  const fieldOptions = design.fields.map((f) => ({ key: f.key, label: f.label, sample: f.sample }));
  const unknownField = el.field !== "" && !design.fields.some((f) => f.key === el.field);

  const fieldSelect = (allowStatic: boolean) => (
    <select
      ref={(n) => { if (el.type === "field" || isCode) mainInput.current = n; }}
      className="ld-select"
      value={el.field === "" && allowStatic ? STATIC_SOURCE : el.field}
      onChange={(e) => {
        const v = e.currentTarget.value;
        if (v === STATIC_SOURCE) onPatch({ field: "", text: el.text || "123456789" });
        else onPatch({ field: v });
      }}
    >
      {el.field === "" && !allowStatic ? <option value="">— Alan seçin —</option> : null}
      {fieldOptions.map((f) => (
        <option key={f.key} value={f.key}>{f.label}</option>
      ))}
      {unknownField ? <option value={el.field}>⚠ {el.field} (bu türde yok)</option> : null}
      {allowStatic ? <option value={STATIC_SOURCE}>Sabit veri (elle yazın)</option> : null}
    </select>
  );

  return (
    <div className="ld-props">
      <div className="ld-props-head">
        <span className="ld-props-icon"><TypeIcon type={el.type} size={22} /></span>
        <div className="ld-props-title">
          <strong>{TYPE_LABELS[el.type]}</strong>
          <span className="ld-muted ld-small">{elementName(design, el)}</span>
        </div>
      </div>
      <AlignBar a={props.align} readOnly={readOnly} />
      <div className="ld-props-actions">
        {el.type !== "qr" ? (
          <button type="button" className="ld-btn ld-btn-ghost" disabled={readOnly} title="90° döndür (R)" onClick={() => props.onRotate(((el.rotation + 90) % 360) as Rotation)}>
            <IconRotate /> Döndür
          </button>
        ) : null}
        <button type="button" className="ld-btn ld-btn-ghost" disabled={readOnly} title="Çoğalt (Ctrl+D)" onClick={props.onDuplicate}>
          <IconCopy /> Çoğalt
        </button>
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-danger" disabled={readOnly} title="Sil (Del)" onClick={props.onDelete}>
          <IconTrash /> Sil
        </button>
      </div>

      {warnings.length > 0 ? (
        <ul className={`ld-inline-warnings${warnings.some((w) => w.level === "error") ? " has-error" : warnings.every((w) => w.level === "info") ? " is-info" : ""}`}>
          {warnings.map((w, i) => (
            <li key={i} className={`ld-warn-${w.level}`}>{w.level === "info" ? <IconInfo /> : <IconWarn />} <span>{w.message.replace(/^.*? — /, "")}</span></li>
          ))}
        </ul>
      ) : null}

      <fieldset className="ld-fieldset" disabled={readOnly}>
        {/* ------------------------------------------------ İçerik */}
        {el.type === "text" ? (
          <Section title="İçerik">
            <Row label="Metin">
              <input
                ref={(n) => { mainInput.current = n; }}
                className="ld-input"
                type="text"
                maxLength={LIMITS.text}
                value={el.text}
                placeholder="Etikete yazılacak metin"
                onChange={(e) => onPatch({ text: e.currentTarget.value }, k("text"))}
              />
            </Row>
          </Section>
        ) : null}

        {el.type === "field" ? (
          <Section title="İçerik">
            <Row label="Veri alanı" hint={value ? `Örnek: ${value}` : "Bu alanın örnek değeri boş."}>{fieldSelect(false)}</Row>
            <AffixRows el={el} onPatch={onPatch} k={k} />
          </Section>
        ) : null}

        {el.type === "barcode" ? (
          <Section title="Barkod">
            <Row label="Barkod türü">
              <select className="ld-select" value={el.symbology} onChange={(e) => onPatch({ symbology: e.currentTarget.value as Symbology })}>
                {(Object.keys(SYMBOLOGY_LABELS) as Symbology[]).map((s) => (
                  <option key={s} value={s}>{SYMBOLOGY_LABELS[s]}</option>
                ))}
              </select>
            </Row>
            <Row label="Veri" hint={value ? `Örnek: ${value}` : undefined}>{fieldSelect(true)}</Row>
            {el.field === "" ? (
              <Row label="Sabit veri" hint={el.symbology === "gs1-128" ? "AI'ları parantezle yazın: (01)08690000012345(10)LOT1" : undefined}>
                <input className="ld-input" type="text" maxLength={LIMITS.text} value={el.text} onChange={(e) => onPatch({ text: e.currentTarget.value }, k("text"))} />
              </Row>
            ) : null}
            <AffixRows el={el} onPatch={onPatch} k={k} />
            <Toggle checked={el.showText} onChange={(v) => onPatch({ showText: v })} label="Barkodun altına yazısını bas" />
          </Section>
        ) : null}

        {el.type === "qr" ? (
          <Section title="QR kod">
            <Row label="Veri" hint={value ? `Örnek: ${value}` : undefined}>{fieldSelect(true)}</Row>
            {el.field === "" ? (
              <Row label="Sabit veri">
                <input className="ld-input" type="text" maxLength={LIMITS.text} value={el.text} onChange={(e) => onPatch({ text: e.currentTarget.value }, k("text"))} />
              </Row>
            ) : null}
            <AffixRows el={el} onPatch={onPatch} k={k} />
          </Section>
        ) : null}

        {el.type === "image" ? (
          <Section title="Resim">
            <Row label="Resim">
              <select
                ref={(n) => { mainInput.current = n; }}
                className="ld-select"
                value={el.imageId}
                onChange={(e) => onPatch({ imageId: e.currentTarget.value })}
              >
                <option value="">— Resim seçin —</option>
                {design.images.map((img) => (
                  <option key={img.id} value={img.id}>{img.name}</option>
                ))}
                {el.imageId && !design.images.some((i) => i.id === el.imageId) ? <option value={el.imageId}>⚠ {el.imageId} (bulunamadı)</option> : null}
              </select>
            </Row>
            <div className="ld-btn-col">
              <button type="button" className="ld-btn ld-btn-ghost ld-btn-block" onClick={props.onUploadImage}><IconUpload /> Bilgisayardan yükle…</button>
              <button type="button" className="ld-btn ld-btn-ghost ld-btn-block" onClick={props.onRequestLogo} disabled={props.logoPending}>
                <IconBuilding /> {props.logoPending ? "Logo isteniyor…" : "Şirket logosunu getir"}
              </button>
              <button type="button" className="ld-btn ld-btn-ghost ld-btn-block" onClick={props.onImageAspect} disabled={!el.imageId}>Orijinal en/boy oranına getir</button>
            </div>
            <p className="ld-note">Yazıcı siyah-beyaz basar: önizleme, %50 eşikle basılacak hali gösterir.</p>
          </Section>
        ) : null}

        {/* ------------------------------------------------ Yazı */}
        {isText ? (
          <Section title="Yazı">
            <Row label="Yazı boyu">
              <NumberField value={el.fontMm > 0 ? el.fontMm : 2.75} min={1} max={60} step={0.25} onChange={(v) => onPatch({ fontMm: v }, k("fontMm"))} ariaLabel="Yazı boyu (mm)" />
            </Row>
            <div className="ld-chips">
              {FONT_PRESETS.map((p) => (
                <button key={p.label} type="button" className={`ld-chip${el.fontMm === p.mm ? " is-on" : ""}`} onClick={() => onPatch({ fontMm: p.mm })}>{p.label}</button>
              ))}
            </div>
            <Row label="Hizalama">
              <Segmented<Align>
                ariaLabel="Hizalama"
                value={el.align}
                onChange={(v) => onPatch({ align: v })}
                options={[
                  { value: "left", label: "Sol" },
                  { value: "center", label: "Orta" },
                  { value: "right", label: "Sağ" },
                ]}
              />
            </Row>
            <Toggle checked={el.bold} onChange={(v) => onPatch({ bold: v })} label="Kalın (harfler %20 geniş)" />
            <Toggle checked={el.fit} onChange={(v) => onPatch({ fit: v })} label="Uzun yazıyı genişliğe sığdır (küçült)" />
            {el.fit ? (
              <Row label="En küçük yazı boyu" hint="0 = yazı boyunun yarısı">
                <NumberField value={el.minFontMm} min={0} max={60} step={0.25} onChange={(v) => onPatch({ minFontMm: v }, k("minFontMm"))} />
              </Row>
            ) : null}
            <Row label="En çok satır" hint="Uzun metin alt satıra geçer; fazlası kesilir.">
              <NumberField value={Math.max(1, el.maxLines)} min={1} max={10} step={1} integer suffix="satır" onChange={(v) => onPatch({ maxLines: v })} />
            </Row>
            <Toggle checked={el.inverted} onChange={(v) => onPatch({ inverted: v })} label="Ters: siyah zemin üstüne beyaz yazı" />
            {el.inverted ? <p className="ld-note">Beyaz yazı için altına dolu bir Kutu koyun.</p> : null}
          </Section>
        ) : null}

        {/* ------------------------------------------------ Çizgi / kutu */}
        {el.type === "line" ? (
          <Section title="Çizgi">
            <Row label="Yön">
              <Segmented<"h" | "v">
                ariaLabel="Yön"
                value={el.wMm >= el.hMm ? "h" : "v"}
                onChange={(v) => {
                  const horizontal = el.wMm >= el.hMm;
                  if ((v === "h") !== horizontal) props.onRotate(90);
                }}
                options={[
                  { value: "h", label: "Yatay" },
                  { value: "v", label: "Dikey" },
                ]}
              />
            </Row>
            <Row label="Kalınlık">
              <NumberField
                value={Math.min(el.wMm, el.hMm)}
                min={0.13}
                max={20}
                step={0.25}
                onChange={(v) => onPatch(el.wMm >= el.hMm ? { hMm: v, thicknessMm: v } : { wMm: v, thicknessMm: v }, k("thick"))}
              />
            </Row>
            <Row label="Uzunluk">
              <NumberField
                value={Math.max(el.wMm, el.hMm)}
                min={0.5}
                max={400}
                onChange={(v) => onPatch(el.wMm >= el.hMm ? { wMm: v } : { hMm: v }, k("len"))}
              />
            </Row>
          </Section>
        ) : null}

        {el.type === "box" ? (
          <Section title="Kutu">
            <Toggle checked={el.thicknessMm === 0} onChange={(v) => onPatch({ thicknessMm: v ? 0 : 0.5 })} label="İçi dolu (siyah)" />
            {el.thicknessMm > 0 ? (
              <Row label="Kenar kalınlığı">
                <NumberField value={el.thicknessMm} min={0.13} max={20} step={0.25} onChange={(v) => onPatch({ thicknessMm: v }, k("thicknessMm"))} />
              </Row>
            ) : null}
          </Section>
        ) : null}

        {/* ------------------------------------------------ Konum ve boyut */}
        <Section title="Konum ve boyut" aside={<DotReadout el={el} ctx={ctx} />}>
          <div className="ld-grid2">
            <Row label="Soldan (X)">
              <NumberField value={el.xMm} min={0} max={design.widthMm} onChange={(v) => onPatch({ xMm: v }, k("x"))} />
            </Row>
            <Row label="Üstten (Y)">
              <NumberField value={el.yMm} min={0} max={design.heightMm} onChange={(v) => onPatch({ yMm: v }, k("y"))} />
            </Row>
            {el.type === "qr" ? (
              <Row label="Boyut">
                <NumberField value={el.wMm || 20} min={5} max={200} onChange={(v) => onPatch({ wMm: v, hMm: v }, k("size"))} />
              </Row>
            ) : el.type === "line" ? null : (
              <>
                <Row label={isText ? "Genişlik" : el.type === "barcode" ? "Uzunluk" : "Genişlik"} hint={isText && el.wMm === 0 ? "0 = etiketin sonuna kadar" : undefined}>
                  <NumberField value={el.wMm} min={0} max={400} onChange={(v) => onPatch({ wMm: v }, k("w"))} />
                </Row>
                {isText ? (
                  <Row label="Yükseklik" hint="Yazı boyundan hesaplanır">
                    <span className="ld-readonly">{String(roundMm(geo.localH)).replace(".", ",")} mm</span>
                  </Row>
                ) : (
                  <Row label={el.type === "barcode" ? "Çubuk boyu" : "Yükseklik"}>
                    <NumberField value={el.hMm} min={el.type === "barcode" ? 2 : 0.13} max={400} onChange={(v) => onPatch({ hMm: v }, k("h"))} />
                  </Row>
                )}
              </>
            )}
          </div>
          {el.type !== "qr" && el.type !== "line" && el.type !== "box" ? (
            <Row label="Döndürme">
              <Segmented<Rotation>
                ariaLabel="Döndürme"
                value={el.rotation}
                onChange={(v) => props.onRotate(v)}
                options={[
                  { value: 0, label: "0°" },
                  { value: 90, label: "90°" },
                  { value: 180, label: "180°" },
                  { value: 270, label: "270°" },
                ]}
              />
            </Row>
          ) : null}
        </Section>

        <Section title="Baskı">
          <Toggle checked={el.enabled} onChange={(v) => onPatch({ enabled: v })} label="Etikette bas (etkin)" />
        </Section>
      </fieldset>
    </div>
  );
}

/** Elemanın yazıcıdaki kutusu (nokta) — BC ^FO ve basılı alan. */
function DotReadout({ el, ctx }: { el: LabelElement; ctx: LayoutContext }) {
  const { box } = printBoundsDots(el, ctx);
  return (
    <span className="ld-dots" title="Yazıcı noktası: ^FO x,y ve basılı alan (203 dpi = 8 nokta/mm)">
      ^FO {box.x0},{box.y0} · {box.x1 - box.x0}×{box.y1 - box.y0}
    </span>
  );
}

function AffixRows({ el, onPatch, k }: { el: LabelElement; onPatch: ElementPatcher; k: (p: string) => string }) {
  return (
    <div className="ld-grid2">
      <Row label="Ön ek" hint="Örn. “BİRİM: ”">
        <input className="ld-input" type="text" maxLength={LIMITS.prefix} value={el.prefix} onChange={(e) => onPatch({ prefix: e.currentTarget.value }, k("prefix"))} />
      </Row>
      <Row label="Son ek">
        <input className="ld-input" type="text" maxLength={LIMITS.suffix} value={el.suffix} onChange={(e) => onPatch({ suffix: e.currentTarget.value }, k("suffix"))} />
      </Row>
    </div>
  );
}

// ---------------------------------------------------------------- çoklu seçim

export function MultiPanel({ count, readOnly, onDuplicate, onDelete, onClear, align }: { count: number; readOnly: boolean; onDuplicate: () => void; onDelete: () => void; onClear: () => void; align: AlignActions }) {
  return (
    <div className="ld-props">
      <div className="ld-props-head">
        <div className="ld-props-title">
          <strong>{count} öğe seçili</strong>
          <span className="ld-muted ld-small">Birlikte taşıyabilir, hizalayabilir, çoğaltabilir ya da silebilirsiniz.</span>
        </div>
      </div>
      <AlignBar a={align} readOnly={readOnly} />
      <div className="ld-props-actions">
        <button type="button" className="ld-btn ld-btn-ghost" disabled={readOnly} onClick={onDuplicate}><IconCopy /> Çoğalt</button>
        <button type="button" className="ld-btn ld-btn-ghost ld-btn-danger" disabled={readOnly} onClick={onDelete}><IconTrash /> Sil</button>
        <button type="button" className="ld-btn ld-btn-ghost" onClick={onClear}>Seçimi kaldır</button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- etiket

interface LabelPanelProps {
  design: LabelDesign;
  ctx: LayoutContext;
  readOnly: boolean;
  warnedIds: ReadonlySet<string>;
  overflow: ReadonlyMap<string, number>;
  safeMarginMm: number;
  onMeta: (patch: Partial<LabelDesign>, key?: string) => void;
  onSelect: (id: string) => void;
  onToggleEnabled: (id: string, enabled: boolean) => void;
}

export function LabelPanel({ design, ctx, readOnly, warnedIds, overflow, safeMarginMm, onMeta, onSelect, onToggleEnabled }: LabelPanelProps) {
  const dots = labelDots(ctx);
  return (
    <div className="ld-props">
      <div className="ld-sizecard">
        <div className="ld-sizecard-main">
          <strong>{formatDecimal(design.widthMm)} × {formatDecimal(design.heightMm)} mm</strong>
          <span>{design.dpi} dpi · {dots.w} × {dots.h} nokta</span>
        </div>
        <p className="ld-sizecard-note">
          BC bu tasarımı tam bu ölçüde basar (^PW{dots.w} ^LL{dots.h}). Yazıcıdaki rulo da {formatDecimal(design.widthMm)} × {formatDecimal(design.heightMm)} mm olmalı.
          {safeMarginMm > 0 ? ` Yazı, barkod ve QR kenardan en az ${formatDecimal(safeMarginMm)} mm içeride kalmalı (kesikli çizgi).` : ""}
        </p>
        {overflow.size > 0 ? <p className="ld-sizecard-over"><IconWarn size={14} /> {overflow.size} öğe etiketin dışına taşıyor.</p> : null}
      </div>
      <Section title="Etiket">
        <dl className="ld-kv">
          <dt>Kod</dt>
          <dd>{design.code || "—"}</dd>
          <dt>Tür</dt>
          <dd>{KIND_LABELS[design.kind]}</dd>
        </dl>
        <fieldset className="ld-fieldset" disabled={readOnly}>
          <Row label="Açıklama">
            <input className="ld-input" type="text" maxLength={100} value={design.description} onChange={(e) => onMeta({ description: e.currentTarget.value }, "description")} />
          </Row>
          <Toggle checked={design.active} onChange={(v) => onMeta({ active: v })} label="Bu tasarımı kullan (etkin)" />
        </fieldset>
      </Section>
      <Section title={`Öğeler (${design.elements.length})`}>
        {design.elements.length === 0 ? <p className="ld-muted ld-small">Henüz öğe yok. Soldan sürükleyin.</p> : null}
        <ul className="ld-layer-list">
          {design.elements.map((el) => (
            <li key={el.id} className={el.enabled ? "" : "is-disabled"}>
              <button type="button" className="ld-layer" onClick={() => onSelect(el.id)}>
                <span className="ld-layer-icon"><TypeIcon type={el.type} size={16} /></span>
                <span className="ld-layer-name">{elementName(design, el)}</span>
                {overflow.has(el.id) ? (
                  <span className="ld-layer-over" title="Etiketin dışına taşıyor">{formatDecimal(overflow.get(el.id) ?? 0)} mm</span>
                ) : warnedIds.has(el.id) ? (
                  <span className="ld-layer-warn" title="Uyarı var"><IconWarn size={14} /></span>
                ) : null}
              </button>
              <button
                type="button"
                className="ld-icon-btn"
                disabled={readOnly}
                title={el.enabled ? "Basılıyor — kapatmak için tıklayın" : "Basılmıyor — açmak için tıklayın"}
                aria-label={el.enabled ? "Pasif yap" : "Etkin yap"}
                onClick={() => onToggleEnabled(el.id, !el.enabled)}
              >
                {el.enabled ? <IconEye size={16} /> : <IconEyeOff size={16} />}
              </button>
            </li>
          ))}
        </ul>
      </Section>
      <p className="ld-note">İpucu: öğeye çift tıklayınca içeriği burada düzenlenir. Metinde üst/alt tutamak yazı boyunu değiştirir.</p>
    </div>
  );
}
