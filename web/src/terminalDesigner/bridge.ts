// BC denetim eklentisi köprüsü. BC, AL'deki procedure'leri iframe penceresinde
// global fonksiyon olarak çağırır (SetData, SetPreview, NotifyResult); olaylar
// Microsoft.Dynamics.NAV.InvokeExtensibilityMethod ile AL'ye gider.
type NavHost = { InvokeExtensibilityMethod?: (name: string, args: unknown[], skipIfBusy?: boolean, callback?: () => void) => void };

function nav(): NavHost | undefined {
  return (window as unknown as { Microsoft?: { Dynamics?: { NAV?: NavHost } } }).Microsoft?.Dynamics?.NAV;
}

export function inBusinessCentral(): boolean {
  return typeof nav()?.InvokeExtensibilityMethod === "function";
}

export function invoke(name: string, ...args: unknown[]): void {
  nav()?.InvokeExtensibilityMethod?.(name, args, false);
}

type Handlers = {
  SetData?: (json: string) => void;
  SetPreview?: (json: string) => void;
  NotifyResult?: (json: string) => void;
};

const handlers: Handlers = {};
const pending: { name: keyof Handlers; json: string }[] = [];

/** BC hazır olmadan gelen çağrılar React bağlanana kadar kuyrukta bekler. */
export function registerHandlers(next: Handlers): () => void {
  Object.assign(handlers, next);
  pending.splice(0).forEach(({ name, json }) => handlers[name]?.(json));
  return () => { (Object.keys(next) as (keyof Handlers)[]).forEach((k) => delete handlers[k]); };
}

for (const name of ["SetData", "SetPreview", "NotifyResult"] as const) {
  (window as unknown as Record<string, unknown>)[name] = (json: string) => {
    const h = handlers[name];
    if (h) h(json);
    else pending.push({ name, json });
  };
}
