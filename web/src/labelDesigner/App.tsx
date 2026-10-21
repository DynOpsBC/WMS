// Etiket tasarımcısı kök bileşeni: durum, BC köprüsü, kısayollar.
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { isInsideBc, listen, raise, setDevHandler, simulateIncoming, type IncomingMessage } from "./bridge";
import { createElement, nextElementId, normalizeDesign, parseIncoming, sampleValues } from "./model/design";
import { layoutContext, type LayoutContext } from "./model/layout";
import {
  addElement,
  duplicateElements,
  fitIntoLabel,
  mapElements,
  nextImageId,
  nudge,
  placeAt,
  removeElements,
  rotateTo,
  syncTextHeight,
  updateElement,
  withImageAspect,
} from "./model/ops";
import type { Dpi, LabelDesign, LabelElement, LabelImage, Rotation } from "./model/types";
import { dotsPerMm, mmToDots } from "./model/units";
import { validateDesign } from "./model/validate";
import { parseGfa, type MonoBitmap } from "./render/gf";
import { imageElementBitmap, loadImage, makeSampleLogo, readImageFile } from "./render/imageRaster";
import { renderLabel } from "./render/renderLabel";
import { SAMPLE_DESIGN } from "./sampleDesign";
import { applyTemplate, templateUsesLogo, type LabelTemplate } from "./templates";
import { TemplateGallery } from "./ui/TemplateGallery";
import { buildDesignJson } from "./state/exportDesign";
import { historyReducer, initHistory } from "./state/history";
import { useDecodedImages } from "./state/useDecodedImages";
import { Palette, type PalettePayload } from "./ui/Palette";
import { PreviewModal, Toasts, WarningsBar, type PreviewState, type Toast } from "./ui/Overlays";
import { ElementPanel, LabelPanel, MultiPanel } from "./ui/PropertiesPanel";
import { fitZoom, Stage } from "./ui/Stage";
import { TopBar } from "./ui/TopBar";

const COMPANY_IMAGE_ID = "COMPANY";
const EMPTY_DESIGN: LabelDesign = normalizeDesign({ version: 1, code: "", kind: "Item", widthMm: 80, heightMm: 40, dpi: 203, elements: [] });
const ZOOM_STEPS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12];
const PREVIEW_TIMEOUT_MS = 30_000;
const LOGO_TIMEOUT_MS = 20_000;

let controlReadySent = false;

function ctxOf(d: LabelDesign): LayoutContext {
  return layoutContext(d, sampleValues(d));
}

function toPngSrc(base64: string): string {
  const s = base64.trim();
  return s.startsWith("data:") ? s : `data:image/png;base64,${s}`;
}

export function App() {
  const insideBc = useMemo(isInsideBc, []);
  const [hist, dispatch] = useReducer(historyReducer, undefined, () => initHistory(insideBc ? EMPTY_DESIGN : normalizeDesign(SAMPLE_DESIGN)));
  const design = hist.present;
  const [loaded, setLoaded] = useState(!insideBc);
  const [selection, setSelection] = useState<string[]>([]);
  const [zoom, setZoom] = useState(2);
  const [zoomMode, setZoomMode] = useState<"fit" | "manual">("fit");
  const [gridStep, setGridStep] = useState(1);
  const [showRulers, setShowRulers] = useState(true);
  const [stageSize, setStageSize] = useState({ w: 0, h: 0 });
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [preview, setPreview] = useState<PreviewState>({ open: false, status: "loading", designPng: "", realPng: "", error: "" });
  const [warnOpen, setWarnOpen] = useState(false);
  const [focusToken, setFocusToken] = useState(0);
  const [logoPending, setLogoPending] = useState(false);
  const [gallery, setGallery] = useState<{ open: boolean; mode: "browse" | "start" }>({ open: false, mode: "browse" });
  const [, setSavedTick] = useState(0);

  const savedRef = useRef<LabelDesign>(design);
  const prevSavedRef = useRef<LabelDesign | null>(null);
  const savePendingRef = useRef(false);
  // BC "activeAtLoad": BC Aktif'i yalnız kullanıcı değiştirdiyse yazar. Taban yüklemede
  // BC'den gelir, her başarılı kayıtta gönderilen değere çekilir.
  const activeAtLoadRef = useRef<boolean | undefined>(undefined);
  const sentActiveRef = useRef<boolean | undefined>(undefined);
  const designRef = useRef(design);
  designRef.current = design;
  const selectionRef = useRef(selection);
  selectionRef.current = selection;
  const logoTargetRef = useRef<string | null>(null);
  const logoTimer = useRef<number | undefined>(undefined);
  const previewTimer = useRef<number | undefined>(undefined);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const uploadTargetRef = useRef<string | null>(null);
  const toastSeq = useRef(0);

  const readOnly = Boolean(design.readOnly);
  const dirty = design !== savedRef.current;
  const values = useMemo(() => sampleValues(design), [design]);
  const ctx = useMemo(() => layoutContext(design, values), [design, values]);
  const warnings = useMemo(() => validateDesign(design, ctx), [design, ctx]);
  const warnedIds = useMemo(() => new Set(warnings.map((w) => w.elementId).filter((id): id is string => Boolean(id))), [warnings]);
  const decoded = useDecodedImages(design.images);

  // ------------------------------------------------------------ yardımcılar
  const toast = useCallback((kind: Toast["kind"], text: string, action?: Toast["action"]) => {
    toastSeq.current += 1;
    const id = toastSeq.current;
    setToasts((t) => [...t.slice(-3), { id, kind, text, action }]);
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), action ? 15000 : kind === "error" ? 9000 : 4500);
  }, []);

  const commit = useCallback((update: (d: LabelDesign) => LabelDesign, key?: string) => dispatch({ type: "commit", update, key }), []);

  const patchElement = useCallback(
    (id: string, patch: Partial<LabelElement>, key?: string) =>
      commit((d) => {
        const el = d.elements.find((e) => e.id === id);
        if (!el) return d;
        return updateElement(d, id, syncTextHeight({ ...el, ...patch }, ctxOf(d)));
      }, key),
    [commit],
  );

  /** Bir tasarım için resim elemanlarının 1 bit hali (çözülmüş resimden ya da kayıtlı ^GFA'dan). */
  const bitmapFor = useCallback(
    (d: LabelDesign) =>
      (el: LabelElement): MonoBitmap | null => {
        const image = d.images.find((i) => i.id === el.imageId);
        const dec = image ? decoded.get(image) : null;
        if (image && dec) return imageElementBitmap(el, image, dec, d.dpi);
        if (el.imageGf) return parseGfa(el.imageGf);
        return null;
      },
    // decoded.version: çözülen resimler gelince yeniden çiz
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [decoded.version],
  );
  const imageBitmap = useMemo(() => bitmapFor(design), [bitmapFor, design]);

  const designJson = useCallback(() => buildDesignJson(designRef.current, decoded.ensure), [decoded.ensure]);

  // ------------------------------------------------------------ BC'den gelenler
  const finishLogo = useCallback(() => {
    window.clearTimeout(logoTimer.current);
    setLogoPending(false);
    logoTargetRef.current = null;
  }, []);

  const applyLogo = useCallback(
    async (logo: LabelImage) => {
      let nw = logo.widthPx ?? 0;
      let nh = logo.heightPx ?? 0;
      try {
        const img = await loadImage(logo.dataUrl);
        nw = img.naturalWidth;
        nh = img.naturalHeight;
      } catch {
        /* oran bilinmiyor */
      }
      const d = designRef.current;
      const target = logoTargetRef.current ? d.elements.find((e) => e.id === logoTargetRef.current && e.type === "image") : undefined;
      if (target) {
        commit((cur) => updateElement(cur, target.id, withImageAspect({ ...target, imageId: COMPANY_IMAGE_ID }, nw, nh, cur)));
        setSelection([target.id]);
      } else if (!d.elements.some((e) => e.type === "image" && e.imageId === COMPANY_IMAGE_ID)) {
        const id = nextElementId(d);
        let el = createElement("image", id, { imageId: COMPANY_IMAGE_ID });
        el = { ...el, xMm: 2, yMm: 2, wMm: Math.min(25, d.widthMm - 4) };
        el = fitIntoLabel(withImageAspect(el, nw, nh, d), d);
        commit((cur) => addElement(cur, el));
        setSelection([id]);
      }
      toast("success", "Şirket logosu eklendi.");
    },
    [commit, toast],
  );

  const handleIncoming = useCallback(
    (message: IncomingMessage) => {
      if (message.type === "load") {
        let parsed: ReturnType<typeof parseIncoming>;
        try {
          parsed = parseIncoming(message.json);
        } catch (err) {
          toast("error", `Tasarım okunamadı: ${err instanceof Error ? err.message : String(err)}`);
          return;
        }
        if (parsed.merge === "images") {
          // CompanyLogoRequested yanıtı: yalnız resimler; kaydedilmemiş öğeler korunur.
          const incoming = parsed.design.images;
          commit((d) => {
            const local = new Set(d.images.map((i) => i.id));
            const add = incoming.filter((i) => i.id === COMPANY_IMAGE_ID || !local.has(i.id));
            if (add.length === 0) return d;
            const byId = new Map(d.images.map((i) => [i.id, i]));
            for (const img of add) byId.set(img.id, img);
            return { ...d, images: [...byId.values()] };
          });
          const logo = incoming.find((i) => i.id === COMPANY_IMAGE_ID && i.dataUrl);
          const wanted = logoPending || logoTargetRef.current !== null;
          if (logo && wanted) void applyLogo(logo);
          else if (!logo && wanted) toast("error", "Şirket logosu bulunamadı. BC'de Şirket Bilgileri sayfasına resim ekleyin.");
          finishLogo();
          return;
        }
        dispatch({ type: "load", design: parsed.design });
        // Yeni (boş) tasarım: hazır şablonla başlamayı öner.
        if (parsed.design.elements.length === 0 && !parsed.design.readOnly) setGallery({ open: true, mode: "start" });
        savedRef.current = parsed.design;
        activeAtLoadRef.current = typeof parsed.design.activeAtLoad === "boolean" ? parsed.design.activeAtLoad : parsed.design.active;
        savePendingRef.current = false;
        setSelection([]);
        setLoaded(true);
        setZoomMode("fit");
        finishLogo();
        return;
      }
      if (message.type === "preview") {
        window.clearTimeout(previewTimer.current);
        setPreview((p) =>
          message.pngBase64.trim()
            ? { ...p, open: true, status: "ready", realPng: toPngSrc(message.pngBase64), error: "" }
            : { ...p, status: "error", error: "BC boş önizleme döndürdü." },
        );
        return;
      }
      // ShowMessage
      toast(message.kind, message.text);
      if (message.kind === "error") {
        if (savePendingRef.current && prevSavedRef.current) {
          savedRef.current = prevSavedRef.current;
          setSavedTick((t) => t + 1);
        }
        savePendingRef.current = false;
        setPreview((p) => (p.open && p.status === "loading" ? { ...p, status: "error", error: message.text } : p));
        if (logoPending) finishLogo();
      } else if (message.kind === "success") {
        if (savePendingRef.current && sentActiveRef.current !== undefined) activeAtLoadRef.current = sentActiveRef.current;
        savePendingRef.current = false;
      }
    },
    [applyLogo, commit, finishLogo, logoPending, toast],
  );

  useEffect(() => listen(handleIncoming), [handleIncoming]);

  // BC'ye hazır olduğumuzu bildir (BC LoadDesign ile yanıt verir). Tek sefer.
  useEffect(() => {
    if (controlReadySent) return;
    controlReadySent = true;
    raise("ControlReady");
  }, []);

  // BC dışı: olayları taklit et.
  useEffect(() => {
    if (insideBc) return;
    setDevHandler((event, args) => {
      window.setTimeout(() => {
        switch (event) {
          case "SaveRequested":
            // eslint-disable-next-line no-console
            console.log("[Etiket Tasarımcısı] DesignJson", JSON.parse(args[0] ?? "{}"));
            simulateIncoming({ type: "message", kind: "success", text: "Geliştirme modu: tasarım kaydedilmedi, JSON konsola yazıldı." });
            break;
          case "TestPrintRequested":
            simulateIncoming({ type: "message", kind: "info", text: "Geliştirme modu: yazıcı yok, test baskı gönderilmedi." });
            break;
          case "PreviewRequested":
            simulateIncoming({ type: "message", kind: "error", text: "BC dışında Labelary kontrolü yapılamaz." });
            break;
          case "CompanyLogoRequested":
            simulateIncoming({
              type: "load",
              json: JSON.stringify({ ...SAMPLE_DESIGN, merge: "images", images: [{ id: COMPANY_IMAGE_ID, name: "Şirket logosu", dataUrl: makeSampleLogo() }] }),
            });
            break;
          default:
            break;
        }
      }, 250);
    });
    return () => setDevHandler(null);
  }, [insideBc]);

  // ------------------------------------------------------------ görünüm
  useEffect(() => {
    if (zoomMode === "fit" && stageSize.w > 0) setZoom(fitZoom(stageSize.w, stageSize.h, design, showRulers));
  }, [zoomMode, stageSize, design.widthMm, design.heightMm, showRulers]); // eslint-disable-line react-hooks/exhaustive-deps

  // Geri al sonrası olmayan öğeleri seçimden çıkar.
  useEffect(() => {
    const ids = new Set(design.elements.map((e) => e.id));
    setSelection((sel) => (sel.every((id) => ids.has(id)) ? sel : sel.filter((id) => ids.has(id))));
  }, [design.elements]);

  const zoomBy = (dir: 1 | -1) => {
    setZoomMode("manual");
    setZoom((z) => {
      if (dir > 0) return ZOOM_STEPS.find((s) => s > z + 0.001) ?? z;
      return [...ZOOM_STEPS].reverse().find((s) => s < z - 0.001) ?? z;
    });
  };

  // ------------------------------------------------------------ düzenleme
  const addFromPalette = useCallback(
    (payload: PalettePayload, at?: { x: number; y: number }) => {
      if (readOnly) return;
      const d = designRef.current;
      const c = ctxOf(d);
      const id = nextElementId(d);
      const firstImage = d.images[0];
      let el = createElement(payload.type, id, {
        field: payload.field ?? d.fields[0]?.key ?? "",
        imageId: payload.type === "image" ? firstImage?.id ?? "" : undefined,
      });
      if (payload.type === "image" && firstImage) {
        const dec = decoded.get(firstImage);
        if (dec) el = withImageAspect(el, dec.naturalWidth, dec.naturalHeight, d);
      }
      el = syncTextHeight(fitIntoLabel(el, d), c);
      el = placeAt(el, at?.x ?? d.widthMm / 2, at?.y ?? d.heightMm / 2, d, c, gridStep);
      commit((cur) => addElement(cur, el));
      setSelection([id]);
    },
    [commit, decoded, gridStep, readOnly],
  );

  const deleteSelected = useCallback(() => {
    const sel = selectionRef.current;
    if (readOnly || sel.length === 0) return;
    commit((d) => removeElements(d, sel));
    setSelection([]);
  }, [commit, readOnly]);

  const duplicateSelected = useCallback(() => {
    const sel = selectionRef.current;
    if (readOnly || sel.length === 0) return;
    const { newIds } = duplicateElements(designRef.current, sel);
    commit((d) => duplicateElements(d, sel).design);
    setSelection(newIds);
  }, [commit, readOnly]);

  const rotateSelected = useCallback(
    (rotation?: Rotation) => {
      const sel = selectionRef.current;
      if (readOnly || sel.length === 0) return;
      commit((d) => {
        const c = ctxOf(d);
        return mapElements(d, sel, (el) => {
          const target = rotation ?? (((el.rotation + 90) % 360) as Rotation);
          const next = el.type === "line" || el.type === "box" ? rotateTo(el, rotation === undefined ? 90 : target, c) : rotateTo(el, target, c);
          return syncTextHeight(next, c);
        });
      });
    },
    [commit, readOnly],
  );

  const openUpload = useCallback((targetId: string | null) => {
    if (readOnly) return;
    uploadTargetRef.current = targetId;
    fileInputRef.current?.click();
  }, [readOnly]);

  const onFileChosen = async (file: File | undefined) => {
    if (!file) return;
    if (!/^image\/(png|jpeg)$/.test(file.type)) {
      toast("error", "Yalnız PNG veya JPG resim yüklenebilir.");
      return;
    }
    try {
      const { dataUrl, width, height } = await readImageFile(file);
      const d = designRef.current;
      const imageId = nextImageId(d);
      const name = file.name.replace(/\.[^.]+$/, "").slice(0, 50) || imageId;
      const image: LabelImage = { id: imageId, name, dataUrl, widthPx: width, heightPx: height };
      const targetId = uploadTargetRef.current;
      const target = targetId ? d.elements.find((e) => e.id === targetId && e.type === "image") : undefined;
      if (target) {
        commit((cur) => updateElement({ ...cur, images: [...cur.images, image] }, target.id, withImageAspect({ ...target, imageId }, width, height, cur)));
        setSelection([target.id]);
      } else {
        const c = ctxOf(d);
        const id = nextElementId(d);
        let el = createElement("image", id, { imageId });
        el = { ...el, wMm: Math.min(30, d.widthMm - 4) };
        el = fitIntoLabel(withImageAspect(el, width, height, d), d);
        el = placeAt(el, d.widthMm / 2, d.heightMm / 2, d, c, gridStep);
        commit((cur) => addElement({ ...cur, images: [...cur.images, image] }, el));
        setSelection([id]);
      }
      toast("success", "Resim eklendi. Yazıcı siyah-beyaz basar; önizleme basılacak hali gösterir.");
    } catch (err) {
      toast("error", err instanceof Error ? err.message : "Resim okunamadı.");
    }
  };

  const requestLogo = useCallback(() => {
    if (readOnly) return;
    const sel = selectionRef.current;
    const d = designRef.current;
    const selectedImage = sel.length === 1 ? d.elements.find((e) => e.id === sel[0] && e.type === "image") : undefined;
    logoTargetRef.current = selectedImage?.id ?? null;
    const existing = d.images.find((i) => i.id === COMPANY_IMAGE_ID && i.dataUrl);
    if (existing) {
      // Logo zaten elimizde: BC'ye sormadan kullan.
      void applyLogo(existing).then(() => (logoTargetRef.current = null));
      return;
    }
    setLogoPending(true);
    window.clearTimeout(logoTimer.current);
    logoTimer.current = window.setTimeout(() => {
      setLogoPending(false);
      logoTargetRef.current = null;
      toast("error", "BC şirket logosunu göndermedi.");
    }, LOGO_TIMEOUT_MS);
    raise("CompanyLogoRequested");
  }, [applyLogo, readOnly, toast]);

  const requestLogoRef = useRef(requestLogo);
  requestLogoRef.current = requestLogo;

  const imageAspect = useCallback(() => {
    const sel = selectionRef.current;
    const d = designRef.current;
    const el = sel.length === 1 ? d.elements.find((e) => e.id === sel[0]) : undefined;
    const image = el ? d.images.find((i) => i.id === el.imageId) : undefined;
    const dec = image ? decoded.get(image) : null;
    if (!el || !dec) return;
    commit((cur) => updateElement(cur, el.id, withImageAspect(el, dec.naturalWidth, dec.naturalHeight, cur)));
  }, [commit, decoded]);

  const applyTemplateChoice = useCallback(
    (t: LabelTemplate) => {
      if (readOnly) return;
      commit((d) => applyTemplate(d, t));
      setGallery((g) => ({ ...g, open: false }));
      setZoomMode("fit");
      const logoIndex = t.elements.findIndex((e) => e.type === "image" && e.imageId === COMPANY_IMAGE_ID);
      const hasLogo = designRef.current.images.some((i) => i.id === COMPANY_IMAGE_ID && i.dataUrl);
      if (templateUsesLogo(t) && !hasLogo && logoIndex >= 0) {
        setSelection([`e${logoIndex + 1}`]);
        toast("info", `“${t.name}” uygulandı. Bu şablonda şirket logosu var.`, { label: "Şirket logosunu getir", run: () => requestLogoRef.current() });
      } else {
        setSelection([]);
        toast("success", `“${t.name}” uygulandı. Geri Al ile önceki tasarıma dönebilirsiniz.`);
      }
    },
    [commit, readOnly, toast],
  );

  // ------------------------------------------------------------ BC olayları
  const save = useCallback(async () => {
    if (readOnly) {
      toast("error", "Bu tasarımı değiştirme izniniz yok (salt okunur).");
      return;
    }
    const d = designRef.current;
    const base = activeAtLoadRef.current;
    const json = await buildDesignJson(base === undefined ? d : { ...d, activeAtLoad: base }, decoded.ensure);
    sentActiveRef.current = d.active;
    prevSavedRef.current = savedRef.current;
    savedRef.current = d;
    savePendingRef.current = true;
    setSavedTick((t) => t + 1);
    raise("SaveRequested", json);
  }, [decoded.ensure, readOnly, toast]);

  const testPrint = useCallback(async () => {
    const json = await designJson();
    toast("info", "Test baskısı hazırlanıyor (örnek verilerle)…");
    raise("TestPrintRequested", json);
  }, [designJson, toast]);

  const designPng = useCallback((): string => {
    const d = designRef.current;
    const canvas = document.createElement("canvas");
    const wDots = mmToDots(d.widthMm, d.dpi);
    const hDots = mmToDots(d.heightMm, d.dpi);
    const scale = Math.min(1, 900 / Math.max(wDots, hDots)) * (8 / dotsPerMm(d.dpi)) * 1.5;
    canvas.width = Math.max(1, Math.round(wDots * scale));
    canvas.height = Math.max(1, Math.round(hDots * scale));
    const g = canvas.getContext("2d");
    if (!g) return "";
    renderLabel(g, d, { scale, ctx: ctxOf(d), imageBitmap, showDisabled: false });
    return canvas.toDataURL("image/png");
  }, [imageBitmap]);

  const requestPreview = useCallback(async () => {
    setPreview({ open: true, status: "loading", designPng: designPng(), realPng: "", error: "" });
    const json = await designJson();
    window.clearTimeout(previewTimer.current);
    previewTimer.current = window.setTimeout(() => {
      setPreview((p) => (p.open && p.status === "loading" ? { ...p, status: "error", error: "Labelary yanıt vermedi (internet erişimi gerekli)." } : p));
    }, PREVIEW_TIMEOUT_MS);
    raise("PreviewRequested", json);
  }, [designJson, designPng]);

  // ------------------------------------------------------------ klavye
  const keyHandler = useRef<(e: KeyboardEvent) => void>(() => undefined);
  keyHandler.current = (e: KeyboardEvent) => {
    const t = e.target as HTMLElement | null;
    const typing = !!t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
    const mod = e.ctrlKey || e.metaKey;
    const key = e.key.toLowerCase();
    if (mod && key === "s") {
      e.preventDefault();
      void save();
      return;
    }
    if (typing || preview.open || gallery.open) return;
    if (mod && key === "z" && !e.shiftKey) {
      e.preventDefault();
      if (!readOnly) dispatch({ type: "undo" });
      return;
    }
    if (mod && (key === "y" || (key === "z" && e.shiftKey))) {
      e.preventDefault();
      if (!readOnly) dispatch({ type: "redo" });
      return;
    }
    if (mod && key === "a") {
      e.preventDefault();
      setSelection(designRef.current.elements.map((el) => el.id));
      return;
    }
    if (e.key === "Escape") {
      setSelection([]);
      return;
    }
    const sel = selectionRef.current;
    if (sel.length === 0 || readOnly) return;
    if (mod && key === "d") {
      e.preventDefault();
      duplicateSelected();
    } else if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      deleteSelected();
    } else if (!mod && key === "r") {
      e.preventDefault();
      rotateSelected();
    } else if (e.key.startsWith("Arrow")) {
      e.preventDefault();
      const step = e.shiftKey ? 5 : e.altKey ? 1 / dotsPerMm(designRef.current.dpi) : gridStep || 0.5;
      const dx = e.key === "ArrowLeft" ? -step : e.key === "ArrowRight" ? step : 0;
      const dy = e.key === "ArrowUp" ? -step : e.key === "ArrowDown" ? step : 0;
      commit((d) => nudge(d, sel, dx, dy), `nudge:${sel.join(",")}`);
    }
  };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => keyHandler.current(e);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // ------------------------------------------------------------ çizim
  const single = selection.length === 1 ? design.elements.find((el) => el.id === selection[0]) : undefined;
  const elementWarnings = single ? warnings.filter((w) => w.elementId === single.id) : [];
  const defaultCodeField =
    ["ItemNo", "BinCode", "LPNo", "ZoneCode", "SSCC"].find((k) => design.fields.some((f) => f.key === k)) ?? design.fields[0]?.key ?? "";

  return (
    <div className={`ld-app${readOnly ? " is-readonly" : ""}`}>
      <TopBar
        design={design}
        readOnly={readOnly}
        dirty={dirty}
        canUndo={hist.past.length > 0}
        canRedo={hist.future.length > 0}
        previewBusy={preview.open && preview.status === "loading"}
        onUndo={() => dispatch({ type: "undo" })}
        onRedo={() => dispatch({ type: "redo" })}
        onSize={(w, h) => commit((d) => ({ ...d, widthMm: w, heightMm: h }), "size")}
        onDpi={(dpi: Dpi) => commit((d) => ({ ...d, dpi }))}
        onSave={() => void save()}
        onTestPrint={() => void testPrint()}
        onPreview={() => void requestPreview()}
        onTemplates={() => setGallery({ open: true, mode: "browse" })}
      />
      {readOnly ? <div className="ld-banner">Salt okunur: bu tasarımı değiştirme izniniz yok. Test baskı ve önizleme kullanılabilir.</div> : null}
      <div className="ld-body">
        {readOnly ? null : (
          <Palette
            fields={design.fields}
            defaultCodeField={defaultCodeField}
            onAdd={(p) => addFromPalette(p)}
            onUploadImage={() => openUpload(null)}
            onRequestLogo={requestLogo}
            logoPending={logoPending}
          />
        )}
        <main className="ld-center">
          <div className="ld-stagebar">
            <div className="ld-zoom" role="group" aria-label="Yakınlaştırma">
              <button type="button" className="ld-icon-btn" onClick={() => zoomBy(-1)} aria-label="Uzaklaştır" title="Uzaklaştır">−</button>
              <span className="ld-zoom-value" title="%100 = gerçek boyut">%{Math.round(zoom * 100)}</span>
              <button type="button" className="ld-icon-btn" onClick={() => zoomBy(1)} aria-label="Yakınlaştır" title="Yakınlaştır">+</button>
              <button type="button" className={`ld-btn ld-btn-ghost ld-btn-sm${zoomMode === "fit" ? " is-on" : ""}`} onClick={() => setZoomMode("fit")}>Sığdır</button>
              <button type="button" className="ld-btn ld-btn-ghost ld-btn-sm" onClick={() => { setZoomMode("manual"); setZoom(1); }} title="Gerçek boyut">%100</button>
            </div>
            <label className="ld-stagebar-item">
              <span>Izgara</span>
              <select className="ld-select ld-select-compact" value={gridStep} onChange={(e) => setGridStep(Number(e.currentTarget.value))}>
                <option value={0}>Kapalı</option>
                <option value={0.5}>0,5 mm</option>
                <option value={1}>1 mm</option>
              </select>
            </label>
            <label className="ld-stagebar-item">
              <input type="checkbox" checked={showRulers} onChange={(e) => setShowRulers(e.currentTarget.checked)} /> Cetvel
            </label>
            <span className="ld-topbar-spacer" />
            <span className="ld-muted ld-small ld-stagebar-hint">
              {design.widthMm} × {design.heightMm} mm · {design.dpi} dpi · örnek verilerle gösteriliyor
            </span>
          </div>
          <div className="ld-stage-wrap">
            <Stage
              design={design}
              ctx={ctx}
              selection={selection}
              zoom={zoom}
              gridStep={gridStep}
              showRulers={showRulers}
              readOnly={readOnly}
              imageBitmap={imageBitmap}
              imageVersion={decoded.version}
              warnedIds={warnedIds}
              onSelect={setSelection}
              onGestureBegin={() => dispatch({ type: "gestureBegin" })}
              onGestureUpdate={(update) => dispatch({ type: "gestureUpdate", update })}
              onGestureEnd={() => dispatch({ type: "gestureEnd" })}
              onDropPayload={(payload, x, y) => addFromPalette(payload, { x, y })}
              onEditElement={(id) => {
                setSelection([id]);
                setFocusToken((n) => n + 1);
              }}
              onStageResize={(w, h) => setStageSize((s) => (s.w === w && s.h === h ? s : { w, h }))}
              onOpenTemplates={() => setGallery({ open: true, mode: "start" })}
            />
            {!loaded ? (
              <div className="ld-loading"><span className="ld-spinner" aria-hidden="true" /> Tasarım BC'den yükleniyor…</div>
            ) : null}
          </div>
          <WarningsBar warnings={warnings} open={warnOpen} onToggle={() => setWarnOpen((o) => !o)} onPick={(id) => setSelection([id])} />
        </main>
        <aside className="ld-right" aria-label="Özellikler">
          {single ? (
            <ElementPanel
              key={single.id}
              design={design}
              element={single}
              ctx={ctx}
              warnings={elementWarnings}
              readOnly={readOnly}
              focusToken={focusToken}
              onPatch={(patch, key) => patchElement(single.id, patch, key)}
              onRotate={(r) => rotateSelected(single.type === "line" || single.type === "box" ? 90 : r)}
              onDuplicate={duplicateSelected}
              onDelete={deleteSelected}
              onUploadImage={() => openUpload(single.id)}
              onRequestLogo={requestLogo}
              onImageAspect={imageAspect}
              logoPending={logoPending}
            />
          ) : selection.length > 1 ? (
            <MultiPanel count={selection.length} readOnly={readOnly} onDuplicate={duplicateSelected} onDelete={deleteSelected} onClear={() => setSelection([])} />
          ) : (
            <LabelPanel
              design={design}
              readOnly={readOnly}
              warnedIds={warnedIds}
              onMeta={(patch, key) => commit((d) => ({ ...d, ...patch }), key)}
              onSelect={(id) => setSelection([id])}
              onToggleEnabled={(id, enabled) => patchElement(id, { enabled })}
            />
          )}
        </aside>
      </div>
      <input
        ref={fileInputRef}
        type="file"
        accept="image/png,image/jpeg"
        hidden
        onChange={(e) => {
          const file = e.currentTarget.files?.[0];
          e.currentTarget.value = "";
          void onFileChosen(file);
        }}
      />
      <PreviewModal
        state={preview}
        onClose={() => {
          window.clearTimeout(previewTimer.current);
          setPreview((p) => ({ ...p, open: false }));
        }}
        onRetry={() => void requestPreview()}
      />
      <TemplateGallery
        open={gallery.open}
        mode={gallery.mode}
        design={design}
        bitmapFor={bitmapFor}
        imageVersion={decoded.version}
        onApply={applyTemplateChoice}
        onBlank={() => setGallery((g) => ({ ...g, open: false }))}
        onClose={() => setGallery((g) => ({ ...g, open: false }))}
      />
      <Toasts toasts={toasts} onDismiss={(id) => setToasts((t) => t.filter((x) => x.id !== id))} />
    </div>
  );
}
