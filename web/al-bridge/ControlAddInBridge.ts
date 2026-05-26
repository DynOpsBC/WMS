export type PickBoardMessage =
  | { type: "setData"; payload: unknown }
  | { type: "setLocale"; locale: string }
  | { type: "applyFilter"; filter: unknown };

type Listener = (message: PickBoardMessage) => void;

const listeners = new Set<Listener>();

export function listenBridge(listener: Listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function reassign(pickNo: string, userId: string) {
  const microsoft = (window as Window & { Microsoft?: { Dynamics?: { NAV?: { InvokeExtensibilityMethod?: (...args: unknown[]) => void } } } }).Microsoft;
  microsoft?.Dynamics?.NAV?.InvokeExtensibilityMethod?.("Reassign", [pickNo, userId]);
  window.parent?.postMessage({ type: "reassign", pickNo, userId }, "*");
}

export function requestRefresh() {
  const microsoft = (window as Window & { Microsoft?: { Dynamics?: { NAV?: { InvokeExtensibilityMethod?: (...args: unknown[]) => void } } } }).Microsoft;
  microsoft?.Dynamics?.NAV?.InvokeExtensibilityMethod?.("RequestRefresh", []);
  window.parent?.postMessage({ type: "requestRefresh" }, "*");
}

window.addEventListener("message", (event) => {
  const data = event.data as PickBoardMessage;
  if (!data || typeof data !== "object" || !("type" in data)) return;
  if (data.type === "setData" || data.type === "setLocale" || data.type === "applyFilter") {
    listeners.forEach((listener) => listener(data));
  }
});

Object.assign(window, {
  SetData: (payload: unknown) => listeners.forEach((listener) => listener({ type: "setData", payload })),
  SetLocale: (locale: string) => listeners.forEach((listener) => listener({ type: "setLocale", locale })),
  ApplyFilter: (filter: unknown) => listeners.forEach((listener) => listener({ type: "applyFilter", filter })),
});
