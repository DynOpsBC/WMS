/// <reference types="vitest" />
// Göz ve LP Karşılaştırma control add-in paketi: tek IIFE js + tek css,
// doğrudan al/src/ControlAddIn/Resources/binLpCompare.js/.css içine.
// BC iframe'i ES modül/parça yükleyemez; bu yüzden lib + iife.
//   npx vite build --config vite.binLpCompare.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  publicDir: false,
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  build: {
    outDir: "../al/src/ControlAddIn/Resources",
    // Diğer add-in paketleri aynı klasörde: asla temizleme.
    emptyOutDir: false,
    sourcemap: false,
    cssCodeSplit: false,
    target: "es2019",
    lib: {
      entry: "src/binLpCompare/main.tsx",
      name: "DopsBinLpCompare",
      formats: ["iife"],
      fileName: () => "binLpCompare.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: (asset) =>
          asset.name?.endsWith(".css") ? "binLpCompare.css" : "binLpCompare-[name][extname]",
      },
    },
  },
  test: {
    include: ["src/binLpCompare/**/*.test.ts"],
  },
});
