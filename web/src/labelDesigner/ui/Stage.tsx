// Orta alan: etiketin gerçek oranlı çizimi + seçme/taşıma/boyutlandırma katmanı.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type DragEvent, type PointerEvent as ReactPointerEvent } from "react";
import { elementName, fieldLabel, isKnownType, resolveValue } from "../model/design";
import { elementGeometry, type ElementGeometry, type LayoutContext } from "../model/layout";
import { moveFrom, resizeElement, updateElement, type Box, type Handle } from "../model/ops";
import type { LabelDesign, LabelElement } from "../model/types";
import { CSS_PX_PER_MM, mmToDots, pxPerMm } from "../model/units";
import type { MonoBitmap } from "../render/gf";
import { renderLabel } from "../render/renderLabel";
import { DRAG_MIME, type PalettePayload } from "./Palette";

const RULER = 22;
const MARGIN = 28;
const MAX_CANVAS_PIXELS = 16_000_000;

interface StageProps {
  design: LabelDesign;
  ctx: LayoutContext;
  selection: string[];
  zoom: number;
  gridStep: number;
  showRulers: boolean;
  readOnly: boolean;
  imageBitmap: (el: LabelElement) => MonoBitmap | null;
  imageVersion: number;
  warnedIds: ReadonlySet<string>;
  onSelect: (ids: string[]) => void;
  onGestureBegin: () => void;
  onGestureUpdate: (update: (d: LabelDesign) => LabelDesign) => void;
  onGestureEnd: () => void;
  onDropPayload: (payload: PalettePayload, xMm: number, yMm: number) => void;
  onEditElement: (id: string) => void;
  onStageResize: (width: number, height: number) => void;
  onOpenTemplates: () => void;
}

type Gesture =
  | { kind: "move"; pointerId: number; startX: number; startY: number; starts: Map<string, { x: number; y: number }>; primaryId: string; moved: boolean }
  | { kind: "resize"; pointerId: number; startX: number; startY: number; start: LabelElement; startBox: Box; handle: Handle };

function handlesFor(el: LabelElement): Handle[] {
  if (el.type === "qr") return ["nw", "ne", "sw", "se"];
  if (el.type === "line") return el.wMm >= el.hMm ? ["w", "e"] : ["n", "s"];
  return ["nw", "n", "ne", "e", "se", "s", "sw", "w"];
}

export function Stage(props: StageProps) {
  const { design, ctx, selection, zoom, gridStep, showRulers, imageBitmap, imageVersion } = props;
  const stageRef = useRef<HTMLDivElement>(null);
  const paperRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const topRulerRef = useRef<HTMLCanvasElement>(null);
  const leftRulerRef = useRef<HTMLCanvasElement>(null);
  const gesture = useRef<Gesture | null>(null);

  const [view, setView] = useState({ w: 0, h: 0 });
  const scale = pxPerMm(zoom);
  const paperW = design.widthMm * scale;
  const paperH = design.heightMm * scale;
  const ruler = showRulers ? RULER : 0;
  // İçerik sahneden küçükse etiketi ortala.
  const contentW = paperW + ruler + 2 * MARGIN;
  const contentH = paperH + ruler + 2 * MARGIN;
  const padX = Math.max(0, (view.w - contentW) / 2);
  const padY = Math.max(0, (view.h - contentH) / 2);
  const offsetX = MARGIN + ruler + padX;
  const offsetY = MARGIN + ruler + padY;

  const geometries = useMemo(() => {
    const m = new Map<string, ElementGeometry>();
    for (const el of design.elements) if (isKnownType(el.type)) m.set(el.id, elementGeometry(el, ctx));
    return m;
  }, [design.elements, ctx]);

  // Etiketi çiz.
  useLayoutEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let dpr = window.devicePixelRatio || 1;
    if (paperW * paperH * dpr * dpr > MAX_CANVAS_PIXELS) dpr = Math.sqrt(MAX_CANVAS_PIXELS / (paperW * paperH));
    const wDots = mmToDots(design.widthMm, design.dpi);
    const hDots = mmToDots(design.heightMm, design.dpi);
    const pxPerDot = (scale * dpr * design.widthMm) / wDots;
    canvas.width = Math.max(1, Math.round(wDots * pxPerDot));
    canvas.height = Math.max(1, Math.round(hDots * pxPerDot));
    const g = canvas.getContext("2d");
    if (!g) return;
    renderLabel(g, design, { scale: pxPerDot, ctx, imageBitmap, showDisabled: true });
  }, [design, ctx, scale, paperW, paperH, imageBitmap, imageVersion]);

  // Cetveller.
  useLayoutEffect(() => {
    if (!showRulers) return;
    drawRuler(topRulerRef.current, design.widthMm, scale, "h");
    drawRuler(leftRulerRef.current, design.heightMm, scale, "v");
  }, [showRulers, design.widthMm, design.heightMm, scale]);

  useEffect(() => {
    const stage = stageRef.current;
    if (!stage) return;
    const report = () => {
      setView((v) => (v.w === stage.clientWidth && v.h === stage.clientHeight ? v : { w: stage.clientWidth, h: stage.clientHeight }));
      props.onStageResize(stage.clientWidth, stage.clientHeight);
    };
    report();
    const ro = new ResizeObserver(report);
    ro.observe(stage);
    return () => ro.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toMm = (clientX: number, clientY: number) => {
    const rect = paperRef.current?.getBoundingClientRect();
    if (!rect) return { x: 0, y: 0 };
    return { x: (clientX - rect.left) / scale, y: (clientY - rect.top) / scale };
  };

  const snapStep = (e: { altKey: boolean }) => (e.altKey ? 0 : gridStep);

  const onElementPointerDown = (e: ReactPointerEvent<HTMLDivElement>, el: LabelElement) => {
    if (e.button !== 0) return;
    e.stopPropagation();
    e.preventDefault();
    const additive = e.shiftKey || e.ctrlKey || e.metaKey;
    let ids: string[];
    if (additive) {
      ids = selection.includes(el.id) ? selection.filter((id) => id !== el.id) : [...selection, el.id];
      props.onSelect(ids);
      if (!ids.includes(el.id)) return;
    } else {
      ids = selection.includes(el.id) ? selection : [el.id];
      if (!selection.includes(el.id)) props.onSelect(ids);
    }
    if (props.readOnly) return;
    const starts = new Map<string, { x: number; y: number }>();
    for (const item of design.elements) if (ids.includes(item.id)) starts.set(item.id, { x: item.xMm, y: item.yMm });
    e.currentTarget.setPointerCapture(e.pointerId);
    gesture.current = { kind: "move", pointerId: e.pointerId, startX: e.clientX, startY: e.clientY, starts, primaryId: el.id, moved: false };
  };

  const onHandlePointerDown = (e: ReactPointerEvent<HTMLDivElement>, el: LabelElement, handle: Handle) => {
    if (e.button !== 0 || props.readOnly) return;
    e.stopPropagation();
    e.preventDefault();
    const geo = geometries.get(el.id);
    if (!geo) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    props.onGestureBegin();
    gesture.current = { kind: "resize", pointerId: e.pointerId, startX: e.clientX, startY: e.clientY, start: el, startBox: { x: geo.x, y: geo.y, w: geo.w, h: geo.h }, handle };
  };

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || g.pointerId !== e.pointerId) return;
    const dxPx = e.clientX - g.startX;
    const dyPx = e.clientY - g.startY;
    if (g.kind === "move") {
      if (!g.moved) {
        if (Math.abs(dxPx) < 3 && Math.abs(dyPx) < 3) return;
        g.moved = true;
        props.onGestureBegin();
      }
      const step = snapStep(e);
      props.onGestureUpdate((d) => moveFrom(d, g.starts, g.primaryId, dxPx / scale, dyPx / scale, step));
    } else {
      const step = snapStep(e);
      props.onGestureUpdate((d) => updateElement(d, g.start.id, resizeElement(g.start, g.startBox, g.handle, dxPx / scale, dyPx / scale, step, ctx)));
    }
  };

  const endGesture = (e: ReactPointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || g.pointerId !== e.pointerId) return;
    gesture.current = null;
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    if (g.kind === "resize" || g.moved) props.onGestureEnd();
  };

  const onDragOver = (e: DragEvent<HTMLDivElement>) => {
    if (!props.readOnly && e.dataTransfer.types.includes(DRAG_MIME)) {
      e.preventDefault();
      e.dataTransfer.dropEffect = "copy";
    }
  };

  const onDrop = (e: DragEvent<HTMLDivElement>) => {
    const raw = e.dataTransfer.getData(DRAG_MIME);
    if (!raw || props.readOnly) return;
    e.preventDefault();
    try {
      const payload = JSON.parse(raw) as PalettePayload;
      const p = toMm(e.clientX, e.clientY);
      props.onDropPayload(payload, p.x, p.y);
    } catch {
      /* yok say */
    }
  };

  const values = ctx.values;
  const single = selection.length === 1 ? design.elements.find((el) => el.id === selection[0]) : undefined;
  const gridPx = gridStep > 0 ? gridStep * scale : 0;
  const showGridLines = gridPx >= 4;
  const majorPx = 10 * scale;

  return (
    <div
      ref={stageRef}
      className="ld-stage"
      onPointerDown={(e) => {
        if (e.button === 0 && !(e.shiftKey || e.ctrlKey || e.metaKey)) props.onSelect([]);
      }}
      onDragOver={onDragOver}
      onDrop={onDrop}
    >
      <div className="ld-stage-inner" style={{ width: Math.max(contentW, view.w), height: Math.max(contentH, view.h) }}>
        {showRulers ? (
          <>
            <canvas ref={topRulerRef} className="ld-ruler ld-ruler-h" style={{ left: offsetX, top: offsetY - RULER, width: paperW, height: RULER }} />
            <canvas ref={leftRulerRef} className="ld-ruler ld-ruler-v" style={{ left: offsetX - RULER, top: offsetY, width: RULER, height: paperH }} />
          </>
        ) : null}
        <div ref={paperRef} className="ld-paper" style={{ left: offsetX, top: offsetY, width: paperW, height: paperH }}>
          <canvas ref={canvasRef} className="ld-canvas" style={{ width: paperW, height: paperH }} />
          {showGridLines ? (
            <div
              className="ld-grid"
              style={{
                backgroundSize: `${majorPx}px ${majorPx}px, ${majorPx}px ${majorPx}px, ${gridPx}px ${gridPx}px, ${gridPx}px ${gridPx}px`,
              }}
            />
          ) : null}
          <div className="ld-overlay" onPointerMove={onPointerMove} onPointerUp={endGesture} onPointerCancel={endGesture}>
            {design.elements.map((el) => {
              const geo = geometries.get(el.id);
              if (!geo) return null;
              const selected = selection.includes(el.id);
              const value = resolveValue(el, values);
              const showPlaceholder =
                (el.type === "text" || el.type === "field" || el.type === "barcode" || el.type === "qr") && value === "";
              const placeholder = el.field ? `‹${fieldLabel(design, el.field)}›` : el.type === "text" ? "‹boş metin›" : "‹veri yok›";
              const thin = geo.w * scale < 8 || geo.h * scale < 8;
              return (
                <div
                  key={el.id}
                  data-id={el.id}
                  className={[
                    "ld-el",
                    selected ? "is-selected" : "",
                    el.enabled ? "" : "is-disabled",
                    props.warnedIds.has(el.id) ? "is-warned" : "",
                    thin ? "is-thin" : "",
                  ].join(" ")}
                  style={{ left: geo.x * scale, top: geo.y * scale, width: Math.max(geo.w * scale, 2), height: Math.max(geo.h * scale, 2) }}
                  title={elementName(design, el)}
                  onPointerDown={(e) => onElementPointerDown(e, el)}
                  onDoubleClick={(e) => {
                    e.stopPropagation();
                    props.onEditElement(el.id);
                  }}
                >
                  {showPlaceholder ? <span className="ld-el-placeholder" style={{ fontSize: Math.max(9, Math.min(14, geo.h * scale * 0.6)) }}>{placeholder}</span> : null}
                  {!el.enabled ? <span className="ld-el-badge">Pasif</span> : null}
                </div>
              );
            })}
            {single && !props.readOnly && geometries.get(single.id)
              ? handlesFor(single).map((h) => {
                  const geo = geometries.get(single.id) as ElementGeometry;
                  const x = geo.x * scale + (h.includes("w") ? 0 : h.includes("e") ? geo.w * scale : (geo.w * scale) / 2);
                  const y = geo.y * scale + (h.includes("n") ? 0 : h.includes("s") ? geo.h * scale : (geo.h * scale) / 2);
                  return (
                    <div
                      key={h}
                      className={`ld-handle ld-handle-${h}`}
                      style={{ left: x, top: y }}
                      onPointerDown={(e) => onHandlePointerDown(e, single, h)}
                      aria-label="Boyutlandır"
                    />
                  );
                })
              : null}
          </div>
          {design.elements.length === 0 ? (
            <div className="ld-empty">
              <div className="ld-empty-card" onPointerDown={(e) => e.stopPropagation()}>
                <strong>Etiket boş</strong>
                <span>Soldan bir öğe sürükleyin ya da hazır bir şablonla başlayın.</span>
                {props.readOnly ? null : (
                  <button type="button" className="ld-btn ld-btn-primary ld-btn-sm" onClick={props.onOpenTemplates}>Hazır şablonla başla</button>
                )}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function drawRuler(canvas: HTMLCanvasElement | null, lengthMm: number, scale: number, dir: "h" | "v") {
  if (!canvas) return;
  const dpr = window.devicePixelRatio || 1;
  const len = lengthMm * scale;
  const cw = dir === "h" ? len : RULER;
  const ch = dir === "h" ? RULER : len;
  canvas.width = Math.max(1, Math.round(cw * dpr));
  canvas.height = Math.max(1, Math.round(ch * dpr));
  const g = canvas.getContext("2d");
  if (!g) return;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, cw, ch);
  g.strokeStyle = "#8a90a0";
  g.fillStyle = "#5b6070";
  g.lineWidth = 1;
  g.font = "10px system-ui, sans-serif";
  const minor = scale >= 4 ? 1 : scale >= 1.5 ? 5 : 10;
  const labelEvery = scale >= 6 ? 5 : 10;
  for (let mm = 0; mm <= lengthMm + 0.001; mm += minor) {
    const p = Math.round(mm * scale) + 0.5;
    const major = mm % 10 === 0;
    const mid = mm % 5 === 0;
    const tick = major ? 10 : mid ? 7 : 4;
    g.beginPath();
    if (dir === "h") {
      g.moveTo(p, RULER);
      g.lineTo(p, RULER - tick);
    } else {
      g.moveTo(RULER, p);
      g.lineTo(RULER - tick, p);
    }
    g.stroke();
    if (mm % labelEvery === 0 && mm > 0) {
      if (dir === "h") {
        g.textAlign = "center";
        g.fillText(String(mm), p, 10);
      } else {
        g.save();
        g.translate(9, p);
        g.rotate(-Math.PI / 2);
        g.textAlign = "center";
        g.fillText(String(mm), 0, 0);
        g.restore();
      }
    }
  }
}

/** Etiketi sahneye sığdıran yakınlaştırma. */
export function fitZoom(stageW: number, stageH: number, design: LabelDesign, showRulers: boolean): number {
  const pad = 2 * MARGIN + (showRulers ? RULER : 0) + 8;
  const zw = (stageW - pad) / (design.widthMm * CSS_PX_PER_MM);
  const zh = (stageH - pad) / (design.heightMm * CSS_PX_PER_MM);
  const z = Math.min(zw, zh);
  if (!Number.isFinite(z) || z <= 0) return 1;
  return Math.max(0.25, Math.min(12, z));
}
