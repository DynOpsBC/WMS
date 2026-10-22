// BC control add-in köprüsü: "DOPSWHS Bin LP Compare".
// BC → JS: SetData(json), SetLocale(code), NotifyResult(json) (global işlevler).
// JS → BC: Microsoft.Dynamics.NAV.InvokeExtensibilityMethod(event, args).
// BC dışında (geliştirme önizlemesi) örnek veriyle yerel çalışır.
import type { CompareFilter, Notice } from "./types";

type NavHost = {
  InvokeExtensibilityMethod?: (name: string, args: unknown[], skipIfBusy?: boolean, callback?: () => void) => void;
};

type BridgeEvent =
  | { type: "data"; payload: unknown }
  | { type: "notice"; payload: Notice }
  | { type: "locale"; payload: string };

type Listener = (event: BridgeEvent) => void;

// BC aynı paketi iki kez çalıştırabilir (Scripts + StartupScript). Dinleyiciler ve
// son veri pencere düzeyinde tek bir nesnede tutulur; böylece hangi kopyanın
// SetData'sı çağrılırsa çağrılsın bağlı ekran veriyi alır.
type SharedState = { listeners: Set<Listener>; lastData: unknown };
const sharedKey = "__dopsBinLpCompareBridge";
const sharedHost = window as unknown as Record<string, SharedState | undefined>;
const shared: SharedState = sharedHost[sharedKey] ?? (sharedHost[sharedKey] = { listeners: new Set<Listener>(), lastData: null });
const listeners = shared.listeners;

function nav(): NavHost | undefined {
  const w = window as Window & { Microsoft?: { Dynamics?: { NAV?: NavHost } } };
  return w.Microsoft?.Dynamics?.NAV;
}

/** BC içinde mi (InvokeExtensibilityMethod var mı)? */
export function isInBc(): boolean {
  return typeof nav()?.InvokeExtensibilityMethod === "function";
}

function emit(event: BridgeEvent) {
  if (event.type === "data") shared.lastData = event.payload;
  listeners.forEach((l) => l(event));
}

export function subscribe(listener: Listener): () => void {
  listeners.add(listener);
  if (shared.lastData != null) listener({ type: "data", payload: shared.lastData });
  return () => listeners.delete(listener);
}

function parseNotice(raw: unknown): Notice {
  let value: unknown = raw;
  if (typeof raw === "string") {
    try {
      value = JSON.parse(raw);
    } catch {
      value = { kind: "info", message: raw };
    }
  }
  const v = (value ?? {}) as Partial<Notice>;
  const kind = v.kind === "success" || v.kind === "error" ? v.kind : "info";
  return { kind, message: String(v.message ?? "") };
}

// BC'nin çağırdığı global yordamlar.
Object.assign(window, {
  SetData: (json: unknown) => emit({ type: "data", payload: json }),
  SetLocale: (code: unknown) => emit({ type: "locale", payload: String(code ?? "") }),
  NotifyResult: (json: unknown) => emit({ type: "notice", payload: parseNotice(json) }),
});

// Yerel önizleme / Playwright: BC yokken çağrılar buraya düşer.
type LocalHandler = (name: string, args: unknown[]) => void;
let localHandler: LocalHandler | null = null;
export function setLocalHandler(handler: LocalHandler | null) {
  localHandler = handler;
}

function invoke(name: string, args: unknown[]) {
  const host = nav();
  if (host?.InvokeExtensibilityMethod) {
    host.InvokeExtensibilityMethod(name, args, false);
    return;
  }
  localHandler?.(name, args);
}

export const bc = {
  ready: () => invoke("ControlReady", []),
  compare: (filter: CompareFilter) => invoke("Compare", [JSON.stringify(filter)]),
  repairUndoneReceipt: (undoEntryNosCsv: string, filter: CompareFilter) =>
    invoke("RepairUndoneReceipt", [undoEntryNosCsv, JSON.stringify(filter)]),
  releaseOrphans: (lpNosCsv: string, filter: CompareFilter) =>
    invoke("ReleaseOrphans", [lpNosCsv, JSON.stringify(filter)]),
  openLp: (lpNo: string) => invoke("OpenLp", [lpNo]),
  openBinContent: (location: string, bin: string, item: string, variant: string) =>
    invoke("OpenBinContent", [location, bin, item, variant]),
  openTraceability: (lpNo: string, item: string, lot: string) => invoke("OpenTraceability", [lpNo, item, lot]),
  exportExcel: (filter: CompareFilter) => invoke("ExportExcel", [JSON.stringify(filter)]),
};

/** Test/önizleme kolaylığı: BC'den veri gelmiş gibi davran. */
export function pushLocalData(json: unknown) {
  emit({ type: "data", payload: json });
}

export function pushLocalNotice(notice: Notice) {
  emit({ type: "notice", payload: notice });
}
