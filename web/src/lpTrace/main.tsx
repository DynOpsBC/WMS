// LP İzlenebilirlik — BC kontrol eklentisi giriş noktası ("DOPSWHS LP Trace").
// Tek IIFE paketi: vite.lpTrace.config.ts → al/src/ControlAddIn/Resources/lpTrace.js/.css
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { installHostApi } from "./bridge";
import { LpTraceApp } from "./LpTraceApp";
import "./styles.css";

installHostApi();

function mountPoint(): HTMLElement {
  // BC eklenti iframe'i "controlAddIn" div'ini verir; yoksa (önizleme) kendimiz ekleriz.
  const existing = document.getElementById("controlAddIn") ?? document.getElementById("lp-trace-root");
  if (existing) return existing;
  const div = document.createElement("div");
  div.id = "lp-trace-root";
  document.body.appendChild(div);
  return div;
}

function start() {
  const host = mountPoint();
  host.classList.add("lt-host");
  createRoot(host).render(
    <StrictMode>
      <LpTraceApp />
    </StrictMode>,
  );
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
else start();
