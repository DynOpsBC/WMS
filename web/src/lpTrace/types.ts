// LP İzlenebilirlik JSON sözleşmesi — AL codeunit 72391 "DOPSWHS LP Trace Data".
// Alan adları AL tarafındaki JsonObject.Add anahtarlarıyla birebir aynıdır.

export type Nav = { kind: string; key: string } | null;

export type InsightLevel = "error" | "warning" | "info";

export interface Insight {
  level: InsightLevel;
  code: string;
  text: string;
  nav: Nav;
}

export type DocState = "open" | "posted" | "missing" | "none";

export interface TraceDocument {
  key: string;
  kind: string;
  kindCaption: string;
  no: string;
  state: DocState;
  exists: boolean;
  stage: number;
  role: string;
  note: string;
  nav: Nav;
}

export interface LpRef {
  no: string;
  status: string;
  binCode: string;
  totalQty?: number;
}

export interface AssignedDoc {
  type: string;
  typeCaption: string;
  no: string;
  state: DocState;
  exists: boolean;
  nav: Nav;
}

export interface LpHeader {
  no: string;
  status: string;
  statusCaption: string;
  locationCode: string;
  binCode: string;
  templateCode: string;
  sscc: string;
  totalQty: number;
  lineCount: number;
  plannedQty: number;
  weightKg: number;
  builtBy: string;
  builtAt: string;
  lastModifiedAt: string;
  pendingReceiptNo: string;
  notes: string;
  assigned: AssignedDoc | null;
  orphan: boolean;
  parent: LpRef | null;
  children: LpRef[];
}

export interface LpLine {
  lineNo: number;
  itemNo: string;
  itemDescription: string;
  variantCode: string;
  lotNo: string;
  serialNo: string;
  packageNo: string;
  qty: number;
  baseQty: number;
  uom: string;
  expirationDate: string;
  sourceBin: string;
  sourceDocType: string;
  sourceDocTypeCaption: string;
  sourceDocNo: string;
  sourceDocLineNo: number;
  sourceDocQty: number;
  sourceIleNo: number;
  sourceLpNo: string;
  childLpNo: string;
  groupKey: string;
  sourceDocState: DocState;
  nav: Nav;
}

export interface SourceGroup {
  key: string;
  kind: "doc" | "lp" | "ile" | "child" | "none" | string;
  label: string;
  sourceLpNo: string;
  sourceLpStatus: string;
  sourceDocType: string;
  sourceDocNo: string;
  sourceIleNo: number;
  qty: number;
  lineCount: number;
}

export interface TimelineLink {
  kind: string;
  key: string;
  label: string;
}

export interface TimelineEntry {
  entryNo: number;
  action: string;
  actionCaption: string;
  at: string;
  user: string;
  device: string;
  fromBin: string;
  toBin: string;
  qty: number;
  itemNo: string;
  lotSerial: string;
  relatedDocument: string;
  sourceLpNo: string;
  targetLpNo: string;
  undo: boolean;
  link: TimelineLink | null;
  /** Çözülemeyen (silinmiş) belge no — ör. PU001130. */
  missingDocNo?: string;
}

export interface LedgerEntry {
  entryNo: number;
  postingDate: string;
  entryType: string;
  documentType: string;
  documentNo: string;
  documentLineNo: number;
  orderNo: string;
  itemNo: string;
  variantCode: string;
  lotNo: string;
  serialNo: string;
  locationCode: string;
  qty: number;
  remainingQty: number;
  open: boolean;
  positive: boolean;
  correction: boolean;
  appliesToEntry: number;
  lpNo: string;
  lpNos: string;
  matchedBy: "sourceLine" | "lpNo" | "lpNos" | "undo" | "undone" | string;
  undoneByEntryNo: number;
  thisLpQty: number;
  linkedLpQty: number;
}

export interface WarehouseEntry {
  entryNo: number;
  registeringDate: string;
  entryType: string;
  locationCode: string;
  zoneCode: string;
  binCode: string;
  itemNo: string;
  lotNo: string;
  qty: number;
  qtyBase: number;
  uom: string;
  sourceDocument: string;
  sourceNo: string;
  whseDocumentType: string;
  whseDocumentNo: string;
  referenceDocument: string;
  referenceNo: string;
  userId: string;
}

export interface TreeLine {
  lineNo: number;
  qty: number;
  baseQty: number;
  uom: string;
  sourceDocType: string;
  sourceDocNo: string;
  sourceIleNo: number;
  sourceLpNo: string;
  groupKey: string;
  sourceLabel: string;
  /** Kaynak giriş geri alındıysa geri alma girişi no, yoksa 0. */
  sourceUndoneBy?: number;
}

export interface TreeLp {
  no: string;
  status: string;
  statusCaption: string;
  locationCode: string;
  binCode: string;
  assignedDocType: string;
  assignedDocNo: string;
  orphan: boolean;
  qty: number;
  lineCount: number;
  mixedSources: boolean;
  /** LP'nin en az bir satırı geri alınmış bir mal kabul girişine bağlı. */
  onUndoneEntry?: boolean;
  /** Tek kaynak girişli LP'lerde o giriş, aksi hâlde 0. */
  sourceIleNo?: number;
  lines: TreeLine[];
}

export interface GroupEntry {
  entryNo: number;
  postingDate: string;
  entryType: string;
  documentType: string;
  documentNo: string;
  locationCode: string;
  qty: number;
  remainingQty: number;
  open: boolean;
  positive: boolean;
  correction: boolean;
  undoneByEntryNo: number;
  lpQty: number;
  diff: number;
}

export type GroupState = "ok" | "excess" | "partial";

export interface TreeGroup {
  key: string;
  itemNo: string;
  itemDescription: string;
  lotNo: string;
  lpCount: number;
  lpQty: number;
  bcRemainingQty: number;
  unlinkedLpQty: number;
  diff: number;
  state: GroupState;
  lps: TreeLp[];
  entries: GroupEntry[];
}

export interface HistoricLp {
  no: string;
  status: string;
  statusCaption: string;
  locationCode: string;
  binCode: string;
  assignedDocNo: string;
  orphan: boolean;
  lastAction: string;
  lastAt: string;
  lastRelatedDocument: string;
  emptiedByUndo: boolean;
}

export interface TreeTotals {
  groupCount: number;
  lpCount: number;
  lpQty: number;
  bcRemainingQty: number;
  historicLpCount: number;
  orphanLpCount: number;
}

export type TraceMode = "empty" | "lp" | "lot" | "item" | "document" | "notFound" | "error";

export interface TracePayload {
  version: number;
  mode: TraceMode;
  query: string;
  generatedAt: string;
  message?: string;
  title?: string;
  // LP modu
  lp?: LpHeader;
  lines: LpLine[];
  sourceGroups: SourceGroup[];
  mixedSources: boolean;
  timeline: TimelineEntry[];
  itemLedger: LedgerEntry[];
  warehouseEntries: WarehouseEntry[];
  // Ağaç modları
  groups: TreeGroup[];
  historicLps: HistoricLp[];
  totals?: TreeTotals;
  // Ortak
  documents: TraceDocument[];
  insights: Insight[];
  truncated: Record<string, boolean>;
}
