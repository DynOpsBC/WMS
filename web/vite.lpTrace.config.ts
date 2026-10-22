/// <reference types="vitest" />
// LP İzlenebilirlik (BC kontrol eklentisi "DOPSWHS LP Trace") — tek IIFE paket:
// al/src/ControlAddIn/Resources/lpTrace.js + lpTrace.css.
// emptyOutDir KAPALI: Resources klasöründeki diğer eklenti dosyaları silinmez.
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  publicDir: false,
  build: {
    outDir: "../al/src/ControlAddIn/Resources",
    emptyOutDir: false,
    copyPublicDir: false,
    sourcemap: false,
    cssCodeSplit: false,
    target: "es2019",
    lib: {
      entry: "src/lpTrace/main.tsx",
      name: "DopsLpTrace",
      formats: ["iife"],
      fileName: () => "lpTrace.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: (asset) => (asset.name?.endsWith(".css") ? "lpTrace.css" : "lpTrace-[name][extname]"),
      },
    },
  },
  test: {
    include: ["src/lpTrace/**/*.{test,spec}.{ts,tsx}"],
  },
});
