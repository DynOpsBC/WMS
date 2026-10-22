import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BinLpCompareApp } from "./BinLpCompareApp";
import { isInBc, pushLocalData, pushLocalNotice, setLocalHandler } from "./bridge";
import { localCompare, localReleaseOrphans, localRepairUndone } from "./sampleData";
import type { CompareFilter } from "./types";
import "./styles.css";

// BC aynı betiği iki kez yükleyebilir (Scripts + StartupScript); tek kez bağla.
const flag = "__dopsBinLpCompareMounted";
const w = window as unknown as Record<string, unknown>;

if (!w[flag]) {
  w[flag] = true;
  // BC iframe'i #controlAddIn kabını verir; geliştirme önizlemesinde #bin-lp-root.
  let host = document.getElementById("controlAddIn") ?? document.getElementById("bin-lp-root");
  if (!host) {
    host = document.createElement("div");
    document.body.appendChild(host);
  }
  host.classList.add("blc-host");
  document.documentElement.classList.add("blc-doc");

  if (!isInBc()) installLocalPreview();

  createRoot(host).render(
    <StrictMode>
      <BinLpCompareApp />
    </StrictMode>,
  );
}

/** BC dışı önizleme: BC olaylarını örnek veriyle yanıtlar. */
function installLocalPreview() {
  const params = new URLSearchParams(window.location.search);
  const parse = (json: unknown): Partial<CompareFilter> => {
    try {
      return JSON.parse(String(json)) as Partial<CompareFilter>;
    } catch {
      return {};
    }
  };
  let lastFilter: Partial<CompareFilter> = {
    location: params.get("state") === "empty" ? "" : "MERKEZ",
    onlyDiff: params.get("all") !== "1",
  };
  const later = (fn: () => void) => window.setTimeout(fn, 250);
  setLocalHandler((name, args) => {
    switch (name) {
      case "ControlReady":
        later(() => pushLocalData(localCompare(lastFilter)));
        break;
      case "Compare":
        lastFilter = parse(args[0]);
        later(() => pushLocalData(localCompare(lastFilter)));
        break;
      case "RepairUndoneReceipt": {
        lastFilter = parse(args[1]);
        const n = localRepairUndone(String(args[0]));
        later(() => {
          pushLocalNotice({ kind: "success", message: `${n} LP satırı boşaltıldı.` });
          pushLocalData(localCompare(lastFilter));
        });
        break;
      }
      case "ReleaseOrphans": {
        lastFilter = parse(args[1]);
        const n = localReleaseOrphans(String(args[0]));
        later(() => {
          pushLocalNotice({ kind: "success", message: `${n} LP serbest bırakıldı.` });
          pushLocalData(localCompare(lastFilter));
        });
        break;
      }
      case "ExportExcel":
        pushLocalNotice({ kind: "info", message: "BC içinde Excel dosyası indirilir (önizleme)." });
        break;
      default:
        pushLocalNotice({ kind: "info", message: `BC içinde açılır: ${name} ${args.filter(Boolean).join(" · ")}` });
    }
  });
}
