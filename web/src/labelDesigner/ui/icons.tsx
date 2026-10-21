// Küçük satır içi SVG simgeler (dış kaynak yok).
import type { ReactNode } from "react";
import type { ElementType } from "../model/types";

type P = { size?: number };

const svg = (size: number, children: ReactNode) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {children}
  </svg>
);

export const IconText = ({ size = 20 }: P) => svg(size, <><path d="M5 6V4h14v2" /><path d="M12 4v16" /><path d="M9 20h6" /></>);
export const IconField = ({ size = 20 }: P) => svg(size, <><path d="M8 4c-2 0-3 1-3 3v2c0 1.5-1 3-2 3 1 0 2 1.5 2 3v2c0 2 1 3 3 3" /><path d="M16 4c2 0 3 1 3 3v2c0 1.5 1 3 2 3-1 0-2 1.5-2 3v2c0 2-1 3-3 3" /><path d="M10 12h4" /></>);
export const IconBarcode = ({ size = 20 }: P) => svg(size, <><path d="M4 5v14M7 5v14M10 5v14M13 5v14M15 5v14M18 5v14M20 5v14" /></>);
export const IconQr = ({ size = 20 }: P) => svg(size, <><rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" /><rect x="3" y="14" width="7" height="7" /><path d="M14 14h3v3h-3zM20 14v.01M17 20h4M20 17v4" /></>);
export const IconLine = ({ size = 20 }: P) => svg(size, <path d="M4 12h16" />);
export const IconBox = ({ size = 20 }: P) => svg(size, <rect x="4" y="6" width="16" height="12" rx="1" />);
export const IconImage = ({ size = 20 }: P) => svg(size, <><rect x="3" y="5" width="18" height="14" rx="2" /><circle cx="9" cy="10" r="2" /><path d="M21 16l-5-5-8 8" /></>);
export const IconUndo = ({ size = 18 }: P) => svg(size, <><path d="M9 14L4 9l5-5" /><path d="M4 9h11a5 5 0 010 10h-3" /></>);
export const IconRedo = ({ size = 18 }: P) => svg(size, <><path d="M15 14l5-5-5-5" /><path d="M20 9H9a5 5 0 000 10h3" /></>);
export const IconSave = ({ size = 18 }: P) => svg(size, <><path d="M5 3h11l3 3v15H5z" /><path d="M8 3v5h8V3" /><rect x="8" y="13" width="8" height="6" /></>);
export const IconPrinter = ({ size = 18 }: P) => svg(size, <><path d="M7 9V3h10v6" /><rect x="3" y="9" width="18" height="8" rx="2" /><rect x="7" y="14" width="10" height="7" /></>);
export const IconEye = ({ size = 18 }: P) => svg(size, <><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></>);
export const IconEyeOff = ({ size = 18 }: P) => svg(size, <><path d="M3 3l18 18" /><path d="M10.6 5.1A10 10 0 0112 5c6 0 10 7 10 7a17 17 0 01-3.2 3.9M6.1 6.1C3.6 7.8 2 12 2 12s4 7 10 7a9.6 9.6 0 004.5-1.1" /></>);
export const IconRotate = ({ size = 18 }: P) => svg(size, <><path d="M20 11a8 8 0 10-2.3 5.7" /><path d="M20 4v7h-7" /></>);
export const IconCopy = ({ size = 18 }: P) => svg(size, <><rect x="8" y="8" width="13" height="13" rx="2" /><path d="M16 8V5a2 2 0 00-2-2H5a2 2 0 00-2 2v9a2 2 0 002 2h3" /></>);
export const IconTrash = ({ size = 18 }: P) => svg(size, <><path d="M4 7h16" /><path d="M10 11v6M14 11v6" /><path d="M6 7l1 13h10l1-13" /><path d="M9 7V4h6v3" /></>);
export const IconWarn = ({ size = 16 }: P) => svg(size, <><path d="M12 3l10 18H2z" /><path d="M12 10v5M12 18v.01" /></>);
export const IconCheck = ({ size = 16 }: P) => svg(size, <path d="M4 12l5 5L20 6" />);
export const IconClose = ({ size = 18 }: P) => svg(size, <path d="M6 6l12 12M18 6L6 18" />);
export const IconUpload = ({ size = 18 }: P) => svg(size, <><path d="M12 16V4" /><path d="M7 9l5-5 5 5" /><path d="M4 20h16" /></>);
export const IconBuilding = ({ size = 18 }: P) => svg(size, <><rect x="4" y="3" width="16" height="18" rx="1" /><path d="M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2M11 21v-3h2v3" /></>);
export const IconSearch = ({ size = 18 }: P) => svg(size, <><circle cx="11" cy="11" r="7" /><path d="M20 20l-4-4" /></>);

export function TypeIcon({ type, size = 20 }: { type: ElementType | string; size?: number }) {
  switch (type) {
    case "text": return <IconText size={size} />;
    case "field": return <IconField size={size} />;
    case "barcode": return <IconBarcode size={size} />;
    case "qr": return <IconQr size={size} />;
    case "line": return <IconLine size={size} />;
    case "box": return <IconBox size={size} />;
    case "image": return <IconImage size={size} />;
    default: return <IconWarn size={size} />;
  }
}
export const IconTemplates = ({ size = 18 }: P) => svg(size, <><rect x="3" y="3" width="8" height="8" rx="1" /><rect x="13" y="3" width="8" height="8" rx="1" /><rect x="3" y="13" width="8" height="8" rx="1" /><rect x="13" y="13" width="8" height="8" rx="1" /></>);
