// Basit çizgi ikonlar (bağımlılıksız). Terminaldeki WmsGlyph karşılıkları.
import type { CSSProperties } from "react";

const P: Record<string, string> = {
  RECEIVING: "M12 3v11M7.5 9.5 12 14l4.5-4.5M4 16v4h16v-4",
  PUTAWAY: "M4 5h16M4 12h7M4 19h16M17 15V8M14 11l3-3 3 3",
  PICKING: "M3 4h2.2l2.2 10.5h10.4L20 7H6.4M9 19.5h.01M17 19.5h.01",
  PACKING: "M3.5 7.5 12 3.5l8.5 4v9l-8.5 4-8.5-4zM3.5 7.5l8.5 4 8.5-4M12 11.5v9",
  SHIPPING: "M2.5 6.5h11v9h-11zM13.5 9.5h4l3 3.2v2.8h-7M6.5 18.5a1.6 1.6 0 1 0 0-.01M17 18.5a1.6 1.6 0 1 0 0-.01",
  LICENSE_PLATES: "M3 4.5h18v10H3zM3 19h18M7 14.5V19M17 14.5V19M7 9.5h5",
  HIERARCHICAL_LP: "M8 3.5h8v6H8zM3 14.5h8v6H3zM13 14.5h8v6h-8zM12 9.5v2.5M7 14.5V12h10v2.5",
  ADHOC_MOVE: "M4 12h16M16 8l4 4-4 4M8 8l-4 4 4 4",
  DIRECTED_MOVE: "M5 19 19 5M10 5h9v9",
  COUNT: "M9 3.5h6v3H9zM7 5H5v16h14V5h-2M8.5 13l2.3 2.3L15.5 11",
  COUNT_V2: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2M14 18h6M18 14v2",
  FIRST_COUNT: "M4 5h16v14H4zM8 9h8M8 13h5M15.5 15.5l1.5 1.5 3-3",
  PRODUCTION: "M3 20.5V10l5.5 3.5V10l5.5 3.5V5.5h6.5v15z",
  SUBCONTRACTING: "M4 8h13l-3.5-3.5M20 16H7l3.5 3.5",
  ASSEMBLY: "M4 4h7v7H4zM13 13h7v7h-7zM13 4h7v7h-7zM4 13h7v7H4z",
  QUALITY: "M12 3 20 6v5.5c0 4.8-3.4 8.2-8 9.5-4.6-1.3-8-4.7-8-9.5V6zM8.8 12l2.2 2.2 4.4-4.4",
  QUALITY_MGMT: "M5 20V10M12 20V4M19 20v-7M3 20h18",
  ITEM_INQUIRY: "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM20 20l-4.8-4.8",
  BIN_INQUIRY: "M3 5h18M3 12h18M3 19h18M6 5v14M18 5v14",
  LABELS: "M3.5 12.5V4h8.5l9 9-8.5 8.5zM8 8.5h.01",
  WHSE_ENTRIES: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01",
  FIELD_SETTINGS: "M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1M15 4v4M9 10v4M17 16v4",
  SELF_TEST: "M3 12h4l3-7.5 4 15 3-7.5h4",
  PRINTERS: "M6.5 9V3.5h11V9M6.5 17.5H4v-7.5h16v7.5h-2.5M6.5 14h11v7h-11z",
  TEST_CENTER: "M9 3.5h6M10 3.5V9l-5 8.7A2 2 0 0 0 6.7 20.5h10.6a2 2 0 0 0 1.7-2.8L14 9V3.5",
  POSTING_TEST: "M5 4h10l4 4v12H5zM15 4v4h4M8.5 14l2.2 2.2 4.4-4.4",
  CONNECTION: "M4.5 10.5a10.5 10.5 0 0 1 15 0M7.8 13.8a5.8 5.8 0 0 1 8.4 0M12 18h.01",
  BUTTON: "M4 8h16v8H4z",
  EYE: "M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
  EYE_OFF: "M3 3l18 18M10.6 5.6A9.6 9.6 0 0 1 12 5.5c6.4 0 10 6.5 10 6.5a17 17 0 0 1-3 3.8M6.5 6.9C3.8 8.6 2 12 2 12s3.6 6.5 10 6.5a9.5 9.5 0 0 0 4.6-1.2M9.9 9.9a3 3 0 0 0 4.2 4.2",
  GRIP: "M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01",
  UNDO: "M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11",
  REDO: "M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13",
  SAVE: "M5 4h11l3 3v13H5zM8 4v5h7V4M8 20v-6h8v6",
  PLUS: "M12 5v14M5 12h14",
  TRASH: "M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3",
  PHONE: "M7 2.5h10a1.5 1.5 0 0 1 1.5 1.5v16a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 20V4A1.5 1.5 0 0 1 7 2.5zM11 18.5h2",
  LOCK: "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3",
  UP: "M12 19V5M6 11l6-6 6 6",
  DOWN: "M12 5v14M6 13l6 6 6-6",
  RESET: "M4 12a8 8 0 1 0 2.4-5.7M4 4v4.5h4.5",
  INFO: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 11v5M12 7.5h.01",
  CHECK: "M5 12.5l4.5 4.5L19 7.5",
  SCAN: "M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M7 12h10",
};

export function Icon({ name, size = 18, stroke = 1.9, style, className }: { name: string; size?: number; stroke?: number; style?: CSSProperties; className?: string }) {
  const d = P[name] ?? P.BUTTON;
  return (
    <svg className={className} style={style} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={name === "GRIP" ? 3 : stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

export function glyphFor(key: string): string {
  return P[key] ? key : "BUTTON";
}

/** Android HomeCategories vurgu renkleri. */
export const groupAccent: Record<string, string> = {
  "Gelen": "#26A65B",
  "Giden": "#6C5CE7",
  "İç Operasyon": "#2D9CDB",
  "Üretim": "#E2873B",
  "Kalite": "#14B8A6",
  "Sorgu": "#9B59B6",
  "Destek ve Ayarlar": "#64748B",
};

export function accentOf(group: string): string {
  return groupAccent[group] ?? "#6C5CE7";
}
