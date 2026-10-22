import type { IconName } from "./model";

// 16px çizgi ikonlar (harici kütüphane yok; BC eklentisi tek dosya kalsın).
const PATHS: Record<IconName, string> = {
  box: "M3 5.5 8 3l5 2.5v5L8 13l-5-2.5z M3 5.5 8 8l5-2.5 M8 8v5",
  plus: "M8 3.5v9 M3.5 8h9",
  minus: "M3.5 8h9",
  link: "M6.5 9.5l3-3 M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1 M9 11.5l-1 1A2.5 2.5 0 0 1 4.5 9l1-1",
  unlink: "M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1 M9 11.5l-1 1A2.5 2.5 0 0 1 4.5 9l1-1 M3 3l10 10",
  arrow: "M3 8h10 M9.5 4.5 13 8l-3.5 3.5",
  in: "M12 4 5 11 M5 6v5h5",
  out: "M4 12l7-7 M6 5h5v5",
  layers: "M8 3 13 5.5 8 8 3 5.5z M3 8.5 8 11l5-2.5 M3 11l5 2.5 5-2.5",
  split: "M8 13V8 M8 8 4 4 M8 8l4-4 M4 7V4h3 M12 7V4H9",
  broken: "M3 5.5 8 3l5 2.5v5L8 13l-5-2.5z M6 6.5l4 3 M10 6.5l-4 3",
  check: "M3.5 8.5l3 3 6-7",
  doc: "M4.5 2.5h5l2.5 2.5v8.5h-7.5z M9.5 2.5V5H12 M6.5 8h3.5 M6.5 10.5h3.5",
  undo: "M5 6.5H10a3 3 0 0 1 0 6H7 M7.5 4 5 6.5 7.5 9",
  dot: "M8 6.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z",
};

export function Icon({ name, size = 16 }: { name: IconName; size?: number }) {
  return (
    <svg className="lt-icon" width={size} height={size} viewBox="0 0 16 16" aria-hidden="true">
      <path d={PATHS[name]} fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
