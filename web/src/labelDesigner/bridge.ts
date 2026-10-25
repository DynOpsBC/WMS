// BC control add-in köprüsü ("DOPSWHS Label Designer").
// BC → JS: LoadDesign / ShowPreview / ShowMessage (global fonksiyonlar).
// JS → BC: Microsoft.Dynamics.NAV.InvokeExtensibilityMethod ile olaylar.
// React henüz dinlemiyorsa gelen çağrılar kuyrukta bekler.

export type MessageKind = "info" | "error" | "success";

export type IncomingMessage =
  | { type: "load"; json: string }
  | { type: "preview"; pngBase64: string }
  | { type: "message"; kind: MessageKind; text: string };

export type DesignerEvent =
  | "ControlReady"
  | "SaveRequested"
  | "TestPrintRequested"
  | "PreviewRequested"
  | "CompanyLogoRequested";

type NavHost = {
  InvokeExtensibilityMethod?: (name: string, args: unknown[], skipIfBusy?: boolean, callback?: () => void) => void;
};

type DesignerWindow = Window & {
  Microsoft?: { Dynamics?: { NAV?: NavHost } };
  LoadDesign?: (json: string) => void;
  ShowPreview?: (pngBase64: string) => void;
  ShowMessage?: (kind: string, message: string) => void;
};

type Listener = (message: IncomingMessage) => void;

const queue: IncomingMessage[] = [];
let listener: Listener | null = null;

function nav(): NavHost | undefined {
  return (window as DesignerWindow).Microsoft?.Dynamics?.NAV;
}

/** BC içinde mi (InvokeExtensibilityMethod var mı)? */
export function isInsideBc(): boolean {
  return typeof nav()?.InvokeExtensibilityMethod === "function";
}

function deliver(message: IncomingMessage) {
  if (listener) listener(message);
  else queue.push(message);
}

/** Tek dinleyici (App). Bekleyen çağrılar hemen teslim edilir. */
export function listen(next: Listener): () => void {
  listener = next;
  while (queue.length > 0 && listener) {
    const m = queue.shift();
    if (m) listener(m);
  }
  return () => {
    if (listener === next) listener = null;
  };
}

/** BC'nin çağırdığı prosedürleri global olarak tanımlar (script yüklenir yüklenmez). */
export function installProcedures(): void {
  const w = window as DesignerWindow;
  w.LoadDesign = (json: string) => deliver({ type: "load", json: String(json ?? "") });
  w.ShowPreview = (pngBase64: string) => deliver({ type: "preview", pngBase64: String(pngBase64 ?? "") });
  w.ShowMessage = (kind: string, message: string) => {
    const k: MessageKind = kind === "error" || kind === "success" ? kind : "info";
    deliver({ type: "message", kind: k, text: String(message ?? "") });
  };
}

/** Geliştirme modunda olayları dinlemek için (BC dışı). */
type DevHandler = (event: DesignerEvent, args: string[]) => void;
let devHandler: DevHandler | null = null;

export function setDevHandler(handler: DevHandler | null): void {
  devHandler = handler;
}

/** BC olayını tetikler; BC dışında geliştirme işleyicisine gider. */
export function raise(event: DesignerEvent, ...args: string[]): void {
  const host = nav();
  if (host?.InvokeExtensibilityMethod) {
    host.InvokeExtensibilityMethod(event, args, false);
    return;
  }
  // eslint-disable-next-line no-console
  console.info(`[Etiket Tasarımcısı] ${event}`, args.length ? `${args[0].length} karakter` : "");
  devHandler?.(event, args);
}

/** Geliştirme modunda BC yanıtını taklit eder (LoadDesign/ShowMessage/ShowPreview). */
export function simulateIncoming(message: IncomingMessage): void {
  deliver(message);
}
