import React from "react";
import { createRoot } from "react-dom/client";
import { TerminalDesignerApp } from "./TerminalDesignerApp";
import "./styles.css";

// BC denetim eklentisi iframe'inde kök #controlAddIn'dir; bağımsız önizlemede #root.
function mountPoint(): HTMLElement {
  const host = document.getElementById("controlAddIn") ?? document.getElementById("root") ?? document.body;
  const el = document.createElement("div");
  el.className = "td-root";
  host.appendChild(el);
  return el;
}

createRoot(mountPoint()).render(
  <React.StrictMode>
    <TerminalDesignerApp />
  </React.StrictMode>,
);
