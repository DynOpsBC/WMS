import React from "react";
import { createRoot } from "react-dom/client";

function App() {
  return (
    <main>
      <h1>BCWMS Workstation</h1>
    </main>
  );
}

const root = document.getElementById("root");

if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
}

