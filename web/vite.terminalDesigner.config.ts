/// <reference types="vitest" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Terminal Ekran Tasarımcısı → tek dosyalık BC denetim eklentisi paketi.
//   cd web && npx vite build --config vite.terminalDesigner.config.ts
// Çıktı: al/src/ControlAddIn/Resources/terminalDesigner.js + terminalDesigner.css
// IIFE (modül değil): BC StartupScript'i klasik <script> olarak yükler.
// emptyOutDir=false: aynı klasördeki diğer panellerin dosyalarına dokunmaz.
export default defineConfig({
  plugins: [react()],
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  build: {
    outDir: "../al/src/ControlAddIn/Resources/",
    emptyOutDir: false,
    sourcemap: false,
    cssCodeSplit: false,
    lib: {
      entry: "src/terminalDesigner/main.tsx",
      formats: ["iife"],
      name: "DopsTerminalDesigner",
      fileName: () => "terminalDesigner.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: (asset) => (asset.name?.endsWith(".css") ? "terminalDesigner.css" : "terminalDesigner-[name][extname]"),
      },
    },
  },
  test: {
    include: ["src/terminalDesigner/**/*.test.ts"],
  },
});
