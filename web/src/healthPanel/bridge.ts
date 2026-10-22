// BC kontrol eklentisi köprüsü (yalnız Depo Sağlık Paneli). AL procedure'leri
// (SetData, NotifyResult, SetBusy) global fonksiyon olarak çağırır; olaylar
// Microsoft.Dynamics.NAV.InvokeExtensibilityMethod ile AL'e gider.

export type HealthMessage =
  | { type: "setData"; payload: unknown }
  | { type: "notifyResult"; payload: unknown }
  | { type: "setBusy"; busy: boolean };

type Listener = (m: HealthMessage) => void;
type NavWindow = Window & {
  Microsoft?: { Dynamics?: { NAV?: { InvokeExtensibilityMethod?: (name: string, args: unknown[], skipIfBusy?: boolean) => void } } };
};

const listeners = new Set<Listener>();
// SetData, React bağlanmadan önce gelebilir: son mesajlar saklanır.
let lastData: HealthMessage | null = null;

export function listen(listener: Listener): () => void {
  listeners.add(listener);
  if (lastData) listener(lastData);
  return () => {
    listeners.delete(listener);
  };
}

function emit(m: HealthMessage) {
  if (m.type === "setData") lastData = m;
  listeners.forEach((l) => l(m));
}

export function hasBc(): boolean {
  return typeof (window as NavWindow).Microsoft?.Dynamics?.NAV?.InvokeExtensibilityMethod === "function";
}

function invoke(name: string, args: unknown[]) {
  const nav = (window as NavWindow).Microsoft?.Dynamics?.NAV;
  if (nav?.InvokeExtensibilityMethod) nav.InvokeExtensibilityMethod(name, args);
  else window.parent?.postMessage({ type: "healthPanel", name, args }, "*");
}

export const bc = {
  ready: () => invoke("ControlReady", []),
  refresh: (locationFilter: string) => invoke("RequestRefresh", [locationFilter]),
  fixIssue: (id: number) => invoke("FixIssue", [id]),
  fixCategory: (key: string) => invoke("FixCategory", [key]),
  showIssue: (id: number, target: "main" | "compare" | "trace" = "main") => invoke("ShowIssue", [id, target]),
};

export function installGlobals() {
  Object.assign(window, {
    SetData: (payload: unknown) => emit({ type: "setData", payload }),
    NotifyResult: (payload: unknown) => emit({ type: "notifyResult", payload }),
    SetBusy: (busy: unknown) => emit({ type: "setBusy", busy: busy === true || busy === "true" }),
  });
}
