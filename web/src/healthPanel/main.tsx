import { createRoot } from "react-dom/client";
import { HealthPanelApp } from "./HealthPanelApp";
import { installGlobals } from "./bridge";
import "./styles.css";

// BC kontrol eklentisi: tek IIFE. BC, eklenti iframe'inde #controlAddIn
// kabını oluşturur; yoksa (önizleme) body'ye bir kap eklenir.
type MountedWindow = Window & { __dopsHealthPanelMounted?: boolean };

function mount() {
  const w = window as MountedWindow;
  if (w.__dopsHealthPanelMounted) return;
  w.__dopsHealthPanelMounted = true;
  installGlobals();
  let host = document.getElementById("controlAddIn");
  if (!host) {
    host = document.createElement("div");
    host.id = "controlAddIn";
    document.body.appendChild(host);
  }
  host.classList.add("hp-host");
  createRoot(host).render(<HealthPanelApp />);
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
else mount();
