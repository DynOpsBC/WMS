// Terminal Ekran Tasarımcısı — BC "DOPSWHS Terminal Layout Mgt" JSON sözleşmesi.

export type ScanFlag = "LP" | "LOT" | "BIN";
export type AppliesTo = "all" | "role" | "terminal";

export interface CatalogItem {
  screen: string;
  key: string;
  kind: "tile" | "button";
  group: string;
  label: string;
  description: string;
  sort: number;
  flags: ScanFlag[];
  availability: string;
  locked: boolean;
}

export interface ScreenDef {
  key: string;
  title: string;
  tileKey: string;
}

export interface LayoutHeader {
  code: string;
  description: string;
  appliesTo: AppliesTo;
  appliesToCode: string;
  active: boolean;
  version?: number;
  modifiedAt?: string;
  modifiedBy?: string;
}

export interface LayoutLine {
  screen: string;
  key: string;
  visible: boolean;
  sort: number;
  label: string;
  note: string;
  requireLp: boolean;
  requireLot: boolean;
  requireBin: boolean;
}

export interface Layout extends LayoutHeader {
  lines: LayoutLine[];
}

export interface DesignerData {
  catalogVersion: string;
  catalog: CatalogItem[];
  screens: ScreenDef[];
  layouts: LayoutHeader[];
  roles: { code: string; description: string }[];
  terminals: { code: string }[];
  layout: Layout;
}

export interface PreviewData {
  roleCode: string;
  terminalCode: string;
  layoutCode: string;
  layoutDescription: string;
  layout: Layout;
}

export interface NotifyResult {
  ok: boolean;
  message: string;
}
