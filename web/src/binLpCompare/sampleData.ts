// BC dışı önizleme ve ekran görüntüleri için örnek veri (gerçek müşteri verisi değildir).
import { buildFilterPayload, splitList, summarize } from "./model";
import type { CompareData, CompareFilter, CompareRow, LpLine } from "./types";

let lineSeq = 0;
function line(
  lpNo: string,
  qtyBase: number,
  opts: Partial<LpLine> = {},
): LpLine {
  lineSeq += 1;
  return {
    lpNo,
    lpStatus: "Oluşturuldu",
    assignedDocType: "",
    assignedDocNo: "",
    pendingReceiptNo: "",
    parentLpNo: "",
    orphan: false,
    builtAt: "2026-10-14T08:12:00Z",
    lineNo: 10000,
    qty: qtyBase,
    uom: "ADET",
    qtyBase,
    uomMissing: false,
    lot: "",
    serial: "",
    expirationDate: "",
    sourceEntryNo: 0,
    sourceDocType: "",
    sourceDocNo: "",
    sourceDocLineNo: 0,
    sourceBin: "",
    sourceLpNo: "",
    ...opts,
  };
}

function row(partial: Omit<CompareRow, "id" | "diff" | "lpCount" | "reasonDetail" | "undoEntryNos" | "orphanLpNos" | "repairableLines" | "zone" | "variant" | "uom"> & Partial<CompareRow>): CompareRow {
  const lpCount = new Set(partial.lines.map((l) => l.lpNo)).size;
  return {
    id: 0,
    zone: "PICK",
    variant: "",
    uom: "ADET",
    reasonDetail: "",
    undoEntryNos: "",
    orphanLpNos: "",
    repairableLines: 0,
    lpCount,
    ...partial,
    diff: Math.round((partial.lp - partial.stock) * 100000) / 100000,
  };
}

export function sampleRows(): CompareRow[] {
  lineSeq = 0;
  const rows: CompareRow[] = [
    row({
      bin: "K.K03.11", item: "ITM-104233", description: "Etiket rulosu 100x150 termal", lot: "A102511",
      stock: 45000, lp: 90000, status: "lpOver", reason: "undoneReceipt",
      reasonDetail: "Mal kabul geri alınmış (kayıt 115286) ama LP dolu kalmış; 1 LP satırı boşaltılabilir.",
      undoEntryNos: "115286", repairableLines: 1,
      lines: [
        line("LP0001882", 30000, { lot: "A102511", sourceEntryNo: 109400, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001187", sourceBin: "RCV-01", expirationDate: "2028-03-31" }),
        line("LP0001883", 15000, { lot: "A102511", sourceEntryNo: 109400, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001187", sourceBin: "RCV-01", expirationDate: "2028-03-31" }),
        line("LP0001907", 45000, { lot: "A102511", sourceEntryNo: 109433, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001191", sourceBin: "RCV-01", expirationDate: "2028-03-31" }),
      ],
    }),
    row({
      bin: "K.K03.12", item: "ITM-104233", description: "Etiket rulosu 100x150 termal", lot: "A102498",
      stock: 12000, lp: 12000, status: "equal", reason: "none",
      lines: [
        line("LP0001850", 6000, { lot: "A102498", sourceEntryNo: 109311, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001176" }),
        line("LP0001851", 6000, { lot: "A102498", sourceEntryNo: 109311, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001176" }),
      ],
    }),
    row({
      bin: "K.K02.08", item: "ITM-104240", description: "Koli 40x30x30 çift oluklu", lot: "",
      stock: 1200, lp: 1500, status: "lpOver", reason: "none",
      lines: [line("LP0001720", 1500, { qty: 25, uom: "KOLI", sourceEntryNo: 108822, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001102" })],
    }),
    row({
      bin: "K.K04.02", item: "ITM-200118", description: "Streç film 23 mic 50 cm", lot: "",
      stock: 640, lp: 400, status: "stockOver", reason: "none",
      lines: [line("LP0001790", 400, { sourceBin: "BULK-03" })],
    }),
    row({
      bin: "K.K05.01", item: "ITM-310077", description: "Yapışkan bant 48 mm şeffaf", lot: "L-2409",
      stock: 0, lp: 360, status: "lpNoStock", reason: "otherBin",
      reasonDetail: "Bu madde/lot stoğu başka gözde: K.K05.07. LP fiziksel olarak taşınmış ama sistemde taşınmamış olabilir.",
      lines: [line("LP0001811", 360, { lot: "L-2409", sourceEntryNo: 108990, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001131" })],
    }),
    row({
      bin: "K.K05.07", item: "ITM-310077", description: "Yapışkan bant 48 mm şeffaf", lot: "L-2409",
      stock: 360, lp: 0, status: "stockNoLp", reason: "otherBin",
      reasonDetail: "Bu madde/lotun LP'si başka gözde kayıtlı: K.K05.01.",
      lines: [],
    }),
    row({
      bin: "K.K06.03", item: "ITM-410002", description: "Palet streç kapak 120x100", lot: "LT-0912",
      stock: 0, lp: 200, status: "lpNoStock", reason: "lotMismatch",
      reasonDetail: "Bu gözde LP'siz stok farklı lotta: LT-0913. LP lotu yanlış girilmiş olabilir.",
      lines: [line("LP0001840", 200, { lot: "LT-0912", sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001160" })],
    }),
    row({
      bin: "K.K06.03", item: "ITM-410002", description: "Palet streç kapak 120x100", lot: "LT-0913",
      stock: 200, lp: 0, status: "stockNoLp", reason: "lotMismatch",
      reasonDetail: "Bu gözdeki LP'lerde farklı lot var: LT-0912.",
      lines: [],
    }),
    row({
      bin: "RCV-01", zone: "RECEIVE", item: "ITM-500031", description: "Köşebent karton 35 mm", lot: "B771",
      stock: 48, lp: 48, status: "equal", reason: "orphanAssignment",
      reasonDetail: "LP atandığı belge artık yok (LP0001902); LP başka işlemlerde kullanılamaz.",
      orphanLpNos: "LP0001902",
      lines: [line("LP0001902", 48, { lot: "B771", lpStatus: "Atandı", assignedDocType: "Depo Yerleştirme", assignedDocNo: "PA000412", orphan: true, sourceEntryNo: 109501, sourceDocType: "Depo Mal Kabulü", sourceDocNo: "RE001195" })],
    }),
    row({
      bin: "K.K07.01", item: "ITM-620015", description: "Zımba teli 22 mm", lot: "",
      stock: -5, lp: 0, status: "negativeStock", reason: "none",
      lines: [],
    }),
    row({
      bin: "K.K07.04", item: "ITM-620015", description: "Zımba teli 22 mm", lot: "",
      stock: 900, lp: 900, status: "equal", reason: "none",
      lines: [line("LP0001760", 900, { lpStatus: "Atandı", assignedDocType: "Depo Toplama", assignedDocNo: "PI004211" })],
    }),
    row({
      bin: "B.B01.02", zone: "BULK", item: "ITM-200118", description: "Streç film 23 mic 50 cm", lot: "",
      stock: 2400, lp: 2400, status: "equal", reason: "none",
      lines: [line("LP0001700", 1200), line("LP0001701", 1200)],
    }),
  ];
  return rows.map((r, i) => ({ ...r, id: i + 1 }));
}

const LOCATIONS = [
  { code: "MERKEZ", name: "Merkez Depo" },
  { code: "ANTREPO", name: "Antrepo" },
];
const ZONES = [
  { code: "PICK", name: "Toplama" },
  { code: "BULK", name: "Yığın" },
  { code: "RECEIVE", name: "Mal kabul" },
];

let localRows: CompareRow[] | null = null;
function rowsStore(): CompareRow[] {
  if (!localRows) localRows = sampleRows();
  return localRows;
}

function matchesItem(item: string, filter: string): boolean {
  if (!filter) return true;
  return filter.split("|").some((f) => {
    const pattern = f.trim();
    if (!pattern) return false;
    if (pattern.includes("*")) {
      const re = new RegExp(`^${pattern.split("*").map((p) => p.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`);
      return re.test(item);
    }
    return item === pattern;
  });
}

function inBinRange(bin: string, from: string, to: string): boolean {
  if (from && to) return bin >= from && bin <= to;
  if (from) return from.includes("*") ? matchesItem(bin, from) : bin === from;
  if (to) return bin <= to;
  return true;
}

/** BC'nin yapacağı süzmeyi örnek veride taklit eder. */
export function localCompare(filterIn: Partial<CompareFilter>): CompareData {
  const filter = buildFilterPayload({
    location: filterIn.location ?? "MERKEZ",
    zone: filterIn.zone ?? "",
    binFrom: filterIn.binFrom ?? "",
    binTo: filterIn.binTo ?? "",
    item: filterIn.item ?? "",
    onlyDiff: filterIn.onlyDiff ?? true,
  });
  const scoped = filter.location
    ? rowsStore().filter(
        (r) =>
          (!filter.zone || r.zone === filter.zone) &&
          inBinRange(r.bin, filter.binFrom, filter.binTo) &&
          matchesItem(r.item, filter.item),
      )
    : [];
  const visible = filter.onlyDiff ? scoped.filter((r) => r.status !== "equal" || r.reason !== "none") : scoped;
  return {
    ...filter,
    generatedAt: new Date("2026-10-22T09:30:00").toISOString(),
    traceabilityAvailable: true,
    binMandatory: true,
    needsLocation: !filter.location,
    locations: LOCATIONS,
    zones: ZONES,
    summary: summarize(scoped),
    rows: visible,
    truncated: false,
    maxRows: 3000,
  };
}

/** Yerel önizlemede düzeltme düğmelerinin etkisi. */
export function localRepairUndone(undoCsv: string): number {
  let emptied = 0;
  const undo = new Set(splitList(undoCsv));
  localRows = rowsStore().map((r) => {
    if (r.reason !== "undoneReceipt" || !splitList(r.undoEntryNos).some((u) => undo.has(u))) return r;
    const remaining = r.lines.filter((l) => l.sourceEntryNo !== 109433);
    emptied += r.lines.length - remaining.length;
    const lp = remaining.reduce((s, l) => s + l.qtyBase, 0);
    return { ...r, lines: remaining, lp, diff: lp - r.stock, lpCount: new Set(remaining.map((l) => l.lpNo)).size,
      status: Math.abs(lp - r.stock) < 0.00001 ? "equal" : r.status, reason: "none", reasonDetail: "", undoEntryNos: "", repairableLines: 0 };
  });
  return emptied;
}

export function localReleaseOrphans(lpCsv: string): number {
  const lps = new Set(splitList(lpCsv));
  let released = 0;
  localRows = rowsStore().map((r) => {
    if (!splitList(r.orphanLpNos).some((lp) => lps.has(lp))) return r;
    released += 1;
    return {
      ...r, reason: "none", reasonDetail: "", orphanLpNos: "",
      lines: r.lines.map((l) => (lps.has(l.lpNo) ? { ...l, orphan: false, lpStatus: "Oluşturuldu", assignedDocType: "", assignedDocNo: "" } : l)),
    };
  });
  return released;
}
