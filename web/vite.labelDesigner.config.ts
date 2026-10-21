// Etiket tasarımcısı (BC control add-in "DOPSWHS Label Designer") için tek
// dosyalık paket: IIFE labelDesigner.js + labelDesigner.css, dış kaynak yok.
// Yalnız bu iki dosyayı yazar; Resources klasöründeki diğer dosyalara dokunmaz.
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  publicDir: false,
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  build: {
    outDir: "../al/src/ControlAddIn/Resources/",
    emptyOutDir: false,
    copyPublicDir: false,
    sourcemap: false,
    cssCodeSplit: false,
    minify: "esbuild",
    target: "es2019",
    reportCompressedSize: true,
    lib: {
      entry: "src/labelDesigner/main.tsx",
      name: "DopsLabelDesigner",
      formats: ["iife"],
      fileName: () => "labelDesigner.js",
    },
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
        assetFileNames: (asset) => (asset.name?.endsWith(".css") ? "labelDesigner.css" : "labelDesigner-[name][extname]"),
      },
    },
  },
});
