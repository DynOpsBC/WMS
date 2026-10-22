// Yalnız geliştirme önizlemesi (src/lpTrace/index.html): BC yokken AL'nin yerine
// örnek yükleri döndürür. BC paketi (main.tsx girişi) bu dosyayı içermez.
import { emptyTrace } from "./model";
import { sampleDocumentTrace, sampleLotTrace, sampleLpTrace } from "./sample";
import type { TracePayload } from "./types";

const samples: Record<string, TracePayload> = {
  LP001740: sampleLpTrace,
  A102511: sampleLotTrace,
  "AB.01740 A102511": sampleLotTrace,
  "109433": sampleDocumentTrace,
};

type HostApi = { SetData?: (json: string) => void };

window.addEventListener("lptrace:invoke", (event) => {
  const { name, args } = (event as CustomEvent<{ name: string; args: unknown[] }>).detail;
  const host = window as unknown as HostApi;
  if (name === "Search") {
    const query = String(args[0] ?? "");
    const payload = samples[query] ?? { ...emptyTrace(), mode: "notFound", query, generatedAt: new Date().toISOString() };
    window.setTimeout(() => host.SetData?.(JSON.stringify(payload)), 120);
  }
  if (name === "OpenNode") {
    (window as unknown as { __lpTraceOpened?: unknown[] }).__lpTraceOpened = [...((window as unknown as { __lpTraceOpened?: unknown[] }).__lpTraceOpened ?? []), args];
  }
});
