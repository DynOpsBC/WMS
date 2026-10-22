import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import type { DragEvent } from "react";
import { inBusinessCentral, invoke, registerHandlers } from "./bridge";
import { Icon, accentOf, glyphFor } from "./icons";
import { sampleData, sampleLayouts, samplePreview } from "./sampleData";
import {
  changedCount, displayLabel, editorReducer, groupsOf, initEditor, isDirty, screenItems,
} from "./state";
import type { EditorAction, EditorState } from "./state";
import type { AppliesTo, CatalogItem, DesignerData, Layout, LayoutHeader, LayoutLine, NotifyResult, PreviewData, ScanFlag } from "./types";

const EMPTY_LAYOUT: Layout = { code: "", description: "", appliesTo: "all", appliesToCode: "", active: true, lines: [] };
const APPLIES: { value: AppliesTo; label: string }[] = [
  { value: "all", label: "Tüm terminaller" },
  { value: "role", label: "Rol" },
  { value: "terminal", label: "Terminal" },
];
const FLAG_TEXT: Record<ScanFlag, string> = { LP: "LP / palet okutmak zorunlu", LOT: "Lot no. girmek zorunlu", BIN: "Raf okutmak zorunlu" };
const FLAG_SHORT: Record<ScanFlag, string> = { LP: "LP", LOT: "Lot", BIN: "Raf" };

type Toast = { ok: boolean; message: string } | null;
type DragInfo = { screen: string; key: string; group: string } | null;

export function TerminalDesignerApp() {
  const [data, setData] = useState<DesignerData | null>(null);
  const catalog = data?.catalog ?? [];
  const reducer = useMemo(() => editorReducer(catalog), [catalog]);
  const [editor, dispatch] = useReducer(
    (s: EditorState, a: EditorAction) => reducer(s, a),
    EMPTY_LAYOUT,
    initEditor,
  );
  const [screen, setScreen] = useState("HOME");
  const [selected, setSelected] = useState<string>("RECEIVING");
  const [showHidden, setShowHidden] = useState(true);
  const [previewRole, setPreviewRole] = useState("");
  const [previewTerminal, setPreviewTerminal] = useState("");
  const [preview, setPreview] = useState<PreviewData | null>(null);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState<Toast>(null);
  const [newOpen, setNewOpen] = useState(false);
  const [pendingSwitch, setPendingSwitch] = useState<string | null>(null);
  const standalone = useRef(!inBusinessCentral());
  const standaloneLayouts = useRef<Layout[]>(structuredClone(sampleLayouts));

  const dirty = isDirty(editor);
  const layout = editor.layout;

  const showToast = useCallback((t: NotifyResult) => {
    setToast(t);
    window.setTimeout(() => setToast((cur) => (cur === t ? null : cur)), t.ok ? 3200 : 7000);
  }, []);

  const applyData = useCallback((next: DesignerData) => {
    setData(next);
    dispatch({ type: "load", layout: next.layout });
    setSaving(false);
  }, []);

  // BC köprüsü
  useEffect(() => {
    const off = registerHandlers({
      SetData: (json) => applyData(JSON.parse(json) as DesignerData),
      SetPreview: (json) => setPreview(JSON.parse(json) as PreviewData),
      NotifyResult: (json) => { setSaving(false); showToast(JSON.parse(json) as NotifyResult); },
    });
    if (standalone.current) applyData(sampleData());
    else invoke("ControlReady");
    return off;
  }, [applyData, showToast]);

  // Önizleme rolü / terminali değişince BC'den geçerli yerleşimi iste.
  useEffect(() => {
    if (!previewRole && !previewTerminal) { setPreview(null); return; }
    if (standalone.current) setPreview(samplePreview(previewRole, previewTerminal));
    else invoke("RequestPreview", previewRole, previewTerminal);
  }, [previewRole, previewTerminal, data]);

  const save = useCallback(() => {
    if (!dirty || saving) return;
    if (layout.appliesTo !== "all" && !layout.appliesToCode) {
      showToast({ ok: false, message: layout.appliesTo === "role" ? "Bir rol seçin." : "Bir terminal seçin." });
      return;
    }
    setSaving(true);
    if (standalone.current) {
      const idx = standaloneLayouts.current.findIndex((l) => l.code === layout.code);
      const savedLayout = { ...structuredClone(layout), version: (layout.version ?? 0) + 1, modifiedBy: "ÖNİZLEME", modifiedAt: new Date().toISOString() };
      if (idx >= 0) standaloneLayouts.current[idx] = savedLayout;
      window.setTimeout(() => {
        dispatch({ type: "load", layout: savedLayout });
        setData((d) => d && { ...d, layout: savedLayout, layouts: d.layouts.map((h) => (h.code === savedLayout.code ? headerOf(savedLayout) : h)) });
        setSaving(false);
        showToast({ ok: true, message: `${layout.code} kaydedildi. Terminaller en geç 5 dakika içinde yeni yerleşimi alır.` });
      }, 350);
      return;
    }
    invoke("SaveLayout", JSON.stringify({ ...layout, lines: layout.lines }));
  }, [dirty, saving, layout, showToast]);

  // Klavye: Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y / Ctrl+S
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const typing = target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT");
      if (!(e.ctrlKey || e.metaKey)) return;
      const k = e.key.toLowerCase();
      if (k === "s") { e.preventDefault(); save(); }
      else if (!typing && k === "z") { e.preventDefault(); dispatch({ type: e.shiftKey ? "redo" : "undo" }); }
      else if (!typing && k === "y") { e.preventDefault(); dispatch({ type: "redo" }); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [save]);

  const loadLayout = (code: string) => {
    if (standalone.current) {
      const l = standaloneLayouts.current.find((x) => x.code === code);
      if (l) {
        const d = sampleData();
        applyData({ ...d, layouts: standaloneLayouts.current.map(headerOf), layout: structuredClone(l) });
      }
    } else invoke("LoadLayout", code);
  };

  const requestSwitch = (code: string) => {
    if (code === layout.code) return;
    if (dirty) setPendingSwitch(code);
    else loadLayout(code);
  };

  const createLayout = (payload: NewLayoutPayload) => {
    setNewOpen(false);
    if (standalone.current) {
      const base = payload.copyFrom ? standaloneLayouts.current.find((l) => l.code === payload.copyFrom) : undefined;
      const created: Layout = {
        code: payload.code, description: payload.description, appliesTo: payload.appliesTo, appliesToCode: payload.appliesToCode,
        active: true, version: 1, modifiedBy: "ÖNİZLEME", modifiedAt: new Date().toISOString(),
        lines: base ? structuredClone(base.lines) : catalog.map((c) => ({ screen: c.screen, key: c.key, visible: true, sort: c.sort, label: "", note: "", requireLp: false, requireLot: false, requireBin: false })),
      };
      standaloneLayouts.current.push(created);
      loadLayout(created.code);
      showToast({ ok: true, message: `${created.code} oluşturuldu.` });
    } else invoke("CreateLayout", JSON.stringify(payload));
  };

  const deleteLayout = () => {
    if (standalone.current) {
      standaloneLayouts.current = standaloneLayouts.current.filter((l) => l.code !== layout.code);
      loadLayout(standaloneLayouts.current[0]?.code ?? "");
      showToast({ ok: true, message: `${layout.code} silindi.` });
    } else invoke("DeleteLayout", layout.code);
  };

  if (!data) {
    return <div className="td-loading"><div className="td-spinner" />Terminal yerleşimleri yükleniyor…</div>;
  }

  const screens = data.screens;
  const currentScreen = screens.find((s) => s.key === screen) ?? screens[0];
  const selectedItem = catalog.find((c) => c.screen === screen && c.key === selected) ?? null;
  const selectedLine = selectedItem ? layout.lines.find((l) => l.screen === screen && l.key === selectedItem.key) ?? null : null;
  const previewing = preview !== null;
  // Önizlenen yerleşim şu an düzenlenen ise kaydedilmemiş değişiklikler de görünsün.
  const phoneLayout = preview && preview.layoutCode !== layout.code ? preview.layout : layout;
  const changes = changedCount(layout, catalog);

  return (
    <div className="td">
      <header className="td-top">
        <div className="td-brand">
          <div className="td-brand-icon"><Icon name="PHONE" size={20} /></div>
          <div>
            <h1>Terminal Ekran Tasarımcısı</h1>
            <p>El terminali menüsünü ve düğmelerini sürükleyip bırakarak düzenleyin.</p>
          </div>
        </div>
        <div className="td-top-actions">
          <button className="td-icon-btn" title="Geri al (Ctrl+Z)" aria-label="Geri al" disabled={!editor.past.length} onClick={() => dispatch({ type: "undo" })}><Icon name="UNDO" /></button>
          <button className="td-icon-btn" title="Yinele (Ctrl+Shift+Z)" aria-label="Yinele" disabled={!editor.future.length} onClick={() => dispatch({ type: "redo" })}><Icon name="REDO" /></button>
          {dirty && <span className="td-dirty"><span className="td-dot" />Kaydedilmemiş değişiklik</span>}
          <button className="td-btn td-btn-primary" disabled={!dirty || saving} onClick={save}>
            <Icon name={saving ? "RESET" : "SAVE"} className={saving ? "td-spin" : ""} />{saving ? "Kaydediliyor…" : "Kaydet"}
          </button>
        </div>
      </header>

      <section className="td-layoutbar">
        <label className="td-field td-field-layout">
          <span>Yerleşim</span>
          <select value={layout.code} onChange={(e) => requestSwitch(e.target.value)} data-testid="layout-select">
            {data.layouts.map((h) => (
              <option key={h.code} value={h.code}>{h.code} — {targetText(h)}{h.active ? "" : " (pasif)"}</option>
            ))}
          </select>
        </label>
        <button className="td-btn" onClick={() => setNewOpen(true)}><Icon name="PLUS" />Yeni yerleşim</button>
        <div className="td-sep" />
        <label className="td-field td-grow">
          <span>Açıklama</span>
          <input value={layout.description} maxLength={100} onChange={(e) => dispatch({ type: "header", patch: { description: e.target.value } })} />
        </label>
        <div className="td-field">
          <span>Uygulandığı</span>
          <div className="td-seg" role="radiogroup" aria-label="Uygulandığı">
            {APPLIES.map((a) => (
              <button key={a.value} role="radio" aria-checked={layout.appliesTo === a.value}
                className={layout.appliesTo === a.value ? "on" : ""}
                onClick={() => dispatch({ type: "header", patch: { appliesTo: a.value, appliesToCode: a.value === layout.appliesTo ? layout.appliesToCode : "" } })}>
                {a.label}
              </button>
            ))}
          </div>
        </div>
        {layout.appliesTo !== "all" && (
          <label className="td-field">
            <span>{layout.appliesTo === "role" ? "Rol" : "Terminal"}</span>
            <select value={layout.appliesToCode} onChange={(e) => dispatch({ type: "header", patch: { appliesToCode: e.target.value } })}>
              <option value="">Seçin…</option>
              {(layout.appliesTo === "role" ? data.roles.map((r) => ({ code: r.code, text: `${r.code} — ${r.description}` })) : data.terminals.map((t) => ({ code: t.code, text: t.code })))
                .map((o) => <option key={o.code} value={o.code}>{o.text}</option>)}
            </select>
          </label>
        )}
        <label className="td-switch" title="Pasif yerleşim hiçbir terminale uygulanmaz">
          <input type="checkbox" checked={layout.active} onChange={(e) => dispatch({ type: "header", patch: { active: e.target.checked } })} />
          <span className="td-switch-track"><span /></span>Etkin
        </label>
        {data.layouts.length > 1 && (
          <button className="td-icon-btn td-danger" title="Yerleşimi sil" aria-label="Yerleşimi sil" onClick={deleteLayout}><Icon name="TRASH" /></button>
        )}
      </section>

      <main className="td-body">
        {/* SOL — katalog */}
        <aside className="td-catalog" aria-label="Ekranlar ve öğeler">
          <div className="td-panel-title">Ekranlar</div>
          <nav className="td-screens">
            {screens.map((s) => {
              const items = screenItems(layout, catalog, s.key, true);
              const hidden = items.filter((x) => !x.line.visible).length;
              return (
                <button key={s.key} className={`td-screen ${s.key === screen ? "on" : ""}`} onClick={() => { setScreen(s.key); setSelected(items[0]?.item.key ?? ""); }}>
                  <Icon name={s.key === "HOME" ? "PHONE" : glyphFor(s.tileKey)} size={16} />
                  <span className="td-screen-name">{s.title}</span>
                  <span className="td-screen-meta">{hidden ? <em>{hidden} gizli</em> : null}{items.length}</span>
                </button>
              );
            })}
          </nav>
          <div className="td-panel-title td-panel-title-row">
            <span>{currentScreen.key === "HOME" ? "Menü kutuları" : "Düğmeler"}</span>
            <span className="td-hint">{currentScreen.key === "HOME" ? "sürükle · göz ile gizle" : "göz ile gizle"}</span>
          </div>
          <CatalogList
            catalog={catalog} layout={layout} screen={screen} selected={selected}
            onSelect={setSelected} dispatch={dispatch}
          />
        </aside>

        {/* ORTA — telefon */}
        <section className="td-stage">
          <div className="td-stage-bar">
            <div className="td-field td-inline">
              <span>Önizleme rolü</span>
              <select value={previewRole} onChange={(e) => setPreviewRole(e.target.value)} data-testid="preview-role">
                <option value="">— Düzenlenen yerleşim —</option>
                {data.roles.map((r) => <option key={r.code} value={r.code}>{r.code} — {r.description}</option>)}
              </select>
            </div>
            <div className="td-field td-inline">
              <span>Terminal</span>
              <select value={previewTerminal} onChange={(e) => setPreviewTerminal(e.target.value)}>
                <option value="">Herhangi</option>
                {data.terminals.map((t) => <option key={t.code} value={t.code}>{t.code}</option>)}
              </select>
            </div>
            {!previewing && (
              <label className="td-check">
                <input type="checkbox" checked={showHidden} onChange={(e) => setShowHidden(e.target.checked)} />Gizlileri soluk göster
              </label>
            )}
          </div>
          {previewing && preview && (
            <div className="td-preview-banner" data-testid="preview-banner">
              <Icon name="EYE" size={16} />
              <span>
                {preview.roleCode ? <b>{preview.roleCode}</b> : null}{preview.roleCode && preview.terminalCode ? " · " : null}
                {preview.terminalCode ? <b>{preview.terminalCode}</b> : null} için uygulanan yerleşim:{" "}
                <b>{preview.layoutCode || "Standart"}</b> <span className="td-muted">({preview.layoutDescription})</span>
              </span>
              {preview.layoutCode && preview.layoutCode !== layout.code && (
                <button className="td-link" onClick={() => { setPreviewRole(""); setPreviewTerminal(""); requestSwitch(preview.layoutCode); }}>Bu yerleşimi düzenle</button>
              )}
            </div>
          )}
          <Phone
            catalog={catalog} layout={phoneLayout} screen={screen} screenTitle={currentScreen.title}
            selected={selected} editable={!previewing || phoneLayout === layout} showHidden={!previewing && showHidden}
            onSelect={(k) => setSelected(k)} dispatch={dispatch}
            onOpenScreen={(tileKey) => { const s = screens.find((x) => x.tileKey === tileKey); if (s) { setScreen(s.key); setSelected(screenItems(layout, catalog, s.key, true)[0]?.item.key ?? ""); } }}
            onBack={() => { setScreen("HOME"); setSelected(currentScreen.tileKey || "RECEIVING"); }}
          />
          <p className="td-stage-foot">
            <Icon name="LOCK" size={14} /> Yerleşim yalnız <b>gizler, sıralar ve yeniden adlandırır</b>. Terminalin kendi yetki kuralları
            (ör. canlı ortamda yalnız yöneticiye açık ekranlar) her zaman önce uygulanır; yerleşim erişim vermez.
          </p>
        </section>

        {/* SAĞ — özellikler */}
        <aside className="td-inspector" aria-label="Seçili öğe">
          {selectedItem && selectedLine ? (
            <Inspector item={selectedItem} line={selectedLine} dispatch={dispatch} catalog={catalog} layout={layout} />
          ) : (
            <div className="td-empty">Telefondan ya da soldaki listeden bir öğe seçin.</div>
          )}
          <div className="td-summary">
            <div><b>{changes}</b> öğe standarttan farklı</div>
            <div className="td-muted">Sürüm {layout.version ?? 0}{layout.modifiedBy ? ` · ${layout.modifiedBy}` : ""}{layout.modifiedAt ? ` · ${fmtDate(layout.modifiedAt)}` : ""}</div>
          </div>
        </aside>
      </main>

      {toast && (
        <div className={`td-toast ${toast.ok ? "ok" : "err"}`} role="status">
          <Icon name={toast.ok ? "CHECK" : "INFO"} />{toast.message}
          <button aria-label="Kapat" onClick={() => setToast(null)}>×</button>
        </div>
      )}

      {newOpen && (
        <NewLayoutDialog data={data} onCancel={() => setNewOpen(false)} onCreate={createLayout} currentCode={layout.code} />
      )}

      {pendingSwitch && (
        <div className="td-modal-bg" role="dialog" aria-modal="true">
          <div className="td-modal">
            <h2>Kaydedilmemiş değişiklikler var</h2>
            <p><b>{layout.code}</b> yerleşimindeki değişiklikler kaybolacak. Devam edilsin mi?</p>
            <div className="td-modal-actions">
              <button className="td-btn" onClick={() => setPendingSwitch(null)}>Vazgeç</button>
              <button className="td-btn td-btn-danger" onClick={() => { const c = pendingSwitch; setPendingSwitch(null); loadLayout(c); }}>Değişiklikleri at</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function headerOf(l: Layout): LayoutHeader {
  const { lines: _lines, ...h } = l;
  return h;
}

function targetText(h: LayoutHeader): string {
  if (h.appliesTo === "role") return `Rol: ${h.appliesToCode || "?"}`;
  if (h.appliesTo === "terminal") return `Terminal: ${h.appliesToCode || "?"}`;
  return "Tüm terminaller";
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString("tr-TR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

// ---------------------------------------------------------------- sürükle-bırak

function useDnd(dispatch: (a: EditorAction) => void, axis: "x" | "y") {
  const [drag, setDrag] = useState<DragInfo>(null);
  const [over, setOver] = useState<{ key: string; place: "before" | "after" } | null>(null);
  const bind = (screen: string, key: string, group: string, enabled: boolean) => enabled ? {
    draggable: true,
    onDragStart: (e: DragEvent) => {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", key);
      setDrag({ screen, key, group });
    },
    onDragEnd: () => { setDrag(null); setOver(null); },
    onDragOver: (e: DragEvent) => {
      if (!drag || drag.screen !== screen || drag.group !== group) return;
      e.preventDefault();
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const place = axis === "x" ? (e.clientX < r.left + r.width / 2 ? "before" : "after") : (e.clientY < r.top + r.height / 2 ? "before" : "after");
      if (over?.key !== key || over.place !== place) setOver({ key, place });
    },
    onDrop: (e: DragEvent) => {
      e.preventDefault();
      if (drag && drag.screen === screen && drag.group === group && drag.key !== key) {
        dispatch({ type: "move", screen, key: drag.key, targetKey: key, place: over?.place ?? "before" });
      }
      setDrag(null); setOver(null);
    },
  } : {};
  const cls = (key: string, group: string, screen: string) => {
    const out: string[] = [];
    if (drag?.key === key) out.push("dragging");
    if (drag && drag.group === group && drag.screen === screen && over?.key === key && drag.key !== key) out.push(`drop-${over.place}`);
    return out.join(" ");
  };
  return { bind, cls };
}

// ---------------------------------------------------------------- katalog listesi

function CatalogList({ catalog, layout, screen, selected, onSelect, dispatch }: {
  catalog: CatalogItem[]; layout: Layout; screen: string; selected: string;
  onSelect: (k: string) => void; dispatch: (a: EditorAction) => void;
}) {
  const { bind, cls } = useDnd(dispatch, "y");
  const items = screenItems(layout, catalog, screen, true);
  const groups = groupsOf(catalog, screen);
  return (
    <div className="td-list" data-testid="catalog-list">
      {groups.map((g) => (
        <div key={g || "_"} className="td-list-group">
          {g && <div className="td-list-group-title"><span className="td-swatch" style={{ background: accentOf(g) }} />{g}</div>}
          {items.filter((x) => x.item.group === g).map(({ item, line }) => (
            <div key={item.key}
              className={`td-row ${selected === item.key ? "on" : ""} ${line.visible ? "" : "off"} ${cls(item.key, g, screen)}`}
              onClick={() => onSelect(item.key)} data-key={item.key}
              {...bind(screen, item.key, g, item.kind === "tile")}>
              {item.kind === "tile" ? <span className="td-grip" title="Sürükleyerek sırala"><Icon name="GRIP" size={14} /></span> : <span className="td-grip-gap" />}
              <span className="td-row-icon" style={{ color: accentOf(item.group || "Giden") }}><Icon name={glyphFor(item.kind === "tile" ? item.key : "BUTTON")} size={16} /></span>
              <span className="td-row-text">
                <span className="td-row-label">{displayLabel(item, line)}</span>
                {line.label && <span className="td-row-sub">Standart: {item.label}</span>}
                {!line.label && item.availability && <span className="td-row-sub">{item.availability}</span>}
              </span>
              {requiredFlags(line).length > 0 && <span className="td-pill" title="Zorunlu okutma">{requiredFlags(line).map((f) => FLAG_SHORT[f]).join("+")}</span>}
              <button className={`td-eye ${line.visible ? "" : "off"}`} disabled={item.locked}
                title={item.locked ? "Bu öğe gizlenemez" : line.visible ? "Gizle" : "Göster"}
                aria-label={`${displayLabel(item, line)} ${line.visible ? "gizle" : "göster"}`}
                onClick={(e) => { e.stopPropagation(); dispatch({ type: "toggle", screen, key: item.key }); }}>
                <Icon name={item.locked ? "LOCK" : line.visible ? "EYE" : "EYE_OFF"} size={16} />
              </button>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function requiredFlags(line: LayoutLine): ScanFlag[] {
  const out: ScanFlag[] = [];
  if (line.requireLp) out.push("LP");
  if (line.requireLot) out.push("LOT");
  if (line.requireBin) out.push("BIN");
  return out;
}

// ---------------------------------------------------------------- telefon

function Phone({ catalog, layout, screen, screenTitle, selected, editable, showHidden, onSelect, dispatch, onOpenScreen, onBack }: {
  catalog: CatalogItem[]; layout: Layout; screen: string; screenTitle: string; selected: string; editable: boolean; showHidden: boolean;
  onSelect: (k: string) => void; dispatch: (a: EditorAction) => void; onOpenScreen: (tileKey: string) => void; onBack: () => void;
}) {
  const { bind, cls } = useDnd(dispatch, "x");
  const items = screenItems(layout, catalog, screen, showHidden);
  const isHome = screen === "HOME";
  return (
    <div className="td-phone" data-testid="phone">
      <div className="td-phone-notch" />
      <div className="td-phone-screen">
        <div className="td-status"><span>09:41</span><span className="td-status-r">◔ ▮▮▮ 86%</span></div>
        <div className="td-appbar">
          {!isHome && <button className="td-appbar-back" onClick={onBack}>‹ Menü</button>}
          <span className="td-appbar-title">{isHome ? "Ana Menü" : screenTitle}</span>
          <span className="td-appbar-pill"><span className="td-dot ok" />Bağlı</span>
        </div>
        <div className="td-phone-content">
          {isHome ? (
            <>
              <div className="td-home-header">
                <div className="td-home-brand">BADE</div>
                <div>
                  <div className="td-home-company">BADE Natural · E-DefterSandbox</div>
                  <div className="td-home-user">DEPO-01 · Ahmet Yılmaz</div>
                </div>
              </div>
              {groupsOf(catalog, "HOME").map((g) => {
                const tiles = items.filter((x) => x.item.group === g);
                if (!tiles.length) return null;
                return (
                  <div key={g} className="td-cat">
                    <div className="td-cat-title"><span className="td-cat-bar" style={{ background: accentOf(g) }} />{g}</div>
                    <div className="td-tiles">
                      {tiles.map(({ item, line }) => (
                        <div key={item.key} data-key={item.key}
                          className={`td-tile ${selected === item.key ? "on" : ""} ${line.visible ? "" : "off"} ${cls(item.key, g, "HOME")}`}
                          style={{ ["--accent" as string]: accentOf(g) }}
                          onClick={() => onSelect(item.key)}
                          onDoubleClick={() => onOpenScreen(item.key)}
                          {...bind("HOME", item.key, g, editable)}>
                          <span className="td-tile-icon"><Icon name={glyphFor(item.key)} size={22} /></span>
                          <span className="td-tile-label">{displayLabel(item, line)}</span>
                          <span className="td-tile-desc">{line.note.trim() || item.description}</span>
                          {!line.visible && <span className="td-tile-hidden"><Icon name="EYE_OFF" size={12} />Gizli</span>}
                          {requiredFlags(line).length > 0 && <span className="td-tile-req"><Icon name="SCAN" size={11} />{requiredFlags(line).map((f) => FLAG_SHORT[f]).join("+")}</span>}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
              <div className="td-help-btn">? Nasıl Kullanılır</div>
            </>
          ) : (
            <div className="td-screen-mock">
              <div className="td-mock-search"><Icon name="SCAN" size={16} />Barkod okutun veya arayın…</div>
              {items.length === 0 && <div className="td-mock-empty">Bu ekranda görünür düğme kalmadı.</div>}
              {items.map(({ item, line }) => (
                <div key={item.key} data-key={item.key}
                  className={`td-mock-btn ${selected === item.key ? "on" : ""} ${line.visible ? "" : "off"}`}
                  onClick={() => onSelect(item.key)}>
                  <span>{displayLabel(item, line)}</span>
                  {!line.visible && <span className="td-tile-hidden"><Icon name="EYE_OFF" size={12} />Gizli</span>}
                </div>
              ))}
              <div className="td-mock-list">
                {[1, 2, 3].map((i) => <div key={i} className="td-mock-card"><span /><span /></div>)}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- özellikler paneli

function Inspector({ item, line, dispatch, catalog, layout }: {
  item: CatalogItem; line: LayoutLine; dispatch: (a: EditorAction) => void; catalog: CatalogItem[]; layout: Layout;
}) {
  const isTile = item.kind === "tile";
  const siblings = screenItems(layout, catalog, item.screen, true).filter((x) => x.item.group === item.group);
  const pos = siblings.findIndex((x) => x.item.key === item.key);
  const modified = !line.visible || line.label || line.note || line.requireLp || line.requireLot || line.requireBin || line.sort !== item.sort;
  return (
    <div className="td-insp" data-testid="inspector">
      <div className="td-insp-head">
        <span className="td-insp-icon" style={{ background: `${accentOf(item.group || "Giden")}1f`, color: accentOf(item.group || "Giden") }}>
          <Icon name={glyphFor(isTile ? item.key : "BUTTON")} size={22} />
        </span>
        <div>
          <div className="td-insp-title">{displayLabel(item, line)}</div>
          <div className="td-insp-sub">{isTile ? `Ana menü kutusu · ${item.group}` : "Ekran düğmesi"}</div>
        </div>
      </div>
      {item.availability && <div className="td-note"><Icon name="INFO" size={14} />{item.availability}</div>}

      <label className="td-switch td-switch-block">
        <input type="checkbox" checked={line.visible} disabled={item.locked} onChange={() => dispatch({ type: "toggle", screen: item.screen, key: item.key })} />
        <span className="td-switch-track"><span /></span>
        <span>Terminalde görünür{item.locked && <em className="td-muted"> — erişim için gerekli, gizlenemez</em>}</span>
      </label>

      {isTile && (
        <>
          <label className="td-field td-field-block">
            <span>Görünen ad</span>
            <input value={line.label} placeholder={item.label} maxLength={50} data-testid="label-input"
              onChange={(e) => dispatch({ type: "label", screen: item.screen, key: item.key, value: e.target.value })} />
            <small>Boş bırakılırsa standart ad: <b>{item.label}</b></small>
          </label>
          <label className="td-field td-field-block">
            <span>Alt yazı / yardım notu</span>
            <textarea rows={2} value={line.note} placeholder={item.description} maxLength={250}
              onChange={(e) => dispatch({ type: "note", screen: item.screen, key: item.key, value: e.target.value })} />
            <small>Doluysa terminalde kutunun alt satırında görünür.</small>
          </label>
          <div className="td-field td-field-block">
            <span>Sıra ({item.group} içinde)</span>
            <div className="td-order">
              <button className="td-icon-btn" disabled={pos <= 0} aria-label="Yukarı taşı" onClick={() => dispatch({ type: "step", screen: item.screen, key: item.key, delta: -1 })}><Icon name="UP" /></button>
              <span><b>{pos + 1}</b> / {siblings.length}</span>
              <button className="td-icon-btn" disabled={pos >= siblings.length - 1} aria-label="Aşağı taşı" onClick={() => dispatch({ type: "step", screen: item.screen, key: item.key, delta: 1 })}><Icon name="DOWN" /></button>
            </div>
          </div>
        </>
      )}
      {!isTile && (
        <>
          <p className="td-insp-desc">{item.description}</p>
          <label className="td-field td-field-block">
            <span>Not (yalnız BC'de görünür)</span>
            <textarea rows={2} value={line.note} maxLength={250} placeholder="Ör. DKÇ istemedi, 21.10 Merve"
              onChange={(e) => dispatch({ type: "note", screen: item.screen, key: item.key, value: e.target.value })} />
          </label>
        </>
      )}

      {item.flags.length > 0 && (
        <fieldset className="td-flags">
          <legend>Zorunlu okutma</legend>
          {item.flags.map((f) => {
            const checked = f === "LP" ? line.requireLp : f === "LOT" ? line.requireLot : line.requireBin;
            return (
              <label key={f} className="td-check">
                <input type="checkbox" checked={checked} onChange={(e) => dispatch({ type: "flag", screen: item.screen, key: item.key, flag: f, value: e.target.checked })} />
                {FLAG_TEXT[f]}
              </label>
            );
          })}
          <small>Kural terminale iletilir; destekleyen terminal sürümünde uygulanır.</small>
        </fieldset>
      )}

      <button className="td-btn td-btn-ghost" disabled={!modified} onClick={() => dispatch({ type: "resetItem", screen: item.screen, key: item.key, defaults: item })}>
        <Icon name="RESET" />Standarda döndür
      </button>
    </div>
  );
}

// ---------------------------------------------------------------- yeni yerleşim

type NewLayoutPayload = { code: string; description: string; appliesTo: AppliesTo; appliesToCode: string; copyFrom: string };

function NewLayoutDialog({ data, onCancel, onCreate, currentCode }: {
  data: DesignerData; onCancel: () => void; onCreate: (p: NewLayoutPayload) => void; currentCode: string;
}) {
  const [p, setP] = useState<NewLayoutPayload>({ code: "", description: "", appliesTo: "role", appliesToCode: "", copyFrom: currentCode });
  const code = p.code.trim().toUpperCase();
  const exists = data.layouts.some((l) => l.code === code);
  const valid = code.length > 0 && code.length <= 20 && !exists && (p.appliesTo === "all" || p.appliesToCode !== "");
  return (
    <div className="td-modal-bg" role="dialog" aria-modal="true" aria-label="Yeni yerleşim">
      <div className="td-modal">
        <h2>Yeni yerleşim</h2>
        <label className="td-field td-field-block">
          <span>Kod</span>
          <input autoFocus value={p.code} maxLength={20} placeholder="ör. DEPOCU" onChange={(e) => setP({ ...p, code: e.target.value.toUpperCase() })} />
          {exists && <small className="td-err">Bu kod zaten var.</small>}
        </label>
        <label className="td-field td-field-block">
          <span>Açıklama</span>
          <input value={p.description} maxLength={100} placeholder="ör. Depo operatörü — sade menü" onChange={(e) => setP({ ...p, description: e.target.value })} />
        </label>
        <div className="td-field td-field-block">
          <span>Uygulandığı</span>
          <div className="td-seg">
            {APPLIES.map((a) => (
              <button key={a.value} className={p.appliesTo === a.value ? "on" : ""} onClick={() => setP({ ...p, appliesTo: a.value, appliesToCode: "" })}>{a.label}</button>
            ))}
          </div>
        </div>
        {p.appliesTo !== "all" && (
          <label className="td-field td-field-block">
            <span>{p.appliesTo === "role" ? "Rol" : "Terminal"}</span>
            <select value={p.appliesToCode} onChange={(e) => setP({ ...p, appliesToCode: e.target.value })}>
              <option value="">Seçin…</option>
              {(p.appliesTo === "role" ? data.roles.map((r) => ({ code: r.code, text: `${r.code} — ${r.description}` })) : data.terminals.map((t) => ({ code: t.code, text: t.code })))
                .map((o) => <option key={o.code} value={o.code}>{o.text}</option>)}
            </select>
          </label>
        )}
        <label className="td-field td-field-block">
          <span>Başlangıç</span>
          <select value={p.copyFrom} onChange={(e) => setP({ ...p, copyFrom: e.target.value })}>
            <option value="">Standart (bugünkü terminal menüsü)</option>
            {data.layouts.map((l) => <option key={l.code} value={l.code}>{l.code} kopyası</option>)}
          </select>
        </label>
        <p className="td-muted td-small">Öncelik: <b>Terminal</b> &gt; <b>Rol</b> &gt; <b>Tüm terminaller</b>. Bir terminale tek bir yerleşim uygulanır.</p>
        <div className="td-modal-actions">
          <button className="td-btn" onClick={onCancel}>Vazgeç</button>
          <button className="td-btn td-btn-primary" disabled={!valid} onClick={() => onCreate({ ...p, code })}>Oluştur</button>
        </div>
      </div>
    </div>
  );
}

