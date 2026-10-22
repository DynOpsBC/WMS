// BC kontrol eklentisi köprüsü: AL → JS (SetData / SetBusy) ve JS → AL olayları
// (ControlReady / Search / OpenNode) Microsoft.Dynamics.NAV.InvokeExtensibilityMethod ile.
import { useSyncExternalStore } from "react";

type NavApi = {
  InvokeExtensibilityMethod?: (name: string, args: unknown[], skipIfBusy?: boolean, callback?: () => void) => void;
};
type HostWindow = Window & { Microsoft?: { Dynamics?: { NAV?: NavApi } } };

export interface HostState {
  payload: unknown;
  busy: boolean;
  revision: number;
}

let state: HostState = { payload: null, busy: false, revision: 0 };
const listeners = new Set<() => void>();

function emit(next: Partial<HostState>) {
  state = { ...state, ...next, revision: state.revision + 1 };
  listeners.forEach((listener) => listener());
}

/** AL'nin çağırdığı yordamları global olarak tanımlar (eklenti betiği yüklenir yüklenmez). */
export function installHostApi() {
  Object.assign(window, {
    SetData: (json: unknown) => emit({ payload: json, busy: false }),
    SetBusy: (busy: unknown) => emit({ busy: Boolean(busy) }),
  });
}

export function useHostState(): HostState {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    () => state,
    () => state,
  );
}

export function isInBc(): boolean {
  return Boolean((window as HostWindow).Microsoft?.Dynamics?.NAV?.InvokeExtensibilityMethod);
}

/** AL olayını tetikler; BC dışında (geliştirme/Playwright) bir DOM olayı yayınlar. */
export function invokeBc(name: "ControlReady" | "Search" | "OpenNode", args: unknown[]) {
  const nav = (window as HostWindow).Microsoft?.Dynamics?.NAV;
  if (nav?.InvokeExtensibilityMethod) {
    nav.InvokeExtensibilityMethod(name, args, false);
    return;
  }
  window.dispatchEvent(new CustomEvent("lptrace:invoke", { detail: { name, args } }));
}

export function requestSearch(text: string) {
  emit({ busy: true });
  invokeBc("Search", [text]);
}

export function openNode(kind: string, key: string) {
  if (!kind || !key) return;
  invokeBc("OpenNode", [kind, key]);
}
