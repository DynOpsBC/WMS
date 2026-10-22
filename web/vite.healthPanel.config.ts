/// <reference types="vitest" />
// Depo Sağlık Paneli (BC kontrol eklentisi "DOPSWHS Health Panel") — tek IIFE
// paket: al/src/ControlAddIn/Resources/healthPanel.js + healthPanel.css.
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
      entry: "src/healthPanel/main.tsx",
      name: "DopsHealthPanel",
      formats: ["iife"],
      fileName: () => "healthPanel.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: (asset) => (asset.name?.endsWith(".css") ? "healthPanel.css" : "healthPanel-[name][extname]"),
      },
    },
  },
  test: {
    include: ["src/healthPanel/**/*.{test,spec}.{ts,tsx}"],
  },
});
