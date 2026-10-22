// Göz ve LP Karşılaştırma — AL codeunit "DOPSWHS Bin LP Compare Mgt" JSON sözleşmesi.

export type CompareStatus = "equal" | "lpOver" | "lpNoStock" | "stockOver" | "stockNoLp" | "negativeStock";
export type CompareReason = "none" | "undoneReceipt" | "orphanAssignment" | "lotMismatch" | "otherBin";

export type LpLine = {
  lpNo: string;
  lpStatus: string;
  assignedDocType: string;
  assignedDocNo: string;
  pendingReceiptNo?: string;
  parentLpNo?: string;
  orphan: boolean;
  builtAt?: string;
  lineNo: number;
  qty: number;
  uom: string;
  qtyBase: number;
  uomMissing?: boolean;
  lot: string;
  serial?: string;
  expirationDate?: string;
  sourceEntryNo: number;
  sourceDocType: string;
  sourceDocNo: string;
  sourceDocLineNo?: number;
  sourceBin: string;
  sourceLpNo?: string;
};

export type CompareRow = {
  id: number;
  bin: string;
  zone: string;
  item: string;
  description: string;
  variant: string;
  lot: string;
  uom: string;
  stock: number;
  lp: number;
  diff: number;
  lpCount: number;
  status: CompareStatus;
  reason: CompareReason;
  reasonDetail: string;
  undoEntryNos: string;
  orphanLpNos: string;
  repairableLines: number;
  lines: LpLine[];
};

export type CompareSummary = {
  rows: number;
  equal: number;
  lpOver: number;
  lpNoStock: number;
  stockOver: number;
  stockNoLp: number;
  negativeStock: number;
  stockTotal: number;
  lpTotal: number;
  lpSurplusQty: number;
  stockSurplusQty: number;
  bins: number;
  lps: number;
  orphanLps: number;
  undoneReceiptRows: number;
  reasonRows: number;
};

export type Option = { code: string; name: string; binMandatory?: boolean };

export type CompareFilter = {
  location: string;
  zone: string;
  binFrom: string;
  binTo: string;
  item: string;
  onlyDiff: boolean;
};

export type CompareData = CompareFilter & {
  generatedAt: string;
  traceabilityAvailable: boolean;
  /** false: göz zorunlu olmayan lokasyon — karşılaştırma lokasyon düzeyinde, göz kodu boş. */
  binMandatory: boolean;
  needsLocation: boolean;
  locations: Option[];
  zones: Option[];
  summary: CompareSummary;
  rows: CompareRow[];
  truncated: boolean;
  maxRows?: number;
};

export type Notice = { kind: "success" | "info" | "error"; message: string };
