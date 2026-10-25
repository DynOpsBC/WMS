// Giriş noktası. BC control add-in'i Scripts ve StartupScript olarak aynı
// dosyayı yükleyebilir: ikinci çalıştırma hiçbir şey yapmaz.
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { installProcedures } from "./bridge";
import "./styles.css";

type Flagged = Window & { __dopsLabelDesignerLoaded?: boolean };

function mount() {
  let host = document.getElementById("controlAddIn") ?? document.getElementById("root");
  if (!host) {
    host = document.createElement("div");
    host.id = "root";
    document.body.appendChild(host);
  }
  host.classList.add("ld-host");
  createRoot(host).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

const w = window as Flagged;
if (!w.__dopsLabelDesignerLoaded) {
  w.__dopsLabelDesignerLoaded = true;
  // Prosedürler hemen tanımlanır; React hazır olana kadar çağrılar kuyrukta bekler.
  installProcedures();
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount, { once: true });
  else mount();
}
